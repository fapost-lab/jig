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
  for provided in '' ',design' 'design,' 'design,,spec' approval implementation 'design,design'; do
    run jig task artifacts scoped --provided "$provided"
    assert_eq 1 "$RC"
    assert_contains "$OUT" 'task artifacts:'
  done
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
  local wt owner
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  owner=$(cd .ai/workspace/tasks/T-1 && pwd -P)

  [ -L "$wt/.ai/workspace/tasks/T-1" ] || fail "the worktree has no link to the workspace"
  assert_eq "$owner" "$(cd "$wt/.ai/workspace/tasks/T-1" && pwd -P)"
  grep -qx 'branch: task/T-1' .ai/workspace/tasks/T-1/state || fail "branch not recorded"
  grep -q '^base_commit: [0-9a-f]\{40\}$' .ai/workspace/tasks/T-1/state || fail "base_commit not recorded"
  # Inside the worktree the task is current, and the link leaves git clean.
  assert_eq "T-1" "$(cd "$wt" && jig task current)"
  assert_eq "" "$(git -C "$wt" status --porcelain)"
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
  [ -L "$wt/.ai/workspace/tasks/T-1" ] || fail "the worktree has no link to the workspace"
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
# made-up URL.
ship_stub_gh() {
  local existing="${1:-}"
  mkdir -p stub-bin
  cat > stub-bin/gh <<STUB
#!/usr/bin/env bash
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

test_task_ship_empty_index_prints_nothing_staged_no_commit() {
  ship_setup
  ship_cfg_local agent.git commit
  jig task set T-1 knowledge_consolidated true >/dev/null
  local head_before
  head_before=$(git rev-parse HEAD)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "nothing staged; no commit"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
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
  assert_contains "$OUT" "task ship: invalid agent.git: yolo (expected none|commit|push|pr)"
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

