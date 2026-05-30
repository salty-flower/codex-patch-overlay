{ patchManifest, patchRoot, patchSuffix }:
final: prev:
let
  lib = prev.lib;
  enabledPatches = lib.filter (patch: patch.enabled or false) patchManifest.patches;
  patchPaths = map (patch: patchRoot + "/${patch.file}") enabledPatches;
  upstream = lib.findFirst (patch: patch.enabled or false) (lib.head patchManifest.patches) patchManifest.patches;
  upstreamVersion = lib.removePrefix "rust-v" upstream.upstream_base;
  upstreamSrc = final.fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = upstream.upstream_sha;
    hash = upstream.source_hash;
  };
in
{
  codex-patched = prev.codex.overrideAttrs (old: {
    __intentionallyOverridingVersion = true;
    version = "${upstreamVersion}-${patchSuffix}";
    src = upstreamSrc;
    cargoDeps = final.rustPlatform.fetchCargoVendor {
      pname = "codex";
      version = upstreamVersion;
      src = upstreamSrc;
      sourceRoot = "${upstreamSrc.name}/codex-rs";
      hash = upstream.cargo_hash;
    };
    patches = (old.patches or [ ]) ++ patchPaths;
    patchFlags = [ "-p2" ];
    preVersionCheck = ''
      version=${upstreamVersion}
    '';

    passthru = (old.passthru or { }) // {
      patchManifest = patchManifest;
      patchNames = map (patch: patch.name) enabledPatches;
    };
  });
}
