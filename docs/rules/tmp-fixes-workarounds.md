# Temporary Workarounds

## Rust compiler query depth

Carry `chatgpt-recursion-limit` while Rust 1.98 exceeds the default query-depth limit compiling `codex-chatgpt` with the enabled patches.
The compiler reports a depth increase of 130 for `connectors::list_connectors`; the patch raises the crate limit from 128 to 256 without changing runtime behavior.
Remove it when upstream raises the limit or the cumulative patch stack compiles on stable Rust with the default limit.

## Accepted dependency warning for 0.157.0

The maintainer explicitly waived Rust 1.98's future-compatibility warning for `proc-macro-error2 2.0.1` for the 0.157.0 releases.
The dependency arrives through `age 0.11.2` and `i18n-embed-fl 0.9.4`.
Keep the upstream dependency versions for this port; reconsider the waiver on the next upstream bump.
This exception applies only to this known warning.

## TUI snapshot timing

Carry `tui-snapshot-stability` while the affected reconnect, guardian, hook, and exec-flow fixtures render real-time status timers and spinner phases.
Tokio's paused clock does not freeze the renderer's `std::time::Instant`.
The patch fixes fixture timer origins and normalizes the activity spinner without changing runtime behavior or golden snapshots.
Remove it when upstream makes these fixtures deterministic.

## Integration-test import cleanup

Carry `core-test-unused-import` while upstream's `openai_file_mcp` suite imports `wiremock::matchers::body_json` without using it.
Remove it when upstream removes or uses that import.

## Shell-snapshot error formatting

Carry `core-test-error-format` while shell-snapshot tests compare `anyhow::Error` Debug output to a bare message.
CI enables `RUST_BACKTRACE=1`, which adds a stack trace to that output.
The patch compares the complete Display error chain and separately checks that Debug output excludes the fixture credential.
Descendant cleanup assertions remain unchanged.
Remove it when upstream makes these assertions independent of backtrace settings.
