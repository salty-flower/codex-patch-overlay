{ patchManifest, patchRoot, patchSuffix }:
final: prev:
let
  lib = prev.lib;
  enabledPatches = lib.filter (patch: patch.enabled or false) patchManifest.patches;
  patchPaths = map (patch: patchRoot + "/${patch.file}") enabledPatches;
  hasEditableEnterQueue = lib.any (
    patch: (patch.name or null) == "editable-enter-queue" && (patch.enabled or false)
  ) patchManifest.patches;
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
  codex-patched = prev.codex.overrideAttrs (old:
    let
      # Codex 0.147.0 moved to rusty_v8 150.4.0 and enabled the sandbox
      # pointer-compression feature for code mode.  nixpkgs still provides the
      # older 146.4.0 archive, so use the matching artifacts published with
      # the Codex releases instead.  0.148.0 retains the same v8 release.
      # Keep these targets aligned with
      # .github/workflows/release.yml's rusty_v8 staging step.
      rustyV8Version = "150.4.0";
      rustyV8Target = final.stdenv.hostPlatform.rust.rustcTarget;
      rustyV8Artifacts = {
        "aarch64-apple-darwin" = {
          archiveHash = "sha256-AK27SHmISMd1UEQcaGc6XoUpuOG3PqvN7iMss5tA9KE=";
          bindingHash = "sha256-ylrfDPicmnCtRgrnNkiy/om3SqETs8t/dXtqArdYOU8=";
        };
        "aarch64-unknown-linux-gnu" = {
          archiveHash = "sha256-0VF+7UBUaFNwKbAF1f6ZfsdNXI01H5FrOm3yC30oEbo=";
          bindingHash = "sha256-dyeCauR5vbZF6Acjn7EtH44uI956bPFvXuWSaQ0dhQY=";
        };
        "aarch64-unknown-linux-musl" = {
          archiveHash = "sha256-0ljv2cF7ZwdwE/EQMC/xSP0RQozEgE/LXJrQXj5jTLQ=";
          bindingHash = "sha256-dyeCauR5vbZF6Acjn7EtH44uI956bPFvXuWSaQ0dhQY=";
        };
        "x86_64-apple-darwin" = {
          archiveHash = "sha256-4Nm7ZOizoDTCkwyDly8/NXYCERSDQvoEB7OCUO8zCFY=";
          bindingHash = "sha256-ylrfDPicmnCtRgrnNkiy/om3SqETs8t/dXtqArdYOU8=";
        };
        "x86_64-unknown-linux-gnu" = {
          archiveHash = "sha256-o1x10fJuapg4haRbM0kKTr5U8FBQVosyuJz7QhswtYM=";
          bindingHash = "sha256-dyeCauR5vbZF6Acjn7EtH44uI956bPFvXuWSaQ0dhQY=";
        };
        "x86_64-unknown-linux-musl" = {
          archiveHash = "sha256-0G4IvL9FqQz+rIpNMixyiHdcteNgnKcD6jErFVF05Go=";
          bindingHash = "sha256-dyeCauR5vbZF6Acjn7EtH44uI956bPFvXuWSaQ0dhQY=";
        };
      };
      rustyV8Artifact = rustyV8Artifacts.${rustyV8Target};
      rustyV8Base = "https://github.com/openai/codex/releases/download/rusty-v8-v${rustyV8Version}";
      rustyV8Archive = final.fetchurl {
        name = "librusty_v8_ptrcomp_sandbox_release_${rustyV8Target}.a.gz";
        url = "${rustyV8Base}/librusty_v8_ptrcomp_sandbox_release_${rustyV8Target}.a.gz";
        hash = rustyV8Artifact.archiveHash;
      };
      rustyV8Binding = final.fetchurl {
        name = "src_binding_ptrcomp_sandbox_release_${rustyV8Target}.rs";
        url = "${rustyV8Base}/src_binding_ptrcomp_sandbox_release_${rustyV8Target}.rs";
        hash = rustyV8Artifact.bindingHash;
      };
    in
    {
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
      env = (old.env or { }) // lib.optionalAttrs (lib.elem upstreamVersion [ "0.147.0" "0.148.0" ]) {
        RUSTY_V8_ARCHIVE = rustyV8Archive;
        RUSTY_V8_SRC_BINDING_PATH = rustyV8Binding;
      };
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
        ${lib.optionalString hasEditableEnterQueue ''
          # Nix's patch hook cannot consume git binary diffs. Install the
          # generated app-server export payloads alongside the text patch.
          install -Dm644 ${patchRoot}/patches/editable-enter-queue-app-server-exports-stable.json.zst \
            app-server-protocol/schema/precomputed/app-server-exports-stable.json.zst
          install -Dm644 ${patchRoot}/patches/editable-enter-queue-app-server-exports-experimental.json.zst \
            app-server-protocol/schema/precomputed/app-server-exports-experimental.json.zst
        ''}
      '';

      passthru = (old.passthru or { }) // {
        patchManifest = patchManifest;
        patchNames = map (patch: patch.name) enabledPatches;
      };
    });
}
