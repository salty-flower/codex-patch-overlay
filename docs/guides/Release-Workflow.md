# Release Workflow

## Release Gate

| Gate | Required |
| --- | --- |
| Manifest check | Enabled patches have SHA and patch file |
| Build check | `nix flake check` |
| Patch check | `nu scripts/check-release.nu` |
| Tracking check | Carried patches are recorded in `patches/manifest.toml` |

## Release Steps

1. Set `release.patch_suffix` in `patches/manifest.toml`.
2. Confirm enabled patch list.
3. Run `nu scripts/check-release.nu`.
4. Tag release as `codex-<upstream-version>-<patch-suffix>`.
5. Push the tag; `.github/workflows/release.yml` builds and publishes GitHub
   Release artifacts.
6. Publish release notes from manifest entries.
7. Move the `latest-release` branch to the released commit after GitHub Release
   publication succeeds.

## Auto Release

`.github/workflows/auto-release.yml` polls official `openai/codex` releases every
six hours. The workflow ignores prereleases and only considers stable
`rust-vX.Y.Z` tags.

When a newer upstream release exists, `scripts/auto-release.nu`:

1. Checks whether the patched GitHub Release already exists. If only its tag
   exists, dispatches the release build again to recover from an interrupted
   build.
2. Checks out the upstream tag and verifies enabled patches with
   `git apply --check`.
3. Updates enabled manifest entries to the new upstream tag, commit SHA, source
   hash, and Cargo vendor hash.
4. Runs `nix flake check`.
5. Commits the manifest and release record, tags
   `codex-<upstream-version>-patch.1`, pushes it, and dispatches the release
   build workflow.
6. Lets the release workflow move `latest-release` after artifacts are
   published. The move script refuses to move the ref backward if an older
   release job finishes after a newer one.

If patch application or `nix flake check` fails, no tag or GitHub Release is
created. Patch state remains in `patches/manifest.toml` and the docs tree, not
GitHub Issues or Projects.

Consumers that want the newest published patch release can use:

```nix
inputs.codex-patch-overlay.url = "github:salty-flower/codex-patch-overlay/latest-release";
```
