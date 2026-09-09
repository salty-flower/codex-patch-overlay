#!/usr/bin/env nu

# Fast, local, network-free manifest lint: every field docs/rules/Patch-Policy.md
# declares required for an enabled patch, plus that its file actually exists.
# Safe for pre-commit; does not clone upstream or invoke cargo/nix.

def main [] {
  let manifest = (open patches/manifest.toml)
  let enabled = ($manifest.patches | where enabled == true)

  for patch in $enabled {
    let name = $patch.name

    if ($patch.upstream_base? | is-empty) {
      error make { msg: $"enabled patch missing upstream_base: ($name)" }
    }
    if ($patch.upstream_sha? | is-empty) {
      error make { msg: $"enabled patch missing upstream_sha: ($name)" }
    }
    if ($patch.upstream_issue? | is-empty) and ($patch.upstream_pr? | is-empty) {
      error make { msg: $"enabled patch missing upstream_issue or upstream_pr: ($name)" }
    }
    if ($patch.risk? | is-empty) {
      error make { msg: $"enabled patch missing risk: ($name)" }
    }
    if ($patch.status? | is-empty) {
      error make { msg: $"enabled patch missing status: ($name)" }
    }
    if not ($patch.file | path exists) {
      error make { msg: $"enabled patch file missing: ($patch.file)" }
    }
  }
}
