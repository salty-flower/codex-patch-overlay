# AGENTS.md

Read [README.md](README.md) first for install, quick start, and the manual TUI check.
See the README's Layout table for what lives under `docs/`.

## Patch Policy

Follow [docs/rules/Patch-Policy.md](docs/rules/Patch-Policy.md): one behavior change per
patch file, every enabled patch pins `upstream_sha`, patch application failure blocks
release, reject anything that needs a long-lived fork.

## Editing or Regenerating a Patch

Follow [docs/guides/Patch-Porting.md](docs/guides/Patch-Porting.md). Patches are
cumulative and applied in manifest order — `nu scripts/refresh-patch.nu <name>` only
produces a correct single patch when exactly that one patch is applied to staging; with
the full enabled set applied (the normal state), it silently absorbs every other
patch's changes too. The guide has the PRE/TARGET worktree procedure that avoids this.

## Release and CI

Follow [docs/guides/Release-Workflow.md](docs/guides/Release-Workflow.md) for release
gates, packaged binaries, and known CI failure modes. `nix flake check` runs `doCheck`
empty, so it builds `codex-patched` but runs **no tests** for any crate — a patch's own
bundled test can be broken and this gate will never catch it. Always verify ALL enabled
patches applied cumulatively, not just the one you touched.
