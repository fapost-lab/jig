#!/usr/bin/env bash
# Minimal test runner (SPEC §29, decision "A + 1").
#
# Discovers tests/*.t.sh, sources each file and runs every function named
# test_* in its own subshell inside a fresh temporary directory with an
# isolated HOME and deterministic git identity. A test fails when the
# function exits non-zero; assertion helpers live in tests/lib/assert.sh.
#
# Usage: tests/run.sh [name-filter]
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export JIG_HOME="$ROOT"
export JIG_BIN="$ROOT/scripts/jig"

# Shared only within this sequential run; tests receive independent copies.
JIG_TEST_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/jig-test-cache.XXXXXX") || exit 1
export JIG_TEST_CACHE
trap 'rm -rf "$JIG_TEST_CACHE"' EXIT

filter="${1:-}"
pass=0
fail=0
failed=""

list_tests() {
  # Print function names starting with test_ defined in a test file.
  bash -c '
    . "$1"; . "$2"
    declare -F | awk "{print \$3}" | grep "^test_" || true
  ' _ "$ROOT/tests/lib/assert.sh" "$3"
}

for file in "$ROOT"/tests/*.t.sh; do
  [ -e "$file" ] || continue
  base=$(basename "$file" .t.sh)
  for name in $(list_tests _ _ "$file"); do
    full="$base::$name"
    case "$full" in *"$filter"*) ;; *) continue ;; esac
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/jig-test.XXXXXX")
    log="$tmp.log"
    if (
      cd "$tmp" || exit 1
      export HOME="$tmp"
      export JIG_TEST_TMP="$tmp"
      export GIT_CONFIG_NOSYSTEM=1
      export GIT_AUTHOR_NAME=jig GIT_AUTHOR_EMAIL=jig@test
      export GIT_COMMITTER_NAME=jig GIT_COMMITTER_EMAIL=jig@test
      # shellcheck disable=SC1090,SC1091
      . "$ROOT/tests/lib/assert.sh"
      # shellcheck disable=SC1090
      . "$file"
      "$name"
    ) >"$log" 2>&1; then
      pass=$((pass + 1))
      printf 'ok   %s\n' "$full"
    else
      fail=$((fail + 1))
      failed="$failed $full"
      printf 'FAIL %s\n' "$full"
      sed 's/^/     | /' "$log"
    fi
    rm -rf "$tmp" "$log"
  done
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
