# Codex Patch Overlay

Local Nix overlay for carrying small OpenAI Codex patches without maintaining a long-lived fork.

Each release carries community-requested features that upstream `openai/codex` hasn't
merged yet — currently a task-completion notification sound, configurable default
collaboration mode, strict timed CLI queueing, and an opt-in dynamic TUI status-line
command, recallable same-turn Enter submissions, and bounded WebSocket recovery after
silent connection loss or suspend/resume — and ships them as ready-to-run
binaries plus a Nix overlay,
refreshed on every upstream Codex release.
See `patches/manifest.toml` for the
exact patch stack.

## Install a patched build

Prebuilt binaries are attached to every [release](https://github.com/salty-flower/codex-patch-overlay/releases)
for macOS (`aarch64-apple-darwin`) and Linux (`x86_64-unknown-linux-musl`), each with a
`.sha256` checksum. No Nix required:

```sh
tag=codex-0.157.0-patch.1
target=aarch64-apple-darwin   # or x86_64-unknown-linux-musl
base=https://github.com/salty-flower/codex-patch-overlay/releases/download/$tag
curl -fsSL -O "$base/$tag-$target.tar.gz"
curl -fsSL -O "$base/$tag-$target.tar.gz.sha256"
shasum -a 256 -c "$tag-$target.tar.gz.sha256"
tar xzf "$tag-$target.tar.gz"
"./$tag-$target/bin/codex" --version
```

Or consume the Nix overlay, which always tracks the latest patch release:

```nix
inputs.codex-patch-overlay.url = "github:salty-flower/codex-patch-overlay/latest-release";
```

## Personal account switching

Account switching is opt-in through `codex_rotate_helper`.
The `codex-rotate` helper is a separate dependency, included in neither the release tarballs nor this Nix overlay.
Its maintained source currently lives in the private machine-state repository; obtain access or supply a compatible version-1 helper separately.
With access to a machine-state checkout, build its exported `codex-rotate` flake package on `aarch64-darwin` or `x86_64-linux`:

```sh
nix build /absolute/path/to/machine-state#codex-rotate
```

Create a helper settings file, for example `/absolute/path/codex-rotate.json`:

```json
{"state_dir": "/absolute/path/codex-rotate-state", "automatic": false}
```

Add this top-level key to your Codex `config.toml`, using the installed helper's absolute executable path:

```toml
codex_rotate_helper = ["/absolute/path/bin/codex-rotate", "--config", "/absolute/path/codex-rotate.json", "rpc"]
```

Run the patched `codex login` or `codex login --device-auth` to enroll and select a fresh account directly through the helper.
Only personal Free, Go, Plus, Pro and ProLite accounts are supported; managed, Business, Enterprise, Edu and unknown account contexts are rejected.
To import an existing `auth.json`, first stop every native or proxy process that can refresh those credentials, and keep those old refresh writers stopped:

```sh
/absolute/path/bin/codex-rotate --config /absolute/path/codex-rotate.json import --writers-stopped --select /absolute/path/auth.json
```

Use the helper's `list` command to inspect profiles and `switch <account-key-or-unique-label>` to select the account for subsequent model steps.
Automatic quota-based selection is a helper setting, disabled by default with `automatic: false`.
The helper's `enable` command opts in; automatic selection stays dormant until at least two profiles are enabled.
The helper's `disable` command only pauses automatic selection; it does not remove the configured credential authority.
Pass the same `--config /absolute/path/codex-rotate.json` to these helper commands.

Bedrock credential transitions have local RPC coverage only; real AWS authentication and inference remain untested.
See the [account-transition verification record](docs/records/2026-09-13-codex-rotate-review-fixes.md) for the tested boundaries.

## Contract

- **Upstream source**: `openai/codex` release tag or commit.
- **Patch format**: git-style `.patch` files under `patches/`.
- **Patch metadata**: `patches/manifest.toml`.
- **Versioning**: `<upstream-version>-patch.<patch-release>`.
- **Tracking**: `patches/manifest.toml` for carried patches, `docs/backlog/` for candidates.

## Quick Start

```sh
nix flake check
nu scripts/stage-upstream.nu
nu scripts/apply-patches.nu
```

To consume the latest published patch release from another flake, point the
input at the moving `latest-release` ref:

```nix
inputs.codex-patch-overlay.url = "github:salty-flower/codex-patch-overlay/latest-release";
```

## Manual TUI Check

```sh
cd staging/openai-codex/codex-rs
cargo run -p codex-cli --bin codex -- --no-alt-screen -c model_reasoning_summary=detailed
```

Use `/later <delay> <prompt>` to queue a prompt for a future time.
The default collaboration mode and status-line command are opt-in TUI settings:

```toml
[tui]
default_collaboration_mode = "plan"

[tui.status_line_command]
command = ["/path/to/status-line-helper"]
refresh_interval_ms = 1000
```

## Layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Build patched Codex packages and checks |
| `overlays/codex-patched.nix` | Nix overlay that applies enabled manifest patches |
| `patches/manifest.toml` | Patch source of truth for build and CI |
| `patches/*.patch` | Git-style patch files |
| `scripts/*.nu` | Staging, apply, refresh, and release checks |
| `docs/rules/` | Durable patch policies |
| `docs/guides/` | Operational workflows |
| `docs/backlog/` | Candidate patch summaries |
| `docs/research/` | Community feature surveys and design notes |
| `docs/records/` | Completed audits and archived snapshots |
