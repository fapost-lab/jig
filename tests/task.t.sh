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
run_split() {
  local errfile="run_split.stderr.$$"
  OUT=$("$@" 2>"$errfile")
  RC=$?
  ERR=$(cat "$errfile")
  rm -f "$errfile"
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
  mkdir repo && cd repo || return 1
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

