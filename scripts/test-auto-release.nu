#!/usr/bin/env nu

# Tests the pure release-decision helpers in auto-release.nu.

def expect [condition: bool, message: string] {
  if not $condition {
    error make { msg: $message }
  }
}

# auto-release.nu defines its own `main`, which cannot be redefined here, so each call
# sources it in a separate `nu -c`, where `main` is never invoked.
def call [script: string, expression: string] {
  let result = (^nu --no-config-file -c $"source '($script)'; ($expression) | to nuon" | complete)
  expect ($result.exit_code == 0) $"($expression) failed: ($result.stderr | str trim)"
  $result.stdout | from nuon
}

def active-count [script: string, runs: list, tag: string] {
  call $script $"active-release-builds ($runs | to nuon) '($tag)' | length"
}

def main [script_path: string = ""] {
  let script = (if ($script_path | is-empty) {
    $env.FILE_PWD | path join "auto-release.nu"
  } else {
    $script_path
  })

  let bump = (call $script 'release-patch-suffix "rust-v0.140.0" "rust-v0.141.0" "patch.3"')
  expect ($bump == "patch.1") "upstream bumps should reset to patch.1"
  let same = (call $script 'release-patch-suffix "rust-v0.141.0" "rust-v0.141.0" "patch.3"')
  expect ($same == "patch.3") "same-upstream releases should keep the manifest patch suffix"

  # A missing Release with an existing tag must not be retried while that tag is still building.
  let tag = "codex-0.163.0-patch.2"
  let unrelated = [
    { status: "completed", headBranch: $tag, displayTitle: "codex: release" }
    { status: "in_progress", headBranch: "codex-0.163.0-patch.1", displayTitle: "release codex-0.163.0-patch.1" }
    { status: "queued", headBranch: "main", displayTitle: "release codex-0.163.0-patch.10" }
  ]
  expect ((active-count $script $unrelated $tag) == 0) "finished or other-tag builds should not block a retry"

  let pushed = ($unrelated | append { status: "in_progress", headBranch: $tag, displayTitle: "codex: release" })
  expect ((active-count $script $pushed $tag) == 1) "a running tag-push build should block a retry"

  let dispatched = ($unrelated | append { status: "queued", headBranch: "main", displayTitle: $"release ($tag)" })
  expect ((active-count $script $dispatched $tag) == 1) "a queued dispatched build should block a retry"

  print "PASS: patch suffixes reset only on upstream bumps; only an unfinished build of the same tag blocks a retry"
}
