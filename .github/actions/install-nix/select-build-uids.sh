#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'select-build-uids: %s\n' "$*" >&2
  exit 1
}

fixture_mode=false
if [[ $# -eq 5 && $1 == --fixtures ]]; then
  fixture_mode=true
  login_defs=$2
  passwd_source=$3
  build_user_count=$4
  github_env=$5
elif [[ $# -eq 0 ]]; then
  login_defs=/etc/login.defs
  github_env=${GITHUB_ENV:-}
else
  fail 'usage: select-build-uids.sh [--fixtures LOGIN_DEFS PASSWD COUNT GITHUB_ENV]'
fi

if [[ $fixture_mode == false ]]; then
  os_name=$(uname -s) || fail 'could not determine the operating system'
  if [[ $os_name != Linux ]]; then
    printf 'Skipping Linux Nix builder UID selection on %s; keeping installer defaults.\n' "$os_name"
    exit 0
  fi
  # Match the pinned upstream installer check so repeated action invocations
  # do not try to allocate over an existing Nix installation.
  if type -p nix >/dev/null 2>&1; then
    printf 'Nix is already on PATH; skipping Linux builder UID selection.\n'
    exit 0
  fi
  command -v getent >/dev/null 2>&1 || fail 'getent is required to validate system account UIDs'
  command -v python3 >/dev/null 2>&1 || fail 'python3 is required to match the upstream installer build-user count'
  build_user_count=$(python3 -c 'import multiprocessing as mp; print(mp.cpu_count() * 2)') || fail 'could not determine the upstream installer build-user count'
  [[ -e $login_defs ]] || login_defs=/dev/null
  [[ -f $login_defs && -r $login_defs ]] || fail "cannot read login definitions at $login_defs"
fi

[[ $build_user_count =~ ^[1-9][0-9]*$ ]] || fail 'build-user count must be a positive integer'
[[ -n $github_env ]] || fail 'GITHUB_ENV is not set'

uid_bounds=$(awk '
  BEGIN {
    uid_min = 1000
    sys_uid_min = 101
  }
  {
    sub(/[[:space:]]+#.*/, "")
    if ($0 ~ /^[[:space:]]*$/) next
  }
  $1 == "UID_MIN" { uid_min = $2; uid_min_bad = (NF != 2 || $2 !~ /^[0-9]+$/) }
  $1 == "SYS_UID_MIN" { sys_uid_min = $2; sys_uid_min_bad = (NF != 2 || $2 !~ /^[0-9]+$/) }
  $1 == "SYS_UID_MAX" { sys_uid_max = $2; sys_uid_max_bad = (NF != 2 || $2 !~ /^[0-9]+$/); have_sys_uid_max = 1 }
  END {
    if (uid_min_bad || uid_min !~ /^[0-9]+$/ || uid_min + 0 > 4294967294) {
      print "select-build-uids: invalid UID_MIN in login.defs" > "/dev/stderr"
      exit 1
    }
    if (sys_uid_min_bad || sys_uid_min !~ /^[0-9]+$/ || sys_uid_min + 0 < 1 || sys_uid_min + 0 > 4294967294) {
      print "select-build-uids: invalid SYS_UID_MIN in login.defs" > "/dev/stderr"
      exit 1
    }
    if (have_sys_uid_max) {
      if (sys_uid_max_bad || sys_uid_max !~ /^[0-9]+$/ || sys_uid_max + 0 < 1 || sys_uid_max + 0 > 4294967294) {
        print "select-build-uids: invalid SYS_UID_MAX in login.defs" > "/dev/stderr"
        exit 1
      }
      max = sys_uid_max + 0
    } else {
      max = uid_min + 0 - 1
    }
    min = sys_uid_min + 0
    if (min > max) {
      print "select-build-uids: empty system UID range" > "/dev/stderr"
      exit 1
    }
    printf "%.0f %.0f\n", min, max
  }
' "$login_defs") || fail 'could not read shadow-utils UID bounds'
read -r sys_uid_min sys_uid_max <<< "$uid_bounds"

work_dir=$(mktemp -d) || fail 'could not create a temporary directory'
trap 'rm -rf "$work_dir"' EXIT
passwd_file="$work_dir/passwd"
uid_file="$work_dir/occupied-uids"
if [[ $fixture_mode == true ]]; then
  cp "$passwd_source" "$passwd_file" || fail 'could not read the passwd fixture'
else
  getent passwd > "$passwd_file" || fail 'getent passwd failed'
fi

awk -F: -v count="$build_user_count" -v min="$sys_uid_min" -v max="$sys_uid_max" '
  function invalid(message) {
    printf "select-build-uids: invalid getent passwd data: %s\n", message > "/dev/stderr"
    bad = 1
    exit 1
  }
  NF != 7 { invalid("expected seven fields on line " NR) }
  $1 == "" { invalid("empty account name on line " NR) }
  $3 !~ /^[0-9]+$/ || $3 + 0 > 4294967295 { invalid("invalid UID on line " NR) }
  $4 !~ /^[0-9]+$/ || $4 + 0 > 4294967295 { invalid("invalid GID on line " NR) }
  {
    if ($1 ~ /^nixbld[0-9]+$/) {
      builder = substr($1, 7) + 0
      if (builder >= 1 && builder <= count) {
        invalid("builder account " $1 " already exists")
      }
    }
    uid = $3 + 0
    if (uid >= min && uid <= max) {
      printf "%.0f\n", uid
    }
  }
  END {
    if (bad) {
      exit 1
    }
    if (NR == 0) {
      print "select-build-uids: getent passwd returned no accounts" > "/dev/stderr"
      exit 1
    }
  }
' "$passwd_file" > "$uid_file" || fail 'could not validate system accounts'

uid_start=$(LC_ALL=C sort -nr -u "$uid_file" | awk \
  -v min="$sys_uid_min" -v max="$sys_uid_max" -v count="$build_user_count" '
    BEGIN { cursor = max + 1 }
    {
      uid = $1 + 0
      if (cursor - uid - 1 >= count) {
        printf "%.0f\n", cursor - count
        found = 1
        exit
      }
      cursor = uid
    }
    END {
      if (!found && cursor - min >= count) {
        printf "%.0f\n", cursor - count
        found = 1
      }
      if (!found) {
        printf "select-build-uids: no free contiguous range of %s system UIDs in %s..%s\n", count, min, max > "/dev/stderr"
        exit 1
      }
    }
  ') || fail 'unable to select Nix builder UIDs'

printf 'NIX_FIRST_BUILD_UID=%s\n' "$uid_start" >> "$github_env" || fail 'could not write NIX_FIRST_BUILD_UID to GITHUB_ENV'
printf 'Selected %s free Nix builder UIDs starting at %s within %s..%s.\n' \
  "$build_user_count" "$uid_start" "$sys_uid_min" "$sys_uid_max"
