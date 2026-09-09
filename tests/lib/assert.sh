# Assertion helpers and fixtures for tests/*.t.sh. Sourced by tests/run.sh
# inside each test's subshell; every helper exits 1 on failure.
# shellcheck shell=bash

# --- fixtures ----------------------------------------------------------------

# Create an empty git repository in the current (temporary) directory with
# one commit on branch main. Prints nothing.
fixture_repo() {
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  printf '# fixture\n' > README.md
  git add README.md
  git commit -q -m "init"
}

# A default copy-mode install for tests of commands other than init/upgrade.
# Cache only preparation, never results; the runner discards it after each run.
# cp (not hard links) isolates both the installed files and Git state per test.
fixture_jig_repo() {
  if [ -z "${JIG_TEST_CACHE:-}" ]; then
    fixture_repo && jig init --from "$JIG_HOME" >/dev/null
    return $?
  fi
  local seed="$JIG_TEST_CACHE/installed" build
  if [ ! -f "$JIG_TEST_CACHE/ready" ]; then
    mkdir -p "$JIG_TEST_CACHE" || return 1
    build=$(mktemp -d "$JIG_TEST_CACHE/build.XXXXXX") || return 1
    (
      cd "$build" || exit 1
      fixture_repo && jig init --from "$JIG_HOME" >/dev/null
    ) || return 1
    mv "$build" "$seed" || return 1
    touch "$JIG_TEST_CACHE/ready" || return 1
  fi
  cp -R "$seed/." .
}

# Run jig from the framework source checkout.
jig() { "$JIG_BIN" "$@"; }

# Run jig from the copy installed into the current project.
jig_installed() { ".ai/scripts/jig" "$@"; }

# --- assertions --------------------------------------------------------------

fail() { printf 'ASSERT FAIL: %s\n' "$*"; exit 1; }

assert_eq() {
  # assert_eq <expected> <actual> [message]
  [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$1] got [$2]"
}

assert_contains() {
  # assert_contains <haystack> <needle> [message]
  case "$1" in *"$2"*) ;; *) fail "${3:-missing substring}: [$2] not in [$1]" ;; esac
}

assert_not_contains() {
  case "$1" in *"$2"*) fail "${3:-unexpected substring}: [$2] found in [$1]" ;; esac
}

assert_file() { [ -f "$1" ] || fail "${2:-expected file}: $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "${2:-unexpected path}: $1"; }
assert_dir() { [ -d "$1" ] || fail "${2:-expected directory}: $1"; }
assert_symlink() { [ -L "$1" ] || fail "${2:-expected symlink}: $1"; }

assert_file_contains() {
  # assert_file_contains <file> <substring>
  assert_file "$1"
  grep -q -- "$2" "$1" || fail "file $1 does not contain [$2]"
}

assert_exit() {
  # assert_exit <code> <command...> — run command, compare its exit code.
  local expected="$1" actual
  shift
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  [ "$actual" -eq "$expected" ] || fail "exit code: expected $expected got $actual for: $*"
}

# Run a command, capture stdout+stderr into OUT and exit code into RC without
# failing the test. Usage: run cmd args...; then assert on $OUT / $RC.
run() {
  set +e
  OUT=$("$@" 2>&1)
  RC=$?
  set -e
  export OUT RC
}
