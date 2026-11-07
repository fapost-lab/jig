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

# _cleanup_stub_long_mv <dir> <marker> — a `mv` that records its pid and sleeps long,
# so a jig command is parked in a foreground child when the signal arrives.
_cleanup_stub_long_mv() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho $$ > "%s"\nexec sleep 300\n' "$2" > "$1/mv"
  chmod +x "$1/mv"
}

# _cleanup_wait_nonempty <path> — the file exists before its content is written.
_cleanup_wait_nonempty() {
  local until=$((SECONDS + 30))
  while [ ! -s "$1" ] && [ "$SECONDS" -lt "$until" ]; do sleep 0.1; done
  [ -s "$1" ] || fail "stayed empty: $1"
}

test_cleanup_sigterm_ends_jig_parked_on_a_child_and_leaves_no_child() {
  # The trap alone is deferred until the foreground child ends: `kill` of a jig
  # waiting on a long `mv` did nothing for 300 s and the child outlived it.
  fixture_jig_repo
  fixture_task cl "task/cl" active
  _cleanup_stub_long_mv "$PWD/stubbin" "$PWD/child.pid"
  PATH="$PWD/stubbin:$PATH" "$JIG_BIN" task set cl class T1 &
  local pid=$!
  _cleanup_wait_for child.pid
  _cleanup_wait_nonempty child.pid
  local child
  child=$(cat child.pid)
  kill -TERM "$pid"
  local until=$((SECONDS + 15)) rc=0
  while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$until" ]; do sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" "$child" 2>/dev/null || true
    fail "jig still running 15 s after SIGTERM"
  fi
  wait "$pid" 2>/dev/null || rc=$?
  assert_eq 143 "$rc"
  if kill -0 "$child" 2>/dev/null; then
    kill -KILL "$child" 2>/dev/null || true
    fail "the child of an interrupted jig outlived it"
  fi
  [ -z "$(find .ai/workspace/tasks/cl -name '*.tmp.*')" ] \
    || fail "an interrupted write left: $(find .ai/workspace/tasks/cl -name '*.tmp.*')"
}

test_cleanup_sigterm_ends_jig_waiting_on_a_command_substitution() {
  # The 20-hour case: a long loop inside `$(...)` (a quadratic json_quote). The
  # parent only waits for that subshell, so its TERM trap never ran, and TERM sent
  # to the parent alone never reached the subshell.
  fixture_jig_repo
  cat > busy.sh <<'BUSY'
#!/usr/bin/env bash
set -eu
. "$JIG_HOME/scripts/lib/common.sh"
# A cleanup that takes a moment: the supervisor must wait for it, not KILL the
# tree the instant the job subshell (which has no trap and dies at once) is gone.
jig_on_exit 'sleep 0.5; echo cleaned > cleaned'
x=$(: > armed; while :; do :; done)
BUSY
  JIG_HOME="$JIG_HOME" bash -c '. "$JIG_HOME/scripts/lib/common.sh"; jig_supervise bash busy.sh' &
  local pid=$!
  _cleanup_wait_for armed
  local tree
  # The whole tree, as the product walks it: job, busy.sh and the `$(...)` loop.
  tree=$(. "$JIG_HOME/scripts/lib/common.sh"; _jig_descendants "$pid")
  [ "$(printf '%s\n' "$tree" | wc -l)" -ge 3 ] || fail "expected 3 processes under the supervisor, got: $tree"
  kill -TERM "$pid"
  local until=$((SECONDS + 15)) rc=0 p
  while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$until" ]; do sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then
    # shellcheck disable=SC2086
    kill -KILL "$pid" $tree 2>/dev/null || true
    fail "supervisor still running 15 s after SIGTERM"
  fi
  wait "$pid" 2>/dev/null || rc=$?
  assert_eq 143 "$rc"
  for p in $tree; do
    if kill -0 "$p" 2>/dev/null; then
      kill -KILL "$p" 2>/dev/null || true
      fail "process $p under the interrupted command outlived it"
    fi
  done
  assert_file cleaned
}

# _cleanup_stub_failing_ps <dir> — a `ps` that fails the way Git Bash's does on `-o`.
_cleanup_stub_failing_ps() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "ps: unknown option -- o" >&2\nexit 1\n' > "$1/ps"
  chmod +x "$1/ps"
}

test_cleanup_sigterm_ends_the_supervisor_when_the_tree_cannot_be_read() {
  # Under Git Bash `ps -o` fails; under `set -e -o pipefail` that failure killed
  # the signal handler with status 1 before it signalled anything, and the job
  # ran on as an orphan. With no tree to read, the job alone gets the signal.
  # job.sh's parent is the job subshell itself: that is the process that must end.
  _cleanup_stub_failing_ps "$PWD/stubbin"
  mkdir noproc
  printf 'echo $PPID > job.pid\necho $$ > child.pid\nexec sleep 300\n' > job.sh
  PATH="$PWD/stubbin:$PATH" bash -c 'set -eu; set -o pipefail
. "$JIG_HOME/scripts/lib/common.sh"
_JIG_PROC_ROOT="$PWD/noproc"
jig_supervise sh job.sh' &
  local sup=$!
  _cleanup_wait_nonempty child.pid
  local child
  child=$(cat child.pid)
  kill -TERM "$sup"
  local until=$((SECONDS + 15)) rc=0
  while kill -0 "$sup" 2>/dev/null && [ "$SECONDS" -lt "$until" ]; do sleep 0.1; done
  if kill -0 "$sup" 2>/dev/null; then
    kill -KILL "$sup" "$child" 2>/dev/null || true
    fail "supervisor still running 15 s after SIGTERM"
  fi
  wait "$sup" 2>/dev/null || rc=$?
  # The job is checked before its child is killed: a dead child ends the job too.
  local job alive=0
  job=$(cat job.pid)
  if kill -0 "$job" 2>/dev/null; then alive=1; fi
  # Without a tree the job's own child outlives it: that is the degraded case.
  kill -KILL "$job" "$child" 2>/dev/null || true
  assert_eq 143 "$rc"
  [ "$alive" = 0 ] || fail "the job outlived the supervisor: it was never signalled"
}

test_cleanup_descendants_read_proc_where_ps_has_no_o() {
  # Cygwin and MSYS give each process a /proc/<pid>/ppid; the tree is read from
  # there when `ps -o` fails.
  _cleanup_stub_failing_ps "$PWD/stubbin"
  local d
  for d in 100:1 200:100 300:200 400:1; do
    mkdir -p "proc/${d%%:*}"
    printf '%s\n' "${d##*:}" > "proc/${d%%:*}/ppid"
  done
  mkdir -p proc/self
  local out
  out=$(PATH="$PWD/stubbin:$PATH" bash -c 'set -eu; set -o pipefail
. "$JIG_HOME/scripts/lib/common.sh"
_JIG_PROC_ROOT="$PWD/proc"
_jig_descendants 100' | sort | tr '\n' ' ')
  assert_eq "200 300 " "$out"
}

# _cleanup_ping_pids — the Windows pids of the PING.EXE processes now running.
_cleanup_ping_pids() {
  MSYS2_ARG_CONV_EXCL='*' tasklist /FI "IMAGENAME eq PING.EXE" /FO CSV /NH 2>/dev/null |
    awk -F'","' '/^"PING\.EXE"/ { print $2 }' | sort
}

# On Git Bash a native program hears no signal; what stops it is the MSYS2
# runtime: the MSYS stub that execed it, on a fatal signal, ends the native
# program's whole Windows tree (exit_process_tree, msys2-runtime exceptions.cc).
# The stub gets that signal only because the supervisor reads the tree from
# /proc/<pid>/ppid where ps has no -o. So a native grandchild (ping.exe under
# cmd.exe) of an interrupted command must not outlive it; this goes red if the
# /proc walk is lost or the runtime stops ending the native tree.
test_cleanup_sigterm_ends_a_native_grandchild_under_git_bash() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) ;;
    *) skip "needs Git Bash: native Windows programs, taskkill and tasklist" ;;
  esac
  command -v tasklist >/dev/null 2>&1 || skip "no tasklist on PATH"
  local before ours="" until
  before=$(_cleanup_ping_pids)
  MSYS2_ARG_CONV_EXCL='*' bash -c 'set -eu; set -o pipefail
. "$JIG_HOME/scripts/lib/common.sh"
jig_supervise cmd.exe /c ping -n 300 127.0.0.1' >/dev/null 2>&1 &
  local sup=$!
  until=$((SECONDS + 30))
  while [ -z "$ours" ] && [ "$SECONDS" -lt "$until" ]; do
    sleep 0.2
    ours=$(comm -13 <(printf '%s\n' "$before") <(_cleanup_ping_pids))
  done
  [ -n "$ours" ] || { kill -KILL "$sup" 2>/dev/null || true; fail "ping.exe never started"; }
  kill -TERM "$sup"
  until=$((SECONDS + 15))
  while kill -0 "$sup" 2>/dev/null && [ "$SECONDS" -lt "$until" ]; do sleep 0.1; done
  local rc=0
  kill -KILL "$sup" 2>/dev/null || true
  wait "$sup" 2>/dev/null || rc=$?
  local left
  until=$((SECONDS + 5))
  left=$(comm -12 <(printf '%s\n' "$ours") <(_cleanup_ping_pids))
  while [ -n "$left" ] && [ "$SECONDS" -lt "$until" ]; do
    sleep 0.2
    left=$(comm -12 <(printf '%s\n' "$ours") <(_cleanup_ping_pids))
  done
  local p
  for p in $left; do MSYS2_ARG_CONV_EXCL='*' taskkill /F /PID "$p" >/dev/null 2>&1 || true; done
  assert_eq 143 "$rc"
  [ -z "$left" ] || fail "ping.exe outlived the interrupted command: $left"
}

test_cleanup_supervise_passes_the_exit_status_and_stdin_through() {
  _cleanup_script 'jig_supervise bash -c '"'"'read -r l; echo "got:$l"; exit 7'"'"''
  run bash -c 'echo hello | bash cleanup-script.sh'
  assert_eq 7 "$RC"
  assert_contains "$OUT" "got:hello"
}

test_cleanup_supervise_runs_the_exit_cleanup_of_a_command_that_runs_off_its_end() {
  # bash 3.2 skips the EXIT trap of a background subshell that ends without an
  # `exit`; the supervised command is a function, which does exactly that.
  _cleanup_script 'work() { : > a.tmp.$$; jig_cleanup_add a.tmp.$$; jig_on_exit "echo ran > ran"; }
jig_supervise work'
  run bash cleanup-script.sh
  assert_eq 0 "$RC"
  assert_eq ran "$(cat ran)"
  [ -z "$(ls a.tmp.* 2>/dev/null)" ] || fail "registered file survived"
}
