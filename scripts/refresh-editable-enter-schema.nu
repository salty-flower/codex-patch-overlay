#!/usr/bin/env nu

def main [
  --stage: string = "staging/openai-codex"
] {
  let protocol_root = ([$stage "codex-rs/app-server-protocol"] | path join)
  let schema_root = ([$protocol_root "schema"] | path join)
  if not ($protocol_root | path exists) {
    error make { msg: $"missing patched upstream checkout: ($protocol_root)" }
  }

  for experimental in ["0" "1"] {
    with-env {
      CODEX_APP_SERVER_SCHEMA_ROOT: $schema_root
      CODEX_APP_SERVER_SCHEMA_EXPERIMENTAL: $experimental
    } {
      ^cargo test --manifest-path $"($protocol_root)/Cargo.toml" write_schema_fixtures_from_env -- --ignored --nocapture
    }
  }

  cp --force $"($schema_root)/precomputed/app-server-exports-stable.json.zst" patches/editable-enter-queue-app-server-exports-stable.json.zst
  cp --force $"($schema_root)/precomputed/app-server-exports-experimental.json.zst" patches/editable-enter-queue-app-server-exports-experimental.json.zst
}
