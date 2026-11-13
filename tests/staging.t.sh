# Tests for `jig staging ack` (scripts/lib/staging.sh;
# adr-20261113-staging-work-is-reported-to-its-own-author-until-acknowledged):
# the person's own commits on the staging branch that no live task branch holds
# are named by `jig status` until acknowledged, by content, in this clone only.
# shellcheck shell=bash

# _sg_commit <message> [<file>] — a commit straight onto origin's staging
# branch, by the test's author unless GIT_AUTHOR_* say otherwise, fetched back.
_sg_commit() {
  local f="${2:-${1// /-}.txt}"
  git checkout -q -B staging origin/staging
  printf '%s\n' "$1" > "$f"
  git add "$f"
  git commit -q -m "$1"
  git push -q origin staging
  git checkout -q main
  git branch -D -q staging
  git fetch -q origin
}

test_staging_ack_silences_what_it_acknowledged_and_names_what_is_new() {
  fixture_staging_repo
  _sg_commit "first fix"
  _sg_commit "second fix"
  run jig staging ack --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "second fix"
  assert_contains "$OUT" "first fix"
  assert_contains "$OUT" "staging: 2 commit(s) of yours on staging would be acknowledged (jig staging ack)"
  assert_no_file .ai/runtime/staging-acked "a dry run writes nothing"
  run jig staging ack
  assert_eq 0 "$RC"
  assert_contains "$OUT" "staging: 2 commit(s) of yours on staging acknowledged; jig status names only new ones"
  assert_file .ai/runtime/staging-acked
  run jig status
  assert_not_contains "$OUT" "of yours on staging"
  run jig staging ack
  assert_eq 0 "$RC"
  assert_contains "$OUT" "staging: nothing of yours on staging to acknowledge"
  # A new commit of one's own is named again, alone.
  _sg_commit "third fix"
  run jig status
  assert_contains "$OUT" "staging: 1 commit(s) of yours on staging"
  run jig status --json
  assert_contains "$OUT" '"staging":{"commits":1,"list":[{"sha":"'"$(git rev-parse origin/staging)"'","subject":"third fix"'
  assert_not_contains "$OUT" "first fix"
  assert_contains "$OUT" '"ack":"jig staging ack --expect 1"'
  # A commit that arrived after the read refuses the ack the reader was shown.
  _sg_commit "fourth fix"
  run jig staging ack --expect 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "staging ack: 2 commit(s) of yours on staging now, not 1; read jig status again"
  run jig status
  assert_contains "$OUT" "staging: 2 commit(s) of yours on staging"
  run jig staging ack --expect 2
  assert_eq 0 "$RC"
  run jig staging ack --expect 0
  assert_eq 0 "$RC"
  assert_contains "$OUT" "nothing of yours on staging to acknowledge"
}

# By content: a rebase or cherry-pick on the staging branch gives the same
# change a new sha, and it stays acknowledged. A commit with no diff has no
# patch-id and is acknowledged by its sha.
test_staging_ack_holds_across_a_rewrite_of_staging() {
  fixture_staging_repo
  _sg_commit "a fix"
  git checkout -q -B staging origin/staging
  git commit -q --allow-empty -m "an empty note"
  git push -q origin staging
  git checkout -q main
  git branch -D -q staging
  git fetch -q origin
  run jig status
  assert_contains "$OUT" "staging: 2 commit(s) of yours on staging"
  run jig staging ack
  assert_eq 0 "$RC"
  run jig status
  assert_not_contains "$OUT" "of yours on staging"
  # Staging rewritten: the fix cherry-picked anew on top of its parent.
  local fix
  fix=$(git rev-parse origin/staging~1)
  git checkout -q -B staging "origin/staging~2"
  printf 'unrelated\n' > unrelated.txt
  git add unrelated.txt
  GIT_AUTHOR_NAME=colleague GIT_AUTHOR_EMAIL=colleague@test git commit -q -m "a colleague first"
  git cherry-pick "$fix" >/dev/null 2>&1
  git push -q -f origin staging
  git checkout -q main
  git branch -D -q staging
  git fetch -q origin
  [ "$(git log -1 --format=%s origin/staging)" = "a fix" ] || fail "fixture: the fix was not replayed"
  [ "$(git rev-parse origin/staging)" != "$fix" ] || fail "fixture: the fix kept its sha"
  run jig status
  assert_not_contains "$OUT" "of yours on staging"
}

# An acknowledgement made in a task worktree is the clone's: the main checkout
# reads the same file.
test_staging_ack_from_a_worktree_is_seen_by_the_main_checkout() {
  mkdir repo || return 1
  cd repo || return 1
  fixture_staging_repo
  git add -A
  git commit -q -m "tasks" >/dev/null 2>&1 || true
  _sg_commit "a fix"
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  [ -d "$wt" ] || fail "no worktree"
  run jig status
  assert_contains "$OUT" "staging: 1 commit(s) of yours on staging"
  (cd "$wt" && jig staging ack >/dev/null) || fail "ack in the worktree failed"
  run jig status
  assert_not_contains "$OUT" "of yours on staging"
}

test_staging_ack_refuses_off_the_staging_flow_and_bad_arguments() {
  fixture_jig_repo
  run jig staging ack
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not on a sound staging flow"
  run jig staging
  assert_contains "$OUT" "usage: jig staging ack [--dry-run] [--expect <n>]"
  run jig staging ack --all
  assert_contains "$OUT" "unexpected argument: --all"
  run jig staging list
  assert_contains "$OUT" "staging: unknown subcommand: list"
  run jig staging ack --expect
  assert_contains "$OUT" "staging ack: --expect needs a count"
  run jig staging ack --expect many
  assert_contains "$OUT" "--expect takes a count, not 'many'"
}

# A name is matched as written: a backslash in it is no escape.
test_staging_matches_a_name_with_a_backslash() {
  fixture_staging_repo
  export GIT_AUTHOR_NAME='CORP\ivan'
  _sg_commit "a fix"
  GIT_AUTHOR_EMAIL=elsewhere@test _sg_commit "another fix"
  run jig status
  assert_contains "$OUT" "staging: 2 commit(s) of yours on staging"
}
