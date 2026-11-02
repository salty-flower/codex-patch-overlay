#!/usr/bin/env bash
# Exercise the release workflow's actual build and package steps without compiling.
set -euo pipefail

upstream="$(cd "$1" && pwd)"
repo="$(cd "${2:-.}" && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/codex-package-contract.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT

build_step="$(yq -r '.jobs.build.steps[] | select(.name == "Build release binaries").run' "$repo/.github/workflows/release.yml")"
bwrap_step="$(yq -r '.jobs.build.steps[] | select(.name == "Build bwrap and export digest").run' "$repo/.github/workflows/release.yml")"
package_step="$(yq -r '.jobs.build.steps[] | select(.name == "Package artifact").run' "$repo/.github/workflows/release.yml")"
test -n "$build_step" && test "$build_step" != null
test -n "$bwrap_step" && test "$bwrap_step" != null
test -n "$package_step" && test "$package_step" != null

for target in x86_64-unknown-linux-musl aarch64-apple-darwin; do
  root="$fixture/$target"
  staged="$root/staging/openai-codex"
  mkdir -p "$root/bin" "$root/patches" "$root/runner" "$staged/scripts" "$staged/codex-rs"
  cp -R "$upstream/scripts/codex_package" "$staged/scripts/"
  chmod -R u+w "$staged/scripts/codex_package"
  if [[ -f "$upstream/codex-rs/exec-server-cli/Cargo.toml" ]]; then
    mkdir -p "$staged/codex-rs/exec-server-cli"
    cp "$upstream/codex-rs/exec-server-cli/Cargo.toml" "$staged/codex-rs/exec-server-cli/"
  fi
  cp "$repo/patches/manifest.toml" "$root/patches/manifest.toml"
  cp "$repo/README.md" "$repo/LICENSE" "$repo/NOTICE" "$root/"
  printf '#!%s\n' "$(command -v bash)" > "$root/bin/stub-executable"
  cat >> "$root/bin/stub-executable" <<'EOF'
printf 'package contract fixture\n'
EOF
  chmod +x "$root/bin/stub-executable"
  printf '#!%s\n' "$(command -v bash)" > "$root/bin/cargo"
  cat >> "$root/bin/cargo" <<'EOF'
set -euo pipefail
while (($#)); do
  if [[ "$1" == --bin ]]; then
    test "$#" -ge 2
    mkdir -p "target/$TARGET/release"
    cp "$STUB_EXECUTABLE" "target/$TARGET/release/$2"
    shift 2
  else
    shift
  fi
done
EOF
  chmod +x "$root/bin/cargo"
  export TARGET="$target" RELEASE_TAG=codex-package-contract
  export GITHUB_WORKSPACE="$root" RUNNER_TEMP="$root/runner"
  export GITHUB_ENV="$root/github-env"
  export CODEX_RG_BIN="$root/bin/stub-executable" STUB_EXECUTABLE="$root/bin/stub-executable"
  export PATH="$root/bin:$PATH"
  (cd "$staged/codex-rs" && bash -euo pipefail -c "$build_step")
  if [[ "$target" == *-linux-* ]]; then
    (cd "$staged/codex-rs" && bash -euo pipefail -c "$bwrap_step")
  fi
  bash "$repo/scripts/ci/list-upstream-binaries.sh" "$staged" "$target" > "$root/upstream-binaries"
  while IFS= read -r binary; do
    if [[ ! -x "$staged/codex-rs/target/$target/release/$binary" ]]; then
      echo "Release workflow does not build upstream binary: $binary ($target)" >&2
      exit 1
    fi
  done < "$root/upstream-binaries"
  (cd "$root" && bash -euo pipefail -c "$package_step")
  while IFS= read -r binary; do
    package_dir="$root/dist/$RELEASE_TAG-$target"
    if [[ ! -x "$package_dir/bin/$binary" && ! -x "$package_dir/codex-resources/$binary" ]]; then
      echo "Release workflow does not package upstream binary: $binary ($target)" >&2
      exit 1
    fi
  done < "$root/upstream-binaries"
  echo "Upstream package contract passed for $target"
done
