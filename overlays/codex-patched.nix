{
  patchManifest,
  patchRoot,
  patchSuffix,
}:
final: prev:
let
  lib = prev.lib;
  codexRustPlatform = final.makeRustPlatform {
    cargo = final.codex-rust-toolchain;
    rustc = final.codex-rust-toolchain;
  };
  enabledPatches = lib.filter (patch: patch.enabled or false) patchManifest.patches;
  patchPaths = map (patch: patchRoot + "/${patch.file}") enabledPatches;
  dependencyPatches = patchManifest.dependency_patches or [ ];
  # Vendored sources carry an empty checksum file list, so their files can be patched in place.
  applyDependencyPatch = patch: ''
    grep -qxF ${lib.escapeShellArg ''source = "${patch.source}"''} Cargo.lock \
      || { echo "${patch.name}: Cargo.lock no longer pins ${patch.source}" >&2; exit 1; }
    dependency_dirs=("$cargoDepsCopy"/source-git-*/${patch.crate}-[0-9]*/)
    [ "''${#dependency_dirs[@]}" -eq 1 ] && [ -d "''${dependency_dirs[0]}" ] \
      || { echo "${patch.name}: expected one vendored ${patch.crate} git source" >&2; exit 1; }
    patch -p1 --forward --batch -d "''${dependency_dirs[0]}" -i ${patchRoot + "/${patch.file}"}
  '';
  hasEditableEnterQueue = lib.any (
    patch: (patch.name or null) == "editable-enter-queue" && (patch.enabled or false)
  ) patchManifest.patches;
  upstream = lib.findFirst (
    patch: patch.enabled or false
  ) (lib.head patchManifest.patches) patchManifest.patches;
  upstreamVersion = lib.removePrefix "rust-v" upstream.upstream_base;
  upstreamSrc = final.fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = upstream.upstream_sha;
    hash = upstream.source_hash;
  };
in
{
  codex-rust-toolchain = final.rust-bin.stable.latest.default.override {
    extensions = [ "rust-src" ];
  };
  codex-patched = (prev.codex.override { rustPlatform = codexRustPlatform; }).overrideAttrs (
    old:
    let
      # Codex 0.147.0 enabled the sandbox pointer-compression feature for code
      # mode, and 0.164.0 moved to rusty_v8 152.2.0. Pin the matching artifacts
      # published with Codex independently of nixpkgs' bundled version.
      # When a future bump changes the resolved v8 crate, the stale binding
      # file fails compilation loudly; refresh rustyV8Version and the hashes
      # then.  Keep these targets aligned with .github/workflows/release.yml's
      # rusty_v8 staging step.
      rustyV8Version = "152.2.0";
      rustyV8Target = final.stdenv.hostPlatform.rust.rustcTarget;
      rustyV8Artifacts = {
        "aarch64-apple-darwin" = {
          archiveHash = "sha256-/qua4DhL66qZwdAAZURiydQhI9WHGFx4dqru99dv90k=";
          bindingHash = "sha256-udVlLrylFesr9MLuSmVRslZxF7Wqcg9DDSAyYW3X47U=";
        };
        "aarch64-unknown-linux-gnu" = {
          archiveHash = "sha256-EFRGSmIwBs314lriCHcAK/PtuaLC8+ZPRKhxR0KxXoc=";
          bindingHash = "sha256-Pk1f7Nvg+YpgF+adfKglGad/sDLF615M2+zdPi7FGdU=";
        };
        "aarch64-unknown-linux-musl" = {
          archiveHash = "sha256-GmDzaj3Yd4gC5pgGaMTWWjxzBdhaXS3r9GbZqg2q3XU=";
          bindingHash = "sha256-Pk1f7Nvg+YpgF+adfKglGad/sDLF615M2+zdPi7FGdU=";
        };
        "x86_64-apple-darwin" = {
          archiveHash = "sha256-v+Gdm2M7YdmXgOzolpBCf+9LmFxrQZZTbq+UVxFm/CQ=";
          bindingHash = "sha256-udVlLrylFesr9MLuSmVRslZxF7Wqcg9DDSAyYW3X47U=";
        };
        "x86_64-unknown-linux-gnu" = {
          archiveHash = "sha256-s7SQ8qqAntp/ascn+FH7AM6DVb5ygnV3z6rCjHE3280=";
          bindingHash = "sha256-Pk1f7Nvg+YpgF+adfKglGad/sDLF615M2+zdPi7FGdU=";
        };
        "x86_64-unknown-linux-musl" = {
          archiveHash = "sha256-LyZ5dzoSV23GuJsPfXDoGQ5a6opX+PY2Tvr/3RSX0Oc=";
          bindingHash = "sha256-Pk1f7Nvg+YpgF+adfKglGad/sDLF615M2+zdPi7FGdU=";
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
      packageMetadata = final.writeText "codex-package.json" (
        builtins.toJSON {
          layoutVersion = 1;
          version = upstreamVersion;
          target = final.stdenv.hostPlatform.rust.rustcTarget;
          variant = "codex";
          entrypoint = "bin/codex";
          resourcesDir = "codex-resources";
          pathDir = "codex-path";
        }
      );
    in
    {
      __intentionallyOverridingVersion = true;
      version = "${upstreamVersion}-${patchSuffix}";
      src = upstreamSrc;
      cargoDeps = codexRustPlatform.fetchCargoVendor {
        pname = "codex";
        version = upstreamVersion;
        src = upstreamSrc;
        sourceRoot = "${upstreamSrc.name}/codex-rs";
        # This patch adds existing libc and config dependencies to arg0's lock entry.
        # Vendor from the same lockfile that the application build validates.
        patches = lib.filter (path: baseNameOf path == "arg0-private-temp-home.patch") patchPaths;
        patchFlags = [ "-p2" ];
        hash = upstream.cargo_hash;
      };
      # Match release tarballs: the manifest owns patches for this upstream pin.
      patches = patchPaths;
      patchFlags = [ "-p2" ];
      cargoBuildFlags = (old.cargoBuildFlags or [ ]) ++ [
        "--package"
        "codex-responses-api-proxy"
      ];
      preVersionCheck = ''
        version=${upstreamVersion}
      '';
      postFixup = "";
      versionCheckKeepEnvironment = (old.versionCheckKeepEnvironment or [ ]) ++ [
        "CODEX_HOME"
        "TMPDIR"
      ];

      __structuredAttrs = false;
      env =
        (old.env or { })
        // lib.optionalAttrs (lib.versionAtLeast upstreamVersion "0.147.0") {
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
        ${lib.concatMapStrings applyDependencyPatch dependencyPatches}
        ${lib.optionalString hasEditableEnterQueue ''
          # Nix's patch hook cannot consume git binary diffs. Install the
          # generated app-server export payloads alongside the text patch.
          install -Dm644 ${patchRoot + "/patches/editable-enter-queue-app-server-exports-stable.json.zst"} \
            app-server-protocol/schema/precomputed/app-server-exports-stable.json.zst
          install -Dm644 ${
            patchRoot + "/patches/editable-enter-queue-app-server-exports-experimental.json.zst"
          } \
            app-server-protocol/schema/precomputed/app-server-exports-experimental.json.zst
        ''}
      '';

      preInstall = (old.preInstall or "") + ''
        # Completion generation and version checks create temporary PATH aliases.
        # Release builds require CODEX_HOME outside TMPDIR, so use sibling dirs.
        export CODEX_HOME="$NIX_BUILD_TOP/codex-install-home"
        export TMPDIR="$NIX_BUILD_TOP/codex-install-tmp"
        mkdir -p "$CODEX_HOME" "$TMPDIR"
      '';

      postInstall = (old.postInstall or "") + ''
        install -m644 ${packageMetadata} "$out/codex-package.json"
        mkdir -p "$out/codex-resources" "$out/codex-path"
        install -m755 ${lib.getExe final.ripgrep} "$out/codex-path/rg"
        ${lib.optionalString final.stdenv.hostPlatform.isLinux ''
          install -m755 ${lib.getExe final.bubblewrap} "$out/codex-resources/bwrap"
        ''}
        for binary in codex codex-responses-api-proxy codex-code-mode-host; do
          test -x "$out/bin/$binary"
        done
      '';

      passthru = (old.passthru or { }) // {
        patchManifest = patchManifest;
        patchNames = map (patch: patch.name) enabledPatches;
        dependencyPatchNames = map (patch: patch.name) dependencyPatches;
      };
    }
  );
}
