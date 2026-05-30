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
  - `stream-reasoning-live.patch`
  - `symlinked-skills.patch`
- Patch application failure blocks release.
- Upstream merge retires the local patch in the next local release.
- Do not use GitHub Issues or GitHub Projects as patch state.

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
