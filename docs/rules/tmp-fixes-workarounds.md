# Temporary Workarounds

## Nix installer build-user range

Linux CI selects an unused contiguous system UID range before running the upstream Nix installer.
The installer's default starting UID of 30001 exceeds Ubuntu's `SYS_UID_MAX`, causing `useradd` warnings.
The shared install action checks the host's configured range and occupied accounts, then supplies `NIX_FIRST_BUILD_UID`; it retains the upstream multi-user daemon and dedicated builder accounts.
Remove this selection when the upstream installer chooses a compatible free range itself.

## macOS compact unwind table

The macOS release job selects Apple's classic linker while the default linker reports that Codex's `__eh_frame` section exceeds the 16 MiB compact-unwind offset limit.
This matches the verified local linker configuration and preserves unwind metadata.
Remove the selection when the default Apple linker builds the complete release binaries without this warning.

## OpenSSL installation metadata

The musl release build applies the two CI-only patches under `scripts/ci/` to the pinned OpenSSL installer and its `mkinstallvars.pl` helper.
OpenSSL 3.6.4's generated build/install commands omit optional path and comment fields, causing Perl to report missing and uninitialized values.
The helper patch makes those defaults explicit and formats optional undefined values as empty text; replaying both commands produces byte-identical metadata while retaining diagnostics for missing required fields.
The archive checksum and OpenSSL library sources remain unchanged.
Remove both patches when the pinned upstream installer generates this metadata without the diagnostics.

## Accepted dependency warning for 0.157.0

The maintainer explicitly waived Rust 1.98's future-compatibility warning for `proc-macro-error2 2.0.1` for the 0.157.0 releases.
The dependency arrives through `age 0.11.2` and `i18n-embed-fl 0.9.4`.
Keep the upstream dependency versions for this port; reconsider the waiver on the next upstream bump.
This exception applies only to this known warning.

## Stable Rust compatibility

Carry the Rust 1.99 compatibility hunks in `rust-toolchain-stable` while upstream uses deprecated `Atomic::fetch_update` calls or diverging error macros in expression position.
Use the renamed `try_update` calls and invoke error macros as statements; neither change alters runtime behavior.
Remove these hunks when upstream incorporates equivalent changes.

## TUI snapshot timing

Carry `tui-snapshot-stability` while the affected reconnect, disconnect, guardian, hook, and exec-flow fixtures render real-time status timers and spinner phases.
Tokio's paused clock does not freeze the renderer's `std::time::Instant`.
The patch fixes fixture timer origins and normalizes the activity spinner without changing runtime behavior or golden snapshots.
This includes the offline draft and the working status restored after guardian approval.
Remove it when upstream makes these fixtures deterministic.

## Integration-test import cleanup

Carry `core-test-unused-import` while upstream's integration suites retain unused `body_json` or `ReasoningEffort` imports.
Remove it when upstream removes or uses those imports.

## Shell-snapshot error formatting

Carry `core-test-error-format` while shell-snapshot tests compare `anyhow::Error` Debug output to a bare message.
CI enables `RUST_BACKTRACE=1`, which adds a stack trace to that output.
The patch compares the complete Display error chain and separately checks that Debug output excludes the fixture credential.
Descendant cleanup assertions remain unchanged.
Remove it when upstream makes these assertions independent of backtrace settings.
