#!/usr/bin/env nu

# Tests the pure release-decision helpers that auto-release.nu uses.

use lib/release.nu *

def expect [condition: bool, message: string] {
  if not $condition {
    error make { msg: $message }
  }
}

def main [] {
  expect ((release-patch-suffix "rust-v0.140.0" "rust-v0.141.0" "patch.3") == "patch.1") "upstream bumps should reset to patch.1"
  expect ((release-patch-suffix "rust-v0.141.0" "rust-v0.141.0" "patch.3") == "patch.3") "same-upstream releases should keep the manifest patch suffix"

  expect (version-greater-than "rust-v0.163.0" "rust-v0.162.1") "a newer minor version should compare greater"
  expect (version-greater-than "rust-v0.162.10" "rust-v0.162.9") "patch numbers should compare numerically"
  expect (not (version-greater-than "rust-v0.162.1" "rust-v0.162.1")) "equal versions should not compare greater"

  # A missing Release with an existing tag must not be retried while that tag is still building.
  let tag = "codex-0.163.0-patch.2"
  let unrelated = [
    { status: "completed", headBranch: $tag, displayTitle: "codex: release" }
    { status: "in_progress", headBranch: "codex-0.163.0-patch.1", displayTitle: "release codex-0.163.0-patch.1" }
    { status: "queued", headBranch: "main", displayTitle: "release codex-0.163.0-patch.10" }
  ]
  expect ((active-release-builds $unrelated $tag | length) == 0) "finished or other-tag builds should not block a retry"

  let pushed = ($unrelated | append { status: "in_progress", headBranch: $tag, displayTitle: "codex: release" })
  expect ((active-release-builds $pushed $tag | length) == 1) "a running tag-push build should block a retry"

  let dispatched = ($unrelated | append { status: "queued", headBranch: "main", displayTitle: $"release ($tag)" })
  expect ((active-release-builds $dispatched $tag | length) == 1) "a queued dispatched build should block a retry"

  print "PASS: patch suffixes reset only on upstream bumps; versions compare numerically; only an unfinished build of the same tag blocks a retry"
}
