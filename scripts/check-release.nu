#!/usr/bin/env nu

def main [] {
  ^nu scripts/check-editable-enter-queue.nu

  let manifest = (open patches/manifest.toml)
  let enabled = ($manifest.patches | where enabled == true)

  for patch in $enabled {
    if ($patch.upstream_sha | is-empty) {
      error make { msg: $"enabled patch missing upstream_sha: ($patch.name)" }
    }
    if not ($patch.file | path exists) {
      error make { msg: $"enabled patch file missing: ($patch.file)" }
    }
  }

  ^nix flake check
}
