#!/usr/bin/env bash
# Runs against the release binary on both native release builders.
set -euo pipefail

codex="$1"
root="$(mktemp -d /tmp/codex-private-home.XXXXXX)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/home/.codex"
chmod 0755 "$root/home" "$root/home/.codex"

run_codex() {
  env -u CODEX_HOME -u CODEX_SQLITE_HOME -u NO_COLOR \
    HOME="$1" TMPDIR=/tmp "$codex" "${@:2}" \
    > "$root/stdout" 2> "$root/stderr"
}

expect_refusal() {
  run_codex "$1" --version
  grep -q 'Refusing to create helper binaries under temporary dir' "$root/stderr"
}

expect_refusal "$root/home"
for setting in false '"true"' 1; do
  printf 'allow_helpers_in_temp = %s\n' "$setting" > "$root/home/.codex/config.toml"
  expect_refusal "$root/home"
done
printf '%s\n' 'allow_helpers_in_temp = true' > "$root/home/.codex/config.toml"
run_codex "$root/home" --version
test -s "$root/stdout"
test ! -s "$root/stderr"
test -n "$(find "$root/home/.codex/tmp" -name apply_patch -type l -print)"
# --version exits through Clap without dropping the guard. A normal command
# must clean both its own directory and any stale one left by --version.
run_codex "$root/home" completion bash
test -s "$root/stdout"
test ! -s "$root/stderr"
test -d "$root/home/.codex/tmp"
test -z "$(find "$root/home/.codex/tmp" -name 'codex-arg0*' -print)"

for mode in 0775 0757 0777; do
  chmod "$mode" "$root/home"
  expect_refusal "$root/home"
done
chmod 0755 "$root/home"
chmod 0777 "$root/home/.codex"
expect_refusal "$root/home"
chmod 0755 "$root/home/.codex"

ln -s "$root/home" "$root/linked-home"
expect_refusal "$root/linked-home"
mkdir "$root/linked-codex-home"
ln -s "$root/home/.codex" "$root/linked-codex-home/.codex"
expect_refusal "$root/linked-codex-home"

printf '%s\n' 'Private temporary HOME: release policy and normal-exit cleanup passed.'
