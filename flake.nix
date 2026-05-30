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
