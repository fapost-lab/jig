#!/usr/bin/env bash
# Minimal test runner (ARCHITECTURE.md, Scripts layout; decision "A + 1").
#
# Discovers tests/*.t.sh, sources each file and runs every function named
# test_* in its own subshell inside a fresh temporary directory with an
# isolated HOME and deterministic git identity. A test fails when the
# function exits non-zero; assertion helpers live in tests/lib/assert.sh.
#
# Tests run JIG_TEST_JOBS at a time — by default one per CPU. JIG_TEST_JOBS=1
# runs them one after another, printing each failure's log as it happens.
# In parallel, each test prints its `ok`/`FAIL`/`skip` line when it finishes,
# and the logs of the failures follow the run, in discovery order.
#
# A test that calls `skip "<reason>"` (tests/lib/assert.sh) exits 77. Skip is
# a third outcome, not a pass: it is tallied on its own and never lowers the
# failure count, because a check that quietly stopped running must stay
# visible as something other than green (RULES.md, ADR-0013).
#
# JIG_TEST_SHARD=<i>/<n> runs one share of the suite: every n-th test in
# discovery order, starting at the i-th, so the slow tests of one file spread
# across shares. JIG_TEST_SKIP=<file::test>[,...] reports the named tests as
# skipped without running them — for a check that says nothing new on a given
# platform; a skip stays visible, never a pass.
#
# Usage: tests/run.sh [name-filter]
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export JIG_HOME="$ROOT"
export JIG_BIN="$ROOT/scripts/jig"

# Shared only within this run; tests receive independent copies.
JIG_TEST_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/jig-test-cache.XXXXXX") || exit 1
export JIG_TEST_CACHE
RESULTS=$(mktemp -d "${TMPDIR:-/tmp}/jig-test-results.XXXXXX") || exit 1
trap 'rm -rf "$JIG_TEST_CACHE" "$RESULTS"' EXIT
# An interrupted parallel run must not leave its workers running.
trap 'kill $(jobs -p) 2>/dev/null; exit 130' INT TERM

filter="${1:-}"

shard_i=1
shard_n=1
if [ -n "${JIG_TEST_SHARD:-}" ]; then
  shard_i=${JIG_TEST_SHARD%%/*}
  shard_n=${JIG_TEST_SHARD#*/}
  case "$shard_i:$shard_n" in
    # Nine digits and more are refused too: `[ -lt ]` on a number past the
    # integer range fails as an error, which reads as "not less" and let it by.
    *[!0-9:]* | :* | *: | 0* | *:0* | ?????????*:* | *:?????????*) shard_n=0 ;;
  esac
  if [ "$JIG_TEST_SHARD" = "$shard_i" ] || [ "$shard_n" -lt 1 ] || [ "$shard_i" -gt "$shard_n" ]; then
    printf 'tests/run.sh: JIG_TEST_SHARD must be <i>/<n> with 1 <= i <= n: %s\n' "$JIG_TEST_SHARD" >&2
    exit 2
  fi
fi
skip_list=",${JIG_TEST_SKIP:-},"

jobs="${JIG_TEST_JOBS:-}"
[ -n "$jobs" ] || jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || jobs=1
case "$jobs" in
  '' | *[!0-9]* | 0)
    printf 'tests/run.sh: JIG_TEST_JOBS must be a positive integer: %s\n' "$jobs" >&2
    exit 2
    ;;
esac

list_tests() {
  # Print function names starting with test_ defined in a test file.
  bash -c '
    . "$1"; . "$2"
    declare -F | awk "{print \$3}" | grep "^test_" || true
  ' _ "$ROOT/tests/lib/assert.sh" "$1"
}

# enter_test_env <dir> — what every test runs inside, and what the fixture
# cache is built inside: <dir> as working directory and HOME, git reading no
# system config, a fixed identity, and the assertion helpers.
enter_test_env() {
  cd "$1" || exit 1
  export HOME="$1"
  export JIG_TEST_TMP="$1"
  export GIT_CONFIG_NOSYSTEM=1
  # A run started by a narrowed `jig verify` carries the scope it was given,
  # and CI sets CI: neither describes the project a test builds. A test that
  # runs a profile directly inherited JIG_VERIFY_FILES naming this
  # repository's changes and took the scoped path (ADR-0041).
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED CI
  export GIT_AUTHOR_NAME=jig GIT_AUTHOR_EMAIL=jig@test
  export GIT_COMMITTER_NAME=jig GIT_COMMITTER_EMAIL=jig@test
  # shellcheck disable=SC1090,SC1091
  . "$ROOT/tests/lib/assert.sh"
}

# run_test <index> <file> <name> <full> — run one test, record its exit code,
# seconds and log under $RESULTS, and print its line. Everything the line
# reports has finished by the time it is printed: bash 3.2 does not restart a
# write interrupted by SIGCHLD ("write error: Interrupted system call"), so no
# child of this shell is still running when it writes.
run_test() {
  local idx="$1" file="$2" name="$3" full="$4" tmp rc=0 start
  case "$skip_list" in
    *",$full,"*)
      printf '77\t0\t%s\n' "$full" > "$RESULTS/$idx.result"
      printf 'SKIP: JIG_TEST_SKIP\n' > "$RESULTS/$idx.log"
      printf 'skip %s (JIG_TEST_SKIP)\n' "$full"
      return 0
      ;;
  esac
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/jig-test.XXXXXX") || return 1
  start=$SECONDS
  (
    # The runner's descriptors are the runner's: 3 is the semaphore, 4 is the
    # list of tests, and a test reading from 4 would move the offset the
    # dispatch loop reads from — every inherited descriptor shares it.
    exec 3>&- 4<&-
    enter_test_env "$tmp"
    # shellcheck disable=SC1090
    . "$file"
    "$name"
  ) >"$RESULTS/$idx.log" 2>&1 || rc=$?
  printf '%s\t%s\t%s\n' "$rc" "$((SECONDS - start))" "$full" > "$RESULTS/$idx.result"
  rm -rf "$tmp" "$tmp.out" "$tmp.out.err"
  if [ "$rc" -eq 0 ]; then
    printf 'ok   %s\n' "$full"
  elif [ "$rc" -eq 77 ]; then
    # The reason is the last SKIP: line, not the first: a test may print one
    # while probing several capabilities before settling on the one it acts on.
    local reason
    reason=$(sed -n 's/^SKIP: //p' "$RESULTS/$idx.log" | tail -n 1)
    printf 'skip %s (%s)\n' "$full" "$reason"
  else
    printf 'FAIL %s\n' "$full"
    [ "$jobs" -gt 1 ] || sed 's/^/     | /' "$RESULTS/$idx.log"
  fi
  return 0
}

# Discovery first, so that the order is fixed before anything runs. The list
# is read back on descriptor 4, never on stdin, which the tests inherit.
list="$RESULTS/list"
: > "$list"
idx=0
seq=0
for file in "$ROOT"/tests/*.t.sh; do
  [ -e "$file" ] || continue
  base=$(basename "$file" .t.sh)
  for name in $(list_tests "$file"); do
    full="$base::$name"
    case "$full" in *"$filter"*) ;; *) continue ;; esac
    seq=$((seq + 1))
    [ $(( (seq - 1) % shard_n )) -eq $((shard_i - 1)) ] || continue
    idx=$((idx + 1))
    printf '%s\t%s\t%s\t%s\n' "$idx" "$file" "$name" "$full" >> "$list"
  done
done
total=$idx

start_all=$SECONDS
t=$(printf '\t')

if [ "$jobs" -eq 1 ]; then
  while IFS="$t" read -r -u 4 idx file name full; do
    run_test "$idx" "$file" "$name" "$full"
  done 4< "$list"
else
  # The shared fixture is built before any test starts (fixture_cache_prepare
  # explains what two tests building it at once would do).
  cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-test-cache-build.XXXXXX") || exit 1
  if ! ( enter_test_env "$cache_dir"; fixture_cache_prepare ) >"$RESULTS/cache.log" 2>&1; then
    printf 'tests/run.sh: could not build the fixture cache\n' >&2
    sed 's/^/     | /' "$RESULTS/cache.log" >&2
    rm -rf "$cache_dir"
    exit 1
  fi
  rm -rf "$cache_dir"

  # A FIFO holding one token per worker: a test starts by taking one and gives
  # it back when it ends. Plain bash 3.2 — `wait -n` does not exist there — and
  # it hands the next test to whichever worker frees up first, so one slow file
  # does not hold back a whole share of the suite.
  fifo=$(mktemp -u "${TMPDIR:-/tmp}/jig-test-slots.XXXXXX")
  mkfifo "$fifo" || exit 1
  exec 3<>"$fifo"
  rm -f "$fifo"
  i=0
  while [ "$i" -lt "$jobs" ]; do
    printf '.\n' >&3
    i=$((i + 1))
  done
  while IFS="$t" read -r -u 4 idx file name full; do
    read -r -u 3 _
    ( run_test "$idx" "$file" "$name" "$full"; printf '.\n' >&3 ) &
  done 4< "$list"
  wait
  exec 3>&-
fi

pass=0
fail=0
skip=0
while IFS="$t" read -r -u 4 idx file name full; do
  rc=missing
  [ -f "$RESULTS/$idx.result" ] && IFS="$t" read -r rc _ < "$RESULTS/$idx.result"
  if [ "$rc" = 0 ]; then
    pass=$((pass + 1))
  elif [ "$rc" = 77 ]; then
    skip=$((skip + 1))
  else
    fail=$((fail + 1))
    if [ "$jobs" -gt 1 ]; then
      printf '\nFAIL %s\n' "$full"
      sed 's/^/     | /' "$RESULTS/$idx.log" 2>/dev/null
    fi
  fi
done 4< "$list"

# Where the time went: the slowest tests, to the second. Collected before it is
# printed, so no child is alive during the writes (see run_test).
if [ "$total" -gt 0 ]; then
  slowest=$(cat "$RESULTS"/*.result 2>/dev/null | sort -t "$t" -k2,2nr | head -n 5)
  printf '\nslowest:\n'
  while IFS="$t" read -r _ secs full; do
    [ -n "$full" ] || continue
    printf '  %4ss  %s\n' "$secs" "$full"
  done <<EOF
$slowest
EOF
  printf 'wall: %ss, %s job(s)\n' "$((SECONDS - start_all))" "$jobs"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
