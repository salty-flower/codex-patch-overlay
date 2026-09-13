# Codex Rotate account-transition review fixes

## Account ownership

Upstream: `rust-v0.154.0` (`6b9826e3aa83b1a5947db50f4332cb9c65f1b340`).

| Trigger | Required behavior |
| --- | --- |
| Helper selection changes after a model request produces a tool call | The spawned tool handler retains that model step's account. |
| Selection changes while plugin installation waits for approval | Plugin metadata and completion inventory use the original account; the next model step may select the new account. |
| Bedrock API key or AWS access keys are saved successfully | Clear the active Rotate authority before reloading credentials and reporting login success. |

Tool dispatch now enters `scope_request_auth` inside the spawned handler task.
The existing request-bound MCP auth manager carries that snapshot into MCP background tasks.
Bedrock login clears the external authority only after credential persistence succeeds.

## Verification boundary

The plugin-install regression uses synthetic A/B/C accounts and local HTTP/MCP fixtures.
It changes selection between the model response and tool dispatch, then again during approval.
It checks plugin-detail access, completion inventory ownership, the next model request's account,
and execution of the MCP refresh path.
MCP bearer ownership is covered separately by the existing trusted-runtime Rotate test;
the local plugin-install fixture does not assert MCP authorization headers.

Bedrock tests exercise the public app-server login and account-read RPCs with synthetic credentials,
including both API keys and AWS access keys, and assert that the helper is no longer consulted.
No real AWS or Bedrock account was available.
AWS credential validity, request signing, service access, and actual Bedrock inference remain untested.

The existing `editable-enter-queue` patch also needed three test-fixture updates to compile
against this upstream version: one `acceptance_order` initializer and two tuple destructurings.
Those changes are carried in that patch and do not change queue behavior.

## Local checks

Commands run from the cumulatively patched upstream workspace:

```sh
cargo check --locked --offline -p codex-core --tests
cargo check --locked --offline -p codex-app-server --tests
just fix -p codex-core -p codex-app-server --locked --offline
cargo fmt -p codex-core -p codex-app-server -- --check
just test -p codex-core -p codex-app-server -p codex-login --lib --test all \
  -E 'test(rotate) | test(request_plugin_install) | test(session::input_queue) | test(session::turn_input_tests) | test(tools::parallel) | test(tools::registry) | (package(codex-app-server) & test(bedrock))'
```

These scoped checks pass.
The nextest selection runs 112 tests, all passing.
The three affected queue recall tests also pass when selected by their actual
`session::turn_input::tests` names (`recall_before_drain_removes_steer_and_is_idempotent`,
`drain_before_recall_claims_steer_exactly_once`, and
`recall_rejects_turn_mismatch_without_touching_pending_input`).
Plugin-discovery tests require `cargo build -p codex-rmcp-client --bin test_stdio_server` first.
Local compilation used Rust 1.97.1 and the locked dependency versions;
the temporary lockfile only normalized upstream workspace package versions from `0.0.0` to `0.154.0`.
This lockfile adjustment is excluded from the patches.
The unchanged dependency `proc-macro-error2` 2.0.1 reports a future Rust incompatibility
for its private `proc_macro` re-export; dependency updates are outside this fix.
The plugin-install regression fails with the handler-scope fix removed and passes with it restored.
The workspace-wide `just fmt-check` reports pre-existing formatting differences in
`tui/src/app/input.rs` and `tui/src/bottom_pane/chat_composer.rs` from earlier patches.
Those unrelated formatting changes are excluded from this fix.
The stable rustfmt warning about `imports_granularity` is explicitly allowed by upstream's `rustfmt.toml`.

All seven enabled patches pass cumulative `patch -p2 --dry-run` and `git apply --check`
from the pinned upstream SHA, without offsets or fuzz.
After application and installation of the two schema payloads, the source matches the tested worktree.
Manifest, queue-contract, `git diff --check`, and `prek` checks pass.

`nix flake check --offline --no-build` passes evaluation on `x86_64-linux`.
The full Nix build gate remains unverified: fetching base dependencies fails with TLS EOF errors,
including `bash53-002` from `ftpmirror.gnu.org`, before Codex compilation starts.
No release artifact was built or published by this fix.
