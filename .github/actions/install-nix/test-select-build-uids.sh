#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
selector="$script_dir/select-build-uids.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  [[ "$actual" == "$expected" ]] || fail_test "$description (expected $expected, got $actual)"
  printf 'PASS: %s\n' "$description"
}

login_defs="$tmp_dir/login.defs"
passwd_file="$tmp_dir/passwd"
github_env="$tmp_dir/github-env"

cat > "$login_defs" <<'EOF'
# Last active definitions win, and trailing comments are accepted.
UID_MIN 1000 # normal user floor
SYS_UID_MIN 100
SYS_UID_MAX 119
SYS_UID_MAX 120 # last value
EOF

cat > "$passwd_file" <<'EOF'
root:x:0:0:root:/root:/bin/bash
system-a:x:108:100:system-a:/nonexistent:/usr/sbin/nologin
system-b:x:109:100:system-b:/nonexistent:/usr/sbin/nologin
system-c:x:110:100:system-c:/nonexistent:/usr/sbin/nologin
system-d:x:111:100:system-d:/nonexistent:/usr/sbin/nologin
system-e:x:117:100:system-e:/nonexistent:/usr/sbin/nologin
system-f:x:118:100:system-f:/nonexistent:/usr/sbin/nologin
system-g:x:119:100:system-g:/nonexistent:/usr/sbin/nologin
EOF

: > "$github_env"
"$selector" --fixtures "$login_defs" "$passwd_file" 4 "$github_env"
assert_equal 'NIX_FIRST_BUILD_UID=113' "$(< "$github_env")" 'chooses a free high range and exports it through GITHUB_ENV'

cat > "$login_defs" <<'EOF'
UID_MIN 1500
EOF
: > "$github_env"
"$selector" --fixtures "$login_defs" "$passwd_file" 4 "$github_env"
assert_equal 'NIX_FIRST_BUILD_UID=1496' "$(< "$github_env")" 'uses shadow defaults for SYS_UID_MIN and SYS_UID_MAX'

expect_fixture_failure() {
  local description="$1"
  if "$selector" --fixtures "$login_defs" "$passwd_file" 4 "$github_env" >/dev/null 2>&1; then
    fail_test "$description"
  fi
  printf 'PASS: %s\n' "$description"
}

cat > "$login_defs" <<'EOF'
SYS_UID_MIN 100
SYS_UID_MAX 107
EOF
cat > "$passwd_file" <<'EOF'
user-a:x:100:100:user-a:/nonexistent:/usr/sbin/nologin
user-b:x:102:100:user-b:/nonexistent:/usr/sbin/nologin
user-c:x:104:100:user-c:/nonexistent:/usr/sbin/nologin
user-d:x:106:100:user-d:/nonexistent:/usr/sbin/nologin
EOF
expect_fixture_failure 'rejects exhausted UID ranges'

cat > "$login_defs" <<'EOF'
SYS_UID_MIN 0
SYS_UID_MAX 119
EOF
expect_fixture_failure 'rejects UID zero'

cat > "$login_defs" <<'EOF'
SYS_UID_MIN 100
SYS_UID_MAX 4294967295
EOF
expect_fixture_failure 'rejects the reserved maximum UID'

cat > "$login_defs" <<'EOF'
SYS_UID_MIN 100
SYS_UID_MAX invalid
EOF
expect_fixture_failure 'rejects invalid login.defs values'

cat > "$login_defs" <<'EOF'
SYS_UID_MIN 100
SYS_UID_MAX 119
EOF
cat > "$passwd_file" <<'EOF'
root:x:not-a-uid:0:root:/root:/bin/bash
EOF
expect_fixture_failure 'rejects malformed passwd records'

cat > "$passwd_file" <<'EOF'
nixbld1:x:30001:30000:Nix builder:/var/empty:/sbin/nologin
EOF
expect_fixture_failure 'rejects preexisting builder accounts when Nix is not on PATH'

mock_bin="$tmp_dir/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/uname" <<'EOF'
#!/bin/sh
printf 'Linux\n'
EOF
cat > "$mock_bin/nix" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$mock_bin/uname" "$mock_bin/nix"
: > "$github_env"
/usr/bin/env PATH="$mock_bin:/usr/bin:/bin" GITHUB_ENV="$github_env" bash "$selector"
assert_equal '' "$(< "$github_env")" 'matches upstream behavior and skips UID selection when Nix is already on PATH'

cat > "$mock_bin/uname" <<'EOF'
#!/bin/sh
printf 'Darwin\n'
EOF
rm "$mock_bin/nix"
: > "$github_env"
/usr/bin/env PATH="$mock_bin:/usr/bin:/bin" GITHUB_ENV="$github_env" bash "$selector"
assert_equal '' "$(< "$github_env")" 'keeps the upstream installer default on Darwin'

printf 'All UID selection fixtures passed.\n'
