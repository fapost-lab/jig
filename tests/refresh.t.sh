# Tests for `jig refresh` (scripts/lib/refresh.sh; adr-20261112-refresh-brings-the-clone-up-to-origin):
# fetch origin, then fast-forward the base branch, never over a person's changes and never
# moving their checkout when the base is not what is checked out. Also the two readers it
# shares with `jig status`: jig_origin_fetched_at and jig_origin_counts (scripts/lib/common.sh).
# shellcheck shell=bash

# _rf_repo — an installed project, everything committed on main, with a bare `origin.git`
# holding main and a second clone `other/` to move origin from. The bare repository and the
# clone are excluded from git's view, so that a clean checkout reads clean.
_rf_repo() {
  fixture_jig_repo
  printf 'one\n' > shared.txt
  git add -A >/dev/null
  git commit -q -m "shared"
  printf 'origin.git/\nother/\n' >> .git/info/exclude
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  git clone -q origin.git other
}

# _rf_advance [file] — origin's main gains a commit that rewrites <file> (shared.txt) and
# adds fresh.txt.
_rf_advance() {
  local f="${1:-shared.txt}"
  (
    cd other || exit 1
    printf 'two\n' > "$f"
    printf 'new\n' > fresh.txt
    git add -A >/dev/null
    git -c user.name=t -c user.email=t@t commit -q -m "origin moves"
    git push -q origin HEAD:main
  )
}

# _rf_origin_sha — origin's main, as the bare repository has it.
_rf_origin_sha() {
  git --git-dir=origin.git rev-parse refs/heads/main
}

# --- the outcomes ---------------------------------------------------------------

test_refresh_in_step_with_origin_is_up_to_date() {
  _rf_repo
  local sha
  sha=$(git rev-parse main)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"data":{"fetch":{"outcome":"done","message":null,"fetched_at":"'
  assert_contains "$OUT" "\"base\":{\"name\":\"main\",\"outcome\":\"up-to-date\",\"from\":\"$sha\",\"to\":\"$sha\",\"checked_out_in\":null,\"message\":null},\"writes\":[]}}"
  assert_eq "$sha" "$(git rev-parse main)"
}

test_refresh_fast_forwards_the_checked_out_base() {
  _rf_repo
  local old new
  old=$(git rev-parse main)
  _rf_advance
  new=$(_rf_origin_sha)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" "\"outcome\":\"fast-forwarded\",\"from\":\"$old\",\"to\":\"$new\",\"checked_out_in\":null,\"message\":null},\"writes\":[]}}"
  assert_eq "$new" "$(git rev-parse main)"
  assert_eq two "$(cat shared.txt)"
  assert_file fresh.txt
}

test_refresh_fetches_what_the_clone_has_not_seen() {
  _rf_repo
  _rf_advance
  assert_eq "$(_rf_origin_sha)" "$(git --git-dir=origin.git rev-parse refs/heads/main)"
  if [ "$(git rev-parse origin/main)" = "$(_rf_origin_sha)" ]; then
    fail "the fixture had fetched already"
  fi
  run jig refresh
  assert_eq 0 "$RC"
  assert_eq "$(_rf_origin_sha)" "$(git rev-parse origin/main)"
}

test_refresh_blocked_by_an_unstaged_change_to_a_file_the_move_touches() {
  _rf_repo
  local old
  old=$(git rev-parse main)
  _rf_advance
  printf 'mine\n' > shared.txt
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"blocked-by-changes"'
  assert_contains "$OUT" "\"from\":\"$old\",\"to\":\"$old\""
  assert_contains "$OUT" 'shared.txt'
  assert_eq "$old" "$(git rev-parse main)"
  assert_eq mine "$(cat shared.txt)"
  assert_no_file fresh.txt
}

test_refresh_blocked_by_a_staged_change_to_a_file_the_move_touches() {
  _rf_repo
  local old
  old=$(git rev-parse main)
  _rf_advance
  printf 'staged\n' > shared.txt
  git add shared.txt
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"blocked-by-changes"'
  assert_eq "$old" "$(git rev-parse main)"
  assert_eq staged "$(cat shared.txt)"
  assert_eq "shared.txt" "$(git diff --cached --name-only)"
}

test_refresh_blocked_by_an_untracked_file_the_move_would_create() {
  _rf_repo
  local old
  old=$(git rev-parse main)
  _rf_advance
  printf 'mine\n' > fresh.txt
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"blocked-by-changes"'
  assert_contains "$OUT" 'fresh.txt'
  assert_eq "$old" "$(git rev-parse main)"
  assert_eq mine "$(cat fresh.txt)"
}

test_refresh_moves_past_changes_it_does_not_touch() {
  _rf_repo
  local new
  printf 'mine\n' > README.md
  printf 'loose\n' > loose.txt
  printf 'staged\n' > staged.txt
  git add staged.txt
  _rf_advance
  new=$(_rf_origin_sha)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"fast-forwarded"'
  assert_eq "$new" "$(git rev-parse main)"
  assert_eq two "$(cat shared.txt)"
  assert_eq mine "$(cat README.md)"
  assert_eq loose "$(cat loose.txt)"
  assert_eq "staged.txt" "$(git diff --cached --name-only)"
}

test_refresh_moves_a_base_that_is_not_checked_out_without_moving_the_checkout() {
  _rf_repo
  local old new
  old=$(git rev-parse main)
  git checkout -q -b work
  printf 'mine\n' > work.txt
  git add work.txt
  git commit -q -m "work"
  printf 'dirty\n' >> work.txt
  printf 'loose\n' > loose.txt
  local head before
  head=$(git rev-parse HEAD)
  before=$(own_tree_snapshot)
  _rf_advance
  new=$(_rf_origin_sha)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" "\"outcome\":\"fast-forwarded\",\"from\":\"$old\",\"to\":\"$new\""
  assert_eq "$new" "$(git rev-parse main)"
  assert_eq "$head" "$(git rev-parse HEAD)"
  assert_eq work "$(git symbolic-ref --short HEAD)"
  assert_eq "$before" "$(own_tree_snapshot)"
  assert_eq one "$(cat shared.txt)"
  assert_no_file fresh.txt
}

test_refresh_leaves_a_base_checked_out_in_another_worktree() {
  _rf_repo
  local old wt
  old=$(git rev-parse main)
  git checkout -q -b work
  git worktree add -q "$PWD/wt-main" main
  wt=$(cd wt-main && pwd -P)
  printf 'wt-main/\n' >> .git/info/exclude
  _rf_advance
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"checked-out-elsewhere"'
  assert_contains "$OUT" "\"from\":\"$old\",\"to\":\"$old\""
  assert_contains "$OUT" '"checked_out_in":"'
  assert_contains "$OUT" 'wt-main'
  assert_eq "$old" "$(git rev-parse main)"
  assert_eq one "$(cat wt-main/shared.txt)"
  # Run in it, the base moves.
  ( cd "$wt" && run jig refresh --json && assert_contains "$OUT" '"outcome":"fast-forwarded"' )
  assert_eq "$(_rf_origin_sha)" "$(git rev-parse main)"
}

test_refresh_never_moves_a_base_with_commits_origin_lacks() {
  _rf_repo
  printf 'local\n' > local.txt
  git add local.txt
  git commit -q -m "local only"
  local ahead
  ahead=$(git rev-parse main)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"diverged"'
  assert_eq "$ahead" "$(git rev-parse main)"
}

test_refresh_never_moves_a_diverged_base() {
  _rf_repo
  printf 'local\n' > local.txt
  git add local.txt
  git commit -q -m "local only"
  local mine
  mine=$(git rev-parse main)
  _rf_advance
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"diverged"'
  assert_contains "$OUT" "\"from\":\"$mine\",\"to\":\"$mine\""
  assert_eq "$mine" "$(git rev-parse main)"
  assert_eq one "$(cat shared.txt)"
}

test_refresh_says_missing_when_origin_has_no_base() {
  _rf_repo
  git --git-dir=origin.git branch -m main trunk
  git --git-dir=origin.git symbolic-ref HEAD refs/heads/trunk
  git update-ref -d refs/remotes/origin/main
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"missing"'
  assert_contains "$OUT" '"message":"origin/main is not known here"'
  assert_contains "$OUT" '"fetch":{"outcome":"done"'
}

test_refresh_says_missing_when_there_is_no_local_base() {
  _rf_repo
  git checkout -q -b work
  git branch -D main >/dev/null 2>&1
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"missing"'
  assert_contains "$OUT" '"from":null,"to":null'
  assert_contains "$OUT" '"message":"there is no branch main here"'
}

test_refresh_follows_the_configured_base_branch() {
  _rf_repo
  sed -i.bak 's/^git.base_branch: main/git.base_branch: trunk/' .ai/config.yaml
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"base":{"name":"trunk","outcome":"missing"'
}

# --- the fetch ------------------------------------------------------------------

test_refresh_without_an_origin_skips_the_fetch_and_judges_the_base() {
  _rf_repo
  git remote remove origin
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"fetch":{"outcome":"skipped","message":"this clone has no origin","fetched_at":'
  assert_contains "$OUT" '"base":{"name":"main","outcome":"missing"'
}

test_refresh_a_failed_fetch_is_an_answer_and_the_base_is_judged_on_what_is_known() {
  _rf_repo
  git remote set-url origin "$PWD/nowhere.git"
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"fetch":{"outcome":"failed","message":"'
  assert_not_contains "$OUT" '"fetch":{"outcome":"failed","message":null'
  assert_contains "$OUT" '"outcome":"up-to-date"'
  run jig refresh
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'fetch: failed ('
  assert_contains "$OUT" 'main: up to date with origin/main'
}

# --- the clone's revision -------------------------------------------------------
#
# A refresh that changed what the clone knows of origin, or moved the base, raises the
# revision; one that changed neither leaves it, though the fetch's time moved
# (adr-20261112-refresh-brings-the-clone-up-to-origin). Read from the directory, as
# tests/json.t.sh does, so that no read of ours raises it.

# _rf_rev — the clone's revision: the highest numeric name in .ai/runtime/revision, or 0.
_rf_rev() {
  local n best=0 f
  for f in .ai/runtime/revision/[0-9]*; do
    [ -e "$f" ] || continue
    n=${f##*/}
    case "$n" in '' | *[!0-9]*) continue ;; esac
    [ "$n" -le "$best" ] || best=$n
  done
  printf '%s\n' "$best"
}

test_refresh_that_fast_forwards_the_base_raises_the_revision() {
  _rf_repo
  _rf_advance
  local before
  before=$(_rf_rev)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"fast-forwarded"'
  [ "$(_rf_rev)" -gt "$before" ] || fail "revision stayed at $before after a fast-forward"
}

test_refresh_that_fetched_news_of_a_base_it_cannot_move_raises_the_revision() {
  _rf_repo
  printf 'local\n' > local.txt
  git add local.txt
  git commit -q -m "local only"
  _rf_advance
  local before
  before=$(_rf_rev)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"diverged"'
  [ "$(_rf_rev)" -gt "$before" ] || fail "revision stayed at $before after origin/main moved"
}

test_refresh_moving_a_base_checked_out_elsewhere_raises_the_main_checkouts_revision() {
  _rf_repo
  git checkout -q -b work
  git worktree add -q "$PWD/wt-main" main
  printf 'wt-main/\n' >> .git/info/exclude
  _rf_advance
  git fetch -q origin
  local before
  before=$(_rf_rev)
  ( cd wt-main && run jig refresh --json && assert_contains "$OUT" '"outcome":"fast-forwarded"' )
  [ "$(_rf_rev)" -gt "$before" ] || fail "revision stayed at $before after the base moved in a worktree"
}

test_refresh_that_changed_nothing_leaves_the_revision() {
  _rf_repo
  run jig refresh
  local before
  before=$(_rf_rev)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"outcome":"up-to-date"'
  assert_eq "$before" "$(_rf_rev)"
}

test_refresh_with_a_failed_fetch_leaves_the_revision() {
  _rf_repo
  git remote set-url origin "$PWD/nowhere.git"
  run jig refresh
  local before
  before=$(_rf_rev)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"fetch":{"outcome":"failed"'
  assert_eq "$before" "$(_rf_rev)"
}

test_refresh_without_an_origin_leaves_the_revision() {
  _rf_repo
  git remote remove origin
  run jig refresh
  local before
  before=$(_rf_rev)
  run jig refresh --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"fetch":{"outcome":"skipped"'
  assert_eq "$before" "$(_rf_rev)"
}

# --- the forms ------------------------------------------------------------------

test_refresh_json_is_an_envelope_with_the_fetch_and_the_base() {
  _rf_repo
  run jig refresh --json
  assert_eq 0 "$RC"
  case "$OUT" in
    '{"schema":1,"revision":'[0-9]*',"generated_at":"'*'","data":{"fetch":{'*) ;;
    *) fail "not an envelope: $OUT" ;;
  esac
  assert_contains "$OUT" '"fetch":{"outcome":"done","message":null,"fetched_at":"'
  assert_contains "$OUT" '"base":{"name":"main","outcome":"up-to-date","from":"'
  assert_eq 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
}

test_refresh_text_form() {
  _rf_repo
  run jig refresh
  assert_eq 0 "$RC"
  assert_eq "fetch: done
main: up to date with origin/main" "$OUT"
  local old
  old=$(git rev-parse main)
  _rf_advance
  run jig refresh
  assert_eq 0 "$RC"
  assert_contains "$OUT" "main: fast-forwarded ${old:0:12}..$(_rf_origin_sha | cut -c1-12)"
  printf 'mine\n' > shared.txt
  git checkout -q -- shared.txt
  git reset -q --hard HEAD~1
  printf 'mine\n' > shared.txt
  run jig refresh
  assert_eq 0 "$RC"
  assert_contains "$OUT" "main: blocked-by-changes — "
}

test_refresh_refuses_an_unknown_argument_with_a_usage_code() {
  _rf_repo
  run jig refresh bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "refresh: unexpected argument: bogus; usage: jig refresh [--json]"
  run jig refresh bogus --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"usage","message":"refresh: unexpected argument: bogus'
}

test_refresh_help_prints_its_usage() {
  _rf_repo
  run jig refresh --help
  assert_eq 0 "$RC"
  assert_eq "usage: jig refresh [--json]" "$OUT"
}

# --- the readers it shares with status ------------------------------------------

test_origin_fetched_at_ignores_an_empty_fetch_head() {
  _rf_repo
  # Only a failed fetch shows: an empty FETCH_HEAD says nothing.
  : > .git/FETCH_HEAD
  JIG_PROJECT="$PWD"
  . "$JIG_HOME/scripts/lib/common.sh"
  if jig_origin_fetched_at >/dev/null; then
    fail "an empty FETCH_HEAD was read as a fetch"
  fi
  printf 'abc\t\tbranch main of origin\n' > .git/FETCH_HEAD
  touch -t 202601020304.05 .git/FETCH_HEAD
  assert_eq "$(TZ=UTC jig_utc_from_epoch "$(jig_file_mtime .git/FETCH_HEAD)")" "$(jig_origin_fetched_at)"
  # An empty, newer one in a worktree does not hide it.
  git worktree add -q "$PWD/wt" -b wtb
  printf 'wt/\n' >> .git/info/exclude
  : > .git/worktrees/wt/FETCH_HEAD
  assert_eq "$(jig_utc_from_epoch "$(jig_file_mtime .git/FETCH_HEAD)")" "$(jig_origin_fetched_at)"
  # A non-empty newer one in a worktree wins.
  printf 'abc\t\tbranch main of origin\n' > .git/worktrees/wt/FETCH_HEAD
  touch -t 202602030405.06 .git/worktrees/wt/FETCH_HEAD
  assert_eq "$(jig_utc_from_epoch "$(jig_file_mtime .git/worktrees/wt/FETCH_HEAD)")" "$(jig_origin_fetched_at)"
}

test_origin_counts_are_behind_and_ahead_or_nothing() {
  _rf_repo
  # shellcheck disable=SC2034 # read by common.sh, sourced next
  JIG_PROJECT="$PWD"
  . "$JIG_HOME/scripts/lib/common.sh"
  assert_eq "0 0" "$(jig_origin_counts main)"
  _rf_advance
  git fetch -q origin
  assert_eq "1 0" "$(jig_origin_counts main)"
  printf 'l\n' > l.txt
  git add l.txt
  git commit -q -m l
  assert_eq "1 1" "$(jig_origin_counts main)"
  if jig_origin_counts nope >/dev/null; then fail "a missing branch has counts"; fi
}
