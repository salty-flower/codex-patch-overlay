#!/usr/bin/env nu

def fail [message: string] {
  error make { msg: $message }
}

def main [] {
  let manifest = (open patches/manifest.toml)
  let matches = ($manifest.patches | where name == "editable-enter-queue")

  if (($matches | length) != 1) {
    fail "editable-enter-queue must remain in the manifest until exact upstream equivalence is documented"
  }

  let patch = ($matches | first)
  if not $patch.enabled {
    fail "editable-enter-queue cannot be disabled solely because upstream supports queued-message editing"
  }
  if not ($patch.file | path exists) {
    fail $"editable-enter-queue patch is missing: ($patch.file)"
  }

  let body = (open --raw $patch.file)
  let required_contract = [
    "turn/steer/recall"
    "client_user_message_id"
    "TurnSteerRecallStatus"
    "recall_steer"
  ]

  for marker in $required_contract {
    if not ($body | str contains $marker) {
      fail $"editable-enter-queue lost required recall contract marker: ($marker)"
    }
  }

  let payloads = [
    "patches/editable-enter-queue-app-server-exports-stable.json.zst"
    "patches/editable-enter-queue-app-server-exports-experimental.json.zst"
  ]
  for payload in $payloads {
    if not ($payload | path exists) {
      fail $"editable-enter-queue schema payload is missing: ($payload)"
    }
  }
}
