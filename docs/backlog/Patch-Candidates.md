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
| Respect proxy env vars | `openai/codex#4242` | — | **deferred**: see notes |
| Sensitive file exclusion `.codexignore` | `openai/codex#2847`, `openai/codex#6530` | — | **retired**: implemented upstream as model-level enforcement (prompt injection via `<codex-ignore>` context fragment); not sandbox-level deny-read — model *can* still read excluded files. #2847 (open) wants deterministic exclusion; #6530 (closed) reported it wasn't being respected. Files: `codexignore_instructions.rs`, `agents_md.rs::load_codexignore()` |
| Token usage breakdown | `openai/codex#13222` | low | carried |
| Default Plan mode | `openai/codex#13942` | low | carried |

## Research Notes

### Respect proxy env vars (`openai/codex#4242`)

**Deferred** — not a simple patch. Research findings at `rust-v0.137.0`:

1. **HTTP (reqwest) clients already respect `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`**. All production reqwest client construction flows through `build_reqwest_client_with_custom_ca()`, which does NOT call `.no_proxy()`. The only `.no_proxy()` call is inside the seatbelt sandbox (`CODEX_SANDBOX=seatbelt`), which is correct behavior. This covers: API calls, compact endpoint, memories, login flows, exec-server HTTP tool, cloud-tasks, etc.

2. **WebSocket connections (tungstenite) do NOT respect proxy env vars**. The Responses-over-WebSocket transport in `codex-api/src/endpoint/responses_websocket.rs` uses `tokio-tungstenite::connect_async_tls_with_config()` directly, bypassing reqwest entirely. Fixing this would require implementing a CONNECT proxy tunnel (detect proxy from env, establish HTTP CONNECT tunnel, perform TLS handshake through it) — a significant and risky change.

3. **Upstream already addressed this post-0.137.0**. Commits like "Add macOS system proxy resolver" (`b532a823`), "Add Windows system proxy resolver", and "Add shared auth system proxy contract" landed in the 0.138.0-alpha series, indicating upstream is handling proxy support comprehensively. Our patch base will inherit this when rebased.

**Recommendation**: Rebase to a release that includes the upstream system proxy support rather than carrying a local websocket-only CONNECT proxy patch. If HTTP-only proxy is sufficient for a specific use case, no patch is needed — it already works.

## Promotion Rule

- Candidate accepted for carry -> add or enable `patches/manifest.toml` entry.
- Candidate rejected -> remove from this file or move rationale to `docs/records/`.
- Upstream merge -> remove from this file and retire any manifest entry.
