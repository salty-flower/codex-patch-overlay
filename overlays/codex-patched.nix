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

    __structuredAttrs = false;
    postPatch = ''
      # webrtc-sys asks rustc to link libwebrtc statically by default,
      # but nixpkgs provides libwebrtc as a shared library.
      # use LK_CUSTOM_WEBRTC to point to the packaged library and adjust linking
      # to use the shared library instead.
      # Upstream dropped the webrtc-sys dependency in rust-v0.145.0, so the glob
      # can match nothing; substituteInPlace hard-errors when given no files
      # ("called without any files to operate on"). Guard it so the overlay works
      # whether or not the vendored crate is present.
      for webrtc_build_rs in $cargoDepsCopy/*/webrtc-sys-*/build.rs; do
        [ -e "$webrtc_build_rs" ] || continue
        substituteInPlace "$webrtc_build_rs" \
          --replace-fail "cargo:rustc-link-lib=static=webrtc" "cargo:rustc-link-lib=dylib=webrtc"
      done
      substituteInPlace Cargo.toml \
        --replace-fail 'lto = "thin"' "" \
        --replace-fail 'codegen-units = 4' ""
    '';

    passthru = (old.passthru or { }) // {
      patchManifest = patchManifest;
      patchNames = map (patch: patch.name) enabledPatches;
    };
  });
}
