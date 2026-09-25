# Tests for `jig task` (domains/task; schemas/state.md; ARCHITECTURE.md,
# Scripts layout; ADR-0005; ADR-0008).
# shellcheck shell=bash

task_setup() {
  fixture_jig_repo
}

# task_setup, then commit everything `jig init` left untracked so the
# working tree is clean. Tests that exercise `--stash` need a clean baseline
# to make their own dirty change against: `git stash push -u` sweeps up
# every untracked, non-ignored file, and `jig init`'s own output (config.yaml,
# AGENTS.md, .ai/scripts/...) is untracked in the plain fixture — stashing it
# alongside the deliberate test change would delete .ai/config.yaml and make
# every later `jig` command fail `jig_require_init`.
task_setup_clean() {
  task_setup
  git add -A
  git commit -q -m "jig init snapshot"
}

# Turn branch-per-task off, the only way two started tasks can share a branch.
_task_share_one_branch() {
  sed 's|^git.branch_per_task:.*|git.branch_per_task: false|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml
}

# File a task and start it: what a single `task new` used to do.
task_started() {
  jig task new "$@" >/dev/null
  jig task start "$1" >/dev/null
}

# Run a jig command, capturing stdout in OUT and stderr in ERR separately
# (unlike run(), which merges both into OUT). task_current's contract
# (design §2) depends on which stream each part lands on.
# Captured through files for the reason run() gives.
run_split() {
  local out err
  out=$(_run_out)
  err=$(_run_out .err)
  ( "$@" ) >"$out" 2>"$err"
  RC=$?
  OUT=$(cat "$out")
  ERR=$(cat "$err")
  rm -f "$out" "$err"
  export OUT RC ERR
}

# --- new --------------------------------------------------------------------

test_task_new_creates_state_with_expected_keys_in_order() {
  task_setup
  run jig task new T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/workspace/tasks/T-1"

  assert_file .ai/workspace/tasks/T-1/state
  # Filing writes only what it knows: no branch, no fork point.
  local keys
  keys=$(sed -n 's/^\([a-z_]*\):.*/\1/p' .ai/workspace/tasks/T-1/state | tr '\n' ' ')
  assert_eq "task_id status knowledge_consolidated created_at updated_at " "$keys"

  assert_file_contains .ai/workspace/tasks/T-1/state "task_id: T-1"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: false"
  assert_file_contains .ai/workspace/tasks/T-1/state "created_at: $(date +%Y-%m-%d)"
  assert_file_contains .ai/workspace/tasks/T-1/state "updated_at: $(date +%Y-%m-%d)"
}

test_task_new_with_class_and_domains_order() {
  task_setup
  run jig task new T-1 --class T2 --domains flow,triggers
  assert_eq 0 "$RC"

  local keys
  keys=$(sed -n 's/^\([a-z_]*\):.*/\1/p' .ai/workspace/tasks/T-1/state | tr '\n' ' ')
  assert_eq "task_id class status knowledge_consolidated domains created_at updated_at " "$keys"
  assert_file_contains .ai/workspace/tasks/T-1/state "class: T2"
  assert_file_contains .ai/workspace/tasks/T-1/state "domains: flow,triggers"
}

test_task_new_writes_task_md_from_template() {
  task_setup
  run jig task new T-1
  assert_eq 0 "$RC"
  assert_file .ai/workspace/tasks/T-1/task.md
  assert_file_contains .ai/workspace/tasks/T-1/task.md "# T-1"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/task.md)" "{{TASK_ID}}"
  assert_file_contains .ai/workspace/tasks/T-1/task.md "## Goal"
}

test_task_new_via_installed_copy_falls_back_to_builtin_template() {
  task_setup
  run jig_installed task new T-1
  assert_eq 0 "$RC"
  assert_file .ai/workspace/tasks/T-1/task.md
  assert_file_contains .ai/workspace/tasks/T-1/task.md "# T-1"
  assert_file_contains .ai/workspace/tasks/T-1/task.md "## Goal"
  assert_file_contains .ai/workspace/tasks/T-1/task.md "## Notes"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/task.md)" "{{TASK_ID}}"
}

test_task_new_from_file_writes_task_md() {
  task_setup
  printf '# Existing doc\n\nAlready written by the user.\n' > from.md
  run jig task new T-1 --from from.md
  assert_eq 0 "$RC"
  assert_file .ai/workspace/tasks/T-1/task.md
  assert_file_contains .ai/workspace/tasks/T-1/task.md "Already written by the user."
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/task.md)" "## Goal"
}

test_task_new_from_stdin() {
  task_setup
  run bash -c 'printf "# From stdin\n\nBody text.\n" | "$JIG_BIN" task new T-1 --from -'
  assert_eq 0 "$RC"
  assert_file .ai/workspace/tasks/T-1/task.md
  assert_file_contains .ai/workspace/tasks/T-1/task.md "# From stdin"
  assert_file_contains .ai/workspace/tasks/T-1/task.md "Body text."
}

test_task_new_from_file_substitutes_task_id() {
  task_setup
  printf '# {{TASK_ID}}\n\nTask {{TASK_ID}} details.\n' > from.md
  run jig task new T-9 --from from.md
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-9/task.md "# T-9"
  assert_file_contains .ai/workspace/tasks/T-9/task.md "Task T-9 details."
  assert_not_contains "$(cat .ai/workspace/tasks/T-9/task.md)" "{{TASK_ID}}"
}

test_task_new_from_file_byte_for_byte_fidelity() {
  task_setup
  # Single quotes are deliberate: this is literal fixture content (backslash,
  # &, $var, backticks, a tab, non-ASCII), not code meant to expand.
  # shellcheck disable=SC2016
  printf 'first line with a\\b in it\nan & ampersand\na $var literal\nbackticks `echo hi` inline\na\ttab\tcharacter\nUTF-8: Привіт 世界 café\n' > from.md
  run jig task new T-1 --from from.md
  assert_eq 0 "$RC"
  assert_eq "$(cat from.md)" "$(cat .ai/workspace/tasks/T-1/task.md)" "task.md is not byte-for-byte identical to the source"
}

test_task_new_from_missing_file_dies_no_workspace() {
  task_setup
  run jig task new T-1 --from does-not-exist.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no such file"
  assert_no_file .ai/workspace/tasks/T-1
}

test_task_new_from_directory_dies_no_workspace() {
  task_setup
  mkdir somedir
  run jig task new T-1 --from somedir
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a regular file"
  assert_no_file .ai/workspace/tasks/T-1
}

test_task_new_from_without_value_dies() {
  task_setup
  run jig task new T-1 --from
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--from requires a value"
  assert_no_file .ai/workspace/tasks/T-1
}

test_task_new_from_with_class_and_domains() {
  task_setup
  printf 'Doc body.\n' > from.md
  run jig task new T-1 --class T2 --domains flow,triggers --from from.md
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "class: T2"
  assert_file_contains .ai/workspace/tasks/T-1/state "domains: flow,triggers"
  assert_file_contains .ai/workspace/tasks/T-1/task.md "Doc body."
  local keys
  keys=$(sed -n 's/^\([a-z_]*\):.*/\1/p' .ai/workspace/tasks/T-1/state | tr '\n' ' ')
  assert_eq "task_id class status knowledge_consolidated domains created_at updated_at " "$keys"
}

test_task_new_duplicate_id_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task new T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already exists"
}

test_task_new_invalid_id_dies() {
  task_setup
  run jig task new "bad id!"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid task id"
  assert_no_file ".ai/workspace/tasks/bad id!"
}

# An id is the first argument of every subcommand, so a leading dash is a flag
# in the wrong place; accepting it once filed a workspace named `--help`.
test_task_new_leading_dash_id_dies_no_workspace() {
  task_setup
  local id
  for id in -x --bogus -; do
    run jig task new "$id"
    assert_eq 1 "$RC" "task new $id"
    assert_contains "$OUT" "task new: invalid task id: $id"
    assert_no_file ".ai/workspace/tasks/$id"
  done
}

# The same rule holds where the path is built, for subcommands that never
# call _task_valid_id themselves.
test_task_subcommands_reject_leading_dash_id() {
  task_setup
  run jig task show -x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid task id: -x"
  run jig task set -x class T1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid task id: -x"
  assert_no_file ".ai/workspace/tasks/-x"
}

# A workspace filed under a dash-led name before the rule existed must not
# break the listings that walk every directory.
test_task_walks_skip_workspace_with_invalid_id() {
  task_setup
  task_started T-1
  mkdir -p -- ".ai/workspace/tasks/--help"
  sed 's/^task_id: .*/task_id: --help/' .ai/workspace/tasks/T-1/state > ".ai/workspace/tasks/--help/state"
  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "T-1"
  assert_not_contains "$OUT" "--help"
  run_split jig task current
  assert_eq 0 "$RC"
  assert_eq "T-1" "$OUT"
}

test_task_new_invalid_class_dies() {
  task_setup
  run jig task new T-1 --class T9
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid class"
  assert_no_file .ai/workspace/tasks/T-1
}

test_task_new_invalid_domains_dies() {
  task_setup
  run jig task new T-1 --domains "Not_Valid"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid domains"
}

test_task_start_on_detached_head_records_detached() {
  # The `detached` fallback survives where it still applies: a project with
  # branch-per-task off records the checkout's branch, and a detached HEAD
  # has none.
  task_setup
  _task_share_one_branch
  jig task new T-1 >/dev/null
  git checkout -q --detach main

  run jig task start T-1
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: detached"
}

test_task_new_without_init_dies() {
  fixture_repo
  run jig task new T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

test_task_new_no_state_tmp_left_behind() {
  task_setup
  jig task new T-1 >/dev/null
  run bash -c 'ls .ai/workspace/tasks/T-1/state.tmp.* 2>/dev/null'
  assert_eq "" "$OUT"
}

# --- set ----------------------------------------------------------------------

test_task_set_class() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 class T3
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "class: T3"
}

test_task_set_status() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

test_task_set_knowledge_consolidated() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: true"
}

test_task_set_domains_when_absent_inserts_before_created_at() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 domains flow,triggers
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "domains: flow,triggers"
  local keys
  keys=$(sed -n 's/^\([a-z_]*\):.*/\1/p' .ai/workspace/tasks/T-1/state | tr '\n' ' ')
  assert_eq "task_id status knowledge_consolidated domains created_at updated_at " "$keys"
}

test_task_set_invalid_class_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 class nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid class"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "class: nope"
}

test_task_set_invalid_status_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 status nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid status"
}

test_task_set_invalid_knowledge_consolidated_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 knowledge_consolidated maybe
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid knowledge_consolidated"
}

# ADR-0030: closing a task (status consolidated) is refused until its
# knowledge decision is recorded (knowledge_consolidated true).
test_task_set_status_consolidated_without_knowledge_consolidated_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 status consolidated
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires knowledge_consolidated true"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "status: consolidated"
}

test_task_set_status_consolidated_succeeds_after_knowledge_consolidated() {
  task_setup
  jig task new T-1 >/dev/null
  jig task set T-1 knowledge_consolidated true >/dev/null
  run jig task set T-1 status consolidated
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: consolidated"

  # Idempotent: re-setting status consolidated on an already-consolidated
  # task whose flag is still true must still succeed.
  run jig task set T-1 status consolidated
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: consolidated"
}

test_task_set_knowledge_consolidated_false_on_consolidated_task_dies() {
  task_setup
  jig task new T-1 >/dev/null
  jig task set T-1 knowledge_consolidated true >/dev/null
  jig task set T-1 status consolidated >/dev/null
  run jig task set T-1 knowledge_consolidated false
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge_consolidated cannot be false on a consolidated task"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: true"
}

test_task_set_invalid_domains_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 domains "Bad Domain"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid domains"
}

test_task_set_refuses_task_id() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 task_id T-2
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_set_refuses_branch() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 branch other
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_set_refuses_created_at() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 created_at 2020-01-01
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_set_refuses_updated_at() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 updated_at 2020-01-01
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_set_refuses_pause_keys() {
  task_setup
  jig task new T-1 >/dev/null
  local key
  for key in paused paused_at paused_reason paused_stash; do
    run jig task set T-1 "$key" x
    assert_eq 1 "$RC" "task set accepted key [$key]"
    assert_contains "$OUT" "not writable"
  done
}

test_task_set_unknown_key_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 bogus value
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown key"
}

test_task_set_unknown_task_dies() {
  task_setup
  run jig task set NOPE status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task"
}

test_task_set_refreshes_updated_at() {
  task_setup
  jig task new T-1 >/dev/null
  sed 's/^updated_at:.*/updated_at: 2020-01-01/' .ai/workspace/tasks/T-1/state > .ai/workspace/tasks/T-1/state.new
  mv .ai/workspace/tasks/T-1/state.new .ai/workspace/tasks/T-1/state
  assert_file_contains .ai/workspace/tasks/T-1/state "updated_at: 2020-01-01"

  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "updated_at: $(date +%Y-%m-%d)"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "updated_at: 2020-01-01"
}

test_task_set_no_state_tmp_left_behind() {
  task_setup
  jig task new T-1 >/dev/null
  jig task set T-1 status ready >/dev/null
  run bash -c 'ls .ai/workspace/tasks/T-1/state.tmp.* 2>/dev/null'
  assert_eq "" "$OUT"
}

# --- abandon --------------------------------------------------------------------

test_task_abandon_sets_status() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task abandon T-1
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: abandoned"
}

# --- list -------------------------------------------------------------------------

test_task_list_empty() {
  task_setup
  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no tasks"
}

test_task_list_ordering_and_fields() {
  task_setup
  task_started T-2
  task_started T-1 --class T1
  git checkout -q -b other
  # T-3 is started on a branch this test chose, to show that the listing
  # includes a task belonging to a *different* branch.
  _task_share_one_branch
  task_started T-3

  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "T-1 class=T1 status=active branch=task/T-1"
  assert_contains "$OUT" "T-2 class=- status=active branch=task/T-2"
  assert_contains "$OUT" "T-3 class=- status=active branch=other"

  # sorted by id
  local first second third
  first=$(printf '%s\n' "$OUT" | sed -n 1p | cut -d' ' -f1)
  second=$(printf '%s\n' "$OUT" | sed -n 2p | cut -d' ' -f1)
  third=$(printf '%s\n' "$OUT" | sed -n 3p | cut -d' ' -f1)
  assert_eq "T-1" "$first"
  assert_eq "T-2" "$second"
  assert_eq "T-3" "$third"
}

# --- show ---------------------------------------------------------------------------

test_task_show_prints_state_verbatim() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  run jig task show T-1
  assert_eq 0 "$RC"
  assert_eq "$(cat .ai/workspace/tasks/T-1/state)" "$OUT"
}

test_task_show_unknown_dies() {
  task_setup
  run jig task show NOPE
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task"
}

# --- current (design §1, §2) ---------------------------------------------------------

test_task_current_matches_branch() {
  task_setup
  task_started T-1
  run jig task current
  assert_eq 0 "$RC"
  assert_eq "T-1" "$OUT"
}

test_task_current_none_for_branch_exits_1() {
  task_setup
  jig task new T-1 >/dev/null
  git checkout -q -b other
  run jig task current
  assert_eq 1 "$RC"
}

test_task_current_no_tasks_exits_1() {
  task_setup
  run jig task current
  assert_eq 1 "$RC"
}

test_task_current_no_candidates_stderr_message() {
  task_setup
  run jig task current
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no current task for branch: main"
}

test_task_current_excludes_abandoned() {
  task_setup
  jig task new T-1 >/dev/null
  jig task abandon T-1 >/dev/null
  run jig task current
  assert_eq 1 "$RC"
}

test_task_current_excludes_consolidated() {
  task_setup
  jig task new T-1 >/dev/null
  jig task set T-1 knowledge_consolidated true >/dev/null
  jig task set T-1 status consolidated >/dev/null
  run jig task current
  assert_eq 1 "$RC"
}

test_task_current_excludes_paused_task_from_candidates() {
  task_setup
  # Ambiguity needs two *started* tasks sharing one branch, which only a
  # project that turned branch-per-task off can produce. That it takes this
  # much setup is the point of the feature.
  _task_share_one_branch
  task_started T-1
  task_started T-2
  jig task pause T-2 >/dev/null
  # With T-2 paused, T-1 is the only candidate left: deterministic, not
  # ambiguous, even though both share the branch and an active-ish status.
  run jig task current
  assert_eq 0 "$RC"
  assert_eq "T-1" "$OUT"
}

test_task_current_several_candidates_exits_2_lists_both_nothing_on_stdout() {
  task_setup
  # Two started tasks on one branch: only reachable with branch-per-task off.
  _task_share_one_branch
  task_started T-1
  task_started T-2
  run_split jig task current
  assert_eq 2 "$RC"
  assert_eq "" "$OUT" "stdout must be empty on ambiguous current"
  assert_contains "$ERR" "T-1"
  assert_contains "$ERR" "T-2"
}

# --- CLI plumbing ---------------------------------------------------------------------

test_task_no_subcommand_dies_with_usage() {
  task_setup
  run jig task
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task"
}

test_task_unknown_subcommand_dies_with_usage() {
  task_setup
  run jig task bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task"
}

test_task_help_prints_usage() {
  task_setup
  local arg
  for arg in help -h --help; do
    run_split jig task "$arg"
    assert_eq 0 "$RC" "task $arg"
    assert_contains "$OUT" "usage: jig task new|start"
    assert_eq "" "$ERR"
  done
}

test_task_subcommand_help_prints_usage_and_changes_nothing() {
  task_setup
  local sub arg
  for sub in new start set abandon pause resume list show current changes artifacts; do
    for arg in -h --help; do
      run_split jig task "$sub" "$arg"
      assert_eq 0 "$RC" "task $sub $arg"
      assert_contains "$OUT" "usage: jig task $sub"
      assert_eq "" "$ERR" "task $sub $arg"
    done
  done
  assert_no_file ".ai/workspace/tasks/--help"
  assert_no_file ".ai/workspace/tasks/-h"
  assert_eq "no tasks" "$(jig task list)"
}

test_task_unknown_subcommand_help_dies_with_usage() {
  task_setup
  run jig task bogus --help
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task new|start"
}

test_task_subcommands_reject_path_traversal_ids() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  # A state file outside the tasks directory must never be touched.
  printf 'status: active\n' > "$JIG_TEST_TMP/state"
  local before
  before=$(cat "$JIG_TEST_TMP/state")
  for bad in .. ../../x .hidden . 'a b' ''; do
    run jig task set "$bad" status ready
    assert_eq 1 "$RC" "task set accepted id [$bad]"
    assert_contains "$OUT" "invalid task id"
    run jig task abandon "$bad"
    assert_eq 1 "$RC" "task abandon accepted id [$bad]"
    run jig task show "$bad"
    assert_eq 1 "$RC" "task show accepted id [$bad]"
    run jig task new "$bad"
    assert_eq 1 "$RC" "task new accepted id [$bad]"
    run jig task pause "$bad" --stash
    assert_eq 1 "$RC" "task pause accepted id [$bad]"
    run jig task resume "$bad"
    assert_eq 1 "$RC" "task resume accepted id [$bad]"
  done
  assert_eq "$before" "$(cat "$JIG_TEST_TMP/state")" "file outside tasks dir was modified"
  assert_no_file .ai/workspace/tasks/.hidden
}

# --- pause / resume (design §3, §4, §5) -----------------------------------------------

test_task_pause_sets_fields() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task pause T-1
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused_at: $(date +%Y-%m-%d)"
}

test_task_pause_unknown_task_dies() {
  task_setup
  run jig task pause NOPE
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task"
}

test_task_pause_already_paused_dies() {
  task_setup
  jig task new T-1 >/dev/null
  jig task pause T-1 >/dev/null
  run jig task pause T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already paused"
}

test_task_pause_reason() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task pause T-1 --reason "waiting on design review"
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused_reason: waiting on design review"
}

test_task_pause_stash_records_commit_sha_and_leaves_tree_clean() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'dirty change\n' >> README.md

  run jig task pause T-1 --stash
  assert_eq 0 "$RC"

  local sha
  sha=$(sed -n 's/^paused_stash:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  [ -n "$sha" ] || fail "paused_stash was not recorded"
  assert_eq "commit" "$(git cat-file -t "$sha")" "paused_stash is not a commit"
  assert_eq "" "$(git status --porcelain)" "working tree not clean after --stash"
}

test_task_pause_stash_on_clean_tree_records_nothing() {
  task_setup_clean
  jig task new T-1 >/dev/null

  run jig task pause T-1 --stash
  assert_eq 0 "$RC"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused_stash:"
  assert_eq "" "$(git stash list)" "a stash entry was created on a clean tree"
}

test_task_resume_restores_content_byte_for_byte_and_keeps_stash_entry() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'dirty change\n' >> README.md
  local modified_content
  modified_content=$(cat README.md)

  jig task pause T-1 --stash >/dev/null
  assert_not_contains "$(cat README.md)" "dirty change"

  run jig task resume T-1
  assert_eq 0 "$RC"
  assert_eq "$modified_content" "$(cat README.md)" "resume did not restore content byte-for-byte"

  # apply, never pop: the stash entry survives as a backup.
  assert_contains "$(git stash list)" "jig: T-1"

  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused: true"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused_at:"
  # design §4 clears only paused/paused_at/paused_reason; paused_stash stays
  # as the record of which kept stash entry belongs to this resume.
  assert_file_contains .ai/workspace/tasks/T-1/state "paused_stash:"
}

test_task_resume_not_paused_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task resume T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not paused"
}

test_task_resume_wrong_branch_refuses_and_changes_nothing() {
  task_setup_clean
  task_started T-1
  jig task pause T-1 >/dev/null
  git checkout -q -b other

  run jig task resume T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "switch to task/T-1 first"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
}

test_task_resume_failed_apply_leaves_paused_set_and_exits_nonzero() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'line one\n' > conflict.txt
  git add conflict.txt
  git commit -q -m "add conflict.txt"

  printf 'task change\n' > conflict.txt
  jig task pause T-1 --stash >/dev/null
  # conflict.txt is back to "line one"; make an incompatible edit while
  # paused so the stash apply's 3-way merge cannot resolve cleanly.
  printf 'different change\n' > conflict.txt

  run jig task resume T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "stash apply failed"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
}

# --- resume overlap is computed against the task's own base (ADR-0039) --------

test_task_resume_overlap_computed_against_task_base() {
  # A task cut from an epic branch, not from main. A file the epic branch
  # keeps changing after the fork overlaps; a change on main, which the task
  # never forked from, must not be mistaken for overlap.
  task_setup_clean
  git checkout -q -b epic/x
  printf 'v1\n' > shared.txt
  git add shared.txt
  git commit -q -m "epic: add shared.txt"

  git checkout -q -b task/ov epic/x
  printf 'v1
v2\n' > shared.txt
  git add shared.txt
  git commit -q -m "task: touch shared.txt"

  git checkout -q epic/x
  printf 'v1
v3\n' > shared.txt
  git add shared.txt
  git commit -q -m "epic: touch shared.txt again"

  git checkout -q main
  printf 'unrelated\n' > main-only.txt
  git add main-only.txt
  git commit -q -m "main: unrelated change"

  git checkout -q task/ov
  fixture_task ov "task/ov" active "base_branch:epic/x" "paused:true" "paused_at:$(date +%Y-%m-%d)"

  run jig task resume ov
  assert_eq 0 "$RC"
  assert_contains "$OUT" "overlap: 1 files you changed also changed on epic/x"
  assert_contains "$OUT" "shared.txt"
}

test_task_resume_overlap_falls_back_to_configured_base_without_one_recorded() {
  # Same shape as above, but the task carries no base_branch (a workspace
  # from before the field existed, or one never cut from an epic). Judged
  # against main, the epic's own change to shared.txt is not overlap.
  task_setup_clean
  git checkout -q -b epic/x
  printf 'v1\n' > shared.txt
  git add shared.txt
  git commit -q -m "epic: add shared.txt"

  git checkout -q -b task/ov epic/x
  printf 'v1
v2\n' > shared.txt
  git add shared.txt
  git commit -q -m "task: touch shared.txt"

  git checkout -q epic/x
  printf 'v1
v3\n' > shared.txt
  git add shared.txt
  git commit -q -m "epic: touch shared.txt again"

  git checkout -q task/ov
  fixture_task ov "task/ov" active "paused:true" "paused_at:$(date +%Y-%m-%d)"

  run jig task resume ov
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "overlap:"
}

# --- list (paused marker, design §2/§5) -----------------------------------------------

test_task_list_shows_paused_marker() {
  task_setup
  task_started T-1
  jig task new T-2 >/dev/null
  jig task pause T-1 >/dev/null

  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "T-1 class=- status=active branch=task/T-1 paused"
  assert_not_contains "$OUT" "T-2 class=- status=active branch=main paused"
}

# --- dirty-tree refusal (design §6): at start, never at filing ----------------------

test_task_new_files_on_a_dirty_tree() {
  # Filing a task for later in the middle of other work is the case the
  # new/start split exists for; the uncommitted work must stay where it is.
  task_setup
  task_started T-1
  printf 'dirty\n' >> README.md

  run jig task new T-2
  assert_eq 0 "$RC"
  assert_file .ai/workspace/tasks/T-2/state
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  assert_contains "$(git status --porcelain)" "README.md"
}

test_task_start_refusal_names_the_likely_owner() {
  task_setup
  # Only a *started* task owns a branch, so only a started one can be named
  # as the likely owner of uncommitted work.
  task_started T-1
  printf 'dirty\n' >> README.md
  jig task new T-2 >/dev/null

  run jig task start T-2
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig task pause T-1 --stash"
  # task start has no override, so the message must not offer one.
  assert_not_contains "$OUT" "--force"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  if grep -q '^branch:' .ai/workspace/tasks/T-2/state; then
    fail "a refused start recorded a branch"
  fi
}

test_task_start_refuses_a_dirty_tree_on_a_shared_branch() {
  # With one shared branch nothing is cut, but base_commit would still name
  # a point the uncommitted work already sits on top of.
  task_setup_clean
  _task_share_one_branch
  git add .ai/config.yaml
  git commit -q -m "share one branch"
  jig task new T-1 >/dev/null
  printf 'dirty\n' >> README.md

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "uncommitted changes"
  if grep -q '^base_commit:' .ai/workspace/tasks/T-1/state; then
    fail "a refused start recorded base_commit"
  fi
}

test_task_start_dies_naming_the_cause_when_repository_has_no_commits() {
  # git cannot cut a branch with nothing to fork from; "could not create
  # branch" would name the symptom, not the cause.
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  # Roll back to before fixture_repo's own commit: an unborn HEAD, the same
  # as a brand-new repository nobody has committed to yet.
  git update-ref -d refs/heads/main
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task start: the repository has no commits yet; commit something first (even a README), then start the task"
  if grep -q '^base_commit:' .ai/workspace/tasks/T-1/state; then
    fail "a refused start recorded base_commit"
  fi
}

test_task_start_worktree_dies_naming_the_cause_when_repository_has_no_commits() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  git update-ref -d refs/heads/main
  jig task new T-1 >/dev/null

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task start: the repository has no commits yet; commit something first (even a README), then start the task"
  if grep -q '^base_commit:' .ai/workspace/tasks/T-1/state; then
    fail "a refused start recorded base_commit"
  fi
}

test_task_new_untracked_only_does_not_block() {
  task_setup
  printf 'build output\n' > build-output.tmp

  run jig task new T-1
  assert_eq 0 "$RC"
  assert_file .ai/workspace/tasks/T-1/state
}

test_task_list_hides_finished_by_default() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  run jig task new live-one
  run jig task new done-one
  run jig task set done-one knowledge_consolidated true
  run jig task set done-one status consolidated
  run jig task new gone-one
  run jig task set gone-one status abandoned

  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "live-one"
  assert_not_contains "$OUT" "done-one"
  assert_not_contains "$OUT" "gone-one"
  assert_contains "$OUT" "(2 finished; jig task list --all)"
}

test_task_list_all_shows_everything() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  run jig task new live-one
  run jig task new done-one
  run jig task set done-one knowledge_consolidated true
  run jig task set done-one status consolidated

  run jig task list --all
  assert_eq 0 "$RC"
  assert_contains "$OUT" "live-one"
  assert_contains "$OUT" "done-one"
  assert_not_contains "$OUT" "finished; jig task list"
}

test_task_list_keeps_paused_tasks_visible() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  run jig task new dormant
  run jig task pause dormant --reason "waiting"
  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dormant"
  assert_contains "$OUT" "paused"
}

test_task_list_status_filter() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  run jig task new live-one
  run jig task new done-one
  run jig task set done-one knowledge_consolidated true
  run jig task set done-one status consolidated

  run jig task list --status consolidated
  assert_eq 0 "$RC"
  assert_contains "$OUT" "done-one"
  assert_not_contains "$OUT" "live-one"

  run jig task list --status nonsense
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid status"

  run jig task list --status
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires a value"
}

test_task_list_reports_no_live_tasks() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  run jig task new done-one
  run jig task set done-one knowledge_consolidated true
  run jig task set done-one status consolidated
  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no live tasks (1 finished"
}

# Approved SDD/OpenSpec contracts; all setups remain isolated per test.
sdd_task_setup() {
  task_setup_clean
  jig task new scoped --class T3 >/dev/null
}

test_sdd_changes_committed_clean_tree_and_explicit_scope() {
  sdd_task_setup
  local base
  base=$(git rev-parse HEAD)
  printf 'owned\n' > owned.txt
  printf 'unrelated\n' > other.txt
  git add owned.txt other.txt
  git commit -qm 'committed work'
  run jig task changes scoped --base "$base" --files owned.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed  owned.txt"
  assert_contains "$OUT" "excluded: 1 candidate paths"
  assert_not_contains "$OUT" "other.txt"
  run jig task changes scoped --base "$base" --files owned.txt --format paths
  assert_eq owned.txt "$OUT"
}

test_sdd_changes_retains_cancelled_layers_and_untracked() {
  sdd_task_setup
  printf 'changed\n' > README.md
  git add README.md
  git show HEAD:README.md > README.md
  printf 'new\n' > new.txt
  run jig task changes scoped --base HEAD
  assert_eq 0 "$RC"
  assert_contains "$OUT" "staged     README.md"
  assert_contains "$OUT" "unstaged   README.md"
  assert_contains "$OUT" "untracked  new.txt"
}

test_sdd_changes_rename_deletion_and_literal_space_scope() {
  sdd_task_setup
  printf 'file\n' > 'space [x].txt'
  printf 'other\n' > 'space x.txt'
  git add .
  git commit -qm files
  git mv README.md moved.md
  rm 'space [x].txt'
  printf 'changed\n' >> 'space x.txt'
  run jig task changes scoped --base HEAD --format paths
  assert_contains "$OUT" README.md
  assert_contains "$OUT" moved.md
  run jig task changes scoped --base HEAD --files 'space [x].txt' --format paths
  assert_eq 0 "$RC"
  assert_eq 'space [x].txt' "$OUT"
}

test_sdd_changes_empty_stdin_is_not_default_scope() {
  sdd_task_setup
  echo dirty >> README.md
  run jig task changes scoped --base HEAD --files - --format paths < /dev/null
  assert_eq 0 "$RC"
  assert_eq '' "$OUT"
  run jig task changes scoped --base HEAD --files ''
  assert_contains "$OUT" 'selected: 0 paths; excluded: 1 candidate paths'
}

test_sdd_changes_rejects_missing_invalid_base_and_paths() {
  sdd_task_setup
  local scope
  run jig task changes scoped
  assert_eq 1 "$RC"
  assert_contains "$OUT" '--base is required'
  run jig task changes scoped --base no-such-ref
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'cannot resolve commit'
  for scope in '../outside' '/etc/passwd' 'a/../b' 'a/./b' 'a//b'; do
    run jig task changes scoped --base HEAD --files "$scope"
    assert_eq 1 "$RC"
    assert_contains "$OUT" 'path'
  done
  run jig task changes ../outside --base HEAD
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'invalid task id'
}

test_sdd_changes_rejects_control_names_and_git_failures() {
  skip_unless_control_char_names
  sdd_task_setup
  local name
  name=$(printf 'bad\tname')
  echo unsafe > "$name"
  run jig task changes scoped --base HEAD --format paths
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unsupported path'
  rm "$name"
  name=$(printf 'bad\nname')
  echo unsafe > "$name"
  run jig task changes scoped --base HEAD
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unsupported path'
  rm "$name"
  run bash -c '. "$JIG_HOME/scripts/lib/common.sh"; JIG_PROJECT="$PWD"; jig_git_change_rows missing HEAD'
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'Git inventory failed for committed'
}

test_sdd_changes_arguments_and_subdirectory_paths() {
  sdd_task_setup
  mkdir sub
  echo new > 'sub/new file'
  cd sub || return 1
  run jig task changes scoped --base HEAD --format paths
  assert_eq 'sub/new file' "$OUT"
  local flag
  for flag in --base --files --format; do
    run jig task changes scoped "$flag"
    assert_eq 1 "$RC"
    assert_contains "$OUT" 'requires a value'
  done
  run jig task changes scoped --base HEAD --format bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'invalid format'
  run jig task changes scoped --base HEAD --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unknown argument'
}

test_sdd_artifacts_t3_presence_never_approves_or_changes_state() {
  sdd_task_setup
  local state
  state=$(cat .ai/workspace/tasks/scoped/state)
  echo design > .ai/workspace/tasks/scoped/design.md
  run jig task artifacts scoped
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'implement: inputs-available; inputs: task design'
  assert_contains "$OUT" 'unassessed: human design approval'
  assert_contains "$OUT" 'consolidate: needs-input'
  assert_eq "$state" "$(cat .ai/workspace/tasks/scoped/state)"
  assert_not_contains "$OUT" 'status: ready'
}

test_sdd_artifacts_routes_and_conversation_claims() {
  sdd_task_setup
  local class
  for class in T0 T1 T2 T3 T4; do
    jig task set scoped class "$class" >/dev/null
    run jig task artifacts scoped --provided discovery,spec,alternatives,design,plan,verification
    assert_eq 0 "$RC"
    assert_contains "$OUT" "class: $class"
    assert_not_contains "$OUT" 'needs-input'
    assert_contains "$OUT" 'provided-claim'
    assert_no_file .ai/workspace/tasks/scoped/design.md
    # ADR-0030: every class's route ends in consolidate; T0/T1/T2 take their
    # knowledge-decision input from task (and plan for T2), both satisfied
    # here (task.md always exists; plan is a provided claim).
    case "$class" in
      T0 | T1) assert_contains "$OUT" 'consolidate: inputs-available; inputs: task' ;;
      T2) assert_contains "$OUT" 'consolidate: inputs-available; inputs: task plan' ;;
    esac
  done
  jig task set scoped class T4 >/dev/null
  run jig task artifacts scoped
  assert_contains "$OUT" 'design: needs-input; inputs: task spec alternatives'
  assert_contains "$OUT" 'unassessed: implementation and independent reviewer'
  jig task set scoped class T0 >/dev/null
  run jig task artifacts scoped
  assert_not_contains "$OUT" 'needs-input'
}

test_sdd_artifacts_empty_external_and_internal_links() {
  skip_unless_symlinks
  sdd_task_setup
  local root
  root=.ai/workspace/tasks/scoped
  : > "$root/design.md"
  run jig task artifacts scoped
  assert_contains "$OUT" 'design         unavailable (empty)'
  rm "$root/design.md"
  echo external > external.md
  ln -s "$PWD/external.md" "$root/design.md"
  run jig task artifacts scoped
  assert_contains "$OUT" 'design         unavailable (outside workspace)'
  rm "$root/design.md"
  echo internal > "$root/notes.md"
  ln -s notes.md "$root/design.md"
  run jig task artifacts scoped
  assert_contains "$OUT" 'design         present'
}

test_sdd_artifacts_rejects_invalid_claims_and_class() {
  sdd_task_setup
  local provided
  # `task` is writable by `jig task artifact` (nine kinds) but is deliberately
  # not a valid `--provided` claim here (eight kinds): `_task_artifact_kind`
  # and `_task_artifact_writable_kind` are separate predicates on purpose.
  for provided in '' ',design' 'design,' 'design,,spec' approval implementation 'design,design' task; do
    run jig task artifacts scoped --provided "$provided"
    assert_eq 1 "$RC"
    assert_contains "$OUT" 'task artifacts:'
  done
  run jig task artifacts scoped --provided task
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unknown provided kind: task'
  run jig task artifacts scoped --provided
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'requires a value'
  run jig task artifacts scoped --provided design --provided spec
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'duplicate --provided'
  jig task new no-class >/dev/null
  run jig task artifacts no-class
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'invalid or missing class'
  run jig task artifacts unknown
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unknown task'
}

# --- artifact write|append (ADR-0029: a worktree never writes through the link) --

test_task_artifact_write_replaces_and_append_joins_with_a_newline_boundary() {
  sdd_task_setup
  local root=.ai/workspace/tasks/scoped

  # write, with content from a file
  printf 'first draft\n' > src.md
  run jig task artifact write scoped plan --from src.md
  assert_eq 0 "$RC"
  assert_eq "$root/plan.md" "$OUT"
  assert_file_contains "$root/plan.md" 'first draft'

  # write replaces the whole document, not just what changed
  run jig task artifact write scoped plan <<< 'second draft'
  assert_eq 0 "$RC"
  assert_not_contains "$(cat "$root/plan.md")" 'first draft'
  assert_file_contains "$root/plan.md" 'second draft'

  # --from - is the same stdin source as omitting --from entirely
  run jig task artifact write scoped plan --from - <<< 'third draft, explicit stdin'
  assert_eq 0 "$RC"
  assert_file_contains "$root/plan.md" 'third draft, explicit stdin'

  # append creates the file when it is absent
  assert_no_file "$root/handoff.md"
  run jig task artifact append scoped handoff <<< 'note one'
  assert_eq 0 "$RC"
  assert_eq "$root/handoff.md" "$OUT"
  assert_file_contains "$root/handoff.md" 'note one'

  # append onto a document that does not end in a newline inserts one, so the
  # two documents never run into a single line
  printf 'no trailing newline' > "$root/handoff.md"
  run jig task artifact append scoped handoff <<< 'note two'
  assert_eq 0 "$RC"
  assert_eq "$(printf 'no trailing newline\nnote two')" "$(cat "$root/handoff.md")"

  # append onto a document that already ends in a newline does not double it
  printf 'line one\n' > "$root/handoff.md"
  run jig task artifact append scoped handoff <<< 'line two'
  assert_eq 0 "$RC"
  assert_eq "$(printf 'line one\nline two')" "$(cat "$root/handoff.md")"
}

test_task_artifact_rejects_unknown_kind_and_accepts_the_nine_writable_kinds() {
  sdd_task_setup
  run jig task artifact write scoped bogus <<< 'x'
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unknown kind: bogus'

  local kind
  for kind in task discovery spec alternatives design plan review verification handoff; do
    run jig task artifact write scoped "$kind" <<< "content for $kind"
    assert_eq 0 "$RC" "kind $kind should be writable"
    assert_file_contains ".ai/workspace/tasks/scoped/$kind.md" "content for $kind"
  done
}

# The data-loss guard: a `write` or `append` fed nothing must not blank an
# existing document, and must not leave a kind that was never written behind.
test_task_artifact_empty_input_is_refused_for_write_and_append() {
  sdd_task_setup
  local root=.ai/workspace/tasks/scoped
  printf 'do not lose me\n' > "$root/plan.md"

  run jig task artifact write scoped plan < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'refusing to write an empty plan'
  assert_file_contains "$root/plan.md" 'do not lose me'

  run jig task artifact append scoped plan < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'refusing to write an empty plan'
  assert_file_contains "$root/plan.md" 'do not lose me'

  run jig task artifact write scoped handoff < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'refusing to write an empty handoff'
  assert_no_file "$root/handoff.md"

  # An empty --from file is refused the same way as empty stdin.
  : > empty.md
  run jig task artifact write scoped plan --from empty.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'refusing to write an empty plan'
  assert_file_contains "$root/plan.md" 'do not lose me'
}

test_task_artifact_from_argument_validation() {
  sdd_task_setup
  run jig task artifact write scoped plan --from no-such-file.md < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'no such file: no-such-file.md'

  mkdir adir
  run jig task artifact write scoped plan --from adir < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'not a regular file: adir'

  run jig task artifact write scoped plan --from a --from b < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'duplicate --from'

  run jig task artifact write scoped plan --from < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" '--from requires a value'

  run jig task artifact write scoped plan --bogus < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unknown argument: --bogus'
}

test_task_artifact_from_unreadable_file_dies_before_writing() {
  # The write this test forces to fail succeeds wherever chmod 000 does not
  # block reads: as root, and in Git Bash on NTFS.
  skip_unless_unreadable_files
  sdd_task_setup
  local root=.ai/workspace/tasks/scoped
  printf 'do not lose me\n' > "$root/plan.md"
  printf 'unreadable\n' > secret.md
  chmod 000 secret.md

  run jig task artifact write scoped plan --from secret.md < /dev/null
  chmod 644 secret.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'file not readable: secret.md'
  assert_file_contains "$root/plan.md" 'do not lose me'
}

test_task_artifact_help_and_usage_on_missing_or_invalid_arguments() {
  sdd_task_setup
  run jig task artifact --help
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'usage: jig task artifact write <id> <kind> [--from <file>|-]'
  assert_contains "$OUT" 'jig task artifact append <id> <kind> [--from <file>|-]'

  run jig task artifact < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'usage: jig task artifact write'

  run jig task artifact bogus-mode scoped plan < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'usage: jig task artifact write'

  run jig task artifact write < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'usage: jig task artifact write'

  run jig task artifact write scoped < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'usage: jig task artifact write'
}

test_task_artifact_unknown_task_dies() {
  task_setup
  run jig task artifact write no-such-task plan < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unknown task: no-such-task'
}

test_task_artifact_write_refreshes_updated_at_and_becomes_present_in_artifacts() {
  sdd_task_setup
  sed 's/^updated_at:.*/updated_at: 2020-01-01/' .ai/workspace/tasks/scoped/state > s.tmp
  mv s.tmp .ai/workspace/tasks/scoped/state
  assert_file_contains .ai/workspace/tasks/scoped/state 'updated_at: 2020-01-01'

  run jig task artifact write scoped plan <<< 'the plan'
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/scoped/state "updated_at: $(date +%Y-%m-%d)"
  assert_not_contains "$(cat .ai/workspace/tasks/scoped/state)" 'updated_at: 2020-01-01'

  run jig task artifacts scoped
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'plan           present'
}

# The whole reason the verb exists: in a task worktree the workspace is
# reached through a link (ADR-0029), so a write issued from inside the
# worktree must still land in the ORIGINAL checkout's workspace. Modeled on
# test_task_start_worktree_borrows_the_workspace_by_link below.
test_task_artifact_worktree_writes_through_the_borrowed_link() {
  skip_unless_symlinks
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt owner content_file result rc
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  owner=$(cd .ai/workspace/tasks/T-1 && pwd -P)

  content_file="$PWD/content.txt"
  printf 'plan written from the worktree\n' > "$content_file"
  result=$(cd "$wt" && jig task artifact write T-1 plan --from - < "$content_file" 2>&1)
  rc=$?
  assert_eq 0 "$rc" "$result"
  # An absolute path: the destination is outside the worktree, so a relative
  # one would be read against the wrong root (ADR-0029: reports are absolute
  # when the workspace is borrowed).
  assert_eq "$owner/plan.md" "$result"
  assert_file_contains "$owner/plan.md" 'plan written from the worktree'
  # The worktree sees it too, but only because the link resolves there.
  assert_file_contains "$wt/.ai/workspace/tasks/T-1/plan.md" 'plan written from the worktree'
}

# --- branch per task (ADR-0008; a task lives on one branch) ------------------

test_task_start_creates_and_checks_out_a_branch() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task start T-1
  assert_eq 0 "$RC"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: task/T-1"
}

test_task_start_records_the_commit_it_forked_from() {
  # Without this, ancestry cannot tell "this branch has done nothing" from
  # "this branch was fast-forwarded in": in both cases the tip equals the base.
  task_setup
  local head_before
  head_before=$(git rev-parse HEAD)

  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/state "base_commit: $head_before"
}

test_task_start_branch_is_cut_from_the_base_branch_not_head() {
  # A task is work proposed against the base. Starting it wherever the
  # checkout happened to be is how a task inherits an unrelated history.
  task_setup
  git checkout -q -b unrelated
  printf 'unrelated\n' > unrelated.txt
  git add unrelated.txt
  git commit -q -m "unrelated work"

  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  # The unrelated commit must not be an ancestor of the new branch.
  if git merge-base --is-ancestor unrelated HEAD 2>/dev/null; then
    fail "task branch was cut from HEAD, not from the base branch"
  fi
}

test_task_new_files_without_touching_the_checkout() {
  # Filing is not beginning: no branch, no checkout change, and — crucially —
  # no `branch` field. The absence is what keeps a filed task out of
  # `task current` without anyone having to pause it.
  task_setup
  run jig task new T-1
  assert_eq 0 "$RC"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  if grep -qE '^(branch|base_commit):' .ai/workspace/tasks/T-1/state; then
    fail "task new recorded a branch or a fork point"
  fi

  run jig task list
  assert_contains "$OUT" "T-1 class=- status=active not-started"

  run jig task current
  assert_eq 1 "$RC" "a filed task must not be a candidate"
}

test_task_start_respects_branch_per_task_false() {
  task_setup
  sed 's|^git.branch_per_task:.*|git.branch_per_task: false|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  # Still "started": the task records where it began, which is what
  # housekeeping needs to tell "did nothing" from "landed".
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: main"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_commit: "
}

# --- base_branch recorded at start (ADR-0039) ---------------------------------
# Everything that later judges a task against its base — housekeeping,
# context, knowledge paths, resume overlap — reads this one field, so it has
# to land beside branch/base_commit in every path task start takes.

test_task_start_records_base_branch_matching_config() {
  task_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: main"
}

test_task_start_worktree_records_base_branch() {
  task_setup_nested
  jig task new T-1 >/dev/null
  jig task start T-1 --worktree >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: main"
}

test_task_start_branch_per_task_false_records_base_branch() {
  task_setup
  _task_share_one_branch
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: main"
}

test_task_start_records_a_non_default_configured_base() {
  # git.base_branch need not be "main"; whatever it names is what gets
  # recorded and what the task is cut from.
  task_setup
  git branch develop
  sed 's|^git.base_branch:.*|git.base_branch: develop|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: develop"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_commit: $(git rev-parse develop)"
}

test_task_set_refuses_base_branch() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 base_branch epic/x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_start_rejects_a_base_branch_name_git_would_reject() {
  # Checked before anything is created, the same guard as an invalid branch
  # template name: a task must not end up half-started on a bad base.
  task_setup
  sed 's|^git.base_branch:.*|git.base_branch: bad..name|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "git rejects the base branch name: bad..name"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  if grep -qE '^(branch|base_commit|base_branch):' .ai/workspace/tasks/T-1/state; then
    fail "a refused start recorded branch, base_commit or base_branch"
  fi
}

test_task_list_shows_base_only_when_it_differs_from_config() {
  # The state file is edited directly: `task set` refuses base_branch, and
  # `task start` only ever records the configured base for now (an epic base
  # is how a future feature would record one).
  task_setup
  task_started T-1
  task_started T-2
  sed 's|^base_branch:.*|base_branch: epic/foo|' .ai/workspace/tasks/T-1/state > s.tmp
  mv s.tmp .ai/workspace/tasks/T-1/state

  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "T-1 class=- status=active branch=task/T-1 base=epic/foo"
  assert_not_contains "$OUT" "T-2 class=- status=active branch=task/T-2 base="
}

test_task_start_uses_the_configured_branch_template() {
  task_setup
  sed 's|^git.branch_template:.*|git.branch_template: wip/{id}-x|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  assert_eq "wip/T-1-x" "$(git symbolic-ref --short HEAD)"
}

test_task_start_rejects_a_template_without_the_id() {
  task_setup
  sed 's|^git.branch_template:.*|git.branch_template: wip/fixed|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "must contain {id}"
  # The workspace survives: filing succeeded, only starting failed.
  assert_file .ai/workspace/tasks/T-1/state
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

test_task_start_rejects_a_branch_name_git_would_reject() {
  # git's own rules, not a hand-rolled regex: the invalid set is long and
  # creating a ref nobody can delete without plumbing is the failure mode.
  task_setup
  sed 's|^git.branch_template:.*|git.branch_template: bad..{id}|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "git rejects the branch name"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

test_task_start_refuses_an_existing_branch() {
  task_setup
  git branch task/T-1
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "branch already exists"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

test_task_set_refuses_to_write_base_commit() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 base_commit deadbeef
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_start_branches_from_head_in_a_repository_with_no_base_branch() {
  # Documented fallback: when neither the local nor the remote base branch
  # resolves, the branch is cut from HEAD, which is the only thing there is.
  task_setup
  git branch -m main trunk
  jig task new T-1 >/dev/null
  # git.base_branch still says `main`, which now resolves to nothing.
  run jig task start T-1
  assert_eq 0 "$RC"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_commit: $(git rev-parse trunk)"
}

# --- start takes the freshest base -------------------------------------------

test_task_start_prefers_origin_when_local_base_is_behind() {
  # Resolving refs/heads/<base> first meant a local base that had fallen
  # behind produced a stale branch AND a stale base_commit, silently. It
  # happened: a branch was cut from the previous merge and the work on it was
  # missing a command merged an hour earlier.
  task_setup_clean
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  # Move origin/main forward, leaving local main where it is.
  git checkout -q -b ahead
  printf 'ahead\n' > ahead.txt
  git add ahead.txt
  git commit -q -m "ahead"
  git push -q origin ahead:main
  git checkout -q main
  git fetch -q origin

  jig task new T-1 >/dev/null
  run jig task start T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "behind origin"

  # The branch must contain the commit only origin had.
  if ! git merge-base --is-ancestor origin/main HEAD; then
    fail "branch was cut from the stale local base"
  fi
  # ...without taking origin/main as its upstream: the task branch is never
  # pushed there, and `git status` would call it "ahead of origin/main".
  assert_eq "" "$(git config --get branch.task/T-1.merge || true)"
}

test_task_start_refuses_diverged_bases() {
  # Picking either side surprises somebody, and the surprise surfaces far from
  # its cause, so the command refuses instead of guessing.
  task_setup_clean
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  git checkout -q -b theirs
  printf 'theirs\n' > theirs.txt
  git add theirs.txt
  git commit -q -m theirs
  git push -q origin theirs:main
  git checkout -q main
  printf 'ours\n' > ours.txt
  git add ours.txt
  git commit -q -m ours
  git fetch -q origin

  jig task new T-1 >/dev/null
  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "diverged"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

test_task_start_unreachable_origin_warns_and_succeeds() {
  # A command that only wanted fresh refs must not stop the start over a
  # network problem: it warns and goes on with the refs this checkout has.
  task_setup_clean
  git remote add origin "$PWD/no-such-remote"

  jig task new T-1 >/dev/null
  run jig task start T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task start: could not fetch main from origin; using the refs this checkout has"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
}

# --- start from a spec's epic (ADR-0040) ---------------------------------------
# A task linked to a spec whose roadmap declares an open epic is cut from the
# epic instead of the project's configured base.

# task_open_epic <id> — a spec with an open epic, declared, merged into main
# and cut, exactly what `jig spec epic <id>` twice in a row builds. Duplicated
# from spec.t.sh's epic_ready_to_finish because each test file sources only
# itself.
task_open_epic() {
  local id="$1"
  jig spec new "$id" >/dev/null
  git add -A
  git commit -q -m "add spec $id"
  jig spec epic "$id" >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic "$id" >/dev/null
}

# task_link_spec <task-id> <spec-id> — append the Spec: line `jig-idea` would
# have written, the way spec.t.sh links a task to a spec for `spec done`.
task_link_spec() {
  printf 'Spec: .ai/specs/%s/\n' "$2" >> ".ai/workspace/tasks/$1/task.md"
}

test_task_start_cuts_from_the_spec_epic() {
  task_setup_clean
  task_open_epic idea-x
  jig task new T-1 >/dev/null
  task_link_spec T-1 idea-x

  run_split jig task start T-1
  assert_eq 0 "$RC"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: epic/idea-x"
  assert_eq "$(git rev-parse epic/idea-x)" \
    "$(sed -n 's/^base_commit: //p' .ai/workspace/tasks/T-1/state)"
  assert_contains "$ERR" "task start: T-1 is cut from epic/idea-x; open its pull request into epic/idea-x"
}

test_task_start_worktree_cuts_from_the_spec_epic() {
  task_setup_nested
  task_open_epic idea-x
  jig task new T-1 >/dev/null
  task_link_spec T-1 idea-x

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: epic/idea-x"
  assert_contains "$ERR" "task start: T-1 is cut from epic/idea-x; open its pull request into epic/idea-x"
}

test_task_start_no_spec_no_epic_line_in_the_output() {
  task_setup_clean
  jig task new T-1 >/dev/null

  run_split jig task start T-1
  assert_eq 0 "$RC"
  assert_not_contains "$ERR" "is cut from"
}

test_task_start_spec_roadmap_missing_in_this_checkout_dies() {
  task_setup_clean
  jig task new T-1 >/dev/null
  task_link_spec T-1 ghost

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task start: T-1 links to spec ghost, which this checkout does not have; switch to a branch that has it"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

test_task_start_two_spec_lines_dies() {
  task_setup_clean
  jig task new T-1 >/dev/null
  {
    printf 'Spec: .ai/specs/alpha/\n'
    printf 'Spec: .ai/specs/beta/\n'
  } >> .ai/workspace/tasks/T-1/task.md

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task start: T-1 links to more than one spec; keep one Spec: line"
}

test_task_start_two_epic_lines_in_the_roadmap_dies() {
  task_setup_clean
  jig spec new idea-x >/dev/null
  printf 'Epic: epic/a\nEpic: epic/b\n' >> .ai/specs/idea-x/roadmap.md
  jig task new T-1 >/dev/null
  task_link_spec T-1 idea-x

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task start: spec idea-x declares more than one epic; keep one Epic: line"
}

# `--finish` removes the spec now, rather than writing a "— finished" line
# (ADR-0035, ADR-0040 as amended); there is no command left that produces
# one. A roadmap someone wrote or edited by hand (or one an older jig left
# behind) can still carry that line, so `task start` still refuses it —
# simulated here directly, the way spec.t.sh's epic_legacy_finish_line does.
test_task_start_finished_epic_dies() {
  task_setup_clean
  mkdir -p .ai/specs/idea-x
  printf 'Epic: epic/idea-x — finished\n' > .ai/specs/idea-x/roadmap.md
  jig task new T-1 >/dev/null
  task_link_spec T-1 idea-x

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'task start: spec idea-x marks epic epic/idea-x finished; drop "— finished" from its Epic: line to cut tasks from it, or link the task to another spec'
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

test_task_start_open_epic_branch_missing_everywhere_dies() {
  task_setup_clean
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  # Deliberately never run `jig spec epic idea-x` again: the branch is never cut.
  jig task new T-1 >/dev/null
  task_link_spec T-1 idea-x

  run jig task start T-1
  assert_eq 1 "$RC"
  # shellcheck disable=SC2016 # backticks are part of the message
  assert_contains "$OUT" 'task start: epic epic/idea-x of spec idea-x exists neither here nor on origin; push it, or create it with `jig spec epic idea-x`'
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

test_task_start_picks_up_a_remote_only_epic_without_manual_fetch() {
  # A bare local origin sees a branch pushed by another clone; task start
  # fetches on its own rather than trusting whatever refs this checkout
  # happened to have last time it looked (decided 2026-09-16: always).
  task_setup_clean
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git push -q origin main
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  git push -q origin main
  jig spec epic idea-x >/dev/null
  # Simulate a second clone that pushed the epic to origin; it never existed
  # here except as a remote-tracking ref this checkout never fetched.
  git push -q origin epic/idea-x
  git branch -D epic/idea-x

  jig task new T-1 >/dev/null
  task_link_spec T-1 idea-x

  run jig task start T-1
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: epic/idea-x"
}

test_task_start_unreachable_origin_for_epic_base_warns_and_succeeds() {
  task_setup_clean
  task_open_epic idea-x
  git remote add origin "$PWD/no-such-remote"
  jig task new T-1 >/dev/null
  task_link_spec T-1 idea-x

  run jig task start T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task start: could not fetch main from origin; using the refs this checkout has"
  assert_contains "$OUT" "task start: could not fetch epic/idea-x from origin; using the refs this checkout has"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_branch: epic/idea-x"
}

test_task_start_refuses_a_dirty_tree() {
  # One task's uncommitted work must not become another's first commit.
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'dirty\n' >> README.md

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "uncommitted changes"
}

test_task_start_unknown_task_dies() {
  task_setup
  run jig task start nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task"
}

# --- start: a started task, and one only recorded at filing (ADR-0026 amended) ---

test_task_start_refuses_a_task_that_is_already_started() {
  task_setup
  task_started T-1
  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already started on task/T-1"
}

test_task_start_repairs_a_branch_recorded_at_filing() {
  # Before filing and starting were separate, `task new` wrote whatever branch
  # the checkout was on and no fork point. Such a task was never started, and
  # starting it is how the record gets repaired.
  task_setup_clean
  jig task new T-1 >/dev/null
  sed 's|^created_at:|branch: main\ncreated_at:|' .ai/workspace/tasks/T-1/state > s.tmp
  mv s.tmp .ai/workspace/tasks/T-1/state
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: main"

  run jig task start T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "recorded main when it was filed"
  grep -qx 'branch: task/T-1' .ai/workspace/tasks/T-1/state \
    || fail "branch was not rewritten: $(cat .ai/workspace/tasks/T-1/state)"
  grep -q '^base_commit: [0-9a-f]\{40\}$' .ai/workspace/tasks/T-1/state \
    || fail "no base_commit recorded"
}

test_task_start_on_a_paused_task_says_how_to_resume() {
  # Starting is not resuming: the pause stays, and the output says so.
  task_setup_clean
  jig task new T-1 >/dev/null
  jig task pause T-1 >/dev/null

  run jig task start T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "jig task resume T-1"
  assert_eq "true" "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
}

# --- start --worktree (ADR-0029) -----------------------------------------------

# Worktrees are created beside the project, so the project is put one level
# down: the default `../<project>.worktrees` then lands inside this test's own
# temporary directory and is removed with it.
task_setup_nested() {
  mkdir repo || return 1
  cd repo || return 1
  task_setup_clean
}

test_task_start_worktree_leaves_this_checkout_alone() {
  task_setup_nested
  task_started T-1
  printf 'dirty\n' >> README.md
  jig task new T-2 >/dev/null

  run_split jig task start T-2 --worktree
  assert_eq 0 "$RC"
  assert_eq "$(cd .. && pwd -P)/repo.worktrees/T-2" "$OUT"
  assert_contains "$ERR" "open a new agent session in $OUT"
  # The work in progress here is untouched: same branch, still uncommitted.
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  assert_contains "$(git status --porcelain)" "README.md"
  assert_eq "task/T-2" "$(git -C "$OUT" symbolic-ref --short HEAD)"
}

test_task_start_worktree_borrows_the_workspace_by_link() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt owner tasks
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  owner=$(cd .ai/workspace/tasks/T-1 && pwd -P)
  tasks=$(cd .ai/workspace/tasks && pwd -P)

  # The whole directory, not the one task: a task filed from inside the
  # worktree must land beside every other one instead of in a directory that
  # dies with the tree.
  [ -L "$wt/.ai/workspace/tasks" ] || fail "the worktree has no link to the task directory"
  assert_eq "$tasks" "$(cd "$wt/.ai/workspace/tasks" && pwd -P)"
  assert_eq "$owner" "$(cd "$wt/.ai/workspace/tasks/T-1" && pwd -P)"
  grep -qx 'branch: task/T-1' .ai/workspace/tasks/T-1/state || fail "branch not recorded"
  grep -q '^base_commit: [0-9a-f]\{40\}$' .ai/workspace/tasks/T-1/state || fail "base_commit not recorded"
  # Inside the worktree the task is current, and the link leaves git clean.
  assert_eq "T-1" "$(cd "$wt" && jig task current)"
  assert_eq "" "$(git -C "$wt" status --porcelain)"
}

# task_setup_directory_ignored_by_directory — a project whose gitignore names
# the task directory with a trailing slash. Such a rule matches a directory and
# not a link, so a directory link there would read as untracked and
# `git worktree remove` without --force would refuse the tree for the rest of
# its life (ADR-0029 as amended). This is the shape the fallback exists for.
task_setup_tasks_ignored_by_directory() {
  task_setup_nested
  printf '.ai/workspace/tasks/\n.ai/runtime\n.ai/config.local.yaml\n' > .gitignore
  git add .gitignore
  git commit -q -m "ignore the task directory as a directory"
}

# The defect this whole change exists for, end to end. A unit test on the
# linking function would not have caught it: what caught it was comparing two
# lists of tasks by eye, three times in one shift.
test_task_new_in_a_worktree_is_filed_where_every_other_task_is() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)

  # An agent in the worktree files the successor its own work asked for.
  ( cd "$wt" && jig task new T-2 >/dev/null ) || fail "task new in the worktree failed"

  # The checkout that keeps the queue sees it, as a workspace of its own.
  assert_contains "$(jig task show T-2)" "task_id: T-2"
  [ -d .ai/workspace/tasks/T-2 ] || fail "T-2 was not filed in the owning checkout"
  [ ! -L .ai/workspace/tasks/T-2 ] || fail "T-2 should be a workspace, not a link"

  # And it outlives the tree it was written in. `git worktree remove` without
  # --force deletes ignored files without a word, so before this the statement
  # went with the worktree and nothing said so.
  run git worktree remove "$wt"
  [ "$RC" -eq 0 ] || fail "git worktree remove refused the worktree (rc=$RC): $OUT"
  if [ -d "$wt" ]; then
    fail "the worktree is still there
    remove: rc=$RC out=[$OUT]
    still listed by git: [$(git worktree list --porcelain | tr '\n' '|')]
    left in the tree: [$(ls -a "$wt" 2>&1 | tr '\n' ' ')]
    left in .ai/workspace: [$(ls -a "$wt/.ai/workspace" 2>&1 | tr '\n' ' ')]
    the tasks path there: -L=$(if [ -L "$wt/.ai/workspace/tasks" ]; then echo yes; else echo no; fi) -d=$(if [ -d "$wt/.ai/workspace/tasks" ]; then echo yes; else echo no; fi) readlink=[$(readlink "$wt/.ai/workspace/tasks" 2>&1)]
    the owner's tasks: [$(ls -a .ai/workspace/tasks 2>&1 | tr '\n' ' ')]
    the owner's T-1 state: $(if [ -f .ai/workspace/tasks/T-1/state ]; then echo present; else echo MISSING; fi)
    the owner's T-2 state: $(if [ -f .ai/workspace/tasks/T-2/state ]; then echo present; else echo MISSING; fi)
    task show T-2 says: [$(jig task show T-2 2>&1 | head -2 | tr '\n' ' ')]"
  fi
  assert_contains "$(jig task show T-2)" "task_id: T-2"
}

# The other half of the same defect: a reviewer in a worktree refused to drop a
# finding because it could not confirm that the task it named existed.
test_task_start_worktree_shows_the_tasks_filed_outside_it() {
  task_setup_nested
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)

  assert_contains "$(cd "$wt" && jig task show T-2)" "task_id: T-2"
  assert_contains "$(cd "$wt" && jig status)" "task T-2"
}

# The fallback and the shape it falls back from, in one fixture, because
# either half alone is blind. The per-task link is what every worktree got
# before this change, so a test that asserts only it passes just as well
# against code that cannot link a directory at all -- put the pre-fix
# `task.sh` back and this test stayed green (conventions/detectors.md). What
# only the new code can do is answer the two ignore shapes differently, so
# both arms are asserted together and the difference between them is the
# claim.
test_task_start_worktree_chooses_the_link_shape_by_what_git_ignores() {
  task_setup_tasks_ignored_by_directory
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)

  # A rule ending in `/` matches a directory and not a link, so a directory
  # link would read as untracked here: one task it is.
  [ ! -L "$wt/.ai/workspace/tasks" ] || fail "the task directory must not be linked here"
  [ -L "$wt/.ai/workspace/tasks/T-1" ] || fail "the one-task link is missing"
  # The whole point of the fallback: the worktree can still be removed.
  assert_eq "" "$(git -C "$wt" status --porcelain)"

  # The same jig and the same command, one character less in the rule:
  # `.ai/workspace` matches the parent and covers the link either way, so the
  # directory is borrowed whole.
  printf '.ai/workspace\n.ai/runtime\n.ai/config.local.yaml\n' > .gitignore
  git add .gitignore
  git commit -q -m "ignore the workspace as a path, link or directory"
  jig task new T-2 >/dev/null
  local wt2
  wt2=$(jig task start T-2 --worktree 2>/dev/null)

  [ -L "$wt2/.ai/workspace/tasks" ] || fail "the task directory was not borrowed whole"
  assert_eq "" "$(git -C "$wt2" status --porcelain)"
}

# Where the directory could not be linked, the loss must be refused rather than
# made quietly. This also covers a worktree somebody made with `git worktree
# add`, which has a task directory of its own for the same reason.
test_task_new_refuses_in_a_worktree_that_keeps_its_own_task_directory() {
  task_setup_tasks_ignored_by_directory
  jig task new T-1 >/dev/null
  local wt owner
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  owner=$(pwd -P)

  run sh -c "cd '$wt' && '$JIG_BIN' task new T-2"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "would be invisible to $owner"
  [ ! -e "$wt/.ai/workspace/tasks/T-2" ] || fail "a stranded workspace was created anyway"
  [ ! -e .ai/workspace/tasks/T-2 ] || fail "the refusal should file nothing"
}

test_task_start_worktree_branches_from_the_base_not_head() {
  task_setup_nested
  git checkout -q -b unrelated
  printf 'unrelated\n' > unrelated.txt
  git add unrelated.txt
  git commit -q -m "unrelated work"
  jig task new T-1 >/dev/null

  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  assert_eq "$(git rev-parse main)" "$(git -C "$wt" rev-parse HEAD)"
  assert_eq "$(git rev-parse main)" "$(sed -n 's/^base_commit: //p' .ai/workspace/tasks/T-1/state)"
}

# A phase run files a whole wave in one commit on the *local* epic and does
# not push it: `jig_fresh_base_ref` takes the fresher of the local branch and
# origin's, so every branch the wave cuts afterwards carries that same commit,
# by the same SHA, and no two of them rewrite neighbouring roadmap lines
# (adr-20260922-a-phase-run-is-coordinated).
test_task_start_worktree_carries_an_unpushed_epic_commit_into_every_branch() {
  task_setup_nested
  git add -A
  git commit -q -m "jig init snapshot"
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin

  mkdir -p .ai/specs/alpha
  cat > .ai/specs/alpha/roadmap.md <<'RM'
# alpha
Epic: epic/alpha
RM
  git add -A
  git commit -q -m "declare the epic"
  git push -q origin main
  git checkout -q -b epic/alpha
  git push -q origin epic/alpha
  git fetch -q origin

  # The coordinator files the wave: both tags in one commit, left unpushed.
  cat >> .ai/specs/alpha/roadmap.md <<'RM'

## Phase 1 — First

- [ ] `T-a` — Alpha — goal
- [ ] `T-b` — Bravo — goal
RM
  local t tags
  for t in T-a T-b; do
    jig task new "$t" >/dev/null
    printf 'Spec: .ai/specs/alpha/ — Phase 1\n' >> ".ai/workspace/tasks/$t/task.md"
  done
  git add .ai/specs/alpha/roadmap.md
  git commit -q -m "file wave 1"
  tags=$(git rev-parse HEAD)
  ! git merge-base --is-ancestor "$tags" origin/epic/alpha \
    || fail "the wave commit was expected to be local only, not pushed"

  local wt_a wt_b
  wt_a=$(jig task start T-a --worktree 2>/dev/null)
  wt_b=$(jig task start T-b --worktree 2>/dev/null)
  assert_eq "$tags" "$(git -C "$wt_a" rev-parse HEAD)"
  assert_eq "$tags" "$(git -C "$wt_b" rev-parse HEAD)"
  assert_eq "$tags" "$(sed -n 's/^base_commit: //p' .ai/workspace/tasks/T-a/state)"
  assert_eq "$tags" "$(sed -n 's/^base_commit: //p' .ai/workspace/tasks/T-b/state)"
  # Both see the wave's tags, so `jig spec plan` knows the tasks from the
  # first minute rather than after the first merge.
  grep -q "\`T-b\`" "$wt_a/.ai/specs/alpha/roadmap.md" || fail "T-a's worktree is missing the wave's tags"
  grep -q "\`T-a\`" "$wt_b/.ai/specs/alpha/roadmap.md" || fail "T-b's worktree is missing the wave's tags"
}

test_task_start_worktree_honours_the_configured_root() {
  task_setup_nested
  printf 'git.worktree_root: ../elsewhere\n' >> .ai/config.yaml
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_eq "$(cd .. && pwd -P)/elsewhere/T-1" "$OUT"
}

test_task_start_worktree_refuses_an_existing_path() {
  task_setup_nested
  mkdir -p ../repo.worktrees/T-1
  jig task new T-1 >/dev/null

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "worktree path already exists"
  if grep -q '^branch:' .ai/workspace/tasks/T-1/state; then
    fail "a refused start recorded a branch"
  fi
}

test_task_start_worktree_refuses_a_shared_branch() {
  # git will not check one branch out in two worktrees, and one shared branch
  # is what `branch_per_task: false` means.
  task_setup_nested
  _task_share_one_branch
  jig task new T-1 >/dev/null

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--worktree needs git.branch_per_task: true"
  assert_no_file ../repo.worktrees/T-1
}

# --- start --worktree on a machine where `ln -s` copies (Windows Git Bash) ----

test_task_start_worktree_refuses_when_only_copying_links_are_available() {
  skip_unless_link_simulation
  task_setup_nested
  jig task new T-1 >/dev/null
  local lndir
  lndir=$(stub_ln_copy_dir)
  export PATH="$lndir:$PATH"

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--worktree needs a directory link"
  assert_no_file ../repo.worktrees/T-1
  if git rev-parse --verify --quiet refs/heads/task/T-1 >/dev/null; then
    fail "the branch of a refused start was left behind"
  fi
  if grep -q '^branch:' .ai/workspace/tasks/T-1/state; then
    fail "a refused start recorded a branch"
  fi
}

test_task_start_worktree_links_via_a_junction_when_symlinks_copy() {
  skip_unless_link_simulation
  task_setup_nested
  jig task new T-1 >/dev/null
  local lndir jdir owner wt
  lndir=$(stub_ln_copy_dir)
  jdir=$(stub_junction_dir)
  owner=$(cd .ai/workspace/tasks/T-1 && pwd -P)
  export PATH="$jdir:$lndir:$PATH"

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC" "task start should succeed: $ERR"
  wt="$OUT"
  [ -L "$wt/.ai/workspace/tasks" ] || fail "the worktree has no link to the task directory"
  assert_eq "$owner" "$(cd "$wt/.ai/workspace/tasks/T-1" && pwd -P)"
}

test_task_start_dirty_refusal_offers_the_worktree() {
  task_setup_clean
  printf 'dirty\n' >> README.md
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig task start T-1 --worktree"
}

test_task_start_dirty_refusal_on_a_shared_branch_offers_no_worktree() {
  task_setup_clean
  _task_share_one_branch
  git add .ai/config.yaml
  git commit -q -m "share one branch"
  printf 'dirty\n' >> README.md
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_not_contains "$OUT" "--worktree"
}

test_task_list_shows_the_worktree_and_what_waits_for_review() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  printf 'new\n' > "$wt/new.txt"

  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "T-1 class=- status=active branch=task/T-1 worktree=$wt uncommitted=1"
}

test_task_artifacts_reads_the_borrowed_workspace() {
  task_setup_nested
  jig task new T-1 --class T2 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  printf 'design\n' > .ai/workspace/tasks/T-1/plan.md

  set +e
  OUT=$(cd "$wt" && jig task artifacts T-1 2>&1)
  RC=$?
  set -e
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task: T-1; class: T2"
  assert_contains "$OUT" "plan           present"
}

test_task_artifacts_refuses_a_link_to_anywhere_else() {
  # The one link accepted is to this task's own workspace in another worktree
  # of this repository; a link elsewhere could point at anything.
  skip_unless_symlinks
  task_setup
  mkdir -p elsewhere/T-1
  printf 'task_id: T-1\nclass: T2\nstatus: active\n' > elsewhere/T-1/state
  mkdir -p .ai/workspace/tasks
  ln -s "$PWD/elsewhere/T-1" .ai/workspace/tasks/T-1

  run jig task artifacts T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "linked task workspace is unsupported"
}

test_task_artifact_refuses_a_link_to_anywhere_else() {
  # Mirrors test_task_artifacts_refuses_a_link_to_anywhere_else above: the one
  # link `_task_workspace_root` accepts is to this task's own workspace in
  # another worktree of this repository, and both write and append go through
  # that same check before anything is touched.
  skip_unless_symlinks
  task_setup
  mkdir -p elsewhere/T-1
  printf 'task_id: T-1\nclass: T2\nstatus: active\n' > elsewhere/T-1/state
  mkdir -p .ai/workspace/tasks
  ln -s "$PWD/elsewhere/T-1" .ai/workspace/tasks/T-1

  run jig task artifact write T-1 plan <<< 'nope'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "linked task workspace is unsupported"
  assert_no_file elsewhere/T-1/plan.md

  run jig task artifact append T-1 plan <<< 'nope'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "linked task workspace is unsupported"
  assert_no_file elsewhere/T-1/plan.md
}

test_task_start_worktree_failure_leaves_nothing_behind() {
  # `git worktree add -b` creates the branch before the directory. Without an
  # undo, a failed start left the branch behind and every retry died with
  # "branch already exists".
  skip_unless_readonly_dirs
  task_setup_nested
  mkdir ../repo.worktrees
  chmod 555 ../repo.worktrees
  jig task new T-1 >/dev/null

  run jig task start T-1 --worktree
  chmod 755 ../repo.worktrees
  assert_eq 1 "$RC"
  assert_contains "$OUT" "could not create worktree"
  if git rev-parse --verify --quiet refs/heads/task/T-1 >/dev/null; then
    fail "the branch of a failed start was left behind"
  fi
  if grep -q '^branch:' .ai/workspace/tasks/T-1/state; then
    fail "a failed start recorded a branch"
  fi

  run jig task start T-1 --worktree
  assert_eq 0 "$RC"
}

test_task_start_worktree_undoes_itself_when_the_link_fails() {
  # The worktree and branch exist by then; both must go so a retry can work.
  # A tracked *file* named .ai/workspace is the simplest way to make the link
  # impossible in the new checkout without touching this one.
  task_setup_nested
  local blob
  blob=$(printf 'not a directory\n' | git hash-object -w --stdin)
  git update-index --add --cacheinfo "100644,$blob,.ai/workspace"
  git commit -q -m "a file where the workspace directory belongs"
  jig task new T-1 >/dev/null

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "could not link the workspace"
  assert_no_file ../repo.worktrees/T-1
  if git rev-parse --verify --quiet refs/heads/task/T-1 >/dev/null; then
    fail "the branch of a failed start was left behind"
  fi
  assert_eq "" "$(git worktree list --porcelain | grep 'repo.worktrees' || true)"
}

test_task_pause_stash_refuses_a_task_checked_out_elsewhere() {
  # --stash sets aside this checkout's changes. For a task running in its own
  # worktree they are somebody else's, and the task's own work stays put.
  task_setup_nested
  jig task new T-1 >/dev/null
  jig task start T-1 --worktree >/dev/null 2>&1
  printf 'unrelated\n' >> README.md

  run jig task pause T-1 --stash
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1 is on task/T-1"
  assert_contains "$(git status --porcelain)" "README.md"
  assert_eq "" "$(git stash list)"
  if grep -q '^paused:' .ai/workspace/tasks/T-1/state; then
    fail "a refused pause marked the task paused"
  fi
}

# --- ship (agent git rights: design.md, .ai/specs/autopilot/) ----------------

# ship_cfg_local <key> <value> — set a key in .ai/config.local.yaml
# (ADR-0038); creates the file, or appends the key when it is not there yet.
# Mirrors housekeeping.t.sh's hk_cfg_local; duplicated because each test file
# sources only itself.
ship_cfg_local() {
  local file=".ai/config.local.yaml"
  touch "$file"
  if grep -q "^$1:" "$file"; then
    sed "s|^$1:.*|$1: $2|" "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  else
    printf '%s: %s\n' "$1" "$2" >> "$file"
  fi
}

# ship_cfg <key> <value> — rewrite one line of the project's config.yaml.
# Mirrors housekeeping.t.sh's hk_cfg.
ship_cfg() {
  sed "s|^$1:.*|$1: $2|" .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml
}

# ship_setup — a clean repository with a bare `origin`, task T-1 filed and
# started on its own branch, and a commit message ready in msg.txt.
# `agent.git` is left unset (default `none`) and `knowledge_consolidated`
# left `false`; each test sets what it needs.
ship_setup() {
  task_setup_clean
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  printf 'Ship T-1\n\nBody line one.\nBody line two.\n' > msg.txt
}

# ship_setup_forge — ship_setup with GitHub as the forge and `gh` stubbed,
# and with that setting committed on the base branch before the task's own
# branch is cut. `forge` is a project setting, so writing it leaves the
# tracked .ai/config.yaml modified; committed here, it is fixture rather than
# an unstaged change of the task's — which is what `task ship` now refuses to
# ship past (jig_ship_commit).
ship_setup_forge() {
  task_setup_clean
  ship_cfg forge github
  git add .ai/config.yaml
  git commit -q -m "fixture: github is the forge"
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  printf 'Ship T-1\n\nBody line one.\nBody line two.\n' > msg.txt
  ship_stub_gh ""
}

# ship_stage_change — one file, staged, belonging to the task.
ship_stage_change() {
  printf 'ship change\n' > ship.txt
  git add ship.txt
}

# ship_stub_gh <existing-url-or-empty> — a fake `gh` for `task ship`'s pr
# step. `gh auth status` succeeds; `gh pr list ...` prints <existing-url>
# verbatim when given (standing in for the real `--jq` filter's answer) or
# `null` for none (jq's own answer for an empty array); `gh pr create ...`
# records its own arguments, one per line, to gh-create.argv and prints a
# made-up URL. Every call, whichever one it is, appends its arguments to
# gh-calls.log: a test that has to prove the forge was never asked at all
# cannot do it by the absence of gh-create.argv, because `pr list` and `auth
# status` reach the forge before any pull request is created.
ship_stub_gh() {
  local existing="${1:-}"
  mkdir -p stub-bin
  cat > stub-bin/gh <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> gh-calls.log
case "\$1" in
  auth) exit 0 ;;
  pr)
    shift
    case "\$1" in
      list)
        if [ -n "$existing" ]; then
          printf '%s\n' "$existing"
        else
          printf 'null\n'
        fi
        ;;
      create)
        shift
        printf '%s\n' "\$@" > gh-create.argv
        printf 'https://github.com/example/example/pull/99\n'
        ;;
    esac
    ;;
esac
STUB
  chmod +x stub-bin/gh
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# ship_stub_glab <existing-url-or-empty> — a fake `glab` for `task ship`'s pr
# step. `glab auth status` succeeds; `glab mr list ...` prints a compact
# one-line JSON array with one object whose `web_url` is <existing-url>,
# preceded by a nested object field (`assignee`) to prove the parser matches
# `web_url` itself rather than splitting naively on braces or commas, or `[]`
# for none, `glab`'s own answer for an empty list; `glab mr create ...`
# records its own arguments, one per line, to glab-create.argv and prints a
# made-up URL on its last line, the way real `glab` output trails one.
ship_stub_glab() {
  local existing="${1:-}"
  mkdir -p stub-bin
  cat > stub-bin/glab <<STUB
#!/usr/bin/env bash
case "\$1" in
  auth) exit 0 ;;
  mr)
    shift
    case "\$1" in
      list)
        if [ -n "$existing" ]; then
          printf '[{"iid":7,"assignee":{"id":3,"username":"joe"},"web_url":"%s","title":"x"}]\n' "$existing"
        else
          printf '[]\n'
        fi
        ;;
      create)
        shift
        printf '%s\n' "\$@" > glab-create.argv
        printf 'Creating merge request for task/T-1 into main in example/example\nhttps://gitlab.example/example/example/-/merge_requests/99\n'
        ;;
    esac
    ;;
esac
STUB
  chmod +x stub-bin/glab
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# ship_stub_glab_mr_create_fails — a fake `glab` whose `mr create` fails, for
# task ship's error-handling test. `auth status` succeeds and `mr list`
# reports no MR open yet, so the failing `create` is actually reached.
ship_stub_glab_mr_create_fails() {
  mkdir -p stub-bin
  cat > stub-bin/glab <<'STUB'
#!/usr/bin/env bash
case "$1" in
  auth) exit 0 ;;
  mr)
    shift
    case "$1" in
      list) printf '[]\n' ;;
      create) printf 'error: not authorized\n' >&2; exit 1 ;;
    esac
    ;;
esac
STUB
  chmod +x stub-bin/glab
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

test_task_ship_none_level_exits_3_and_changes_nothing() {
  ship_setup
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  local head_before
  head_before=$(git rev-parse HEAD)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 3 "$RC"
  assert_contains "$OUT" "task ship: agent.git is none in this clone; the human commits"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
  assert_contains "$(git status --porcelain -- ship.txt)" "A  ship.txt"
}

test_task_ship_requires_knowledge_consolidated() {
  ship_setup
  ship_cfg_local agent.git commit
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires knowledge_consolidated true"
  assert_contains "$OUT" "jig task set T-1 knowledge_consolidated true"
}

test_task_ship_wrong_branch_refuses() {
  ship_setup
  ship_cfg_local agent.git commit
  jig task set T-1 knowledge_consolidated true >/dev/null
  git checkout -q main

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "current branch is main, but T-1 is on task/T-1"
}

test_task_ship_on_base_branch_refuses() {
  task_setup_clean
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  _task_share_one_branch
  git add -A
  git commit -q -m "branch_per_task off"
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_cfg_local agent.git commit
  printf 'msg\n' > msg.txt

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is its own base"
}

test_task_ship_staged_workspace_path_refuses() {
  ship_setup
  ship_cfg_local agent.git commit
  jig task set T-1 knowledge_consolidated true >/dev/null
  local head_before
  head_before=$(git rev-parse HEAD)
  printf 'oops\n' > .ai/workspace/tasks/T-1/scratch.md
  # -f: .ai/workspace is gitignored (transient state); this reproduces the
  # one way such a path could still end up staged.
  git add -f .ai/workspace/tasks/T-1/scratch.md

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "staged changes under .ai/workspace/ or .ai/runtime/ are not shippable"
  assert_contains "$OUT" ".ai/workspace/tasks/T-1/scratch.md"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
}

test_task_ship_commit_level_commits_only_staged_and_does_not_push() {
  ship_setup
  ship_cfg_local agent.git commit
  jig task set T-1 knowledge_consolidated true >/dev/null
  # An untracked file that is not part of this task's staged change: `git
  # commit -F` without `-a` must leave it alone.
  printf 'not staged\n' > untouched.txt
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "stopped at commit: push is the human's"
  assert_not_contains "$OUT" "pushed "
  assert_eq "" "$(git status --porcelain -- ship.txt)"
  assert_contains "$(git status --porcelain -- untouched.txt)" "?? untouched.txt"
  assert_eq "" "$(git ls-remote origin task/T-1)"
}

# The one case an empty index is right: the working tree is clean, so
# nothing is being left behind, and the branch carries the change an earlier
# run committed. A ship that had to be run twice — a push that failed, a
# forge that was down — gets through here rather than needing an empty commit
# to appease it.
test_task_ship_empty_index_with_a_clean_tree_ships_the_earlier_commit() {
  ship_setup
  ship_cfg_local agent.git push
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  git commit -q -m "committed by an earlier run"
  local head_before
  head_before=$(git rev-parse HEAD)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "nothing staged; no commit"
  assert_contains "$OUT" "pushed task/T-1"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
}

# Nothing to commit is an outcome, not a line in the log (common.sh,
# jig_ship_commit). The branch here carries a commit of its own, so the order
# check below would pass and the pull request would not even look wrong: it
# would carry the earlier commit and not the change, and at `agent.git: merge`
# nothing afterwards would notice — a pull request without the change has
# nothing to make CI red, so it goes green and merges itself.
test_task_ship_unstaged_change_refuses_and_ships_nothing() {
  ship_setup_forge
  ship_cfg_local agent.git merge
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  git commit -q -m "committed by an earlier run"
  printf 'the line the agent forgot to stage\n' >> ship.txt

  run jig task ship T-1 --message-file msg.txt

  assert_eq 1 "$RC"
  assert_contains "$OUT" "nothing is staged"
  assert_contains "$OUT" "ship.txt"
  assert_eq "" "$(git ls-remote origin task/T-1)" "the branch must not be pushed"
  assert_no_file gh-calls.log "the forge must not be asked anything"
}

# The order, not the wording (common.sh, "what a ship may send out"). Proved
# without a network: `origin` is a real bare repository here, so a push that
# happened is visible in its refs, and `gh` is a stub that appends every call
# to gh-calls.log, so a forge that was asked anything is visible too. The
# level is `merge`, the one with every outward step in it.
test_task_ship_empty_branch_refuses_before_anything_leaves_the_machine() {
  ship_setup_forge
  ship_cfg_local agent.git merge
  jig task set T-1 knowledge_consolidated true >/dev/null

  run jig task ship T-1 --message-file msg.txt

  assert_eq 1 "$RC"
  assert_contains "$OUT" "nothing to ship"
  assert_contains "$OUT" "The index was empty"
  assert_eq "" "$(git ls-remote origin task/T-1)" "the branch must not be pushed"
  assert_no_file gh-calls.log "the forge must not be asked anything"
  assert_no_file gh-create.argv
}

# The same refusal at `commit`, where nothing would have left this machine
# anyway: "this branch carries no work" is the same answer at every level,
# and at `commit` the human pushes next.
test_task_ship_empty_branch_refuses_at_commit_level_too() {
  ship_setup
  ship_cfg_local agent.git commit
  jig task set T-1 knowledge_consolidated true >/dev/null
  local head_before
  head_before=$(git rev-parse HEAD)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "nothing to ship"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
}

# The rule itself, for each outward step rather than for one path through
# `task ship`: called with the gate unset, every one of them refuses on its
# own. A step added later inherits the rule only by opening with the guard,
# and this is what says so.
ship_outward_call() {
  run bash -c '. "$JIG_HOME/scripts/lib/common.sh"; '"$1"
}

test_ship_every_outward_step_refuses_before_the_ship_said_what_it_sends() {
  local expected="a step that leaves this machine was reached before the ship checked what it has to send"

  ship_outward_call 'jig_ship_push "task ship" task/T-1'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "$expected"

  ship_outward_call 'jig_ship_pr "task ship" task/T-1 main msg.txt'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "$expected"

  ship_outward_call 'jig_ship_merge "task ship" https://example.invalid/pull/1 deadbeef any'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "$expected"
}

test_task_ship_push_level_pushes_and_stops() {
  ship_setup
  ship_cfg_local agent.git push
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "pushed task/T-1"
  assert_contains "$OUT" "stopped at push: the pull request is the human's"
  assert_contains "$(git ls-remote origin task/T-1)" "refs/heads/task/T-1"
}

test_task_ship_pr_level_creates_pr_into_base_branch() {
  ship_setup
  ship_cfg forge github
  ship_stub_gh ""
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "pushed task/T-1"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
  assert_file gh-create.argv
  local argv
  argv=$(cat gh-create.argv)
  assert_contains "$argv" "$(printf -- '--base\nmain')" "pull request must target the task's own base"
  assert_contains "$argv" "$(printf -- '--head\ntask/T-1')"
  assert_contains "$argv" "$(printf -- '--title\nShip T-1')"
}

test_task_ship_pr_level_does_not_duplicate_an_existing_open_pr() {
  ship_setup
  ship_cfg forge github
  ship_stub_gh "https://github.com/example/example/pull/7"
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/7 (already open)"
  assert_no_file gh-create.argv
}

test_task_ship_pr_level_creates_mr_with_gitlab() {
  ship_setup
  ship_cfg forge gitlab
  ship_stub_glab ""
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "pushed task/T-1"
  assert_contains "$OUT" "pr https://gitlab.example/example/example/-/merge_requests/99"
  assert_file glab-create.argv
  local argv
  argv=$(cat glab-create.argv)
  assert_contains "$argv" "$(printf -- '--target-branch\nmain')" "merge request must target the task's own base"
  assert_contains "$argv" "$(printf -- '--source-branch\ntask/T-1')"
  assert_contains "$argv" "$(printf -- '--title\nShip T-1')"
}

test_task_ship_pr_level_does_not_duplicate_an_existing_open_mr() {
  ship_setup
  ship_cfg forge gitlab
  ship_stub_glab "https://gitlab.example/x/-/merge_requests/7"
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr https://gitlab.example/x/-/merge_requests/7 (already open)"
  assert_no_file glab-create.argv
}

test_task_ship_pr_level_gitlab_mr_create_failure_dies() {
  ship_setup
  ship_cfg forge gitlab
  ship_stub_glab_mr_create_fails
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "glab mr create failed"
}

test_task_ship_pr_level_with_no_forge_stops_with_message() {
  ship_setup
  ship_cfg forge none
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no forge available; the pull request is the human's"
  assert_not_contains "$OUT" "pr https"
}

test_task_ship_invalid_agent_git_level_dies() {
  ship_setup
  ship_cfg_local agent.git yolo
  jig task set T-1 knowledge_consolidated true >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task ship: invalid agent.git: yolo (expected none|commit|push|pr|merge)"
}

test_task_ship_message_file_required() {
  ship_setup
  run jig task ship T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--message-file is required"
}

test_task_ship_message_file_missing_dies() {
  ship_setup
  run jig task ship T-1 --message-file nope.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--message-file: no such file: nope.txt"
}

test_task_ship_unknown_task_dies() {
  task_setup
  printf 'msg\n' > msg.txt
  run jig task ship NOPE --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

# --- ship at agent.git: merge (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci)

# mship_stub_gh — a fake, authenticated `gh` that can merge. Every call is
# logged, one per line, to gh.log; its answers come from files in the test
# directory, so each test sets only what differs:
#   gh-checks    the pull request's check buckets, one per line (default: pass)
#   gh-draft     `true`|`false` for `pr view` (default: false)
#   gh-head      the head `pr view` reports (default: HEAD of this repository)
#   gh-repo      merge-commit, squash and rebase allowed (default: true true true)
#   gh-merge.rc  the exit code of `pr merge` (default: 0)
# `pr create` and `pr merge` record their arguments in gh-create.argv and
# gh-merge.argv.
mship_stub_gh() {
  local dir="$PWD"
  mkdir -p stub-bin
  cat > stub-bin/gh <<STUB
#!/usr/bin/env bash
d="$dir"
printf '%s\n' "\$*" >> "\$d/gh.log"
val() { if [ -f "\$d/\$1" ]; then cat "\$d/\$1"; else printf '%s\n' "\$2"; fi; }
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr list") printf 'null\n' ;;
  "pr create") shift 2; printf '%s\n' "\$@" > "\$d/gh-create.argv"; printf 'https://github.com/example/example/pull/99\n' ;;
  "pr view") printf '%s %s\n' "\$(val gh-draft false)" "\$(val gh-head "\$(git -C "\$d" rev-parse HEAD)")" ;;
  "repo view") val gh-repo "true true true" ;;
  "pr checks") val gh-checks pass ;;
  "pr merge")
    shift 2
    printf '%s\n' "\$@" > "\$d/gh-merge.argv"
    rc=\$(val gh-merge.rc 0)
    [ "\$rc" -eq 0 ] || printf 'GraphQL: Base branch policy prohibits the merge\n' >&2
    exit "\$rc" ;;
esac
STUB
  chmod +x stub-bin/gh
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# mship_stub_glab — the same for `glab`, logged to glab.log:
#   glab-pipeline  the head pipeline's status, or `null` for none (default: success)
#   glab-psha      the head pipeline's commit (default: HEAD of this repository)
#   glab-draft     `true`|`false` (default: false)
#   glab-project   merge_method and squash_option (default: merge default_off)
#   glab-merge.rc  the exit code of `mr merge` (default: 0)
mship_stub_glab() {
  local dir="$PWD"
  mkdir -p stub-bin
  cat > stub-bin/glab <<STUB
#!/usr/bin/env bash
d="$dir"
printf '%s\n' "\$*" >> "\$d/glab.log"
val() { if [ -f "\$d/\$1" ]; then cat "\$d/\$1"; else printf '%s\n' "\$2"; fi; }
head=\$(git -C "\$d" rev-parse HEAD)
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "mr list") printf '[]\n' ;;
  "mr create") shift 2; printf '%s\n' "\$@" > "\$d/glab-create.argv"; printf 'https://gitlab.example/example/example/-/merge_requests/99\n' ;;
  "mr view")
    p=\$(val glab-pipeline success)
    if [ "\$p" = null ]; then pipe=null; else
      pipe="{\"id\":5,\"sha\":\"\$(val glab-psha "\$head")\",\"status\":\"\$p\",\"user\":{\"id\":1,\"state\":\"active\"}}"
    fi
    printf '{"iid":99,"state":"opened","draft":%s,"sha":"%s","head_pipeline":%s}\n' "\$(val glab-draft false)" "\$head" "\$pipe" ;;
  "api projects/:id")
    read -r mm so <<EOF
\$(val glab-project "merge default_off")
EOF
    printf '{"id":1,"namespace":{"id":2,"kind":"group"},"merge_method":"%s","squash_option":"%s"}\n' "\$mm" "\$so" ;;
  "mr merge")
    shift 2
    printf '%s\n' "\$@" > "\$d/glab-merge.argv"
    rc=\$(val glab-merge.rc 0)
    [ "\$rc" -eq 0 ] || printf 'ERROR: 405 Method Not Allowed\n' >&2
    exit "\$rc" ;;
esac
STUB
  chmod +x stub-bin/glab
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# mship_setup <github|gitlab> — ship_setup at agent.git: merge with the forge
# stubbed, the knowledge decision recorded and a change staged. CI is given
# no time to wait (agent.ci_timeout 0): each test settles on the first look.
mship_setup() {
  ship_setup
  ship_cfg forge "$1"
  if [ "$1" = github ]; then mship_stub_gh; else mship_stub_glab; fi
  ship_cfg_local agent.git merge
  ship_cfg_local agent.ci_timeout 0
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
}

# assert_no_override <log> — nothing in <log> asked the forge to override its
# rules or to merge later.
assert_no_override() {
  assert_not_contains "$(cat "$1")" "--admin"
  assert_not_contains "$(cat "$1")" "--auto "
  assert_not_contains "$(cat "$1")" "--auto-merge=true"
}

test_task_ship_merge_level_merges_on_green_checks_at_the_shipped_commit() {
  mship_setup github

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
  local argv
  argv=$(cat gh-merge.argv)
  assert_contains "$argv" "https://github.com/example/example/pull/99"
  assert_contains "$argv" "$(printf -- '--match-head-commit\n%s' "$(git rev-parse HEAD)")"
  assert_contains "$argv" "--merge"
  assert_no_override gh.log
}

test_task_ship_merge_level_takes_squash_when_merge_commits_are_not_allowed() {
  mship_setup github
  printf 'false true true\n' > gh-repo

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "merged "
  assert_contains "$(cat gh-merge.argv)" "--squash"
  assert_not_contains "$(cat gh-merge.argv)" "--merge"
}

test_task_ship_merge_level_does_not_merge_without_any_check() {
  mship_setup github
  : > gh-checks

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: CI checked nothing"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_does_not_merge_when_only_skipped_checks_ran() {
  mship_setup github
  printf 'skipping\n' > gh-checks

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: CI checked nothing"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_does_not_merge_on_a_red_check() {
  mship_setup github
  printf 'pass\nfail\npending\n' > gh-checks

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: a check failed"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_does_not_merge_when_checks_outlast_the_timeout() {
  mship_setup github
  printf 'pass\npending\n' > gh-checks

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: the checks did not finish within 0 minutes (agent.ci_timeout)"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_forge_refusal_leaves_the_pr_open_and_exits_0() {
  mship_setup github
  printf '1\n' > gh-merge.rc

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: the forge refused: GraphQL: Base branch policy prohibits the merge"
  assert_file gh-merge.argv
  assert_no_override gh.log
}

test_task_ship_merge_level_does_not_merge_a_draft() {
  mship_setup github
  printf 'true\n' > gh-draft

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: the pull request is a draft"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_does_not_merge_a_pr_at_another_commit() {
  mship_setup github
  printf '0123456789abcdef0123456789abcdef01234567\n' > gh-head

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: the pull request is at 0123456789abcdef0123456789abcdef01234567"
  assert_no_file gh-merge.argv
}

test_task_ship_draft_opens_a_draft_and_never_merges() {
  mship_setup github

  run jig task ship T-1 --message-file msg.txt --draft
  assert_eq 0 "$RC"
  assert_contains "$(cat gh-create.argv)" "--draft"
  assert_contains "$OUT" "not merged: a draft pull request is never merged"
  assert_no_file gh-merge.argv
}

# Repairs ran out: the finding that stopped the run is still open and no
# knowledge decision was made. A draft is still shipped, and never merged.
test_task_ship_draft_ships_an_unfinished_task_with_its_blocking_finding() {
  ship_setup
  ship_cfg forge github
  mship_stub_gh
  ship_cfg_local agent.git merge
  ship_cfg_local agent.ci_timeout 0
  ship_stage_change
  jig task finding add T-1 --severity P1 --where - --summary "still broken" >/dev/null

  run jig task ship T-1 --message-file msg.txt --draft
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
  assert_contains "$(cat gh-create.argv)" "--draft"
  assert_contains "$OUT" "not merged: a draft pull request is never merged"
  assert_no_file gh-merge.argv
}

test_task_ship_draft_at_pr_level_opens_a_draft() {
  ship_setup
  ship_cfg forge github
  ship_stub_gh ""
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt --draft
  assert_eq 0 "$RC"
  assert_contains "$(cat gh-create.argv)" "--draft"
  assert_not_contains "$OUT" "merged"
}

test_task_ship_pr_level_never_merges() {
  mship_setup github
  ship_cfg_local agent.git pr

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "merged"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_refuses_with_a_blocking_finding_and_merges_nothing() {
  mship_setup github
  jig task finding add T-1 --severity P1 --where - --summary "broken" >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "blocking finding"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_refuses_with_a_stale_receipt_and_merges_nothing() {
  mship_setup github
  jig task receipt T-1 --stage review >/dev/null
  printf 'changed after review\n' >> ship.txt
  git add ship.txt

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "review is stale"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_with_no_forge_leaves_the_merge_to_the_human() {
  ship_setup
  ship_cfg forge none
  ship_cfg_local agent.git merge
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no forge available; the pull request is the human's"
  assert_contains "$OUT" "not merged: no forge available; the merge is the human's"
}

test_task_ship_merge_level_invalid_ci_timeout_dies() {
  mship_setup github
  ship_cfg_local agent.ci_timeout soon

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task ship: invalid agent.ci_timeout: soon (expected whole minutes)"
  assert_no_file gh-merge.argv
}

test_task_ship_merge_level_ignores_the_project_ci_timeout() {
  mship_setup github
  sed '/^agent.ci_timeout:/d' .ai/config.local.yaml > .ai/config.local.yaml.tmp
  mv .ai/config.local.yaml.tmp .ai/config.local.yaml
  printf 'agent.ci_timeout: soon\n' >> .ai/config.yaml

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

test_task_ship_merge_level_ignores_agent_git_merge_in_the_project_config() {
  ship_setup
  printf 'agent.git: merge\n' >> .ai/config.yaml
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 3 "$RC"
}

test_task_ship_merge_level_gitlab_merges_on_a_green_pipeline() {
  mship_setup gitlab

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "merged https://gitlab.example/example/example/-/merge_requests/99"
  local argv
  argv=$(cat glab-merge.argv)
  assert_contains "$argv" "$(printf '99\n--sha\n%s' "$(git rev-parse HEAD)")"
  assert_contains "$argv" "--yes"
  assert_contains "$argv" "--auto-merge=false"
  assert_not_contains "$argv" "--squash"
  assert_no_override glab.log
}

test_task_ship_merge_level_gitlab_squashes_where_the_project_squashes() {
  mship_setup gitlab
  printf 'merge always\n' > glab-project

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$(cat glab-merge.argv)" "--squash"
}

test_task_ship_merge_level_gitlab_does_not_merge_on_a_failed_pipeline() {
  mship_setup gitlab
  printf 'failed\n' > glab-pipeline

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: a check failed"
  assert_no_file glab-merge.argv
}

test_task_ship_merge_level_gitlab_does_not_merge_without_a_pipeline() {
  mship_setup gitlab
  printf 'null\n' > glab-pipeline

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: CI checked nothing"
  assert_no_file glab-merge.argv
}

test_task_ship_merge_level_gitlab_waits_on_a_pipeline_for_an_older_commit() {
  mship_setup gitlab
  printf '0123456789abcdef0123456789abcdef01234567\n' > glab-psha

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: the checks did not finish within 0 minutes"
  assert_no_file glab-merge.argv
}

test_task_ship_merge_level_gitlab_does_not_merge_a_draft() {
  mship_setup gitlab
  printf 'true\n' > glab-draft

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: the merge request is a draft"
  assert_no_file glab-merge.argv
}

test_task_ship_merge_level_gitlab_refusal_leaves_the_mr_open() {
  mship_setup gitlab
  printf '1\n' > glab-merge.rc

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: the forge refused: ERROR: 405 Method Not Allowed"
}

test_task_ship_draft_with_gitlab_opens_a_draft_mr() {
  mship_setup gitlab

  run jig task ship T-1 --message-file msg.txt --draft
  assert_eq 0 "$RC"
  assert_contains "$(cat glab-create.argv)" "--draft"
  assert_no_file glab-merge.argv
}

# --- findings ledger (design.md, findings-ledger) ------------------------------

test_task_finding_add_assigns_ids_in_order() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task finding add T-1 --severity P1 --where scripts/lib/task.sh:10 --summary "first"
  assert_eq 0 "$RC"
  assert_eq "F1" "$OUT"
  run jig task finding add T-1 --severity P2 --where - --summary "second"
  assert_eq 0 "$RC"
  assert_eq "F2" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/findings "$(printf 'F1\tP1\topen')"
  assert_file_contains .ai/workspace/tasks/T-1/findings "$(printf 'F2\tP2\topen')"
}

test_task_finding_add_invalid_severity_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task finding add T-1 --severity P9 --where - --summary "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid severity: P9"
  assert_no_file .ai/workspace/tasks/T-1/findings
}

test_task_finding_add_empty_summary_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task finding add T-1 --severity P1 --where - --summary ""
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--summary must not be empty"
  assert_no_file .ai/workspace/tasks/T-1/findings
}

test_task_finding_add_tab_in_summary_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task finding add T-1 --severity P1 --where - --summary "$(printf 'a\tb')"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--summary must be a single line with no tab"
  assert_no_file .ai/workspace/tasks/T-1/findings
}

test_task_finding_add_tab_in_where_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task finding add T-1 --severity P1 --where "$(printf 'a\tb')" --summary "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--where must be a single line with no tab"
  assert_no_file .ai/workspace/tasks/T-1/findings
}

test_task_finding_add_missing_flags_die() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task finding add T-1 --where - --summary "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--severity is required"
  run jig task finding add T-1 --severity P1 --summary "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--where is required"
  run jig task finding add T-1 --severity P1 --where -
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--summary is required"
}

test_task_finding_add_unknown_task_dies() {
  task_setup
  run jig task finding add NOPE --severity P1 --where - --summary "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

# Validation runs before the ledger file is touched (conventions/shell.md,
# atomic writes): a refused call leaves an existing ledger byte-identical.
test_task_finding_add_failed_validation_leaves_file_unchanged() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P1 --where - --summary "first" >/dev/null
  local before
  before=$(cat .ai/workspace/tasks/T-1/findings)
  run jig task finding add T-1 --severity P9 --where - --summary "x"
  assert_eq 1 "$RC"
  assert_eq "$before" "$(cat .ai/workspace/tasks/T-1/findings)"
  if ls .ai/workspace/tasks/T-1/findings.tmp.* >/dev/null 2>&1; then
    fail "a failed validation left a tmp file behind"
  fi
}

test_task_finding_set_dismissed_without_reason_dies() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  run jig task finding set T-1 F1 dismissed
  assert_eq 1 "$RC"
  assert_contains "$OUT" "dismissed requires --reason"
  assert_file_contains .ai/workspace/tasks/T-1/findings "$(printf '\topen\t')"
}

test_task_finding_set_dismissed_records_reason() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  run jig task finding set T-1 F1 dismissed --reason "not a real bug"
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/findings "$(printf 'dismissed\t-\tx')"
  assert_file_contains .ai/workspace/tasks/T-1/findings "not a real bug"
}

test_task_finding_set_dismissed_keeps_a_backslash_in_the_reason_literal() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  run jig task finding set T-1 F1 dismissed --reason 'path C:\temp\new is fine'
  assert_eq 0 "$RC"
  assert_eq 1 "$(wc -l < .ai/workspace/tasks/T-1/findings | tr -d ' ')"
  assert_eq 7 "$(awk -F '\t' '{ print NF }' .ai/workspace/tasks/T-1/findings)"
  assert_eq 'path C:\temp\new is fine' "$(awk -F '\t' '{ print $7 }' .ai/workspace/tasks/T-1/findings)"
}

test_task_finding_set_reason_on_non_dismissed_dies() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  run jig task finding set T-1 F1 fixed --reason "irrelevant"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason is only valid with dismissed"
}

test_task_finding_set_invalid_status_dies() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  run jig task finding set T-1 F1 nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid status: nope"
}

test_task_finding_set_unknown_finding_dies() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  run jig task finding set T-1 F9 closed
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown finding: F9"
}

test_task_finding_set_no_ledger_dies() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task finding set T-1 F1 closed
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no findings recorded for task: T-1"
}

test_task_finding_set_closed_only_reopens() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  jig task finding set T-1 F1 closed >/dev/null
  run jig task finding set T-1 F1 fixed
  assert_eq 1 "$RC"
  assert_contains "$OUT" "F1 is closed; only \`open\` follows it"
  run jig task finding set T-1 F1 open
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/findings "$(printf '\topen\t')"
}

test_task_finding_set_dismissed_only_reopens_and_clears_reason() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  jig task finding set T-1 F1 dismissed --reason "not applicable" >/dev/null
  run jig task finding set T-1 F1 closed
  assert_eq 1 "$RC"
  assert_contains "$OUT" "F1 is dismissed; only \`open\` follows it"
  run jig task finding set T-1 F1 open
  assert_eq 0 "$RC"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/findings)" "not applicable"
}

test_task_findings_no_ledger() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task findings T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no findings"
  assert_contains "$OUT" "blocking: 0"
}

test_task_findings_unknown_task_dies() {
  task_setup
  run jig task findings NOPE
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_findings_lists_and_counts_blocking() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P1 --where a.sh:1 --summary "blocking one" >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "not blocking" >/dev/null
  run jig task findings T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "F1 P1 open a.sh:1 blocking one"
  assert_contains "$OUT" "F2 P2 open - not blocking"
  assert_contains "$OUT" "blocking: 1"
}

test_task_findings_blocking_flag_exits_1_when_blocking() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P0 --where - --summary "x" >/dev/null
  run jig task findings T-1 --blocking
  assert_eq 1 "$RC"
  assert_contains "$OUT" "F1 P0 open -"
  assert_contains "$OUT" "blocking: 1"
}

test_task_findings_blocking_flag_exits_0_when_nothing_blocks() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P3 --where - --summary "x" >/dev/null
  run jig task findings T-1 --blocking
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "P3"
  assert_contains "$OUT" "blocking: 0"
}

# --- findings ledger gates completion (design.md §4) ---------------------------

test_task_set_status_ready_refuses_open_p1() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task finding add T-1 --severity P1 --where scripts/lib/task.sh:1374 --summary "bad flag" >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "1 blocking finding (F1 P1 open scripts/lib/task.sh:1374)"
  assert_contains "$OUT" "jig task finding set T-1 F1 closed"
  assert_contains "$OUT" "jig task finding set T-1 F1 dismissed --reason <text>"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
}

test_task_set_status_ready_refuses_fixed_p1() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P1 --where - --summary "x" >/dev/null
  jig task finding set T-1 F1 fixed >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "1 blocking finding (F1 P1 fixed -)"
}

test_task_set_status_ready_succeeds_once_closed() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P1 --where - --summary "x" >/dev/null
  jig task finding set T-1 F1 closed >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

test_task_set_status_ready_open_p2_does_not_block() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

# The spec's own scenario: a T2 task with a planted P1 cannot be consolidated.
test_task_set_knowledge_consolidated_refuses_planted_p1_on_t2_task() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task finding add T-1 --severity P1 --where scripts/lib/task.sh:42 --summary "planted finding" >/dev/null
  run jig task set T-1 knowledge_consolidated true
  assert_eq 1 "$RC"
  assert_contains "$OUT" "blocking finding"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: false"
}

test_task_set_knowledge_consolidated_dismissed_p0_does_not_block() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P0 --where - --summary "x" >/dev/null
  jig task finding set T-1 F1 dismissed --reason "false positive, agreed with the human" >/dev/null
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: true"
}

test_task_set_no_findings_file_unchanged_behaviour() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC"
}

# task ship refuses on a blocking finding even when knowledge_consolidated was
# already true before the finding was planted (a fix landed after
# consolidation), so it must recheck independently of that flag.
test_task_ship_refuses_blocking_finding_planted_after_consolidation() {
  ship_setup
  ship_cfg_local agent.git pr
  sed 's/^knowledge_consolidated:.*/knowledge_consolidated: true/' \
    .ai/workspace/tasks/T-1/state > state.tmp
  mv state.tmp .ai/workspace/tasks/T-1/state
  jig task finding add T-1 --severity P0 --where - --summary "found after consolidation" >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "1 blocking finding (F1 P0 open -)"
  assert_contains "$(git status --porcelain -- ship.txt)" "A  ship.txt"
}

# --- review receipt (design.md, review-receipt) --------------------------------

test_task_receipt_writes_all_keys() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md

  local expected_base
  expected_base=$(sed -n 's/^base_commit:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)

  run jig task receipt T-1 --stage review
  assert_eq 0 "$RC"
  assert_contains "$OUT" "stage: review"

  assert_file .ai/workspace/tasks/T-1/receipt
  local keys
  keys=$(sed -n 's/^\([a-z_]*\):.*/\1/p' .ai/workspace/tasks/T-1/receipt | tr '\n' ' ')
  assert_eq "stage reviewed_at tree base_commit head design findings " "$keys"

  assert_file_contains .ai/workspace/tasks/T-1/receipt "stage: review"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "reviewed_at: $(date +%Y-%m-%d)"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "base_commit: $expected_base"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "findings: -"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/receipt)" "design: -"
}

test_task_receipt_reads_the_worktree_that_holds_the_task_branch() {
  task_setup_nested
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 --worktree >/dev/null
  local wt
  wt=$(git worktree list --porcelain | awk '/^worktree /{ p = substr($0, 10) } /^branch refs\/heads\/task\/T-1$/{ print p }')
  [ -n "$wt" ] || fail "task worktree not found"
  # A commit of its own, so the worktree's HEAD differs from this checkout's.
  printf 'x\n' > "$wt/committed.txt"
  git -C "$wt" add committed.txt && git -C "$wt" commit -q -m "task commit"
  run jig task receipt T-1 --stage review
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "head: $(git -C "$wt" rev-parse HEAD)"
  # A change in the filing checkout is not the task's change.
  printf 'unrelated\n' > unrelated.txt
  run jig task receipt T-1 --check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "receipt: current"
  # A change in the task's own worktree is.
  printf 'task work\n' > "$wt/work.txt"
  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (tree"
}

test_task_receipt_refuses_when_the_task_branch_is_checked_out_nowhere() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  git checkout -q main
  run jig task receipt T-1 --stage review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task receipt: task/T-1 is not checked out in any worktree; review the task where its branch is"
  assert_no_file .ai/workspace/tasks/T-1/receipt
}

test_task_receipt_check_counts_an_unreadable_tree_as_changed() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  git checkout -q main
  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (tree"
}

test_task_receipt_architecture_review_stage() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1 --stage architecture-review
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "stage: architecture-review"
}

test_task_receipt_rereview_replaces_the_stage() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  run jig task receipt T-1 --stage architecture-review
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "stage: architecture-review"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/receipt)" "stage: review"
}

test_task_receipt_unknown_task_dies() {
  task_setup
  run jig task receipt nope --stage review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task receipt: unknown task: nope"
}

test_task_receipt_no_args_dies_with_usage() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task receipt"
}

test_task_receipt_stage_requires_a_value_dies() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1 --stage
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task receipt: --stage requires a value"
}

test_task_receipt_invalid_stage_dies() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1 --stage bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task receipt: invalid stage: bogus (expected review|architecture-review)"
}

test_task_receipt_unknown_argument_dies() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1 --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task receipt: unknown argument: --bogus"
}

test_task_receipt_check_and_stage_are_mutually_exclusive_dies() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1 --check --stage review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task receipt: --stage and --check are mutually exclusive"
}

test_task_receipt_check_none_for_t0_through_t3() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1 --check
  assert_eq 0 "$RC"
  assert_eq "receipt: none" "$OUT"
}

test_task_receipt_check_none_required_for_t4() {
  task_setup
  jig task new T-1 --class T4 >/dev/null
  jig task start T-1 >/dev/null
  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_eq "receipt: none (required for T4)" "$OUT"
}

test_task_receipt_check_current_right_after_writing() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  run jig task receipt T-1 --check
  assert_eq 0 "$RC"
  assert_eq "receipt: current" "$OUT"
}

test_task_receipt_check_stale_after_a_tracked_code_edit_names_tree() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null

  printf '# edited\n' >> AGENTS.md

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (tree, reviewed $(date +%Y-%m-%d))"
}

test_task_receipt_check_stale_after_a_new_untracked_file() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null

  printf 'new\n' > untracked.txt

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (tree"
}

test_task_receipt_check_current_after_editing_knowledge_or_specs() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null

  mkdir -p .ai/knowledge/domains/foo .ai/specs/bar
  printf 'x\n' > .ai/knowledge/domains/foo/OVERVIEW.md
  printf 'x\n' > .ai/specs/bar/roadmap.md

  run jig task receipt T-1 --check
  assert_eq 0 "$RC"
  assert_eq "receipt: current" "$OUT"
}

test_task_receipt_check_current_after_committing_the_reviewed_content() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'work in progress\n' > work.txt
  jig task receipt T-1 --stage review >/dev/null

  git add work.txt
  git commit -q -m "commit the reviewed content"

  run jig task receipt T-1 --check
  assert_eq 0 "$RC"
  assert_eq "receipt: current" "$OUT"
}

# The spec's own scenario: amending a commit after review, changing its
# content, must go stale even though HEAD is not what the receipt pins.
test_task_receipt_check_stale_after_an_amend_that_changes_content() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'work in progress\n' > work.txt
  git add work.txt
  git commit -q -m "wip"
  jig task receipt T-1 --stage review >/dev/null

  printf 'different content\n' > work.txt
  git add work.txt
  git commit -q --amend -m "wip amended"

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (tree"
}

test_task_receipt_check_stale_after_editing_design_md_names_design() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design v1\n' > .ai/workspace/tasks/T-1/design.md
  jig task receipt T-1 --stage review >/dev/null

  printf '# design v2\n' > .ai/workspace/tasks/T-1/design.md

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (design"
}

test_task_receipt_check_stale_after_a_findings_change_names_findings() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null

  jig task finding add T-1 --severity P2 --where - --summary "minor" >/dev/null

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (findings"
}

test_task_receipt_t4_design_hash_covers_spec_and_alternatives() {
  task_setup
  jig task new T-1 --class T4 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md
  printf '# spec\n' > .ai/workspace/tasks/T-1/spec.md
  printf '# alt\n' > .ai/workspace/tasks/T-1/alternatives.md
  jig task receipt T-1 --stage review >/dev/null

  printf '# spec v2\n' > .ai/workspace/tasks/T-1/spec.md

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (design"
}

# The temporary index is thrown away on every path, real or not: whatever is
# staged before `task receipt` runs must read back unchanged afterwards.
test_task_receipt_does_not_touch_the_real_index() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'staged\n' > staged.txt
  git add staged.txt

  local before_cached before_ls
  before_cached=$(git diff --cached --name-only)
  before_ls=$(git ls-files -s)

  run jig task receipt T-1 --stage review
  assert_eq 0 "$RC"

  assert_eq "$before_cached" "$(git diff --cached --name-only)"
  assert_eq "$before_ls" "$(git ls-files -s)"
}

test_task_set_status_ready_refuses_stale_receipt() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  printf '# edited\n' >> AGENTS.md

  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: review is stale: code changed since review on $(date +%Y-%m-%d) (tree); re-review and run: jig task receipt T-1 --stage review"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
}

test_task_set_knowledge_consolidated_refuses_stale_receipt() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  printf '# edited\n' >> AGENTS.md

  run jig task set T-1 knowledge_consolidated true
  assert_eq 1 "$RC"
  assert_contains "$OUT" "review is stale: code changed since review on"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: false"
}

test_task_set_status_ready_refuses_t4_without_a_receipt() {
  task_setup
  jig task new T-1 --class T4 >/dev/null
  jig task start T-1 >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: T4 needs a review receipt; run the independent review, then: jig task receipt T-1 --stage review"
}

test_task_set_status_ready_passes_t3_without_a_receipt() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

# task ship refuses on a stale receipt even when knowledge_consolidated was
# already true before the code changed (a later edit, or a re-review nobody
# ran), so it must recheck independently — same reason as the findings ledger
# recheck above.
test_task_ship_refuses_stale_receipt_planted_after_consolidation() {
  ship_setup
  ship_cfg_local agent.git pr
  jig task receipt T-1 --stage review >/dev/null
  sed 's/^knowledge_consolidated:.*/knowledge_consolidated: true/' \
    .ai/workspace/tasks/T-1/state > state.tmp
  mv state.tmp .ai/workspace/tasks/T-1/state
  printf '# edited after review\n' >> AGENTS.md
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "review is stale: code changed since review on"
  assert_contains "$(git status --porcelain -- ship.txt)" "A  ship.txt"
}

# --- autopilot (design.md under .ai/workspace/tasks/autopilot-run) -------------
#
# `jig task autopilot <id> start|stage|repair|stop|resume|end|report`: a run
# journal (`.ai/workspace/tasks/<id>/autopilot`) plus two script-owned state
# keys (`autopilot`, `autopilot_repairs`). The repair limit (2 per run,
# task.md human gate) is enforced here, not by a skill.

test_task_autopilot_start_writes_state_and_journal() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_eq "autopilot: on" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: on"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 0"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tstart\t')"
}

# --phase marks the run as one task of a roadmap phase run: a coordinator
# started it, owns the spec and ships it
# (adr-20260922-a-phase-run-is-coordinated).
test_task_autopilot_start_with_a_phase_records_it_in_state_and_journal() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 start --phase autopilot/4
  assert_eq 0 "$RC"
  assert_contains "$OUT" "autopilot: on"
  assert_contains "$OUT" "phase: autopilot/4"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_phase: autopilot/4"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tstart\tattended phase autopilot/4')"
}

test_task_autopilot_start_without_a_phase_records_none() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "phase:"
  ! grep -q autopilot_phase .ai/workspace/tasks/T-1/state \
    || fail "autopilot_phase was written for a run started without --phase"
}

test_task_autopilot_start_rejects_a_malformed_phase() {
  task_setup
  task_started T-1
  local bad
  for bad in autopilot 4 autopilot/ /4 autopilot/x autopilot/4/5 .bad/4; do
    run jig task autopilot T-1 start --phase "$bad"
    assert_eq 1 "$RC" "expected --phase $bad to be refused"
    assert_contains "$OUT" "--phase takes <spec-id>/<n>"
  done
  run jig task autopilot T-1 start --phase
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--phase requires a value"
}

# autopilot_phase is the script's, like every other autopilot key.
test_task_set_refuses_autopilot_phase() {
  task_setup
  task_started T-1
  run jig task set T-1 autopilot_phase autopilot/4
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: key is not writable: autopilot_phase"
}

test_task_autopilot_start_already_running_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 start
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already running: T-1"
}

test_task_autopilot_start_on_a_stopped_run_points_to_resume() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stop --reason "human gate" >/dev/null
  run jig task autopilot T-1 start
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is stopped; run: jig task autopilot T-1 resume"
}

test_task_autopilot_start_after_done_starts_a_fresh_run() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason "r1" >/dev/null
  jig task autopilot T-1 end >/dev/null
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_eq "autopilot: on" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 0"
}

test_task_autopilot_start_unknown_task_dies() {
  task_setup
  run jig task autopilot NOPE start
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_autopilot_start_invalid_id_dies() {
  task_setup
  run jig task autopilot ../nope start
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid task id"
}

test_task_autopilot_start_unknown_argument_dies() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 start --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument: --bogus"
}

test_task_autopilot_no_id_dies_with_usage() {
  task_setup
  run jig task autopilot
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task autopilot"
}

test_task_autopilot_unknown_action_dies_with_usage() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task autopilot"
}

test_task_autopilot_help_prints_multiline_usage() {
  task_setup
  run_split jig task autopilot --help
  assert_eq 0 "$RC"
  assert_contains "$OUT" "usage: jig task autopilot <id> start"
  assert_contains "$OUT" "jig task autopilot <id> stage <name>"
  assert_contains "$OUT" "jig task autopilot <id> repair --reason <text>"
  assert_contains "$OUT" "jig task autopilot <id> report"
  assert_eq "" "$ERR"
}

test_task_autopilot_stage_logs_name() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stage analyze
  assert_eq 0 "$RC"
  assert_eq "stage: analyze" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tstage\tanalyze')"
}

test_task_autopilot_stage_invalid_name_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stage "Bad Name"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid name: Bad Name"
}

test_task_autopilot_stage_requires_active_run_dies() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 stage analyze
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no active autopilot run: T-1"
}

test_task_autopilot_stage_missing_name_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stage
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task autopilot"
}

test_task_autopilot_stage_unknown_task_dies() {
  task_setup
  run jig task autopilot NOPE stage analyze
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_autopilot_repair_first_and_second_succeed() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 repair --reason "fix lint"
  assert_eq 0 "$RC"
  assert_eq "repair 1/2" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 1"
  run jig task autopilot T-1 repair --reason "fix test"
  assert_eq 0 "$RC"
  assert_eq "repair 2/2" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 2"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: on"
}

test_task_autopilot_repair_third_stops_the_run_and_exits_3() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason "r1" >/dev/null
  jig task autopilot T-1 repair --reason "r2" >/dev/null
  run jig task autopilot T-1 repair --reason "r3"
  assert_eq 3 "$RC"
  assert_eq "stop: repair limit reached (2)" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 2"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tstop\trepair limit reached (2): r3')"
}

test_task_autopilot_repair_requires_reason() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 repair
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason is required"
}

test_task_autopilot_repair_reason_requires_a_value_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 repair --reason
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason requires a value"
}

test_task_autopilot_repair_empty_reason_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 repair --reason ""
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason must not be empty"
}

test_task_autopilot_repair_tab_in_reason_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 repair --reason "$(printf 'a\tb')"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason must be a single line with no tab"
}

test_task_autopilot_repair_unknown_argument_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 repair --reason x --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument: --bogus"
}

test_task_autopilot_repair_requires_active_run_dies() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 repair --reason "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no active autopilot run: T-1"
}

test_task_autopilot_repair_unknown_task_dies() {
  task_setup
  run jig task autopilot NOPE repair --reason x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_autopilot_stop_requires_reason() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stop
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason is required"
}

test_task_autopilot_stop_sets_stopped_and_logs_reason() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stop --reason "needs a human decision"
  assert_eq 0 "$RC"
  assert_eq "autopilot: stopped" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tstop\tneeds a human decision')"
}

test_task_autopilot_stop_empty_reason_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stop --reason ""
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason must not be empty"
}

test_task_autopilot_stop_tab_in_reason_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stop --reason "$(printf 'a\tb')"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason must be a single line with no tab"
}

test_task_autopilot_stop_requires_active_run_dies() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 stop --reason x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no active autopilot run: T-1"
}

test_task_autopilot_stop_unknown_task_dies() {
  task_setup
  run jig task autopilot NOPE stop --reason x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_autopilot_resume_resets_repairs_and_sets_on() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason r1 >/dev/null
  jig task autopilot T-1 stop --reason "gate" >/dev/null
  run jig task autopilot T-1 resume
  assert_eq 0 "$RC"
  assert_eq "autopilot: on" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: on"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 0"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tresume\t')"
  # The reset is real, not cosmetic: two more repairs after resume must not
  # trip the limit early.
  run jig task autopilot T-1 repair --reason r2
  assert_eq 0 "$RC"
  assert_eq "repair 1/2" "$OUT"
}

test_task_autopilot_resume_not_stopped_dies() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 resume
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not stopped: T-1"
}

test_task_autopilot_resume_never_started_dies() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 resume
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not stopped: T-1"
}

test_task_autopilot_resume_unknown_task_dies() {
  task_setup
  run jig task autopilot NOPE resume
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_autopilot_end_sets_done() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 end
  assert_eq 0 "$RC"
  assert_eq "autopilot: done" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: done"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tend\t')"
}

test_task_autopilot_end_requires_active_run_dies() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 end
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no active autopilot run: T-1"
}

test_task_autopilot_end_unknown_task_dies() {
  task_setup
  run jig task autopilot NOPE end
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_autopilot_report_no_run_exits_0() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_eq "no autopilot run" "$OUT"
}

test_task_autopilot_report_unknown_task_dies() {
  task_setup
  run jig task autopilot NOPE report
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_autopilot_report_shows_stages_repairs_stop_and_summary() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stage analyze >/dev/null
  jig task autopilot T-1 repair --reason "r1" >/dev/null
  jig task autopilot T-1 repair --reason "r2" >/dev/null
  jig task autopilot T-1 repair --reason "r3" >/dev/null || true
  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" " start"
  assert_contains "$OUT" " stage: analyze"
  assert_contains "$OUT" " repair: r1"
  assert_contains "$OUT" " repair: r2"
  assert_contains "$OUT" " stop: repair limit reached (2): r3"
  assert_contains "$OUT" "autopilot: stopped, repairs: 2/2"
}

test_task_autopilot_report_after_resume_and_end() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stop --reason "gate" >/dev/null
  jig task autopilot T-1 resume >/dev/null
  jig task autopilot T-1 end >/dev/null
  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" " resume"
  assert_contains "$OUT" " end"
  assert_contains "$OUT" "autopilot: done, repairs: 0/2"
}

# task set (design's script-owned keys, schemas/state.md) --------------------

test_task_set_refuses_autopilot_key() {
  task_setup
  task_started T-1
  run jig task set T-1 autopilot on
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_set_refuses_autopilot_repairs_key() {
  task_setup
  task_started T-1
  run jig task set T-1 autopilot_repairs 0
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

# Autopilot must not weaken the completion gate: a task on autopilot with an
# open P1 finding still refuses `status ready`, exactly as it would off
# autopilot (findings-ledger gate, task_set).
test_task_set_status_ready_still_refuses_with_autopilot_on_and_an_open_p1_finding() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task finding add T-1 --severity P1 --where a.sh:1 --summary "bug" >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "blocking finding"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: on"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "status: ready"
}

# --- the live status page (common.sh jig_status_page_touch/_dirty/_flush;
# adr-20260924-the-status-page-keeps-the-readers-place) ---------------------
#
# `jig status --html` writes .ai/runtime/status.html; once it exists, every
# task command that writes state/journal/findings/receipt redraws it
# synchronously through the INSTALLED copy in the main checkout
# (.ai/scripts/jig status --refresh), output discarded, failures ignored. A
# project that never asked for the page gets none created for it.

test_task_status_page_absent_task_new_creates_no_page() {
  task_setup
  jig task new T-1 >/dev/null
  assert_no_file .ai/runtime/status.html
}

test_task_status_page_absent_task_set_creates_no_page() {
  task_setup
  jig task new T-1 >/dev/null
  jig task set T-1 status active >/dev/null
  assert_no_file .ai/runtime/status.html
}

test_task_status_page_absent_autopilot_start_creates_no_page() {
  task_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  jig task autopilot T-1 start >/dev/null
  assert_no_file .ai/runtime/status.html
}

test_task_status_page_new_task_appears_on_the_page() {
  task_setup
  jig status --html >/dev/null
  jig task new T-9 >/dev/null
  assert_file_contains .ai/runtime/status.html "<code>T-9</code>"
}

test_task_status_page_set_status_ready_changes_the_page() {
  task_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  jig status --html >/dev/null
  assert_file_contains .ai/runtime/status.html "status=active"

  jig task set T-1 status ready >/dev/null
  assert_file_contains .ai/runtime/status.html "status=ready"
  assert_not_contains "$(cat .ai/runtime/status.html)" "status=active"
}

test_task_status_page_finding_add_line_appears() {
  task_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  jig status --html >/dev/null

  run jig task finding add T-1 --severity P1 --where src/x.sh:10 --summary "bad thing"
  assert_eq 0 "$RC"
  assert_file_contains .ai/runtime/status.html "$OUT P1 open src/x.sh:10"
}

test_task_status_page_autopilot_stop_reason_appears() {
  task_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  jig status --html >/dev/null
  jig task autopilot T-1 start >/dev/null

  jig task autopilot T-1 stop --reason "needs a human decision" >/dev/null
  assert_file_contains .ai/runtime/status.html "Autopilot stopped and is waiting for you"
  assert_file_contains .ai/runtime/status.html "needs a human decision"
}

test_task_status_page_autopilot_third_repair_stop_appears() {
  task_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  jig status --html >/dev/null
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason "r1" >/dev/null
  jig task autopilot T-1 repair --reason "r2" >/dev/null

  run jig task autopilot T-1 repair --reason "r3"
  assert_eq 3 "$RC"
  assert_file_contains .ai/runtime/status.html "Autopilot stopped and is waiting for you"
}

# A failing redraw (a broken installed copy) must not change the triggering
# command's own output or exit code, and must leave the page as it was:
# jig_status_page_touch discards the redraw's output and ignores its failure.
test_task_status_page_failing_redraw_does_not_change_output_exit_code_or_page() {
  task_setup
  jig task new T-1 >/dev/null
  jig status --html >/dev/null
  local page_before
  page_before=$(cat .ai/runtime/status.html)

  cat > .ai/scripts/jig <<'BROKEN'
#!/bin/sh
printf 'garbage on stdout\n'
printf 'garbage on stderr\n' >&2
exit 1
BROKEN
  chmod +x .ai/scripts/jig

  run jig task set T-1 class T2
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
  assert_eq "$page_before" "$(cat .ai/runtime/status.html)"
}

# A task command run in a task worktree redraws the MAIN checkout's page
# (jig_config_clone_root), through that checkout's own installed jig.
test_task_status_page_worktree_command_redraws_the_main_checkouts_page() {
  task_setup_nested
  jig task new T-1 --class T1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  jig status --html >/dev/null
  assert_no_file "$wt/.ai/runtime/status.html"
  assert_file_contains .ai/runtime/status.html "class=T1"

  ( cd "$wt" && jig task set T-1 class T2 >/dev/null )

  assert_file_contains .ai/runtime/status.html "class=T2"
  assert_not_contains "$(cat .ai/runtime/status.html)" "class=T1"
}

# --- the human gate (task_gate, _task_gate_state; ADR-0031) -------------------
#
# `jig task gate <id> approved` records a T3/T4 design's approval: only T3/T4,
# only with a design.md in the workspace, writing `gate: approved` and
# `gate_design: <hash>` (the same design hash a review receipt pins).

test_task_gate_refused_for_t2() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md

  run jig task gate T-1 approved
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1 is T2; only T3 and T4 tasks have a human gate"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "gate:"
}

test_task_gate_refused_for_unclassified() {
  task_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null

  run jig task gate T-1 approved
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1 is unclassified; only T3 and T4 tasks have a human gate"
}

test_task_gate_refused_without_design_md() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null

  run jig task gate T-1 approved
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1 has no design.md to approve"
}

test_task_gate_refused_for_a_decision_other_than_approved() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md

  run jig task gate T-1 rejected
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown decision: rejected"
}

test_task_gate_unknown_task_dies() {
  task_setup
  run jig task gate NOPE approved
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_gate_approved_writes_state_matching_the_receipts_design_pin() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md

  run jig task gate T-1 approved
  assert_eq 0 "$RC"
  assert_eq "gate: approved" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate: approved"

  local gate_design receipt_design
  gate_design=$(sed -n 's/^gate_design:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  [ -n "$gate_design" ] || fail "gate_design was not recorded"

  jig task receipt T-1 --stage review >/dev/null
  receipt_design=$(sed -n 's/^design:[[:space:]]*//p' .ai/workspace/tasks/T-1/receipt)
  assert_eq "$receipt_design" "$gate_design" "gate_design must equal the receipt's design pin"
}

test_task_set_refuses_gate_and_pr_url_keys() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  local key
  for key in gate gate_design pr_url; do
    run jig task set T-1 "$key" x
    assert_eq 1 "$RC" "task set accepted key [$key]"
    assert_contains "$OUT" "not writable"
  done
}

# --- the human gate on the status page ----------------------------------------

test_task_status_page_gate_waiting_approved_and_changed_states() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design v1\n' > .ai/workspace/tasks/T-1/design.md
  jig status --html >/dev/null

  assert_file_contains .ai/runtime/status.html "A design is waiting for your decision"

  jig task gate T-1 approved >/dev/null
  assert_file_contains .ai/runtime/status.html "design approved"
  assert_not_contains "$(cat .ai/runtime/status.html)" "A design is waiting for your decision"

  printf '# design v2\n' > .ai/workspace/tasks/T-1/design.md
  # Editing a file in the workspace does not itself redraw; a task command does.
  jig task set T-1 status active >/dev/null
  assert_file_contains .ai/runtime/status.html "A design changed after you approved it"
}

# --- ship stores pr_url (design.md, .ai/specs/autopilot/) ---------------------

test_task_ship_pr_level_records_pr_url_in_state() {
  ship_setup
  ship_cfg forge github
  ship_stub_gh ""
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "pr_url: https://github.com/example/example/pull/99"
}

test_task_ship_pr_level_already_open_pr_still_records_pr_url_in_state() {
  ship_setup
  ship_cfg forge github
  ship_stub_gh "https://github.com/example/example/pull/7"
  ship_cfg_local agent.git pr
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "pr_url: https://github.com/example/example/pull/7"
}

# --- unattended runs (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci)

# unattended_local — opt this clone in to runs that ask nothing.
unattended_local() {
  printf 'autopilot.unattended: true\n' >> .ai/config.local.yaml
}

test_task_autopilot_start_records_the_attended_mode_by_default() {
  task_setup
  task_started T-1
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_eq "autopilot: on" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_mode: attended"
}

test_task_autopilot_start_records_the_unattended_mode() {
  task_setup
  task_started T-1
  unattended_local
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_eq "autopilot: on (unattended)" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_mode: unattended"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tstart\tunattended')"
}

test_task_autopilot_unattended_in_the_project_config_is_ignored() {
  task_setup
  task_started T-1
  printf 'autopilot.unattended: true\n' >> .ai/config.yaml
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_mode: attended"
}

test_task_autopilot_mode_holds_when_the_key_changes_mid_run() {
  task_setup
  task_started T-1
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stop --reason "x" >/dev/null
  : > .ai/config.local.yaml
  jig task autopilot T-1 resume >/dev/null
  run jig task autopilot T-1 decide --reason "kept the old API"
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_mode: unattended"
}

test_task_autopilot_approve_and_decide_are_refused_in_an_attended_run() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 approve --reason "design"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "run is attended; stop and ask the human instead"
  run jig task autopilot T-1 decide --reason "choice"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "run is attended"
  if grep -q "$(printf '\t')decide$(printf '\t')" .ai/workspace/tasks/T-1/autopilot; then
    fail "a refused decide was journaled"
  fi
}

test_task_autopilot_approve_and_decide_need_a_running_run_and_a_reason() {
  task_setup
  task_started T-1
  unattended_local
  run jig task autopilot T-1 decide --reason "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no active autopilot run"
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 approve
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task autopilot approve: --reason is required"
  run jig task autopilot T-1 decide --reason "$(printf 'a\tb')"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason must be a single line with no tab"
}

test_task_autopilot_report_lists_what_was_decided_and_self_approved() {
  task_setup
  task_started T-1
  unattended_local
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 approve --reason "design.md approved at the gate"
  assert_eq 0 "$RC"
  assert_eq "approve: design.md approved at the gate" "$OUT"
  jig task autopilot T-1 decide --reason "kept the old flag name: renaming it breaks callers" >/dev/null
  jig task autopilot T-1 decide --reason "did not delete the old directory" >/dev/null
  jig task autopilot T-1 end >/dev/null

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" "$(printf 'Decided without you:\n- kept the old flag name: renaming it breaks callers\n- did not delete the old directory')"
  assert_contains "$OUT" "$(printf 'Approved by the agent, not a human:\n- design.md approved at the gate')"
  assert_contains "$OUT" "autopilot: done, repairs: 0/2, unattended"
}

test_task_autopilot_report_has_no_blocks_for_an_attended_run() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 report
  assert_not_contains "$OUT" "Decided without you"
  assert_not_contains "$OUT" "Approved by the agent"
  assert_not_contains "$OUT" "unattended"
}

test_task_autopilot_unattended_repair_limit_still_stops_with_exit_3() {
  task_setup
  task_started T-1
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason "r1" >/dev/null
  jig task autopilot T-1 repair --reason "r2" >/dev/null
  run jig task autopilot T-1 repair --reason "r3"
  assert_eq 3 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"
}

test_task_gate_by_agent_in_an_unattended_run_records_who_approved() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md
  unattended_local
  jig task autopilot T-1 start >/dev/null

  run jig task gate T-1 approved --by agent
  assert_eq 0 "$RC"
  assert_eq "gate: approved by the agent" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate: approved"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate_by: agent"
}

test_task_gate_by_agent_is_refused_outside_an_unattended_run() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md

  run jig task gate T-1 approved --by agent
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the gate is the human's"
  jig task autopilot T-1 start >/dev/null
  run jig task gate T-1 approved --by agent
  assert_eq 1 "$RC"
  if grep -q '^gate:' .ai/workspace/tasks/T-1/state; then
    fail "a refused self-approval recorded the gate"
  fi
}

test_task_gate_records_a_human_by_default() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md
  run jig task gate T-1 approved
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate_by: human"
  run jig task gate T-1 approved --by robot
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task gate: invalid --by: robot (expected human|agent)"
}

test_task_set_refuses_autopilot_mode_and_gate_by_keys() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  local key
  for key in autopilot_mode gate_by; do
    run jig task set T-1 "$key" x
    assert_eq 1 "$RC"
    assert_contains "$OUT" "task set: key is not writable: $key"
  done
}

# --- shipping a project nothing verifies -------------------------------------
#
# When no profile covers the project, `jig verify` says so and does not refuse:
# there is nothing to install and nothing to wait for. The cost of not refusing
# is that the sentence has to be read, so `task ship` repeats it at the moment
# the change leaves the machine — where it has consequences — rather than
# leaving it in a run ten minutes earlier
# (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).

test_task_ship_says_nothing_verifies_a_project_no_profile_covers() {
  ship_setup
  ship_cfg_local agent.git commit
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  # The fixture project runs `generic` alone, which declares `detect: always`
  # and therefore covers no stack.
  assert_file_contains .ai/config.yaml "generic"

  run jig task ship T-1 --message-file msg.txt
  # Said, never enforced: the ship goes through.
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "no profile covers this project, so nothing verifies it; this ships unverified"
}

# The other half of the same cut: once something does cover the project, the
# notice is wrong and must not appear. A `task ship` that printed it either way
# would be noise, and noise is how a true line stops being read.
test_task_ship_is_silent_about_verification_when_a_profile_covers_the_project() {
  ship_setup
  ship_cfg_local agent.git commit
  jig task set T-1 knowledge_consolidated true >/dev/null
  # A profile that claims a stack rather than covering everything.
  mkdir -p .ai/profiles/stack
  printf 'name: stack\ndescription: fixture profile that covers a stack.\ndetect: [stack.toml]\n' \
    > .ai/profiles/stack/profile.yaml
  # Replaced, never appended: `cfg` reads the first `profiles:` line, so an
  # appended one changes nothing and the test would pass for no reason.
  sed 's/^profiles:.*/profiles: [generic, stack]/' .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml
  # Matched without the brackets: assert_file_contains greps a regex, and
  # `[generic, stack]` would read as a character class rather than a literal.
  assert_file_contains .ai/config.yaml "generic, stack"
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "committed "
  assert_not_contains "$OUT" "ships unverified"
}
