#!/usr/bin/env nu

def main [
  --stage: string = "staging/openai-codex"
] {
  if not ($stage | path exists) {
    error make { msg: $"missing staging checkout: ($stage)" }
  }

  let manifest = (open patches/manifest.toml)
  let enabled = ($manifest.patches | where enabled == true)

  for patch in $enabled {
    let file = $patch.file
    print $"applying ($patch.name): ($file)"
    ^git -C $stage apply --check $"../../($file)"
    ^git -C $stage apply $"../../($file)"
  }

  ^git -C $stage status --short
}
