# AGENTS.md

Read [README.md](README.md) first for install, quick start, and the manual TUI check.
See the README's Layout table for what lives under `docs/`.

## Patch Policy

Follow [docs/rules/Patch-Policy.md](docs/rules/Patch-Policy.md): one behavior change per
patch file, every enabled patch pins `upstream_sha`, patch application failure blocks
release, reject anything that needs a long-lived fork.

## Editing or Regenerating a Patch

Full flow: [docs/guides/Patch-Porting.md](docs/guides/Patch-Porting.md).

Patches in `patches/*.patch` are cumulative, applied in manifest order. A later patch's
context can depend on an earlier one, so `nu scripts/refresh-patch.nu <name>` only
produces a correct single patch when exactly that one patch is applied to staging — it
naively diffs the whole tree, which silently absorbs every other enabled patch's changes
too once more than one is applied.

To edit or regenerate one patch correctly:

1. Fresh throwaway worktree at the manifest `upstream_sha`
   (`git -C staging/openai-codex worktree add ../../.worktrees/<name> <sha>` — never
   reuse the maintainer's own `staging/openai-codex` checkout).
2. Apply the patches before the target, in manifest order, and commit — this is the PRE
   reference.
3. Apply the target patch and make edits, `git add -A`, **do not commit** the
   target-applied state separately (committing it breaks step 4's diff base).
4. `git diff --binary --cached <PRE-commit>` is the regenerated patch.
5. Verify against a fresh checkout of PRE, not the worktree you just edited in: dry-run
   `patch -p2 -i` from `codex-rs/` (Nix applies with `patch -p2`, not `git apply`) and
   `git apply --check` (matches `apply-patches.nu`).

## What CI Actually Builds

`nix flake check` builds `codex-patched` with
`cargoBuildFlags = --package codex-cli --package codex-code-mode-host` and `doCheck`
empty — it runs **no tests**, for any crate, including `codex-tui`. A patch's own
bundled test can be permanently broken and CI will never catch it. `git apply --check`
passing does not mean the workspace compiles either: a patch that adds a field to an
existing struct must be re-checked against every construction site on the new upstream.

Always verify ALL enabled patches applied cumulatively, not just the one you touched —
`auto-release`'s `verify-patches-apply` stops at the first failure, so a reported
failure understates the real scope. See
[docs/guides/Release-Workflow.md](docs/guides/Release-Workflow.md) for release gates,
packaged binaries, and known CI failure modes.

## Verifying Without a Local Build

Prefer opening a branch/PR and letting CI's `nix flake check` do the real compile. When
a local check is unavoidable, the sandboxed Nix `cc` wrapper lacks the macOS SDK — force
system clang first:

```sh
export SDKROOT=$(xcrun --show-sdk-path)
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=/usr/bin/clang
```
