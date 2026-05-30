#!/usr/bin/env nu

def main [
  name: string
  --stage: string = "staging/openai-codex"
] {
  let manifest = (open patches/manifest.toml)
  let matches = ($manifest.patches | where name == $name)
  if (($matches | length) != 1) {
    error make { msg: $"expected exactly one patch named ($name)" }
  }

  let patch = $matches.0
  let output = $patch.file
  ^git -C $stage diff --binary out> $output
  print $"refreshed ($name): ($output)"
}
