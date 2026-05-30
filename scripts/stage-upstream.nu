#!/usr/bin/env nu

def main [
  --ref: string = ""
  --repo: string = ""
] {
  let manifest = (open patches/manifest.toml)
  let upstream_repo = (if ($repo | is-empty) { $manifest.release.upstream_repo } else { $repo })
  let upstream_ref = (if ($ref | is-empty) {
    let enabled = ($manifest.patches | where enabled == true)
    if (($enabled | length) > 0) {
      $enabled.0.upstream_base
    } else {
      $manifest.patches.0.upstream_base
    }
  } else {
    $ref
  })
  let target = "staging/openai-codex"
  mkdir staging

  if not ($target | path exists) {
    ^git clone $"https://github.com/($upstream_repo).git" $target
  }

  ^git -C $target fetch --tags --prune origin
  ^git -C $target checkout $upstream_ref
  ^git -C $target status --short
}
