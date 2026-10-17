{
  description = "Local patch overlay for OpenAI Codex";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      systems,
    }:
    let
      # nixpkgs 26.11 dropped Intel macOS; do not advertise unevaluable outputs.
      eachSystem = nixpkgs.lib.genAttrs (
        builtins.filter (system: system != "x86_64-darwin") (import systems)
      );
      manifest = builtins.fromTOML (builtins.readFile ./patches/manifest.toml);
      patchSuffix = manifest.release.patch_suffix;
      overlay = nixpkgs.lib.composeManyExtensions [
        rust-overlay.overlays.default
        (import ./overlays/codex-patched.nix {
          patchManifest = manifest;
          patchRoot = ./.;
          inherit patchSuffix;
        })
      ];
    in
    {
      overlays.default = overlay;

      packages = eachSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          default = pkgs.codex-patched;
          codex-patched = pkgs.codex-patched;
          rust-toolchain = pkgs.codex-rust-toolchain;
        }
      );

      checks = eachSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          codex-patched = pkgs.codex-patched;
          package-layout =
            pkgs.runCommand "codex-package-layout-check"
              {
                nativeBuildInputs = [
                  pkgs.fd
                  pkgs.coreutils
                  pkgs.jq
                  pkgs.procps
                ];
              }
              ''
                package=${pkgs.codex-patched}
                while IFS= read -r -d "" link; do
                  resolved="$(realpath "$link")"
                  case "$resolved" in
                    "$package"/*) test ! -d "$link" ;;
                    *) echo "package link escapes its root: $link" >&2; exit 1 ;;
                  esac
                done < <(fd --hidden --no-ignore --type symlink --print0 . "$package")
                test -d "$package/codex-resources"
                for helper in codex-path/rg ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux "codex-resources/bwrap"}; do
                  test -f "$package/$helper"
                  test -x "$package/$helper"
                  test ! -L "$package/$helper"
                  "$package/$helper" --version
                done
                export CODEX_HOME="$NIX_BUILD_TOP/codex-home"
                export TMPDIR="$NIX_BUILD_TOP/codex-tmp"
                unset CODEX_SQLITE_HOME
                mkdir -p "$CODEX_HOME/app-server-daemon" "$TMPDIR"
                printf '%s\n' '{"updater":{"autoUpdateEnabled":false},"shutdownGraceSeconds":0}' > "$CODEX_HOME/app-server-daemon/settings.json"
                trap '"$package/bin/codex" app-server daemon stop' EXIT
                "$package/bin/codex" app-server daemon start
                "$package/bin/codex" app-server daemon version > daemon-version.json
                jq -e '.status == "running" and .appServerVersion == .cliVersion and .managedCodexVersion == .cliVersion' daemon-version.json
                "$package/bin/codex" app-server daemon stop
                trap - EXIT
                touch "$out"
              '';
          manifest = pkgs.runCommand "codex-patch-manifest-check" { } ''
            test -f ${./patches/manifest.toml}
            ${pkgs.yq-go}/bin/yq -o=json ${./patches/manifest.toml} > /dev/null
            touch $out
          '';
          latest-release-ref =
            pkgs.runCommand "codex-latest-release-ref-check"
              {
                nativeBuildInputs = [
                  pkgs.git
                  pkgs.nushell
                ];
              }
              ''
                ${pkgs.nushell}/bin/nu --no-config-file -c '
                  source ${./scripts/move-latest-release-ref.nu}

                  if ((compare-release-tags "codex-0.138.0-patch.1" "codex-0.137.0-patch.1") <= 0) {
                    error make { msg: "newer upstream version should compare greater" }
                  }

                  if ((compare-release-tags "codex-0.137.0-patch.2" "codex-0.137.0-patch.1") <= 0) {
                    error make { msg: "newer patch release should compare greater" }
                  }

                  if not (should-move-latest-release-ref "codex-0.137.0-patch.1" "") {
                    error make { msg: "latest release ref should be created when absent" }
                  }

                  if (should-move-latest-release-ref "codex-0.136.0-patch.1" "codex-0.137.0-patch.1") {
                    error make { msg: "older release should not move latest release ref backward" }
                  }
                '

                nu --no-config-file ${./scripts/test-move-latest-release-ref.nu} ${./scripts/move-latest-release-ref.nu}

                ${pkgs.yq-go}/bin/yq -e '.jobs.publish.steps[] | select(.uses == "actions/checkout@v7").with."persist-credentials" == true' ${./.github/workflows/release.yml} > /dev/null
                ${pkgs.yq-go}/bin/yq -e '.jobs.publish.steps[] | select(.name == "Move latest release ref").run | contains("scripts/move-latest-release-ref.nu")' ${./.github/workflows/release.yml} > /dev/null
                ${pkgs.yq-go}/bin/yq -e '.jobs.build."timeout-minutes" >= 120' ${./.github/workflows/release.yml} > /dev/null
                ${pkgs.yq-go}/bin/yq -e '.jobs.build.steps[] | select(.uses == "Swatinem/rust-cache@v2").with.key == "''${{ matrix.target }}"' ${./.github/workflows/release.yml} > /dev/null
                touch $out
              '';
          # Codex resolves helper executables next to its own binary at runtime
          # and never fetches a missing one, so a release that forgets a --bin
          # target ships a silently degraded package: from upstream 0.147.0 a
          # missing codex-code-mode-host makes code mode fail closed.
          release-binaries = pkgs.runCommand "codex-release-binaries-check" { } ''
            workflow=${./.github/workflows/release.yml}
            build_run="$(${pkgs.yq-go}/bin/yq -r '.jobs.build.steps[] | select(.name == "Build release binaries").run' "$workflow")"
            rg_run="$(${pkgs.yq-go}/bin/yq -r '.jobs.build.steps[] | select(.name == "Fetch packaged ripgrep").run' "$workflow")"
            schema_run="$(${pkgs.yq-go}/bin/yq -r '.jobs.build.steps[] | select(.name == "Install carried schema payloads").run' "$workflow")"
            package_run="$(${pkgs.yq-go}/bin/yq -r '.jobs.build.steps[] | select(.name == "Package artifact").run' "$workflow")"
            printf '%s' "$schema_run" | ${pkgs.ripgrep}/bin/rg -qF -- 'for kind in stable experimental; do' \
              || { echo "release.yml does not install both carried schema payloads" >&2; exit 1; }
            printf '%s' "$schema_run" | ${pkgs.ripgrep}/bin/rg -qF -- 'cp "patches/editable-enter-queue-app-server-exports-''${kind}.json.zst"' \
              || { echo "release.yml does not copy the carried schema payloads" >&2; exit 1; }
            printf '%s' "$schema_run" | ${pkgs.ripgrep}/bin/rg -qF -- '"staging/openai-codex/codex-rs/app-server-protocol/schema/precomputed/app-server-exports-''${kind}.json.zst"' \
              || { echo "release.yml does not install the schemas at their embedded source paths" >&2; exit 1; }
            printf '%s' "$rg_run" | ${pkgs.ripgrep}/bin/rg -qF -- 'from codex_package.ripgrep import fetch_rg' \
              || { echo "release.yml does not fetch ripgrep through upstream's verified DotSlash helper" >&2; exit 1; }
            printf '%s' "$rg_run" | ${pkgs.ripgrep}/bin/rg -qF -- 'fetch_rg(TARGET_SPECS[os.environ["TARGET"]])' \
              || { echo "release.yml does not select ripgrep for the matrix target" >&2; exit 1; }
            printf '%s' "$package_run" | ${pkgs.ripgrep}/bin/rg -qF -- '"$CODEX_RG_BIN" "$package_dir/codex-path/rg"' \
              || { echo "release.yml package step does not ship ripgrep at codex-path/rg" >&2; exit 1; }
            printf '%s' "$package_run" | ${pkgs.ripgrep}/bin/rg -qF -- 'chmod 0755 "$package_dir/codex-path/rg"' \
              || { echo "release.yml package step does not mark codex-path/rg executable" >&2; exit 1; }
            printf '%s' "$package_run" | ${pkgs.ripgrep}/bin/rg -qF -- 'mkdir -p "$package_dir/bin" "$package_dir/codex-resources" "$package_dir/codex-path"' \
              || { echo "release.yml package step does not create every required package directory" >&2; exit 1; }
            printf '%s' "$package_run" | ${pkgs.ripgrep}/bin/rg -qF -- 'validate_package_dir(' \
              || { echo "release.yml does not validate its package layout" >&2; exit 1; }
            printf '%s' "$package_run" | ${pkgs.ripgrep}/bin/rg -qF -- '--arg version "''${upstream_base#rust-v}" --arg target "$TARGET"' \
              || { echo "release.yml does not record the upstream version and target" >&2; exit 1; }
            for binary in codex codex-responses-api-proxy codex-code-mode-host; do
              printf '%s' "$build_run" | ${pkgs.ripgrep}/bin/rg -qF -- "--bin $binary" \
                || { echo "release.yml build step does not build $binary" >&2; exit 1; }
              printf '%s' "$package_run" | ${pkgs.ripgrep}/bin/rg -qF -- "$binary" \
                || { echo "release.yml package step does not ship $binary" >&2; exit 1; }
            done
            printf '%s' "$package_run" | ${pkgs.ripgrep}/bin/rg -qF -- '$package_dir/bin/' \
              || { echo "release.yml package step does not populate bin/" >&2; exit 1; }
            touch $out
          '';
          auto-release =
            pkgs.runCommand "codex-auto-release-check" { nativeBuildInputs = [ pkgs.nushell ]; }
              ''
                # Copy the whole directory so the test can `use` its sibling lib/ module.
                nu --no-config-file ${./scripts}/test-auto-release.nu
                touch $out
              '';
        }
      );

      devShells = eachSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.git
              pkgs.gh
              pkgs.jq
              pkgs.nushell
              pkgs.ripgrep
              pkgs.codex-rust-toolchain
              # For `cargo check` of the staged upstream tree.
              pkgs.pkg-config
              pkgs.openssl
            ];
          };
        }
      );
    };
}
