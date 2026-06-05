# Codex Patch Overlay

Local Nix overlay for carrying small OpenAI Codex patches without maintaining a long-lived fork.

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

`stream-reasoning-live` renders reasoning summaries that the API returns. If the
model returns only encrypted reasoning content, Codex can preserve it for the
next request but cannot render it as text.

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
