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
| WebP image input | `openai/codex#8562`, `openai/codex#8589` | low | carried |
| Transcript search | `openai/codex#8641` | high | candidate |
| Symlinked skills | `openai/codex#8370` | — | **retired**: Rust `fs::read_dir` follows symlinks by default; already works |
| Directory @ selection | `openai/codex#8960` | — | **retired**: implemented upstream in #19068 (2026-05-11) |
| `codex delete <session>` | `openai/codex#8784` | low | carried |
| Disable autocompact | `openai/codex#4106` | low | carried |
| Respect proxy env vars | `openai/codex#4242` | low | candidate |
| Sensitive file exclusion `.codexignore` | `openai/codex#2847` | medium | candidate |

## Promotion Rule

- Candidate accepted for carry -> add or enable `patches/manifest.toml` entry.
- Candidate rejected -> remove from this file or move rationale to `docs/records/`.
- Upstream merge -> remove from this file and retire any manifest entry.
