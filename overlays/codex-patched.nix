{
  patchManifest,
  patchRoot,
  patchSuffix,
}:
final: prev:
let
  lib = prev.lib;
  enabledPatches = lib.filter (patch: patch.enabled or false) patchManifest.patches;
  patchPaths = map (patch: patchRoot + "/${patch.file}") enabledPatches;
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
  codex-patched = prev.codex.overrideAttrs (
    old:
    let
      # Codex 0.147.0 moved to rusty_v8 150.4.0 and enabled the sandbox
      # pointer-compression feature for code mode. Pin the matching artifacts
      # published with Codex independently of nixpkgs' bundled version.
      # When a future bump changes the resolved v8 crate, the stale binding
      # file fails compilation loudly; refresh rustyV8Version and the hashes
      # then.  Keep these targets aligned with .github/workflows/release.yml's
      # rusty_v8 staging step.
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
      # Match scripts/codex_package/codex-zsh from the pinned upstream source.
      # The Linux archive names say musl, but the helper depends on glibc/tinfo.
      zshArtifacts = {
        aarch64-darwin = {
          target = "aarch64-apple-darwin";
          sha256 = "49dec9832379688c9090666694a3449502ac5ebd4d76b9ffde1d0999cd088205";
        };
        x86_64-darwin = {
          target = "x86_64-apple-darwin";
          sha256 = "0246fd4703bb540ae74f13ec739ca365ebd607df44a1f21e335eb7a421352923";
        };
        aarch64-linux = {
          target = "aarch64-unknown-linux-musl";
          sha256 = "8d50cff5dfabc97e37e1138513da022d9247a802c2ff996ab91654bf1892c7d5";
        };
        x86_64-linux = {
          target = "x86_64-unknown-linux-musl";
          sha256 = "e7f760998c9644448d2cb8a821084a0134d6820c14b284bd7f39d7f32262ad40";
        };
      };
      zshArtifact = zshArtifacts.${final.stdenv.hostPlatform.system};
      zshArchive = final.fetchurl {
        url = "https://github.com/openai/codex/releases/download/rust-v0.134.0-alpha.3/codex-zsh-${zshArtifact.target}.tar.gz";
        inherit (zshArtifact) sha256;
      };
      linuxZshRuntime = final.stdenv.mkDerivation {
        pname = "codex-zsh";
        version = "0.134.0-alpha.3";
        src = zshArchive;
        nativeBuildInputs = [ final.autoPatchelfHook ];
        buildInputs = [ final.ncurses ];
        dontConfigure = true;
        dontBuild = true;
        dontStrip = true;
        installPhase = ''
          runHook preInstall
          install -Dm755 bin/zsh "$out/bin/zsh"
          runHook postInstall
        '';
        doInstallCheck = final.stdenv.buildPlatform.canExecute final.stdenv.hostPlatform;
        installCheckPhase = ''
          runHook preInstallCheck
          "$out/bin/zsh" --version
          runHook postInstallCheck
        '';
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
      cargoDeps = final.rustPlatform.fetchCargoVendor {
        pname = "codex";
        version = upstreamVersion;
        src = upstreamSrc;
        sourceRoot = "${upstreamSrc.name}/codex-rs";
        hash = upstream.cargo_hash;
      };
      patches = (old.patches or [ ]) ++ patchPaths;
      patchFlags = [ "-p2" ];
      cargoBuildFlags = (old.cargoBuildFlags or [ ]) ++ [
        "--package"
        "codex-responses-api-proxy"
      ];
      preVersionCheck = ''
        version=${upstreamVersion}
      '';
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
        mkdir -p "$out/codex-resources/zsh" "$out/codex-path"
        ${
          if final.stdenv.hostPlatform.isLinux then
            ''
              mkdir -p "$out/codex-resources/zsh/bin"
              ln -s ${linuxZshRuntime}/bin/zsh "$out/codex-resources/zsh/bin/zsh"
            ''
          else
            ''
              tar -xzf ${zshArchive} --strip-components=1 -C "$out/codex-resources/zsh" codex-zsh/bin/zsh
              chmod 0755 "$out/codex-resources/zsh/bin/zsh"
            ''
        }
        ln -s ${lib.getExe final.ripgrep} "$out/codex-path/rg"
        ${lib.optionalString final.stdenv.hostPlatform.isLinux ''
          ln -s ${lib.getExe final.bubblewrap} "$out/codex-resources/bwrap"
        ''}
        for binary in codex codex-responses-api-proxy codex-code-mode-host; do
          test -x "$out/bin/$binary"
        done
      '';

      passthru = (old.passthru or { }) // {
        patchManifest = patchManifest;
        patchNames = map (patch: patch.name) enabledPatches;
      };
    }
  );
}
