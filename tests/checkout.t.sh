# Tests for scripts/lib/checkout.sh — what is happening in this checkout
# (adr-20260924-a-checkout-records-what-is-happening-in-it). Exercised only
# through the dispatcher (`jig <command>`), the way every caller actually
# reaches it: scripts/jig calls jig_checkout_record before a command runs and
# jig_checkout_notice right after, and _status_checkout (status.sh) is the
# one reader of the busy list.
# shellcheck shell=bash

# Run a jig command, capturing stdout in OUT and stderr in ERR separately
# (task.t.sh's run_split — duplicated here because each *.t.sh file is
# sourced on its own, never alongside a sibling test file). `jig task
# current`'s contract (ADR-0012) is that stdout is exactly an id, so a test
# of the HEAD-moved notice — which prints to stderr — needs the two streams
# kept apart.
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

# checkout_setup — fixture_jig_repo, and nothing this file adds: the runner
# already clears CLAUDE_CODE_SESSION_ID for every test (tests/run.sh), so the
# naming fallback of last resort is off unless a test asks for it. The unset
# is repeated here because these tests are the ones that would pass for the
# wrong reason if it ever went away.
checkout_setup() {
  fixture_jig_repo
  unset CLAUDE_CODE_SESSION_ID
}

# --- the checkout record (runtime/checkout) -----------------------------------

test_checkout_record_writes_checkout_file_with_command_and_args() {
  checkout_setup
  run jig task list --all
  assert_eq 0 "$RC"
  assert_file .ai/runtime/checkout
  assert_file_contains .ai/runtime/checkout "command: task list --all"
}

# --- naming the working record ------------------------------------------------

test_checkout_working_record_named_by_the_task_on_head() {
  checkout_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_file .ai/runtime/working/T-1
  assert_file_contains .ai/runtime/working/T-1 "command: status"
}

test_checkout_working_record_named_by_argument_on_the_base_branch() {
  checkout_setup
  jig task new T-1 >/dev/null
  # `task new` only files the workspace; it never moves HEAD.
  assert_eq "main" "$(git symbolic-ref --short HEAD)"

  run jig task show T-1
  assert_eq 0 "$RC"
  assert_file .ai/runtime/working/T-1
  assert_file_contains .ai/runtime/working/T-1 "command: task show T-1"
}

# A subcommand word is not a task id just because jig_valid_id accepts its
# characters: rule 1 additionally requires a workspace to exist, so "check"
# below must never become a file name under working/.
test_checkout_unmatched_argument_does_not_name_a_working_record() {
  checkout_setup
  run jig knowledge check
  assert_no_file .ai/runtime/working
}

test_checkout_uninitialised_project_creates_no_runtime_dir() {
  fixture_repo
  unset CLAUDE_CODE_SESSION_ID
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "initialised: no"
  assert_no_file .ai/runtime
}

test_checkout_help_and_version_leave_no_records() {
  fixture_repo
  unset CLAUDE_CODE_SESSION_ID
  run jig help
  assert_eq 0 "$RC"
  run jig version
  assert_eq 0 "$RC"
  assert_no_file .ai/runtime
}

# --- the HEAD-moved notice (runtime/checkout's branch_reported) ---------------

test_checkout_notice_reports_moved_head_and_keeps_stdout_the_bare_id() {
  checkout_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  local real_branch
  real_branch=$(git symbolic-ref --short HEAD)

  # Plant a stale "last told" branch, as if an earlier reader had been shown
  # a branch this checkout has since moved off.
  mkdir -p .ai/runtime
  printf 'command: task start T-1\nbranch_reported: bogus-branch\n' > .ai/runtime/checkout

  run_split jig task current
  assert_eq 0 "$RC"
  assert_eq "T-1" "$OUT"
  assert_contains "$ERR" "checkout: HEAD here moved bogus-branch -> $real_branch since you were told"
  assert_file_contains .ai/runtime/checkout "branch_reported: $real_branch"

  # Once told, `branch_reported` matches HEAD again, so a second run must
  # stay silent about it.
  run_split jig task current
  assert_eq 0 "$RC"
  assert_eq "T-1" "$OUT"
  assert_not_contains "$ERR" "checkout: HEAD here moved"
}

test_checkout_notice_skips_non_orienting_commands() {
  checkout_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null

  mkdir -p .ai/runtime
  printf 'command: task start T-1\nbranch_reported: bogus-branch\n' > .ai/runtime/checkout

  # `task show` is not one of the commands a session orients itself with
  # (_jig_checkout_orienting), so it must neither print the notice nor move
  # branch_reported forward.
  run_split jig task show T-1
  assert_eq 0 "$RC"
  assert_not_contains "$ERR" "checkout: HEAD here moved"
  assert_file_contains .ai/runtime/checkout "branch_reported: bogus-branch"
}

# --- `jig status`'s "working here:" line (_status_checkout, status.sh) --------

test_status_shows_working_here_for_foreign_records_but_not_the_current_task() {
  checkout_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  jig task new T-2 >/dev/null

  mkdir -p .ai/runtime/working
  printf 'command: verify\n' > .ai/runtime/working/T-2
  printf 'command: verify\n' > .ai/runtime/working/some-other-session

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "working here: task T-2 (jig verify,"
  assert_contains "$OUT" "working here: another session (jig verify,"
  # T-1's branch is HEAD here: the reader is sitting on it and is not told.
  assert_not_contains "$OUT" "working here: task T-1"
}

test_checkout_busy_expired_record_is_hidden_but_not_deleted() {
  checkout_setup
  jig task new T-2 >/dev/null

  mkdir -p .ai/runtime/working
  printf 'command: verify\n' > .ai/runtime/working/T-2
  touch -t 202001010000 .ai/runtime/working/T-2

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "working here:"
  # Nothing here deletes a record older than the window; only cleaning it up
  # would be a decision of its own (checkout.sh, jig_checkout_busy).
  assert_file .ai/runtime/working/T-2
}

# --- checkout.busy_ttl (config-driven freshness window) -----------------------

test_checkout_busy_ttl_from_config_controls_visibility() {
  checkout_setup
  jig task new T-2 >/dev/null
  printf 'checkout.busy_ttl: 1s\n' >> .ai/config.yaml

  mkdir -p .ai/runtime/working
  printf 'command: verify\n' > .ai/runtime/working/T-2
  touch -t 202001010000 .ai/runtime/working/T-2

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "working here:"

  sed 's|^checkout.busy_ttl:.*|checkout.busy_ttl: 99999d|' .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "working here: task T-2 (jig verify,"
}

# A mistyped setting must not take `jig status` down with it
# (_jig_checkout_ttl catches jig_duration_seconds's death and falls back to
# the 12h default).
test_checkout_busy_ttl_garbage_value_falls_back_to_default_without_failing() {
  checkout_setup
  jig task new T-2 >/dev/null
  printf 'checkout.busy_ttl: nonsense\n' >> .ai/config.yaml

  mkdir -p .ai/runtime/working
  printf 'command: verify\n' > .ai/runtime/working/T-2

  run jig status
  assert_eq 0 "$RC"
  # A fresh record is well within the 12h default, so the fallback must
  # still show it rather than silently hiding everything.
  assert_contains "$OUT" "working here: task T-2 (jig verify,"
}

# --- the session's own record is not a neighbour ------------------------------

# The property delegation safety rests on: a session's own record is excluded
# from the busy list by name, so a coordinator and the agents it spawns — which
# inherit CLAUDE_CODE_SESSION_ID, measured — are one occupant of the checkout,
# not four. Asserted here through `jig status`, the only reader of the list
# until `task start` gains its refusal.
test_checkout_busy_excludes_this_sessions_own_record() {
  fixture_jig_repo
  CLAUDE_CODE_SESSION_ID=this-session-id
  export CLAUDE_CODE_SESSION_ID

  # No task on HEAD and none named in the arguments, so the session id is what
  # names this run's record (rule 3).
  run jig status
  assert_eq 0 "$RC"
  assert_file .ai/runtime/working/this-session-id
  assert_not_contains "$OUT" "working here:"

  # Another session's record, by contrast, is exactly what the reader is owed.
  printf 'command: verify\n' > .ai/runtime/working/other-session-id
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "working here: another session (jig verify,"
  assert_not_contains "$OUT" "this-session-id"
}

# --- checkout.busy_ttl as a per-clone setting (ADR-0038) ----------------------

# Registering a key in JIG_CFG_LOCAL_KEYS is not one edit but three: the list,
# the value check in jig_config_value_problem, and schemas/config.md. Without
# the second, `jig config show --local` calls the key local while
# `jig config set --local` refuses it as "not a local key" — this test is what
# holds the three together.
test_checkout_busy_ttl_is_a_per_clone_setting() {
  checkout_setup
  jig task new T-2 >/dev/null

  run jig config set checkout.busy_ttl 1s --local
  assert_eq 0 "$RC"

  mkdir -p .ai/runtime/working
  printf 'command: verify\n' > .ai/runtime/working/T-2
  touch -t 202001010000 .ai/runtime/working/T-2

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "working here:"

  run jig config show --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "checkout.busy_ttl: 1s"
  assert_not_contains "$OUT" "ignored: checkout.busy_ttl"

  run jig config set checkout.busy_ttl nonsense --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a duration"
}

# A record's temporary is a dotfile, so a process killed between the write and
# the rename leaves nothing the busy glob can see. Named `<id>.tmp.<pid>` it
# would pass jig_valid_id — dots are legal in an id — and become a neighbour
# that never existed.
test_checkout_busy_ignores_a_leftover_temporary() {
  checkout_setup
  jig task new T-2 >/dev/null
  mkdir -p .ai/runtime/working
  printf 'command: verify\n' > .ai/runtime/working/.tmp.T-2.99999

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "working here:"
}

# --- the notice belongs to the reader, not to the checkout --------------------

# The message is the only channel to the session whose HEAD moved, so the
# session that moved it must not be able to consume it. Measured before the
# fix: `task start` followed by `task current` in the same session took the
# message and left the neighbour's `jig status` silent, because one shared
# `branch_reported` answered whoever looked first.
test_checkout_notice_is_personal_to_each_session() {
  fixture_jig_repo
  jig task new T-1 >/dev/null

  # Session A orients itself while HEAD is still the base branch.
  CLAUDE_CODE_SESSION_ID=session-a
  export CLAUDE_CODE_SESSION_ID
  run_split jig task list
  assert_eq 0 "$RC"
  assert_not_contains "$ERR" "checkout: HEAD here moved"
  assert_file .ai/runtime/told/session-a

  # Session B orients, then starts the task, which moves this checkout's HEAD.
  CLAUDE_CODE_SESSION_ID=session-b
  jig task list >/dev/null 2>&1
  jig task start T-1 >/dev/null

  # B gets one true line about a move it made itself — that noise is accepted.
  run_split jig task list
  assert_eq 0 "$RC"
  assert_contains "$ERR" "checkout: HEAD here moved main -> task/T-1"

  # And A is still owed the message: B must not have eaten it.
  CLAUDE_CODE_SESSION_ID=session-a
  run_split jig task list
  assert_eq 0 "$RC"
  assert_contains "$ERR" "checkout: HEAD here moved main -> task/T-1"

  # Told once, told for good — for that session alone.
  run_split jig task list
  assert_not_contains "$ERR" "checkout: HEAD here moved"
}

# --- reading about work elsewhere is not doing it here ------------------------

checkout_setup_nested() {
  mkdir repo || return 1
  cd repo || return 1
  checkout_setup
}

# `jig status` prints `worktree=<path>` for a task whose branch git says is
# checked out elsewhere (ADR-0029). Naming that task as work in progress here
# made one page say both, so rule 1 skips it.
test_checkout_a_task_living_in_another_worktree_is_not_work_here() {
  skip_unless_symlinks
  checkout_setup_nested
  jig task new T-2 >/dev/null
  jig task start T-2 --worktree >/dev/null

  # HEAD here never moved, and T-2's branch is checked out in its own tree.
  assert_eq "main" "$(git symbolic-ref --short HEAD)"

  # `task start --worktree` ran here and recorded the work before the tree
  # existed, so the record is stale from birth. The reader is where that shows,
  # and `jig status` must not print both halves of the contradiction.
  assert_file .ai/runtime/working/T-2
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "worktree="
  assert_not_contains "$OUT" "working here: task T-2"

  # And reading about that work does not re-declare it as work happening here.
  rm -f .ai/runtime/working/T-2
  run jig task show T-2
  assert_eq 0 "$RC"
  assert_no_file .ai/runtime/working/T-2
}

# --- the record directory is read in one pass --------------------------------

# Exercises the batched reader: one `stat` for the whole directory, its BSD
# and GNU spellings, and the ages parsed out of it. A per-file `stat` and a
# per-file fork were most of what a grown directory cost, and nothing here
# deletes an expired record.
test_checkout_busy_reads_a_directory_of_records_in_one_pass() {
  checkout_setup
  local i
  mkdir -p .ai/runtime/working
  for i in 1 2 3 4 5 6 7 8; do
    printf 'command: verify-%s\n' "$i" > ".ai/runtime/working/bulk-$i"
  done
  touch -t 202001010000 .ai/runtime/working/bulk-1 .ai/runtime/working/bulk-2 \
    .ai/runtime/working/bulk-3 .ai/runtime/working/bulk-4

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "jig verify-1"
  assert_not_contains "$OUT" "jig verify-4"
  assert_contains "$OUT" "working here: another session (jig verify-5,"
  assert_contains "$OUT" "working here: another session (jig verify-8,"
}

# --- which commands owe a reader the notice -----------------------------------

# The set lives in _jig_checkout_orienting, and the same two commands are named
# in prose in jig-task/SKILL.md §1. Nothing but this test holds the two
# together, so it asserts the whole set rather than one member: every command a
# session orients itself with prints the notice, and a command that merely
# reads a task does not.
test_checkout_only_orienting_commands_print_the_notice() {
  checkout_setup
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  local real_branch stale
  real_branch=$(git symbolic-ref --short HEAD)
  stale='command: task start T-1
branch_reported: bogus-branch
'

  local cmd
  for cmd in "status" "task current" "task list"; do
    mkdir -p .ai/runtime
    printf '%s' "$stale" > .ai/runtime/checkout
    # shellcheck disable=SC2086
    run_split jig $cmd
    assert_eq 0 "$RC"
    assert_contains "$ERR" "checkout: HEAD here moved bogus-branch -> $real_branch" \
      "jig $cmd is a command a session orients itself with"
  done

  for cmd in "task show T-1" "task artifacts T-1" "knowledge check"; do
    printf '%s' "$stale" > .ai/runtime/checkout
    # shellcheck disable=SC2086
    run_split jig $cmd
    assert_not_contains "$ERR" "checkout: HEAD here moved" \
      "jig $cmd does not orient a session and must stay quiet"
    assert_file_contains .ai/runtime/checkout "branch_reported: bogus-branch"
  done
}

# --- how far the session id reaches ------------------------------------------

# The reviewer's reproduction, inverted. Adapters are not copied into `.ai/`,
# so they are found through the manifest's `jig.source`; with that source gone,
# a valid session id used to name nothing at all, and rule 3 was alive only for
# whoever installed. The jig that is running may itself be a framework
# checkout, and now that is tried second.
test_checkout_session_id_survives_a_source_the_manifest_cannot_reach() {
  fixture_jig_repo
  CLAUDE_CODE_SESSION_ID=session-x
  export CLAUDE_CODE_SESSION_ID
  sed 's|^jig.source:.*|jig.source: /nonexistent/jig-source|' .ai/manifest > .ai/manifest.tmp
  mv .ai/manifest.tmp .ai/manifest

  run jig status
  assert_eq 0 "$RC"
  assert_file .ai/runtime/working/session-x
  assert_not_contains "$OUT" "sessions: not observable"
}

# Being told nothing is not the same as being told there is nobody here. Where
# no active runtime names its sessions — Codex alone, today — `jig status` says
# so, as it already does for the session hook's own exit 2 (ADR-0024).
test_checkout_status_says_when_no_runtime_names_its_sessions() {
  fixture_jig_repo
  CLAUDE_CODE_SESSION_ID=session-x
  export CLAUDE_CODE_SESSION_ID
  sed 's|^adapters:.*|adapters: [codex]|' .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "sessions: not observable (no active runtime names its sessions here)"
  # And with no name, the run leaves no record of its own.
  assert_no_file .ai/runtime/working/session-x
}

# --- "here" is never taken on hearsay -----------------------------------------

# A jig command run under another jig inherits JIG_PROJECT, and the recorder
# used to trust it. The suite run by `jig verify` therefore wrote every record
# into the repository being verified rather than into each test's own checkout —
# found in this repository's `.ai/runtime/told/`, holding session ids that only
# ever existed inside tests. Every other command computes the root with
# jig_require_repo; the recorder now does the same.
test_checkout_record_ignores_an_inherited_project_root() {
  checkout_setup
  local elsewhere
  elsewhere=$(mktemp -d "${TMPDIR:-/tmp}/jig-elsewhere.XXXXXX")
  mkdir -p "$elsewhere/.ai"
  printf 'profiles: [generic]\n' > "$elsewhere/.ai/config.yaml"

  run env JIG_PROJECT="$elsewhere" "$JIG_BIN" task list
  assert_eq 0 "$RC"
  assert_file .ai/runtime/checkout
  assert_no_file "$elsewhere/.ai/runtime"

  rm -rf "$elsewhere"
}

# The same failure one layer down, and the reason this file carries both. The
# root above was inherited through JIG_PROJECT; here it is inherited through
# git itself — `git rev-parse --show-toplevel` reads GIT_DIR, and `git -C`
# does not override it. Measured: with GIT_DIR and GIT_WORK_TREE naming
# another jig project and the working directory untouched, every record went
# there and none here. jig clears the git location variables at the top of the
# dispatcher, before the recorder resolves anything.
test_checkout_record_ignores_a_git_dir_naming_another_repository() {
  checkout_setup
  local elsewhere
  elsewhere=$(mktemp -d "${TMPDIR:-/tmp}/jig-elsewhere.XXXXXX")
  (
    cd "$elsewhere" || exit 1
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    mkdir -p .ai
    printf 'profiles: [generic]\n' > .ai/config.yaml
    printf '# elsewhere\n' > README.md
    git add -A
    git commit -q -m "elsewhere"
  )

  run env GIT_DIR="$elsewhere/.git" GIT_WORK_TREE="$elsewhere" "$JIG_BIN" task list
  assert_eq 0 "$RC"
  assert_file .ai/runtime/checkout
  assert_file_contains .ai/runtime/checkout "command: task list"
  assert_no_file "$elsewhere/.ai/runtime"

  rm -rf "$elsewhere"
}
