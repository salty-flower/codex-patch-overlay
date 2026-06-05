# Patch Candidates

## Candidate Classes

| Class | Policy |
| --- | --- |
| Small UX patch | Eligible for local carry |
| Automation metadata | Eligible for local carry |
| Protocol or session lifecycle | Needs research first |
| Large cross-surface feature | Track upstream, do not carry |

## Initial Candidates

| Patch | Upstream | Risk | Status |
| --- | --- | --- | --- |
| Stream reasoning live | `openai/codex#5339`, `openai/codex#6006` | medium | carried |
| TUI notification sound | `openai/codex#8417` | low | carried |
| WebP image input | `openai/codex#8589` | low | candidate |
| Transcript search | `openai/codex#8641` | high | candidate |

## Promotion Rule

- Candidate accepted for carry -> add or enable `patches/manifest.toml` entry.
- Candidate rejected -> remove from this file or move rationale to `docs/records/`.
- Upstream merge -> remove from this file and retire any manifest entry.
