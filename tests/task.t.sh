# Tests for `jig task` (SPEC §14, §15, §29; ADR-0005; ADR-0008).
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
  # exact key order: task_id, branch, status, knowledge_consolidated,
  # created_at, updated_at (no class/domains: not given).
  local keys
  keys=$(sed -n 's/^\([a-z_]*\):.*/\1/p' .ai/workspace/tasks/T-1/state | tr '\n' ' ')
  assert_eq "task_id branch base_commit status knowledge_consolidated created_at updated_at " "$keys"

  assert_file_contains .ai/workspace/tasks/T-1/state "task_id: T-1"
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: task/T-1"
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
  assert_eq "task_id branch base_commit class status knowledge_consolidated domains created_at updated_at " "$keys"
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
  assert_eq "task_id branch base_commit class status knowledge_consolidated domains created_at updated_at " "$keys"
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

test_task_new_detached_head_records_detached_branch() {
  task_setup
  git checkout -q --detach main
  # --no-branch keeps the checkout detached; with a branch created there is
  # no longer a detached HEAD to record.
  run jig task new T-1 --no-branch
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
  assert_eq "task_id branch base_commit status knowledge_consolidated domains created_at updated_at " "$keys"
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
  jig task new T-2 >/dev/null
  jig task new T-1 --class T1 >/dev/null
  git checkout -q -b other
  # --no-branch so T-3 keeps the checkout's own branch: the point of this
  # line is that a task belonging to a *different* branch still appears in
  # the listing, which needs a branch this test chose rather than one
  # task new derived from the id.
  jig task new T-3 --no-branch >/dev/null

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
  jig task new T-1 >/dev/null
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
  # --no-branch on purpose: two tasks must share one branch for this to be a
  # test of candidate selection at all. With branch-per-task on (the default)
  # they cannot collide, which is the point of that feature — so ambiguity is
  # now only reachable the way it is reproduced here.
  jig task new T-1 --no-branch >/dev/null
  jig task new T-2 --no-branch >/dev/null
  jig task pause T-2 >/dev/null
  # With T-2 paused, T-1 is the only candidate left: deterministic, not
  # ambiguous, even though both share the branch and an active-ish status.
  run jig task current
  assert_eq 0 "$RC"
  assert_eq "T-1" "$OUT"
}

test_task_current_several_candidates_exits_2_lists_both_nothing_on_stdout() {
  task_setup
  # Two tasks on one branch: only reachable with --no-branch now.
  jig task new T-1 --no-branch >/dev/null
  jig task new T-2 --no-branch >/dev/null
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
  jig task new T-1 >/dev/null
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
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null
  jig task pause T-1 >/dev/null

  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "T-1 class=- status=active branch=task/T-1 paused"
  assert_not_contains "$OUT" "T-2 class=- status=active branch=main paused"
}

# --- new: dirty-tree refusal (design §6) -----------------------------------------------

test_task_new_refuses_dirty_tracked_tree_names_task_and_passes_with_force() {
  task_setup
  jig task new T-1 >/dev/null
  printf 'dirty\n' >> README.md

  run jig task new T-2
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1"
  assert_no_file .ai/workspace/tasks/T-2

  run jig task new T-2 --force
  assert_eq 0 "$RC"
  assert_file .ai/workspace/tasks/T-2/state
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

test_task_new_creates_and_checks_out_a_branch() {
  task_setup
  run jig task new T-1
  assert_eq 0 "$RC"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: task/T-1"
}

test_task_new_records_the_commit_it_forked_from() {
  # Without this, ancestry cannot tell "this branch has done nothing" from
  # "this branch was fast-forwarded in": in both cases the tip equals the base.
  task_setup
  local head_before
  head_before=$(git rev-parse HEAD)

  jig task new T-1 >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/state "base_commit: $head_before"
}

test_task_new_branch_is_cut_from_the_base_branch_not_head() {
  # A task is work proposed against the base. Starting it wherever the
  # checkout happened to be is how a task inherits an unrelated history.
  task_setup
  git checkout -q -b unrelated
  printf 'unrelated\n' > unrelated.txt
  git add unrelated.txt
  git commit -q -m "unrelated work"

  jig task new T-1 --force >/dev/null
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  # The unrelated commit must not be an ancestor of the new branch.
  if git merge-base --is-ancestor unrelated HEAD 2>/dev/null; then
    fail "task branch was cut from HEAD, not from the base branch"
  fi
}

test_task_new_no_branch_keeps_the_current_checkout() {
  task_setup
  run jig task new T-1 --no-branch
  assert_eq 0 "$RC"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: main"
  if grep -q '^base_commit:' .ai/workspace/tasks/T-1/state; then
    fail "no branch was created, so there is no fork point to record"
  fi
}

test_task_new_respects_branch_per_task_false() {
  task_setup
  sed 's|^git.branch_per_task:.*|git.branch_per_task: false|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_task_new_uses_the_configured_branch_template() {
  task_setup
  sed 's|^git.branch_template:.*|git.branch_template: wip/{id}-x|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  jig task new T-1 >/dev/null
  assert_eq "wip/T-1-x" "$(git symbolic-ref --short HEAD)"
}

test_task_new_rejects_a_template_without_the_id() {
  task_setup
  sed 's|^git.branch_template:.*|git.branch_template: wip/fixed|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  run jig task new T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "must contain {id}"
  assert_no_file .ai/workspace/tasks/T-1/state
}

test_task_new_rejects_a_branch_name_git_would_reject() {
  # git's own rules, not a hand-rolled regex: the invalid set is long and
  # creating a ref nobody can delete without plumbing is the failure mode.
  task_setup
  sed 's|^git.branch_template:.*|git.branch_template: bad..{id}|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  run jig task new T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "git rejects the branch name"
  assert_no_file .ai/workspace/tasks/T-1/state
}

test_task_new_refuses_an_existing_branch_and_leaves_nothing_behind() {
  task_setup
  git branch task/T-1

  run jig task new T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "branch already exists"
  assert_no_file .ai/workspace/tasks/T-1/state
  assert_no_file .ai/workspace/tasks/T-1
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_task_set_refuses_to_write_base_commit() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 base_commit deadbeef
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
}

test_task_new_branches_from_head_in_a_repository_with_no_base_branch() {
  # Documented fallback: when neither the local nor the remote base branch
  # resolves, the branch is cut from HEAD, which is the only thing there is.
  task_setup
  git branch -m main trunk
  # git.base_branch still says `main`, which now resolves to nothing.
  run jig task new T-1
  assert_eq 0 "$RC"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  assert_file_contains .ai/workspace/tasks/T-1/state "base_commit: $(git rev-parse trunk)"
}
