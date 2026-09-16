# Tests for `jig housekeeping` (domains/housekeeping; ADR-0005; ADR-0006).
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

# hk_tick — move git's clock ten seconds past the previous tick, starting from
# now. Ancestry tells a branch's own commit from one the base already had by
# when each ref moved, and a tie goes to the base (ADR-0032), so a test that
# commits and merges within one second would read its own work as foreign.
# Call it before every git command that moves a ref the test relies on. The
# clock lives in the repository's git directory: it survives the subshells a
# helper runs in, is shared with the repository's worktrees, and never shows up
# in `git status` — a clock in HOME did, whenever the test repository was HOME.
hk_tick() {
  local clock now
  clock="$(git rev-parse --git-common-dir)/hk-clock"
  if [ -f "$clock" ]; then
    now=$(( $(cat "$clock") + 10 ))
  else
    now=$(( $(date +%s) + 10 ))
  fi
  printf '%s\n' "$now" > "$clock"
  export GIT_COMMITTER_DATE="@$now +0000" GIT_AUTHOR_DATE="@$now +0000"
}

# hk_days_ago <n> — a YYYY-MM-DD date <n> days in the past, on BSD and GNU
# date alike (the same portability split as jig_file_age_days).
hk_days_ago() {
  if date -v-"$1"d +%Y-%m-%d 2>/dev/null; then :; else date -d "$1 days ago" +%Y-%m-%d; fi
}

# Call housekeeping_decide directly. The policy is a pure function, so the
# whole domains/housekeeping table is testable without a git repository or a workspace.
hk_decide() {
  bash -c '
    set -eu
    JIG_LIB="$JIG_HOME/scripts/lib"
    . "$JIG_LIB/version.sh"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    . "$JIG_LIB/housekeeping.sh"
    housekeeping_decide "$@"
  ' _ "$@"
}

# --- policy table (domains/housekeeping) -------------------------------------------------

test_housekeeping_decide_consolidated_merged_purges() {
  assert_eq "purge" "$(hk_decide consolidated merged "" 1 14 60)"
}

# --- released (ADR-0039): a phase merged into an epic that has not itself ----
# reached the default branch is kept, not purged, until it has.

test_housekeeping_decide_consolidated_merged_released_true_purges() {
  # Explicit true is the same as the default omitted above.
  assert_eq "purge" "$(hk_decide consolidated merged "" 1 14 60 true)"
}

test_housekeeping_decide_consolidated_merged_released_false_preserves_flagged() {
  assert_eq "preserve base-unreleased" "$(hk_decide consolidated merged "" 1 14 60 false)"
}

test_housekeeping_decide_active_merged_ignores_released() {
  # A phase still active or ready needs a human regardless of where its base
  # stands: needs-consolidation is unaffected by released.
  assert_eq "preserve needs-consolidation" "$(hk_decide active merged "" 1 14 60 false)"
  assert_eq "preserve needs-consolidation" "$(hk_decide ready merged "" 1 14 60 false)"
}

test_housekeeping_decide_released_only_matters_for_consolidated_merged() {
  # Every other status:remote pair is unaffected by released, false or true.
  local st remote
  for st in active ready consolidated abandoned; do
    for remote in open closed unknown; do
      [ "$st:$remote" = "consolidated:merged" ] && continue
      assert_eq "$(hk_decide "$st" "$remote" "" 1 14 60 true)" \
        "$(hk_decide "$st" "$remote" "" 1 14 60 false)" "released changed $st/$remote"
    done
  done
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

test_housekeeping_decide_abandoned_is_never_flagged_for_consolidation() {
  # An abandoned task has nothing to consolidate. Paused and merged, it used to
  # be flagged anyway: five tasks on this repository, exit 3 on every run.
  assert_eq "preserve" "$(hk_decide abandoned merged true 1 14 60)"
  assert_eq "preserve" "$(hk_decide abandoned merged "" 1 14 60)"
}

test_housekeeping_decide_closed_asks_only_a_task_that_is_not_abandoned_yet() {
  assert_eq "preserve" "$(hk_decide abandoned closed "" 1 14 60)"
  assert_eq "preserve abandoned?" "$(hk_decide consolidated closed "" 1 14 60)"
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

  run jig housekeeping --dry-run --verbose
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

  run jig housekeeping --dry-run --verbose
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

  run jig housekeeping --verbose
  assert_contains "$OUT" "gone status=consolidated remote=unknown via=none action=preserve"
  assert_dir .ai/workspace/tasks/gone
}

test_housekeeping_detached_branch_is_unknown() {
  hk_setup
  fixture_task det "detached" consolidated

  run jig housekeeping --verbose
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
  assert_contains "$OUT" "removed (1): moved to .ai/runtime/trash/$(date +%Y-%m-%d)/, recoverable for 7 days"
  assert_contains "$OUT" "  ff"
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
  assert_not_contains "$OUT" "removed ("
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
  assert_contains "$OUT" "would remove (1): would move to .ai/runtime/trash/"
  assert_contains "$OUT" "dry run: nothing was changed"
  assert_dir .ai/workspace/tasks/ff
  assert_no_file .ai/runtime/last-housekeeping
  assert_no_file .ai/runtime/housekeeping.log
}

test_housekeeping_dry_run_does_not_fetch() {
  # jig-task runs the dry run at the start of every session to find tasks that
  # wait to be closed (ADR-0030), so it must never reach the network. An origin
  # that cannot be fetched makes an attempt visible as `stale-remote`.
  hk_setup
  fixture_merge_repo
  hk_cfg housekeeping.fetch true
  if ! git remote add origin "$PWD/no-such-remote" 2>/dev/null; then
    git remote set-url origin "$PWD/no-such-remote"
  fi

  run jig housekeeping --dry-run
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "stale-remote"

  # Control: the same setup without --dry-run does attempt the fetch.
  run jig housekeeping
  assert_contains "$OUT" "stale-remote"
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
  assert_contains "$OUT" "needs you (1):"
  assert_contains "$OUT" "  merged but not consolidated, run jig-consolidate: ff"
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
  hk_stub_gh "still-open$(printf '\t')main$(printf '\t')MERGED"
  fixture_task op "still-open" consolidated

  run jig housekeeping --verbose
  assert_contains "$OUT" "remote=merged via=forge"
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/op/state"
}

test_housekeeping_forge_reports_closed_which_ancestry_cannot() {
  hk_setup
  hk_cfg forge github
  fixture_merge_repo
  hk_stub_gh "still-open$(printf '\t')main$(printf '\t')CLOSED"
  fixture_task op "still-open" active

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "remote=closed via=forge"
  assert_contains "$OUT" "flags=abandoned?"
  assert_dir .ai/workspace/tasks/op
}

test_housekeeping_forge_none_skips_the_tier_entirely() {
  hk_setup
  hk_cfg forge none
  fixture_merge_repo
  hk_stub_gh "still-open$(printf '\t')main$(printf '\t')MERGED"
  fixture_task op "still-open" consolidated

  run jig housekeeping --verbose
  assert_contains "$OUT" "via=none"
  assert_not_contains "$OUT" "via=forge"
  assert_dir .ai/workspace/tasks/op
}

test_housekeeping_branch_without_a_pull_request_falls_through_to_ancestry() {
  hk_setup
  hk_cfg forge github
  fixture_merge_repo
  hk_stub_gh "some-other-branch$(printf '\t')main$(printf '\t')MERGED"
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping --verbose
  assert_contains "$OUT" "remote=merged via=ancestry"
}

test_housekeeping_rejects_an_invalid_forge_value() {
  hk_setup
  hk_cfg forge bitbucket
  run jig housekeeping
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid forge"
}

# --- forge wrong-base (ADR-0038) -----------------------------------------------
# A pull request into a branch other than the task's own base is not the
# task's landing: a phase merged into `main` instead of its epic, or stacked
# on another phase's branch, must not read as done.

test_housekeeping_forge_pr_into_a_non_default_task_base_decides_as_before() {
  hk_setup
  hk_cfg forge github
  git branch epic/x
  git branch op
  hk_stub_gh "op$(printf '\t')epic/x$(printf '\t')MERGED"
  fixture_task op "op" consolidated "base_branch:epic/x"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "remote=merged via=forge"
  assert_not_contains "$OUT" "flags=wrong-base"
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/op/state"
}

test_housekeeping_forge_merged_into_another_base_flags_wrong_base() {
  hk_setup
  hk_cfg forge github
  git branch op
  hk_stub_gh "op$(printf '\t')release$(printf '\t')MERGED"
  fixture_task op "op" consolidated

  run jig housekeeping --verbose
  assert_eq 3 "$RC"
  assert_contains "$OUT" "remote=unknown via=forge"
  assert_contains "$OUT" "flags=wrong-base"
  assert_contains "$OUT" "needs you (1):"
  assert_contains "$OUT" "  pull request merged into release, not main: op"
  assert_dir .ai/workspace/tasks/op

  run jig status
  assert_contains "$OUT" "wrong base: 1 task(s)"
}

test_housekeeping_forge_stacked_pr_into_another_task_branch_flags_wrong_base() {
  # "Another base" need not be the project's default: a phase stacked on
  # another task's branch is just as much a wrong landing.
  hk_setup
  hk_cfg forge github
  git branch op
  hk_stub_gh "op$(printf '\t')task/phase1$(printf '\t')MERGED"
  fixture_task op "op" active

  run jig housekeeping --verbose
  assert_eq 3 "$RC"
  assert_contains "$OUT" "flags=wrong-base"
  assert_contains "$OUT" "  pull request merged into task/phase1, not main: op"
}

test_housekeeping_forge_newer_open_pr_into_task_base_beats_older_merged_elsewhere() {
  hk_setup
  hk_cfg forge github
  git branch op
  hk_stub_gh "op$(printf '\t')release$(printf '\t')MERGED
op$(printf '\t')main$(printf '\t')OPEN"
  fixture_task op "op" active

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "remote=open via=forge"
  assert_not_contains "$OUT" "flags=wrong-base"
}

# --- session hook (domains/housekeeping) -------------------------------------------------

# hk_wait_for <file> [seconds] — wait for the detached housekeeping run to
# produce <file>, up to [seconds] (default 60) of wall-clock time.
#
# The hook returns before housekeeping ends and hands back nothing to wait on,
# so this polls. The deadline is sized for a loaded machine, not for a test
# running alone: a passing test leaves at the first poll that sees the file, so
# only a real failure pays for it. A 5 s budget failed under a full parallel
# run, where this test took 13 s. The deadline is measured with $SECONDS rather
# than counted in iterations, because under load each `sleep 0.1` takes longer
# than it says.
hk_wait_for() {
  local f="$1" deadline=$((SECONDS + ${2:-60}))
  while [ "$SECONDS" -lt "$deadline" ]; do
    [ -e "$f" ] && return 0
    sleep 0.1
  done
  [ -e "$f" ]
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

  run jig housekeeping --verbose
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
  assert_not_contains "$OUT" "needs you"
}

test_housekeeping_base_branch_from_config_is_honoured() {
  hk_setup
  hk_cfg git.base_branch trunk
  # The task sits on `main`, which is no longer the base branch, so ancestry
  # is a real question again rather than a tautology.
  fixture_task t "main" consolidated

  run jig housekeeping --dry-run --verbose
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
  jig task set ff knowledge_consolidated true >/dev/null
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

# --- the fork point (ADR-0008; a branch that did nothing has landed nothing) --

test_housekeeping_branch_with_no_commits_since_the_fork_is_unknown() {
  # THE regression this field exists for. A branch created and not committed
  # to has a tip identical to the base's, so `merge-base --is-ancestor` is
  # trivially true and ancestry answers `merged`. A consolidated task would
  # then be purged while all of its work sits uncommitted in the tree.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  git branch task/fresh
  fixture_task fresh "task/fresh" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "fresh status=consolidated remote=unknown via=none action=preserve"
  assert_dir .ai/workspace/tasks/fresh
}

test_housekeeping_branch_with_landed_commits_is_merged() {
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/landed
  printf 'work\n' > work.txt
  git add work.txt
  hk_tick
  git commit -q -m "task work"
  git checkout -q main
  hk_tick
  git merge -q --no-ff -m "merge task/landed" task/landed
  fixture_task landed "task/landed" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "landed status=consolidated remote=merged via=ancestry action=purge"
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/landed/state"
}

test_housekeeping_branch_with_unlanded_commits_is_preserved() {
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  git checkout -q -b task/open
  printf 'work\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  git checkout -q main
  fixture_task op "task/open" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "op status=consolidated remote=unknown"
  assert_dir .ai/workspace/tasks/op
}

test_housekeeping_task_without_a_fork_point_behaves_as_before() {
  # Every workspace created before this field existed has no base_commit.
  # Absence is a valid state, not a defect, and must not change any verdict.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping --verbose
  assert_contains "$OUT" "ff status=consolidated remote=merged via=ancestry action=purge"
}

test_housekeeping_ignores_a_fork_point_that_no_longer_exists() {
  # A rewritten history can leave base_commit pointing at nothing. That must
  # fall back to the old check rather than abort the run.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated "base_commit:0000000000000000000000000000000000000000"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ff status=consolidated remote=merged"
}

# --- own work vs. a foreign fast-forward (ADR-0032) --------------------------
# Git's refs alone cannot tell "merged by fast-forward" from "fast-forwarded
# onto a newer base with nothing of its own": in both, the tip is an ancestor
# of the base. Only reflog timing tells them apart.

test_housekeeping_branch_moved_onto_a_newer_base_with_no_own_commits_is_unknown() {
  # Observed on 2026-09-13: a task branch fast-forwarded onto origin/main with
  # no commits of its own read as `merged`, and a `ready` task got flagged
  # needs-consolidation for work nobody did. Three ways a branch ends up
  # carrying only the base's commits: merge --ff-only, rebase, reset --hard.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git branch task/mff
  git branch task/mrb
  git branch task/mrs
  hk_tick
  printf 'main work\n' > main-work.txt
  git add main-work.txt
  git commit -q -m "main moves on"

  hk_tick
  git checkout -q task/mff
  git merge -q --ff-only main
  git checkout -q main

  hk_tick
  git checkout -q task/mrb
  git rebase -q main
  git checkout -q main

  hk_tick
  git checkout -q task/mrs
  git reset -q --hard main
  git checkout -q main

  fixture_task mff "task/mff" ready "base_commit:$fork"
  fixture_task mrb "task/mrb" ready "base_commit:$fork"
  fixture_task mrs "task/mrs" ready "base_commit:$fork"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "mff status=ready remote=unknown"
  assert_contains "$OUT" "mrb status=ready remote=unknown"
  assert_contains "$OUT" "mrs status=ready remote=unknown"
  assert_not_contains "$OUT" "flags=needs-consolidation"
}

test_housekeeping_branch_moved_onto_a_newer_base_reports_the_reason() {
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git branch task/noown
  hk_tick
  printf 'main work\n' > main-work.txt
  git add main-work.txt
  git commit -q -m "main moves on"
  hk_tick
  git checkout -q task/noown
  git merge -q --ff-only main
  git checkout -q main
  fixture_task noown "task/noown" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "noown status=consolidated remote=unknown"
  assert_contains "$OUT" \
    "its branch has no commits of its own (only commits main already had): noown"
}

test_housekeeping_own_commit_then_fast_forward_merge_is_merged() {
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/ownff
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git merge -q --ff-only task/ownff
  fixture_task ownff "task/ownff" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "ownff status=consolidated remote=merged via=ancestry action=purge"
}

test_housekeeping_own_commit_squash_merged_with_a_fork_point_is_merged() {
  # The squash shape (design.md §2 step 2), now with base_commit recorded: the
  # fork-point gate must not get in the way of a squash merge it can vouch for.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/ownsq
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git merge --squash task/ownsq >/dev/null
  hk_tick
  git commit -q -m "squashed task/ownsq"
  fixture_task ownsq "task/ownsq" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "ownsq status=consolidated remote=merged via=ancestry action=purge"
}

test_housekeeping_own_commit_cherry_picked_onto_main_is_merged() {
  # The rebase-merge shape (design.md §2 step 3): every commit lands
  # individually, with the branch itself left untouched.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/owncp
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git cherry-pick task/owncp >/dev/null
  fixture_task owncp "task/owncp" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "owncp status=consolidated remote=merged via=ancestry action=purge"
}

test_housekeeping_own_work_after_an_earlier_fast_forward_is_still_seen() {
  # The branch first carries only the base's commits (which alone would read
  # `unknown`), then gets a commit of its own before merging. The earlier
  # fast-forward must not hide the later own work.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git branch task/ffthenown
  hk_tick
  printf 'main work\n' > main-work.txt
  git add main-work.txt
  git commit -q -m "main moves on"
  hk_tick
  git checkout -q task/ffthenown
  git merge -q --ff-only main
  hk_tick
  printf 'own\n' > own.txt
  git add own.txt
  git commit -q -m "own work after the fast-forward"
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/ffthenown" task/ffthenown
  fixture_task ffthenown "task/ffthenown" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" \
    "ffthenown status=consolidated remote=merged via=ancestry action=purge"
}

test_housekeeping_a_discarded_own_commit_is_unknown() {
  # A commit made on the branch and then reset away landed nothing: it is not
  # an ancestor of the tip any more, so it must not count as own work.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/discarded
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work to be discarded"
  hk_tick
  git checkout -q main
  printf 'main work\n' > main-work.txt
  git add main-work.txt
  hk_tick
  git commit -q -m "main moves on"
  hk_tick
  git checkout -q task/discarded
  git reset -q --hard main
  git checkout -q main
  fixture_task discarded "task/discarded" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "discarded status=consolidated remote=unknown"
  assert_contains "$OUT" \
    "its branch has no commits of its own (only commits main already had): discarded"
}

test_housekeeping_remote_tracking_ref_reads_merged_from_origin() {
  # The bare remote lives beside the project, not inside it, the same reason
  # hk_worktree_setup nests the project under `repo`.
  mkdir repo
  cd repo
  hk_setup
  git init -q --bare ../origin.git
  git remote add origin ../origin.git
  hk_tick
  git push -q origin main
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/remote
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git push -q origin task/remote
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/remote" task/remote
  hk_tick
  git push -q origin main
  git branch -q -D task/remote
  fixture_task remote "task/remote" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "remote status=consolidated remote=merged via=ancestry action=purge"
}

test_housekeeping_remote_tracking_ref_ff_onto_main_with_no_own_commits_is_unknown() {
  # The mirror of the case above: nothing of its own, read from
  # origin/<branch> once the local branch is gone.
  mkdir repo
  cd repo
  hk_setup
  git init -q --bare ../origin.git
  git remote add origin ../origin.git
  hk_tick
  git push -q origin main
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git branch task/remoteff
  hk_tick
  printf 'main work\n' > main-work.txt
  git add main-work.txt
  git commit -q -m "main moves on"
  hk_tick
  git push -q origin main
  hk_tick
  git checkout -q task/remoteff
  git merge -q --ff-only main
  hk_tick
  git push -q origin task/remoteff
  git checkout -q main
  git branch -q -D task/remoteff
  fixture_task remoteff "task/remoteff" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "remoteff status=consolidated remote=unknown"
}

test_housekeeping_no_reflog_for_branch_stays_unknown() {
  # core.logAllRefUpdates is turned off before the branch exists, so its ref
  # never gets a reflog: its own commits cannot be told from the base's.
  hk_setup
  git config core.logAllRefUpdates false
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/noreflog
  rm -f .git/logs/refs/heads/task/noreflog
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  rm -f .git/logs/refs/heads/task/noreflog
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/noreflog" task/noreflog
  fixture_task noreflog "task/noreflog" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_contains "$OUT" "noreflog status=consolidated remote=unknown"
  assert_contains "$OUT" \
    "no reflog for its branch, so its own commits cannot be told from main's: noreflog"
}

# --- tasks cut from a base other than the project's default (ADR-0038) --------

test_housekeeping_two_task_bases_in_one_run_both_merged_by_ancestry() {
  # Task a lands on the project's default base; task b lands on its own
  # epic base. Neither is main, so each has to be judged against its own.
  hk_setup
  local fork_main fork_epic
  fork_main=$(git rev-parse HEAD)
  hk_tick
  git branch epic/x
  fork_epic=$(git rev-parse epic/x)

  hk_tick
  git checkout -q -b task/a
  printf 'a\n' > a.txt
  git add a.txt
  hk_tick
  git commit -q -m "task a work"
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/a" task/a

  hk_tick
  git checkout -q -b task/b epic/x
  printf 'b\n' > b.txt
  git add b.txt
  hk_tick
  git commit -q -m "task b work"
  hk_tick
  git checkout -q epic/x
  git merge -q --no-ff -m "merge task/b into epic/x" task/b
  git checkout -q main

  fixture_task a "task/a" consolidated "base_commit:$fork_main"
  fixture_task b "task/b" consolidated "base_branch:epic/x" "base_commit:$fork_epic"

  # a lands on main, the project's default base, and is purged as before; b
  # lands on epic/x, which has not itself reached main, so it is judged
  # merged against its own base (the purpose of this test) but kept rather
  # than purged (ADR-0039: a phase's workspace survives until its epic does).
  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "a status=consolidated remote=merged via=ancestry action=purge"
  assert_contains "$OUT" "b status=consolidated remote=merged via=ancestry action=preserve flags=base-unreleased"
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/a/state"
  assert_dir .ai/workspace/tasks/b
}

# --- released: a phase's workspace waits for its epic to reach main (ADR-0039) -

test_housekeeping_phase_merged_into_epic_only_waits_for_the_epic_to_reach_main() {
  hk_setup
  local fork_epic
  git branch epic/x
  fork_epic=$(git rev-parse epic/x)
  hk_tick
  git checkout -q -b task/b epic/x
  printf 'b\n' > b.txt
  git add b.txt
  hk_tick
  git commit -q -m "task b work"
  hk_tick
  git checkout -q epic/x
  git merge -q --no-ff -m "merge task/b into epic/x" task/b
  git checkout -q main

  fixture_task b "task/b" consolidated "base_branch:epic/x" "base_commit:$fork_epic"

  run jig housekeeping
  assert_eq 0 "$RC"
  assert_contains "$OUT" "waiting for merge (1): consolidated, pull request still open"
  assert_contains "$OUT" "waiting for epic/x to reach main: b"
  assert_dir .ai/workspace/tasks/b
}

test_housekeeping_phase_merged_into_epic_purges_once_the_epic_reaches_main_by_ancestry() {
  hk_setup
  local fork_epic
  git branch epic/x
  fork_epic=$(git rev-parse epic/x)
  hk_tick
  git checkout -q -b task/b epic/x
  printf 'b\n' > b.txt
  git add b.txt
  hk_tick
  git commit -q -m "task b work"
  hk_tick
  git checkout -q epic/x
  git merge -q --no-ff -m "merge task/b into epic/x" task/b
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge epic/x into main" epic/x

  fixture_task b "task/b" consolidated "base_branch:epic/x" "base_commit:$fork_epic"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "b status=consolidated remote=merged via=ancestry action=purge"
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/b/state"
}

test_housekeeping_forge_merged_pr_from_epic_to_main_purges_the_phase() {
  hk_setup
  hk_cfg forge github
  local fork_epic
  git branch epic/x
  fork_epic=$(git rev-parse epic/x)
  hk_tick
  git checkout -q -b task/b epic/x
  printf 'b\n' > b.txt
  git add b.txt
  hk_tick
  git commit -q -m "task b work"
  hk_tick
  git checkout -q epic/x
  git merge -q --no-ff -m "merge task/b into epic/x" task/b
  git checkout -q main
  # Only the epic's own pull request into main is in the forge listing; the
  # task's branch has no pull request of its own, so it reads as merged by
  # ancestry into the epic, and released comes from the epic's forge PR.
  hk_stub_gh "epic/x$(printf '\t')main$(printf '\t')MERGED"
  fixture_task b "task/b" consolidated "base_branch:epic/x" "base_commit:$fork_epic"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "b status=consolidated remote=merged via=ancestry action=purge"
  assert_file ".ai/runtime/trash/$(date +%Y-%m-%d)/b/state"
}

test_housekeeping_forge_configured_without_the_epic_pr_and_no_ancestry_keeps_the_phase() {
  hk_setup
  hk_cfg forge github
  local fork_epic
  git branch epic/x
  fork_epic=$(git rev-parse epic/x)
  hk_tick
  git checkout -q -b task/b epic/x
  printf 'b\n' > b.txt
  git add b.txt
  hk_tick
  git commit -q -m "task b work"
  hk_tick
  git checkout -q epic/x
  git merge -q --no-ff -m "merge task/b into epic/x" task/b
  git checkout -q main
  # A forge is configured, but neither the epic's pull request nor its
  # ancestry into main answers "released" — kept rather than guessed.
  hk_stub_gh "unrelated$(printf '\t')main$(printf '\t')MERGED"
  fixture_task b "task/b" consolidated "base_branch:epic/x" "base_commit:$fork_epic"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "b status=consolidated remote=merged via=ancestry action=preserve flags=base-unreleased"
  assert_dir .ai/workspace/tasks/b
}

test_housekeeping_branch_equals_its_own_non_default_base_is_unknown() {
  # The same tautology test_housekeeping_task_on_the_base_branch_is_unknown_
  # not_merged guards against for main, for a task whose base is an epic.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  git branch epic/x
  fixture_task onepic "epic/x" consolidated "base_branch:epic/x" "base_commit:$fork"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "onepic status=consolidated remote=unknown via=none action=preserve"
  assert_not_contains "$OUT" "flags=wrong-base"
  assert_dir .ai/workspace/tasks/onepic
}

test_housekeeping_own_work_reflog_uses_the_tasks_base_not_main() {
  # ADR-0032's own-work guard, now per base: a branch fast-forwarded onto its
  # epic with no commits of its own must stay unknown, even though main's
  # reflog — the only one the old, single-base code read — knows nothing
  # about the epic's commits at all.
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git branch epic/x
  hk_tick
  git checkout -q -b task/ff epic/x
  hk_tick
  git checkout -q epic/x
  printf 'epic work\n' > epic-work.txt
  git add epic-work.txt
  hk_tick
  git commit -q -m "epic moves on"
  hk_tick
  git checkout -q task/ff
  git merge -q --ff-only epic/x
  git checkout -q main
  fixture_task ff "task/ff" ready "base_branch:epic/x" "base_commit:$fork"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ff status=ready remote=unknown"
  assert_not_contains "$OUT" "flags=needs-consolidation"
}

test_housekeeping_ancestry_merged_into_default_base_flags_wrong_base() {
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git branch epic/x
  hk_tick
  git checkout -q -b task/wb epic/x
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/wb into main" task/wb
  fixture_task wb "task/wb" consolidated "base_branch:epic/x" "base_commit:$fork"

  run jig housekeeping --verbose
  assert_eq 3 "$RC"
  assert_contains "$OUT" "remote=unknown via=ancestry"
  assert_contains "$OUT" "flags=wrong-base"
  assert_contains "$OUT" "  its branch is merged into main, not epic/x: wb"
  assert_dir .ai/workspace/tasks/wb

  run jig status
  assert_contains "$OUT" "wrong base: 1 task(s)"
}

test_housekeeping_ancestry_no_wrong_base_when_the_epic_ref_is_gone() {
  # Asked only while the task's own base still resolves: with it gone, "not
  # on the base" is nothing more than "the base is not here".
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/gone
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/gone into main" task/gone
  fixture_task gone "task/gone" consolidated "base_branch:epic/nonexistent" "base_commit:$fork"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "remote=unknown via=none"
  assert_not_contains "$OUT" "flags=wrong-base"
}

test_housekeeping_task_without_a_base_branch_field_never_flags_wrong_base() {
  # Every workspace from before this field existed carries no base_branch
  # line; jig_task_base falls back to the configured base and nothing here
  # is new behaviour.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ff status=consolidated remote=merged via=ancestry action=purge"
  assert_not_contains "$OUT" "flags=wrong-base"
}

# --- what a purged task leaves behind ----------------------------------------
# The purge is the last moment a task's own attributes exist anywhere: the
# workspace is about to move to trash and be erased (ADR-0006). Recording them
# on the line that removes it is what lets `jig measure` count a task nobody
# can open any more.

test_housekeeping_purge_line_records_the_task_facts() {
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated class:T2 knowledge_consolidated:true

  run jig housekeeping
  assert_file_contains .ai/runtime/housekeeping.log "task=ff"
  assert_file_contains .ai/runtime/housekeeping.log "class=T2"
  assert_file_contains .ai/runtime/housekeeping.log "consolidated=true"
  assert_file_contains .ai/runtime/housekeeping.log "created="
}

test_housekeeping_purge_line_omits_a_fact_the_state_does_not_carry() {
  # An absent value is left out rather than defaulted, so a reader can tell
  # "this task had no class" from "this line predates the field".
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated

  run jig housekeeping
  assert_file_contains .ai/runtime/housekeeping.log "action=purge"
  if grep -q "class=" .ai/runtime/housekeeping.log; then
    fail "a task with no class must not produce a class= field"
  fi
}

test_housekeeping_preserve_line_carries_no_facts() {
  # Only the purge line needs them: a preserved task is re-reported on every
  # run, and repeating its attributes daily would bloat the log for nothing.
  hk_setup
  fixture_task live "no-such-branch" active class:T3

  run jig housekeeping
  assert_file_contains .ai/runtime/housekeeping.log "action=preserve"
  if grep -q "class=T3" .ai/runtime/housekeeping.log; then
    fail "a preserve line must not carry task facts"
  fi
}

test_housekeeping_facts_are_logged_not_printed() {
  # stdout is for a human reading one run; the facts are for a reader counting
  # tasks months later.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated class:T2

  run jig housekeeping --verbose
  assert_contains "$OUT" "action=purge"
  assert_not_contains "$OUT" "class=T2"
}

# --- task worktrees (ADR-0029) -------------------------------------------------

# hk_worktree_task <id> — a task started in its own worktree, committed to and
# fast-forwarded into main, then consolidated: the case housekeeping purges.
# The project is put one level down so the default worktree root lands inside
# the test's temporary directory. Prints the worktree path.
hk_worktree_setup() {
  mkdir repo || return 1
  cd repo || return 1
  hk_setup
  git add -A
  git commit -q -m "jig init snapshot"
}

hk_worktree_task() {
  local id="$1" wt
  jig task new "$id" >/dev/null
  hk_tick
  wt=$(jig task start "$id" --worktree 2>/dev/null)
  printf 'work\n' > "$wt/$id.txt"
  git -C "$wt" add "$id.txt"
  hk_tick
  git -C "$wt" commit -q -m "work for $id"
  hk_tick
  git merge -q --ff-only "task/$id"
  jig task set "$id" knowledge_consolidated true >/dev/null
  jig task set "$id" status consolidated >/dev/null
  printf '%s\n' "$wt"
}

test_housekeeping_removes_the_worktree_of_a_purged_task() {
  hk_worktree_setup
  local wt
  wt=$(hk_worktree_task T-1)

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "remove worktree $wt"
  assert_contains "$OUT" "T-1 status=consolidated remote=merged via=ancestry action=purge"
  assert_no_file "$wt"
  assert_no_file .ai/workspace/tasks/T-1
  # The commits outlive the worktree: the branch is not housekeeping's.
  git rev-parse --verify --quiet refs/heads/task/T-1 >/dev/null || fail "the task branch was deleted"
  assert_file_contains .ai/runtime/housekeeping.log "task=T-1 worktree=$wt action=remove"
}

test_housekeeping_keeps_a_worktree_with_uncommitted_work_and_its_workspace() {
  # Agents do not commit: uncommitted work in a task worktree is the normal
  # state before review. git refuses to remove it, and the workspace stays
  # with it rather than leaving the worktree's link dangling.
  hk_worktree_setup
  local wt
  wt=$(hk_worktree_task T-1)
  printf 'not reviewed yet\n' > "$wt/draft.txt"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "worktree $wt kept (uncommitted-changes)"
  assert_contains "$OUT" "T-1 status=consolidated remote=merged via=ancestry action=preserve flags=worktree-kept"
  assert_file "$wt/draft.txt"
  assert_file .ai/workspace/tasks/T-1/state

  run jig status
  assert_contains "$OUT" "worktrees kept: 1 task(s)"

  run jig housekeeping
  assert_contains "$OUT" "needs you (1):"
  assert_contains "$OUT" "  worktree kept, it has uncommitted changes ($wt): T-1"
}

test_housekeeping_keeps_a_worktree_holding_a_workspace_of_its_own() {
  # `git worktree remove` deletes ignored files without a word, and a real
  # workspace inside the worktree is one this checkout knows nothing about.
  hk_worktree_setup
  local wt
  wt=$(hk_worktree_task T-1)
  mkdir -p "$wt/.ai/workspace/tasks/filed-there"
  printf 'task_id: filed-there\n' > "$wt/.ai/workspace/tasks/filed-there/state"

  run jig housekeeping --verbose
  assert_contains "$OUT" "worktree $wt kept (own-workspace)"
  assert_file "$wt/.ai/workspace/tasks/filed-there/state"
  assert_file .ai/workspace/tasks/T-1/state
}

# hk_foreign_worktree_task <id> — the task's branch checked out in a worktree
# jig did not create (`../manual`, beside the default root), committed to,
# fast-forwarded into main and closed: how an agent runtime's own session
# worktree looks once a task was started inside it.
hk_foreign_worktree_task() {
  local id="$1"
  # The root exists, so what decides is the path check, not a missing root.
  mkdir -p ../repo.worktrees
  jig task new "$id" >/dev/null
  hk_tick
  git worktree add -q -b "task/$id" ../manual main
  sed "s|^created_at:|branch: task/$id\nbase_commit: $(git rev-parse main)\ncreated_at:|" \
    ".ai/workspace/tasks/$id/state" > ../s.tmp
  mv ../s.tmp ".ai/workspace/tasks/$id/state"
  printf 'work\n' > "../manual/$id.txt"
  git -C ../manual add "$id.txt"
  hk_tick
  git -C ../manual commit -q -m "work"
  hk_tick
  git merge -q --ff-only "task/$id"
  jig task set "$id" knowledge_consolidated true >/dev/null
  jig task set "$id" status consolidated >/dev/null
}

test_housekeeping_leaves_a_clean_foreign_worktree_and_purges_the_workspace() {
  # A worktree somebody made by hand, or a runtime made for its session, is
  # never touched. Clean and unlocked, it no longer holds the workspace back:
  # otherwise the task sits under "needs you" on every run until a person
  # removes a tree jig does not own (ADR-0029 as amended).
  hk_worktree_setup
  hk_foreign_worktree_task T-1
  local wt
  wt=$(cd -P ../manual && pwd -P)

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "worktree $wt left in place (outside-worktree-root)"
  assert_contains "$OUT" "T-1 status=consolidated remote=merged via=ancestry action=purge"
  assert_file ../manual/T-1.txt
  assert_no_file .ai/workspace/tasks/T-1
  assert_file_contains .ai/runtime/housekeeping.log "task=T-1 worktree=$wt action=leave reason=outside-worktree-root"

  run jig housekeeping
  assert_not_contains "$OUT" "needs you"
}

test_housekeeping_keeps_the_workspace_of_a_foreign_worktree_with_uncommitted_work() {
  hk_worktree_setup
  hk_foreign_worktree_task T-1
  local wt
  wt=$(cd -P ../manual && pwd -P)
  printf 'not reviewed yet\n' > ../manual/draft.txt

  run jig housekeeping --verbose
  assert_contains "$OUT" "worktree $wt kept (uncommitted-changes)"
  assert_contains "$OUT" "T-1 status=consolidated remote=merged via=ancestry action=preserve flags=worktree-kept"
  assert_file ../manual/draft.txt
  assert_file .ai/workspace/tasks/T-1/state
}

test_housekeeping_keeps_the_workspace_of_a_locked_foreign_worktree() {
  # Claude Code locks the worktree of a running agent: a live session is not
  # the moment to take the task's context away.
  hk_worktree_setup
  hk_foreign_worktree_task T-1
  local wt
  wt=$(cd -P ../manual && pwd -P)
  git worktree lock ../manual

  run jig housekeeping --verbose
  assert_contains "$OUT" "worktree $wt kept (locked)"
  assert_file .ai/workspace/tasks/T-1/state

  run jig housekeeping
  assert_contains "$OUT" "  worktree kept, it is locked, a session may still be using it ($wt): T-1"
}

test_housekeeping_dry_run_removes_no_worktree() {
  hk_worktree_setup
  local wt
  wt=$(hk_worktree_task T-1)

  run jig housekeeping --dry-run --verbose
  assert_contains "$OUT" "would-remove worktree $wt"

  run jig housekeeping --dry-run
  assert_contains "$OUT" "  worktree would be removed: T-1"
  assert_file "$wt/T-1.txt"
  assert_file .ai/workspace/tasks/T-1/state
}

test_housekeeping_inside_a_worktree_leaves_the_borrowed_workspace_alone() {
  # The worktree's link is not a workspace it owns. Housekeeping there must
  # neither purge through it nor move the link: the owner decides.
  hk_worktree_setup
  local wt
  wt=$(hk_worktree_task T-1)

  set +e
  OUT=$(cd "$wt" && jig housekeeping 2>&1)
  RC=$?
  set -e
  assert_eq 0 "$RC"
  assert_contains "$OUT" "no task workspaces"
  [ -L "$wt/.ai/workspace/tasks/T-1" ] || fail "the link was moved"
  assert_file .ai/workspace/tasks/T-1/state
}

# --- the checkout guard (a purge target checked out in this checkout) -------
# `_task_worktrees` never lists the checkout housekeeping itself runs from, so
# a task whose branch is checked out right here, not in a worktree, needs its
# own guard: uncommitted changes on that branch are most likely the task's
# own, and a `merged` verdict must not take the workspace from beside them.

test_housekeeping_guard_keeps_this_checkout_with_uncommitted_changes_on_the_purged_branch() {
  hk_setup
  local fork proj
  fork=$(git rev-parse HEAD)
  proj=$(git rev-parse --show-toplevel)
  hk_tick
  git checkout -q -b task/here
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/here" task/here
  hk_tick
  git checkout -q task/here
  fixture_task t "task/here" consolidated "base_commit:$fork"
  printf 'not reviewed yet\n' > uncommitted.txt

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "checkout $proj kept (uncommitted-changes)"
  assert_contains "$OUT" \
    "t status=consolidated remote=merged via=ancestry action=preserve flags=worktree-kept"
  assert_contains "$OUT" "needs you (1):"
  assert_contains "$OUT" "  this checkout has uncommitted changes on the task's branch: t"
  assert_dir .ai/workspace/tasks/t
  assert_file_contains .ai/runtime/housekeeping.log \
    "task=t worktree=$proj action=keep reason=uncommitted-changes"

  run jig status
  assert_contains "$OUT" "worktrees kept: 1 task(s)"
}

test_housekeeping_guard_does_not_block_a_clean_checkout_on_the_purged_branch() {
  # A fixture repo from hk_setup may already have untracked files; commit
  # everything first so the branch checked out here is genuinely clean, the
  # way hk_worktree_setup does for the same reason.
  mkdir repo
  cd repo
  hk_setup
  git add -A
  git commit -q -m "jig init snapshot"
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/here-clean
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/here-clean" task/here-clean
  hk_tick
  git checkout -q task/here-clean
  fixture_task t "task/here-clean" consolidated "base_commit:$fork"

  run jig housekeeping --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "t status=consolidated remote=merged via=ancestry action=purge"
  assert_no_file .ai/workspace/tasks/t
}

test_housekeeping_dry_run_guard_writes_no_log() {
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  hk_tick
  git checkout -q -b task/here-dry
  printf 'own\n' > own.txt
  git add own.txt
  hk_tick
  git commit -q -m "own work"
  hk_tick
  git checkout -q main
  git merge -q --no-ff -m "merge task/here-dry" task/here-dry
  hk_tick
  git checkout -q task/here-dry
  fixture_task t "task/here-dry" consolidated "base_commit:$fork"
  printf 'not reviewed yet\n' > uncommitted.txt

  run jig housekeeping --dry-run --verbose
  assert_eq 0 "$RC"
  assert_contains "$OUT" "action=preserve flags=worktree-kept"
  assert_no_file .ai/runtime/housekeeping.log
}

# --- the grouped report -------------------------------------------------------

test_housekeeping_report_groups_tasks_by_outcome() {
  hk_setup
  fixture_merge_repo
  fixture_task done-a "ff-merged" consolidated
  fixture_task todo "commit-merged" active
  fixture_task wip "no-such-branch" active
  fixture_task trunk "main" consolidated
  fixture_task gone "gone-merged" consolidated
  fixture_task old "no-such-branch" abandoned "updated_at:$(hk_days_ago 3)"

  run jig housekeeping
  assert_eq 3 "$RC"
  assert_contains "$OUT" "needs you (1):"
  assert_contains "$OUT" "  merged but not consolidated, run jig-consolidate: todo"
  assert_contains "$OUT" "removed (1): moved to .ai/runtime/trash/$(date +%Y-%m-%d)/, recoverable for 7 days"
  assert_contains "$OUT" "in progress (1):"
  assert_contains "$OUT" "kept, cannot tell whether it landed (2):"
  assert_contains "$OUT" "  worked on main directly, which leaves no trace of landing: trunk"
  assert_contains "$OUT" "  its branch gone-merged no longer exists: gone"
  assert_contains "$OUT" "abandoned, waiting to expire (1):"
  assert_contains "$OUT" "  expires in 12 days: old"
  # The per-task decision lines are for --verbose only.
  assert_not_contains "$OUT" "status="

  # What needs a person comes first, then what happened, then what is kept.
  local order
  order=$(printf '%s\n' "$OUT" | grep -oE '^(needs you|removed|in progress|kept, cannot tell|abandoned, waiting)' | tr '\n' '|')
  assert_eq "needs you|removed|in progress|kept, cannot tell|abandoned, waiting|" "$order"
}

test_housekeeping_report_lists_tasks_sharing_a_note_together() {
  hk_setup
  fixture_task a "main" consolidated
  fixture_task b "main" consolidated
  fixture_task c "main" consolidated

  run jig housekeeping
  assert_contains "$OUT" "kept, cannot tell whether it landed (3):"
  assert_contains "$OUT" "  worked on main directly, which leaves no trace of landing: a, b, c"
}

test_housekeeping_report_wraps_a_long_group() {
  hk_setup
  local i
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
    fixture_task "a-task-in-progress-$i" "no-such-branch" active
  done

  run jig housekeeping
  assert_contains "$OUT" "in progress (12):"
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
    assert_contains "$OUT" "a-task-in-progress-$i"
  done
  local longest
  longest=$(printf '%s\n' "$OUT" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
  [ "$longest" -le 88 ] || fail "a report line is $longest characters wide"
}

test_housekeeping_report_says_why_a_branch_cannot_tell() {
  hk_setup
  local fork
  fork=$(git rev-parse HEAD)
  git branch task/fresh
  git checkout -q -b task/open
  printf 'work\n' > work.txt
  git add work.txt
  git commit -q -m "task work"
  git checkout -q main
  fixture_task fresh "task/fresh" consolidated "base_commit:$fork"
  fixture_task op "task/open" consolidated "base_commit:$fork"
  fixture_task never "" consolidated

  run jig housekeeping
  assert_contains "$OUT" "  its branch has no commits since the task started: fresh"
  assert_contains "$OUT" "  no sign that its branch landed on main: op"
  assert_contains "$OUT" "  never started, so there is no branch to check: never"
}

test_housekeeping_report_cannot_be_mistaken_for_log_lines() {
  # The session hook and the scheduler templates append stdout to the log that
  # `jig status` and `jig measure` read by `task=` fields and `--- run` markers.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated
  fixture_task todo "commit-merged" active

  run jig housekeeping --verbose
  assert_not_contains "$OUT" "task="
  if printf '%s\n' "$OUT" | grep -q '^--- run '; then
    fail "the report prints a line the log reader takes for a run marker"
  fi
}

test_housekeeping_report_appended_to_the_log_changes_no_count() {
  # Run the way the session hook runs it: the report goes into the same log
  # as the audit lines. It purges one task and flags one; each must be counted
  # exactly once by the readers of the log.
  hk_setup
  fixture_merge_repo
  fixture_task ff "ff-merged" consolidated
  fixture_task todo "commit-merged" active

  jig housekeeping --verbose >> .ai/runtime/housekeeping.log 2>&1 || true
  assert_file_contains .ai/runtime/housekeeping.log "ff status=consolidated remote=merged via=ancestry action=purge"
  run jig status
  assert_contains "$OUT" "needs consolidation: 1 task(s)"
  run jig measure
  # Counted once: the report line in the log carries no `task=` field.
  assert_contains "$OUT" "2 tasks (1 live, 1 recorded at purge)"
}

