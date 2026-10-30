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
  assert_eq "task_id status knowledge_consolidated route_evidence created_at updated_at " "$keys"

  assert_file_contains .ai/workspace/tasks/T-1/state "task_id: T-1"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: false"
  assert_file_contains .ai/workspace/tasks/T-1/state "created_at: $(date +%Y-%m-%d)"
  assert_file_contains .ai/workspace/tasks/T-1/state "updated_at: $(date +%Y-%m-%d)"
}

# The state file is the claim on the id, not the directory. A `mkdir` that
# succeeds for a second maker lets two `task new` past the existence check at
# once; this one plays the race out: making the task's directory, it also lets
# the rival's state land first, then reports success as uutils does.
test_task_new_refuses_a_taken_id_where_mkdir_excludes_nobody() {
  task_setup
  local real
  real=$(command -v mkdir)
  mkdir -p uubin
  cat > uubin/mkdir <<EOF
#!/bin/sh
"$real" -p "\$@" || exit 1
for d in "\$@"; do
  case "\$d" in
    */tasks/T-1) printf 'task_id: T-1\\nclass: T2\\n' > "\$d/state" ;;
  esac
done
EOF
  chmod +x uubin/mkdir
  PATH="$PWD/uubin:$PATH"
  run jig task new T-1 --class T1
  assert_eq 1 "$RC" "task new wrote over a state another maker had filed"
  assert_contains "$OUT" "task already exists: T-1"
  assert_file_contains .ai/workspace/tasks/T-1/state "class: T2"
}

test_task_new_with_class_and_domains_order() {
  task_setup
  run jig task new T-1 --class T2 --domains flow,triggers
  assert_eq 0 "$RC"

  local keys
  keys=$(sed -n 's/^\([a-z_]*\):.*/\1/p' .ai/workspace/tasks/T-1/state | tr '\n' ' ')
  assert_eq "task_id class status knowledge_consolidated route_evidence domains created_at updated_at " "$keys"
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
  assert_eq "task_id class status knowledge_consolidated route_evidence domains created_at updated_at " "$keys"
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

# --- new --goal, new --json ---------------------------------------------------
#
# A program files a task without writing a file first (spec contract-queue):
# the short description is the goal paragraph, and with --json the answer is
# the filed task, or a refusal with its code (schemas/json.md).

test_task_new_goal_writes_the_goal_paragraph() {
  task_setup
  run jig task new T-1 --goal '  File the task  from the page '
  assert_eq 0 "$RC"
  # The text form says what it always said: the workspace, nothing else.
  assert_eq ".ai/workspace/tasks/T-1" "$OUT"
  local md=.ai/workspace/tasks/T-1/task.md
  assert_eq "$(printf '# T-1\n\n## Goal\n\nFile the task  from the page\n\n## Scope')" "$(sed -n 1,7p "$md")"
  assert_not_contains "$(cat "$md")" "One paragraph"
  assert_file_contains "$md" "## Notes"
  run jig task list --goals
  assert_contains "$OUT" "goal: File the task  from the page"
  # The built-in brief of an installed copy takes it the same way.
  run jig_installed task new T-2 --goal "Ship it & say so"
  assert_eq 0 "$RC"
  assert_eq "$(printf '# T-2\n\n## Goal\n\nShip it & say so\n\n## Scope')" "$(sed -n 1,7p .ai/workspace/tasks/T-2/task.md)"
}

test_task_new_goal_refuses_what_is_not_one_paragraph() {
  task_setup
  printf 'x\n' > from.md
  run jig task new T-1 --goal "$(printf 'one\ntwo')"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task new: --goal is one line"
  run jig task new T-1 --goal "   "
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task new: --goal is empty"
  run jig task new T-1 --goal " # Heading"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task new: --goal cannot start with #"
  run jig task new T-1 --goal x --from from.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task new: --goal and --from both write task.md"
  run jig task new T-1 --goal
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task new: --goal requires a value"
  assert_no_file .ai/workspace/tasks/T-1
}

# The goal goes in place of the template's placeholder; a brief whose heading
# is followed by text keeps it below the goal, and one without the heading
# gets one.
test_task_new_goal_lands_under_the_goal_heading_of_any_brief() {
  task_setup
  local got
  got=$(
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/task.sh"
    printf '# x\n\n## Goal\nold text\n\n## Scope\n' | _task_md_put_goal 'G \1 &'
    printf -- '--\n'
    printf '# x\n\nBody.\n' | _task_md_put_goal 'G'
    printf -- '--\n'
    printf '# x\n\n## Goal\n\n' | _task_md_put_goal 'G'
  )
  assert_eq "$(printf '# x\n\n## Goal\nG \\1 &\n\nold text\n\n## Scope\n--\n# x\n\nBody.\n\n## Goal\n\nG\n--\n# x\n\n## Goal\n\nG')" "$got"
}

# A brief filed without --goal holds only the template's comment under
# `## Goal`: that is no goal, in the text listing or in JSON. A comment on one
# line or across several is dropped wherever it stands, and a line that held
# only a comment does not end the paragraph.
test_task_goal_leaves_html_comments_out() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task list --goals
  assert_eq 0 "$RC"
  assert_contains "$OUT" "goal: (none)"
  assert_not_contains "$OUT" "<!--"
  _tl_json
  assert_contains "$OUT" '{"id":"T-1","class":null,"status":"active","issue":null,"goal":null,'
  local got f="$JIG_TEST_TMP.goal.md"
  got=$(
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/task.sh"
    printf '# x\n\n## Goal\n\n<!-- One paragraph:\n## not a heading -->\nKeep <!-- why -->the\nreturn URL.\n\nLater.\n' > "$f"
    _task_goal "$f"
    printf '# x\n\n## Goal\n\n<!-- one -->\n\n<!-- two\nlines -->\n\n## Scope\n\nx\n' > "$f"
    _task_goal "$f"
    printf '# x\n\n## Goal\n\nText <!-- open\nstill comment\n--> after.\n' > "$f"
    _task_goal "$f"
  )
  rm -f "$f"
  assert_eq "$(printf 'Keep the return URL.\n(none)\nText after.')" "$got"
}

# _tn_json — `jig task new --json <args>` with stdout in OUT, stderr in ERR,
# generated_at and revision replaced as _tl_json replaces them.
_tn_json() {
  run_split jig task new --json "$@"
  local rc=$RC err=$ERR
  OUT=$(printf '%s\n' "$OUT" | sed -e 's/"generated_at":"[0-9TZ:-]*"/"generated_at":"T"/' -e 's/^{"schema":1,"revision":[0-9][0-9]*,/{"schema":1,"revision":"R",/')
  RC=$rc
  ERR=$err
}

test_task_new_json_answers_with_the_filed_task() {
  task_setup
  local today
  today=$(date +%Y-%m-%d)
  _tn_json T-1 --class T1 --goal 'File "it" from the page'
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  _tl_cut_actions
  # The filed task is the object `task list --json` lists for it.
  assert_eq "{\"schema\":1,\"revision\":\"R\",\"generated_at\":\"T\",\"data\":{\"task\":{\"id\":\"T-1\",\"class\":\"T1\",\"status\":\"active\",\"issue\":null,\"goal\":\"File \\\"it\\\" from the page\",\"knowledge_consolidated\":false,\"paused\":false,\"pause_request\":null,\"created_at\":\"$today\",\"updated_at\":\"$today\",\"archived_at\":null,\"archived_reason\":null,\"archived_from\":null,\"absorbed_into\":null,\"absorbs\":[],\"absorbs_partly\":[],\"partly_in\":[],\"branch\":null,\"base_branch\":\"main\",\"worktree\":null,\"gate\":null,\"autopilot\":null,\"pull_request\":null,\"housekeeping_flags\":[]}}}" "$OUT"
  local actions=$ACTIONS
  _tl_json
  _tl_cut_actions
  assert_eq "$actions" "$ACTIONS"
  assert_contains "$OUT" "{\"id\":\"T-1\",\"class\":\"T1\""
  assert_file .ai/workspace/tasks/T-1/state
  # Without --goal the brief is the template's, and it has no goal yet.
  _tn_json T-2
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"data":{"task":{"id":"T-2","class":null,"status":"active","issue":null,"goal":null,'
  # --json may stand anywhere; the id stays the first of the others.
  run_split jig task new T-3 --lean --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"data":{"task":{"id":"T-3",'
  assert_file_contains .ai/workspace/tasks/T-3/state "route_depth: lean"
}

test_task_new_json_names_why_it_refused() {
  task_setup
  jig task new T-1 >/dev/null
  _tn_json T-1 --goal "again"
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","error":{"code":"already-exists","message":"task new: task already exists: T-1"}}' "$OUT"
  assert_eq "jig: error: task new: task already exists: T-1" "$ERR"
  # A directory left without a state file still holds the id.
  mkdir -p .ai/workspace/tasks/T-2
  _tn_json T-2
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"already-exists","message":"task new: task already exists: T-2"}}'
  # Every usage refusal comes before the id is judged taken: a program told
  # `already-exists` asks for another id, and must not then learn of a bad class.
  _tn_json T-1 --class T9
  assert_contains "$OUT" '"error":{"code":"usage","message":"task new: invalid class: T9"}}'
  _tn_json T-1 --goal ""
  assert_contains "$OUT" '"error":{"code":"usage","message":"task new: --goal is empty"}}'
  _tn_json "bad id!"
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","error":{"code":"usage","message":"task new: invalid task id: bad id!"}}' "$OUT"
  assert_no_file ".ai/workspace/tasks/bad id!"
  _tn_json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"usage","message":"usage: jig task new <id> '
  _tn_json T-4 --nope
  assert_contains "$OUT" '"error":{"code":"usage","message":"task new: unknown argument: --nope"}}'
  _tn_json T-4 --class T9
  assert_contains "$OUT" '"error":{"code":"usage","message":"task new: invalid class: T9"}}'
  _tn_json T-4 --domains Not_Valid
  assert_contains "$OUT" '"error":{"code":"usage","message":"task new: invalid domains: Not_Valid"}}'
  _tn_json T-4 --class
  assert_contains "$OUT" '"error":{"code":"usage","message":"task new: --class requires a value"}}'
  _tn_json T-4 --goal "$(printf 'a\nb')"
  assert_contains "$OUT" '"error":{"code":"usage","message":"task new: --goal is one line: the goal paragraph of task.md"}}'
  assert_no_file .ai/workspace/tasks/T-4
}

# Two `task new` racing for one id both pass the check that the directory is
# absent; the directory itself is the claim, and the second is refused as taken.
# A mkdir on PATH makes the directory appear between the check and the claim.
test_task_new_json_loses_a_race_for_the_id_as_already_exists() {
  task_setup
  local stub="$JIG_TEST_TMP.mkdirstub" real
  real=$(command -v mkdir)
  mkdir -p "$stub"
  cat > "$stub/mkdir" <<EOF
#!/bin/sh
if [ "\$#" -eq 1 ] && [ "\${1##*/}" = T-race ]; then "$real" "\$1"; fi
exec "$real" "\$@"
EOF
  chmod +x "$stub/mkdir"
  PATH="$stub:$PATH" _tn_json T-race
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"already-exists","message":"task new: task already exists: T-race"}}'
  assert_no_file .ai/workspace/tasks/T-race/state
  rm -rf "$stub"
}

test_task_new_json_in_a_project_without_jig_is_an_envelope() {
  mkdir plain
  cd plain
  git init -q
  _tn_json T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"not-initialised","message":"project is not initialised; run: jig init"}}'
  assert_no_file .ai/workspace/tasks/T-1
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
  task_route_class T-1
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

test_task_set_knowledge_consolidated() {
  task_setup
  jig task new T-1 >/dev/null
  task_route_done T-1
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
  assert_eq "task_id status knowledge_consolidated route_evidence domains created_at updated_at " "$keys"
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
  task_route_done T-1
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

# autopilot-end-closes-unmerged-task: a merge alone never closes a task
# (AGENTS.md), and the reverse holds too — closing one never stands in for a
# merge that has not happened. Once `task ship` opened a pull request
# (pr_url), `status consolidated` asks the forge, live, whether it merged;
# silent when no pull request was ever opened (covered above: T-1 there never
# ran `task ship`, and consolidating it succeeds with no forge in play at all).

# pr_check_stub_gh <existing-pr-url> <view-state> — ship_stub_gh's `pr
# list`/`pr create`, plus `gh pr view <url> --json state --jq .state`
# answering <view-state> verbatim (e.g. OPEN, MERGED), or failing outright
# when <view-state> is FAIL — how a network hiccup or a revoked token reads.
pr_check_stub_gh() {
  local existing="${1:-}" state="${2:-OPEN}"
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
      view)
        if [ "$state" = FAIL ]; then
          exit 1
        fi
        printf '%s\n' "$state"
        ;;
    esac
    ;;
esac
STUB
  chmod +x stub-bin/gh
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# pr_check_ship_T1 — ship_setup with GitHub stubbed, at agent.git: pr, that
# opens T-1's pull request. <view-state> answers the later `gh pr view`.
pr_check_ship_T1() {
  ship_setup
  ship_cfg forge github
  pr_check_stub_gh "" "$1"
  ship_cfg_local agent.git pr
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  jig task ship T-1 --message-file msg.txt >/dev/null
}

test_task_set_status_consolidated_refuses_an_open_pull_request() {
  pr_check_ship_T1 OPEN

  run jig task set T-1 status consolidated
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires its pull request to be merged"
  assert_contains "$OUT" "is open"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "status: consolidated"
}

test_task_set_status_consolidated_succeeds_once_the_pull_request_is_merged() {
  pr_check_ship_T1 MERGED

  run jig task set T-1 status consolidated
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: consolidated"
}

test_task_set_status_consolidated_refuses_when_the_forge_cannot_confirm() {
  pr_check_ship_T1 FAIL

  run jig task set T-1 status consolidated
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is unknown"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "status: consolidated"
}

test_task_set_knowledge_consolidated_false_on_consolidated_task_dies() {
  task_setup
  jig task new T-1 >/dev/null
  task_route_done T-1
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
  task_route_class NOPE
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

  task_route_class T-1

  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "updated_at: $(date +%Y-%m-%d)"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "updated_at: 2020-01-01"
}

test_task_set_no_state_tmp_left_behind() {
  task_setup
  jig task new T-1 >/dev/null
  task_route_class T-1
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

# The why of an abandon lands in `state`, where `task show` and the next agent
# read it, not only in a task.md note
# (adr-20261029-an-abandoned-task-says-why-and-its-roadmap-item-follows).
test_task_abandon_records_reason_and_move() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task abandon T-1 --reason "lives in monitoring" --moved-to "../monitoring#sentry-errors"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task abandon: T-1 abandoned, moved to ../monitoring#sentry-errors"
  # Nothing is there in the fixture: the command that files it is printed.
  assert_contains "$OUT" "file it there yourself: (cd ../monitoring && jig task new sentry-errors)"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: abandoned"
  assert_file_contains .ai/workspace/tasks/T-1/state "abandoned_reason: lives in monitoring"
  assert_file_contains .ai/workspace/tasks/T-1/state "moved_to: ../monitoring#sentry-errors"
  assert_file_contains .ai/workspace/tasks/T-1/state "abandoned_at: $(date +%Y-%m-%d)"

  # A second abandon refines the record; a move not repeated is a move no more.
  run jig task abandon T-1 --reason "not needed"
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "abandoned_reason: not needed"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "moved_to:"
}

test_task_abandon_refuses_a_bad_reference_or_reason() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task abandon T-1 --moved-to "/abs/repo#x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task abandon: --moved-to /abs/repo#x: the repository path must be relative"
  run jig task abandon T-1 --moved-to "repo-without-hash"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no # between the repository and the id"
  run jig task abandon T-1 --reason ""
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason must not be empty"
  run jig task abandon T-1 --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task abandon: unknown argument: --bogus"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
}

# A spec-linked task says why, and `task set` is no way around it.
# shellcheck disable=SC2016 # the roadmap's backticks are literal
test_task_abandon_of_a_spec_linked_task_needs_a_reason() {
  task_setup
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf '%s\n' '- [ ] `T-1` — the thing' > .ai/specs/alpha/roadmap.md
  printf 'Spec: .ai/specs/alpha/ — Phase 1\n' >> .ai/workspace/tasks/T-1/task.md
  run jig task abandon T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task abandon: T-1 is linked to spec alpha; say why: jig task abandon T-1 --reason <text>"
  run jig task set T-1 status abandoned
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: T-1 is linked to a spec; abandon it with jig task abandon T-1 --reason <text>"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"

  run jig task abandon T-1 --reason "superseded" --moved-to "packages/mon#spec/monitoring"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "spec drop: T-1 closed in .ai/specs/alpha/roadmap.md"
  assert_contains "$OUT" "add it to that spec yourself"
  assert_eq '- [x] `T-1` — the thing — moved to packages/mon#spec/monitoring ('"$(date +%Y-%m-%d)"'): superseded' \
    "$(cat .ai/specs/alpha/roadmap.md)"
}

# Taken back, a task loses the record of why it was given up; the closed
# roadmap item is the person's to reopen, and they are told so.
# shellcheck disable=SC2016 # the roadmap's backticks are literal
test_task_reopen_clears_the_abandon_record() {
  task_setup
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf '%s\n' '- [ ] `T-1` — the thing' > .ai/specs/alpha/roadmap.md
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  jig task abandon T-1 --reason "later" >/dev/null 2>&1
  run jig task set T-1 status active
  assert_eq 0 "$RC"
  assert_contains "$OUT" "reopen that item by hand"
  local st
  st=$(cat .ai/workspace/tasks/T-1/state)
  assert_not_contains "$st" "abandoned_reason:"
  assert_not_contains "$st" "abandoned_at:"
  # A task linking two specs is linked all the same.
  jig task new T-2 >/dev/null
  printf 'Spec: .ai/specs/alpha/\nSpec: .ai/specs/beta/\n' >> .ai/workspace/tasks/T-2/task.md
  run jig task abandon T-2
  assert_eq 1 "$RC"
  assert_contains "$OUT" "say why"
  run jig task list --json
  assert_contains "$OUT" '"command":"jig task abandon T-2 --reason <text>"'
  run jig task set T-1 abandoned_reason x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: key is not writable: abandoned_reason"
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
  # One session starting task after task in one checkout is not what this test
  # is about; T-2's work record would refuse the next start (checkout.sh).
  jig task new T-1 --class T1 >/dev/null
  rm -rf .ai/runtime/working
  jig task start T-1 >/dev/null
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
  task_route_done T-1
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
    task_route_class "$bad"
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

# state-write-does-not-interpret-escapes: `awk -v` expands `\n`, `\t` and
# other escape sequences in the value it is given, so a reason spelling a
# literal backslash-n (any Windows path, e.g. `C:\temp`) used to be written
# as a real newline and split into a second, bogus state key. The state file
# must hold exactly what the user typed, and exactly one state key from it.
test_task_pause_reason_does_not_interpret_escapes() {
  task_setup
  jig task new T-1 >/dev/null
  local before_base_commit
  before_base_commit=$(sed -n 's/^base_commit:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)

  run jig task pause T-1 --reason 'C:\temp\nbase_commit: x'
  assert_eq 0 "$RC"

  local reason
  reason=$(sed -n 's/^paused_reason:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  assert_eq 'C:\temp\nbase_commit: x' "$reason" "reason was not written literally"

  local reason_lines
  reason_lines=$(grep -c '^paused_reason:' .ai/workspace/tasks/T-1/state)
  assert_eq "1" "$reason_lines" "reason split the state file into a second key"

  local after_base_commit
  after_base_commit=$(sed -n 's/^base_commit:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  assert_eq "$before_base_commit" "$after_base_commit" "an interpreted escape overwrote base_commit"
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

test_task_resume_with_stash_on_wrong_branch_refuses_and_changes_nothing() {
  task_setup_clean
  task_started T-1
  printf 'dirty change\n' >> README.md
  jig task pause T-1 --stash >/dev/null
  git checkout -q -b other

  run jig task resume T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "switch to task/T-1 first"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
  assert_not_contains "$(cat README.md)" "dirty change"
}

# Without a recorded stash there is nothing to apply, so where it runs does not
# matter: the pause is cleared from any branch.
test_task_resume_without_stash_succeeds_from_another_branch() {
  task_setup_clean
  task_started T-1
  jig task pause T-1 >/dev/null
  git checkout -q -b other

  run jig task resume T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "resumed T-1"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused: true"
  assert_eq "other" "$(git symbolic-ref --short HEAD)"
}

# --- resume --json and --revision --------------------------------------------------

# _tr_rev — REV <- the clone's revision, as a read reports it.
_tr_rev() {
  REV=$(jig task list --json 2>/dev/null | sed -n 's/^{"schema":1,"revision":\([0-9][0-9]*\),.*/\1/p')
  [ -n "$REV" ] || fail "no revision in the task list"
}

# _tr_json <args...> — `jig task resume <args> --json`; stdout in OUT, stderr
# in ERR, status in RC.
_tr_json() {
  run_split jig task resume "$@" --json
}

# _tr_code — the error.code of the envelope in OUT.
_tr_code() {
  printf '%s\n' "$OUT" | sed -n 's/.*"error":{"code":"\([^"]*\)".*/\1/p'
}

# _tr_data — the data of the envelope in OUT, without the envelope's head.
_tr_data() {
  printf '%s\n' "$OUT" | sed -e 's/^{"schema":1,"revision":[0-9]*,"generated_at":"[^"]*","data"://' -e 's/}$//'
}

# _tr_task_of_list — the task object a one-task `jig task list --json` prints.
_tr_task_of_list() {
  jig task list --json | sed -e 's/.*"data":{"tasks":\[//' -e 's/\],"hidden".*//'
}

# A paused task on its branch, a clean tree, no stash.
_tr_paused_task() {
  task_setup_clean
  task_started T-1
  jig task pause T-1 >/dev/null
}

test_task_resume_json_success_has_the_task_and_what_resume_found() {
  _tr_paused_task
  _tr_json T-1
  assert_eq 0 "$RC"
  assert_eq "" "$ERR"
  assert_contains "$OUT" '"data":{"task":{"id":"T-1"'
  assert_contains "$OUT" '"paused":false'
  # No stash, a clean tree on the task's branch, overlap checked and empty.
  assert_contains "$OUT" ',"resume":{"paused_days":0,"stash":null,"uncommitted":0,"overlap":[]}}'
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused: true"
  # The task in the data is the one a listing prints after the resume.
  local in_data
  in_data=$(_tr_data | sed -e 's/^{"task"://' -e 's/,"resume":{.*//')
  assert_eq "$(_tr_task_of_list)" "$in_data" "data.task differs from the task list"
}

test_task_resume_json_raises_the_revision_by_two() {
  _tr_paused_task
  _tr_rev
  local before=$REV
  _tr_json T-1
  assert_eq 0 "$RC"
  _tr_rev
  assert_eq "$((before + 2))" "$REV" "a resume must raise the clone revision by exactly two"
}

test_task_resume_with_current_revision_succeeds() {
  _tr_paused_task
  _tr_rev
  _tr_json T-1 --revision "$REV"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"paused":false'
  # --json and --revision in either order.
  jig task pause T-1 >/dev/null
  _tr_rev
  run_split jig task resume --json T-1 --revision "$REV"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"paused":false'
}

test_task_resume_with_stale_revision_is_refused_and_changes_nothing() {
  _tr_paused_task
  _tr_rev
  local old=$((REV + 7)) state_before now
  state_before=$(cat .ai/workspace/tasks/T-1/state)
  now=$REV
  _tr_json T-1 --revision "$old"
  assert_eq 1 "$RC"
  assert_eq stale-revision "$(_tr_code)"
  assert_contains "$OUT" "the clone changed since revision $old"
  assert_eq "$state_before" "$(cat .ai/workspace/tasks/T-1/state)" "a refused resume changed the state"
  _tr_rev
  assert_eq "$now" "$REV" "a refused resume moved the revision"
  # The new state was built before the claim; the refusal takes it away.
  assert_eq "" "$(_tr_state_tmp)" "a refused --json resume left its new state behind"

  # The text form refuses the same way.
  run jig task resume T-1 --revision "$old"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the clone changed since revision $old"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
  assert_eq "" "$(_tr_state_tmp)" "a refused resume left its new state behind"
}

# _tr_state_tmp — the temporary state files left in T-1's workspace, if any.
_tr_state_tmp() {
  (cd .ai/workspace/tasks/T-1 && ls -a) | grep '^state\.tmp' || true
}

test_task_resume_json_unknown_task_is_not_found() {
  task_setup
  _tr_json NOPE
  assert_eq 1 "$RC"
  assert_eq not-found "$(_tr_code)"
  assert_contains "$OUT" "unknown task: NOPE"
}

test_task_resume_json_not_paused_is_refused() {
  task_setup
  task_started T-1
  _tr_json T-1
  assert_eq 1 "$RC"
  assert_eq not-paused "$(_tr_code)"
  assert_contains "$OUT" "not paused: T-1"
}

test_task_resume_json_bad_arguments_are_usage() {
  _tr_paused_task
  _tr_json T-1 --revision 08
  assert_eq usage "$(_tr_code)" "08: $OUT"
  _tr_json T-1 --revision x
  assert_eq usage "$(_tr_code)" "x: $OUT"
  _tr_json T-1 --revision
  assert_eq usage "$(_tr_code)" "no value: $OUT"
  _tr_json T-1 --revision ""
  assert_eq usage "$(_tr_code)" "empty: $OUT"
  _tr_json T-1 --bogus
  assert_eq usage "$(_tr_code)" "unknown arg: $OUT"
  assert_eq 1 "$RC"
  _tr_json "bad!id"
  assert_eq usage "$(_tr_code)" "bad id: $OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
}

test_task_resume_json_with_stash_on_wrong_branch_is_wrong_checkout() {
  task_setup_clean
  task_started T-1
  printf 'dirty change\n' >> README.md
  jig task pause T-1 --stash >/dev/null
  git checkout -q -b other
  _tr_rev
  local before=$REV
  _tr_json T-1
  assert_eq 1 "$RC"
  assert_eq wrong-checkout "$(_tr_code)"
  assert_contains "$OUT" "switch to task/T-1 first"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
  _tr_rev
  assert_eq "$before" "$REV" "a refused resume moved the revision"
}

test_task_resume_json_stash_conflict_leaves_the_task_paused() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'line one\n' > conflict.txt
  git add conflict.txt
  git commit -q -m "add conflict.txt"
  printf 'task change\n' > conflict.txt
  jig task pause T-1 --stash >/dev/null
  printf 'different change\n' > conflict.txt

  _tr_json T-1
  assert_eq 1 "$RC"
  assert_eq stash-conflict "$(_tr_code)"
  assert_contains "$OUT" "stash apply failed"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
  # Refused after the claim, with the new state already built: it goes too.
  assert_eq "" "$(_tr_state_tmp)" "a stash-conflict resume left its new state behind"

  # The text form, run where the producer is no subshell, cleans up as well.
  git checkout -q -- conflict.txt 2>/dev/null || true
  printf 'different change\n' > conflict.txt
  run jig task resume T-1
  assert_eq 1 "$RC"
  assert_eq "" "$(_tr_state_tmp)" "a stash-conflict text resume left its new state behind"
}

test_task_resume_json_with_stash_reports_its_sha_applied() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'dirty change\n' >> README.md
  jig task pause T-1 --stash >/dev/null
  local sha
  sha=$(sed -n 's/^paused_stash:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  [ -n "$sha" ] || fail "paused_stash was not recorded"

  _tr_json T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "\"stash\":{\"sha\":\"$sha\",\"applied\":true}"
  assert_contains "$(cat README.md)" "dirty change"
}

# A task whose branch is checked out in another worktree, resumed from the main
# checkout: nothing to apply, so it succeeds, and the uncommitted count is the
# worktree's, not this checkout's.
test_task_resume_without_stash_from_main_checkout_reads_the_worktree() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  printf 'a\n' > "$wt/wt-one.txt"
  printf 'b\n' > "$wt/wt-two.txt"
  jig task pause T-1 >/dev/null
  assert_eq "main" "$(git symbolic-ref --short HEAD)"

  _tr_json T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"paused":false'
  assert_contains "$OUT" '"stash":null,"uncommitted":2,'
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused: true"
}

test_task_resume_with_stash_for_a_branch_in_a_worktree_names_the_worktree() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt sha
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  jig task pause T-1 >/dev/null
  # Record a stash by hand: this checkout holds no work of its own to stash.
  printf 'dirty\n' >> README.md
  sha=$(git stash create)
  git checkout -q README.md
  printf 'paused_stash: %s\n' "$sha" >> .ai/workspace/tasks/T-1/state

  _tr_json T-1
  assert_eq 1 "$RC"
  assert_eq wrong-checkout "$(_tr_code)"
  assert_contains "$OUT" "checked out in"
  assert_contains "$OUT" "repo.worktrees/T-1"
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

# _tr_conflicted_resume — T-1 paused with a stash of conflict.txt, the same
# line committed differently while it was paused, and a resume whose apply
# merged the stash with conflicts. The tree holds the conflict markers.
_tr_conflicted_resume() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'line one\n' > conflict.txt
  git add conflict.txt
  git commit -q -m "add conflict.txt"
  printf 'task change\n' > conflict.txt
  jig task pause T-1 --stash >/dev/null
  printf 'base change\n' > conflict.txt
  git commit -q -am "change conflict.txt while paused"
  run jig task resume T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "left conflicts"
  assert_contains "$(cat conflict.txt)" "<<<<<<<"
}

test_task_resume_after_a_conflicted_apply_records_it_and_stays_paused() {
  _tr_conflicted_resume
  local sha
  sha=$(sed -n 's/^paused_stash:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused_stash_applied: $sha"
  assert_eq "" "$(_tr_state_tmp)" "a conflicted resume left its new state behind"
}

test_task_resume_after_a_staged_resolution_ends_the_pause_without_applying_again() {
  _tr_conflicted_resume
  printf 'resolved\n' > conflict.txt
  git add conflict.txt
  run jig task resume T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "conflicts resolved"
  assert_eq "resolved" "$(cat conflict.txt)" "the stash was applied a second time"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused: true"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused_stash_applied:"
  assert_contains "$(git stash list)" "jig: T-1"
}

test_task_resume_after_a_committed_resolution_ends_the_pause_on_a_clean_tree() {
  _tr_conflicted_resume
  printf 'resolved\n' > conflict.txt
  git add conflict.txt
  git commit -q -m "resolve conflict.txt"
  local sha
  sha=$(sed -n 's/^paused_stash:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  _tr_json T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "\"stash\":{\"sha\":\"$sha\",\"applied\":true}"
  assert_eq "" "$(git status --porcelain)" "the stash was applied a second time"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused: true"
}

test_task_resume_with_conflicts_still_unresolved_refuses_and_writes_nothing() {
  _tr_conflicted_resume
  local before
  _tr_rev
  before=$REV
  _tr_json T-1
  assert_eq 1 "$RC"
  assert_eq stash-conflict "$(_tr_code)"
  assert_contains "$OUT" "still have conflicts"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused: true"
  _tr_rev
  assert_eq "$before" "$REV" "a refused resume moved the revision"
}

# An apply that stops part way with no conflicts — a stashed untracked file
# committed while paused — wrote the tracked change already: recorded too, so
# the retry does not apply the stash over it.
test_task_resume_after_an_apply_that_stopped_part_way_records_it() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'tracked change\n' >> README.md
  printf 'untracked\n' > u.txt
  jig task pause T-1 --stash >/dev/null
  printf 'committed meanwhile\n' > u.txt
  git add u.txt
  git commit -q -m "add u.txt while paused"
  local sha
  sha=$(sed -n 's/^paused_stash:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)
  run jig task resume T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "stopped part way"
  assert_not_contains "$OUT" "applied nothing"
  assert_file_contains .ai/workspace/tasks/T-1/state "paused_stash_applied: $sha"

  run jig task resume T-1
  assert_eq 0 "$RC"
  assert_eq 1 "$(grep -c 'tracked change' README.md)" "the stash was applied a second time"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused: true"
}

# Unmerged paths already in the checkout, no record: git would refuse the
# apply anyway, so resume refuses before the claim and records nothing.
test_task_resume_over_unresolved_conflicts_of_the_checkout_refuses_and_writes_nothing() {
  task_setup_clean
  jig task new T-1 >/dev/null
  printf 'line one\n' > c.txt
  git add c.txt
  git commit -q -m "add c.txt"
  git checkout -q -b side
  printf 'side\n' > c.txt
  git commit -q -am "side"
  git checkout -q main
  printf 'main\n' > c.txt
  git commit -q -am "main"
  printf 'task change\n' >> README.md
  jig task pause T-1 --stash >/dev/null
  git merge -q side >/dev/null 2>&1 || true
  [ -n "$(git diff --name-only --diff-filter=U)" ] || fail "no unmerged path to test against"
  local before
  _tr_rev
  before=$REV
  _tr_json T-1
  assert_eq 1 "$RC"
  assert_eq stash-conflict "$(_tr_code)"
  assert_contains "$OUT" "unresolved conflicts"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "paused_stash_applied:"
  _tr_rev
  assert_eq "$before" "$REV" "a refused resume moved the revision"
}

test_task_set_refuses_paused_stash_applied() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 paused_stash_applied abc
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not writable"
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
  task_route_done done-one
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
  task_route_done done-one
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
  task_route_done done-one
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

test_task_list_goals_prints_the_first_goal_paragraph_under_each_task() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  jig task new b-task --from - >/dev/null <<'EOF'
# B

## Goal

The first line of the goal
and its second line.

A second paragraph that is not shown.

## Scope
EOF
  jig task new a-task --from - >/dev/null <<'EOF'
# A

No goal heading here.
EOF

  run jig task list --goals
  assert_eq 0 "$RC"
  assert_eq "a-task class=- status=active not-started
  goal: (none)
b-task class=- status=active not-started
  goal: The first line of the goal and its second line." "$OUT"

  # Without the flag the listing is as it was.
  run jig task list
  assert_not_contains "$OUT" "goal:"
}

test_task_list_reports_no_live_tasks() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  run jig task new done-one
  task_route_done done-one
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
  # Start from the bottom, so every set below raises the class.
  jig task set scoped class T0 --reason "fixture" >/dev/null
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
  jig task set scoped class T0 --reason "fixture" >/dev/null
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
  # `task` is writable by `jig task artifact` (twelve kinds) but is deliberately
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

test_task_artifact_rejects_unknown_kind_and_accepts_the_twelve_writable_kinds() {
  sdd_task_setup
  run jig task artifact write scoped bogus <<< 'x'
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'unknown kind: bogus'

  local kind
  for kind in task discovery spec alternatives design plan review verification handoff knowledge-map commit-message pr-body; do
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

# --- a brief with no goal (the same reading as `task list --goals`) ---------

test_task_start_warns_when_a_t2_task_has_no_goal() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  run jig task start T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warning: task start: T-1 has no goal"
  assert_contains "$OUT" "jig task artifact write T-1 task --from <file>"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
}

test_task_start_is_quiet_about_a_task_with_a_goal() {
  task_setup
  jig task new T-1 --class T2 --goal "The widget renders." >/dev/null
  run jig task start T-1
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "has no goal"
}

test_task_start_refuses_a_t3_task_whose_goal_is_only_the_template_comment() {
  task_setup
  local head_before
  head_before=$(git symbolic-ref --short HEAD)
  jig task new T-1 --class T3 >/dev/null
  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task start: T-1 is T3 and has no goal"
  assert_contains "$OUT" "jig task artifact write T-1 task --from <file>"
  # Nothing was started: no branch, no fork point, the checkout where it was.
  assert_eq "$head_before" "$(git symbolic-ref --short HEAD)"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "base_commit:"

  # Writing the goal is the way past it.
  jig task artifact write T-1 task --from - >/dev/null <<'EOF'
# T-1

## Goal

The tenant can be decommissioned.
EOF
  run jig task start T-1
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "has no goal"
}

test_task_start_worktree_refuses_a_t4_task_with_no_goal() {
  task_setup
  jig task new T-1 --class T4 >/dev/null
  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task start: T-1 is T4 and has no goal"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "base_commit:"
  assert_eq "" "$(git branch --list task/T-1)"
}

test_task_actions_withhold_start_from_a_t3_task_with_no_goal() {
  task_setup_clean
  jig task new big --class T3 >/dev/null
  _tl_agree big "pause request-pause set-class abandon archive"
  _tl_json
  assert_contains "$OUT" "is T3 and has no goal"
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
  git checkout -q main
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
  git clone -q --bare . "${PWD}.origin.git"
  git remote add origin "${PWD}.origin.git"
  git push -q origin main
  jig spec new idea-x >/dev/null
  git checkout -q main
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

# --- start: a dirty tree that is only a spec names `jig spec ship` -----------
# (idea-leaves-a-tree-task-start-refuses): a spec `jig-idea` left mid-session
# is not another task's work, and the door out is already named.

test_task_start_dirty_tree_under_one_spec_names_spec_ship() {
  task_setup_clean
  jig spec new idea-x >/dev/null
  git checkout -q main
  git add -A
  git commit -q -m "add spec idea-x"
  printf 'more work\n' >> .ai/specs/idea-x/spec.md
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "uncommitted changes under .ai/specs/idea-x/; ship it first: \`jig spec ship idea-x\`"
}

test_task_start_dirty_tree_under_one_spec_still_offers_a_worktree() {
  task_setup_clean
  jig spec new idea-x >/dev/null
  git checkout -q main
  git add -A
  git commit -q -m "add spec idea-x"
  printf 'more work\n' >> .ai/specs/idea-x/roadmap.md
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "or start it in its own worktree: \`jig task start T-1 --worktree\`"
}

test_task_start_dirty_tree_mixed_with_a_spec_does_not_name_spec_ship() {
  task_setup_clean
  jig spec new idea-x >/dev/null
  git checkout -q main
  git add -A
  git commit -q -m "add spec idea-x"
  printf 'more work\n' >> .ai/specs/idea-x/spec.md
  printf 'dirty\n' >> README.md
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_not_contains "$OUT" "spec ship"
  assert_contains "$OUT" "uncommitted changes in the working tree; commit them"
}

test_task_start_dirty_tree_across_two_specs_does_not_name_either() {
  task_setup_clean
  jig spec new idea-x >/dev/null
  git checkout -q main
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec new idea-y >/dev/null
  git checkout -q main
  git add -A
  git commit -q -m "add spec idea-y"
  printf 'more\n' >> .ai/specs/idea-x/spec.md
  printf 'more\n' >> .ai/specs/idea-y/spec.md
  jig task new T-1 >/dev/null

  run jig task start T-1
  assert_eq 1 "$RC"
  assert_not_contains "$OUT" "spec ship"
  assert_contains "$OUT" "uncommitted changes in the working tree; commit them"
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
  assert_contains "$OUT" "jig task start T-1 --worktree"
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

# --- start --worktree on a started task: moving it out of this checkout ---------

test_task_start_worktree_moves_a_started_task_out_of_this_checkout() {
  task_setup_nested
  task_started T-1
  printf 'work\n' > work.txt
  git add work.txt
  git commit -q -m "work on T-1"
  before=$(git rev-parse HEAD)
  state_before=$(cat .ai/workspace/tasks/T-1/state)

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_eq "$(cd .. && pwd -P)/repo.worktrees/T-1" "$OUT"
  assert_contains "$ERR" "moved to its own worktree; this checkout is on main now"
  assert_eq "task/T-1" "$(git -C "$OUT" symbolic-ref --short HEAD)"
  # The commits ride with the branch; the task's record is untouched.
  assert_eq "$before" "$(git -C "$OUT" rev-parse HEAD)"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  assert_eq "$state_before" "$(cat .ai/workspace/tasks/T-1/state)"
  # The workspace is reachable from the worktree through the link.
  [ -f "$OUT/.ai/workspace/tasks/T-1/state" ] || fail "workspace not linked"
}

test_task_start_worktree_on_a_started_task_refuses_a_dirty_tree() {
  task_setup_nested
  task_started T-1
  printf 'dirty\n' >> README.md

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "uncommitted changes"
  assert_contains "$OUT" "jig task pause T-1 --stash"
  # Nothing was changed.
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  [ ! -e ../repo.worktrees/T-1 ] || fail "a worktree was left behind"
}

test_task_start_worktree_on_a_started_task_refuses_when_the_base_is_taken() {
  task_setup_nested
  task_started T-1
  git worktree add -q ../elsewhere main

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "cannot leave task/T-1 here"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  [ ! -e ../repo.worktrees/T-1 ] || fail "a worktree was left behind"
}

test_task_start_worktree_on_a_started_task_needs_no_switch_when_it_is_not_checked_out() {
  task_setup_nested
  task_started T-1
  git switch -q main

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_not_contains "$ERR" "this checkout is on"
  assert_eq "task/T-1" "$(git -C "$OUT" symbolic-ref --short HEAD)"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_task_start_worktree_on_a_task_already_in_a_worktree_says_where() {
  task_setup_nested
  jig task new T-1 >/dev/null
  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  wt="$OUT"

  run jig task start T-1 --worktree
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already on task/T-1 in its own worktree: $wt"
}

test_task_start_worktree_on_a_started_task_puts_head_back_when_the_worktree_cannot_be_made() {
  skip_unless_readonly_dirs
  task_setup_nested
  task_started T-1
  # An unwritable worktree root makes the add fail after HEAD has moved off.
  mkdir -p ../repo.worktrees
  chmod 555 ../repo.worktrees
  run jig task start T-1 --worktree
  rc=$RC
  chmod 755 ../repo.worktrees
  assert_eq 1 "$rc"
  assert_eq "task/T-1" "$(git symbolic-ref --short HEAD)"
  git rev-parse --verify --quiet refs/heads/task/T-1 >/dev/null || fail "the branch was lost"
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
  # Git is done with the tree: out of its records, tracked files gone. Whether
  # the *directory* survives is a platform fact this test does not own -- on
  # Windows a removal that returns 0 leaves the directory behind, junction
  # included (measured 2026-09-14, tests/housekeeping.t.sh), and clearing that
  # is `_hk_worktree_leftover`'s job. Measured again here on 2026-09-25, on the
  # borrowed-directory form: the leftover's `.ai/workspace/tasks` was still a
  # link (`-L` yes) pointing at this checkout, so the removal went nowhere
  # through it -- which is why the two assertions below are the whole claim and
  # `[ ! -d "$wt" ]` was never part of it.
  assert_eq 1 "$(git worktree list --porcelain | grep -c '^worktree ')" \
    "git still lists a worktree after the only one was removed"
  # The promise: the statement filed inside the tree is still here, and the tree
  # took none of this checkout's own workspaces with it.
  assert_contains "$(jig task show T-2)" "task_id: T-2"
  assert_file .ai/workspace/tasks/T-1/state
  assert_file .ai/workspace/tasks/T-2/state
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
  git clone -q --bare . "${PWD}.origin.git"
  git remote add origin "${PWD}.origin.git"
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

# --- artifacts --json, artifact read (schemas/json.md) ------------------------

# _ta_json <args...> — `jig task <args>` with stdout in OUT, stderr in ERR,
# generated_at and revision replaced as _tn_json replaces them.
_ta_json() {
  run_split jig task "$@"
  local rc=$RC err=$ERR
  OUT=$(printf '%s\n' "$OUT" | sed -e 's/"generated_at":"[0-9TZ:-]*"/"generated_at":"T"/' -e 's/^{"schema":1,"revision":[0-9][0-9]*,/{"schema":1,"revision":"R",/')
  RC=$rc
  ERR=$err
}

test_task_artifacts_json_lists_every_kind_with_its_state() {
  task_setup_clean
  jig task new scoped >/dev/null
  local root=.ai/workspace/tasks/scoped state
  printf 'the plan\n' > "$root/plan.md"
  : > "$root/review.md"
  mkdir "$root/design.md"
  # Fixed times, written in UTC, so the whole shape can be compared.
  TZ=UTC touch -t 202001020304.05 "$root/task.md" "$root/plan.md" "$root/review.md"
  local tbytes
  tbytes=$(wc -c < "$root/task.md" | tr -d ' ')
  state=$(cat "$root/state")
  # The class is not asked: an unclassified task lists as well.
  _ta_json artifacts scoped --json
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  local m='"reason":null,"updated_at":null,"bytes":null}'
  assert_eq "{\"schema\":1,\"revision\":\"R\",\"generated_at\":\"T\",\"data\":{\"task\":\"scoped\",\"artifacts\":[{\"kind\":\"task\",\"state\":\"present\",\"reason\":null,\"updated_at\":\"2020-01-02T03:04:05Z\",\"bytes\":$tbytes},{\"kind\":\"discovery\",\"state\":\"missing\",$m,{\"kind\":\"spec\",\"state\":\"missing\",$m,{\"kind\":\"alternatives\",\"state\":\"missing\",$m,{\"kind\":\"design\",\"state\":\"unavailable\",\"reason\":\"missing or not a regular file\",\"updated_at\":null,\"bytes\":null},{\"kind\":\"plan\",\"state\":\"present\",\"reason\":null,\"updated_at\":\"2020-01-02T03:04:05Z\",\"bytes\":9},{\"kind\":\"review\",\"state\":\"empty\",\"reason\":null,\"updated_at\":\"2020-01-02T03:04:05Z\",\"bytes\":0},{\"kind\":\"verification\",\"state\":\"missing\",$m,{\"kind\":\"handoff\",\"state\":\"missing\",$m,{\"kind\":\"knowledge-map\",\"state\":\"missing\",$m,{\"kind\":\"commit-message\",\"state\":\"missing\",$m,{\"kind\":\"pr-body\",\"state\":\"missing\",$m]}}" "$OUT"
  # A read: nothing written, the revision where it was.
  assert_eq "$state" "$(cat "$root/state")"
  local r1 r2
  r1=$(jig task artifacts scoped --json | sed -n 's/^{"schema":1,"revision":\([0-9]*\),.*/\1/p')
  r2=$(jig task artifacts --json scoped | sed -n 's/^{"schema":1,"revision":\([0-9]*\),.*/\1/p')
  assert_eq "$r1" "$r2"
  # The text form keeps its bytes.
  jig task set scoped class T2 >/dev/null
  run jig task artifacts scoped
  assert_contains "$OUT" 'design         unavailable (missing or not a regular file)'
  assert_contains "$OUT" 'review         unavailable (empty)'
  assert_contains "$OUT" 'plan           present'
}

test_task_artifacts_json_marks_a_link_out_of_the_workspace_unavailable() {
  skip_unless_symlinks
  task_setup_clean
  jig task new scoped >/dev/null
  echo external > external.md
  ln -s "$PWD/external.md" .ai/workspace/tasks/scoped/design.md
  _ta_json artifacts scoped --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '{"kind":"design","state":"unavailable","reason":"outside workspace","updated_at":null,"bytes":null}'
  _ta_json artifact read scoped design --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"failed","message":"task artifact: design of scoped is unavailable (outside workspace)"}}'
  run jig task artifact read scoped design
  assert_eq 1 "$RC"
  assert_not_contains "$OUT" external
}

test_task_artifacts_json_names_why_it_refused() {
  task_setup_clean
  jig task new scoped >/dev/null
  _ta_json artifacts nope --json
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","error":{"code":"not-found","message":"task artifacts: unknown task: nope"}}' "$OUT"
  assert_eq 'jig: error: task artifacts: unknown task: nope' "$ERR"
  _ta_json artifacts scoped --provided design --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"task artifacts: --provided cannot be combined with --json"}}'
  _ta_json artifacts scoped --bogus --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"task artifacts: unknown argument: --bogus"}}'
  _ta_json artifacts --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"usage: jig task artifacts <id>'
  _ta_json artifacts "bad id!" --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"task artifacts: invalid task id: bad id!"}}'
}

test_task_artifact_read_prints_the_document_as_it_is() {
  task_setup_clean
  jig task new scoped >/dev/null
  local root=.ai/workspace/tasks/scoped
  printf '# Plan\n\nSay "hi"\tthen\\go.\n\n' > "$root/plan.md"
  TZ=UTC touch -t 202001020304.05 "$root/plan.md"
  run jig task artifact read scoped plan
  assert_eq 0 "$RC"
  assert_eq "$(cat "$root/plan.md")" "$OUT"
  # Byte for byte, trailing newlines included.
  jig task artifact read scoped plan > out.md
  cmp -s "$root/plan.md" out.md || fail "read changed the bytes"

  _ta_json artifact read scoped plan --json
  assert_eq 0 "$RC" "$ERR"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","data":{"task":"scoped","kind":"plan","updated_at":"2020-01-02T03:04:05Z","bytes":'"$(wc -c < "$root/plan.md" | tr -d ' ')"',"content":"# Plan\n\nSay \"hi\"\tthen\\go.\n\n"}}' "$OUT"
  # --json may stand anywhere.
  _ta_json artifact --json read scoped plan
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"kind":"plan",'
  # A control byte is escaped, and quoting stays linear in the document's
  # size (a per-character pass took about a minute for 50 KB).
  { printf 'esc \033[1m bold\001\n'; head -c 60000 /dev/zero | tr '\0' 'a'; printf '\n'; } > "$root/handoff.md"
  _ta_json artifact read scoped handoff --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"content":"esc \u001b[1m bold\u0001\naaaa'
  # An empty document reads as empty.
  : > "$root/review.md"
  _ta_json artifact read scoped review --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"bytes":0,"content":""}}'
}

test_task_artifact_read_names_why_it_refused() {
  task_setup_clean
  jig task new scoped >/dev/null
  _ta_json artifact read scoped design --json
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","error":{"code":"not-found","message":"task artifact: scoped has no design"}}' "$OUT"
  _ta_json artifact read nope plan --json
  assert_contains "$OUT" '"error":{"code":"not-found","message":"task artifact: unknown task: nope"}}'
  _ta_json artifact read scoped bogus --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"task artifact: unknown kind: bogus (one of: task discovery spec alternatives design plan review verification handoff knowledge-map commit-message pr-body)"}}'
  _ta_json artifact read scoped --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"usage: jig task artifact write'
  _ta_json artifact read scoped plan extra --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"usage: jig task artifact write'
  _ta_json artifact write scoped plan --json < /dev/null
  assert_contains "$OUT" '"error":{"code":"usage","message":"task artifact: --json goes with read only"}}'
  assert_no_file .ai/workspace/tasks/scoped/plan.md
  _ta_json artifact read "bad id!" plan --json
  assert_contains "$OUT" '"error":{"code":"usage","message":"task artifact: invalid task id: bad id!"}}'
  run jig task artifact read scoped design
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'task artifact: scoped has no design'
  run jig task artifact read scoped
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'usage: jig task artifact write'
}

# A worktree task's workspace is the owner's (ADR-0029): read from the
# worktree through its link, and from the main checkout directly, both find it.
test_task_artifacts_json_and_read_find_a_worktree_tasks_workspace() {
  task_setup_nested
  jig task new T-1 --class T2 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  printf 'plan in the workspace\n' > .ai/workspace/tasks/T-1/plan.md

  _ta_json artifacts T-1 --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '{"kind":"plan","state":"present",'
  _ta_json artifact read T-1 plan --json
  assert_contains "$OUT" '"content":"plan in the workspace\n"}}'

  set +e
  OUT=$(cd "$wt" && jig task artifacts T-1 --json 2>&1)
  RC=$?
  set -e
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '{"kind":"plan","state":"present",'
  set +e
  OUT=$(cd "$wt" && jig task artifact read T-1 plan --json 2>&1)
  RC=$?
  set -e
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"content":"plan in the workspace\n"}}'
}

test_jig_utc_from_epoch_and_file_mtime() {
  task_setup
  # Expanded by the inner bash, not here.
  # shellcheck disable=SC2016
  local lib='. "$JIG_HOME/scripts/lib/common.sh"; '
  run bash -c "$lib"'jig_utc_from_epoch 0; jig_utc_from_epoch 1577934245'
  assert_eq 0 "$RC"
  assert_eq "$(printf '1970-01-01T00:00:00Z\n2020-01-02T03:04:05Z')" "$OUT"
  run bash -c "$lib"'jig_utc_from_epoch ""'
  assert_eq 1 "$RC"
  run bash -c "$lib"'jig_utc_from_epoch 12a'
  assert_eq 1 "$RC"
  # GNU's `-r` reads a file: a file named after the seconds must not win.
  TZ=UTC touch -t 200001010000.00 1577934245
  run bash -c "$lib"'jig_utc_from_epoch 1577934245'
  assert_eq '2020-01-02T03:04:05Z' "$OUT"
  printf x > f
  TZ=UTC touch -t 202001020304.05 f
  run bash -c "$lib"'jig_file_mtime f'
  assert_eq 0 "$RC"
  assert_eq 1577934245 "$OUT"
  run bash -c "$lib"'jig_file_mtime no-such-file'
  assert_eq 1 "$RC"
}

# The same refusal one level up. `task start --worktree` links the whole
# `.ai/workspace/tasks` now, so a link at the parent is the usual shape, and
# `-L` on the task's own path cannot see it: the check must judge the tasks
# directory by where it leads. Here it leads to a directory no checkout of
# this repository holds, outside the repository, and every verb that reads or
# writes through `_task_workspace_root` refuses before touching it. Planted
# with plant_dir_link, so Windows is checked with a junction rather than
# skipped.
test_task_artifact_refuses_a_borrowed_directory_that_leads_outside() {
  task_setup_nested
  jig task new T-1 >/dev/null
  mkdir ../outside
  cp -R .ai/workspace/tasks/T-1 ../outside/T-1
  rm -rf .ai/workspace/tasks
  plant_dir_link "$(cd ../outside && pwd -P)" "$PWD/.ai/workspace/tasks"

  run jig task artifact write T-1 plan <<< 'planted'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task artifact: .ai/workspace/tasks leads to"
  assert_contains "$OUT" "which is no checkout of this repository"
  assert_no_file ../outside/T-1/plan.md

  run jig task artifact append T-1 plan <<< 'planted'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "which is no checkout of this repository"
  assert_no_file ../outside/T-1/plan.md

  run jig task artifacts T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task artifacts: .ai/workspace/tasks leads to"
}

# Two levels up: a link at `.ai/workspace` resolves the task directory and the
# tasks directory through the same link just as well, so it is judged the same
# way.
test_task_artifact_refuses_a_workspace_link_that_leads_outside() {
  task_setup_nested
  jig task new T-1 >/dev/null
  mkdir -p ../outside/tasks
  cp -R .ai/workspace/tasks/T-1 ../outside/tasks/T-1
  rm -rf .ai/workspace
  plant_dir_link "$(cd ../outside && pwd -P)" "$PWD/.ai/workspace"

  run jig task artifact write T-1 plan <<< 'planted'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "which is no checkout of this repository"
  assert_no_file ../outside/tasks/T-1/plan.md
}

# A borrowed directory vouches for itself, not for what sits in it: a task
# entry there that is a link of its own is judged like any other link, from
# the worktree as from the owner.
test_task_artifact_refuses_a_task_link_inside_a_borrowed_directory() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  [ -L "$wt/.ai/workspace/tasks" ] || fail "the worktree did not borrow the task directory"
  mkdir ../outside
  mv .ai/workspace/tasks/T-1 ../outside/T-1
  plant_dir_link "$(cd ../outside/T-1 && pwd -P)" "$PWD/.ai/workspace/tasks/T-1"

  set +e
  OUT=$(cd "$wt" && jig task artifact write T-1 plan <<< 'planted' 2>&1)
  RC=$?
  set -e
  assert_eq 1 "$RC"
  assert_contains "$OUT" "linked task workspace is unsupported"
  assert_no_file ../outside/T-1/plan.md
}

# The other half of the rule: a link at `.ai/workspace` that leads into
# another checkout of this repository is how a coordinator shares the main
# checkout's workspace from a second worktree, and it keeps working.
test_task_artifact_writes_through_a_workspace_link_into_another_worktree() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local owner coord result rc
  owner=$(pwd -P)
  git worktree add -q ../coord >/dev/null 2>&1 || fail "could not add a worktree"
  coord=$(cd ../coord && pwd -P)
  rm -rf "$coord/.ai/workspace"
  plant_dir_link "$owner/.ai/workspace" "$coord/.ai/workspace"

  set +e
  result=$(cd "$coord" && jig task artifact write T-1 plan <<< 'from the coordinator' 2>&1)
  rc=$?
  set -e
  assert_eq 0 "$rc" "$result"
  assert_file_contains "$owner/.ai/workspace/tasks/T-1/plan.md" 'from the coordinator'
}

# --- every writer of a workspace refuses a planted link --------------------------
#
# #183 closed the artifact commands; the commands that write `state`, the
# journal, the findings and the receipt went through task_dir and did not look.
# Every writer now passes the one check (_task_guard_write / _task_guard_dir),
# and each is exercised here against a `.ai/workspace/tasks` that leads outside
# the repository: it must refuse and leave what is outside exactly as it was.

# task_outside_sum — one number standing for everything under ../outside.
task_outside_sum() {
  (cd ../outside && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s\n' "$f"; cat "$f"; done | cksum)
}

# task_plant_tasks_link — move the tasks directory outside the repository and
# put a link to it where it was (a symlink, or a junction on Windows).
task_plant_tasks_link() {
  mkdir ../outside
  cp -R .ai/workspace/tasks/. ../outside/
  rm -rf .ai/workspace/tasks
  plant_dir_link "$(cd ../outside && pwd -P)" "$PWD/.ai/workspace/tasks"
}

# task_refused_on_planted_link <label> <command...> — the command exits 1 with
# the refusal and nothing outside changed.
task_refused_on_planted_link() {
  local label="$1" before after
  shift
  before=$(task_outside_sum)
  run "$@"
  assert_eq 1 "$RC" "$label: $OUT"
  assert_contains "$OUT" "which is no checkout of this repository" "$label"
  after=$(task_outside_sum)
  assert_eq "$before" "$after" "$label changed a file outside the repository"
}

test_task_writers_refuse_a_planted_tasks_link() {
  task_setup_nested
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null
  printf 'msg\n' > msg.txt
  task_plant_tasks_link
  printf 'dirty\n' > dirty.txt

  task_refused_on_planted_link set jig task set T-1 class T2
  task_refused_on_planted_link abandon jig task abandon T-1
  task_refused_on_planted_link pause jig task pause T-1 --reason why
  task_refused_on_planted_link pause-stash jig task pause T-1 --stash
  assert_eq "" "$(git stash list)" "pause --stash stashed before the refusal"
  assert_file dirty.txt
  task_refused_on_planted_link resume jig task resume T-1
  task_refused_on_planted_link gate jig task gate T-1 approved --by agent
  task_refused_on_planted_link receipt jig task receipt T-1 --stage review
  task_refused_on_planted_link finding-add jig task finding add T-1 --severity P2 --where - --summary s
  task_refused_on_planted_link finding-set jig task finding set T-1 F1 fixed
  task_refused_on_planted_link autopilot-start jig task autopilot T-1 start
  task_refused_on_planted_link autopilot-stage jig task autopilot T-1 stage implement
  task_refused_on_planted_link autopilot-repair jig task autopilot T-1 repair --reason r
  task_refused_on_planted_link autopilot-stop jig task autopilot T-1 stop --reason r
  task_refused_on_planted_link autopilot-decide jig task autopilot T-1 decide --reason r
  task_refused_on_planted_link autopilot-resume jig task autopilot T-1 resume --answer a
  task_refused_on_planted_link autopilot-end jig task autopilot T-1 end
  task_refused_on_planted_link start jig task start T-2
  task_refused_on_planted_link start-worktree jig task start T-2 --worktree
  task_refused_on_planted_link bootstrap jig task bootstrap T-1
  task_refused_on_planted_link ship jig task ship T-1 --message-file msg.txt
  task_refused_on_planted_link artifact-write jig task artifact write T-1 plan --from msg.txt
  task_refused_on_planted_link artifact-append jig task artifact append T-1 plan --from msg.txt
  task_refused_on_planted_link new jig task new T-3
  assert_no_file ../outside/T-3/state
  assert_eq "./T-1
./T-2" "$(cd ../outside && find . -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)" "a task directory appeared outside"
}

# The same, one level up, where a link at `.ai/workspace` carries the tasks
# directory with it.
test_task_writers_refuse_a_planted_workspace_link() {
  task_setup_nested
  jig task new T-1 >/dev/null
  mkdir -p ../outside
  cp -R .ai/workspace/. ../outside/
  rm -rf .ai/workspace
  plant_dir_link "$(cd ../outside && pwd -P)" "$PWD/.ai/workspace"

  task_refused_on_planted_link set jig task set T-1 class T2
  task_refused_on_planted_link new jig task new T-3
  task_refused_on_planted_link pause jig task pause T-1
  assert_no_file ../outside/tasks/T-3/state
}

# `task new` makes the tasks directory when there is none; made through a link
# at `.ai/workspace` it would be made outside the repository.
test_task_new_refuses_a_workspace_link_to_a_directory_without_tasks() {
  task_setup_nested
  rm -rf .ai/workspace
  mkdir ../outside
  plant_dir_link "$(cd ../outside && pwd -P)" "$PWD/.ai/workspace"

  run jig task new T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task new: .ai/workspace leads to"
  assert_contains "$OUT" "which is no checkout of this repository"
  [ ! -e ../outside/tasks ] || fail "a tasks directory appeared outside"
}

# A link planted as one task's own directory is refused by the writers as well.
test_task_writers_refuse_a_planted_task_link() {
  task_setup_nested
  jig task new T-1 >/dev/null
  mkdir ../outside
  mv .ai/workspace/tasks/T-1 ../outside/T-1
  plant_dir_link "$(cd ../outside/T-1 && pwd -P)" "$PWD/.ai/workspace/tasks/T-1"

  run jig task set T-1 class T2
  assert_eq 1 "$RC"
  assert_contains "$OUT" "linked task workspace is unsupported"
  assert_not_contains "$(cat ../outside/T-1/state)" "class: T2"
}

# The legitimate shapes still write: a worktree that borrowed the tasks
# directory, and a coordinator whose `.ai/workspace` leads into the owner's.
test_task_writers_work_through_the_links_jig_makes() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local owner coord wt
  owner=$(pwd -P)
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  [ -L "$wt/.ai/workspace/tasks" ] || fail "the worktree did not borrow the task directory"

  set +e
  OUT=$(cd "$wt" && jig task set T-1 class T2 2>&1)
  RC=$?
  set -e
  assert_eq 0 "$RC" "$OUT"
  assert_eq "T2" "$(sed -n 's/^class: //p' "$owner/.ai/workspace/tasks/T-1/state")"
  set +e
  OUT=$(cd "$wt" && jig task autopilot T-1 start 2>&1)
  RC=$?
  set -e
  assert_eq 0 "$RC" "$OUT"
  assert_file "$owner/.ai/workspace/tasks/T-1/autopilot"

  git worktree add -q ../coord >/dev/null 2>&1 || fail "could not add a worktree"
  coord=$(cd ../coord && pwd -P)
  rm -rf "$coord/.ai/workspace"
  plant_dir_link "$owner/.ai/workspace" "$coord/.ai/workspace"
  set +e
  OUT=$(cd "$coord" && jig task finding add T-1 --severity P2 --where - --summary s 2>&1)
  RC=$?
  set -e
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains "$owner/.ai/workspace/tasks/T-1/findings" "F1"
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

# ship_exclude_fixture — the test's own scaffolding (the bare origin, the gh
# stub and what it logs) is not a new file of the task's: kept out of what
# `task ship` reads as new files through .git/info/exclude, never .gitignore,
# which is tracked. msg.txt stays visible on purpose: ship must leave the
# message file out by itself.
ship_exclude_fixture() {
  printf '%s\n' origin.git stub-bin 'gh-*' 'glab-*' '*.log' '*.argv' '*.tmp' >> .git/info/exclude
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
  ship_exclude_fixture
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
  ship_exclude_fixture
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
  task_route_done T-1
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
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  git checkout -q main

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "current branch is main, but T-1 is on task/T-1"
}

test_task_ship_on_base_branch_refuses() {
  task_setup_clean
  git clone -q --bare . "${PWD}.origin.git"
  git remote add origin "${PWD}.origin.git"
  git fetch -q origin
  _task_share_one_branch
  git add -A
  git commit -q -m "branch_per_task off"
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
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

# An empty index is the agent that forgot `git add`, not a choice to ship
# nothing (adr-20261029-task-ship-stages-tracked-changes-and-refuses-new-files):
# ship stages the tracked changes itself, so the change goes out with the
# ship rather than being left in the working tree. The commit message file
# sits untracked in the tree, as an agent's often does, and is never staged.
test_task_ship_stages_tracked_changes_when_nothing_is_staged() {
  ship_setup_forge
  ship_cfg_local agent.git push
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  git commit -q -m "committed by an earlier run"
  printf 'the line the agent forgot to stage\n' >> ship.txt

  run jig task ship T-1 --message-file msg.txt

  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "nothing was staged; staged the tracked changes:"
  assert_contains "$OUT" "ship.txt"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "pushed task/T-1"
  assert_eq "" "$(git status --porcelain -- ship.txt)" "the change must be committed"
  assert_contains "$(git show HEAD:ship.txt)" "the line the agent forgot to stage"
  assert_contains "$(git status --porcelain -- msg.txt)" "?? msg.txt"
}

# A new file is where staging on the agent's behalf would cost the most: a
# secret or a scratch file pushed to the forge is not taken back. So it is a
# refusal, with nothing staged, committed or sent — never the earlier commit
# pushed while the new file stays behind.
test_task_ship_refuses_untracked_files_when_nothing_is_staged() {
  ship_setup_forge
  ship_cfg_local agent.git merge
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  git commit -q -m "committed by an earlier run"
  printf 'tracked edit\n' >> ship.txt
  printf 'new\n' > new.txt
  local head_before
  head_before=$(git rev-parse HEAD)

  run jig task ship T-1 --message-file msg.txt

  assert_eq 1 "$RC"
  assert_contains "$OUT" "nothing is staged, and these files are not tracked by git:"
  assert_contains "$OUT" "new.txt"
  assert_not_contains "$OUT" "msg.txt"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
  assert_eq "" "$(git diff --cached --name-only)" "nothing may be left staged"
  assert_eq "" "$(git ls-remote origin task/T-1)" "the branch must not be pushed"
  assert_no_file gh-calls.log "the forge must not be asked anything"
}

# A staged index is the agent's choice and is committed as it is; what it
# leaves out is named, so a forgotten file is visible rather than silent.
test_task_ship_names_what_a_staged_index_leaves_out() {
  ship_setup
  ship_cfg_local agent.git commit
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  printf 'edit\n' >> .ai/config.yaml
  printf 'left out\n' > other.txt
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt

  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "not part of this commit"
  assert_contains "$OUT" ".ai/config.yaml"
  assert_contains "$OUT" "other.txt"
  assert_not_contains "$OUT" "msg.txt"
  assert_contains "$(git status --porcelain -- .ai/config.yaml)" " M .ai/config.yaml"
}

# The order, not the wording (common.sh, "what a ship may send out"). Proved
# without a network: `origin` is a real bare repository here, so a push that
# happened is visible in its refs, and `gh` is a stub that appends every call
# to gh-calls.log, so a forge that was asked anything is visible too. The
# level is `merge`, the one with every outward step in it.
test_task_ship_empty_branch_refuses_before_anything_leaves_the_machine() {
  ship_setup_forge
  ship_cfg_local agent.git merge
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "pushed task/T-1"
  assert_contains "$OUT" "stopped at push: the pull request is the human's"
  assert_contains "$(git ls-remote origin task/T-1)" "refs/heads/task/T-1"
}

# fetch-never-waits-for-a-prompt: `jig_ship_push` is one of the network git
# calls that task enumerated, alongside housekeeping's and self-update's
# fetches. Asserted on the actual invocation (stub_git_env_log_dir), the same
# way those are: a local bare origin never prompts for anything either way.
test_task_ship_push_never_waits_for_a_prompt() {
  ship_setup
  ship_cfg_local agent.git push
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  local log="$PWD/git-calls.log"
  PATH="$(stub_git_env_log_dir "$log"):$PATH" run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pushed task/T-1"

  assert_file "$log"
  local push_line
  push_line=$(grep 'ARGS=.*push -u origin task/T-1' "$log") \
    || fail "no logged git push -u origin call: $(cat "$log")"
  assert_contains "$push_line" "TERMINAL_PROMPT=0"
  case "$push_line" in
    *"BatchMode=yes"*) ;;
    *) fail "GIT_SSH_COMMAND must carry -o BatchMode=yes: $push_line" ;;
  esac
}

test_task_ship_pr_level_creates_pr_into_base_branch() {
  ship_setup
  ship_cfg forge github
  ship_stub_gh ""
  ship_cfg_local agent.git pr
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
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
  task_route_done T-1
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
#   gh-head      the head `pr view` reports (default: HEAD where gh runs, so a
#                ship from a worktree reads that worktree's)
#   gh-repo      merge-commit, squash and rebase allowed (default: true true true)
#   gh-merge.rc  the exit code of `pr merge` (default: 0)
#   gh-existing  the pull request `pr list` finds open (default: none)
# `pr create` and `pr merge` record their arguments in gh-create.argv and
# gh-merge.argv; `pr create` also copies the body it was given to
# gh-create.body.
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
  "pr list") val gh-existing null ;;
  "pr create")
    shift 2
    printf '%s\n' "\$@" > "\$d/gh-create.argv"
    while [ \$# -gt 0 ]; do
      if [ "\$1" = --body-file ]; then cat "\$2" > "\$d/gh-create.body"; fi
      shift
    done
    printf 'https://github.com/example/example/pull/99\n' ;;
  "pr view") printf '%s %s\n' "\$(val gh-draft false)" "\$(val gh-head "\$(git rev-parse HEAD)")" ;;
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
  task_route_done T-1
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
  # The shipped commit by its message: after the merge this checkout is back
  # on main and the task's branch is gone.
  assert_contains "$argv" "$(printf -- '--match-head-commit\n%s' "$(git log -g -1 --format=%H --grep='^Ship T-1' HEAD)")"
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

# --- a merged branch leaves with its work (adr-20261007-a-merged-branch-leaves-with-its-work)

# assert_branch_gone <branch> — no such branch here, on origin.git, or as an
# origin/ ref.
assert_branch_gone() {
  if git show-ref --verify --quiet "refs/heads/$1"; then fail "branch $1 is still here"; fi
  if git show-ref --verify --quiet "refs/remotes/origin/$1"; then fail "origin/$1 is still here"; fi
  if git --git-dir=origin.git show-ref --verify --quiet "refs/heads/$1"; then fail "branch $1 is still on origin"; fi
}

test_task_ship_merge_puts_the_checkout_back_on_main_and_deletes_the_branch() {
  mship_setup github

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
  assert_contains "$OUT" "task ship: back on main"
  assert_contains "$OUT" "task ship: deleted branch task/T-1"
  assert_contains "$OUT" "task ship: deleted branch task/T-1 on origin"
  assert_eq main "$(git symbolic-ref --short HEAD)"
  assert_branch_gone task/T-1
}

# A squash leaves the branch's commits off main; `git branch -d` still takes
# it, against its upstream, because the local branch goes before origin's.
test_task_ship_squash_merge_still_deletes_the_branch() {
  mship_setup github
  printf 'false true true\n' > gh-repo

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$(cat gh-merge.argv)" "--squash"
  assert_contains "$OUT" "task ship: deleted branch task/T-1 on origin"
  assert_eq main "$(git symbolic-ref --short HEAD)"
  assert_branch_gone task/T-1
}

test_task_ship_gitlab_merge_deletes_the_branch() {
  mship_setup gitlab

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: deleted branch task/T-1 on origin"
  assert_branch_gone task/T-1
}

test_task_ship_merge_keeps_the_branch_when_the_key_is_off() {
  mship_setup github
  ship_cfg_local git.delete_merged_branches false

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "merged "
  assert_not_contains "$OUT" "deleted branch"
  assert_eq task/T-1 "$(git symbolic-ref --short HEAD)"
  git show-ref --verify --quiet refs/heads/task/T-1 || fail "the local branch was deleted"
  git --git-dir=origin.git show-ref --verify --quiet refs/heads/task/T-1 || fail "origin's branch was deleted"
}

test_task_ship_without_a_merge_keeps_the_branch() {
  mship_setup github
  printf 'fail\n' > gh-checks

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: a check failed"
  assert_not_contains "$OUT" "deleted branch"
  assert_eq task/T-1 "$(git symbolic-ref --short HEAD)"
  git --git-dir=origin.git show-ref --verify --quiet refs/heads/task/T-1 || fail "origin's branch was deleted"
}

# Shipped from the task's own worktree: the base is checked out in the main
# checkout, and a worktree is never moved, so both copies of the branch stay
# for housekeeping.
test_task_ship_merge_from_a_worktree_keeps_the_branch() {
  mship_setup github
  git reset -q
  rm -f ship.txt
  # The forge setting mship_setup wrote is tracked; committed on the task's
  # branch, it moves to the worktree with it.
  git commit -q -am "fixture: github is the forge"
  run jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt here="$PWD"
  wt=$(printf '%s\n' "$OUT" | tail -n 1)
  [ -d "$wt" ] || fail "no worktree at: $wt"
  cd "$wt" || fail "cannot enter $wt"
  printf 'ship change\n' > ship.txt
  git add ship.txt
  run jig task ship T-1 --message-file "$here/msg.txt"
  cd "$here" || fail "cannot go back"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "merged "
  assert_contains "$OUT" "task ship: kept branch task/T-1: it is checked out in this worktree"
  git show-ref --verify --quiet refs/heads/task/T-1 || fail "the local branch was deleted"
  git --git-dir=origin.git show-ref --verify --quiet refs/heads/task/T-1 || fail "origin's branch was deleted"
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

# --- open findings handed to a triage task
# (adr-20261029-a-ship-hands-open-findings-to-one-triage-task) -----------------

# triage_findings — on T-1, two findings left for later (a P2 and a P3, open)
# and two that are not (a P2 and a P1, closed). Recorded before the route's
# records, as a review records them before its receipt.
triage_findings() {
  local f
  jig task finding add T-1 --severity P2 --where src/scrub.sh:12 --summary "the message scrub path has no test" >/dev/null
  f=$(jig task finding add T-1 --severity P2 --where src/a.sh --summary "closed P2 summary")
  jig task finding set T-1 "$f" closed
  jig task finding add T-1 --severity P3 --where - --summary "events without a hint are not scrubbed" >/dev/null
  f=$(jig task finding add T-1 --severity P1 --where src/b.sh:1 --summary "closed P1 summary")
  jig task finding set T-1 "$f" closed
}

# triage_ship_setup <level> [findings] — ship_setup at <level> with GitHub
# stubbed (merging on green checks), T-1's findings recorded when the second
# argument is `findings`, the route done and the knowledge decision recorded.
triage_ship_setup() {
  ship_setup
  ship_cfg forge github
  # Staged with the change, so a second ship finds nothing left unstaged.
  git add .ai/config.yaml
  mship_stub_gh
  ship_cfg_local agent.git "$1"
  ship_cfg_local agent.ci_timeout 0
  [ "${2:-}" != findings ] || triage_findings
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
}

test_task_ship_hands_open_findings_to_one_triage_task_verbatim() {
  triage_ship_setup pr findings
  local ledger md
  ledger=$(cat .ai/workspace/tasks/T-1/findings)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: 2 open finding(s) handed to task T-1-findings"
  md=.ai/workspace/tasks/T-1-findings/task.md
  assert_file "$md"
  assert_file_contains "$md" "# Triage the open findings of T-1"
  assert_file_contains "$md" "- Task: T-1"
  assert_file_contains "$md" "- Pull request: https://github.com/example/example/pull/99"
  assert_file_contains "$md" "- F1 · P2 · src/scrub.sh:12 — the message scrub path has no test"
  assert_file_contains "$md" "- F3 · P3 · - — events without a hint are not scrubbed"
  assert_not_contains "$(cat "$md")" "closed P2 summary"
  assert_not_contains "$(cat "$md")" "closed P1 summary"
  # Filed, not started, and linked both ways.
  assert_file_contains .ai/workspace/tasks/T-1-findings/state "triage_of: T-1"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1-findings/state)" "branch:"
  assert_file_contains .ai/workspace/tasks/T-1/state "triage_task: T-1-findings"
  # The source ledger is the one the review's receipt pinned, byte for byte.
  assert_eq "$ledger" "$(cat .ai/workspace/tasks/T-1/findings)"

  run jig task findings T-1
  assert_contains "$OUT" "handed to T-1-findings: 2 open P2/P3"
}

test_task_ship_hands_findings_over_and_still_merges() {
  triage_ship_setup merge findings

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: 2 open finding(s) handed to task T-1-findings"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
  assert_file .ai/workspace/tasks/T-1-findings/task.md
}

test_task_ship_a_second_ship_files_no_second_triage_task() {
  triage_ship_setup pr findings
  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  local md
  md=$(cat .ai/workspace/tasks/T-1-findings/task.md)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: 2 open finding(s) already handed to T-1-findings"
  assert_eq "$md" "$(cat .ai/workspace/tasks/T-1-findings/task.md)"
  assert_eq "1" "$(find .ai/workspace/tasks -maxdepth 1 -name 'T-1-*' | wc -l | tr -d ' ')"
}

test_task_ship_without_open_findings_files_no_triage_task() {
  triage_ship_setup pr
  jig task finding add T-1 --severity P2 --where - --summary "fixed and closed" >/dev/null
  jig task finding set T-1 F1 closed

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "handed"
  assert_no_file .ai/workspace/tasks/T-1-findings/state
}

test_task_ship_files_no_triage_task_without_a_pull_request_or_for_a_draft() {
  triage_ship_setup commit findings
  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "stopped at commit"
  assert_not_contains "$OUT" "handed"
  assert_no_file .ai/workspace/tasks/T-1-findings/state

  ship_cfg_local agent.git pr
  run jig task ship T-1 --message-file msg.txt --draft
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "handed"
  assert_no_file .ai/workspace/tasks/T-1-findings/state
}

test_task_ship_leaves_a_taken_triage_id_alone_and_ships() {
  triage_ship_setup pr findings
  jig task new T-1-findings >/dev/null
  local before
  before=$(cat .ai/workspace/tasks/T-1-findings/task.md)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: warning: 2 open finding(s) not handed over: task T-1-findings already exists and is not their triage"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
  assert_eq "$before" "$(cat .ai/workspace/tasks/T-1-findings/task.md)"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "triage_task:"
}

# --- a triage task closes as done ----------------------------------------------

# triage_filed <id> <source> — <id> filed as `task ship` files a triage task:
# through `jig task new`, then `triage_of: <source>` written into its state, a
# key only ship writes (task set refuses it).
triage_filed() {
  jig task new "$1" >/dev/null
  printf 'triage_of: %s\n' "$2" >> ".ai/workspace/tasks/$1/state"
}

test_task_set_closes_a_triage_task_filed_by_ship_in_one_command() {
  triage_ship_setup pr findings
  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  # shellcheck disable=SC2016 # the backticks are the text asserted
  assert_file_contains .ai/workspace/tasks/T-1-findings/task.md \
    'close this task as done: `jig task set T-1-findings status consolidated`'

  run_split jig task set T-1-findings status consolidated
  assert_eq 0 "$RC" "$ERR"
  local state
  state=$(cat .ai/workspace/tasks/T-1-findings/state)
  assert_contains "$state" "status: consolidated"
  # The knowledge decision is recorded with the close: `consolidated` still
  # implies it for every reader (ADR-0030).
  assert_contains "$state" "knowledge_consolidated: true"
  assert_not_contains "$state" "class:"
  assert_not_contains "$state" "abandoned"
  # Finished, so hidden from the live list and listed as consolidated.
  run jig task list
  assert_not_contains "$OUT" "T-1-findings"
  run jig task list --all
  assert_contains "$OUT" "T-1-findings"
  assert_contains "$OUT" "consolidated"
}

test_task_set_records_a_triage_tasks_knowledge_decision_without_a_class() {
  task_setup
  triage_filed T-1-findings T-1
  run_split jig task set T-1-findings knowledge_consolidated true
  assert_eq 0 "$RC" "$ERR"
  run_split jig task set T-1-findings status consolidated
  assert_eq 0 "$RC" "$ERR"
  assert_file_contains .ai/workspace/tasks/T-1-findings/state "status: consolidated"
}

test_task_actions_offer_close_for_a_triage_task() {
  task_setup
  triage_filed T-1-findings T-1
  jig task new T-2 >/dev/null
  _tl_json
  assert_contains "$OUT" '"id":"close","command":"jig task set T-1-findings status consolidated","offered":true,"reason":null}'
  assert_contains "$OUT" '"id":"close","command":"jig task set T-2 status consolidated","offered":false,"reason":"task set: status consolidated requires knowledge_consolidated true; record the knowledge decision first: jig task set T-2 knowledge_consolidated true"}'
}

test_task_set_still_refuses_to_close_an_unclassified_task_that_is_not_a_triage() {
  task_setup
  jig task new T-2 >/dev/null
  run_split jig task set T-2 knowledge_consolidated true
  assert_eq 1 "$RC"
  assert_contains "$ERR" "task set: the route of T-2 () is missing: class (not classified, so there is no route: jig task set T-2 class Tn)"
  run_split jig task set T-2 status consolidated
  assert_eq 1 "$RC"
  assert_contains "$ERR" "task set: status consolidated requires knowledge_consolidated true; record the knowledge decision first: jig task set T-2 knowledge_consolidated true"
  assert_file_contains .ai/workspace/tasks/T-2/state "knowledge_consolidated: false"
  assert_not_contains "$(cat .ai/workspace/tasks/T-2/state)" "status: consolidated"
}

# Classified or started, a triage task is an ordinary task again: its route is
# asked for, and the close needs the knowledge decision first.
test_task_set_asks_a_classified_or_started_triage_task_for_its_route() {
  task_setup_clean
  triage_filed T-1-findings T-1
  jig task set T-1-findings class T1 >/dev/null
  run_split jig task set T-1-findings status consolidated
  assert_eq 1 "$RC"
  assert_contains "$ERR" "requires knowledge_consolidated true"
  run_split jig task set T-1-findings knowledge_consolidated true
  assert_eq 1 "$RC"
  assert_contains "$ERR" "the route of T-1-findings (T1) is missing: verify"

  triage_filed T-3-findings T-3
  jig task start T-3-findings >/dev/null 2>&1
  assert_file_contains .ai/workspace/tasks/T-3-findings/state "branch: task/T-3-findings"
  run_split jig task set T-3-findings status consolidated
  assert_eq 1 "$RC"
  assert_contains "$ERR" "requires knowledge_consolidated true"
  run_split jig task set T-3-findings knowledge_consolidated true
  assert_eq 1 "$RC"
  assert_contains "$ERR" "class (not classified, so there is no route"
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
  task_route_done T-1
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
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no forge available; the pull request is the human's"
  assert_contains "$OUT" "not merged: no forge available; the merge is the human's"
}

# --- a release shipped as a task (adr-20261026-a-task-that-raises-the-version-is-a-release)

# rship_setup <file> <old> <new> [<other> <version>] — mship_setup on GitHub
# where <file> declares version <old> on main before T-1 is cut, and the
# task's change raises it to <new>; <other>, when given, declares <version> on
# main too and is left alone. Nobody answers (`autopilot.unattended`), so a
# release may be merged at all; each test sets `release.merge` and what else
# differs.
rship_setup() {
  local file="$1" old="$2" new="$3"
  task_setup_clean
  ship_cfg forge github
  git add .ai/config.yaml
  rship_write "$file" "$old"
  git add "${file%+*}"
  if [ $# -ge 5 ]; then
    rship_write "$4" "$5"
    git add "$4"
  fi
  git commit -q -m "fixture: version $old"
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  ship_exclude_fixture
  printf 'Ship T-1\n\nBody line one.\nBody line two.\n' > msg.txt
  mship_stub_gh
  ship_cfg_local agent.git merge
  ship_cfg_local agent.ci_timeout 0
  ship_cfg_local autopilot.unattended true
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  rship_write "$file" "$new"
  git add "${file%+*}"
}

# rship_write <file>[+<variant>] <version> — <file> declaring <version> the
# way its kind does; a variant writes the same file another way.
rship_write() {
  mkdir -p "$(dirname "$1")"
  case "$1" in
    scripts/lib/version.sh) printf '#!/bin/sh\nJIG_VERSION="%s"\n' "$2" > "$1" ;;
    package.json | composer.json) printf '{\n  "name": "example",\n  "version": "%s",\n  "dependencies": {}\n}\n' "$2" > "$1" ;;
    pyproject.toml) printf '[tool.other]\nversion = "9"\n\n[project]\nname = "example"\nversion = "%s"\n' "$2" > "$1" ;;
    Cargo.toml) printf '[workspace]\nmembers = ["a"]\n\n[workspace.dependencies.foo]\nversion = "%s"\n' "$2" > "$1" ;;
    VERSION+crlf) printf '\r\n%s\r\n' "$2" > VERSION ;;
    Cargo.toml+package) printf '[package]\nname = "example"\nversion = "%s"\n' "$2" > Cargo.toml ;;
    pyproject.toml+poetry) printf "[ tool.poetry ] # metadata\nname = 'example'\nversion = '%s'\n" "$2" > pyproject.toml ;;
    *) printf '%s\n' "$2" > "$1" ;;
  esac
}

test_task_ship_release_is_not_merged_when_release_merge_is_human() {
  rship_setup scripts/lib/version.sh 0.33.0 0.34.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version in scripts/lib/version.sh: 0.33.0 -> 0.34.0"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
  assert_contains "$OUT" "not merged: release.merge is human in this clone; the release's merge is the person's"
  assert_no_file gh-merge.argv
}

test_task_ship_release_is_merged_when_release_merge_is_agent() {
  rship_setup scripts/lib/version.sh 0.33.0 0.33.1
  ship_cfg_local release.merge agent

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
  assert_not_contains "$(cat gh-create.argv)" "--draft"
}

test_task_ship_major_release_opens_a_draft_and_is_not_merged() {
  rship_setup scripts/lib/version.sh 1.2.3 2.0.0
  ship_cfg_local release.merge agent

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$(cat gh-create.argv)" "--draft"
  assert_eq "Needs a human: major release?" "$(head -n 1 gh-create.body)"
  assert_contains "$(cat gh-create.body)" "Body line one."
  assert_contains "$OUT" "not merged: a major release needs a human; the pull request is a draft"
  assert_no_file gh-merge.argv
}

# A version that cannot be read as numbers is taken as major: a mistake
# never merges a release.
test_task_ship_unreadable_version_counts_as_major() {
  rship_setup VERSION 1.0.0 next
  ship_cfg_local release.merge agent

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: a major release needs a human; the pull request is a draft"
  assert_no_file gh-merge.argv
}

test_task_ship_release_is_not_merged_in_an_attended_ship() {
  rship_setup scripts/lib/version.sh 0.33.0 0.34.0
  ship_cfg_local release.merge agent
  ship_cfg_local autopilot.unattended false

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: this change raises the version; outside an unattended run a release's merge is the human's"
  assert_no_file gh-merge.argv
}

# Any project, not only Jig's own source: a raised package.json is a release.
test_task_ship_recognises_a_raised_package_json() {
  rship_setup package.json 1.4.0 1.5.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version in package.json: 1.4.0 -> 1.5.0"
  assert_contains "$OUT" "not merged: release.merge is human"
  assert_no_file gh-merge.argv
}

test_task_ship_change_that_keeps_the_version_is_merged_as_before() {
  rship_setup scripts/lib/version.sh 0.33.0 0.33.0
  ship_cfg_local release.merge human
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

# A file that declares a version for the first time raises nothing.
test_task_ship_first_version_declaration_is_not_a_release() {
  mship_setup github
  ship_cfg_local release.merge human
  ship_cfg_local autopilot.unattended true
  rship_write VERSION 0.1.0
  git add VERSION

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

# A task into an epic is not the release: the epic's final pull request is.
test_task_ship_version_raise_into_an_epic_is_not_a_release() {
  rship_setup scripts/lib/version.sh 0.33.0 0.34.0
  ship_cfg_local release.merge human
  git branch -q epic/x main
  git push -q origin epic/x
  sed 's|^base_branch:.*|base_branch: epic/x|' .ai/workspace/tasks/T-1/state > state.tmp
  mv state.tmp .ai/workspace/tasks/T-1/state

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

# The first file whose version went up decides, not the first that declares
# one: an unchanged VERSION does not hide a raised package.json.
test_task_ship_release_in_a_later_version_file_is_recognised() {
  rship_setup package.json 1.4.0 1.5.0 VERSION 1.0.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version in package.json: 1.4.0 -> 1.5.0"
  assert_contains "$OUT" "not merged: release.merge is human"
  assert_no_file gh-merge.argv
}

test_task_ship_recognises_a_raised_composer_json() {
  rship_setup composer.json 2.0.0 2.0.1
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version in composer.json: 2.0.0 -> 2.0.1"
  assert_no_file gh-merge.argv
}

# Only [project] (or [tool.poetry]) names the package's version: a `version`
# line of another table above it is not read.
test_task_ship_reads_pyproject_version_from_its_project_table() {
  rship_setup pyproject.toml 1.0.0 1.1.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version in pyproject.toml: 1.0.0 -> 1.1.0"
  assert_no_file gh-merge.argv
}

# A dependency's version in a workspace Cargo.toml is not the package's.
test_task_ship_cargo_dependency_version_is_not_a_release() {
  rship_setup Cargo.toml 1.0.0 2.0.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

test_task_ship_version_file_with_a_blank_crlf_first_line_is_read() {
  rship_setup VERSION+crlf 1.0.0 1.1.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version in VERSION: 1.0.0 -> 1.1.0"
  assert_no_file gh-merge.argv
}

test_task_ship_recognises_a_raised_cargo_package() {
  rship_setup Cargo.toml+package 0.4.0 0.5.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "this change raises the version in Cargo.toml: 0.4.0 -> 0.5.0"
  assert_no_file gh-merge.argv
}

# [tool.poetry] written with spaces and a comment, its version in a literal
# (single-quoted) string.
test_task_ship_recognises_a_raised_poetry_version() {
  rship_setup pyproject.toml+poetry 1.0.0 1.0.1
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "this change raises the version in pyproject.toml: 1.0.0 -> 1.0.1"
  assert_no_file gh-merge.argv
}

# The same version written another way raises nothing.
test_task_ship_same_version_written_with_a_v_is_not_a_release() {
  rship_setup VERSION 1.0.0 v1.0.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

# A version that is not X.Y.Z cannot be compared as numbers: any change of it
# is a major release.
test_task_ship_two_part_version_change_counts_as_major() {
  rship_setup VERSION 1.0 1.1
  ship_cfg_local release.merge agent

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "not merged: a major release needs a human; the pull request is a draft"
  assert_no_file gh-merge.argv
}

# A version that goes down raises nothing (a release never goes back,
# ADR-0034); the ship is an ordinary one.
test_task_ship_lowered_version_is_not_a_release() {
  rship_setup VERSION 1.5.0 1.4.0
  ship_cfg_local release.merge human

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

# origin/main is stale here, the local main is not, and the task merged the
# local main with its raise: that raise is main's, not the task's.
test_task_ship_raise_merged_in_from_a_fresher_main_is_not_the_tasks() {
  rship_setup scripts/lib/version.sh 0.33.0 0.33.0
  ship_cfg_local release.merge human
  local stale
  stale=$(git rev-parse refs/remotes/origin/main)
  git checkout -q main
  rship_write scripts/lib/version.sh 0.34.0
  git commit -q -am "release 0.34.0"
  git push -q origin main
  git update-ref refs/remotes/origin/main "$stale"
  git checkout -q task/T-1
  git merge -q --no-edit main
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "raises the version"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

# The order of spec ship: outside an unattended run a release is the human's,
# whatever release.merge says.
test_task_ship_attended_release_names_the_attended_reason_first() {
  rship_setup scripts/lib/version.sh 0.33.0 0.34.0
  ship_cfg_local release.merge human
  ship_cfg_local autopilot.unattended false

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not merged: this change raises the version; outside an unattended run a release's merge is the human's"
  assert_not_contains "$OUT" "release.merge is human"
}

test_task_ship_draft_release_says_the_raise_and_is_not_merged() {
  rship_setup scripts/lib/version.sh 0.33.0 0.34.0
  ship_cfg_local release.merge agent

  run jig task ship T-1 --message-file msg.txt --draft
  assert_eq 0 "$RC"
  assert_contains "$OUT" "this change raises the version in scripts/lib/version.sh: 0.33.0 -> 0.34.0"
  assert_contains "$(cat gh-create.argv)" "--draft"
  assert_contains "$OUT" "not merged: a draft pull request is never merged"
  assert_no_file gh-merge.argv
}

# A second ship finds the pull request already open; the release is still
# held.
test_task_ship_release_is_still_held_when_the_pr_is_already_open() {
  rship_setup scripts/lib/version.sh 0.33.0 0.34.0
  ship_cfg_local release.merge human
  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  printf 'https://github.com/example/example/pull/99\n' > gh-existing

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99 (already open)"
  assert_contains "$OUT" "not merged: release.merge is human"
  assert_no_file gh-merge.argv
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
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change

  run jig task ship T-1 --message-file msg.txt
  assert_eq 3 "$RC"
}

# --- autopilot.git (adr-20260921-agent-git-rights-are-a-local-setting, amended 2026-10-08)

test_task_ship_without_autopilot_git_a_run_ships_at_agent_git() {
  mship_setup github
  jig task autopilot T-1 start >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: git level merge (agent.git)"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

test_task_ship_autopilot_git_merge_merges_a_run_over_agent_git_pr() {
  mship_setup github
  ship_cfg_local agent.git pr
  ship_cfg_local autopilot.git merge
  jig task autopilot T-1 start >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: git level merge (autopilot.git)"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
}

test_task_ship_autopilot_git_does_not_reach_a_ship_outside_a_run() {
  mship_setup github
  ship_cfg_local agent.git pr
  ship_cfg_local autopilot.git merge

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: git level pr (agent.git)"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
  assert_not_contains "$OUT" "merged "
  assert_no_file gh-merge.argv
}

# A run that has ended ships like any other work.
test_task_ship_after_the_run_ended_goes_by_agent_git() {
  mship_setup github
  ship_cfg_local agent.git pr
  ship_cfg_local autopilot.git merge
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 end >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: git level pr (agent.git)"
  assert_no_file gh-merge.argv
}

# An attended run that stopped waits for its person, who may finish the task
# by hand: their ship goes by their own level.
test_task_ship_an_attended_stopped_run_goes_by_agent_git() {
  mship_setup github
  ship_cfg_local agent.git pr
  ship_cfg_local autopilot.git merge
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stop --reason "the gate" >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: git level pr (agent.git)"
  assert_not_contains "$OUT" "merged "
  assert_no_file gh-merge.argv
}

# An unattended run whose repairs ran out is stopped and ships its draft at
# the run's level.
test_task_ship_an_unattended_stopped_run_ships_its_draft_at_autopilot_git() {
  mship_setup github
  ship_cfg_local agent.git none
  ship_cfg_local autopilot.git pr
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason r1 >/dev/null
  jig task autopilot T-1 repair --reason r2 >/dev/null
  jig task autopilot T-1 repair --reason r3 >/dev/null 2>&1
  assert_eq stopped "$(sed -n 's/^autopilot: //p' .ai/workspace/tasks/T-1/state)"

  run jig task ship T-1 --message-file msg.txt --draft
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: git level pr (autopilot.git)"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
}

test_task_ship_autopilot_git_pr_stops_a_run_at_the_pr_over_agent_git_merge() {
  mship_setup github
  ship_cfg_local autopilot.git pr
  jig task autopilot T-1 start >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task ship: git level pr (autopilot.git)"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/99"
  assert_not_contains "$OUT" "merged "
  assert_no_file gh-merge.argv
}

test_task_ship_autopilot_git_none_hands_a_run_to_the_human() {
  mship_setup github
  ship_cfg_local autopilot.git none
  jig task autopilot T-1 start >/dev/null

  run jig task ship T-1 --message-file msg.txt
  assert_eq 3 "$RC"
  assert_contains "$OUT" "task ship: autopilot.git is none in this clone; the human commits"
}

test_task_ship_invalid_autopilot_git_refuses_a_run_and_never_falls_back() {
  mship_setup github
  ship_cfg_local autopilot.git yolo
  jig task autopilot T-1 start >/dev/null
  local head_before
  head_before=$(git rev-parse HEAD)

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task ship: invalid autopilot.git: yolo (expected none|commit|push|pr|merge)"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
}

test_task_route_and_autopilot_start_name_the_runs_git_level() {
  task_setup
  task_started T-1
  jig task set T-1 class T1 >/dev/null
  run jig task route T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "autopilot git: none (agent.git)"

  printf 'agent.git: pr\nautopilot.git: merge\n' > .ai/config.local.yaml
  run jig task route T-1
  assert_contains "$OUT" "autopilot git: merge (autopilot.git)"
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_contains "$OUT" "autopilot git: merge (autopilot.git)"
}

test_task_ship_merge_level_gitlab_merges_on_a_green_pipeline() {
  mship_setup gitlab

  run jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "merged https://gitlab.example/example/example/-/merge_requests/99"
  local argv
  argv=$(cat glab-merge.argv)
  assert_contains "$argv" "$(printf '99\n--sha\n%s' "$(git log -g -1 --format=%H --grep='^Ship T-1' HEAD)")"
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
  task_route_class T-1
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
  task_route_class T-1
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "1 blocking finding (F1 P1 fixed -)"
}

test_task_set_status_ready_succeeds_once_closed() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P1 --where - --summary "x" >/dev/null
  jig task finding set T-1 F1 closed >/dev/null
  task_route_class T-1
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

test_task_set_status_ready_open_p2_does_not_block() {
  task_setup
  jig task new T-1 >/dev/null
  jig task finding add T-1 --severity P2 --where - --summary "x" >/dev/null
  task_route_class T-1
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

# The spec's own scenario: a T2 task with a planted P1 cannot be consolidated.
test_task_set_knowledge_consolidated_refuses_planted_p1_on_t2_task() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task finding add T-1 --severity P1 --where scripts/lib/task.sh:42 --summary "planted finding" >/dev/null
  task_route_done T-1
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
  task_route_done T-1
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: true"
}

test_task_set_no_findings_file_unchanged_behaviour() {
  task_setup
  jig task new T-1 >/dev/null
  task_route_class T-1
  run jig task set T-1 status ready
  assert_eq 0 "$RC"
  task_route_done T-1
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
  assert_eq "stage stages reviewed_at tree diff context merge_base base_commit head design findings " "$keys"

  assert_file_contains .ai/workspace/tasks/T-1/receipt "stage: review"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "reviewed_at: $(date +%Y-%m-%d)"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "base_commit: $expected_base"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "findings: -"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "diff: "
  assert_file_contains .ai/workspace/tasks/T-1/receipt "context: "
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
  assert_contains "$OUT" "receipt: stale (diff"
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
  assert_contains "$OUT" "receipt: stale (diff"
}

test_task_receipt_architecture_review_stage() {
  task_setup
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
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
  jig task new T-1 --class T4 --goal "The goal." >/dev/null
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

test_task_receipt_check_stale_after_a_tracked_code_edit_names_diff() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null

  printf '# edited\n' >> AGENTS.md

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (diff, reviewed $(date +%Y-%m-%d))"
}

test_task_receipt_check_stale_after_a_new_untracked_file() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null

  printf 'new\n' > untracked.txt

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (diff"
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
  assert_contains "$OUT" "receipt: stale (diff"
}

# The case this key exists for: the base moves on and is merged into the
# task's branch, bringing files the task never touched. The task's own change
# is the same, so the receipt stays current.
test_task_receipt_check_current_after_merging_unrelated_base_changes() {
  task_setup_clean
  local base
  base=$(git symbolic-ref --short HEAD)
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'the task work\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null

  git checkout -q "$base"
  printf 'someone else\n' > other.txt
  git add other.txt
  git commit -q -m "unrelated change on the base"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"
  assert_file other.txt

  run jig task receipt T-1 --check
  assert_eq 0 "$RC"
  assert_eq "receipt: current" "$OUT"
}

# ...and the other way: the same merge, but the task's own file changes after
# the review, so the receipt goes stale.
test_task_receipt_check_stale_when_the_task_diff_changes_after_a_base_merge() {
  task_setup_clean
  local base
  base=$(git symbolic-ref --short HEAD)
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'the task work\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null

  git checkout -q "$base"
  printf 'someone else\n' > other.txt
  git add other.txt
  git commit -q -m "unrelated change on the base"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"
  printf 'the task work, changed\n' > work.txt

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (diff, reviewed"
}

# A base change to a file the task also touches changes the task's own diff
# once merged: the review did not see that interaction.
test_task_receipt_check_stale_when_a_base_merge_changes_a_file_the_task_touches() {
  task_setup_clean
  local base
  base=$(git symbolic-ref --short HEAD)
  printf 'line one\nline two\nline three\n' > shared.txt
  git add shared.txt
  git commit -q -m "shared file"
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'line one\nline two\nline three\ntask line\n' > shared.txt
  git add shared.txt
  git commit -q -m "task edit"
  jig task receipt T-1 --stage review >/dev/null

  git checkout -q "$base"
  printf 'base line\nline one\nline two\nline three\n' > shared.txt
  git add shared.txt
  git commit -q -m "base edits the same file"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (diff, reviewed"
}

# The knowledge the review resolved is pinned by content. Another hand editing
# it makes the receipt stale and the message says it is the knowledge, not the
# code; the task's own knowledge edits (consolidation) leave it current, a new
# document and an edit to one the review resolved alike.
test_task_receipt_context_follows_resolved_knowledge_not_the_tasks_own() {
  task_setup_clean
  local base
  base=$(git symbolic-ref --short HEAD)
  mkdir -p .ai/knowledge
  cat > .ai/knowledge/rule-work.md <<'EOF2'
---
id: rule-work
type: convention
status: accepted
paths:
  - work.txt
summary: Work files follow this.
---
# Work files
v1
EOF2
  git add -A
  git commit -q -m "a convention for work.txt"
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'the task work\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null

  # The task's own knowledge, written at consolidation: not a reason.
  cat > .ai/knowledge/adr-own.md <<'EOF2'
---
id: adr-own
type: adr
status: accepted
paths:
  - work.txt
summary: The task's own decision.
---
# The task decided this
EOF2
  run jig task receipt T-1 --check
  assert_eq "receipt: current" "$OUT"

  # The task edits the convention the review resolved: still its own change.
  printf 'the task adds a note\n' >> .ai/knowledge/rule-work.md
  run jig task receipt T-1 --check
  assert_eq "receipt: current" "$OUT"
  run jig task receipt T-1 --since-review
  assert_not_contains "$OUT" "knowledge the review relied on changed"
  git add -A
  git commit -q -m "the task's knowledge"
  run jig task receipt T-1 --check
  assert_eq "receipt: current" "$OUT"

  # The convention the review relied on changes by another hand, merged in.
  git checkout -q "$base"
  sed 's/^summary: .*/summary: Work files follow this, revised./' .ai/knowledge/rule-work.md > rule.tmp
  mv rule.tmp .ai/knowledge/rule-work.md
  git commit -q -am "the base revises the convention"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"
  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (context, reviewed"
  task_route_class T-1
  run jig task set T-1 status ready
  assert_contains "$OUT" "the knowledge the review relied on, not the code"
}

# Writes the convention rule-work.md (v1) that matches work.txt and commits it.
_task_receipt_commit_work_convention() {
  mkdir -p .ai/knowledge
  cat > .ai/knowledge/rule-work.md <<'EOF2'
---
id: rule-work
type: convention
status: accepted
paths:
  - work.txt
summary: Work files follow this.
---
# Work files
v1
EOF2
  git add -A
  git commit -q -m "a convention for work.txt"
}

# The base moves a convention the review applied and that is merged into the
# task's branch: the task's diff is the same, the knowledge under it is not.
test_task_receipt_check_stale_when_a_base_merge_changes_resolved_knowledge() {
  task_setup_clean
  local base
  base=$(git symbolic-ref --short HEAD)
  _task_receipt_commit_work_convention
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'the task work\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null

  git checkout -q "$base"
  printf 'v2\n' >> .ai/knowledge/rule-work.md
  git commit -q -am "the base rewrites the convention"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"

  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (context, reviewed"
}

# The same, seen from the checkout that files the task while the branch lives
# in its own worktree: the knowledge is resolved where the branch is.
test_task_receipt_context_is_resolved_in_the_tasks_worktree() {
  task_setup_nested
  local base
  base=$(git symbolic-ref --short HEAD)
  _task_receipt_commit_work_convention
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 --worktree >/dev/null
  local wt
  wt=$(git worktree list --porcelain | awk '/^worktree /{ p = substr($0, 10) } /^branch refs\/heads\/task\/T-1$/{ print p }')
  [ -n "$wt" ] || fail "task worktree not found"
  printf 'the task work\n' > "$wt/work.txt"
  jig task receipt T-1 --stage review >/dev/null

  # Editing the convention in the filing checkout is not what the review read.
  printf 'v2\n' >> .ai/knowledge/rule-work.md
  run jig task receipt T-1 --check
  assert_eq "receipt: current" "$OUT"

  # Committed on the base and merged into the task's branch, it is.
  git commit -q -am "the base rewrites the convention"
  git -C "$wt" merge -q --no-edit "$base"
  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (context, reviewed"
}

# Without a base to measure from, the pin is the whole tree, as before: any
# change is a change, and an unrelated file is not forgiven.
test_task_receipt_without_a_merge_base_pins_the_whole_tree() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  sed 's/^base_branch:.*/base_branch: no-such-branch/; s/^base_commit:.*/base_commit: 0000000000000000000000000000000000000000/' \
    .ai/workspace/tasks/T-1/state > state.tmp
  mv state.tmp .ai/workspace/tasks/T-1/state
  jig task receipt T-1 --stage review >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/receipt "diff: tree:"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "context: -"
  run jig task receipt T-1 --check
  assert_eq "receipt: current" "$OUT"

  printf 'unrelated\n' > unrelated.txt
  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (diff"
}

# A receipt written before `diff` and `context` existed is compared by `tree`.
test_task_receipt_without_diff_key_is_compared_by_tree() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  grep -v '^diff:\|^context:' .ai/workspace/tasks/T-1/receipt > r.tmp
  mv r.tmp .ai/workspace/tasks/T-1/receipt
  run jig task receipt T-1 --check
  assert_eq "receipt: current" "$OUT"

  printf 'new\n' > untracked.txt
  run jig task receipt T-1 --check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "receipt: stale (tree, reviewed"
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
  jig task new T-1 --class T4 --goal "The goal." >/dev/null
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

  task_route_class T-1

  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: review is stale: code changed since review on $(date +%Y-%m-%d) (diff; diff: the task's own change); re-review and run: jig task receipt T-1 --stage review"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
}

test_task_set_knowledge_consolidated_refuses_stale_receipt() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  printf '# edited\n' >> AGENTS.md

  task_route_done T-1

  run jig task set T-1 knowledge_consolidated true
  assert_eq 1 "$RC"
  assert_contains "$OUT" "review is stale: code changed since review on"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: false"
}

test_task_set_status_ready_refuses_t4_without_a_receipt() {
  task_setup
  jig task new T-1 --class T4 --goal "The goal." >/dev/null
  jig task start T-1 >/dev/null
  task_route_class T-1
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: T4 needs a review receipt; run the independent review, then: jig task receipt T-1 --stage review"
}

test_task_set_status_ready_refuses_t3_without_an_architecture_review() {
  task_setup
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
  jig task start T-1 >/dev/null
  printf 'design\n' > .ai/workspace/tasks/T-1/design.md
  jig task gate T-1 approved >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "architecture review (no architecture-review receipt"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
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

# The knowledge half of the receipt is checked where it decides: ship refuses
# when the base rewrote a convention the review applied, though the task's own
# diff is the same (`jig status` does not look at it; it says "not checked").
test_task_ship_refuses_a_receipt_stale_by_context() {
  task_setup_clean
  local base
  base=$(git symbolic-ref --short HEAD)
  _task_receipt_commit_work_convention
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  ship_cfg_local agent.git pr
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'the task work\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null
  sed 's/^knowledge_consolidated:.*/knowledge_consolidated: true/' \
    .ai/workspace/tasks/T-1/state > state.tmp
  mv state.tmp .ai/workspace/tasks/T-1/state

  git checkout -q "$base"
  printf 'v2\n' >> .ai/knowledge/rule-work.md
  git commit -q -am "the base rewrites the convention"
  git push -q origin "$base"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"
  printf 'Ship T-1\n\nBody.\n' > msg.txt

  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "review is stale"
  assert_contains "$OUT" "context"
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
  assert_eq "$(printf 'autopilot: on\ndepth: full (route.depth)\nautopilot git: none (agent.git)')" "$OUT"
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
  assert_eq "$(printf 'autopilot: on\ndepth: full (route.depth)\nautopilot git: none (agent.git)')" "$OUT"
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

# A pause request is honoured at the next stage boundary
# (adr-20261019-a-pause-request-is-honoured-at-the-stage-boundary): the stage
# is not entered, the task is paused, the request is taken out of the queue,
# and the run stays on — exit 4, which the skill ends the session on.
test_task_autopilot_stage_honours_a_pause_request() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stage analyze >/dev/null
  jig queue request T-1 pause --reason "need the laptop" >/dev/null
  local at rev_before rev_after
  at=$(awk -F '\t' '$1 == "request" { print $4 }' .ai/runtime/queue)
  rev_before=$(jig task list --json | sed -n 's/^{"schema":1,"revision":\([0-9]*\),.*/\1/p')
  run jig task autopilot T-1 stage implement
  assert_eq 4 "$RC" "$OUT"
  assert_eq "paused: T-1 (pause requested at $at: need the laptop); stage implement not entered" "$OUT"
  assert_eq true "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
  assert_eq "pause requested at $at: need the laptop" "$(sed -n 's/^paused_reason: //p' .ai/workspace/tasks/T-1/state)"
  assert_eq on "$(sed -n 's/^autopilot: //p' .ai/workspace/tasks/T-1/state)"
  assert_eq "" "$(grep '^request' .ai/runtime/queue || true)"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tpause\timplement not entered: pause requested at %s: need the laptop' "$at")"
  assert_eq 0 "$(grep -c "$(printf '\tstage\timplement')" .ai/workspace/tasks/T-1/autopilot)"
  rev_after=$(jig task list --json | sed -n 's/^{"schema":1,"revision":\([0-9]*\),.*/\1/p')
  [ "$rev_after" -gt "$rev_before" ] || fail "revision $rev_before -> $rev_after"
  # Paused, the run enters no stage until the task is resumed.
  run jig task autopilot T-1 stage implement
  assert_eq 4 "$RC" "$OUT"
  assert_contains "$OUT" "T-1 is paused; resume it with jig task resume T-1"
  jig task resume T-1 >/dev/null
  run jig task autopilot T-1 stage implement
  assert_eq 0 "$RC" "$OUT"
  assert_eq "stage: implement" "$OUT"
}

# Sticky: a request made of a task between two runs, or before its run
# started, is honoured by the first stage that comes.
test_task_autopilot_stage_honours_a_request_made_before_the_run() {
  task_setup
  task_started T-1
  jig queue request T-1 pause >/dev/null
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stage analyze
  assert_eq 4 "$RC" "$OUT"
  assert_contains "$OUT" "stage analyze not entered"
  assert_eq true "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
}

# The request of another task, or none at all, changes nothing.
test_task_autopilot_stage_without_a_request_of_its_own_enters_the_stage() {
  task_setup
  task_started T-1
  task_started T-2
  jig queue request T-2 pause >/dev/null
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stage analyze
  assert_eq 0 "$RC" "$OUT"
  assert_eq "stage: analyze" "$OUT"
  assert_contains "$(cat .ai/runtime/queue)" "$(printf 'request\ttask:T-2\tpause')"
}

# A run works in the task's worktree; the queue is the clone's, in the main
# checkout, and the request made there is honoured from the worktree.
test_task_autopilot_stage_honours_a_request_from_the_tasks_worktree() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt out rc
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  jig queue request T-1 pause >/dev/null
  out=$(cd "$wt" && jig task autopilot T-1 start >/dev/null && jig task autopilot T-1 stage analyze 2>&1)
  rc=$?
  assert_eq 4 "$rc" "$out"
  assert_contains "$out" "stage analyze not entered"
  assert_eq "" "$(grep '^request' .ai/runtime/queue || true)"
  assert_no_file "$wt/.ai/runtime/queue"
  assert_eq true "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
}

# A queue of another format holds no request this jig reads: the stage is
# entered, and the task lists none.
test_task_autopilot_stage_reads_no_request_from_another_queue_format() {
  task_setup
  task_started T-1
  mkdir -p .ai/runtime
  printf '# jig queue 2\nrequest\ttask:T-1\tpause\t2026-10-19T10:00:00Z\t\n' > .ai/runtime/queue
  jig task autopilot T-1 start >/dev/null
  run jig task autopilot T-1 stage analyze
  assert_eq 0 "$RC" "$OUT"
  assert_eq "stage: analyze" "$OUT"
  run_split jig task list --json
  assert_contains "$OUT" '"pause_request":null'
}

# A pause made by hand honours a pending request: it goes with it.
test_task_pause_takes_a_pending_pause_request_out() {
  task_setup
  task_started T-1
  jig queue request T-1 pause >/dev/null
  run jig task pause T-1 --reason "by hand"
  assert_eq 0 "$RC" "$OUT"
  assert_eq "" "$(grep '^request' .ai/runtime/queue || true)"
  assert_eq "by hand" "$(sed -n 's/^paused_reason: //p' .ai/workspace/tasks/T-1/state)"
}

# --if-requested: the pause a stage boundary makes when only a person's
# pending request asks for it — what `jig context resolve --stage` runs for
# a session without autopilot. Nothing pending: silent, exit 0, not paused.
test_task_pause_if_requested_without_a_request_does_nothing() {
  task_setup
  task_started T-1
  task_started T-2
  jig queue request T-2 pause >/dev/null
  run jig task pause T-1 --if-requested --stage implement
  assert_eq 0 "$RC" "$OUT"
  assert_eq "" "$OUT"
  assert_eq "" "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
  assert_contains "$(cat .ai/runtime/queue)" "$(printf 'request\ttask:T-2\tpause')"
}

# A pending request: taken out, the task paused with the request's reason,
# exit 4; without a run, no journal is written.
test_task_pause_if_requested_honours_a_pending_request() {
  task_setup
  task_started T-1
  jig queue request T-1 pause --reason "need the laptop" >/dev/null
  local at
  at=$(awk -F '\t' '$1 == "request" { print $4 }' .ai/runtime/queue)
  run jig task pause T-1 --if-requested --stage verify
  assert_eq 4 "$RC" "$OUT"
  assert_eq "paused: T-1 (pause requested at $at: need the laptop); stage verify not entered" "$OUT"
  assert_eq true "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
  assert_eq "pause requested at $at: need the laptop" "$(sed -n 's/^paused_reason: //p' .ai/workspace/tasks/T-1/state)"
  assert_eq "" "$(grep '^request' .ai/runtime/queue || true)"
  assert_no_file .ai/workspace/tasks/T-1/autopilot
  # Already paused: nothing more to do.
  run jig task pause T-1 --if-requested --stage verify
  assert_eq 0 "$RC" "$OUT"
  assert_eq "" "$OUT"
}

# With a run on, the journal records the stage it did not enter, as `task
# autopilot stage` does.
test_task_pause_if_requested_logs_a_running_autopilot() {
  task_setup
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  jig queue request T-1 pause >/dev/null
  run jig task pause T-1 --if-requested --stage review
  assert_eq 4 "$RC" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tpause\treview not entered: pause requested at ')"
  assert_eq on "$(sed -n 's/^autopilot: //p' .ai/workspace/tasks/T-1/state)"
}

# A pause that could not be written is never reported as made: the failed
# state write stops the command (errexit), with no `paused:` line and no
# exit 4. Forced with a read-only workspace directory, which makes
# _task_rewrite_state's temp-file write fail.
test_task_pause_if_requested_never_reports_a_pause_it_could_not_write() {
  skip_unless_readonly_dirs
  task_setup
  task_started T-1
  jig queue request T-1 pause >/dev/null
  chmod 555 .ai/workspace/tasks/T-1
  run jig task pause T-1 --if-requested --stage implement
  chmod 755 .ai/workspace/tasks/T-1
  [ "$RC" -ne 0 ] && [ "$RC" -ne 4 ] || fail "exit $RC: $OUT"
  assert_not_contains "$OUT" "paused:"
  assert_eq "" "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
}

test_task_pause_if_requested_refuses_what_is_not_its_own() {
  task_setup
  task_started T-1
  run jig task pause T-1 --if-requested --stage implement --reason "mine"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "takes the reason from the request"
  run jig task pause T-1 --if-requested --stage implement --stash
  assert_eq 1 "$RC"
  assert_contains "$OUT" "does not stash"
  run jig task pause T-1 --if-requested
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires --stage"
  run jig task pause T-1 --stage implement
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--stage needs --if-requested"
  run jig task pause T-1 --if-requested --stage "Bad Name"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid stage: Bad Name"
  assert_eq "" "$(sed -n 's/^paused: //p' .ai/workspace/tasks/T-1/state)"
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
  run jig task autopilot T-1 resume --answer "go on"
  assert_eq 0 "$RC"
  assert_eq "autopilot: on" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: on"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 0"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tresume\tgo on')"
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
  jig task autopilot T-1 resume --answer "approved as shown" >/dev/null
  jig task autopilot T-1 end >/dev/null
  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" " resume: approved as shown"
  assert_contains "$OUT" "Resumed on an answer (check it was yours):
- approved as shown"
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
  task_route_class T-1
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

  task_route_class T-1

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
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
  jig task start T-1 >/dev/null

  run jig task gate T-1 approved
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1 has no design.md to approve"
}

test_task_gate_refused_for_a_decision_other_than_approved() {
  task_setup
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
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
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
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
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
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
  task_route_done T-1
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
  task_route_done T-1
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
  assert_eq "$(printf 'autopilot: on\ndepth: full (route.depth)\nautopilot git: none (agent.git)')" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_mode: attended"
}

test_task_autopilot_start_records_the_unattended_mode() {
  task_setup
  task_started T-1
  unattended_local
  run jig task autopilot T-1 start
  assert_eq 0 "$RC"
  assert_eq "$(printf 'autopilot: on (unattended)\ndepth: full (route.depth)\nautopilot git: none (agent.git)')" "$OUT"
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
  : > .ai/config.local.yaml
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
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
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

# --- autopilot report: changed linked sources (linked-sources-in-pr-body) ------

# A clean jig repository with an accepted stub linking <source> (type <type>,
# default convention), committed, so a task started next forks after it.
_task_linked_source() {
  local src="$1" type="${2:-convention}" slug="${3:-style}"
  task_setup_clean
  mkdir -p "$(dirname "$src")"
  printf 'line one\n' > "$src"
  git add "$src"
  git commit -q -m "add $src"
  jig knowledge new "$type" "$slug" --source "$src" --proposed --domains a >/dev/null
  jig knowledge accept "$type-$slug" >/dev/null
  git add -A
  git commit -q -m "link $src"
}

test_task_autopilot_report_lists_a_changed_linked_source() {
  _task_linked_source docs/style.md
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  printf 'line two\nline three\n' >> docs/style.md

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  # One line per stub, with the size of the edit and the command to read it;
  # it sits with the other blocks, before the summary lines.
  assert_contains "$OUT" "$(printf '\nChanged linked sources — need your review (jig-accept):\n- convention-style: docs/style.md (modified, +2 -0) — jig knowledge sources --diff convention-style\ndepth: ')"
}

test_task_autopilot_report_has_no_linked_sources_block_without_an_edit() {
  _task_linked_source docs/style.md
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  printf 'unrelated\n' > other.md

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "Changed linked sources"
}

test_task_autopilot_report_leaves_out_a_source_a_human_approved() {
  _task_linked_source docs/style.md
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  printf 'line two\n' >> docs/style.md
  jig knowledge reviewed convention-style >/dev/null

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "Changed linked sources"
}

test_task_autopilot_report_marks_a_changed_decision_record() {
  _task_linked_source docs/adr/0009-thing.md adr thing
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  printf 'amended\n' >> docs/adr/0009-thing.md

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" "- adr-thing: docs/adr/0009-thing.md (modified, +1 -0, a decision record) — jig knowledge sources --diff adr-thing"
}

test_task_autopilot_report_lists_a_deleted_linked_source_without_a_size() {
  _task_linked_source docs/style.md
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  git rm -q docs/style.md

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" "- convention-style: docs/style.md (deleted) — jig knowledge sources --diff convention-style"
}

# A branch checked out nowhere in this clone cannot be read; the report says
# so rather than leave the block out, which would read as "nothing changed".
test_task_autopilot_report_says_when_linked_sources_were_not_checked() {
  _task_linked_source docs/style.md
  task_started T-1
  jig task autopilot T-1 start >/dev/null
  git checkout -q main

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" "Changed linked sources: not checked, task/T-1 is not checked out in this clone"
}

# Asked for from the main checkout, the report reads the edits where the
# task's branch is: its worktree, not the checkout the command runs in.
test_task_autopilot_report_reads_linked_sources_in_the_task_worktree() {
  # Nested, as task_setup_nested is: the worktree is created beside the repo.
  mkdir repo && cd repo || return 1
  _task_linked_source docs/style.md
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  (cd "$wt" && jig task autopilot T-1 start >/dev/null && printf 'line two\n' >> docs/style.md)

  run jig task autopilot T-1 report
  assert_eq 0 "$RC"
  assert_contains "$OUT" "- convention-style: docs/style.md (modified, +1 -0) — jig knowledge sources --diff convention-style"
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
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
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
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
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
  jig task new T-1 --class T3 --goal "The goal." >/dev/null
  jig task start T-1 >/dev/null
  printf '# design\n' > .ai/workspace/tasks/T-1/design.md
  run jig task gate T-1 approved
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate_by: human"
  run jig task gate T-1 approved --by robot
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task gate: invalid --by: robot (expected human|agent)"
}

test_task_set_refuses_script_owned_run_and_triage_keys() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  local key
  for key in autopilot_mode gate_by triage_task triage_of; do
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
  task_route_done T-1
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
  task_route_done T-1
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

# --- route depth (adr-20261002-route-depth-is-a-personal-choice) --------------

test_task_new_lean_records_the_depth_in_state() {
  task_setup
  run jig task new T-1 --class T2 --lean
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "^route_depth: lean$"
}

test_task_new_without_lean_records_no_depth() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "route_depth"
}

test_task_route_full_by_default_names_the_class_route() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "class: T2"
  assert_contains "$OUT" "depth: full (route.depth)"
  assert_contains "$OUT" "route: analyze, plan, implement, review, verify, consolidate"
  assert_not_contains "$OUT" "lean:"
  assert_contains "$OUT" "never trimmed: tests on changed files, CI before a merge, consolidation"
}

test_task_route_lean_task_folds_the_plan_into_the_analysis() {
  task_setup
  jig task new T-1 --class T2 --lean >/dev/null
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "depth: lean (task)"
  assert_contains "$OUT" "route: analyze, implement, review, verify, consolidate"
  assert_contains "$OUT" "lean: the plan is part of the analysis; one review round"
  assert_contains "$OUT" "a re-review only closes a fixed P0/P1"
}

# The floor: lean never removes the gate or the architecture review of T3, nor
# a stage of T4's route.
test_task_route_lean_keeps_every_stage_of_t3_and_t4() {
  task_setup
  jig task new T-3 --class T3 --lean >/dev/null
  jig task new T-4 --class T4 --lean >/dev/null
  run jig task route T-3
  assert_contains "$OUT" "route: discover, design, human gate, implement, architecture review, verify, consolidate"
  assert_contains "$OUT" "lean: the gate, the architecture review and verify are unchanged"
  run jig task route T-4
  assert_contains "$OUT" "route: discover, specify, alternatives, design, human gate, implement, independent review, verify, consolidate"
}

test_task_route_follows_the_personal_setting_and_the_task_overrides_it() {
  task_setup
  jig task new T-1 --class T1 >/dev/null
  jig config set route.depth lean --local >/dev/null
  run jig task route T-1
  assert_contains "$OUT" "depth: lean (route.depth)"
  assert_contains "$OUT" "lean: the analysis is a few lines in task.md"
  run jig task set T-1 route_depth full
  assert_eq 0 "$RC" "$OUT"
  run jig task route T-1
  assert_contains "$OUT" "depth: full (task)"
  assert_not_contains "$OUT" "lean:"
}

# A project value does nothing: the setting is one person's (local-only), and
# a hand-written invalid local value reads as full — a mistake costs process,
# never a stage.
test_task_route_ignores_a_project_value_and_reads_an_invalid_one_as_full() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  printf 'route.depth: lean\n' >> .ai/config.yaml
  run jig task route T-1
  assert_contains "$OUT" "depth: full (route.depth)"
  printf 'route.depth: light\n' > .ai/config.local.yaml
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "depth: full (route.depth)"
  assert_contains "$OUT" "route: analyze, plan, implement, review, verify, consolidate"
}

test_task_route_unclassified_task_has_no_route_yet() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "class: -"
  assert_contains "$OUT" "route: none until the task is classified (jig task set T-1 class Tn)"
}

test_task_route_unknown_task_dies() {
  task_setup
  run jig task route nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task route: unknown task: nope"
}

# --- delegation (adr-20261005-jig-names-the-roles-not-the-models) -------------

test_task_route_names_no_delegate_when_no_model_is_set() {
  task_setup
  jig task new T-1 --class T3 >/dev/null
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "delegate:"
  assert_not_contains "$OUT" "executor:"
}

test_task_route_names_each_delegated_stage_with_the_model_as_written() {
  task_setup
  jig task new T-2 --class T2 >/dev/null
  jig task new T-3 --class T3 >/dev/null
  jig config set claude.implement_model sonnet claude.review_model 'opus[1m]' --local >/dev/null
  run jig task route T-2
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "delegate: implement -> sonnet (claude.implement_model)"
  assert_contains "$OUT" "delegate: review -> opus[1m] (claude.review_model)"
  run jig task route T-3
  assert_contains "$OUT" "delegate: review -> opus[1m] (claude.review_model)"
}

# A route with no review stage gets no review line; the implement line stays.
test_task_route_names_no_review_delegate_for_a_class_without_review() {
  task_setup
  jig task new T-1 --class T1 >/dev/null
  jig config set claude.implement_model haiku claude.review_model sonnet --local >/dev/null
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "delegate: implement -> haiku (claude.implement_model)"
  assert_not_contains "$OUT" "delegate: review"
}

# Local-only: a model committed to the project's file delegates nothing.
test_task_route_ignores_a_model_in_the_project_file() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  printf 'claude.review_model: opus\n' >> .ai/config.yaml
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "delegate:"
}

test_task_route_names_codex_model_for_matching_stage() {
  task_setup
  jig task new T-2 --class T2 >/dev/null
  jig task new T-1 --class T1 >/dev/null
  jig config set codex.implement_model gpt-6-luna codex.review_model gpt-6.1-sol --local >/dev/null
  run jig task route T-2
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "delegate: implement -> gpt-6-luna (codex.implement_model)"
  assert_contains "$OUT" "delegate: review -> gpt-6.1-sol (codex.review_model)"
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "delegate: implement -> gpt-6-luna (codex.implement_model)"
  assert_not_contains "$OUT" "delegate: review"
}

test_task_route_keeps_runtime_specific_model_lines_separate() {
  task_setup
  jig task new T-2 --class T2 >/dev/null
  jig config set claude.review_model opus codex.review_model gpt-6.1-sol --local >/dev/null
  run jig task route T-2
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "delegate: review -> opus (claude.review_model)"
  assert_contains "$OUT" "delegate: review -> gpt-6.1-sol (codex.review_model)"
}

test_task_route_ignores_codex_model_in_project_file() {
  task_setup
  jig task new T-2 --class T2 >/dev/null
  printf 'codex.review_model: gpt-6.1-sol\n' >> .ai/config.yaml
  run jig task route T-2
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "delegate:"
}

test_task_route_names_external_executor_without_changing_stage_evidence() {
  task_setup
  jig task new T-2 --class T2 >/dev/null
  jig task new T-1 --class T1 >/dev/null
  jig config set executor.implement_runtime claude executor.review_runtime codex \
    executor.implement_model sonnet executor.review_model gpt-6.1-sol --local >/dev/null
  run jig task route T-2
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "executor: implement -> claude (executor.implement_runtime; local config)"
  assert_contains "$OUT" "executor model: implement -> sonnet (executor.implement_model; local config)"
  assert_contains "$OUT" "executor: review -> codex (executor.review_runtime; local config)"
  assert_contains "$OUT" "executor model: review -> gpt-6.1-sol (executor.review_model; local config)"
  assert_contains "$OUT" "route: analyze, plan, implement, review, verify, consolidate"
  run jig task route T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "executor: implement -> claude (executor.implement_runtime; local config)"
  assert_not_contains "$OUT" "executor: review"
}

test_task_route_ignores_external_executor_in_project_config() {
  task_setup
  jig task new T-2 --class T2 >/dev/null
  printf 'executor.review_runtime: codex\n' >> .ai/config.yaml
  run jig task route T-2
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "executor:"
}

test_task_executor_choices_are_isolated_by_task_and_frozen_at_start() {
  task_setup_clean
  jig task new T-a --class T2 >/dev/null
  jig task new T-b --class T2 >/dev/null
  jig config set executor.implement_runtime claude executor.review_runtime claude \
    executor.review_model sonnet --local >/dev/null
  jig task set T-a executor_implement_runtime codex
  jig task set T-a executor_implement_model gpt-6.1-sol
  jig task set T-b executor_review_runtime codex
  run jig task route T-a
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "executor: implement -> codex (executor.implement_runtime; task)"
  assert_contains "$OUT" "executor model: implement -> gpt-6.1-sol (executor.implement_model; task)"
  assert_contains "$OUT" "executor: review -> claude (executor.review_runtime; local config)"
  run jig task route T-b
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "executor: implement -> claude (executor.implement_runtime; local config)"
  assert_contains "$OUT" "executor: review -> codex (executor.review_runtime; task)"
  assert_contains "$OUT" "executor model: review -> sonnet (executor.review_model; local config)"
  jig task start T-a >/dev/null
  local second_tree
  second_tree=$(jig task start T-b --worktree)
  OUT=$(cd "$second_tree" && jig task route T-b)
  assert_contains "$OUT" "executor: review -> codex (executor.review_runtime; task)"
  assert_contains "$OUT" "executor: implement -> claude (executor.implement_runtime; local config)"
  jig config set executor.implement_runtime codex executor.review_runtime codex \
    executor.review_model opus --local >/dev/null
  OUT=$(cd "$second_tree" && jig task route T-b)
  assert_contains "$OUT" "executor: implement -> claude (executor.implement_runtime; local config)"
  assert_contains "$OUT" "executor model: review -> sonnet (executor.review_model; local config)"
  run jig task set T-a executor_review_runtime codex
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'executor choice is fixed'
  run jig task route T-a
  assert_contains "$OUT" "executor: review -> claude (executor.review_runtime; local config)"
  run jig task route T-b
  assert_contains "$OUT" "executor: review -> codex (executor.review_runtime; task)"
}

test_task_start_freezes_an_unset_executor_against_later_local_settings() {
  task_setup_clean
  jig task new T-2 --class T2 >/dev/null
  jig task start T-2 >/dev/null
  jig config set executor.implement_runtime codex --local >/dev/null
  run jig task route T-2
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" 'executor:'
  assert_contains "$(cat .ai/workspace/tasks/T-2/state)" 'executor_implement_runtime_source: default'
}

test_task_executor_wave_keeps_diffs_and_receipts_separate_after_first_merge() {
  task_setup_clean
  mkdir -p .ai/specs/two
  cat > .ai/specs/two/roadmap.md <<'RM'
# Two-task wave

## Phase 1 — Two executors

- [ ] `T-a` — Alpha — first task
- [ ] `T-b` — Bravo — second task
- [ ] `T-next` — Next — later task

## Waves

1. Alpha; Bravo
2. Next
RM
  git add .ai/specs/two/roadmap.md
  git commit -q -m 'file two-task wave'
  jig task new T-a --class T2 >/dev/null
  jig task new T-b --class T2 >/dev/null
  jig task new T-next --class T2 >/dev/null
  local a b
  for a in T-a T-b; do
    printf 'Spec: .ai/specs/two/ — Phase 1\n' >> ".ai/workspace/tasks/$a/task.md"
  done
  jig task set T-a executor_implement_runtime claude
  jig task set T-b executor_implement_runtime codex
  a=$(jig task start T-a --worktree 2>/dev/null)
  b=$(jig task start T-b --worktree 2>/dev/null)
  assert_contains "$(cd "$a" && jig task route T-a)" 'executor: implement -> claude (executor.implement_runtime; task)'
  assert_contains "$(cd "$b" && jig task route T-b)" 'executor: implement -> codex (executor.implement_runtime; task)'
  printf 'owned by alpha\n' > "$a/alpha.txt"
  git -C "$a" add alpha.txt
  git -C "$a" commit -q -m alpha
  printf 'owned by bravo\n' > "$b/bravo.txt"
  git -C "$b" add bravo.txt
  git -C "$b" commit -q -m bravo
  assert_eq alpha.txt "$(git -C "$a" diff --name-only main...task/T-a)"
  assert_eq bravo.txt "$(git -C "$b" diff --name-only main...task/T-b)"
  jig task receipt T-b --stage review >/dev/null
  git merge -q --no-ff --no-edit task/T-a
  git -C "$b" merge -q --no-edit main
  assert_eq bravo.txt "$(git -C "$b" diff --name-only main...task/T-b)"
  run jig task receipt T-b --check
  assert_eq 0 "$RC" "$OUT"
  assert_eq 'receipt: current' "$OUT"
  (cd "$b" && jig task autopilot T-b start --phase two/1 >/dev/null)
  (cd "$b" && jig task autopilot T-b stop --reason 'selected executor unavailable' >/dev/null)
  run jig spec plan two --phase 1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" 'wave 2 — waiting'
  assert_contains "$OUT" 'T-b'
  assert_contains "$(cat .ai/workspace/tasks/T-b/state)" 'autopilot: stopped'
}

test_task_executor_choice_validates_and_inherit_removes_override() {
  task_setup
  jig task new T-2 --class T2 >/dev/null
  run jig task set T-2 executor_implement_runtime other
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'not a runtime: claude or codex'
  run jig task set T-2 executor_review_model 'bad#model'
  assert_eq 1 "$RC"
  jig task set T-2 executor_implement_runtime codex
  run jig task route T-2
  assert_contains "$OUT" "executor: implement -> codex (executor.implement_runtime; task)"
  jig task set T-2 executor_implement_runtime inherit
  run jig task route T-2
  assert_not_contains "$OUT" 'executor: implement'
  assert_not_contains "$(cat .ai/workspace/tasks/T-2/state)" 'executor_implement_runtime'
}

test_task_set_route_depth_refuses_anything_but_full_or_lean() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  run jig task set T-1 route_depth light
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: invalid route_depth: light (full or lean)"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "route_depth"
}

test_task_autopilot_start_and_report_name_the_depth() {
  task_setup
  task_started T-1 --class T2 --lean
  run jig task autopilot T-1 start
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "depth: lean (task)"
  jig task autopilot T-1 end >/dev/null
  run jig task autopilot T-1 report
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "depth: lean (task)"
  assert_contains "$OUT" "autopilot: done, repairs: 0/2"
}

# `jig task artifacts` follows the same depth: a lean T2 has no plan stage and
# its implement stage reads the analysis, not a plan that will never be written.
test_task_artifacts_lean_t2_has_no_plan_stage() {
  task_setup
  jig task new T-1 --class T2 --lean >/dev/null
  run jig task artifacts T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task: T-1; class: T2; depth: lean"
  assert_not_contains "$OUT" "plan: "
  assert_contains "$OUT" "implement: needs-input; inputs: task discovery"
  printf 'analysis\n' > .ai/workspace/tasks/T-1/discovery.md
  run jig task artifacts T-1
  assert_contains "$OUT" "implement: inputs-available; inputs: task discovery"
}

test_task_artifacts_full_t2_keeps_the_plan_stage() {
  task_setup
  jig task new T-1 --class T2 >/dev/null
  run jig task artifacts T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task: T-1; class: T2; depth: full"
  assert_contains "$OUT" "plan: needs-input; inputs: task discovery"
}

# --- route evidence (adr-20261004-a-route-stage-is-proven-by-its-record) ------

# route_task [<task new args>] — T-1 filed with <args> and started.
route_task() {
  task_setup
  jig task new T-1 --goal "The goal." "$@" >/dev/null
  jig task start T-1 >/dev/null
}

route_design() {
  printf '# design\n\nthe answer\n' > .ai/workspace/tasks/T-1/design.md
}

test_route_evidence_t3_without_a_gate_is_refused_at_ready() {
  route_task --class T3
  route_design
  jig task receipt T-1 --stage architecture-review >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: the route of T-1 (T3) is missing: human gate (no approval recorded: jig task gate T-1 approved)"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: active"
}

test_route_evidence_t3_without_a_design_names_design_and_gate() {
  route_task --class T3
  jig task receipt T-1 --stage architecture-review >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "design (no design.md: jig task artifact write T-1 design); human gate (no approval recorded"
}

test_route_evidence_t3_without_an_architecture_review_is_refused_at_ready() {
  route_task --class T3
  route_design
  jig task gate T-1 approved >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is missing: architecture review (no architecture-review receipt: jig task receipt T-1 --stage architecture-review)"
}

test_route_evidence_t3_review_receipt_is_not_an_architecture_review() {
  route_task --class T3
  route_design
  jig task gate T-1 approved >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "architecture review (no architecture-review receipt"
}

test_route_evidence_t3_design_changed_after_the_gate_is_refused() {
  route_task --class T3
  route_design
  jig task gate T-1 approved >/dev/null
  printf 'changed after approval\n' >> .ai/workspace/tasks/T-1/design.md
  jig task receipt T-1 --stage architecture-review >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "human gate (the design changed after its approval: take it back to the gate, then jig task gate T-1 approved)"
}

# route_t3_complete — every record a T3 route leaves, in route order.
route_t3_complete() {
  route_design
  jig task gate T-1 approved >/dev/null
  jig task receipt T-1 --stage architecture-review >/dev/null
}

test_route_evidence_t3_complete_full_run_passes_every_gate() {
  route_task --class T3
  route_t3_complete
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "missing"
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "knowledge_consolidated: true"
}

test_route_evidence_t3_complete_lean_run_passes_and_lean_keeps_the_gate() {
  route_task --class T3 --lean
  route_design
  jig task receipt T-1 --stage architecture-review >/dev/null
  # Lean trims nothing a T3 route records: the gate is still asked for.
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "human gate (no approval recorded"
  jig task gate T-1 approved >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC" "$OUT"
}

test_route_evidence_unattended_self_approval_counts_as_the_gate() {
  route_task --class T3
  unattended_local
  jig task autopilot T-1 start >/dev/null
  route_design
  jig task gate T-1 approved --by agent >/dev/null
  jig task receipt T-1 --stage architecture-review >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
}

test_route_evidence_receipt_remembers_every_stage_it_was_written_for() {
  route_task --class T3
  route_t3_complete
  # A re-review under the other stage does not erase the architecture review.
  jig task receipt T-1 --stage review >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/receipt "stage: review"
  assert_file_contains .ai/workspace/tasks/T-1/receipt "stages: architecture-review,review"
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
}

test_route_evidence_receipt_without_stages_counts_its_own_stage() {
  route_task --class T3
  route_t3_complete
  # A receipt written before `stages:` existed (the stale check ignores the
  # line, so dropping it changes nothing else).
  grep -v '^stages:' .ai/workspace/tasks/T-1/receipt > r.tmp
  mv r.tmp .ai/workspace/tasks/T-1/receipt
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
}

test_route_evidence_t2_without_a_review_is_refused_at_ready() {
  route_task --class T2
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: the route of T-1 (T2) is missing: review (no review receipt: jig task receipt T-1 --stage review)"
}

test_route_evidence_t2_complete_full_and_lean_runs_pass() {
  route_task --class T2
  jig task receipt T-1 --stage review >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC" "$OUT"

  jig task new T-2 --class T2 --lean >/dev/null
  jig task start T-2 >/dev/null
  run jig task set T-2 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "review (no review receipt"
  jig task receipt T-2 --stage review >/dev/null
  run jig task set T-2 status ready
  assert_eq 0 "$RC" "$OUT"
  run jig task set T-2 knowledge_consolidated true
  assert_eq 0 "$RC" "$OUT"
}

test_route_evidence_t4_names_the_spec_and_the_alternatives() {
  route_task --class T4
  route_design
  jig task gate T-1 approved >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "specify (no spec.md: jig task artifact write T-1 spec); alternatives (no alternatives.md: jig task artifact write T-1 alternatives)"
  printf 'spec\n' > .ai/workspace/tasks/T-1/spec.md
  printf 'alternatives\n' > .ai/workspace/tasks/T-1/alternatives.md
  # The documents the gate pins changed: approve and review them again.
  jig task gate T-1 approved >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
}

test_route_evidence_knowledge_decision_asks_for_verify_sign_off() {
  route_task --class T0
  run jig task set T-1 knowledge_consolidated true
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: the route of T-1 (T0) is missing: verify (not signed off: jig verify, then jig task set T-1 status ready)"
  jig task set T-1 status ready >/dev/null
  run jig task set T-1 knowledge_consolidated true
  assert_eq 0 "$RC" "$OUT"
}

test_route_evidence_unclassified_task_is_refused() {
  route_task
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is missing: class (not classified, so there is no route: jig task set T-1 class Tn)"
}

test_route_evidence_a_task_filed_before_the_check_passes_with_a_warning() {
  route_task --class T3
  grep -v '^route_evidence:' .ai/workspace/tasks/T-1/state > s.tmp
  mv s.tmp .ai/workspace/tasks/T-1/state
  run jig task set T-1 status ready
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jig: warning: task set: T-1 was filed before route evidence was checked, so this passes without: design (no design.md"
  assert_contains "$OUT" "human gate (no approval recorded"
  assert_file_contains .ai/workspace/tasks/T-1/state "status: ready"
}

test_route_evidence_task_set_refuses_its_keys() {
  route_task --class T1
  local key
  for key in route_evidence class_lowered_from class_lowered_reason; do
    run jig task set T-1 "$key" x
    assert_eq 1 "$RC"
    assert_contains "$OUT" "not writable: $key"
  done
}

test_route_evidence_ship_rechecks_the_route() {
  ship_setup
  ship_cfg_local agent.git commit
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  # Verify's sign-off withdrawn after the knowledge decision.
  jig task set T-1 status active >/dev/null
  ship_stage_change
  local head_before
  head_before=$(git rev-parse HEAD)
  run jig task ship T-1 --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task ship: the route of T-1 (T0) is missing: verify (not signed off"
  assert_eq "$head_before" "$(git rev-parse HEAD)"
}

# --- lowering a class ----------------------------------------------------------

test_route_lowering_a_class_needs_a_reason() {
  route_task --class T3
  run jig task set T-1 class T1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task set: lowering T-1 from T3 to T1 sheds stages of its route; say why: jig task set T-1 class T1 --reason <text>"
  assert_file_contains .ai/workspace/tasks/T-1/state "class: T3"
}

test_route_lowering_is_recorded_and_shown() {
  route_task --class T3
  run jig task set T-1 class T1 --reason "only a message changes"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "class: T1"
  assert_file_contains .ai/workspace/tasks/T-1/state "class_lowered_from: T3"
  assert_file_contains .ai/workspace/tasks/T-1/state "class_lowered_reason: only a message changes"
  run jig task route T-1
  assert_contains "$OUT" "lowered: from T3: only a message changes"
  run jig status
  assert_contains "$OUT" "task T-1 class=T1 status=active lowered=T3"
  # Lowering again keeps the highest class it came from.
  jig task set T-1 class T0 --reason "nothing to analyze" >/dev/null
  assert_file_contains .ai/workspace/tasks/T-1/state "class_lowered_from: T3"
  # Raising back to where it came from clears the record.
  jig task set T-1 class T3 >/dev/null
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "class_lowered_from"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "class_lowered_reason"
}

test_route_lowering_reason_is_only_for_a_lower_class() {
  route_task --class T1
  run jig task set T-1 class T2 --reason "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason is only for lowering a class"
  run jig task set T-1 status active --reason "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--reason is only for lowering a class"
}

test_route_lowering_out_of_the_gate_is_refused_in_an_unattended_run() {
  route_task --class T3
  unattended_local
  jig task autopilot T-1 start >/dev/null
  run jig task set T-1 class T2 --reason "small after all"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "an unattended run does not lower T-1 from T3 below T3"
  assert_file_contains .ai/workspace/tasks/T-1/state "class: T3"
}

test_route_lowering_is_journaled_and_reported_in_a_run() {
  route_task --class T4
  unattended_local
  jig task autopilot T-1 start >/dev/null
  # T4 to T3 keeps the gate, so an unattended run may do it.
  run jig task set T-1 class T3 --reason "no money involved"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tlower\tT4 to T3: no money involved')"
  run jig task autopilot T-1 report
  assert_contains "$OUT" "Class lowered:
- from T4 to T3: no money involved"
}

# --- resume needs an answer --------------------------------------------------------

test_route_resume_without_an_answer_is_refused() {
  route_task --class T1
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stop --reason "which API?" >/dev/null
  run jig task autopilot T-1 resume
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--answer is required"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"
}

test_route_resume_is_refused_in_an_unattended_run() {
  route_task --class T1
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason r1 >/dev/null
  jig task autopilot T-1 repair --reason r2 >/dev/null
  jig task autopilot T-1 repair --reason r3 >/dev/null
  run jig task autopilot T-1 resume --answer "try again" --by human
  assert_eq 1 "$RC"
  assert_contains "$OUT" "exhausted its unattended repair limit"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 2"
}

test_route_unattended_manual_stop_resumes_only_on_human_answer_without_reset() {
  route_task --class T1
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason r1 >/dev/null
  jig task autopilot T-1 stop --reason "ask the owner" >/dev/null

  run jig task autopilot T-1 resume --answer "use CI as evidence"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "needs an actual human answer and --by human"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"

  run jig task autopilot T-1 resume --answer "use CI as evidence" --by human
  assert_eq 0 "$RC"
  assert_eq "autopilot: on" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot_repairs: 1"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tresume\thuman: use CI as evidence')"
  run jig task autopilot T-1 repair --reason r2
  assert_eq 0 "$RC"
  assert_eq "repair 2/2" "$OUT"
  run jig task autopilot T-1 repair --reason r3
  assert_eq 3 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"
}

test_route_unattended_gate_after_human_answer_stays_agent_approved() {
  route_task --class T3
  printf '# Design\n' > .ai/workspace/tasks/T-1/design.md
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stop --reason "owner answered in chat" >/dev/null

  run jig task gate T-1 approved --by human
  assert_eq 1 "$RC"
  assert_contains "$OUT" "resume --answer <text> --by human"
  run jig task gate T-1 approved --by agent
  assert_eq 1 "$RC"
  run jig task autopilot T-1 resume --answer "approve the narrower scope" --by human
  assert_eq 0 "$RC"
  run jig task gate T-1 approved --by agent
  assert_eq 0 "$RC"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate_by: agent"
}

test_route_lowering_out_of_the_gate_is_refused_after_an_unattended_run_stopped() {
  route_task --class T3
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 stop --reason "stuck" >/dev/null
  # The key unset afterwards changes nothing: the run was unattended.
  : > .ai/config.local.yaml
  run jig task set T-1 class T1 --reason "small after all"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "an unattended run does not lower T-1 from T3 below T3"
}

test_route_lowering_out_of_the_gate_is_refused_where_the_clone_is_unattended() {
  route_task --class T4
  unattended_local
  run jig task set T-1 class T2 --reason "small after all"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "does not lower T-1 from T4 below T3"
}

test_route_unattended_run_ends_only_after_the_knowledge_decision() {
  route_task --class T0
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason r1 >/dev/null
  jig task autopilot T-1 repair --reason r2 >/dev/null
  # Ending and starting again would be two fresh repairs nobody granted.
  run jig task autopilot T-1 end
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unattended run ends after consolidation"
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: on"
  jig task set T-1 status ready >/dev/null
  jig task set T-1 knowledge_consolidated true >/dev/null
  run jig task autopilot T-1 end
  assert_eq 0 "$RC" "$OUT"
}

test_route_gate_in_an_unattended_run_is_the_agents() {
  route_task --class T3
  unattended_local
  jig task autopilot T-1 start >/dev/null
  route_design
  run jig task gate T-1 approved
  assert_eq 1 "$RC"
  assert_contains "$OUT" "this approval is the agent's: jig task gate T-1 approved --by agent"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "gate: approved"
}

# Before a run starts, the person working the task is there to approve it
# (test_task_gate_in_an_unattended_clone_without_a_run_is_the_persons).
test_route_gate_in_an_unattended_clone_before_a_run_is_the_persons() {
  route_task --class T3
  unattended_local
  route_design
  run jig task gate T-1 approved
  assert_eq 0 "$RC" "a person could not approve before a run started: $OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate: approved"
}

test_route_gate_in_an_unattended_clone_is_refused_when_the_run_is_stopped() {
  route_task --class T3
  unattended_local
  jig task autopilot T-1 start >/dev/null
  jig task autopilot T-1 repair --reason r1 >/dev/null
  jig task autopilot T-1 repair --reason r2 >/dev/null
  jig task autopilot T-1 repair --reason r3 >/dev/null || true
  route_design
  assert_file_contains .ai/workspace/tasks/T-1/state "autopilot: stopped"
  run jig task gate T-1 approved
  assert_eq 1 "$RC"
  assert_contains "$OUT" "exhausted its unattended repair limit; ship a draft"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "gate: approved"
}

test_route_gate_in_an_attended_clone_stays_the_humans() {
  route_task --class T3
  route_design
  run jig task gate T-1 approved
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains .ai/workspace/tasks/T-1/state "gate: approved"
}

test_route_evidence_ignores_the_persons_depth() {
  route_task --class T2
  # A lean setting trims the plan, which leaves no record; the review is
  # still asked for, whatever the person's depth.
  printf 'route.depth: lean\n' >> .ai/config.local.yaml
  run jig task set T-1 status ready
  assert_eq 1 "$RC"
  assert_contains "$OUT" "review (no review receipt"
}

# --- tracker issue (adr-20261010-a-task-carries-its-tracker-issue) -------------

# issue_cfg <pattern> — set the project's task.issue_pattern, written exactly
# as given (quotes included).
issue_cfg() {
  printf 'task.issue_pattern: %s\n' "$1" >> .ai/config.yaml
}

# issue_of <id> — the task's recorded issue, or nothing.
issue_of() {
  sed -n 's/^issue: //p' ".ai/workspace/tasks/$1/state"
}

test_task_new_reads_no_issue_without_a_pattern() {
  task_setup
  jig task new PROJ-12-fix-login >/dev/null
  jig task new release-0-25-1 >/dev/null
  assert_eq "" "$(issue_of PROJ-12-fix-login)"
  assert_eq "" "$(issue_of release-0-25-1)"
}

test_task_new_reads_an_alphanumeric_issue_from_the_start_of_the_id() {
  task_setup
  issue_cfg "'[A-Z][A-Z0-9]*-[0-9]+'"
  jig task new SRD-2455-fix-login >/dev/null
  jig task new SRD-77 >/dev/null
  jig task new SRD-2455x-fix >/dev/null
  jig task new release-0-25-1 >/dev/null
  jig task new fix-SRD-1 >/dev/null
  assert_eq "SRD-2455" "$(issue_of SRD-2455-fix-login)"
  assert_eq "SRD-77" "$(issue_of SRD-77)"
  assert_eq "" "$(issue_of SRD-2455x-fix)"
  assert_eq "" "$(issue_of release-0-25-1)"
  assert_eq "" "$(issue_of fix-SRD-1)"
}

test_task_new_reads_a_numeric_issue() {
  task_setup
  issue_cfg '[0-9]+'
  jig task new 123-fix-login >/dev/null
  jig task new 45_cache >/dev/null
  jig task new release-0-25-1 >/dev/null
  jig task new 123abc-fix >/dev/null
  assert_eq "123" "$(issue_of 123-fix-login)"
  assert_eq "45" "$(issue_of 45_cache)"
  assert_eq "" "$(issue_of release-0-25-1)"
  assert_eq "" "$(issue_of 123abc-fix)"
}

test_task_new_with_an_unreadable_pattern_files_the_task_without_an_issue() {
  task_setup
  issue_cfg '[0-9'
  run jig task new 123-fix
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task.issue_pattern is not a pattern awk can read"
  assert_file .ai/workspace/tasks/123-fix/state
  assert_eq "" "$(issue_of 123-fix)"
}

test_task_set_refuses_the_issue() {
  task_setup
  jig task new T-1 >/dev/null
  run jig task set T-1 issue PROJ-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "key is not writable: issue"
}

test_task_list_and_show_name_the_issue() {
  task_setup
  issue_cfg '[A-Z]+-[0-9]+'
  jig task new SRD-9-fix --class T1 >/dev/null
  jig task new other --class T1 >/dev/null
  run jig task list
  assert_contains "$OUT" "SRD-9-fix class=T1 status=active issue=SRD-9 not-started"
  assert_contains "$OUT" "other class=T1 status=active not-started"
  run jig task show SRD-9-fix
  assert_contains "$OUT" "issue: SRD-9"
}

# issue_ship_setup <pattern> <id> — ship_setup for a task named after an
# issue, with the pattern committed on the base branch first, so that it is
# fixture and not an unstaged change the ship refuses to go past.
issue_ship_setup() {
  task_setup_clean
  issue_cfg "$1"
  git add .ai/config.yaml
  git commit -q -m "fixture: tracker issues"
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  jig task new "$2" >/dev/null
  jig task start "$2" >/dev/null
  printf 'Fix the login form\n\nBody line one.\n' > msg.txt
  task_route_done "$2"
  jig task set "$2" knowledge_consolidated true >/dev/null
  ship_stage_change
}

test_task_ship_puts_the_issue_before_the_commit_subject() {
  issue_ship_setup '[A-Z]+-[0-9]+' SRD-2455-fix-login
  ship_cfg_local agent.git commit
  run jig task ship SRD-2455-fix-login --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task ship: issue SRD-2455 added to the message's first line"
  assert_eq "SRD-2455 Fix the login form" "$(git log -1 --format=%s)"
  assert_eq "Body line one." "$(git log -1 --format=%b | sed '/^$/d')"
  # The task's own message file is left as its author wrote it.
  assert_eq "Fix the login form" "$(head -n 1 msg.txt)"
}

test_task_ship_puts_a_numeric_issue_after_the_commit_subject() {
  issue_ship_setup '[0-9]+' 123-fix-login
  ship_cfg_local agent.git commit
  run jig task ship 123-fix-login --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_eq "Fix the login form (#123)" "$(git log -1 --format=%s)"
}

test_task_ship_does_not_repeat_an_issue_the_subject_names() {
  issue_ship_setup '[A-Z]+-[0-9]+' SRD-2455-fix-login
  ship_cfg_local agent.git commit
  printf 'Fix the login form for SRD-2455\n\nBody.\n' > msg.txt
  run jig task ship SRD-2455-fix-login --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "added to the message"
  assert_eq "Fix the login form for SRD-2455" "$(git log -1 --format=%s)"
}

test_task_ship_counts_only_the_issue_as_a_whole_word() {
  issue_ship_setup '[A-Z]+-[0-9]+' SRD-245-fix
  ship_cfg_local agent.git commit
  printf 'Follow up on SRD-2450\n' > msg.txt
  run jig task ship SRD-245-fix --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_eq "SRD-245 Follow up on SRD-2450" "$(git log -1 --format=%s)"
}

test_task_ship_names_the_issue_in_the_pull_request_title() {
  issue_ship_setup '[A-Z]+-[0-9]+' SRD-2455-fix-login
  ship_cfg forge github
  git add .ai/config.yaml
  ship_stub_gh ""
  ship_cfg_local agent.git pr
  run jig task ship SRD-2455-fix-login --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(cat gh-create.argv)" "$(printf -- '--title\nSRD-2455 Fix the login form')"
}

test_task_ship_names_the_issue_in_a_given_title_once() {
  issue_ship_setup '[0-9]+' 77-fix
  ship_cfg forge github
  git add .ai/config.yaml
  ship_stub_gh ""
  ship_cfg_local agent.git pr
  run jig task ship 77-fix --message-file msg.txt --title "Fix it"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(cat gh-create.argv)" "$(printf -- '--title\nFix it (#77)')"
}

test_task_ship_without_an_issue_keeps_the_subject() {
  issue_ship_setup '[A-Z]+-[0-9]+' fix-login
  ship_cfg_local agent.git commit
  run jig task ship fix-login --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_eq "Fix the login form" "$(git log -1 --format=%s)"
}

# --- task list --json (adr-20261015-a-read-is-one-json-envelope) -------------
#
# The contract: schemas/json.md describes the shape these tests pin. A field
# renamed or retyped here is a broken consumer elsewhere, so the shape is
# compared whole, not probed field by field.

# _tl_json — `jig task list --json <args>` with stdout in OUT, stderr in ERR,
# generated_at replaced by T and revision by R once their forms are checked
# (the revision's own behaviour is pinned in tests/json.t.sh).
_tl_json() {
  run_split jig task list --json "$@"
  local at rev
  at=$(printf '%s\n' "$OUT" | sed -n 's/.*"generated_at":"\([^"]*\)".*/\1/p')
  case "$at" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) fail "generated_at is not a UTC timestamp: [$at] in $OUT" ;;
  esac
  rev=$(printf '%s\n' "$OUT" | sed -n 's/^{"schema":1,"revision":\([0-9][0-9]*\),.*/\1/p')
  [ -n "$rev" ] || fail "revision is not an integer in $OUT"
  OUT=$(printf '%s\n' "$OUT" | sed -e 's/"generated_at":"[^"]*"/"generated_at":"T"/' -e 's/^{"schema":1,"revision":[0-9]*,/{"schema":1,"revision":"R",/')
}

# _tl_cut_actions — move every task's `actions` array out of OUT into ACTIONS,
# one array per line in the order the tasks came, so the facts and the actions
# are pinned by tests of their own. No reason holds a `]`.
_tl_cut_actions() {
  ACTIONS=$(printf '%s\n' "$OUT" | grep -o ',"actions":\[[^]]*\]' | sed 's/^,"actions"://')
  OUT=$(printf '%s\n' "$OUT" | sed 's/,"actions":\[[^]]*\]//g')
}

# _tl_ids — the task ids OUT lists, space-separated, in order.
_tl_ids() {
  printf '%s\n' "$OUT" | grep -o '"id":"[^"]*","class"' | sed 's/"id":"//; s/","class"$//' | paste -sd' ' -
}

test_task_list_json_pins_a_task_with_every_fact() {
  task_setup_nested
  git branch task/SRD-9-full
  git worktree add -q ../wt task/SRD-9-full
  printf 'new\n' > ../wt/new.txt
  local wt dir upd
  wt=$(cd ../wt && pwd -P)
  dir=.ai/workspace/tasks/SRD-9-full
  fixture_task SRD-9-full task/SRD-9-full active "class:T3" "issue:SRD-9" \
    "created_at:2026-10-01" "paused:true" "pr_url:https://github.com/example/example/pull/7"
  printf '# SRD-9-full\n\n## Goal\n\nShip the list\nas "data".\n\n## Scope\n\nx\n' > "$dir/task.md"
  printf 'design\n' > "$dir/design.md"
  jig task gate SRD-9-full approved >/dev/null
  printf 'autopilot: stopped\nautopilot_mode: unattended\nautopilot_repairs: 1\nautopilot_phase: spec-x/1\n' >> "$dir/state"
  printf '2026-10-02T09:00:00Z\tstart\t-\n2026-10-02T10:00:00Z\tstage\timplement\n2026-10-02T11:00:00Z\tstop\tWhich "name"?\n' > "$dir/autopilot"
  mkdir -p .ai/runtime
  {
    printf -- '--- run 2026-10-02T12:00:00Z forge=github\n'
    printf '2026-10-02T12:00:00Z task=SRD-9-full status=active remote=unknown via=forge action=preserve flags=wrong-base,STALE_CANDIDATE\n'
  } > .ai/runtime/housekeeping.log
  printf 'task/SRD-9-full\tmain\topen\tred\t2026-10-02T12:00:00Z\n' > .ai/runtime/forge-cache
  upd=$(sed -n 's/^updated_at: //p' "$dir/state")

  _tl_json
  assert_eq 0 "$RC" "$ERR"
  _tl_cut_actions
  assert_eq '[{"id":"start","command":"jig task start SRD-9-full","offered":true,"reason":null},{"id":"pause","command":"jig task pause SRD-9-full","offered":false,"reason":"task pause: already paused: SRD-9-full"},{"id":"resume","command":"jig task resume SRD-9-full","offered":true,"reason":null},{"id":"request-pause","command":"jig queue request task:SRD-9-full pause","offered":false,"reason":"queue request: task SRD-9-full is already paused"},{"id":"cancel-pause-request","command":"jig queue cancel task:SRD-9-full pause","offered":false,"reason":"queue cancel: no pause of task:SRD-9-full is requested"},{"id":"approve-gate","command":"jig task gate SRD-9-full approved","offered":false,"reason":"task gate: SRD-9-full is stopped; if a human answered, run: jig task autopilot SRD-9-full resume --answer <text> --by human; then approve with --by agent"},{"id":"answer-stop","command":"jig task autopilot SRD-9-full resume --answer <text> --by human","offered":true,"reason":null},{"id":"set-class","command":"jig task set SRD-9-full class <Tn>","offered":true,"reason":null},{"id":"ship","command":"jig task ship SRD-9-full --message-file <file>","offered":false,"reason":"task ship: agent.git is none in this clone; the human commits"},{"id":"close","command":"jig task set SRD-9-full status consolidated","offered":false,"reason":"task set: status consolidated requires knowledge_consolidated true; record the knowledge decision first: jig task set SRD-9-full knowledge_consolidated true"},{"id":"abandon","command":"jig task abandon SRD-9-full","offered":true,"reason":null},{"id":"archive","command":"jig task archive SRD-9-full","offered":true,"reason":null},{"id":"unarchive","command":"jig task unarchive SRD-9-full","offered":false,"reason":"task unarchive: task SRD-9-full is not archived"},{"id":"reopen","command":"jig task set SRD-9-full status active","offered":false,"reason":"task SRD-9-full is active, not abandoned"}]' "$ACTIONS"
  assert_eq "{\"schema\":1,\"revision\":\"R\",\"generated_at\":\"T\",\"data\":{\"tasks\":[{\"id\":\"SRD-9-full\",\"class\":\"T3\",\"status\":\"active\",\"issue\":\"SRD-9\",\"goal\":\"Ship the list as \\\"data\\\".\",\"knowledge_consolidated\":false,\"paused\":true,\"pause_request\":null,\"created_at\":\"2026-10-01\",\"updated_at\":\"$upd\",\"archived_at\":null,\"archived_reason\":null,\"archived_from\":null,\"absorbed_into\":null,\"absorbs\":[],\"absorbs_partly\":[],\"partly_in\":[],\"branch\":\"task/SRD-9-full\",\"base_branch\":\"main\",\"worktree\":{\"path\":\"$wt\",\"uncommitted\":1},\"gate\":{\"state\":\"approved\",\"by\":\"human\"},\"autopilot\":{\"state\":\"stopped\",\"mode\":\"unattended\",\"repairs\":1,\"stage\":\"implement\",\"stage_at\":\"2026-10-02T10:00:00Z\",\"stop_reason\":\"Which \\\"name\\\"?\",\"stop_at\":\"2026-10-02T11:00:00Z\",\"phase\":\"spec-x/1\"},\"pull_request\":{\"url\":\"https://github.com/example/example/pull/7\",\"state\":\"open\",\"ci\":\"red\",\"fetched_at\":\"2026-10-02T12:00:00Z\"},\"housekeeping_flags\":[\"wrong-base\",\"STALE_CANDIDATE\"]}],\"hidden\":0,\"archived\":0,\"housekeeping\":{\"ran_at\":\"2026-10-02T12:00:00Z\",\"forge\":\"github\"}}}" "$OUT"
}

test_task_list_json_says_null_for_every_fact_a_task_does_not_have() {
  task_setup
  fixture_task bare "" active "created_at:2026-10-01" "updated_at:2026-10-01"
  _tl_json
  assert_eq 0 "$RC" "$ERR"
  _tl_cut_actions
  assert_eq 14 "$(printf '%s\n' "$ACTIONS" | grep -o '{"id":' | wc -l | tr -d ' ')"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","data":{"tasks":[{"id":"bare","class":null,"status":"active","issue":null,"goal":null,"knowledge_consolidated":false,"paused":false,"pause_request":null,"created_at":"2026-10-01","updated_at":"2026-10-01","archived_at":null,"archived_reason":null,"archived_from":null,"absorbed_into":null,"absorbs":[],"absorbs_partly":[],"partly_in":[],"branch":null,"base_branch":"main","worktree":null,"gate":null,"autopilot":null,"pull_request":null,"housekeeping_flags":[]}],"hidden":0,"archived":0,"housekeeping":null}}' "$OUT"
}

test_task_list_json_with_no_tasks_is_an_empty_list() {
  task_setup
  _tl_json
  assert_eq 0 "$RC"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","data":{"tasks":[],"hidden":0,"archived":0,"housekeeping":null}}' "$OUT"
}

# Which tasks are listed is the text listing's rule, with the count of what it
# hid; --all and --status mean what they mean there. Sorted by id.
test_task_list_json_lists_the_tasks_the_text_listing_does() {
  task_setup
  fixture_task b-live "" active
  fixture_task a-ready "" ready
  fixture_task c-done "" consolidated
  fixture_task d-gone "" abandoned
  _tl_json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"hidden":2'
  assert_eq 'a-ready b-live' "$(_tl_ids)"
  _tl_json --all
  assert_contains "$OUT" '"hidden":0'
  assert_eq 'a-ready b-live c-done d-gone' "$(_tl_ids)"
  # --json may come anywhere among the arguments.
  run_split jig task list --status consolidated --json
  assert_eq 0 "$RC"
  assert_eq 'c-done' "$(_tl_ids)"
}

# A flag this disk already disproves is gone here exactly as it is gone from
# the status page (hklog_flagged_ids), and one it cannot disprove stays.
test_task_list_json_reports_the_housekeeping_flags_that_still_stand() {
  task_setup
  fixture_task closed-since task/closed-since consolidated
  fixture_task open-still task/open-still active
  mkdir -p .ai/runtime
  {
    printf -- '--- run 2026-09-01T00:00:00Z forge=github\n'
    printf '2026-09-01T00:00:00Z task=open-still status=active remote=closed via=forge action=preserve flags=abandoned?\n'
    printf -- '--- run 2026-09-25T12:00:00Z forge=failed\n'
    printf '2026-09-25T12:00:00Z task=closed-since status=active remote=merged via=forge action=preserve flags=needs-consolidation\n'
    printf '2026-09-25T12:00:00Z task=open-still status=active remote=merged via=forge action=preserve flags=needs-consolidation\n'
  } > .ai/runtime/housekeeping.log
  _tl_json --all
  assert_eq 0 "$RC"
  _tl_cut_actions
  assert_contains "$OUT" '"id":"closed-since",'
  assert_contains "$OUT" '"pull_request":null,"housekeeping_flags":[]},{"id":"open-still"'
  # Only the last run counts: the older abandoned? is not repeated.
  assert_contains "$OUT" '"housekeeping_flags":["needs-consolidation"]}]'
  assert_contains "$OUT" '"housekeeping":{"ran_at":"2026-09-25T12:00:00Z","forge":"failed"}'
}

test_task_list_json_reports_a_refusal_as_an_envelope() {
  task_setup
  _tl_json --status bogus
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":"R","generated_at":"T","error":{"code":"usage","message":"task list: invalid status: bogus"}}' "$OUT"
  assert_contains "$ERR" "jig: error: task list: invalid status: bogus"
  _tl_json --nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"usage","message":"task list: unknown argument: --nope"}}'
  _tl_json --status
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"usage","message":"task list: --status requires a value"}}'
}

test_task_list_json_in_a_project_without_jig_is_an_envelope() {
  mkdir plain
  cd plain
  git init -q
  _tl_json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"not-initialised","message":"project is not initialised; run: jig init"}}'
  assert_not_contains "$OUT" '"data"'
  # Outside git altogether, the refusal says so in its own code.
  cd ..
  mkdir bare
  cd bare
  _tl_json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"not-a-repository","message":"not inside a git repository"}}'
}

# Reading never touches the network: no forge CLI, no fetch, no ls-remote.
# A gh on PATH would leave a mark; git's own trace lists every git it ran.
test_task_list_json_never_reaches_the_network() {
  task_setup
  fixture_task t1 task/t1 active "pr_url:https://github.com/example/example/pull/7"
  git remote add origin https://example.invalid/repo.git
  mkdir -p .ai/runtime
  printf 'task/t1\tmain\topen\tpending\t2026-10-01T00:00:00Z\n' > .ai/runtime/forge-cache
  mkdir bin
  printf '#!/bin/sh\necho called >> "%s/gh.called"\nexit 1\n' "$PWD" > bin/gh
  chmod +x bin/gh
  PATH="$PWD/bin:$PATH" GIT_TRACE="$PWD/git.trace" run_split jig task list --json
  assert_eq 0 "$RC" "$ERR"
  assert_no_file gh.called
  # An old cache is reported with its time, never refreshed by the read.
  assert_contains "$OUT" '"state":"open","ci":"pending","fetched_at":"2026-10-01T00:00:00Z"'
  assert_file git.trace
  assert_not_contains "$(cat git.trace)" "fetch"
  assert_not_contains "$(cat git.trace)" "ls-remote"
  assert_not_contains "$(cat git.trace)" "remote-https"
}

# The pull request's state and checks come from the forge cache housekeeping
# wrote (lib/forgecache.sh), joined by the task's branch and base; the newest
# entry wins, an entry for another base is not the task's, and what the cache
# does not say is null — with the time it was heard when it does.
test_task_list_json_joins_the_pull_request_to_the_forge_cache() {
  task_setup
  fixture_task a-open task/a-open active "pr_url:https://github.com/example/example/pull/1"
  fixture_task b-merged task/b-merged active "pr_url:https://github.com/example/example/pull/2" "base_branch:epic/x"
  fixture_task c-unheard task/c-unheard active "pr_url:https://github.com/example/example/pull/3"
  fixture_task d-no-pr task/d-no-pr active
  mkdir -p .ai/runtime
  {
    printf '# jig forge cache\n'
    printf 'task/a-open\tmain\topen\tpending\t2026-10-15T10:00:00Z\n'
    printf 'task/a-open\tmain\tclosed\tred\t2026-10-01T10:00:00Z\n'
    printf 'task/b-merged\tmain\tclosed\t-\t2026-10-15T10:00:00Z\n'
    printf 'task/b-merged\tepic/x\tmerged\t-\t2026-10-14T10:00:00Z\n'
    printf 'task/d-no-pr\tmain\topen\tgreen\t2026-10-15T10:00:00Z\n'
  } > .ai/runtime/forge-cache
  _tl_json
  assert_eq 0 "$RC" "$ERR"
  _tl_cut_actions
  assert_contains "$OUT" '"pull_request":{"url":"https://github.com/example/example/pull/1","state":"open","ci":"pending","fetched_at":"2026-10-15T10:00:00Z"}'
  assert_contains "$OUT" '"pull_request":{"url":"https://github.com/example/example/pull/2","state":"merged","ci":null,"fetched_at":"2026-10-14T10:00:00Z"}'
  assert_contains "$OUT" '"pull_request":{"url":"https://github.com/example/example/pull/3","state":null,"ci":null,"fetched_at":null}'
  # No pull request opened: the cache does not invent one.
  assert_contains "$OUT" '"id":"d-no-pr",'
  assert_contains "$OUT" '"pull_request":null,"housekeeping_flags":[]}]'
}

# A worktree borrows the owner's task directory (ADR-0029), and so reads the
# owner's forge cache; its own housekeeping never writes one.
test_task_list_json_in_a_worktree_reads_the_owners_forge_cache() {
  task_setup_nested
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  printf 'pr_url: https://github.com/example/example/pull/9\n' >> .ai/workspace/tasks/T-1/state
  mkdir -p .ai/runtime
  printf 'task/T-1\tmain\topen\tgreen\t2026-10-15T10:00:00Z\n' > .ai/runtime/forge-cache
  OUT=$(cd "$wt" && jig task list --json 2>/dev/null)
  assert_contains "$OUT" '"pull_request":{"url":"https://github.com/example/example/pull/9","state":"open","ci":"green","fetched_at":"2026-10-15T10:00:00Z"}'

  local bin="$PWD/bin"
  mkdir -p "$bin"
  # shellcheck disable=SC2016 # the stub's own $1 and $*, expanded when it runs
  printf '#!/bin/sh\necho "$*" >> "%s/calls"\ncase "$1" in auth) exit 0 ;; esac\nprintf "task/T-1\\tmain\\tMERGED\\tabc\\n"\n' "$bin" > "$bin/gh"
  chmod +x "$bin/gh"
  sed 's/^forge:.*/forge: github/; s/^housekeeping.fetch:.*/housekeeping.fetch: false/' \
    .ai/config.yaml > "$wt/.ai/config.yaml"
  git remote add origin https://github.com/example/example.git
  (cd "$wt" && PATH="$bin:$PATH" jig housekeeping >/dev/null 2>&1) || true
  # The forge was asked, and what it said went nowhere.
  assert_contains "$(cat "$bin/calls")" "pr list"
  assert_no_file "$wt/.ai/runtime/forge-cache"
  assert_eq "$(printf 'task/T-1\tmain\topen\tgreen\t2026-10-15T10:00:00Z')" "$(cat .ai/runtime/forge-cache)"
}

# --json changes nothing for a reader of the text listing.
test_task_list_text_form_is_unchanged_beside_json() {
  task_setup
  fixture_task t1 "" active "class:T1"
  run jig task list --goals
  assert_eq 0 "$RC"
  assert_eq "$(printf 't1 class=T1 status=active not-started\n  goal: (none)')" "$OUT"
}

# The mode is the one the gates read (_task_autopilot_mode): anything but
# `unattended` — an absent key, a stray capital — is an attended run.
test_task_list_json_reports_the_autopilot_mode_the_gates_read() {
  task_setup
  fixture_task odd "" active "autopilot:on" "autopilot_mode:Unattended"
  fixture_task old "" active "autopilot:done"
  _tl_json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"id":"odd",'
  assert_not_contains "$OUT" '"mode":"Unattended"'
  assert_eq 2 "$(printf '%s\n' "$OUT" | grep -o '"mode":"attended"' | wc -l | tr -d ' ')"
}

# --- what a person may do next (adr-20261015-one-table-of-what-a-person-may-do)
#
# The actions table (_task_actions) offers an action only when its command
# accepts it on the task's state, and says why it withholds one in the words
# the command's own guard refuses with. These tests run the commands to prove
# it rather than restating the table.

# _tl_action_rows — one line per action object in OUT (a listing of one task):
# `<id><TAB><offered><TAB><command><TAB><reason>`, the reason empty for null.
# No command or reason the table writes holds a `}` or an escaped backslash.
_tl_action_rows() {
  printf '%s\n' "$OUT" \
    | grep -o '{"id":"[a-z-]*","command":"[^"]*","offered":[a-z]*,"reason":[^}]*}' \
    | awk '{
        s = $0
        sub(/^\{"id":"/, "", s); id = s; sub(/".*/, "", id); s = substr(s, length(id) + 1)
        sub(/^","command":"/, "", s); cmd = s; sub(/","offered":.*/, "", cmd); s = substr(s, length(cmd) + 1)
        sub(/^","offered":/, "", s); off = s; sub(/,.*/, "", off); s = substr(s, length(off) + 1)
        sub(/^,"reason":/, "", s); sub(/\}$/, "", s)
        if (s == "null") r = ""; else { r = substr(s, 2, length(s) - 2); gsub(/\\"/, "\"", r) }
        printf "%s\t%s\t%s\t%s\n", id, off, cmd, r
      }'
}

# _tl_agree <id> <expected-offered> — list <id> as data, check that the
# actions offered are exactly <expected-offered> (space-separated, in table
# order), then run every command: an offered one must succeed, and one a guard
# withheld must refuse with its reason. The table's own withholdings — a
# finished task, an approved design, a merged pull request — have no command
# refusal to compare and are skipped. The workspace is put back after each
# command; `start`, which moves HEAD, runs last.
_tl_agree() {
  local id="$1" want="$2" rows action offered command reason t saved msg got="" start=""
  t=$(printf '\t')
  _tl_json --all
  assert_eq 0 "$RC" "$ERR"
  rows=$(_tl_action_rows)
  assert_eq 14 "$(printf '%s\n' "$rows" | grep -c .)" "$OUT"
  saved=$(mktemp -d "${TMPDIR:-/tmp}/jig-tl-agree.XXXXXX")
  # The queue too: a pause request written by one command must not change
  # what the next is judged on.
  [ ! -f .ai/runtime/queue ] || cp .ai/runtime/queue "$saved/queue"
  msg="$saved/msg.txt"
  printf 'Ship it\n' > "$msg"
  cp -R ".ai/workspace/tasks/$id" "$saved/ws"
  while IFS="$t" read -r action offered command reason; do
    [ -n "$action" ] || continue
    [ "$offered" = false ] || got="${got:+$got }$action"
    if [ "$offered" = false ]; then
      case "$reason" in
        "task $id is "* | *"design is approved"* | *"pull request is merged"*) continue ;;
      esac
    fi
    command=$(printf '%s' "$command" | sed "s|<text>|go|; s|<Tn>|T4|; s|<file>|$msg|")
    if [ "$action" = start ] && [ "$offered" = true ]; then
      start="$command"
      continue
    fi
    set -f
    # shellcheck disable=SC2086 # the command is words, split as a person types them
    set -- $command
    set +f
    # Away from the rows this loop reads: a command must not eat them.
    run_split "$@" </dev/null
    if [ "$offered" = true ]; then
      assert_eq 0 "$RC" "$action is offered but its command refused: $ERR"
    else
      [ "$RC" -ne 0 ] || fail "$action is withheld ($reason) but its command accepted it"
      assert_contains "$ERR" "$reason"
    fi
    rm -rf ".ai/workspace/tasks/$id"
    cp -R "$saved/ws" ".ai/workspace/tasks/$id"
    rm -f .ai/runtime/queue
    [ ! -f "$saved/queue" ] || cp "$saved/queue" .ai/runtime/queue
  done <<EOF
$rows
EOF
  assert_eq "$want" "$got"
  if [ -n "$start" ]; then
    set -f
    # shellcheck disable=SC2086
    set -- $start
    set +f
    run_split "$@"
    assert_eq 0 "$RC" "start is offered but its command refused: $ERR"
  fi
  rm -rf "$saved"
}

test_task_actions_of_a_task_not_started_agree_with_their_commands() {
  task_setup_clean
  jig task new fresh >/dev/null
  _tl_agree fresh "start pause request-pause set-class abandon archive"
}

# An attended run stopped at a T3 gate, on a paused task started here: the
# person approves, answers, unpauses; the ship and the close wait for the
# knowledge decision.
test_task_actions_at_a_gate_and_a_stop_agree_with_their_commands() {
  task_setup_clean
  ship_cfg_local agent.git commit
  jig task new big --class T3 --goal "The goal." >/dev/null
  jig task start big >/dev/null
  jig task artifact write big design --from - >/dev/null <<EOF
the design
EOF
  printf 'autopilot: stopped\nautopilot_mode: attended\nautopilot_repairs: 1\npaused: true\n' >> .ai/workspace/tasks/big/state
  _tl_agree big "resume approve-gate answer-stop set-class abandon archive"
}

# A pending pause request: it can be cancelled and not asked again; a direct
# pause stays offered and takes the request with it. The task lists the
# request with its time, for the card that shows its age.
test_task_actions_of_a_pause_request_agree_with_their_commands() {
  task_setup_clean
  jig task new asked >/dev/null
  jig queue request asked pause --reason "standup" >/dev/null
  _tl_agree asked "start pause cancel-pause-request set-class abandon archive"
  local at
  at=$(awk -F '\t' '$1 == "request" { print $4 }' .ai/runtime/queue)
  _tl_json
  assert_contains "$OUT" "\"paused\":false,\"pause_request\":{\"requested_at\":\"$at\",\"reason\":\"standup\"},"
  assert_contains "$OUT" "{\"id\":\"request-pause\",\"command\":\"jig queue request task:asked pause\",\"offered\":false,\"reason\":\"queue request: a pause of task:asked is already requested, at $at\"}"
}

# Where nobody answers (autopilot.unattended), a run that spent its repairs is
# not resumed and its gate is not the person's; a task whose knowledge
# decision is recorded and that opened no pull request can be closed; a ship
# is refused for the record its route is missing.
test_task_actions_of_an_unattended_run_agree_with_their_commands() {
  task_setup_clean
  ship_cfg_local agent.git commit
  ship_cfg_local autopilot.unattended true
  jig task new run --class T3 --goal "The goal." >/dev/null
  jig task start run >/dev/null
  jig task artifact write run design --from - >/dev/null <<EOF
the design
EOF
  sed 's/^knowledge_consolidated: false/knowledge_consolidated: true/' .ai/workspace/tasks/run/state > s.tmp
  mv s.tmp .ai/workspace/tasks/run/state
  printf 'autopilot: stopped\nautopilot_mode: unattended\nautopilot_repairs: 2\n' >> .ai/workspace/tasks/run/state
  _tl_agree run "pause request-pause set-class close abandon archive"
  _tl_json --all
  assert_contains "$OUT" '"command":"jig task autopilot run resume --answer <text> --by human","offered":false,"reason":"task autopilot resume: run exhausted its unattended repair limit; ship a draft"'
  assert_contains "$OUT" '"id":"ship","command":"jig task ship run --message-file <file>","offered":false,"reason":"task ship: the route of run (T3) is missing: '
}

# A clone set to autopilot.unattended still has a person in it: a task worked
# without a run is approved by that person, and the table offers the approval
# the command records. Inside the task's unattended run the approval stays the
# agent's (adr-20261004-a-route-stage-is-proven-by-its-record).
test_task_gate_in_an_unattended_clone_without_a_run_is_the_persons() {
  task_setup_clean
  ship_cfg_local autopilot.unattended true
  jig task new big --class T3 >/dev/null
  jig task artifact write big design --from - >/dev/null <<EOF
the design
EOF
  _tl_json
  assert_contains "$OUT" '"id":"approve-gate","command":"jig task gate big approved","offered":true,"reason":null}'
  # The status says the design waits for the person, and the table offers it.
  run jig status --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"gate-waiting"'

  run jig task gate big approved --by agent
  assert_eq 1 "$RC" "an agent approved outside an unattended run"
  assert_contains "$OUT" "has no unattended autopilot run on, so the gate is the human's"

  run jig task gate big approved --by human
  assert_eq 0 "$RC" "the person could not approve in an unattended clone: $OUT"
  assert_contains "$OUT" "gate: approved"
  assert_file_contains .ai/workspace/tasks/big/state "gate_by: human"
}

test_task_gate_inside_an_unattended_run_is_still_the_agents() {
  task_setup_clean
  jig task new big --class T3 >/dev/null
  jig task artifact write big design --from - >/dev/null <<EOF
the design
EOF
  printf 'autopilot: on\nautopilot_mode: unattended\n' >> .ai/workspace/tasks/big/state
  run jig task gate big approved --by human
  assert_eq 1 "$RC" "a human approval was recorded inside an unattended run"
  assert_contains "$OUT" "big's run is unattended, so this approval is the agent's"
}

# A finished task offers nothing but reopening an abandoned one.
test_task_actions_of_finished_tasks_offer_only_reopen() {
  task_setup_clean
  fixture_task gone "" abandoned
  _tl_agree gone "archive reopen"
  rm -rf .ai/workspace/tasks/gone
  fixture_task done-1 "" consolidated
  _tl_agree done-1 ""
  _tl_json --all
  assert_contains "$OUT" '"id":"abandon","command":"jig task abandon done-1","offered":false,"reason":"task done-1 is consolidated"}'
}

# A request left on a finished task can still be taken back, and nothing else
# is offered.
test_task_actions_of_a_finished_task_with_a_pause_request_offer_its_cancel() {
  task_setup_clean
  # Asked while the task was live; it was closed before a stage came.
  fixture_task done-2 "" active
  jig queue request done-2 pause >/dev/null
  sed 's/^status: active/status: consolidated/' .ai/workspace/tasks/done-2/state > s.tmp
  mv s.tmp .ai/workspace/tasks/done-2/state
  _tl_agree done-2 "cancel-pause-request"
}

# A design approved is not offered for approval again, though the command
# would record it a second time: the table may withhold more than a command
# refuses, never less.
test_task_actions_withhold_an_approval_already_given() {
  task_setup_clean
  jig task new big --class T3 >/dev/null
  jig task artifact write big design --from - >/dev/null <<EOF
the design
EOF
  jig task gate big approved >/dev/null
  _tl_json
  assert_contains "$OUT" '"id":"approve-gate","command":"jig task gate big approved","offered":false,"reason":"task gate: big'"'"'s design is approved; nothing waits at its gate"}'
  printf 'changed\n' >> .ai/workspace/tasks/big/design.md
  _tl_json
  assert_contains "$OUT" '"id":"approve-gate","command":"jig task gate big approved","offered":true,"reason":null}'
}

# `close` is the one guard that asks the forge; the table reads the forge
# cache instead and never the forge. A cache's `merged` is final, so the
# command agrees when it asks; a cache that says `open`, or nothing, withholds
# the close in the words the command refuses with when the forge says the same.
test_task_actions_close_reads_the_forge_cache_the_command_confirms() {
  task_setup_clean
  ship_cfg forge github
  git remote add origin https://github.com/example/example.git
  fixture_task T-1 task/T-1 active "knowledge_consolidated:true" "pr_url:https://github.com/example/example/pull/7"
  mkdir -p .ai/runtime
  printf 'task/T-1\tmain\tmerged\t-\t2026-10-15T10:00:00Z\n' > .ai/runtime/forge-cache
  _tl_json
  assert_contains "$OUT" '"id":"close","command":"jig task set T-1 status consolidated","offered":true,"reason":null}'
  pr_check_stub_gh "" MERGED
  run_split jig task set T-1 status consolidated
  assert_eq 0 "$RC" "$ERR"

  fixture_task T-1 task/T-1 active "knowledge_consolidated:true" "pr_url:https://github.com/example/example/pull/7"
  printf 'task/T-1\tmain\topen\tgreen\t2026-10-15T10:00:00Z\n' > .ai/runtime/forge-cache
  _tl_json
  assert_contains "$OUT" '"id":"close","command":"jig task set T-1 status consolidated","offered":false,"reason":"task set: status consolidated requires its pull request to be merged: https://github.com/example/example/pull/7 is open; merge it, then run this again"}'
  pr_check_stub_gh "" OPEN
  run_split jig task set T-1 status consolidated
  assert_eq 1 "$RC"
  assert_contains "$ERR" "jig: error: task set: status consolidated requires its pull request to be merged: https://github.com/example/example/pull/7 is open; merge it, then run this again"

  rm -f .ai/runtime/forge-cache
  _tl_json
  assert_contains "$OUT" '"reason":"task set: status consolidated requires its pull request to be merged: https://github.com/example/example/pull/7 is unknown; merge it, then run this again"}'
  pr_check_stub_gh "" FAIL
  run_split jig task set T-1 status consolidated
  assert_contains "$ERR" "is unknown; merge it, then run this again"
}

# A ship the table offers is one `task ship` carries out.
test_task_actions_offer_a_ship_the_command_carries_out() {
  ship_setup
  ship_cfg_local agent.git commit
  task_route_done T-1
  jig task set T-1 knowledge_consolidated true >/dev/null
  ship_stage_change
  _tl_json
  assert_contains "$OUT" '"id":"ship","command":"jig task ship T-1 --message-file <file>","offered":true,"reason":null}'
  run_split jig task ship T-1 --message-file msg.txt
  assert_eq 0 "$RC" "$ERR"
  assert_eq "Ship T-1" "$(git log -1 --format=%s)"
}

# The guards the table asks never reach the network: not the close's forge
# question, not the ship's receipt check.
test_task_actions_never_reach_the_network() {
  task_setup
  ship_cfg forge github
  ship_cfg_local agent.git pr
  fixture_task t1 task/t1 active "knowledge_consolidated:true" "pr_url:https://github.com/example/example/pull/7"
  printf 'stage: review\ndiff: x\ncontext: x\ndesign: -\nfindings: -\n' > .ai/workspace/tasks/t1/receipt
  git remote add origin https://example.invalid/repo.git
  mkdir bin
  printf '#!/bin/sh\necho called >> "%s/gh.called"\nexit 1\n' "$PWD" > bin/gh
  chmod +x bin/gh
  PATH="$PWD/bin:$PATH" GIT_TRACE="$PWD/git.trace" run_split jig task list --json
  assert_eq 0 "$RC" "$ERR"
  assert_no_file gh.called
  assert_contains "$OUT" '"id":"close","command":"jig task set t1 status consolidated","offered":false,"reason":"task set: status consolidated requires its pull request to be merged: https://github.com/example/example/pull/7 is unknown; merge it, then run this again"}'
  assert_contains "$OUT" '"id":"ship","command":"jig task ship t1 --message-file <file>","offered":false,"reason":"task ship: review is stale: '
  assert_not_contains "$(cat git.trace)" "fetch"
  assert_not_contains "$(cat git.trace)" "ls-remote"
  assert_not_contains "$(cat git.trace)" "remote-https"
}

# An invalid git level withholds the ship in the words `task ship` refuses with.
test_task_actions_of_an_invalid_git_level_agree_with_their_commands() {
  task_setup_clean
  ship_cfg_local agent.git bogus
  jig task new lvl >/dev/null
  _tl_agree lvl "start pause request-pause set-class abandon archive"
  _tl_json
  assert_contains "$OUT" '"reason":"task ship: invalid agent.git: bogus (expected none|commit|push|pr|merge)"}'
}

# A read about work in another checkout is not work there: the ship row's
# receipt check runs `jig context` in the task's worktree, and that run leaves
# no checkout record behind (adr-20260924-a-checkout-records-what-is-happening-in-it).
test_task_actions_leave_no_checkout_record_in_the_tasks_worktree() {
  task_setup_nested
  ship_cfg_local agent.git commit
  jig task new x >/dev/null
  local wt before after
  wt=$(jig task start x --worktree 2>/dev/null)
  printf 'work\n' > "$wt/work.txt"
  sed 's/^knowledge_consolidated: false/knowledge_consolidated: true/' .ai/workspace/tasks/x/state > s.tmp
  mv s.tmp .ai/workspace/tasks/x/state
  printf 'stage: review\ndiff: x\ncontext: x\ndesign: -\nfindings: -\n' > .ai/workspace/tasks/x/receipt
  before=$(cd "$wt" && find .ai/runtime -type f 2>/dev/null | LC_ALL=C sort; cat .ai/runtime/checkout 2>/dev/null)
  _tl_json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"reason":"task ship: review is stale: '
  after=$(cd "$wt" && find .ai/runtime -type f 2>/dev/null | LC_ALL=C sort; cat .ai/runtime/checkout 2>/dev/null)
  assert_eq "$before" "$after"
}

# --- receipt --since-review (re-review reads what changed since the review) ---

# A task with one committed file, reviewed: the starting point of most of the
# since-review tests below.
_since_review_setup() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'one\n' > work.txt
  printf 'keep\n' > steady.txt
  git add work.txt steady.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null
}

test_task_receipt_records_the_merge_base_its_diff_was_measured_from() {
  _since_review_setup
  local mb
  mb=$(sed -n 's/^merge_base:[[:space:]]*//p' .ai/workspace/tasks/T-1/receipt)
  [ -n "$mb" ] || fail "receipt has no merge_base"
  git cat-file -e "$mb^{commit}" || fail "merge_base is not a commit: $mb"
  assert_eq "$(git merge-base HEAD "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || git for-each-ref --format='%(refname:short)' refs/heads | grep -v '^task/' | head -1)")" "$mb"
}

test_task_receipt_since_review_is_none_when_the_receipt_is_current() {
  _since_review_setup
  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC"
  assert_eq "re-review: none — the receipt is current" "$OUT"
}

test_task_receipt_since_review_is_narrow_after_editing_a_task_file() {
  _since_review_setup
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC"
  assert_contains "$OUT" "re-review: narrow (diff)"
  assert_contains "$OUT" "changed since review: 1 paths"
  assert_contains "$OUT" "diff --git a/work.txt b/work.txt"
  assert_contains "$OUT" "-one"
  assert_contains "$OUT" "+two"
  assert_not_contains "$OUT" "steady.txt"
}

test_task_receipt_since_review_includes_a_new_untracked_file() {
  _since_review_setup
  printf 'fresh\n' > added.txt

  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC"
  assert_contains "$OUT" "re-review: narrow (diff)"
  assert_contains "$OUT" "changed since review: 1 paths"
  assert_contains "$OUT" "added.txt"
  assert_contains "$OUT" "+fresh"
}

test_task_receipt_since_review_leaves_out_what_a_base_merge_brought_in() {
  _since_review_setup
  local base
  base=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -v '^task/' | head -1)
  git checkout -q "$base"
  printf 'someone else\n' > other.txt
  git add other.txt
  git commit -q -m "unrelated change on the base"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"
  assert_file other.txt
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC"
  assert_contains "$OUT" "re-review: narrow (diff)"
  assert_contains "$OUT" "changed since review: 1 paths"
  assert_contains "$OUT" "diff --git a/work.txt b/work.txt"
  assert_not_contains "$OUT" "other.txt"
}

test_task_receipt_since_review_paths_format_prints_only_paths() {
  _since_review_setup
  printf 'two\n' > work.txt
  printf 'fresh\n' > added.txt

  run jig task receipt T-1 --since-review --format paths
  assert_eq 0 "$RC"
  assert_eq "added.txt
work.txt" "$OUT"
}

test_task_receipt_since_review_paths_format_sends_none_to_stderr() {
  _since_review_setup
  local out err
  out=$(jig task receipt T-1 --since-review --format paths 2>/dev/null)
  err=$(jig task receipt T-1 --since-review --format paths 2>&1 >/dev/null)
  assert_eq "" "$out"
  assert_contains "$err" "re-review: none"
}

test_task_receipt_since_review_ledger_only_change_is_narrow_with_zero_paths() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'one\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task finding add T-1 --severity P2 --where - --summary "minor" >/dev/null
  jig task receipt T-1 --stage review >/dev/null
  jig task finding set T-1 F1 fixed >/dev/null

  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC"
  assert_contains "$OUT" "re-review: narrow (findings)"
  assert_contains "$OUT" "changed since review: 0 paths"
  assert_not_contains "$OUT" "diff --git"
}

test_task_receipt_since_review_is_full_when_the_design_changed() {
  _since_review_setup
  printf '# design v1\n' > .ai/workspace/tasks/T-1/design.md
  jig task receipt T-1 --stage review >/dev/null
  printf '# design v2\n' > .ai/workspace/tasks/T-1/design.md

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — "
}

test_task_receipt_since_review_is_full_when_the_knowledge_changed() {
  task_setup_clean
  local base
  base=$(git symbolic-ref --short HEAD)
  _task_receipt_commit_work_convention
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'one\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null

  git checkout -q "$base"
  printf 'v2\n' >> .ai/knowledge/rule-work.md
  git commit -q -am "the base rewrites the convention"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — .ai/knowledge/rule-work.md, which resolves for the task's files, changed since the review"
}

# --- re-review width from the knowledge (adr-20261029-a-global-knowledge-edit-narrows-a-re-review)

# _since_review_base_commits <shell> — run <shell> on the base branch, commit
# what it changed and merge the base into task/T-1: another task's
# consolidation arriving with a merge of main.
_since_review_base_commits() {
  local base
  base=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -v '^task/' | head -1)
  git checkout -q "$base"
  eval "$1"
  git add -A
  git commit -q -m "the base moves the knowledge"
  git checkout -q task/T-1
  git merge -q --no-edit "$base"
}

test_task_receipt_lists_the_documents_the_review_read() {
  task_setup_clean
  _task_receipt_commit_work_convention
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null
  printf 'one\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  jig task receipt T-1 --stage review >/dev/null

  local docs hash
  docs=$(sed -n 's/^context_doc:[[:space:]]*//p' .ai/workspace/tasks/T-1/receipt)
  assert_contains "$docs" ".ai/knowledge/RULES.md "
  assert_contains "$docs" ".ai/knowledge/rule-work.md "
  hash=$(printf '%s\n' "$docs" | sed -n 's|^\.ai/knowledge/RULES.md ||p')
  assert_eq "$(git hash-object --no-filters .ai/knowledge/RULES.md)" "$hash"
  git cat-file -e "$hash^{blob}" || fail "the content the review read is not stored: $hash"
}

test_task_receipt_since_review_is_narrow_when_only_a_global_document_changed() {
  _since_review_setup
  _since_review_base_commits "printf 'a rule from another task\n' >> .ai/knowledge/RULES.md"

  run jig task receipt T-1 --check
  assert_eq 1 "$RC" "a global edit still stales the receipt: $OUT"

  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "re-review: narrow (context)"
  assert_contains "$OUT" "changed since review: 0 paths"
  assert_contains "$OUT" "knowledge changed since review: 1 documents"
  assert_contains "$OUT" "knowledge: .ai/knowledge/RULES.md"
  assert_contains "$OUT" "+a rule from another task"
}

test_task_receipt_since_review_is_narrow_with_the_task_diff_and_a_global_edit() {
  _since_review_setup
  _since_review_base_commits "printf 'more architecture\n' >> .ai/knowledge/ARCHITECTURE.md"
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "re-review: narrow (diff, context)"
  assert_contains "$OUT" "diff --git a/work.txt b/work.txt"
  assert_contains "$OUT" "knowledge: .ai/knowledge/ARCHITECTURE.md"
  assert_contains "$OUT" "+more architecture"
}

test_task_receipt_since_review_ignores_a_new_adr_for_other_files() {
  _since_review_setup
  _since_review_base_commits "mkdir -p .ai/knowledge/adr
cat > .ai/knowledge/adr/20260101-elsewhere.md <<'EOF2'
---
id: adr-20260101-elsewhere
type: adr
status: accepted
paths:
  - elsewhere/**
summary: Not about the task's files.
---
# Elsewhere
EOF2
printf 'the closing route\n' >> .ai/knowledge/ARCHITECTURE.md"

  run jig task receipt T-1 --since-review
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "re-review: narrow (context)"
  assert_contains "$OUT" "knowledge changed since review: 1 documents"
  assert_not_contains "$OUT" "elsewhere"
}

test_task_receipt_since_review_is_full_when_a_document_newly_resolves() {
  _since_review_setup
  _since_review_base_commits "cat > .ai/knowledge/rule-work.md <<'EOF2'
---
id: rule-work
type: convention
status: accepted
paths:
  - work.txt
summary: Work files follow this.
---
# Work files
EOF2"

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — a document resolves for the task's files that did not at the review, or no longer does: .ai/knowledge/rule-work.md"
}

test_task_receipt_since_review_is_full_for_a_receipt_without_its_documents() {
  _since_review_setup
  sed '/^context_doc:/d' .ai/workspace/tasks/T-1/receipt > receipt.tmp
  cp receipt.tmp .ai/workspace/tasks/T-1/receipt
  rm -f receipt.tmp
  _since_review_base_commits "printf 'a rule\n' >> .ai/knowledge/RULES.md"

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the receipt does not list which documents it read"
}

test_task_receipt_since_review_paths_format_leaves_the_knowledge_out() {
  _since_review_setup
  _since_review_base_commits "printf 'a rule\n' >> .ai/knowledge/RULES.md"
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review --format paths
  assert_eq 0 "$RC"
  assert_eq "work.txt" "$OUT"
}

test_task_receipt_since_review_is_full_for_a_legacy_tree_receipt() {
  _since_review_setup
  grep -v '^diff:' .ai/workspace/tasks/T-1/receipt > receipt.tmp
  cp receipt.tmp .ai/workspace/tasks/T-1/receipt
  rm -f receipt.tmp
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — the receipt predates the task's own diff"
}

test_task_receipt_since_review_is_full_without_a_receipt() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — "
}

test_task_receipt_since_review_is_full_for_a_receipt_without_merge_base() {
  _since_review_setup
  sed '/^merge_base:/d' .ai/workspace/tasks/T-1/receipt > receipt.tmp
  cp receipt.tmp .ai/workspace/tasks/T-1/receipt
  rm -f receipt.tmp
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — "
}

test_task_receipt_since_review_is_full_for_an_empty_merge_base() {
  _since_review_setup
  sed 's/^merge_base:.*/merge_base: /' .ai/workspace/tasks/T-1/receipt > receipt.tmp
  cp receipt.tmp .ai/workspace/tasks/T-1/receipt
  rm -f receipt.tmp
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — "
}

test_task_receipt_since_review_is_full_when_the_receipt_tree_is_unreadable() {
  _since_review_setup
  sed 's/^tree:.*/tree: 0000000000000000000000000000000000000001/' .ai/workspace/tasks/T-1/receipt > receipt.tmp
  cp receipt.tmp .ai/workspace/tasks/T-1/receipt
  rm -f receipt.tmp
  printf 'two\n' > work.txt

  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — "
}

test_task_receipt_since_review_full_in_paths_format_goes_to_stderr() {
  task_setup_clean
  jig task new T-1 --class T2 >/dev/null
  jig task start T-1 >/dev/null

  local out err
  out=$(jig task receipt T-1 --since-review --format paths 2>/dev/null) && fail "expected exit 1"
  err=$(jig task receipt T-1 --since-review --format paths 2>&1 >/dev/null) || true
  assert_eq "" "$out"
  assert_contains "$err" "re-review: full — "
}

test_task_receipt_since_review_is_full_when_the_branch_is_checked_out_nowhere() {
  _since_review_setup
  git checkout -q main
  run jig task receipt T-1 --since-review
  assert_eq 1 "$RC"
  assert_contains "$OUT" "re-review: full — "
}

test_task_receipt_since_review_with_stage_dies() {
  _since_review_setup
  run jig task receipt T-1 --since-review --stage review
  [ "$RC" -ne 0 ] || fail "expected a non-zero exit"
  assert_contains "$OUT" "--since-review takes no --stage or --check"
}

test_task_receipt_since_review_with_check_dies() {
  _since_review_setup
  run jig task receipt T-1 --since-review --check
  [ "$RC" -ne 0 ] || fail "expected a non-zero exit"
  assert_contains "$OUT" "--since-review takes no --stage or --check"
}

test_task_receipt_format_without_since_review_dies() {
  _since_review_setup
  run jig task receipt T-1 --check --format paths
  [ "$RC" -ne 0 ] || fail "expected a non-zero exit"
  assert_contains "$OUT" "--format goes with --since-review"
}

# --- archive (adr-20261027-a-task-nobody-finished-is-archived-not-purged) ----

# _ta_get <id> <key> — a task's state value, read from the file.
_ta_get() {
  sed -n "s/^$2: //p" ".ai/workspace/tasks/$1/state" | head -n 1
}

test_task_archive_keeps_the_workspace_and_records_why() {
  task_setup_clean
  fixture_task old-1 "" active "updated_at:2026-01-01"
  jig task archive old-1 >/dev/null
  assert_eq archived "$(_ta_get old-1 status)"
  assert_eq manual "$(_ta_get old-1 archived_reason)"
  assert_eq active "$(_ta_get old-1 archived_from)"
  assert_eq "$(date +%Y-%m-%d)" "$(_ta_get old-1 archived_at)"
  assert_file .ai/workspace/tasks/old-1/state
}

test_task_unarchive_returns_the_status_it_had_and_refreshes_updated_at() {
  task_setup_clean
  local from
  for from in active ready abandoned; do
    fixture_task "from-$from" "" "$from" "updated_at:2026-01-01"
    jig task archive "from-$from" >/dev/null
    assert_eq "$from" "$(_ta_get "from-$from" archived_from)"
    jig task unarchive "from-$from" >/dev/null
    assert_eq "$from" "$(_ta_get "from-$from" status)"
    assert_eq "" "$(_ta_get "from-$from" archived_at)"
    assert_eq "" "$(_ta_get "from-$from" archived_reason)"
    assert_eq "" "$(_ta_get "from-$from" archived_from)"
    assert_eq "$(date +%Y-%m-%d)" "$(_ta_get "from-$from" updated_at)"
  done
}

test_task_archive_refusals() {
  task_setup_clean
  fixture_task done-1 "" consolidated
  run jig task archive done-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task archive: task done-1 is consolidated"
  fixture_task old-1 "" active
  jig task archive old-1 >/dev/null
  run jig task archive old-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already archived"
  fixture_task live-1 "" active
  run jig task unarchive live-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task unarchive: task live-1 is not archived"
  run jig task archive
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task archive <id>"
  run jig task unarchive
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task unarchive <id>"
}

test_task_set_cannot_write_or_move_an_archive() {
  task_setup_clean
  fixture_task live-1 "" active
  run jig task set live-1 status archived
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig task archive live-1"
  assert_eq active "$(_ta_get live-1 status)"
  local key
  for key in archived_at archived_reason archived_from; do
    run jig task set live-1 "$key" x
    assert_eq 1 "$RC" "$key"
  done
  jig task archive live-1 >/dev/null
  run jig task set live-1 status active
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig task unarchive live-1"
  run jig task abandon live-1
  assert_eq 1 "$RC"
  assert_eq archived "$(_ta_get live-1 status)"
}

test_task_list_hides_the_archive_and_points_at_it() {
  task_setup_clean
  fixture_task live-1 "" active
  fixture_task old-1 "" active
  fixture_task gone-1 "" abandoned
  jig task archive old-1 >/dev/null
  run jig task list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "live-1"
  assert_not_contains "$OUT" "old-1"
  assert_contains "$OUT" "(1 finished; jig task list --all)"
  assert_contains "$OUT" "archived: 1 (jig task list --status archived)"
  run jig task list --status archived
  assert_eq 0 "$RC"
  assert_contains "$OUT" "old-1 class="
  assert_contains "$OUT" "status=archived"
  assert_contains "$OUT" "archived_at=$(date +%Y-%m-%d) archived_reason=manual"
  assert_not_contains "$OUT" "live-1"
  # Only the archive exists: the listing still says so.
  rm -rf .ai/workspace/tasks/live-1 .ai/workspace/tasks/gone-1
  run jig task list
  assert_contains "$OUT" "no live tasks"
  assert_contains "$OUT" "archived: 1 (jig task list --status archived)"
}

test_task_list_json_carries_the_archive() {
  task_setup_clean
  fixture_task live-1 "" active
  fixture_task gone-1 "" abandoned
  fixture_task old-1 "" ready
  jig task archive old-1 >/dev/null
  _tl_json
  assert_eq 0 "$RC" "$ERR"
  # hidden is every task left out; archived is the part of it in the archive.
  assert_contains "$OUT" '"hidden":2,"archived":1,'
  assert_eq 'live-1' "$(_tl_ids)"
  assert_contains "$OUT" '"archived_at":null,"archived_reason":null,"archived_from":null'
  _tl_json --status archived
  assert_eq 'old-1' "$(_tl_ids)"
  assert_contains "$OUT" '"status":"archived"'
  assert_contains "$OUT" "\"archived_at\":\"$(date +%Y-%m-%d)\",\"archived_reason\":\"manual\",\"archived_from\":\"ready\""
  _tl_json --all
  assert_contains "$OUT" '"hidden":0,"archived":0,'
}

test_task_actions_of_an_archived_task_offer_only_unarchive() {
  task_setup_clean
  fixture_task old-1 "" active
  jig task archive old-1 >/dev/null
  _tl_agree old-1 "unarchive"
}

test_task_actions_of_an_archived_task_with_a_pause_request_offer_its_cancel() {
  task_setup_clean
  fixture_task old-2 "" active
  jig queue request old-2 pause >/dev/null
  jig task archive old-2 >/dev/null
  _tl_agree old-2 "cancel-pause-request unarchive"
}

# --- merge (adr-20261027-an-absorbed-task-is-archived-with-its-receiver) -------

# _tm_pair — two live tasks with a document each; `from` has a goal.
_tm_pair() {
  task_setup_clean
  jig task new from-1 --class T1 --goal "Do the from work" >/dev/null
  jig task new to-1 --class T1 --goal "Do the to work" >/dev/null
  printf 'analysis of from\n' > .ai/workspace/tasks/from-1/analysis.md
}

test_task_merge_whole_copies_documents_records_both_ends_and_archives() {
  _tm_pair
  run jig task merge from-1 --into to-1
  assert_eq 0 "$RC" "$OUT"
  assert_eq "task merge: from-1 absorbed into to-1; from-1 is archived" "$OUT"
  assert_file .ai/workspace/tasks/to-1/absorbed/from-1/analysis.md
  assert_file .ai/workspace/tasks/to-1/absorbed/from-1/task.md
  assert_eq "analysis of from" "$(cat .ai/workspace/tasks/to-1/absorbed/from-1/analysis.md)"
  assert_contains "$(cat .ai/workspace/tasks/to-1/task.md)" "## Absorbed: from-1 (whole)"
  assert_contains "$(cat .ai/workspace/tasks/to-1/task.md)" "Do the from work"
  assert_contains "$(cat .ai/workspace/tasks/to-1/task.md)" "Its documents: absorbed/from-1/."
  assert_eq "from-1" "$(_ta_get to-1 absorbs)"
  assert_eq "to-1" "$(_ta_get from-1 absorbed_into)"
  assert_eq archived "$(_ta_get from-1 status)"
  assert_eq absorbed "$(_ta_get from-1 archived_reason)"
  assert_eq active "$(_ta_get from-1 archived_from)"
  assert_eq active "$(_ta_get to-1 status)"
}

test_task_merge_keeps_what_the_absorbed_task_itself_absorbed() {
  _tm_pair
  jig task new deep-1 --goal "Deep" >/dev/null
  printf 'deep doc\n' > .ai/workspace/tasks/deep-1/notes.md
  jig task merge deep-1 --into from-1 >/dev/null
  jig task merge from-1 --into to-1 >/dev/null
  assert_file .ai/workspace/tasks/to-1/absorbed/from-1/absorbed/deep-1/notes.md
}

test_task_merge_adds_each_absorbed_task_to_the_list_once() {
  _tm_pair
  jig task new more-1 >/dev/null
  jig task merge from-1 --into to-1 >/dev/null
  jig task merge more-1 --into to-1 >/dev/null
  assert_eq "from-1,more-1" "$(_ta_get to-1 absorbs)"
}

test_task_merge_partial_leaves_the_source_live() {
  _tm_pair
  run jig task merge from-1 --into to-1 --partial
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "to-1 takes part of from-1; from-1 stays open"
  assert_eq active "$(_ta_get from-1 status)"
  assert_eq "to-1" "$(_ta_get from-1 partly_in)"
  assert_eq "from-1" "$(_ta_get to-1 absorbs_partly)"
  assert_eq "" "$(_ta_get to-1 absorbs)"
  assert_eq "" "$(_ta_get from-1 absorbed_into)"
  assert_file .ai/workspace/tasks/to-1/absorbed/from-1/analysis.md
  assert_contains "$(cat .ai/workspace/tasks/to-1/task.md)" "## Absorbed: from-1 (partly)"
  assert_contains "$(cat .ai/workspace/tasks/from-1/task.md)" "## Partly in to-1"
}

test_task_merge_partial_can_be_repeated() {
  _tm_pair
  jig task merge from-1 --into to-1 --partial >/dev/null
  printf 'more\n' > .ai/workspace/tasks/from-1/design.md
  run jig task merge from-1 --into to-1 --partial
  assert_eq 0 "$RC" "$OUT"
  assert_file .ai/workspace/tasks/to-1/absorbed/from-1/design.md
  assert_eq "from-1" "$(_ta_get to-1 absorbs_partly)"
}

test_task_merge_accepts_an_abandoned_source_and_a_ready_receiver() {
  _tm_pair
  jig task abandon from-1 >/dev/null
  fixture_task ready-1 "" ready
  run jig task merge from-1 --into ready-1
  assert_eq 0 "$RC" "$OUT"
  assert_eq abandoned "$(_ta_get from-1 archived_from)"
}

test_task_merge_refusals() {
  _tm_pair
  fixture_task done-1 "" consolidated
  fixture_task gone-1 "" abandoned
  fixture_task old-1 "" active
  jig task archive old-1 >/dev/null

  run jig task merge from-1 --into from-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "a task cannot absorb itself"

  run jig task merge from-1 --into done-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task done-1 is consolidated; only a live task absorbs another"
  run jig task merge from-1 --into old-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task old-1 is archived"
  run jig task merge from-1 --into gone-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task gone-1 is abandoned"

  run jig task merge done-1 --into to-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task done-1 is consolidated; only an unfinished task is absorbed"
  run jig task merge old-1 --into to-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task old-1 is archived; only an unfinished task is absorbed"

  run jig task merge from-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task merge <from> --into <to> [--partial]"
  run jig task merge from-1 --into
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--into requires a value"
  run jig task merge from-1 --into to-1 --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument: --bogus"
  run jig task merge
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig task merge"

  # Nothing was written by any of the refusals.
  assert_eq active "$(_ta_get from-1 status)"
  assert_eq "" "$(_ta_get to-1 absorbs)"
  assert_no_file .ai/workspace/tasks/to-1/absorbed
}

test_task_merge_a_second_whole_merge_of_the_same_task_refreshes_the_copy() {
  _tm_pair
  jig task merge from-1 --into to-1 >/dev/null
  jig task unarchive from-1 >/dev/null
  printf 'newer analysis\n' > .ai/workspace/tasks/from-1/analysis.md
  run jig task merge from-1 --into to-1
  assert_eq 0 "$RC" "$OUT"
  assert_eq archived "$(_ta_get from-1 status)"
  assert_eq "to-1" "$(_ta_get from-1 absorbed_into)"
  assert_eq "from-1" "$(_ta_get to-1 absorbs)"
  assert_eq "newer analysis" "$(cat .ai/workspace/tasks/to-1/absorbed/from-1/analysis.md)"
}

test_task_merge_is_not_blocked_by_a_leftover_copy() {
  _tm_pair
  mkdir -p .ai/workspace/tasks/to-1/absorbed/from-1
  printf 'stale\n' > .ai/workspace/tasks/to-1/absorbed/from-1/analysis.md
  run jig task merge from-1 --into to-1
  assert_eq 0 "$RC" "$OUT"
  assert_eq "analysis of from" "$(cat .ai/workspace/tasks/to-1/absorbed/from-1/analysis.md)"
  assert_eq archived "$(_ta_get from-1 status)"
}

test_task_merge_refuses_when_absorbed_is_a_link() {
  skip_unless_symlinks
  _tm_pair
  fixture_task dep-1 "" active
  jig queue depend dep-1 --on from-1 --reason "needs from" >/dev/null
  local before
  before=$(cat .ai/runtime/queue)
  mkdir -p "outside-dir/elsewhere"
  ln -s "$PWD/outside-dir/elsewhere" .ai/workspace/tasks/to-1/absorbed
  run jig task merge from-1 --into to-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is a link; remove it first"
  assert_eq active "$(_ta_get from-1 status)"
  assert_eq "" "$(_ta_get to-1 absorbs)"
  assert_eq "$before" "$(cat .ai/runtime/queue)"
  assert_eq "" "$(ls "outside-dir/elsewhere")"
}

test_task_merge_refuses_when_the_destination_is_a_link() {
  skip_unless_symlinks
  _tm_pair
  fixture_task dep-1 "" active
  jig queue depend dep-1 --on from-1 --reason "needs from" >/dev/null
  local before
  before=$(cat .ai/runtime/queue)
  mkdir -p "outside-dir/elsewhere" .ai/workspace/tasks/to-1/absorbed
  ln -s "$PWD/outside-dir/elsewhere" .ai/workspace/tasks/to-1/absorbed/from-1
  run jig task merge from-1 --into to-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is a link; remove it first"
  assert_eq active "$(_ta_get from-1 status)"
  assert_eq "$before" "$(cat .ai/runtime/queue)"
  assert_eq "" "$(ls "outside-dir/elsewhere")"
}

test_task_merge_leaves_links_in_the_sources_absorbed_tree_behind() {
  skip_unless_symlinks
  _tm_pair
  mkdir -p .ai/workspace/tasks/from-1/absorbed/old-1/sub "outside-dir/outside"
  printf 'old doc\n' > .ai/workspace/tasks/from-1/absorbed/old-1/analysis.md
  printf 'deep\n' > .ai/workspace/tasks/from-1/absorbed/old-1/sub/deep.md
  printf 'secret\n' > "outside-dir/outside/secret.md"
  ln -s "$PWD/outside-dir/outside/secret.md" .ai/workspace/tasks/from-1/absorbed/old-1/link.md
  ln -s "$PWD/outside-dir/outside" .ai/workspace/tasks/from-1/absorbed/old-1/linkdir
  run jig task merge from-1 --into to-1
  assert_eq 0 "$RC" "$OUT"
  local d=.ai/workspace/tasks/to-1/absorbed/from-1/absorbed/old-1
  assert_eq "old doc" "$(cat $d/analysis.md)"
  assert_eq "deep" "$(cat $d/sub/deep.md)"
  [ ! -e "$d/link.md" ] && [ ! -L "$d/link.md" ] || fail "a file link was copied"
  [ ! -e "$d/linkdir" ] && [ ! -L "$d/linkdir" ] || fail "a directory link was copied"
}

test_task_merge_of_an_unknown_task_fails() {
  _tm_pair
  run jig task merge nope --into to-1
  assert_eq 1 "$RC"
  run jig task merge from-1 --into nope
  assert_eq 1 "$RC"
}

test_task_set_refuses_the_merge_keys() {
  task_setup_clean
  fixture_task live-1 "" active
  local key
  for key in absorbed_into absorbs partly_in absorbs_partly; do
    run jig task set live-1 "$key" x
    assert_eq 1 "$RC" "$key"
    assert_contains "$OUT" "key is not writable: $key"
  done
}

test_task_unarchive_after_a_whole_merge_restores_the_source_and_keeps_the_receivers_record() {
  _tm_pair
  jig task merge from-1 --into to-1 >/dev/null
  jig task unarchive from-1 >/dev/null
  assert_eq active "$(_ta_get from-1 status)"
  assert_eq "" "$(_ta_get from-1 absorbed_into)"
  assert_eq "" "$(_ta_get from-1 archived_reason)"
  assert_eq "from-1" "$(_ta_get to-1 absorbs)"
}

test_task_list_names_the_merge_links() {
  _tm_pair
  jig task new part-1 >/dev/null
  jig task merge from-1 --into to-1 >/dev/null
  jig task merge part-1 --into to-1 --partial >/dev/null
  run jig task list --status archived
  assert_contains "$OUT" "from-1 class="
  assert_contains "$OUT" " absorbed_into=to-1"
  run jig task list
  assert_contains "$OUT" " absorbs=from-1"
  assert_contains "$OUT" " absorbs_partly=part-1"
  assert_contains "$OUT" " partly_in=to-1"
}

test_task_list_json_carries_the_merge_links() {
  _tm_pair
  jig task new part-1 >/dev/null
  jig task merge from-1 --into to-1 >/dev/null
  jig task merge part-1 --into to-1 --partial >/dev/null
  jig task new more-1 >/dev/null
  jig task merge more-1 --into to-1 >/dev/null
  _tl_json --all
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"absorbed_into":"to-1","absorbs":[],"absorbs_partly":[],"partly_in":[]'
  assert_contains "$OUT" '"absorbed_into":null,"absorbs":["from-1","more-1"],"absorbs_partly":["part-1"],"partly_in":[]'
  assert_contains "$OUT" '"absorbed_into":null,"absorbs":[],"absorbs_partly":[],"partly_in":["to-1"]'
}

# --- what a listing costs per task -------------------------------------------
#
# `task list --json` once started ~150 processes per task — a `$(...)` and an
# awk for every field of `state`, the queue read twice, the config once per
# key — and took 12 s on a project of 41 tasks. What these tests hold is the
# shape that fixed it: a fixed number of processes per task, whatever fields
# the task has. They count processes, not seconds: a time threshold is noise
# in CI, on Windows above all.

# _tl_forks <jig args> — run jig with them and print how many processes it
# started: every new subshell (a `$(...)`, a `( )`) and every external
# program. A DEBUG trap, inherited by functions and subshells (`set -T`) and
# installed through BASH_ENV, notes a subshell by a BASH_SUBSHELL its shell did
# not have before and an external program by `type -P`. The elements of a
# pipeline go uncounted in bash 3.2; a fork per task would still show.
_tl_forks() {
  local probe="$JIG_TEST_TMP.forkprobe" log="$JIG_TEST_TMP.forks"
  cat > "$probe" <<'PROBE'
set -T
_tlf_level=$BASH_SUBSHELL
# Builtins and keywords, listed before the trap is set; a word in neither, and
# no function, that PATH finds is an external program. Nothing is written to
# a file but the log: pipeline elements run at once, and a shared scratch file
# answered one of them with another's word.
_tlf_names=" $(compgen -b | tr '\n' ' ') $(compgen -k | tr '\n' ' ') "
_tlf_trap() {
  local word glob=0
  if [ "$_tlf_level" != "$BASH_SUBSHELL" ]; then
    _tlf_level=$BASH_SUBSHELL
    printf 'S\n' >> "$TLF_LOG"
  fi
  case $- in *f*) ;; *) glob=1; set -f ;; esac
  # shellcheck disable=SC2086 # split into words on purpose
  set -- $BASH_COMMAND
  [ "$glob" = 0 ] || set +f
  while :; do case "${1-}" in [A-Za-z_]*=*) shift ;; *) break ;; esac; done
  word=${1-}
  case "$word" in '' | *[\"\'\$\`\(\)\[\]\{\}\;\<\>\|\&]*) return 0 ;; esac
  case "$_tlf_names" in *" $word "*) return 0 ;; esac
  declare -F -- "$word" >/dev/null && return 0
  type -P -- "$word" >/dev/null 2>&1 || return 0
  printf 'E %s\n' "$word" >> "$TLF_LOG"
  return 0
}
trap '_tlf_trap' DEBUG
PROBE
  : > "$log"
  TLF_LOG="$log" BASH_ENV="$probe" "$JIG_BIN" "$@" >/dev/null 2>&1 || return 1
  wc -l < "$log" | tr -d ' '
}

# _tl_same_cost <few> <many> — fail unless 4 tasks with many fields started
# as many processes as 4 with few. One either way is allowed: what a run does
# once (a revision claimed, a record written) need not land in the same run.
_tl_same_cost() {
  local d=$(($2 - $1))
  [ "$d" -ge -1 ] && [ "$d" -le 1 ] \
    || fail "processes for 4 tasks with many fields ($2) differ from 4 with few ($1)"
}

# _tl_live_tasks <prefix> <n> [key:value ...] — <n> live tasks, filed and not
# started, with the extra state lines given.
_tl_live_tasks() {
  local prefix="$1" n="$2" i=1
  shift 2
  while [ "$i" -le "$n" ]; do
    fixture_task "$prefix-$i" "" active "class:T2" "$@"
    i=$((i + 1))
  done
}

test_task_list_json_starts_a_fixed_number_of_processes_per_task() {
  task_setup
  local two six ten few many
  _tl_live_tasks lean 2
  # The first run sets up what every later run finds made (runtime records,
  # the revision): counted, it would be read as a cost of the tasks.
  _tl_forks task list --all --json >/dev/null || fail "task list --json failed under the probe"
  two=$(_tl_forks task list --all --json) || fail "task list --json failed under the probe"
  _tl_live_tasks more 4
  six=$(_tl_forks task list --all --json) || fail "task list --json failed under the probe"
  # The same tasks with every list field and a dozen more keys in state:
  # what they cost must be what the bare ones cost.
  _tl_live_tasks rich 4 "issue:X-1" "absorbs:a,b" "absorbs_partly:c" "partly_in:d" \
    "gate_by:human" "autopilot_phase:s/1" "route_depth:lean" "domains:task" \
    "paused_reason:none" "triage_task:t" "share:vendor" "setup:ok"
  ten=$(_tl_forks task list --all --json) || fail "task list --json failed under the probe"
  few=$((six - two))
  many=$((ten - six))
  _tl_same_cost "$few" "$many"
  # None per task: the listing forks for none of these tasks, so a process
  # per task is a regression (one allowed for a once-per-run record).
  [ "$few" -le 1 ] || fail "4 more tasks started $few more processes (2 tasks: $two, 6: $six)"
}

test_status_json_starts_a_fixed_number_of_processes_per_task() {
  task_setup
  local two six ten few many
  _tl_live_tasks lean 2
  # The first run sets up what every later run finds made (runtime records,
  # the revision): counted, it would be read as a cost of the tasks.
  _tl_forks status --json >/dev/null || fail "status --json failed under the probe"
  two=$(_tl_forks status --json) || fail "status --json failed under the probe"
  _tl_live_tasks more 4
  six=$(_tl_forks status --json) || fail "status --json failed under the probe"
  _tl_live_tasks rich 4 "issue:X-1" "absorbs:a,b" "partly_in:d" "gate_by:human" \
    "route_depth:lean" "domains:task" "paused_reason:none" "setup:ok"
  ten=$(_tl_forks status --json) || fail "status --json failed under the probe"
  few=$((six - two))
  many=$((ten - six))
  _tl_same_cost "$few" "$many"
  # One per live task, the receipt line (task_receipt_check), and one more
  # allowed for a once-per-run record.
  [ "$few" -le 5 ] || fail "4 more tasks started $few more processes (2 tasks: $two, 6: $six)"
}

# _ts_lib — run the rest of the arguments as a script with the libraries a
# listing uses sourced, in this project.
_ts_lib() {
  bash -c '
    set -eu
    JIG_LIB="$JIG_HOME/scripts/lib"
    . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"; . "$JIG_LIB/task.sh"
    JIG_PROJECT=$(pwd -P)
    eval "$1"
  ' _ "$1"
}

# The snapshot a read path holds never hides a write: every writer of a state
# file drops it, so the next read sees the new value.
test_task_state_snapshot_sees_a_write_made_after_it_was_loaded() {
  task_setup
  fixture_task snap "" active "class:T1"
  local got
  # shellcheck disable=SC2016 # the script expands in _ts_lib's shell
  got=$(_ts_lib '
    dir="$JIG_PROJECT/.ai/workspace/tasks/snap"
    jig_read_snapshot_begin
    task_state_var v snap status; printf "%s\n" "$v"
    _task_rewrite_state "$dir" status ready
    task_state_var v snap status; printf "%s\n" "$v"
    _task_rewrite_state_remove "$dir" class
    task_state_var v snap class; printf "[%s] %s\n" "$v" "$_JIG_TS_FOUND"
    jig_read_snapshot_end
    task_state_get snap status
  ')
  assert_eq "$(printf 'active\nready\n[] 0\nready')" "$got"
}

# One rule reads `state`, with or without the snapshot: the first `<key>:`
# line, the value after the colon without its leading blanks — what the awk
# this reader replaced printed, which the test asks too.
test_task_state_reader_keeps_the_one_rule_of_the_format() {
  task_setup
  local dir=.ai/workspace/tasks/fmt key want plain snap
  mkdir -p "$dir"
  printf 'task_id: fmt\nclass:\t  T3\nclass: T1\nclass_lowered_from: T4\nempty:\nweird-key: w v \nspaced:   a  b  \nlast: no newline' > "$dir/state"
  for key in task_id class class_lowered_from empty weird-key spaced last missing clas; do
    want=$(awk -v k="$key:" 'index($0, k) == 1 { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "$dir/state")
    plain=$(_ts_lib "task_state_get fmt '$key'")
    snap=$(_ts_lib "jig_read_snapshot_begin; task_state_get fmt '$key'")
    assert_eq "[$want]" "[$plain]" "task_state_get fmt $key"
    assert_eq "[$want]" "[$snap]" "task_state_get fmt $key, from the snapshot"
  done
}

test_task_merge_writes_no_queue_file_when_there_is_none() {
  _tm_pair
  jig task merge from-1 --into to-1 >/dev/null
  assert_no_file .ai/runtime/queue
}

test_task_usage_names_merge() {
  run jig task
  assert_contains "$OUT" "unarchive|merge|pause"
  run jig task merge --help
  assert_contains "$OUT" "usage: jig task merge <from> --into <to> [--partial]"
}

# _tm_ship_absorbed <issue> — the issue-named receiver SRD-1-main, set up for a
# ship, with an absorbed task carrying <issue>.
_tm_ship_absorbed() {
  issue_ship_setup '[A-Z]+-[0-9]+' SRD-1-main
  fixture_task SRD-7-other "" active "issue:$1"
  jig task merge SRD-7-other --into SRD-1-main >/dev/null
}

test_task_ship_names_the_absorbed_issues_in_the_commit() {
  _tm_ship_absorbed SRD-7
  ship_cfg_local agent.git commit
  run jig task ship SRD-1-main --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "absorbed issues named: SRD-7"
  assert_eq "Absorbs: SRD-7" "$(git log -1 --format=%b | sed '/^$/d' | tail -n 1)"
  # The task's own message file is left as written.
  assert_not_contains "$(cat msg.txt)" "Absorbs:"
}

test_task_ship_names_a_numeric_absorbed_issue_with_a_hash() {
  _tm_ship_absorbed 45
  ship_cfg_local agent.git commit
  run jig task ship SRD-1-main --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_eq "Absorbs: #45" "$(git log -1 --format=%b | sed '/^$/d' | tail -n 1)"
}

test_task_ship_does_not_repeat_an_absorbs_line() {
  _tm_ship_absorbed SRD-7
  ship_cfg_local agent.git commit
  printf 'Fix the login form\n\nBody.\n\nAbsorbs: SRD-7\n' > msg.txt
  run jig task ship SRD-1-main --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "absorbed issues named"
  assert_eq 1 "$(git log -1 --format=%b | grep -c '^Absorbs: ')"
}

test_task_ship_names_the_partly_absorbed_issues_and_skips_tasks_without_one() {
  issue_ship_setup '[A-Z]+-[0-9]+' SRD-1-main
  fixture_task SRD-7-other "" active "issue:SRD-7"
  fixture_task plain-1 "" active
  jig task merge SRD-7-other --into SRD-1-main --partial >/dev/null
  jig task merge plain-1 --into SRD-1-main >/dev/null
  ship_cfg_local agent.git commit
  run jig task ship SRD-1-main --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_eq "Absorbs: SRD-7" "$(git log -1 --format=%b | sed '/^$/d' | tail -n 1)"
}

test_task_ship_without_absorbed_issues_adds_no_line() {
  issue_ship_setup '[A-Z]+-[0-9]+' SRD-1-main
  fixture_task plain-1 "" active
  jig task merge plain-1 --into SRD-1-main >/dev/null
  ship_cfg_local agent.git commit
  run jig task ship SRD-1-main --message-file msg.txt
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$(git log -1 --format=%B)" "Absorbs:"
}

test_task_ship_names_the_absorbed_issues_in_the_pull_request_body() {
  _tm_ship_absorbed SRD-7
  ship_cfg forge github
  git add .ai/config.yaml
  mship_stub_gh
  ship_cfg_local agent.git pr
  printf 'PR body.\n' > body.txt
  run jig task ship SRD-1-main --message-file msg.txt --body-file body.txt
  assert_eq 0 "$RC" "$OUT"
  assert_eq "Absorbs: SRD-7" "$(sed '/^$/d' gh-create.body | tail -n 1)"
  assert_eq "PR body." "$(head -n 1 gh-create.body)"
  assert_eq "PR body." "$(cat body.txt)"
}
