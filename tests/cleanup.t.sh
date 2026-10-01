#!/usr/bin/env bash
# shellcheck disable=SC2016 # script bodies are single-quoted on purpose
# tests/cleanup.t.sh — the process-wide exit cleanup (jig_cleanup_add, jig_on_exit in
# scripts/lib/common.sh): a temporary file or directory dies with the command that made
# it, whether the command ends, fails or is interrupted.

# _cleanup_script <body> — a script of its own that loads common.sh, so the test sees the
# real exit behaviour of a process rather than of the test's subshell.
_cleanup_script() {
  {
    printf '#!/usr/bin/env bash\nset -eu\n. "%s/scripts/lib/common.sh"\n' "$JIG_HOME"
    printf '%s\n' "$1"
  } > cleanup-script.sh
}

# _cleanup_wait_for <path> — poll for a path to appear, bounded by the clock.
_cleanup_wait_for() {
  local until=$((SECONDS + 30))
  while [ ! -e "$1" ] && [ "$SECONDS" -lt "$until" ]; do sleep 0.1; done
  [ -e "$1" ] || fail "never appeared: $1"
}

test_cleanup_removes_registered_paths_at_a_normal_exit() {
  _cleanup_script 'mkdir d; : > a.tmp.$$; : > d/x
jig_cleanup_add a.tmp.$$
jig_cleanup_add -d d
: > keep.$$'
  bash cleanup-script.sh
  [ -z "$(ls a.tmp.* 2>/dev/null)" ] || fail "registered file survived"
  assert_no_file d
  [ -n "$(ls keep.* 2>/dev/null)" ] || fail "an unregistered file was removed"
}

test_cleanup_runs_when_the_command_dies_of_an_error() {
  _cleanup_script ': > a.tmp.$$
jig_cleanup_add a.tmp.$$
false'
  run bash cleanup-script.sh
  assert_eq 1 "$RC"
  [ -z "$(ls a.tmp.* 2>/dev/null)" ] || fail "registered file survived set -e"
}

test_cleanup_keeps_the_exit_status() {
  _cleanup_script ': > a
jig_cleanup_add a
exit 7'
  run bash cleanup-script.sh
  assert_eq 7 "$RC"
  assert_no_file a
}

test_cleanup_registrations_accumulate_across_libraries() {
  # Two libraries sourced into one process, each registering its own: the second
  # must not replace the first (a `trap` per library did).
  _cleanup_script ': > one; : > two; : > three
jig_cleanup_add one
jig_on_exit "echo action-ran > acted"
jig_cleanup_add two
jig_cleanup_add one
jig_on_exit "echo action-ran > acted"
jig_cleanup_add three'
  bash cleanup-script.sh
  assert_no_file one
  assert_no_file two
  assert_no_file three
  assert_eq "action-ran" "$(cat acted)"
}

test_cleanup_registering_twice_is_one_entry() {
  _cleanup_script 'for i in 1 2 3; do : > f; jig_cleanup_add f; done
printf "%s" "$_JIG_EXIT_FILES" | grep -c "^f$" > count'
  bash cleanup-script.sh
  assert_eq 1 "$(cat count)"
}

test_cleanup_runs_on_sigterm() {
  _cleanup_script ': > a.tmp.$$
jig_cleanup_add a.tmp.$$
: > armed
while :; do sleep 0.1; done'
  bash cleanup-script.sh &
  local pid=$!
  _cleanup_wait_for armed
  kill -TERM "$pid"
  wait "$pid" 2>/dev/null || true
  [ -z "$(ls a.tmp.* 2>/dev/null)" ] || fail "registered file survived SIGTERM"
}

test_cleanup_runs_on_sigint() {
  # A background job of a non-interactive shell starts with SIGINT ignored, and an
  # ignored signal cannot be trapped; job control gives the job its dispositions back.
  _cleanup_script ': > a.tmp.$$
jig_cleanup_add a.tmp.$$
: > armed
while :; do sleep 0.1; done'
  set -m
  bash cleanup-script.sh &
  local pid=$!
  set +m
  _cleanup_wait_for armed
  kill -INT "$pid"
  local until=$((SECONDS + 5))
  while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$until" ]; do sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then
    # The runner itself was started with SIGINT ignored (a background job), and an
    # ignored signal is inherited by everything under it: nothing here can test it.
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    skip "SIGINT is ignored in this environment"
  fi
  wait "$pid" 2>/dev/null || true
  [ -z "$(ls a.tmp.* 2>/dev/null)" ] || fail "registered file survived SIGINT"
}

test_cleanup_a_subshell_never_removes_what_its_parent_registered() {
  # `$$` is the parent's pid in a subshell too; the subshell's own exit must not
  # take the parent's temporary files with it.
  _cleanup_script ': > parent.tmp.$$
jig_cleanup_add parent.tmp.$$
(
  : > child.tmp.$$
  jig_cleanup_add child.tmp.$$
)
[ -e parent.tmp.$$ ] || { echo parent-file-lost > verdict; exit 1; }
[ ! -e child.tmp.$$ ] || { echo child-file-left > verdict; exit 1; }
echo fine > verdict
x=$(: > sub.tmp.$$; jig_cleanup_add sub.tmp.$$; echo done)
[ -e parent.tmp.$$ ] || { echo parent-file-lost-2 > verdict; exit 1; }'
  run bash cleanup-script.sh
  assert_eq 0 "$RC"
  assert_eq fine "$(cat verdict)"
  [ -z "$(ls parent.tmp.* 2>/dev/null)" ] || fail "parent file survived its own exit"
}

test_cleanup_leaves_a_neighbour_with_another_pid_alone() {
  : > "a.tmp.1"
  _cleanup_script ': > a.tmp.$$
jig_cleanup_add a.tmp.$$'
  bash cleanup-script.sh
  assert_file a.tmp.1
}

test_cleanup_an_interrupted_state_write_leaves_no_temporary_file() {
  # The real case the task came from: a command killed between creating its
  # `.tmp.$$` file and the `mv` that publishes it. `mv` is stubbed to signal its
  # parent and then linger, so the interruption lands exactly there.
  fixture_jig_repo
  fixture_task cl "task/cl" active
  local bin="$PWD/stubbin"
  mkdir -p "$bin"
  printf '#!/bin/sh\nkill -TERM "$PPID"\nsleep 1\nexit 0\n' > "$bin/mv"
  chmod +x "$bin/mv"
  run env PATH="$bin:$PATH" "$JIG_BIN" task set cl class T1
  assert_eq 143 "$RC"
  [ -z "$(find .ai/workspace/tasks/cl -name '*.tmp.*')" ] \
    || fail "an interrupted write left: $(find .ai/workspace/tasks/cl -name '*.tmp.*')"
}
