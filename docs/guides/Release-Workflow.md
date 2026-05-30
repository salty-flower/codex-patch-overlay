# Release Workflow

## Release Gate

| Gate | Required |
| --- | --- |
| Manifest check | Enabled patches have SHA and patch file |
| Build check | `nix flake check` |
| Patch check | `nu scripts/check-release.nu` |
| Tracking check | Carried patches have GitHub issues |

## Release Steps

1. Set `release.patch_suffix` in `patches/manifest.toml`.
2. Confirm enabled patch list.
3. Run `nu scripts/check-release.nu`.
4. Tag release as `codex-<upstream-version>-<patch-suffix>`.
5. Publish release notes from manifest entries.
