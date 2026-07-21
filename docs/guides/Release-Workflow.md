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

## Manual Prerelease

`gh release create <tag> --prerelease --target <sha>`, then
`gh workflow run release.yml --ref main -f tag=<tag>`. Requires
`RELEASE_PUSH_TOKEN` (see below) — the default `GITHUB_TOKEN` can create a
release on a tag push but cannot update one that already exists
(`403 Resource not accessible by integration`). `isPrerelease=true` keeps
`latest-release` from moving.

## `RELEASE_PUSH_TOKEN`

Read by `auto-release.yml` (commit/tag/dispatch) and `release.yml`'s publish
step, falling back to `github.token` when unset.

Fine-grained PAT requirements, repo-scoped to `codex-patch-overlay`:

| Permission | Level | Used for |
| --- | --- | --- |
| Contents | Read and write | commit, tag, push, create/update release, upload assets |
| Workflows | Read and write | `gh workflow run` dispatch; also required for release **update** (`Contents` alone 403s with `Resource not accessible by personal access token`) |

Classic PAT with `repo` scope covers both and is the simpler fallback.

## Known CI Failure Modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| Build: `could not find native static library rusty_v8` | `Swatinem/rust-cache` full-matches on an unchanged `Cargo.lock` (e.g. a patch.N+1 re-release) and restores `v8`'s build-script output, whose baked linker path only the fresh build populates | `release.yml` stages the archive at `$GITHUB_WORKSPACE/.rusty_v8` (run-stable) and runs `cargo clean -p v8` after cache restore, forcing `v8` to rebuild every run |
| `nix flake check` fails on `checks.<system>.latest-release-ref`: `no matches found` | `flake.nix` pins the build jobs' `Swatinem/rust-cache` key to `${{ matrix.target }}` via a `yq` assertion — do not change it to bust a cache | bust a poisoned cache with `gh cache delete <id>` instead of changing the key |
| `publish`: `403 Resource not accessible by integration` | `GITHUB_TOKEN` cannot update a release that already exists (only create one on tag push) | pass `token: ${{ secrets.RELEASE_PUSH_TOKEN \|\| github.token }}` to `action-gh-release` |
| `publish`: `403 Resource not accessible by personal access token` | fine-grained PAT has `Contents: write` but not `Workflows: write` | add `Workflows: write` to the PAT |
