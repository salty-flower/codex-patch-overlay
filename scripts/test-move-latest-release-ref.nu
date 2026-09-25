#!/usr/bin/env nu

def expect [condition: bool, message: string] {
  if not $condition {
    error make { msg: $message }
  }
}

def run-git [args: list<string>] {
  let result = (^git ...$args | complete)
  if $result.exit_code != 0 {
    error make { msg: $"git ($args | str join ' ') failed: ($result.stderr | str trim)" }
  }
  $result.stdout | str trim
}

def remote-ref [remote: string, ref: string] {
  let output = (run-git ["ls-remote" "--exit-code" "--refs" $remote $ref])
  $output | split row "\t" | first
}

def run-script [script: string, tag: string] {
  ^nu --no-config-file $script $tag --remote origin | complete
}

def main [script_path: string = ""] {
  let script = (if ($script_path | is-empty) {
    $env.FILE_PWD | path join "move-latest-release-ref.nu"
  } else {
    $script_path
  })
  let temp_result = (^mktemp -d | complete)
  expect ($temp_result.exit_code == 0) $"mktemp failed: ($temp_result.stderr | str trim)"
  let fixture = ($temp_result.stdout | str trim)
  let remote_repo = ($fixture | path join "remote.git")
  let work_repo = ($fixture | path join "work")
  let release_ref = "refs/heads/latest-release"
  let initial_tag = "codex-0.157.0-patch.1"
  let older_tag = "codex-0.156.0-patch.1"
  let non_commit_tag = "codex-0.158.0-patch.1"
  let missing_tag = "codex-0.159.0-patch.1"

  run-git ["init" "--bare" "--quiet" $remote_repo] | ignore
  run-git ["init" "-b" "main" "--quiet" $work_repo] | ignore
  run-git ["-C" $work_repo "config" "user.name" "Release Ref Test"] | ignore
  run-git ["-C" $work_repo "config" "user.email" "release-ref-test@example.invalid"] | ignore

  "older release commit\n" | save ($work_repo | path join "tracked.txt")
  run-git ["-C" $work_repo "add" "tracked.txt"] | ignore
  run-git ["-C" $work_repo "commit" "--quiet" "-m" "older release commit"] | ignore
  let older_sha = (run-git ["-C" $work_repo "rev-parse" "HEAD"])
  run-git ["-C" $work_repo "tag" $older_tag $older_sha] | ignore

  "release commit\n" | save --force ($work_repo | path join "tracked.txt")
  run-git ["-C" $work_repo "commit" "--quiet" "-am" "release commit"] | ignore
  let target_sha = (run-git ["-C" $work_repo "rev-parse" "HEAD"])
  run-git ["-C" $work_repo "tag" $initial_tag $target_sha] | ignore
  run-git ["-C" $work_repo "remote" "add" "origin" $remote_repo] | ignore
  run-git ["-C" $work_repo "push" "--quiet" "origin" $"refs/tags/($older_tag)" $"refs/tags/($initial_tag)"] | ignore

  "untagged HEAD commit\n" | save --append ($work_repo | path join "tracked.txt")
  run-git ["-C" $work_repo "commit" "--quiet" "-am" "later main commit"] | ignore
  let untagged_head = (run-git ["-C" $work_repo "rev-parse" "HEAD"])
  expect ($older_sha != $target_sha) "test setup expected older tag to point at a distinct commit"
  expect ($untagged_head != $target_sha) "test setup expected HEAD to be later than the release tag"

  cd $work_repo
  let publish = (run-script $script $initial_tag)
  expect ($publish.exit_code == 0) $"publishing valid tag failed: ($publish.stderr | str trim)"
  let published_sha = (remote-ref "origin" $release_ref)
  expect ($published_sha == $target_sha) "latest-release must point to the resolved release-tag commit"
  expect ($published_sha != $untagged_head) "latest-release unexpectedly followed the non-tag HEAD"

  let downgrade = (run-script $script $older_tag)
  expect ($downgrade.exit_code == 0) $"older release should be ignored successfully: ($downgrade.stderr | str trim)"
  expect ((remote-ref "origin" $release_ref) == $target_sha) "older release moved latest-release backwards"

  let blob_sha = (run-git ["rev-parse" $"HEAD:tracked.txt"])
  run-git ["tag" "-a" $non_commit_tag $blob_sha "-m" "tag to blob"] | ignore
  let invalid = (run-script $script $non_commit_tag)
  expect ($invalid.exit_code != 0) "non-commit release tag was accepted"
  expect ((remote-ref "origin" $release_ref) == $target_sha) "non-commit tag changed latest-release"

  let missing = (run-script $script $missing_tag)
  expect ($missing.exit_code != 0) "missing release tag was accepted"
  expect ((remote-ref "origin" $release_ref) == $target_sha) "missing tag changed latest-release"

  print "PASS: latest-release follows the requested tag commit from a non-tag HEAD; an older commit, missing tag, and non-commit tag are handled safely"
}
