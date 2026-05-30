# Patch Porting

## Flow

| Step | Command |
| --- | --- |
| Stage upstream | `nu scripts/stage-upstream.nu --ref rust-v0.135.0` |
| Apply enabled patches | `nu scripts/apply-patches.nu` |
| Edit staged source | `staging/openai-codex/` |
| Refresh patch | `nu scripts/refresh-patch.nu <patch-name>` |
| Verify release | `nu scripts/check-release.nu` |

## Porting Rules

- Keep patch scope smaller than the upstream PR when possible.
- Prefer current upstream architecture over exact historical patch replay.
- Refresh one patch at a time.
- Update `upstream_sha` after successful port.
- Move abandoned candidates to `docs/records/`.
