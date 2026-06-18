{
  description = "Local patch overlay for OpenAI Codex";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = { self, nixpkgs, systems }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
      manifest = builtins.fromTOML (builtins.readFile ./patches/manifest.toml);
      patchSuffix = manifest.release.patch_suffix;
      overlay = import ./overlays/codex-patched.nix {
        patchManifest = manifest;
        patchRoot = ./.;
        inherit patchSuffix;
      };
    in
    {
      overlays.default = overlay;

      packages = eachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          default = pkgs.codex-patched;
          codex-patched = pkgs.codex-patched;
        });

      checks = eachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          codex-patched = pkgs.codex-patched;
          manifest = pkgs.runCommand "codex-patch-manifest-check" { } ''
            test -f ${./patches/manifest.toml}
            ${pkgs.yq-go}/bin/yq -o=json ${./patches/manifest.toml} > /dev/null
            touch $out
          '';
          latest-release-ref = pkgs.runCommand "codex-latest-release-ref-check" { } ''
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

            ${pkgs.yq-go}/bin/yq -e '.jobs.publish.steps[] | select(.uses == "actions/checkout@v4").with."persist-credentials" == true' ${./.github/workflows/release.yml} > /dev/null
            ${pkgs.yq-go}/bin/yq -e '.jobs.publish.steps[] | select(.name == "Move latest release ref").run | contains("scripts/move-latest-release-ref.nu")' ${./.github/workflows/release.yml} > /dev/null
            touch $out
          '';
          auto-release = pkgs.runCommand "codex-auto-release-check" { } ''
            ${pkgs.nushell}/bin/nu --no-config-file -c '
              source ${./scripts/auto-release.nu}

              if ((release-patch-suffix "rust-v0.140.0" "rust-v0.141.0" "patch.3") != "patch.1") {
                error make { msg: "upstream bumps should reset to patch.1" }
              }

              if ((release-patch-suffix "rust-v0.141.0" "rust-v0.141.0" "patch.3") != "patch.3") {
                error make { msg: "same-upstream releases should keep the manifest patch suffix" }
              }
            '
            touch $out
          '';
        });

      devShells = eachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.git
              pkgs.gh
              pkgs.jq
              pkgs.nushell
              pkgs.ripgrep
            ];
          };
        });
    };
}
