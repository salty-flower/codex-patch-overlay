#!/usr/bin/env bash
set -euo pipefail

upstream="$1"
target="$2"
package="$3"
list_binaries="$4"
binaries="$(mktemp "${TMPDIR:-/tmp}/codex-upstream-binaries.XXXXXXXX")"
trap 'rm -f "$binaries"' EXIT
bash "$list_binaries" "$upstream" "$target" > "$binaries"
while IFS= read -r binary; do
  if [[ ! ( -f "$package/bin/$binary" && -x "$package/bin/$binary" ) && ! ( -f "$package/codex-resources/$binary" && -x "$package/codex-resources/$binary" ) ]]; then
    echo "Nix package does not include upstream binary: $binary ($target)" >&2
    exit 1
  fi
done < "$binaries"
