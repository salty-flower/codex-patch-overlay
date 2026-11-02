#!/usr/bin/env bash
set -euo pipefail

upstream="$(cd "$1" && pwd)"
repo="$(cd "$2" && pwd)"
check="$3"
check_installed="$4"
list_binaries="$5"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/codex-package-contract-test.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/upstream/scripts" "$fixture/upstream/codex-rs/exec-server-cli"
cp -R "$upstream/scripts/codex_package" "$fixture/upstream/scripts/"
chmod -R u+w "$fixture/upstream/scripts/codex_package"
cp "$upstream/codex-rs/exec-server-cli/Cargo.toml" "$fixture/upstream/codex-rs/exec-server-cli/"

cat >> "$fixture/upstream/scripts/codex_package/cargo.py" <<'PY'

import functools

_original_source_binaries_for_target = source_binaries_for_target

@functools.wraps(_original_source_binaries_for_target)
def source_binaries_for_target(*args, **kwargs):
    return [*_original_source_binaries_for_target(*args, **kwargs), "codex-future-helper"]
PY
if bash "$check" "$fixture/upstream" "$repo" > "$fixture/binary.log" 2>&1; then
  echo 'Missing upstream binary did not fail the contract check' >&2
  exit 1
fi
grep -Fq 'Release workflow does not build upstream binary: codex-future-helper' "$fixture/binary.log"
echo 'PASS: new upstream build target is detected'

# Model the release workflow being updated while the Nix package is still stale.
mkdir -p "$fixture/repo/.github/workflows" "$fixture/repo/patches" "$fixture/repo/scripts/ci"
cp "$repo/.github/workflows/release.yml" "$fixture/repo/.github/workflows/"
cp "$repo/patches/manifest.toml" "$fixture/repo/patches/"
cp "$repo/README.md" "$repo/LICENSE" "$repo/NOTICE" "$fixture/repo/"
cp "$list_binaries" "$fixture/repo/scripts/ci/list-upstream-binaries.sh"
perl -pi -e 's/extra_bins\+=\(--bin codex-exec-server\)/extra_bins+=(--bin codex-exec-server --bin codex-future-helper)/; s/binaries\+=\(codex-exec-server\)/binaries+=(codex-exec-server codex-future-helper)/' "$fixture/repo/.github/workflows/release.yml"
bash "$check" "$fixture/upstream" "$fixture/repo" > "$fixture/release-updated.log" 2>&1

mkdir -p "$fixture/package/bin" "$fixture/package/codex-resources"
printf '#!%s\nexit 0\n' "$(command -v bash)" > "$fixture/stub"
chmod +x "$fixture/stub"
for binary in codex codex-code-mode-host codex-exec-server; do
  cp "$fixture/stub" "$fixture/package/bin/$binary"
done
cp "$fixture/stub" "$fixture/package/codex-resources/bwrap"
if bash "$check_installed" "$fixture/upstream" x86_64-unknown-linux-gnu "$fixture/package" "$list_binaries" > "$fixture/installed.log" 2>&1; then
  echo 'Missing upstream binary in Nix package did not fail the check' >&2
  exit 1
fi
grep -Fq 'Nix package does not include upstream binary: codex-future-helper' "$fixture/installed.log"
cp "$fixture/stub" "$fixture/package/bin/codex-future-helper"
bash "$check_installed" "$fixture/upstream" x86_64-unknown-linux-gnu "$fixture/package" "$list_binaries"
echo 'PASS: new upstream binary is required in the Nix package'

cp "$upstream/scripts/codex_package/cargo.py" "$fixture/upstream/scripts/codex_package/cargo.py"
cat >> "$fixture/upstream/scripts/codex_package/layout.py" <<'PY'

_original_validate_package_dir = validate_package_dir

def validate_package_dir(package_dir, variant, spec):
    _original_validate_package_dir(package_dir, variant, spec)
    raise RuntimeError("synthetic new upstream package requirement")
PY
if bash "$check" "$fixture/upstream" "$repo" > "$fixture/layout.log" 2>&1; then
  echo 'New upstream package requirement did not fail the contract check' >&2
  exit 1
fi
grep -Fq 'synthetic new upstream package requirement' "$fixture/layout.log"
echo 'PASS: new upstream package requirement is detected'
