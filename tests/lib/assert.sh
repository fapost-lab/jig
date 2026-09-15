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
  fixture_cache_prepare || return 1
  cp -R "$JIG_TEST_CACHE/installed/." .
}

# fixture_cache_prepare — build the cached install fixture_jig_repo copies, once
# per runner invocation. Lazy when tests run one at a time; a parallel runner
# calls it before it starts any test, because two tests building it at once
# would both miss `ready`, and the second `mv` would put its build *inside* the
# first one's — a fixture corrupted without an error.
fixture_cache_prepare() {
  local seed="$JIG_TEST_CACHE/installed" build
  [ ! -f "$JIG_TEST_CACHE/ready" ] || return 0
  mkdir -p "$JIG_TEST_CACHE" || return 1
  build=$(mktemp -d "$JIG_TEST_CACHE/build.XXXXXX") || return 1
  (
    cd "$build" || exit 1
    fixture_repo && jig init --from "$JIG_HOME" >/dev/null
  ) || return 1
  mv "$build" "$seed" || return 1
  touch "$JIG_TEST_CACHE/ready" || return 1
}

# Build the merge topologies housekeeping has to tell apart, on top of the
# current repository (call after fixture_jig_repo). Every branch below is
# created off main and left behind so ancestry detection can be asserted
# against a known answer:
#
#   ff-merged       fast-forwarded into main          -> merged
#   commit-merged   merged with a real merge commit   -> merged
#   squash-merged   squashed into one commit on main  -> merged
#   rebase-merged   replayed commit-by-commit on main -> merged
#   still-open      never merged                      -> unknown
#   gone-merged     squash-merged, then branch deleted-> unknown (no local ref)
#
# `gone-merged` is the case only a forge can answer: with the branch deleted
# there is no tip to compare, which is why the ancestry tier must say
# `unknown` rather than guess.
fixture_merge_repo() {
  git checkout -q -b ff-merged
  printf 'ff\n' > ff.txt
  git add ff.txt
  git commit -q -m "ff work"
  git checkout -q main
  git merge -q --ff-only ff-merged

  git checkout -q -b commit-merged
  printf 'mc\n' > mc.txt
  git add mc.txt
  git commit -q -m "merge-commit work"
  git checkout -q main
  git merge -q --no-ff -m "merge commit-merged" commit-merged

  # Two commits, so a per-commit patch-id comparison would miss this and only
  # the combined diff matches (design.md §2 step 2).
  git checkout -q -b squash-merged
  printf 'sq1\n' > sq.txt
  git add sq.txt
  git commit -q -m "squash work 1"
  printf 'sq2\n' >> sq.txt
  git add sq.txt
  git commit -q -m "squash work 2"
  git checkout -q main
  # `--squash` always says "Squash commit -- not updating HEAD" on stdout and
  # `cherry-pick` has no --quiet at all, so both are silenced here rather than
  # leaking into the output a test asserts on.
  git merge --squash squash-merged >/dev/null
  git commit -q -m "squashed squash-merged"

  git checkout -q -b rebase-merged
  printf 'rb\n' > rb.txt
  git add rb.txt
  git commit -q -m "rebase work"
  git checkout -q main
  git cherry-pick rebase-merged >/dev/null

  git checkout -q -b still-open
  printf 'open\n' > open.txt
  git add open.txt
  git commit -q -m "open work"
  git checkout -q main

  git checkout -q -b gone-merged
  printf 'gone\n' > gone.txt
  git add gone.txt
  git commit -q -m "gone work"
  git checkout -q main
  git merge --squash gone-merged >/dev/null
  git commit -q -m "squashed gone-merged"
  git branch -q -D gone-merged
}

# Create a task workspace directly, bypassing `jig task new`'s dirty-tree and
# branch checks: housekeeping tests need workspaces whose `branch` and
# `updated_at` are set to values the current checkout does not have.
# Usage: fixture_task <id> <branch> <status> [key:value ...]
fixture_task() {
  local id="$1" branch="$2" status="$3" kv key value today file
  shift 3
  today=$(date +%Y-%m-%d)
  file=".ai/workspace/tasks/$id/state"
  mkdir -p ".ai/workspace/tasks/$id"
  {
    printf 'task_id: %s\n' "$id"
    printf 'branch: %s\n' "$branch"
    printf 'status: %s\n' "$status"
    # A closed task always carries a recorded knowledge decision: `task set`
    # refuses the other combination (ADR-0030), so a fixture must not build it.
    if [ "$status" = consolidated ]; then
      printf 'knowledge_consolidated: true\n'
    else
      printf 'knowledge_consolidated: false\n'
    fi
    printf 'created_at: %s\n' "$today"
    printf 'updated_at: %s\n' "$today"
  } > "$file"
  # An override replaces its key rather than appending a second copy:
  # task_state_get reads the first match, so a duplicate `updated_at` would
  # silently defeat every ageing test.
  for kv in "$@"; do
    key="${kv%%:*}"
    value="${kv#*:}"
    if grep -q "^$key:" "$file"; then
      sed "s|^$key:.*|$key: $value|" "$file" > "$file.tmp"
      mv "$file.tmp" "$file"
    else
      printf '%s: %s\n' "$key" "$value" >> "$file"
    fi
  done
  printf '# %s\n' "$id" > ".ai/workspace/tasks/$id/task.md"
}

# Run jig from the framework source checkout.
jig() { "$JIG_BIN" "$@"; }

# Run jig from the copy installed into the current project.
jig_installed() { ".ai/scripts/jig" "$@"; }

# --- assertions --------------------------------------------------------------

fail() { printf 'ASSERT FAIL: %s\n' "$*"; exit 1; }

# skip <reason> — mark the running test skipped rather than passed or
# failed: print "SKIP: <reason>" and exit 77, the code tests/run.sh treats
# as a skip. A skip is not a pass (RULES.md, ADR-0013): it must stay
# distinguishable in the tally, the same invariant verify.sh already
# applies to a profile's exit code 2.
skip() {
  printf 'SKIP: %s\n' "$1"
  exit 77
}

# skip_unless_readonly_dirs — skip the calling test unless `chmod 555` on a
# directory actually blocks creating a file inside it on this filesystem.
# Windows/MSYS was seen to ignore the read-only bit for a directory owned by
# the running user, so a negative-path test that depends on the write
# failing must confirm the guarantee itself rather than assume POSIX
# permission semantics everywhere.
skip_unless_readonly_dirs() {
  local dir blocked=0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-ro-check.XXXXXX") || return 1
  chmod 555 "$dir"
  ( : > "$dir/probe" ) 2>/dev/null || blocked=1
  chmod 755 "$dir"
  rm -rf "$dir"
  [ "$blocked" -eq 1 ] || skip "chmod 555 does not make a directory read-only here"
}

# skip_unless_control_char_names — skip the calling test unless a file name
# containing a tab round-trips through `git status --porcelain`, which
# quotes such names as "bad\tname". NTFS under MSYS maps a tab in a file
# name to a private-use Unicode character instead of keeping the byte, so a
# test that plants a tab and expects to see it quoted back must confirm
# this filesystem can represent it at all.
skip_unless_control_char_names() {
  local dir name status
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-ctrl-check.XXXXXX") || return 1
  name=$(printf 'bad\tname')
  status=$(
    cd "$dir" || exit 1
    git init -q .
    : > "$name" 2>/dev/null
    git status --porcelain 2>/dev/null
  )
  rm -rf "$dir"
  case "$status" in
    *'bad\tname'*) ;;
    *) skip "this filesystem cannot represent a tab in a file name" ;;
  esac
}

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
#
# Captured through a file, never a pipe. bash 3.2 does not restart a write
# that SIGCHLD interrupts: a jig command whose own child exits while the pipe
# it writes to is full loses the line it was writing, with "printf: write
# error: Interrupted system call". Under load that happened to a test, which
# then missed a line it asserted on. A write to a regular file does not block,
# so nothing interrupts it. The command still runs in a subshell, as it did
# inside $(...), so an `exit` or a `cd` in it cannot reach the test.
run() {
  local out
  out=$(_run_out)
  set +e
  ( "$@" ) >"$out" 2>&1
  RC=$?
  set -e
  OUT=$(cat "$out")
  rm -f "$out"
  export OUT RC
}

# _run_out [suffix] — the file run() and its variants capture into: beside the
# test's directory, never inside it, since that directory is often the
# repository under test and `git status` would list the file. tests/run.sh
# removes it with the directory.
_run_out() {
  if [ -n "${JIG_TEST_TMP:-}" ]; then
    printf '%s.out%s\n' "$JIG_TEST_TMP" "${1:-}"
  else
    mktemp "${TMPDIR:-/tmp}/jig-run-out.XXXXXX"
  fi
}
