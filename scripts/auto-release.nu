#!/usr/bin/env nu

const FAKE_SHA256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

def env-var [name: string] {
  let matches = ($env | transpose key value | where key == $name)
  if (($matches | length) == 0) {
    ""
  } else {
    $matches.0.value
  }
}

def fail [message: string] {
  error make { msg: $message }
}

def latest-stable-tag [repo: string] {
  let result = (^gh release list --repo $repo --limit 100 --json tagName,isDraft,isPrerelease,publishedAt | complete)
  if $result.exit_code != 0 {
    fail $"failed to list upstream releases for ($repo): ($result.stderr)"
  }

  let releases = ($result.stdout | from json)
  let stable = ($releases | where isDraft == false | where isPrerelease == false | where tagName =~ '^rust-v[0-9]+\.[0-9]+\.[0-9]+$')
  if (($stable | length) == 0) {
    fail $"no stable rust-v release found for ($repo)"
  }

  $stable.0.tagName
}

def tag-version [tag: string] {
  $tag | str replace "rust-v" ""
}

def version-parts [tag: string] {
  tag-version $tag | split row "." | each {|part| $part | into int }
}

def version-greater-than [left: string, right: string] {
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

def release-patch-suffix [current_tag: string, target_tag: string, manifest_patch_suffix: string] {
  if $target_tag == $current_tag {
    $manifest_patch_suffix
  } else {
    "patch.1"
  }
}

def overlay-repo [] {
  let from_env = (env-var "GITHUB_REPOSITORY")
  if not ($from_env | is-empty) {
    return $from_env
  }

  let remote = (^git remote get-url origin | complete)
  if $remote.exit_code == 0 {
    let remote_url = ($remote.stdout | str trim)
    let matches = ($remote_url | parse -r 'github\.com[:/](?P<path>.+)$')
    if (($matches | length) > 0) {
      return ($matches.0.path | str replace --regex '\.git$' '')
    }
  }

  let result = (^gh repo view --json nameWithOwner --jq .nameWithOwner | complete)
  if $result.exit_code != 0 {
    fail $"failed to detect overlay repo: ($result.stderr)"
  }

  $result.stdout | str trim
}

def release-exists [repo: string, tag: string] {
  let result = (^gh release view $tag --repo $repo | complete)
  $result.exit_code == 0
}

def remote-tag-exists [tag: string] {
  let result = (^git ls-remote --exit-code --tags origin $tag | complete)
  $result.exit_code == 0
}

def write-output [release_tag: string, upstream_tag: string, dispatch_release: bool] {
  let output = (env-var "GITHUB_OUTPUT")
  if not ($output | is-empty) {
    let lines = ([
      $"release_tag=($release_tag)"
      $"upstream_tag=($upstream_tag)"
      $"dispatch_release=($dispatch_release)"
    ] | str join (char nl))
    ($lines + (char nl)) | save --append $output
  }
}

def enabled-patches [manifest] {
  $manifest.patches | where enabled == true
}

def assert-enabled-patches [patches] {
  if (($patches | length) == 0) {
    fail "manifest has no enabled patches"
  }

  for patch in $patches {
    if ($patch.upstream_sha | is-empty) {
      fail $"enabled patch missing upstream_sha: ($patch.name)"
    }
    if not ($patch.file | path exists) {
      fail $"enabled patch file missing: ($patch.file)"
    }
  }
}

def checked-out-upstream [repo: string, tag: string] {
  let stage = (^mktemp -d | str trim)
  ^git clone --filter=blob:none $"https://github.com/($repo).git" $stage
  ^git -C $stage checkout --detach $tag
  let sha = (^git -C $stage rev-parse HEAD | str trim)
  { stage: $stage, sha: $sha }
}

def verify-patches-apply [stage: string, patches] {
  let root = (^pwd | str trim)
  for patch in $patches {
    let patch_path = ([$root $patch.file] | path join)
    print $"checking ($patch.name): ($patch.file)"
    ^git -C $stage apply --check $patch_path
    ^git -C $stage apply $patch_path
  }
}

def source-hash [repo: string, sha: string] {
  let url = $"https://github.com/($repo)/archive/($sha).tar.gz"
  let prefetch = (^nix-prefetch-url --unpack --type sha256 $url | complete)
  if $prefetch.exit_code != 0 {
    fail $"failed to prefetch upstream source ($sha): ($prefetch.stderr)"
  }

  let nix32 = ($prefetch.stdout | lines | last | str trim)
  let converted = (^nix hash convert --hash-algo sha256 --from nix32 --to sri $nix32 | complete)
  if $converted.exit_code != 0 {
    fail $"failed to convert upstream source hash: ($converted.stderr)"
  }

  $converted.stdout | str trim
}

def refresh-cargo-hash [] {
  let result = (^nix build .#packages.x86_64-linux.codex-patched --no-link --print-build-logs | complete)
  if $result.exit_code == 0 {
    fail "cargo vendor hash refresh unexpectedly succeeded with fake hash"
  }

  let text = ([$result.stdout $result.stderr] | str join (char nl))
  let matches = ($text | parse -r 'got:\s+(?P<hash>sha256-[A-Za-z0-9+/=]+)')
  if (($matches | length) == 0) {
    fail $"failed to parse cargo vendor hash from nix output: ($text)"
  }

  $matches | last | get hash
}

def update-manifest [
  path: string
  upstream_tag: string
  upstream_sha: string
  new_source_hash: string
  new_cargo_hash: string
  patch_suffix: string
] {
  let raw = (open --raw $path)
  mut in_patch = false
  mut patch_enabled = false
  mut out = []

  for line in ($raw | lines) {
    mut next = $line

    if ($line == "[[patches]]") {
      $in_patch = true
      $patch_enabled = false
    }

    if ($line =~ '^patch_suffix = ') {
      $next = $"patch_suffix = \"($patch_suffix)\""
    }

    if ($in_patch and ($line =~ '^enabled = ')) {
      $patch_enabled = ($line =~ 'true')
    }

    if ($in_patch and $patch_enabled) {
      if ($line =~ '^upstream_base = ') {
        $next = $"upstream_base = \"($upstream_tag)\""
      } else if ($line =~ '^upstream_sha = ') {
        $next = $"upstream_sha = \"($upstream_sha)\""
      } else if ($line =~ '^source_hash = ') {
        $next = $"source_hash = \"($new_source_hash)\""
      } else if ($line =~ '^cargo_hash = ') {
        $next = $"cargo_hash = \"($new_cargo_hash)\""
      }
    }

    $out = ($out | append $next)
  }

  (($out | str join (char nl)) + (char nl)) | save -f $path
}

def write-record [release_tag: string, upstream_repo: string, upstream_tag: string, upstream_sha: string, patches] {
  let date = (date now | format date "%Y-%m-%d")
  let path = $"docs/records/($date)-($release_tag).md"
  if not ($path | path exists) {
    let patch_lines = ($patches | each {|patch| $"- `($patch.name)`" } | str join (char nl))
    let body = ([
      $"# ($release_tag)"
      ""
      "## Source"
      ""
      $"- Upstream: `($upstream_repo)@($upstream_tag)`"
      $"- Upstream SHA: `($upstream_sha)`"
      $"- Patch release: `($release_tag)`"
      ""
      "## Gate"
      ""
      "- Enabled patches applied with `git apply --check`."
      "- `nix flake check` passed before tagging."
      "- GitHub Actions builds release artifacts from the tag."
      ""
      "## Enabled Patches"
      ""
      $patch_lines
    ] | str join (char nl))
    ($body + (char nl)) | save -f $path
  }

  $path
}

def main [
  --upstream-tag: string = ""
  --apply
] {
  let manifest_path = "patches/manifest.toml"
  let manifest = (open $manifest_path)
  let manifest_patch_suffix = $manifest.release.patch_suffix
  let upstream_repo = $manifest.release.upstream_repo
  let current_tag = (enabled-patches $manifest).0.upstream_base
  let target_tag = (if ($upstream_tag | is-empty) { latest-stable-tag $upstream_repo } else { $upstream_tag })

  if not ($target_tag =~ '^rust-v[0-9]+\.[0-9]+\.[0-9]+$') {
    fail $"target upstream tag is not a stable rust release: ($target_tag)"
  }

  if (($target_tag != $current_tag) and not (version-greater-than $target_tag $current_tag)) {
    fail $"target upstream tag ($target_tag) is older than manifest upstream ($current_tag)"
  }

  let patch_suffix = (release-patch-suffix $current_tag $target_tag $manifest_patch_suffix)
  let release_tag = $"codex-(tag-version $target_tag)-($patch_suffix)"
  let repo = (overlay-repo)

  if (release-exists $repo $release_tag) {
    print $"already released: ($release_tag)"
    return
  }

  if (remote-tag-exists $release_tag) {
    if $apply {
      print $"release missing for existing tag: retrying ($release_tag)"
      write-output $release_tag $target_tag true
    } else {
      print $"dry run: would retry release for existing tag ($release_tag)"
    }
    return
  }

  let patches = (enabled-patches $manifest)
  assert-enabled-patches $patches

  let upstream = (checked-out-upstream $upstream_repo $target_tag)
  verify-patches-apply $upstream.stage $patches

  if not $apply {
    print $"dry run: would release ($release_tag) from ($target_tag) at ($upstream.sha)"
    return
  }

  let dirty = (^git status --porcelain | str trim)
  if not ($dirty | is-empty) {
    fail $"working tree must be clean before auto-release: ($dirty)"
  }

  let new_source_hash = (if ($target_tag == $current_tag) { $patches.0.source_hash } else { source-hash $upstream_repo $upstream.sha })
  update-manifest $manifest_path $target_tag $upstream.sha $new_source_hash $FAKE_SHA256 $patch_suffix
  let new_cargo_hash = (if ($target_tag == $current_tag) { $patches.0.cargo_hash } else { refresh-cargo-hash })
  update-manifest $manifest_path $target_tag $upstream.sha $new_source_hash $new_cargo_hash $patch_suffix

  ^nix flake check

  let record_path = (write-record $release_tag $upstream_repo $target_tag $upstream.sha $patches)
  ^git config user.name "github-actions[bot]"
  ^git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  ^git add $manifest_path $record_path

  let staged = (^git diff --cached --quiet | complete)
  if $staged.exit_code == 0 {
    fail $"no release changes staged for ($release_tag)"
  }

  ^git commit -m $"codex: release (tag-version $target_tag) ($patch_suffix)"
  ^git tag -a $release_tag -m $release_tag
  ^git push origin HEAD:main
  ^git push origin $release_tag
  # Pushing the new tag triggers release.yml through its push event. Only an
  # existing tag with a missing release needs an explicit workflow dispatch.
  write-output $release_tag $target_tag false
}
