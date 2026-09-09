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

## Regenerating One Patch Mid-Stack

Patches in `patches/*.patch` are cumulative, applied in manifest order — a later
patch's context can depend on an earlier one. `nu scripts/refresh-patch.nu <name>`
does a naive `git diff` of the whole staging tree, so it only yields a correct single
patch when exactly that one patch is applied. With the full enabled set applied (the
normal state after `apply-patches.nu`), it silently absorbs every other enabled
patch's changes too.

To edit or regenerate one patch correctly instead:

1. Fresh throwaway worktree at the manifest `upstream_sha`
   (`git -C staging/openai-codex worktree add ../../.worktrees/<name> <sha>` — never
   reuse the maintainer's own `staging/openai-codex` checkout).
2. Apply the patches before the target, in manifest order, and commit — this is the
   PRE reference.
3. Apply the target patch and make edits, `git add -A`, **do not commit** the
   target-applied state separately (committing it breaks step 4's diff base).
4. `git diff --binary --cached <PRE-commit>` is the regenerated patch.
5. Verify against a fresh checkout of PRE, not the worktree you just edited in:
   dry-run `patch -p2 -i` from `codex-rs/` (Nix applies with `patch -p2`, not
   `git apply`) and `git apply --check` (matches `apply-patches.nu`).

When a local build of the verification step is unavoidable, the sandboxed Nix `cc`
wrapper lacks the macOS SDK — force system clang first:

```sh
export SDKROOT=$(xcrun --show-sdk-path)
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
export CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER=/usr/bin/clang
```
