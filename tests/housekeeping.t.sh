# Tests for `jig housekeeping` (SPEC §23, §24; ADR-0005; ADR-0006).
# shellcheck shell=bash

hk_setup() {
  fixture_jig_repo
  # Most tests exercise the policy and the purge, not the network: without
  # this every run would try to fetch and reach for `gh`, and the forge tier
  # would answer differently on a maintainer's machine than in CI.
  hk_cfg forge none
  hk_cfg housekeeping.fetch false
}

# hk_cfg <key> <value> — rewrite one line of the project's config.yaml.
hk_cfg() {
  sed "s|^$1:.*|$1: $2|" .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml
}

# hk_days_ago <n> — a YYYY-MM-DD date <n> days in the past, on BSD and GNU
# date alike (the same portability split as jig_file_age_days).
hk_days_ago() {
  if date -v-"$1"d +%Y-%m-%d 2>/dev/null; then :; else date -d "$1 days ago" +%Y-%m-%d; fi
}

# Call housekeeping_decide directly. The policy is a pure function, so the
# whole SPEC §23 table is testable without a git repository or a workspace.
hk_decide() {
  bash -c '
    set -eu
    JIG_LIB="$JIG_HOME/scripts/lib"
    . "$JIG_LIB/version.sh"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    . "$JIG_LIB/housekeeping.sh"
    housekeeping_decide "$@"
  ' _ "$@"
}

# --- policy table (SPEC §23) -------------------------------------------------

test_housekeeping_decide_consolidated_merged_purges() {
  assert_eq "purge" "$(hk_decide consolidated merged "" 1 14 60)"
}

test_housekeeping_decide_active_merged_needs_consolidation() {
  assert_eq "preserve needs-consolidation" "$(hk_decide active merged "" 1 14 60)"
}

test_housekeeping_decide_ready_merged_needs_consolidation() {
  assert_eq "preserve needs-consolidation" "$(hk_decide ready merged "" 1 14 60)"
}

test_housekeeping_decide_open_preserves_every_status() {
  local st
  for st in active ready consolidated abandoned; do
    assert_eq "preserve" "$(hk_decide "$st" open "" 1 14 60)" "status $st on open"
  done
}

test_housekeeping_decide_closed_flags_abandoned_question() {
  assert_eq "preserve abandoned?" "$(hk_decide active closed "" 1 14 60)"
  assert_eq "preserve abandoned?" "$(hk_decide ready closed "" 1 14 60)"
}

test_housekeeping_decide_unknown_preserves_every_status() {
  local st
  for st in active ready consolidated; do
    assert_eq "preserve" "$(hk_decide "$st" unknown "" 1 14 60)" "status $st on unknown"
  done
}

test_housekeeping_decide_abandoned_purges_only_past_ttl() {
  assert_eq "preserve" "$(hk_decide abandoned unknown "" 14 14 60)" "at the ttl"
  assert_eq "purge" "$(hk_decide abandoned unknown "" 15 14 60)" "past the ttl"
}

test_housekeeping_decide_abandoned_purges_regardless_of_remote() {
  local remote
  for remote in merged open closed unknown; do
    assert_eq "purge" "$(hk_decide abandoned "$remote" "" 30 14 60)" "abandoned on $remote"
  done
}

test_housekeeping_decide_stale_candidate_is_report_only() {
  # Old and unmerged: flagged, never purged. Semantic lifecycle beats TTL.
  assert_eq "preserve STALE_CANDIDATE" "$(hk_decide active unknown "" 99 14 60)"
  assert_eq "preserve needs-consolidation,STALE_CANDIDATE" \
    "$(hk_decide active merged "" 99 14 60)"
}

test_housekeeping_decide_stale_candidate_absent_when_purging() {
  # An abandoned workspace past both TTLs is purged; flagging it stale as
  # well would put a "look at this" marker on a directory that just moved.
  assert_eq "purge" "$(hk_decide abandoned unknown "" 99 14 60)"
}

# --- pause is orthogonal (ADR-0012) ------------------------------------------

test_housekeeping_decide_paused_never_changes_the_action() {
  local st remote
  for st in active ready consolidated; do
    for remote in open closed unknown; do
      assert_eq "$(hk_decide "$st" "$remote" "" 1 14 60)" \
        "$(hk_decide "$st" "$remote" true 1 14 60)" "paused changed $st/$remote"
    done
  done
}

test_housekeeping_decide_paused_and_merged_still_needs_consolidation() {
  assert_eq "preserve needs-consolidation" "$(hk_decide active merged true 1 14 60)"
  assert_eq "preserve needs-consolidation" "$(hk_decide ready merged true 1 14 60)"
}

test_housekeeping_decide_paused_consolidated_merged_still_purges() {
  # Pause exempts a task from auto-resume, never from its lifecycle end.
  assert_eq "purge" "$(hk_decide consolidated merged true 1 14 60)"
}

test_housekeeping_decide_paused_is_still_reported_stale() {
  assert_eq "preserve STALE_CANDIDATE" "$(hk_decide active unknown true 99 14 60)"
}

# --- ancestry (design.md §2) -------------------------------------------------

test_housekeeping_ancestry_detects_every_merge_shape() {
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated
  fixture_task mc "commit-merged" consolidated
  fixture_task sq "squash-merged" consolidated
  fixture_task rb "rebase-merged" consolidated

  run jig housekeeping --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ff status=consolidated remote=merged via=ancestry action=would-purge"
  assert_contains "$OUT" "mc status=consolidated remote=merged via=ancestry action=would-purge"
  assert_contains "$OUT" "sq status=consolidated remote=merged via=ancestry action=would-purge"
  assert_contains "$OUT" "rb status=consolidated remote=merged via=ancestry action=would-purge"
}

test_housekeeping_ancestry_says_unknown_not_open() {
  # The ancestry tier answers "landed" or "cannot tell"; only a forge knows
  # about pull requests, so an unmerged branch is `unknown`, never `open`.
  hk_setup
  fixture_merge_repo
  fixture_task op "still-open" consolidated

  run jig housekeeping --dry-run
  assert_contains "$OUT" "op status=consolidated remote=unknown via=none action=preserve"
  assert_not_contains "$OUT" "remote=open"
}

test_housekeeping_deleted_branch_is_unknown_not_merged() {
  # `gone-merged` really was squash-merged, but its branch is gone, so there
  # is no tip to compare. Guessing "merged" here would delete a workspace on
  # the strength of a missing ref.
  hk_setup
  fixture_merge_repo
  fixture_task gone "gone-merged" consolidated

  run jig housekeeping
  assert_contains "$OUT" "gone status=consolidated remote=unknown via=none action=preserve"
  assert_dir .ai/workspace/tasks/gone
}

test_housekeeping_detached_branch_is_unknown() {
  hk_setup
  fixture_task det "detached" consolidated

  run jig housekeeping
  assert_contains "$OUT" "det status=consolidated remote=unknown via=none action=preserve"
  assert_dir .ai/workspace/tasks/det
}

# --- purge (ADR-0006) --------------------------------------------------------

test_housekeeping_purges_consolidated_merged_to_trash() {
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping
  assert_eq 0 "$RC"
  assert_no_file .ai/workspace/tasks/ff/state
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/ff/state"
  assert_contains "$OUT" "action=purge"
  assert_contains "$OUT" "dest=.ai/runtime/trash/"
}

test_housekeeping_purge_keeps_the_workspace_readable_in_trash() {
  # Recovery is a plain `mv` back, which only works if the contents survive.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated
  printf 'design notes\n' > .ai/workspace/tasks/ff/design.md

  run jig housekeeping
  assert_file_contains ".ai/runtime/trash/$(date +%Y-%m-%d)/ff/design.md" "design notes"
}

test_housekeeping_trash_collision_does_not_destroy_the_earlier_entry() {
  hk_setup
  fixture_merge_repo
  local day
  day=$(date +%Y-%m-%d)
  mkdir -p ".ai/runtime/trash/$day/ff"
  printf 'first\n' > ".ai/runtime/trash/$day/ff/marker"

  fixture_task ff "ff-merged" consolidated
  run jig housekeeping
  assert_file_contains ".ai/runtime/trash/$day/ff/marker" "first"
  assert_file ".ai/runtime/trash/$day/ff-2/state"
}

test_housekeeping_never_purges_on_unknown_remote() {
  hk_setup
  local st
  for st in active ready consolidated; do
    fixture_task "u-$st" "no-such-branch" "$st"
  done

  run jig housekeeping
  for st in active ready consolidated; do
    assert_dir ".ai/workspace/tasks/u-$st"
  done
  assert_not_contains "$OUT" "action=purge"
}

test_housekeeping_purges_abandoned_past_ttl_only() {
  hk_setup
  fixture_task old-one "no-such-branch" abandoned "updated_at:$(hk_days_ago 30)"
  fixture_task young-one "no-such-branch" abandoned "updated_at:$(hk_days_ago 3)"

  run jig housekeeping
  assert_no_file .ai/workspace/tasks/old-one/state
  assert_dir .ai/workspace/tasks/young-one
}

# --- dry run -----------------------------------------------------------------

test_housekeeping_dry_run_changes_nothing() {
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "would-purge"
  assert_contains "$OUT" "dry run: nothing was changed"
  assert_dir .ai/workspace/tasks/ff
  assert_no_file .ai/runtime/last-housekeeping
  assert_no_file .ai/runtime/housekeeping.log
}

test_housekeeping_dry_run_does_not_expire_trash() {
  hk_setup
  local old
  old=$(hk_days_ago 30)
  mkdir -p ".ai/runtime/trash/$old/gone"
  printf 'x\n' > ".ai/runtime/trash/$old/gone/marker"

  run jig housekeeping --dry-run
  assert_contains "$OUT" "would-delete trash/$old"
  assert_file ".ai/runtime/trash/$old/gone/marker"
}

# --- trash expiry (phase two of ADR-0006) ------------------------------------

test_housekeeping_expires_trash_past_ttl_only() {
  hk_setup
  local old young
  old=$(hk_days_ago 30)
  young=$(hk_days_ago 2)
  mkdir -p ".ai/runtime/trash/$old/a" ".ai/runtime/trash/$young/b"

  run jig housekeeping
  assert_eq 0 "$RC"
  assert_no_file ".ai/runtime/trash/$old/a"
  assert_dir ".ai/runtime/trash/$young/b"
  assert_contains "$OUT" "delete trash/$old"
}

test_housekeeping_trash_age_comes_from_the_directory_name() {
  # A freshly-moved directory has today's mtime, so an mtime-based expiry
  # would keep an entry alive forever. The date in the path is the clock.
  hk_setup
  local old
  old=$(hk_days_ago 30)
  mkdir -p ".ai/runtime/trash/$old/a"
  touch ".ai/runtime/trash/$old" ".ai/runtime/trash/$old/a"

  run jig housekeeping
  assert_no_file ".ai/runtime/trash/$old/a"
}

test_housekeeping_ignores_non_date_directories_in_trash() {
  hk_setup
  mkdir -p ".ai/runtime/trash/not-a-date/x"

  run jig housekeeping
  assert_eq 0 "$RC"
  assert_dir ".ai/runtime/trash/not-a-date/x"
}

# --- report, log, exit codes -------------------------------------------------

test_housekeeping_exits_3_when_consolidation_is_needed() {
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" active

  run jig housekeeping
  assert_eq 3 "$RC"
  assert_contains "$OUT" "flags=needs-consolidation"
  assert_contains "$OUT" "action needed"
}

test_housekeeping_exit_0_when_nothing_needs_an_agent() {
  hk_setup
  fixture_task quiet "no-such-branch" active

  run jig housekeeping
  assert_eq 0 "$RC"
}

test_housekeeping_logs_the_deciding_tier() {
  # "Why was this deleted?" has to be answerable from the log months later,
  # which means recording which tier decided, not just the verdict.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping
  assert_file .ai/runtime/housekeeping.log
  assert_file_contains .ai/runtime/housekeeping.log "task=ff"
  assert_file_contains .ai/runtime/housekeeping.log "via=ancestry"
  assert_file_contains .ai/runtime/housekeeping.log "action=purge"
}

test_housekeeping_stamps_last_housekeeping() {
  hk_setup
  run jig housekeeping
  assert_file .ai/runtime/last-housekeeping
  run jig status
  assert_contains "$OUT" "housekeeping: 0 days ago"
}

test_housekeeping_reports_when_there_are_no_workspaces() {
  hk_setup
  rm -rf .ai/workspace/tasks
  run jig housekeeping
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no task workspaces"
}

test_housekeeping_rejects_unknown_arguments() {
  hk_setup
  run jig housekeeping --wat
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig housekeeping"
}

test_housekeeping_rejects_an_invalid_ttl() {
  # A typo in config must stop the run, not become "0 days" and expire the
  # entire trash directory.
  hk_setup
  hk_cfg housekeeping.trash_ttl "7 days"
  run jig housekeeping
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid duration"
}

test_housekeeping_skips_a_directory_that_is_not_a_task_id() {
  hk_setup
  mkdir -p ".ai/workspace/tasks/.hidden"
  printf 'status: consolidated\n' > ".ai/workspace/tasks/.hidden/state"

  run jig housekeeping
  assert_eq 0 "$RC"
  assert_dir ".ai/workspace/tasks/.hidden"
}

# --- forge tier (alternatives.md C1) -----------------------------------------

# Install a fake `gh` on PATH that answers the one call the forge tier makes.
hk_stub_gh() {
  mkdir -p stub-bin
  cat > stub-bin/gh <<STUB
#!/usr/bin/env bash
case "\$1" in
  auth) exit 0 ;;
  pr) printf '%s\n' "$1" ;;
esac
STUB
  chmod +x stub-bin/gh
  PATH="$PWD/stub-bin:$PATH"
  export PATH
  git remote add origin https://github.com/example/example.git 2>/dev/null || true
}

test_housekeeping_forge_state_wins_over_ancestry() {
  hk_setup
  hk_cfg forge github
  fixture_merge_repo
  # The branch is unmerged locally; the forge says it was merged.
  hk_stub_gh "still-open$(printf '\t')MERGED"
  fixture_task op "still-open" consolidated

  run jig housekeeping
  assert_contains "$OUT" "remote=merged via=forge"
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/op/state"
}

test_housekeeping_forge_reports_closed_which_ancestry_cannot() {
  hk_setup
  hk_cfg forge github
  fixture_merge_repo
  hk_stub_gh "still-open$(printf '\t')CLOSED"
  fixture_task op "still-open" active

  run jig housekeeping
  assert_eq 0 "$RC"
  assert_contains "$OUT" "remote=closed via=forge"
  assert_contains "$OUT" "flags=abandoned?"
  assert_dir .ai/workspace/tasks/op
}

test_housekeeping_forge_none_skips_the_tier_entirely() {
  hk_setup
  hk_cfg forge none
  fixture_merge_repo
  hk_stub_gh "still-open$(printf '\t')MERGED"
  fixture_task op "still-open" consolidated

  run jig housekeeping
  assert_contains "$OUT" "via=none"
  assert_not_contains "$OUT" "via=forge"
  assert_dir .ai/workspace/tasks/op
}

test_housekeeping_branch_without_a_pull_request_falls_through_to_ancestry() {
  hk_setup
  hk_cfg forge github
  fixture_merge_repo
  hk_stub_gh "some-other-branch$(printf '\t')MERGED"
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping
  assert_contains "$OUT" "remote=merged via=ancestry"
}

test_housekeeping_rejects_an_invalid_forge_value() {
  hk_setup
  hk_cfg forge bitbucket
  run jig housekeeping
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid forge"
}

# --- session hook (SPEC §25) -------------------------------------------------

# Wait up to ~5s for the detached housekeeping run to produce <file>.
hk_wait_for() {
  local f="$1" i=0
  while [ "$i" -lt 50 ]; do
    [ -e "$f" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

test_session_hook_runs_housekeeping_when_due() {
  hk_setup
  assert_no_file .ai/runtime/last-housekeeping
  run .ai/scripts/jig-session-hook
  assert_eq 0 "$RC"
  hk_wait_for .ai/runtime/last-housekeeping \
    || fail "hook did not run housekeeping"
}

test_session_hook_is_a_noop_before_the_cadence_elapses() {
  hk_setup
  jig housekeeping >/dev/null
  assert_file .ai/runtime/last-housekeeping
  local before
  before=$(wc -c < .ai/runtime/housekeeping.log)

  run .ai/scripts/jig-session-hook
  assert_eq 0 "$RC"
  sleep 0.5
  assert_eq "$before" "$(wc -c < .ai/runtime/housekeeping.log)" \
    "hook ran housekeeping again inside the cadence"
}

test_session_hook_exits_0_when_the_project_is_not_initialised() {
  # A hook that can fail is a hook that can break the session it is attached
  # to, so every giving-up path returns 0.
  fixture_jig_repo
  local hook=".ai/scripts/jig-session-hook"
  cp "$hook" ./hook-copy
  rm -rf .ai
  run ./hook-copy
  assert_eq 0 "$RC"
}

# --- trunk-based work has no local evidence of landing -----------------------

test_housekeeping_task_on_the_base_branch_is_unknown_not_merged() {
  # `merge-base --is-ancestor main main` is trivially true, so an ancestry
  # check on a task whose branch IS the base branch would call every such
  # task merged. On a trunk-based repository that turns every consolidated
  # workspace into a purge candidate on the first run.
  hk_setup
  fixture_task trunk "main" consolidated

  run jig housekeeping
  assert_contains "$OUT" "trunk status=consolidated remote=unknown via=none action=preserve"
  assert_dir .ai/workspace/tasks/trunk
}

test_housekeeping_does_not_flag_every_active_trunk_task() {
  # The same bug seen from the other side: `active` + `merged` flags
  # needs-consolidation, and housekeeping exits 3 for it. Firing that for
  # every in-progress task on the project's own default workflow would make
  # exit code 3 meaningless.
  hk_setup
  fixture_task t1 "main" active
  fixture_task t2 "main" ready

  run jig housekeeping
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "needs-consolidation"
}

test_housekeeping_base_branch_from_config_is_honoured() {
  hk_setup
  hk_cfg git.base_branch trunk
  # The task sits on `main`, which is no longer the base branch, so ancestry
  # is a real question again rather than a tautology.
  fixture_task t "main" consolidated

  run jig housekeeping --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "t status=consolidated"
}

# --- the report reflects one run, not the whole log --------------------------

test_status_counts_one_task_flagged_across_runs_once() {
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" active

  jig housekeeping >/dev/null || true
  jig housekeeping >/dev/null || true
  jig housekeeping >/dev/null || true

  run jig status
  assert_contains "$OUT" "needs consolidation: 1 task(s)"
}

test_status_forgets_a_flag_once_the_task_is_consolidated() {
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" active

  jig housekeeping >/dev/null || true
  run jig status
  assert_contains "$OUT" "needs consolidation: 1 task(s)"

  # Consolidate it: the next run purges it, and the stale flag from the
  # previous run must not keep being reported.
  jig task set ff status consolidated >/dev/null
  jig housekeeping >/dev/null
  run jig status
  assert_not_contains "$OUT" "needs consolidation"
}

test_housekeeping_log_marks_each_run() {
  hk_setup
  jig housekeeping >/dev/null
  jig housekeeping >/dev/null
  local runs
  runs=$(grep -c '^--- run ' .ai/runtime/housekeeping.log)
  assert_eq 2 "$runs"
}

test_housekeeping_dry_run_writes_no_run_marker() {
  hk_setup
  run jig housekeeping --dry-run
  assert_no_file .ai/runtime/housekeeping.log
}
