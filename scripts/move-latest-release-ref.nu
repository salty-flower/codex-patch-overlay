#!/usr/bin/env nu

const LATEST_RELEASE_REF = "refs/heads/latest-release"

def fail [message: string] {
  error make { msg: $message }
}

def env-var [name: string] {
  let matches = ($env | transpose key value | where key == $name)
  if (($matches | length) == 0) {
    ""
  } else {
    $matches.0.value
  }
}

def release-version-parts [tag: string] {
  let matches = ($tag | parse -r '^codex-(?P<major>[0-9]+)\.(?P<minor>[0-9]+)\.(?P<patch>[0-9]+)-patch\.(?P<patch_release>[0-9]+)$')
  if (($matches | length) == 0) {
    fail $"not a patched Codex release tag: ($tag)"
  }

  let row = $matches.0
  [$row.major $row.minor $row.patch $row.patch_release] | each {|part| $part | into int }
}

def compare-version-parts [left: list<int>, right: list<int>] {
  for idx in 0..3 {
    let left_part = ($left | get $idx)
    let right_part = ($right | get $idx)

    if ($left_part > $right_part) {
      return 1
    } else if ($left_part < $right_part) {
      return (-1)
    }
  }

  0
}

def compare-release-tags [left: string, right: string] {
  compare-version-parts (release-version-parts $left) (release-version-parts $right)
}

def should-move-latest-release-ref [target_tag: string, current_tag: string] {
  if ($current_tag | is-empty) {
    true
  } else {
    (compare-release-tags $target_tag $current_tag) >= 0
  }
}

def latest-release-tag [tags: list<string>] {
  $tags | reduce --fold "" {|tag, best|
    if (($best | is-empty) or ((compare-release-tags $tag $best) > 0)) {
      $tag
    } else {
      $best
    }
  }
}

def current-latest-release [remote: string, ref: string] {
  let ls_remote = (^git ls-remote --exit-code --refs $remote $ref | complete)
  if $ls_remote.exit_code == 2 {
    return { exists: false, tag: "" }
  }

  if $ls_remote.exit_code != 0 {
    fail $"failed to inspect ($ref) on ($remote): ($ls_remote.stderr)"
  }

  let tracking_ref = $"refs/remotes/($remote)/latest-release"
  let fetch = (^git fetch --tags $remote $"+($ref):($tracking_ref)" | complete)
  if $fetch.exit_code != 0 {
    fail $"failed to fetch ($ref) from ($remote): ($fetch.stderr)"
  }

  let tag_result = (^git tag --points-at $tracking_ref --list "codex-*-patch.*" | complete)
  if $tag_result.exit_code != 0 {
    fail $"failed to inspect release tags for ($ref): ($tag_result.stderr)"
  }

  let tags = ($tag_result.stdout | lines | where {|line| not ($line | str trim | is-empty) })
  if (($tags | length) == 0) {
    fail $"($ref) exists on ($remote) but does not point at a codex-*-patch.* tag"
  }

  { exists: true, tag: (latest-release-tag $tags) }
}

def main [
  release_tag: string = ""
  --remote: string = "origin"
  --ref: string = $LATEST_RELEASE_REF
] {
  let target_tag = (if ($release_tag | is-empty) { env-var "RELEASE_TAG" } else { $release_tag })
  if ($target_tag | is-empty) {
    fail "release tag must be provided as an argument or RELEASE_TAG"
  }

  release-version-parts $target_tag | ignore

  let current = (current-latest-release $remote $ref)
  if not (should-move-latest-release-ref $target_tag $current.tag) {
    print $"keeping ($ref) at newer release ($current.tag); not moving it back to ($target_tag)"
    return
  }

  let push = (^git push $remote $"HEAD:($ref)" --force | complete)
  if $push.exit_code != 0 {
    fail $"failed to move ($ref) to ($target_tag): ($push.stderr)"
  }

  if $current.exists {
    print $"moved ($ref) from ($current.tag) to ($target_tag)"
  } else {
    print $"created ($ref) at ($target_tag)"
  }
}
