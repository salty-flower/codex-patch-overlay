# Pure release-decision helpers shared by auto-release.nu and its tests.
# Keep network, git, and file I/O out of this module so tests can call it directly.

export def tag-version [tag: string] {
  $tag | str replace "rust-v" ""
}

export def version-parts [tag: string] {
  tag-version $tag | split row "." | each {|part| $part | into int }
}

export def version-greater-than [left: string, right: string] {
  let l = (version-parts $left)
  let r = (version-parts $right)

  if ($l.0 != $r.0) {
    $l.0 > $r.0
  } else if ($l.1 != $r.1) {
    $l.1 > $r.1
  } else {
    $l.2 > $r.2
  }
}

export def release-patch-suffix [current_tag: string, target_tag: string, manifest_patch_suffix: string] {
  if $target_tag == $current_tag {
    $manifest_patch_suffix
  } else {
    "patch.1"
  }
}

# Unfinished release.yml runs building `tag`.
# Tag pushes run on the tag ref; dispatched runs carry the tag only in their `run-name`.
export def active-release-builds [runs, tag: string] {
  $runs | where {|run|
    $run.status != "completed" and ($run.headBranch == $tag or $run.displayTitle == $"release ($tag)")
  }
}
