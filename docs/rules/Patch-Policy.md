# Patch Policy

## Source Split

| Source | Rule |
| --- | --- |
| Upstream code | Pin by release tag and commit SHA |
| Local changes | Carry as git-style patch files |
| Build truth | `patches/manifest.toml` + `flake.nix` |
| Candidate truth | `docs/backlog/Patch-Candidates.md` |
| Execution truth | `patches/manifest.toml` |

## Patch Rules

- One behavior change per patch file.
- Every enabled patch must declare:
  - `upstream_base`
  - `upstream_sha`
  - `upstream_issue` or `upstream_pr`
  - `risk`
  - `status`
- Patch file names must be stable:
  - `tui-notification-sound.patch`
  - `tui-status-line-command.patch`
- Patch application failure blocks release.
- Upstream merge retires the local patch in the next local release.
- Do not use GitHub Issues or GitHub Projects as patch state.

## Dependency Patches

A fix that belongs in a locked Cargo dependency, not in codex-rs, is a `[[dependency_patches]]` entry instead of a `[[patches]]` entry.

- Pin the dependency by its exact `Cargo.lock` `source` string, and declare `crate`, `upstream_issue` or `upstream_pr`, `risk`, and `status`.
- The build fails when the lock no longer pins that source; re-port the patch against the new source instead of loosening the pin.
- Generate the patch relative to the crate root, so it applies with `patch -p1` inside the crate directory.
- Nix patches the vendored copy in `postPatch`; CI and release builds run `scripts/ci/apply-dependency-patches.py`, which also discards Cargo's cached build of the crate.
- Never fork the dependency to carry the change.

## Versioning

| Case | Version |
| --- | --- |
| First patch release for upstream `0.132.0` | `0.132.0-patch.1` |
| Patch-only local update | `0.132.0-patch.2` |
| Upstream bump | `0.133.0-patch.1` |

## Rejection Rules

- Reject patches that require a long-lived fork.
- Reject patches that duplicate upstream runtime policy.
- Reject patches that hide security-relevant behavior.
- Prefer wrapper tooling over source patches for UI experiments outside Codex TUI.
