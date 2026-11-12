# Tests for writes in Jig's own tree (scripts/lib/owntree.sh, scripts/lib/writes.sh;
# adr-20261104-a-write-goes-in-jigs-own-tree): the branch, the level, what holds a
# write off, and what a reader sees. The writers themselves are in spec.t.sh and
# knowledge.t.sh.
# shellcheck shell=bash

_w_add() {
  run jig spec item add idea-x --phase 2 --text "$1" --json
}

# --- the level ------------------------------------------------------------------

test_writes_at_none_are_refused_with_a_code_and_nothing_done() {
  own_tree_repo none
  local before
  before=$(own_tree_snapshot)
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"git-not-allowed"'
  assert_contains "$OUT" "jig config set --local agent.git commit"
  assert_eq "$before" "$(own_tree_snapshot)"
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a branch was cut at none"
  fi
  own_tree_gone
}

test_writes_ignore_agent_git_in_the_project_config() {
  own_tree_repo none
  printf 'agent.git: pr\n' >> .ai/config.yaml
  _w_add "New"
  assert_contains "$OUT" '"code":"git-not-allowed"'
}

test_writes_at_commit_commit_and_stop_leaving_the_checkout_alone() {
  own_tree_repo commit
  # A person's work in progress, tracked, staged and untracked.
  printf 'mine\n' >> .ai/specs/idea-x/spec.md
  printf 'staged\n' > staged.txt
  git add staged.txt
  printf 'loose\n' > loose.txt
  local before
  before=$(own_tree_snapshot)
  _w_add "New"
  assert_eq 0 "$RC"
  assert_eq "$before" "$(own_tree_snapshot)"
  local tip
  tip=$(git rev-parse spec/idea-x)
  assert_contains "$OUT" '"branch":"spec/idea-x","base":"main"'
  assert_contains "$OUT" "\"commit\":\"$tip\",\"commits\":1,\"pushed\":false,\"pr\":null,\"merged\":false,\"committed\":true,\"level\":\"commit\""
  assert_contains "$OUT" '"note":"agent.git is commit: pushing spec/idea-x is yours"'
  assert_eq "1" "$(git rev-list --count main..spec/idea-x)"
  assert_eq ".ai/specs/idea-x/roadmap.md" "$(git diff --name-only main spec/idea-x)"
  if git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "pushed at commit"
  fi
  own_tree_gone
}

test_writes_at_push_push_and_leave_the_pull_request() {
  own_tree_repo push
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":true,"pr":null'
  assert_contains "$OUT" '"note":"agent.git is push: the pull request is yours"'
  assert_eq "$(git rev-parse spec/idea-x)" "$(git --git-dir=origin.git rev-parse spec/idea-x)"
}

test_writes_at_pr_with_no_forge_say_the_pull_request_is_yours() {
  own_tree_repo pr
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":true,"pr":null'
  assert_contains "$OUT" '"note":"no forge available: the pull request is yours"'
}

test_writes_with_no_origin_stay_committed_and_say_so() {
  own_tree_repo push
  git remote remove origin
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"committed":true'
  assert_contains "$OUT" '"pushed":false'
  assert_contains "$OUT" 'no origin'
}

test_writes_in_a_row_share_one_branch_and_one_pull_request() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pr":"https://github.com/example/example/pull/42"'
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"commits":2'
  assert_contains "$OUT" '"pr":"https://github.com/example/example/pull/42"'
  # Opened once, into the default branch.
  assert_eq 1 "$(grep -c '^--base$' stub-gh/create.argv)"
  assert_contains "$(cat stub-gh/create.argv)" "$(printf -- '--base\nmain\n--head\nspec/idea-x')"
  assert_contains "$(cat stub-gh/create.argv)" "$(printf -- '--title\nRoadmap edits: idea-x')"
}

test_writes_take_the_pull_request_from_what_gh_answers_not_from_its_warning() {
  # Under the lock the call is bounded, and its output comes back through files: gh's
  # warning about a dirty checkout, on stderr, is not the pull request.
  own_tree_repo pr
  own_tree_stub_gh
  : > stub-gh/warn
  _w_add "First"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pr":"https://github.com/example/example/pull/42"'
  assert_contains "$(cat .ai/runtime/writes/spec-idea-x)" "pr: https://github.com/example/example/pull/42"
}

# The GitHub account a pull request is opened as is named before the push
# (jig_ship_account, common.sh): an account gh does not hold is an answer with
# the write committed and nothing sent, not a refusal after the branch went out.
test_writes_at_pr_name_the_github_account_before_the_push() {
  own_tree_repo pr
  own_tree_stub_gh
  # A GitHub name for origin that resolves nowhere, and the bare repository
  # for whatever does get pushed.
  git remote set-url origin https://github.com.invalid/example/example.git
  git remote set-url --push origin "$PWD/origin.git"
  printf 'github.account: dave\n' >> .ai/config.local.yaml
  _w_add "New"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"committed":true'
  assert_contains "$OUT" '"pushed":false'
  assert_contains "$OUT" 'github.account is dave'
  if git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "spec/idea-x was pushed before the account was named"
  fi
  assert_no_file stub-gh/create.argv
}

test_writes_at_merge_do_not_wait_for_ci_and_say_how_to_merge() {
  own_tree_repo merge
  own_tree_stub_gh
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"merged":false'
  assert_contains "$OUT" 'jig writes ship spec:idea-x'
  assert_no_file stub-gh/merged
}

test_writes_a_failed_push_is_an_answer_and_writes_ship_carries_it_on() {
  own_tree_repo push
  printf '#!/bin/sh\necho refused-by-hook >&2\nexit 1\n' > .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"committed":true'
  assert_contains "$OUT" '"pushed":false'
  assert_contains "$OUT" 'refused-by-hook'
  rm .git/hooks/pre-push
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":true'
  assert_eq "$(git rev-parse spec/idea-x)" "$(git --git-dir=origin.git rev-parse spec/idea-x)"
}

test_writes_ship_opens_the_pull_request_after_the_level_was_raised() {
  own_tree_repo commit
  own_tree_stub_gh
  _w_add "New"
  assert_contains "$OUT" '"pr":null'
  own_tree_level pr
  run jig writes ship spec:idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'pull request: https://github.com/example/example/pull/42'
  assert_contains "$OUT" 'merged: no'
}

test_writes_ship_at_merge_merges_once_ci_passed_at_the_shipped_commit() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "New"
  printf 'spec/idea-x\n' > stub-gh/head
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"merged":true'
  assert_contains "$(cat stub-gh/merged)" "--match-head-commit $(git rev-parse spec/idea-x)"
  # Merged: nothing waits now.
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
}

test_writes_ship_at_merge_ships_from_origins_tip_after_the_local_branch_was_deleted() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "New"
  assert_contains "$OUT" '"pushed":true'
  local sent
  sent=$(git --git-dir=origin.git rev-parse spec/idea-x)
  git branch -q -D spec/idea-x
  printf 'spec/idea-x\n' > stub-gh/head
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'internal:'
  assert_contains "$OUT" "\"commit\":\"$sent\""
  assert_contains "$OUT" '"commits":1'
  assert_contains "$OUT" '"merged":true'
  assert_contains "$(cat stub-gh/merged)" "--match-head-commit $sent"
}

test_writes_ship_refuses_to_cut_a_deleted_branch_below_an_edit_never_sent() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "First"
  assert_contains "$OUT" '"pushed":true'
  printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  _w_add "Second"
  assert_contains "$OUT" '"pushed":false'
  local unsent
  unsent=$(git rev-parse spec/idea-x)
  rm -f .git/hooks/pre-push
  git branch -q -D spec/idea-x
  printf 'spec/idea-x\n' > stub-gh/head
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
  assert_contains "$OUT" "$unsent"
  assert_no_file stub-gh/merged
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a refused ship cut the branch"
  fi
  # The edit still waits, by the record.
  run jig writes --json
  assert_contains "$OUT" '"target":"spec:idea-x"'
}

test_writes_ship_says_why_it_could_not_cut_the_deleted_branch_again() {
  own_tree_repo push
  _w_add "New"
  assert_contains "$OUT" '"pushed":true'
  git branch -q -D spec/idea-x
  # A lock git left: the ref cannot be created, and git says why.
  mkdir -p .git/refs/heads/spec
  : > .git/refs/heads/spec/idea-x.lock
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'could not cut spec/idea-x again at origin'
  assert_contains "$OUT" 'idea-x.lock'
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a refused cut left the branch"
  fi
}

test_writes_ship_at_merge_does_not_merge_when_the_ship_steps_stopped() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "First"
  assert_contains "$OUT" '"pr":"https://github.com/example/example/pull/42"'
  printf '#!/bin/sh\necho refused-by-hook >&2\nexit 1\n' > .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  _w_add "Second"
  assert_contains "$OUT" '"pushed":false'
  printf 'spec/idea-x\n' > stub-gh/head
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'refused-by-hook'
  assert_contains "$OUT" '"merged":false'
  assert_no_file stub-gh/merged
}

test_writes_ship_keeps_a_write_that_landed_while_it_waited_for_ci() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "New"
  printf 'spec/idea-x\n' > stub-gh/head
  # While `writes ship` holds no lock: another edit lands on the branch.
  cat > stub-gh/on-merge <<'HOOK'
next=$(git commit-tree -p spec/idea-x -m later 'spec/idea-x^{tree}')
git update-ref refs/heads/spec/idea-x "$next"
HOOK
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"merged":true'
  run jig writes --json
  assert_contains "$OUT" '"target":"spec:idea-x"'
  assert_contains "$OUT" "\"commit\":\"$(git rev-parse spec/idea-x)\""
}

test_writes_ship_keeps_the_record_of_a_write_that_took_a_new_name_while_it_merged() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "New"
  printf 'spec/idea-x\n' > stub-gh/head
  # While `writes ship` holds no lock the forge merged, and the next edit, finding the
  # branch spent, went on a new name: the record names that one now.
  cat > stub-gh/on-merge <<'HOOK'
f=.ai/runtime/writes/spec-idea-x
sed 's|^branch: .*|branch: spec/idea-x-2|' "$f" > "$f.new"
mv "$f.new" "$f"
HOOK
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"merged":true'
  assert_contains "$(cat .ai/runtime/writes/spec-idea-x)" "branch: spec/idea-x-2"
  assert_contains "$(cat .ai/runtime/writes/spec-idea-x)" "merged: 0"
}

test_writes_ship_leaves_the_record_to_a_write_that_holds_the_lock_after_the_merge() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "New"
  printf 'spec/idea-x\n' > stub-gh/head
  cat > stub-gh/on-merge <<HOOK
mkdir -p .ai/runtime/writes/lock/busy
printf 'checkout: elsewhere\npid: $$\n' > .ai/runtime/writes/lock/busy/run
HOOK
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"merged":true'
  assert_contains "$OUT" 'another write held the lock'
  assert_contains "$(cat .ai/runtime/writes/spec-idea-x)" "merged: 0"
  assert_contains "$(cat .ai/runtime/writes/lock/busy/run)" "pid: $$"
}

test_writes_ship_at_merge_leaves_a_red_pull_request_open() {
  own_tree_repo merge
  own_tree_stub_gh
  printf 'agent.ci_timeout: 0\n' >> .ai/config.local.yaml
  _w_add "New"
  printf 'spec/idea-x\n' > stub-gh/head
  printf 'fail\n' > stub-gh/checks
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"merged":false'
  assert_no_file stub-gh/merged
  run jig writes --json
  assert_contains "$OUT" '"target":"spec:idea-x"'
}

test_writes_ship_refuses_what_is_not_waiting_and_what_is_not_a_target() {
  own_tree_repo push
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"not-found"'
  run jig writes ship bogus --json
  assert_contains "$OUT" '"code":"usage"'
  run jig writes ship --json
  assert_contains "$OUT" '"code":"usage"'
  run jig writes bogus --json
  assert_contains "$OUT" '"code":"usage"'
}

# --- what holds a write off -----------------------------------------------------

test_writes_a_refusal_leaves_no_branch_for_a_later_spec_new() {
  own_tree_repo commit
  run jig spec item add nope --phase 1 --text x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"not-found"'
  if git rev-parse --verify --quiet refs/heads/spec/nope >/dev/null; then
    fail "a refused write left its branch"
  fi
  run jig spec new nope
  assert_eq 0 "$RC"
}

test_writes_a_change_of_nothing_cuts_no_branch() {
  own_tree_repo commit
  local alpha
  alpha=$(jig spec list --json | awk '{ gsub(/\{"id":"i-/, "\n&"); print }' | sed -n 2p | sed -E 's/^\{"id":"(i-[0-9a-f-]+)".*/\1/')
  run jig spec item move idea-x "$alpha" --top --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"commit":null'
  assert_contains "$OUT" '"committed":false'
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a write that changed nothing left a branch"
  fi
}


test_writes_a_stale_revision_is_refused_and_writes_nothing() {
  own_tree_repo commit
  local rev
  rev=$(own_tree_rev)
  run jig spec item add idea-x --phase 2 --text "First" --revision "$rev" --json
  assert_eq 0 "$RC"
  local tip
  tip=$(git rev-parse spec/idea-x)
  run jig spec item add idea-x --phase 2 --text "Second" --revision "$rev" --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"stale-revision"'
  assert_eq "$tip" "$(git rev-parse spec/idea-x)"
  own_tree_gone
}

test_writes_claim_the_revision_after_the_tree_is_made() {
  # Overtaken while the branch was being resolved: the claim catches it, the
  # cheap check having passed. A pre-checkout hook is not git's, so a hook on the
  # tree's checkout raises the revision the way another writer would.
  own_tree_repo commit
  local rev
  rev=$(own_tree_rev)
  cat > .git/hooks/post-checkout <<'HOOK'
#!/bin/sh
d=$(git rev-parse --git-common-dir)/../.ai/runtime/revision
mkdir -p "$d"
: > "$d/99999999999"
exit 0
HOOK
  chmod +x .git/hooks/post-checkout
  run jig spec item add idea-x --phase 2 --text "New" --revision "$rev" --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"stale-revision"'
  assert_no_file .ai/runtime/writes/spec-idea-x "a refused write left a record"
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a refused write left its branch"
  fi
  own_tree_gone
}

test_writes_without_a_revision_are_not_refused_for_a_write_made_meanwhile() {
  # The same raise, by another writer while the tree was being made: a caller that gave
  # no --revision asked for no check, so the claim takes the revision as it is then.
  own_tree_repo commit
  cat > .git/hooks/post-checkout <<'HOOK'
#!/bin/sh
d=$(git rev-parse --git-common-dir)/../.ai/runtime/revision
mkdir -p "$d"
: > "$d/99999999999"
exit 0
HOOK
  chmod +x .git/hooks/post-checkout
  run jig spec item add idea-x --phase 2 --text "New" --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"committed":true'
  assert_contains "$(own_tree_show spec/idea-x .ai/specs/idea-x/roadmap.md)" '- [ ] New'
  own_tree_gone
}

test_writes_a_running_write_holds_another_off_and_a_dead_one_does_not() {
  own_tree_repo commit
  mkdir -p .ai/runtime/writes/lock/busy
  # This shell lives, and it is not the jig below.
  printf 'checkout: elsewhere\npid: %s\n' "$$" > .ai/runtime/writes/lock/busy/run
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-busy"'
  assert_contains "$OUT" "elsewhere"
  assert_file .ai/runtime/writes/lock/busy/run
  # Reaped in a subshell, so its pid is one that is gone.
  local dead
  ( : ) & dead=$!
  wait "$dead"
  printf 'checkout: elsewhere\npid: %s\n' "$dead" > .ai/runtime/writes/lock/busy/run
  _w_add "New"
  assert_eq 0 "$RC"
  own_tree_gone
  # The take-back's own claim went with it.
  assert_no_file .ai/runtime/writes/lock/busy
}

# _w_dead_holder — a lock record whose holder is gone: a pid reaped in a subshell.
_w_dead_holder() {
  local dead
  ( : ) & dead=$!
  wait "$dead"
  mkdir -p .ai/runtime/writes/lock/busy
  printf 'checkout: elsewhere\npid: %s\n' "$dead" > .ai/runtime/writes/lock/busy/run
}

# _w_after_the_judgement <script> [<n>] — run <script> once, from here, after a writer
# has judged the lock's holder gone and before it acts on that: at the <n>th `stat` of
# the record (default 2; the first is the judgement's, the second the take-back's read
# of it, the third its look again under the claim), or at its removal, whichever comes
# first.
_w_after_the_judgement() {
  local real_stat real_rm n
  n=$(printf "%${2:-2}s" | tr ' ' x)
  real_stat=$(command -v stat)
  real_rm=$(command -v rm)
  mkdir -p stub-git
  printf '%s\n' "$1" > stub-git/window
  cat > stub-git/stat <<STUB
#!/usr/bin/env bash
d='$PWD/stub-git'
case " \$* " in
  *"/busy/run "*)
    case " \$* " in
      *" -f "*) printf x >> "\$d/stats" ;;
    esac
    if [ ! -f "\$d/fired" ] && [ "\$(cat "\$d/stats" 2>/dev/null)" = $n ]; then
      : > "\$d/fired"
      (cd '$PWD' && bash "\$d/window") > "\$d/window.out" 2>&1
    fi ;;
esac
exec '$real_stat' "\$@"
STUB
  cat > stub-git/rm <<STUB
#!/usr/bin/env bash
d='$PWD/stub-git'
case " \$* " in
  *"/busy/run "*)
    if [ ! -f "\$d/fired" ]; then
      : > "\$d/fired"
      (cd '$PWD' && bash "\$d/window") > "\$d/window.out" 2>&1
    fi ;;
esac
exec '$real_rm' "\$@"
STUB
  chmod +x stub-git/stat stub-git/rm
  PATH="$PWD/stub-git:$PATH"
  export PATH
}

test_writes_two_writers_taking_back_one_dead_lock_leave_the_first_ones_claim() {
  # Both found the holder gone; the other took the lock back and claimed it first. The
  # record that stands is a live one now, and it is not this writer's to remove.
  own_tree_repo commit
  _w_dead_holder
  _w_after_the_judgement "printf 'checkout: elsewhere\npid: $$\n' > .ai/runtime/writes/lock/busy/run"
  _w_add "New"
  assert_file stub-git/fired "the window never opened"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-busy"'
  assert_contains "$(cat .ai/runtime/writes/lock/busy/run)" "pid: $$"
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a second writer went on beside the first"
  fi
}

test_writes_a_take_back_leaves_a_record_that_changed_under_its_claim() {
  # The record is replaced after the take-back read it and claimed it: under the claim it
  # is not the record judged gone, and it stays.
  own_tree_repo commit
  _w_dead_holder
  _w_after_the_judgement "printf 'checkout: elsewhere\npid: $$\n' > .ai/runtime/writes/lock/busy/run" 3
  _w_add "New"
  assert_file stub-git/fired "the window never opened"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-busy"'
  assert_contains "$(cat .ai/runtime/writes/lock/busy/run)" "pid: $$"
  assert_no_file .ai/runtime/writes/lock/busy/clear.* "the take-back's claim stayed"
}

test_writes_a_take_back_another_has_claimed_is_refused_and_named() {
  # A writer stopped inside its take-back left the claim: the record stays, and the
  # refusal names what a person deletes.
  own_tree_repo commit
  _w_dead_holder
  local run=.ai/runtime/writes/lock/busy/run mtime pid
  mtime=$(stat -f '%m' "$run" 2>/dev/null) || mtime=""
  case "$mtime" in '' | *[!0-9]*) mtime=$(stat -c '%Y' "$run") ;; esac
  pid=$(sed -n 's/^pid: //p' "$run")
  : > ".ai/runtime/writes/lock/busy/clear.$pid.$mtime"
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-busy"'
  assert_contains "$OUT" "clear.$pid.$mtime"
  assert_contains "$(cat "$run")" "pid: $pid"
  rm ".ai/runtime/writes/lock/busy/clear.$pid.$mtime"
  _w_add "New"
  assert_eq 0 "$RC"
}

# _w_stalled_origin — a fake `git` for which origin never answers: ls-remote, fetch and
# push sleep far past any budget, everything else is git.
_w_stalled_origin() {
  local real
  real=$(command -v git)
  mkdir -p stub-git
  cat > stub-git/git <<STUB
#!/usr/bin/env bash
case " \$* " in
  *" ls-remote "* | *" fetch "* | *" push "*) exec sleep 60 ;;
esac
exec '$real' "\$@"
STUB
  chmod +x stub-git/git
  PATH="$PWD/stub-git:$PATH"
  export PATH
}

test_writes_a_stalled_origin_costs_the_write_its_push_not_the_lock() {
  # Every network call under the lock is cut off at its budget: the write answers, its
  # commit waits for `jig writes ship`, and the lock is back long before its ttl.
  own_tree_repo push
  _w_stalled_origin
  local start elapsed
  start=$SECONDS
  JIG_NET_CALL=1 _w_add "New"
  elapsed=$((SECONDS - start))
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"committed":true'
  assert_contains "$OUT" '"pushed":false'
  assert_contains "$OUT" 'no answer within 1s; cut off'
  assert_no_file .ai/runtime/writes/lock/busy/run "the lock outlives the write"
  # Five calls at a second each, on a slow runner; unbounded, one sleep alone is 60.
  if [ "$elapsed" -ge 40 ]; then
    fail "the write took ${elapsed}s against a stalled origin; expected each call cut off at its budget"
  fi
  run jig writes --json
  assert_contains "$OUT" '"target":"spec:idea-x"'
}

# _w_net <body> — run <body> in a shell that has loaded common.sh.
_w_net() {
  printf '#!/usr/bin/env bash\nset -eu\n. "%s/scripts/lib/common.sh"\n%s\n' "$JIG_HOME" "$1" > net.sh
  run bash net.sh
}

test_writes_jig_net_without_a_deadline_is_the_call_itself() {
  _w_net 'jig_net sh -c "echo out; echo err >&2; exit 3" || echo "rc=$?"'
  assert_contains "$OUT" "out"
  assert_contains "$OUT" "err"
  assert_contains "$OUT" "rc=3"
}

test_writes_jig_net_under_a_deadline_cuts_a_call_off_at_its_budget() {
  local start elapsed
  start=$SECONDS
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _w_net '_JIG_NET_CALL=1
_JIG_NET_DEADLINE=$(($(date +%s) + 600))
jig_net sh -c "echo partial; exec sleep 60" || echo "rc=$?"
jig_net sh -c "echo whole; exit 2" || echo "rc2=$?"
_JIG_NET_DEADLINE=$(($(date +%s) - 1))
jig_net sh -c ": > started" || echo "rc3=$?"'
  elapsed=$((SECONDS - start))
  assert_contains "$OUT" "rc=124"
  assert_contains "$OUT" "sh: no answer within 1s; cut off"
  assert_contains "$OUT" "sh: not started"
  assert_not_contains "$OUT" "partial"
  assert_contains "$OUT" "whole"
  assert_contains "$OUT" "rc2=2"
  assert_contains "$OUT" "rc3=124"
  assert_no_file started "a call past the deadline was started"
  if [ "$elapsed" -ge 30 ]; then
    fail "jig_net took ${elapsed}s; expected the call cut off after 1s"
  fi
}

test_writes_past_the_ttl_leave_the_next_writers_tree_and_lock_alone() {
  # The holder stalled past the ttl, and the next writer has cleared its lock and made
  # the tree when it wakes.
  own_tree_repo commit
  own_tree_in_the_window "printf 'checkout: elsewhere\npid: $$\n' > .ai/runtime/writes/lock/busy/run
git worktree add -q --detach .git/jig/tree HEAD"
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-busy"'
  assert_file .git/jig/tree/.git "the next writer's tree went"
  assert_contains "$(cat .ai/runtime/writes/lock/busy/run)" "pid: $$"
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a write went on in another writer's tree"
  fi
}

test_writes_refused_a_tree_in_the_way_do_not_take_it_for_their_own() {
  own_tree_repo commit
  own_tree_in_the_window "git worktree add -q --detach .git/jig/tree HEAD"
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-busy"'
  assert_file .git/jig/tree/.git "a tree this write did not make went"
  assert_no_file .ai/runtime/writes/lock/busy/run "the lock outlives the write"
}

test_writes_that_lost_the_lock_after_making_the_tree_leave_both() {
  # The ttl passes while the write is in its tree: from then on the path and the lock may
  # be the next writer's. What it left is swept, once the lock is free.
  own_tree_repo commit
  cat > .git/hooks/post-checkout <<HOOK
#!/bin/sh
printf 'checkout: elsewhere\npid: $$\n' > "\$(git rev-parse --git-common-dir)/../.ai/runtime/writes/lock/busy/run"
exit 0
HOOK
  chmod +x .git/hooks/post-checkout
  _w_add "New"
  assert_file .git/jig/tree/.git "the tree went without the lock"
  assert_contains "$(cat .ai/runtime/writes/lock/busy/run)" "pid: $$"
}

test_writes_a_checkout_on_the_branch_is_refused_and_not_moved() {
  own_tree_repo commit
  git switch -q -c spec/idea-x
  printf 'mine\n' >> .ai/specs/idea-x/spec.md
  local before tip
  before=$(own_tree_snapshot)
  tip=$(git rev-parse spec/idea-x)
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-checked-out"'
  # The last segment: git prints C:/... where pwd -P prints /c/... (conventions/shell.md).
  assert_contains "$OUT" "${PWD##*/}"
  assert_eq "$before" "$(own_tree_snapshot)"
  assert_eq "$tip" "$(git rev-parse spec/idea-x)"
  own_tree_gone
}

test_writes_another_worktree_on_the_branch_is_refused_too() {
  own_tree_repo commit
  git branch spec/idea-x
  git worktree add -q "$PWD.elsewhere" spec/idea-x
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-checked-out"'
  assert_contains "$OUT" "elsewhere"
}

test_writes_diverged_from_origin_is_refused() {
  own_tree_repo push
  _w_add "First"
  git clone -q origin.git "$PWD.other"
  git -C "$PWD.other" switch -q spec/idea-x
  git -C "$PWD.other" commit -q --allow-empty -m theirs
  git -C "$PWD.other" push -q origin spec/idea-x
  # And a commit here that origin does not have.
  local mine
  mine=$(git commit-tree -p spec/idea-x -m mine 'spec/idea-x^{tree}')
  git update-ref refs/heads/spec/idea-x "$mine"
  _w_add "Second"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-diverged"'
  assert_eq "$mine" "$(git rev-parse spec/idea-x)"
}

test_writes_take_a_push_from_another_clone_on_board() {
  own_tree_repo push
  _w_add "First"
  git clone -q origin.git "$PWD.other"
  git -C "$PWD.other" switch -q spec/idea-x
  git -C "$PWD.other" commit -q --allow-empty -m theirs
  git -C "$PWD.other" push -q origin spec/idea-x
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$(git log --format=%s spec/idea-x)" theirs
  assert_contains "$OUT" '"pushed":true'
}

test_writes_a_refused_commit_leaves_nothing_waiting() {
  own_tree_repo commit
  # A hook in the project's own hooks directory, which a tree runs like any checkout.
  printf '#!/bin/sh\necho needs-node-modules >&2\nexit 1\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"commit-refused"'
  assert_contains "$OUT" 'needs-node-modules'
  assert_eq 0 "$(git rev-list --count main..spec/idea-x)"
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
  own_tree_gone
}

test_writes_a_refused_commit_leaves_an_earlier_edit_waiting() {
  own_tree_repo commit
  _w_add "First"
  assert_eq 0 "$RC"
  local tip
  tip=$(git rev-parse spec/idea-x)
  printf '#!/bin/sh\necho needs-node-modules >&2\nexit 1\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  _w_add "Second"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"commit-refused"'
  # This edit is not committed; the one before it still waits where it was.
  assert_eq "$tip" "$(git rev-parse spec/idea-x)"
  run jig writes --json
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  own_tree_gone
}

test_writes_clear_a_tree_a_killed_write_left() {
  own_tree_repo commit
  mkdir -p .git/jig
  git worktree add -q --detach .git/jig/tree HEAD
  printf 'dirt\n' >> .git/jig/tree/.ai/specs/idea-x/spec.md
  _w_add "New"
  assert_eq 0 "$RC"
  own_tree_gone
}

test_writes_housekeeping_clears_a_tree_a_killed_write_left() {
  own_tree_repo commit
  mkdir -p .git/jig
  git worktree add -q -b spec/idea-x .git/jig/tree HEAD
  jig housekeeping >/dev/null 2>&1
  own_tree_gone
  # And the branch it held is free again, with whatever it had.
  git switch -q spec/idea-x
  assert_eq spec/idea-x "$(git symbolic-ref --short HEAD)"
}

test_writes_get_past_their_own_tree_gone_and_still_registered() {
  own_tree_repo commit
  mkdir -p .git/jig
  git worktree add -q --detach .git/jig/tree HEAD
  rm -rf .git/jig/tree
  _w_add "New"
  assert_eq 0 "$RC"
  own_tree_gone
}

test_writes_housekeeping_clears_their_own_tree_gone_and_still_registered() {
  own_tree_repo commit
  mkdir -p .git/jig
  git worktree add -q -b spec/idea-x .git/jig/tree HEAD
  rm -rf .git/jig/tree
  jig housekeeping >/dev/null 2>&1
  own_tree_gone
}

test_writes_and_housekeeping_keep_a_worktree_whose_directory_is_away() {
  # An unmounted volume, a folder being renamed: nothing was removed by anybody.
  own_tree_repo commit
  git worktree add -q -b task/away "$PWD.away" HEAD
  mv "$PWD.away" "$PWD.elsewhere"
  _w_add "New"
  assert_eq 0 "$RC"
  jig housekeeping >/dev/null 2>&1
  assert_eq 2 "$(git worktree list --porcelain | grep -c '^worktree ')"
  mv "$PWD.elsewhere" "$PWD.away"
  assert_eq task/away "$(git -C "$PWD.away" symbolic-ref --short HEAD)"
  if git switch -q task/away 2>/dev/null; then
    fail "the branch of a worktree that was away came free"
  fi
}

test_writes_housekeeping_leaves_the_tree_of_a_running_write() {
  own_tree_repo commit
  mkdir -p .git/jig .ai/runtime/writes/lock/busy
  git worktree add -q --detach .git/jig/tree HEAD
  printf 'checkout: elsewhere\npid: %s\n' "$$" > .ai/runtime/writes/lock/busy/run
  jig housekeeping >/dev/null 2>&1
  assert_dir .git/jig/tree
}

test_writes_from_a_linked_worktree_share_the_clones_tree_and_records() {
  own_tree_repo commit
  git worktree add -q -b task/other "$PWD.wt" HEAD
  (
    cd "$PWD.wt" || exit 1
    jig spec item add idea-x --phase 2 --text "New" --json >/dev/null 2>&1
  )
  assert_file .ai/runtime/writes/spec-idea-x
  assert_eq 1 "$(git rev-list --count main..spec/idea-x)"
  assert_no_file .git/jig/tree
  assert_contains "$(jig writes)" "spec:idea-x  spec/idea-x -> main"
}

# --- a clone whose git directory is not named .git --------------------------------

# _w_odd_doc — a proposed document, committed, for a knowledge decision to go on.
_w_odd_doc() {
  mkdir -p .ai/knowledge/features
  cat > .ai/knowledge/features/alpha.md <<'DOC'
---
id: feature-alpha
type: feature
status: proposed
domains: [one]
paths: ["src/**"]
summary: "Alpha."
---
# Alpha
DOC
  git add -A >/dev/null
  git commit -q -m "a proposal"
}

# _w_odd_decide — a knowledge decision against the revision a read just gave, once a
# write has raised it: a tree that reads its own empty counter calls that stale.
_w_odd_decide() {
  _w_add "First"
  assert_eq 0 "$RC"
  run jig knowledge accept feature-alpha --revision "$(own_tree_rev)" --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"committed":true'
  assert_eq active "$(own_tree_show knowledge/decisions .ai/knowledge/features/alpha.md | sed -n 's/^status: //p')"
}

# _w_odd_shares <other-checkout> — this checkout's write is seen from the other, its
# revision is the other's, and a running write there holds this one off.
_w_odd_shares() {
  local other="$1" lock
  _w_odd_decide
  assert_eq "$(own_tree_rev)" "$(cd "$other" && own_tree_rev)"
  assert_contains "$(cd "$other" && jig writes)" "knowledge  knowledge/decisions -> main"
  lock="$(git rev-parse --git-common-dir)/jig/writes/lock/busy"
  mkdir -p "$lock" "$(git rev-parse --git-common-dir)/jig"
  git worktree add -q --detach "$(git rev-parse --git-common-dir)/jig/tree" HEAD
  # This shell lives, and it is not the jig below.
  printf 'checkout: elsewhere\npid: %s\n' "$$" > "$lock/run"
  (
    cd "$other" || exit 1
    run jig spec item add idea-x --phase 2 --text "Held off" --json
    assert_eq 1 "$RC"
    assert_contains "$OUT" '"code":"write-busy"'
  )
  assert_file "$(git rev-parse --git-common-dir)/jig/tree/.git" "a second writer swept a live tree"
  assert_file "$lock/run" "a second writer took the lock"
}

test_writes_work_with_a_separate_git_dir() {
  own_tree_repo commit
  _w_odd_doc
  git push -q origin main
  git init -q --separate-git-dir "$PWD.gitdir" >/dev/null
  git worktree add -q -b task/other "$PWD.wt" HEAD
  own_tree_level_in "$PWD.wt"
  _w_odd_shares "$PWD.wt"
}

test_writes_work_in_a_submodule() {
  own_tree_repo commit
  _w_odd_doc
  local sub="$PWD"
  mkdir "$PWD.super"
  cd "$PWD.super" || exit 1
  git init -q .
  git commit -q --allow-empty -m "the superproject"
  git -c protocol.file.allow=always submodule --quiet add "$sub" sub
  cd sub || exit 1
  own_tree_level commit
  _w_odd_decide
  assert_eq active "$(own_tree_show knowledge/decisions .ai/knowledge/features/alpha.md | sed -n 's/^status: //p')"
  assert_no_file "$(git rev-parse --git-common-dir)/jig/tree" "the tree outlives the write"
}

test_writes_work_in_the_worktrees_of_a_bare_repository() {
  own_tree_repo commit
  _w_odd_doc
  git clone -q --bare . "$PWD.bare"
  git -C "$PWD.bare" worktree add -q "$PWD.one" main
  git -C "$PWD.bare" worktree add -q -b task/other "$PWD.two" main
  own_tree_level_in "$PWD.one"
  own_tree_level_in "$PWD.two"
  cd "$PWD.one" || exit 1
  _w_odd_shares "${PWD%.one}.two"
}

# --- the branch, between edits --------------------------------------------------

# _w_merged_and_moved_on — a write, merged, and the base gone on past it, so that only a
# fast-forward puts the next commit on the base's tip.
_w_merged_and_moved_on() {
  _w_add "First"
  git push -q origin "$(git rev-parse spec/idea-x):refs/heads/main"
  git fetch -q origin
  git merge -q --ff-only origin/main
  printf 'later\n' > later.txt
  git add later.txt
  git commit -q -m "later on main"
  git push -q origin main
}

test_writes_after_a_merge_go_on_the_same_name_from_the_new_base() {
  own_tree_repo push
  _w_merged_and_moved_on
  local tip
  tip=$(git rev-parse main)
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_contains "$OUT" '"commits":1'
  assert_contains "$OUT" '"pushed":true'
  assert_eq "$tip" "$(git rev-parse spec/idea-x^)"
}

test_writes_a_person_switching_to_the_branch_mid_write_keeps_it_where_it_was() {
  own_tree_repo push
  _w_merged_and_moved_on
  git worktree add -q --detach "$PWD.person" HEAD
  local old
  old=$(git rev-parse spec/idea-x)
  own_tree_in_the_window "git -C '$PWD.person' switch -q spec/idea-x"
  _w_add "Second"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-checked-out"'
  assert_eq spec/idea-x "$(git -C "$PWD.person" symbolic-ref --short HEAD)"
  assert_eq "$old" "$(git rev-parse spec/idea-x)"
  assert_eq "$old" "$(git -C "$PWD.person" rev-parse HEAD)"
}

test_writes_overtaken_at_the_claim_leave_the_branch_where_it_was() {
  own_tree_repo push
  _w_merged_and_moved_on
  local old rev
  old=$(git rev-parse spec/idea-x)
  rev=$(own_tree_rev)
  own_tree_in_the_window ": > .ai/runtime/revision/99999999999"
  run jig spec item add idea-x --phase 2 --text "Second" --revision "$rev" --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"stale-revision"'
  assert_eq "$old" "$(git rev-parse spec/idea-x)"
  own_tree_gone
}

test_writes_refused_in_validation_leave_the_branch_where_it_was_and_see_the_new_base() {
  own_tree_repo commit
  # A phase only the new base has: validation reads what the branch will be at.
  _w_add "First"
  local old
  old=$(git rev-parse spec/idea-x)
  git merge -q --ff-only spec/idea-x
  printf '\n## Phase 3 — Three\n' >> .ai/specs/idea-x/roadmap.md
  git add -A .ai/specs/idea-x
  git commit -q -m "a third phase"
  git push -q origin main
  run jig spec item add idea-x --phase 9 --text "Nowhere" --json
  assert_eq 1 "$RC"
  assert_eq "$old" "$(git rev-parse spec/idea-x)"
  own_tree_gone
  run jig spec item add idea-x --phase 3 --text "Second" --json
  assert_eq 0 "$RC"
  assert_eq "$(git rev-parse main)" "$(git rev-parse spec/idea-x^)"
  own_tree_gone
}

test_writes_a_branch_only_on_origin_is_cut_at_the_commit_from_its_tip() {
  own_tree_repo push
  git fetch -q origin
  git -C "$PWD" worktree add -q --detach "$PWD.other" HEAD
  printf 'theirs\n' > "$PWD.other/theirs.txt"
  git -C "$PWD.other" add theirs.txt
  git -C "$PWD.other" commit -q -m "theirs"
  git -C "$PWD.other" push -q origin HEAD:refs/heads/spec/idea-x
  local tip
  tip=$(git -C "$PWD.other" rev-parse HEAD)
  run jig spec item add idea-x --phase 9 --text "Nowhere" --json
  assert_eq 1 "$RC"
  if git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null; then
    fail "a refused write made the branch"
  fi
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_eq "$tip" "$(git rev-parse spec/idea-x^)"
  assert_contains "$OUT" '"pushed":true'
}

test_writes_after_a_squash_merge_cut_a_new_name_and_leave_the_old_alone() {
  own_tree_repo push
  _w_add "First"
  local old
  old=$(git rev-parse spec/idea-x)
  # The first path is read from the branch, not from the file written here.
  # shellcheck disable=SC2094
  own_tree_show spec/idea-x .ai/specs/idea-x/roadmap.md > .ai/specs/idea-x/roadmap.md
  git add -A .ai/specs/idea-x
  git commit -q -m squashed
  git push -q origin main
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  assert_contains "$OUT" '"commits":1'
  assert_eq "$old" "$(git rev-parse spec/idea-x)"
  assert_eq "$old" "$(git --git-dir=origin.git rev-parse spec/idea-x)"
  # And the record follows the new name.
  _w_add "Third"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  assert_contains "$OUT" '"commits":2'
}

test_writes_after_a_squash_merge_do_not_take_the_name_of_another_spec() {
  own_tree_repo push
  # A spec whose id is what the new name would be, its own branch merged and gone.
  mkdir -p .ai/specs/idea-x-2
  printf '# Idea X 2\n' > .ai/specs/idea-x-2/spec.md
  printf '# Roadmap: Idea X 2\n\n## Phase 1 — One\n\n- [ ] Its own\n' > .ai/specs/idea-x-2/roadmap.md
  git add -A .ai/specs/idea-x-2
  git commit -q -m "another spec"
  git push -q origin main
  _w_add "First"
  # shellcheck disable=SC2094
  own_tree_show spec/idea-x .ai/specs/idea-x/roadmap.md > .ai/specs/idea-x/roadmap.md
  git add -A .ai/specs/idea-x
  git commit -q -m squashed
  git push -q origin main
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-3"'
  assert_contains "$OUT" '"commits":1'
  if git rev-parse --verify --quiet refs/heads/spec/idea-x-2 >/dev/null; then
    fail "a write of idea-x took the branch of spec idea-x-2"
  fi
  run jig spec item add idea-x-2 --phase 1 --text "Next" --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  assert_contains "$OUT" '"commits":1'
}

test_writes_after_a_closed_pull_request_do_not_bring_its_edits_back() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "Turned down"
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  assert_not_contains "$(own_tree_show spec/idea-x-2 .ai/specs/idea-x/roadmap.md)" "Turned down"
  assert_contains "$(own_tree_show spec/idea-x .ai/specs/idea-x/roadmap.md)" "Turned down"
}

test_writes_after_the_branch_was_deleted_on_origin_cut_a_new_name() {
  own_tree_repo push
  _w_add "First"
  local old
  old=$(git rev-parse spec/idea-x)
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  assert_eq "$old" "$(git rev-parse spec/idea-x)"
  if git rev-parse --verify --quiet refs/remotes/origin/spec/idea-x >/dev/null; then
    fail "a ref origin no longer has stayed"
  fi
}

test_writes_after_a_local_branch_was_deleted_recreate_it_from_origin() {
  own_tree_repo push
  _w_add "First"
  git branch -q -D spec/idea-x
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_contains "$OUT" '"commits":2'
}

test_writes_never_force_a_push() {
  own_tree_repo push
  _w_add "First"
  assert_not_contains "$(grep -n -- '--force' "$JIG_HOME/scripts/lib/writes.sh" || true)" "push"
  assert_not_contains "$(grep -n 'push.*--force\|reset --hard\|git clean\|branch -D' "$JIG_HOME/scripts/lib/owntree.sh" || true)" "git"
}

# _w_person_commit <message> — a commit on main here, that nobody has pushed.
_w_person_commit() {
  printf '%s\n' "$1" >> mine.txt
  git add mine.txt
  git commit -q -m "$1"
}

test_writes_leave_out_what_a_person_has_not_pushed_on_their_base() {
  own_tree_repo push
  local base
  base=$(git rev-parse origin/main)
  _w_person_commit "unpushed on main"
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"commits":1'
  assert_eq "$base" "$(git rev-parse spec/idea-x^)"
  assert_eq 1 "$(git --git-dir=origin.git rev-list --count main..spec/idea-x)"
  run jig writes --json
  assert_contains "$OUT" '"commits":1'
}

test_writes_are_not_held_up_by_a_base_that_diverged_here() {
  own_tree_repo commit
  git worktree add -q --detach "$PWD.other" HEAD
  printf 'theirs\n' > "$PWD.other/theirs.txt"
  git -C "$PWD.other" add theirs.txt
  git -C "$PWD.other" commit -q -m theirs
  git -C "$PWD.other" push -q origin HEAD:refs/heads/main
  git fetch -q origin
  _w_person_commit "unpushed on main"
  _w_add "New"
  assert_eq 0 "$RC"
  assert_eq "$(git rev-parse origin/main)" "$(git rev-parse spec/idea-x^)"
}

test_writes_say_pushed_only_when_origin_holds_the_tip_after_a_failed_push() {
  own_tree_repo push
  _w_add "First"
  assert_contains "$OUT" '"pushed":true'
  git remote set-url --push origin /nonexistent/origin.git
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":false'
  assert_contains "$OUT" 'git push failed'
  run jig writes --json
  assert_contains "$OUT" '"pushed":false'
  assert_contains "$(jig writes)" "not pushed"
  git remote set-url --push origin "$PWD/origin.git"
  run jig writes ship spec:idea-x --json
  assert_contains "$OUT" '"pushed":true'
  assert_contains "$(jig writes)" "pushed, no pull request"
}

test_writes_say_pushed_only_when_origin_holds_the_tip_at_a_lower_level() {
  own_tree_repo push
  _w_add "First"
  own_tree_level commit
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":false'
  run jig writes --json
  assert_contains "$OUT" '"pushed":false'
}

# _w_merged_without_the_tip — a pull request of the first edit, merged by ancestry into
# nothing yet: the second edit's push failed, so only the first reached origin. Leaves
# it merged on origin and the second waiting here.
_w_merged_without_the_tip() {
  _w_add "First"
  git remote set-url --push origin /nonexistent/origin.git
  _w_add "Second"
  git remote set-url --push origin "$PWD/origin.git"
  git push -q origin "$(git rev-parse spec/idea-x^):refs/heads/main"
  git fetch -q origin
  printf 'MERGED\n' > stub-gh/state
  rm stub-gh/url
}

test_writes_keep_what_a_merged_pull_request_did_not_hold() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_merged_without_the_tip
  local second
  second=$(git rev-parse spec/idea-x)
  _w_add "Third"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_eq "$second" "$(git rev-parse spec/idea-x^)"
  assert_eq "" "$(git rev-parse --verify --quiet refs/heads/spec/idea-x-2)"
  assert_contains "$(jig writes)" "spec:idea-x  spec/idea-x -> main  2 commit(s)"
  assert_eq "$(git rev-parse spec/idea-x)" "$(git --git-dir=origin.git rev-parse spec/idea-x)"
}

test_writes_keep_what_a_merged_pull_request_did_not_hold_when_origin_dropped_its_branch() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_merged_without_the_tip
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  local second
  second=$(git rev-parse spec/idea-x)
  _w_add "Third"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_eq "$second" "$(git rev-parse spec/idea-x^)"
}

test_writes_after_a_merged_pull_request_that_held_the_tip_cut_a_new_name() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  # Squashed: the base has moved on, and the branch is no ancestor of it.
  git worktree add -q --detach "$PWD.other" origin/main
  printf 'squashed\n' > "$PWD.other/squashed.txt"
  git -C "$PWD.other" add squashed.txt
  git -C "$PWD.other" commit -q -m squashed
  git -C "$PWD.other" push -q origin HEAD:refs/heads/main
  git fetch -q origin
  printf 'MERGED\n' > stub-gh/state
  rm stub-gh/url
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
}

test_writes_after_a_merged_pull_request_know_the_tip_went_when_the_tracking_ref_has_gone() {
  # Somebody's `fetch --prune`: only the record says origin held the tip.
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  git worktree add -q --detach "$PWD.other" origin/main
  printf 'squashed\n' > "$PWD.other/squashed.txt"
  git -C "$PWD.other" add squashed.txt
  git -C "$PWD.other" commit -q -m squashed
  git -C "$PWD.other" push -q origin HEAD:refs/heads/main
  git fetch -q origin
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  git update-ref -d refs/remotes/origin/spec/idea-x
  printf 'MERGED\n' > stub-gh/state
  rm stub-gh/url
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
}

test_writes_after_a_fast_forward_leave_the_merged_pull_request_behind() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  git push -q origin "$(git rev-parse spec/idea-x):refs/heads/main"
  git fetch -q origin
  printf 'MERGED\n' > stub-gh/state
  own_tree_level push
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_contains "$OUT" '"pr":null'
  _w_add "Third"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_contains "$OUT" '"commits":2'
}

test_writes_refuse_a_branch_with_a_persons_commits_and_no_record() {
  own_tree_repo push
  git switch -q -c spec/idea-x
  printf 'wip\n' > wip.txt
  git add wip.txt
  git commit -q -m "my unfinished wip"
  git switch -q main
  local tip
  tip=$(git rev-parse spec/idea-x)
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
  assert_contains "$OUT" "spec/idea-x has commits"
  assert_eq "$tip" "$(git rev-parse spec/idea-x)"
  assert_no_file .ai/runtime/writes/spec-idea-x "a refused write left a record"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  own_tree_gone
  # Once it is theirs on origin, there is nothing of theirs to publish.
  git push -q origin spec/idea-x
  _w_add "New"
  assert_eq 0 "$RC"
  assert_eq "$tip" "$(git rev-parse spec/idea-x^)"
}

test_writes_refuse_a_persons_commit_on_top_of_a_write() {
  own_tree_repo push
  _w_add "First"
  git worktree add -q --detach "$PWD.person" spec/idea-x
  git -C "$PWD.person" switch -q spec/idea-x
  printf 'wip\n' > "$PWD.person/wip.txt"
  git -C "$PWD.person" add wip.txt
  git -C "$PWD.person" commit -q -m "my unfinished wip"
  git -C "$PWD.person" switch -q --detach
  local tip
  tip=$(git rev-parse spec/idea-x)
  _w_add "Second"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
  assert_eq "$tip" "$(git rev-parse spec/idea-x)"
}

test_writes_ship_refuses_a_persons_commit_on_top_of_a_write() {
  own_tree_repo commit
  _w_add "First"
  git worktree add -q --detach "$PWD.person" spec/idea-x
  git -C "$PWD.person" switch -q spec/idea-x
  printf 'wip\n' > "$PWD.person/wip.txt"
  git -C "$PWD.person" add wip.txt
  git -C "$PWD.person" commit -q -m "my unfinished wip"
  git -C "$PWD.person" switch -q --detach
  own_tree_level push
  local tip
  tip=$(git rev-parse spec/idea-x)
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
  assert_contains "$OUT" "spec/idea-x has commits"
  assert_eq "$tip" "$(git rev-parse spec/idea-x)"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  assert_no_file .ai/runtime/writes/lock/busy/run "the lock outlives the write"
}

# _w_wip_on <branch> — a person's commit on it, not pushed, in a checkout that then leaves it.
_w_wip_on() {
  git worktree add -q --detach "$PWD.person" "$1"
  git -C "$PWD.person" switch -q "$1"
  printf 'wip\n' > "$PWD.person/wip.txt"
  git -C "$PWD.person" add wip.txt
  git -C "$PWD.person" commit -q -m "my unfinished wip"
  git -C "$PWD.person" switch -q --detach
}

# _w_on_origin_main <how> <branch> — the base moves on past <branch> on origin: a merge
# commit of it, or a squash, which is a commit of its content alone.
_w_on_origin_main() {
  git worktree add -q --detach "$PWD.other" origin/main
  if [ "$1" = merge ]; then
    git -C "$PWD.other" merge -q --no-ff -m merged "origin/$2"
  else
    git -C "$PWD.other" merge -q --squash "origin/$2"
    git -C "$PWD.other" commit -q -m squashed
  fi
  git -C "$PWD.other" push -q origin HEAD:refs/heads/main
  git fetch -q origin
}

# _w_merged_then_wip <how> <run...> — a pull request merged, a person's commit on the
# branch, then <run...>: refused, with the commit still here and not on origin.
_w_merged_then_wip() {
  local how="$1" branch="$2" sent tip
  sent=$(git rev-parse "origin/$branch")
  _w_on_origin_main "$how" "$branch"
  printf 'MERGED\n' > stub-gh/state
  rm stub-gh/url
  _w_wip_on "$branch"
  tip=$(git rev-parse "$branch")
  shift 2
  run "$@"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
  assert_eq "$tip" "$(git rev-parse "$branch")"
  assert_eq "$sent" "$(git --git-dir=origin.git rev-parse "$branch")"
}

test_writes_refuse_a_persons_commit_on_a_branch_whose_pull_request_merged_by_a_merge_commit() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_merged_then_wip merge spec/idea-x jig spec item add idea-x --phase 2 --text "Second" --json
}

test_writes_refuse_a_persons_commit_on_a_branch_whose_pull_request_was_squashed() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_merged_then_wip squash spec/idea-x jig spec item add idea-x --phase 2 --text "Second" --json
}

test_writes_refuse_a_persons_commit_on_the_knowledge_branch_too() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_odd_doc
  git push -q origin main
  run jig knowledge accept feature-alpha --json
  assert_eq 0 "$RC"
  _w_merged_then_wip squash knowledge/decisions jig knowledge accept feature-alpha --json
}

test_writes_refuse_a_persons_commit_on_a_branch_whose_pull_request_was_closed() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  _w_wip_on spec/idea-x
  _w_add "Second"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
}

# _w_local_epic — the roadmap on origin's main says an epic, which is only here, with a
# person's commit on it.
_w_local_epic() {
  printf 'Epic: epic/idea-x\n\n' | cat - .ai/specs/idea-x/roadmap.md > roadmap.tmp
  mv roadmap.tmp .ai/specs/idea-x/roadmap.md
  git add -A .ai/specs/idea-x
  git commit -q -m "an epic"
  git push -q origin main
  git switch -q -c epic/idea-x
  printf 'unpushed\n' > unpushed.txt
  git add unpushed.txt
  git commit -q -m "person unpushed on epic"
  git switch -q main
}

test_writes_refuse_to_carry_out_a_base_origin_does_not_have() {
  own_tree_repo push
  _w_local_epic
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"base-not-on-origin"'
  assert_contains "$OUT" "epic/idea-x is not on origin"
  assert_eq "" "$(git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  assert_no_file .ai/runtime/writes/spec-idea-x "a refused write left a record"
  own_tree_gone
}

test_writes_on_a_base_origin_does_not_have_commit_here_and_ship_refuses_to_send_them() {
  own_tree_repo commit
  _w_local_epic
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"base":"epic/idea-x"'
  assert_contains "$OUT" '"pushed":false'
  own_tree_level push
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"base-not-on-origin"'
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
}

test_writes_ship_does_not_bring_back_a_pull_request_closed_unmerged() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "Turned down"
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  own_tree_level merge
  local creates before
  creates=$(grep -c . stub-gh/create.argv)
  before=$(cat .ai/runtime/writes/spec-idea-x)
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"not-found"'
  assert_contains "$OUT" "closed unmerged"
  assert_eq "$creates" "$(grep -c . stub-gh/create.argv)"
  assert_no_file stub-gh/merged "a turned-down edit merged"
  # What it learned it keeps: reads stop counting the edit, and the next ship says the same.
  assert_eq "$before
ended: closed" "$(cat .ai/runtime/writes/spec-idea-x)"
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
  assert_not_contains "$(jig status)" "waiting"
  run jig writes ship spec:idea-x --json
  assert_contains "$OUT" '"code":"not-found"'
  own_tree_gone
}

test_writes_ship_does_not_send_again_what_a_squash_landed() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_on_origin_main squash spec/idea-x
  # The file moves on, so the paths the branch touched no longer read the same on the base.
  git -C "$PWD.other" switch -q --detach origin/main
  printf 'later\n' >> "$PWD.other/.ai/specs/idea-x/roadmap.md"
  git -C "$PWD.other" add -A .ai/specs/idea-x
  git -C "$PWD.other" commit -q -m "later"
  git -C "$PWD.other" push -q origin HEAD:refs/heads/main
  printf 'MERGED\n' > stub-gh/state
  rm stub-gh/url
  own_tree_level merge
  local creates
  creates=$(grep -c . stub-gh/create.argv)
  assert_contains "$(jig writes)" "spec:idea-x"
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"not-found"'
  assert_contains "$OUT" "merged with these edits"
  assert_eq "$creates" "$(grep -c . stub-gh/create.argv)"
  assert_no_file stub-gh/merged "what landed merged again"
}

test_writes_ship_opens_a_new_pull_request_for_what_a_merged_one_did_not_hold() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_merged_without_the_tip
  local creates second
  creates=$(grep -c . stub-gh/create.argv)
  second=$(git rev-parse spec/idea-x)
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":true'
  assert_contains "$OUT" '"pr":"https://github.com/example/example/pull/42"'
  if [ "$(grep -c . stub-gh/create.argv)" -le "$creates" ]; then
    fail "no new pull request opened"
  fi
  assert_eq "$second" "$(git --git-dir=origin.git rev-parse spec/idea-x)"
}

test_writes_ship_forgets_a_merged_pull_request_that_did_not_hold_the_tip() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_merged_without_the_tip
  own_tree_level push
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":true'
  assert_contains "$OUT" '"pr":null'
}

test_writes_refused_keep_the_tracking_ref_so_the_next_write_sees_the_same() {
  own_tree_repo push
  git switch -q -c spec/idea-x
  printf 'shipped\n' > shipped.txt
  git add shipped.txt
  git commit -q -m shipped
  git push -q origin spec/idea-x
  git switch -q main
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  local stale
  stale=$(git rev-parse refs/remotes/origin/spec/idea-x)
  run jig spec item add idea-x --phase 9 --text "Nowhere" --json
  assert_eq 1 "$RC"
  assert_eq "$stale" "$(git rev-parse refs/remotes/origin/spec/idea-x)"
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  # At the commit, what `fetch --prune` would have done is done.
  assert_eq "" "$(git rev-parse --verify --quiet refs/remotes/origin/spec/idea-x)"
  assert_eq "$stale" "$(git rev-parse spec/idea-x)"
}

test_writes_name_a_leftover_tree_with_a_code_of_its_own_and_leave_it() {
  own_tree_repo commit
  mkdir -p .git/jig/tree
  printf 'left\n' > .git/jig/tree/left.txt
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"tree-in-the-way"'
  assert_contains "$OUT" "delete that directory"
  assert_file .git/jig/tree/left.txt
  assert_no_file .ai/runtime/writes/lock/busy/run "the lock outlives the write"
  jig housekeeping >/dev/null 2>&1
  assert_file .git/jig/tree/left.txt "housekeeping deleted what git would not"
  rm -rf .git/jig/tree
  _w_add "New"
  assert_eq 0 "$RC"
  own_tree_gone
}

test_writes_name_a_leftover_tree_git_no_longer_knows() {
  own_tree_repo commit
  mkdir -p .git/jig/tree
  printf 'gitdir: /nowhere/at/all\n' > .git/jig/tree/.git
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"tree-in-the-way"'
}

# --- what git leaves of the tree (Windows) ---------------------------------------
# On Windows `git worktree remove` can drop the registration and leave the directory
# (housekeeping measured it for a task worktree). macOS/Linux git removes it outright,
# so a fake `git` leaves one: after the real `worktree remove` took a tree that was
# there, it runs stub-git/leftover, which plants what Windows would leave.

# _w_leftover_git <script> — the fake git, <script> run from here after each removal.
_w_leftover_git() {
  local real
  real=$(command -v git)
  mkdir -p stub-git
  printf '%s\n' "$1" > stub-git/leftover
  cat > stub-git/git <<STUB
#!/usr/bin/env bash
case " \$* " in
  *" worktree remove "*)
    tree='$PWD/.git/jig/tree' was=0 rc=0
    [ ! -e "\$tree" ] || was=1
    '$real' "\$@" || rc=\$?
    [ "\$was\$rc" != 10 ] || (cd '$PWD' && bash stub-git/leftover)
    exit "\$rc" ;;
esac
exec '$real' "\$@"
STUB
  chmod +x stub-git/git
  PATH="$PWD/stub-git:$PATH"
  export PATH
}

# _w_leftover_owner — what a leftover's link points at: content that must outlive it.
_w_leftover_owner() {
  mkdir -p stub-git/owner/nested
  printf 'kept\n' > stub-git/owner/state
  printf 'nested, kept\n' > stub-git/owner/nested/doc.md
}

_w_leftover_owner_intact() {
  assert_eq "kept" "$(cat stub-git/owner/state)"
  assert_eq "nested, kept" "$(cat stub-git/owner/nested/doc.md)"
}

# The link the fake git plants is made the way Jig makes one (jig_link_dir): a junction
# on Windows Git Bash, where `ln -s` copies. Expanded by the leftover script, from the clone.
# shellcheck disable=SC2016
_W_PLANT_LINK='bash -c ". \"\$JIG_HOME/scripts/lib/version.sh\"; . \"\$JIG_HOME/scripts/lib/common.sh\"; jig_link_dir \"\$1\" \"\$2\"" _ "$PWD/stub-git/owner" "$PWD/.git/jig/tree/borrowed"'

test_writes_clear_links_and_empty_directories_git_left_of_the_tree() {
  own_tree_repo commit
  _w_leftover_owner
  plant_dir_link "$PWD/stub-git/owner" "$PWD/stub-git/probe"
  rm -f stub-git/probe 2>/dev/null || rmdir stub-git/probe
  _w_leftover_git "mkdir -p .git/jig/tree/a/b .git/jig/tree/c
$_W_PLANT_LINK"
  _w_add "New"
  assert_eq 0 "$RC"
  own_tree_gone
  _w_leftover_owner_intact
  _w_add "Next"
  assert_eq 0 "$RC"
  own_tree_gone
  _w_leftover_owner_intact
}

test_writes_leave_a_file_git_left_of_the_tree_for_a_person() {
  own_tree_repo commit
  _w_leftover_owner
  plant_dir_link "$PWD/stub-git/owner" "$PWD/stub-git/probe"
  rm -f stub-git/probe 2>/dev/null || rmdir stub-git/probe
  _w_leftover_git "mkdir -p .git/jig/tree/a
printf 'held\n' > .git/jig/tree/a/held.txt
$_W_PLANT_LINK"
  _w_add "New"
  assert_eq 0 "$RC"
  assert_file .git/jig/tree/a/held.txt
  assert_no_file .git/jig/tree/borrowed "a link goes even beside a file"
  _w_leftover_owner_intact
  _w_add "Next"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"tree-in-the-way"'
  assert_file .git/jig/tree/a/held.txt
  _w_leftover_owner_intact
}

test_writes_clear_an_empty_leftover_git_no_longer_knows() {
  own_tree_repo commit
  mkdir -p .git/jig/tree/a/b
  _w_add "New"
  assert_eq 0 "$RC"
  own_tree_gone
}

# --- what a reader sees ---------------------------------------------------------

test_writes_list_json_pins_the_shape() {
  own_tree_repo push
  run jig writes --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"data":{"writes":[]}'
  _w_add "New"
  local tip
  tip=$(git rev-parse spec/idea-x)
  run jig writes --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" "\"data\":{\"writes\":[{\"target\":\"spec:idea-x\",\"branch\":\"spec/idea-x\",\"base\":\"main\",\"commit\":\"$tip\",\"commits\":1,\"pushed\":true,\"pr\":null,\"merged\":false}]}}"
}

test_writes_list_text_and_status_say_where_an_edit_waits() {
  own_tree_repo commit
  run jig status
  assert_not_contains "$OUT" "writes:"
  _w_add "New"
  run jig writes
  assert_eq 0 "$RC"
  assert_eq "spec:idea-x  spec/idea-x -> main  1 commit(s)  not pushed" "$OUT"
  run jig status
  assert_contains "$OUT" "writes: 1 waiting (jig writes)"
}

test_writes_a_person_on_a_branch_of_that_name_is_not_a_write_that_waits() {
  own_tree_repo commit
  git branch spec/idea-x
  git switch -q spec/idea-x
  git commit -q --allow-empty -m mine
  git switch -q main
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
}

test_writes_list_no_ghost_for_a_record_a_killed_write_left_half_made() {
  own_tree_repo commit
  _w_add "New"
  # A killed write leaves its temporary as a dotfile, outside the glob of records.
  cp .ai/runtime/writes/spec-idea-x .ai/runtime/writes/.tmp.spec-idea-x.999
  cp .ai/runtime/writes/spec-idea-x ".ai/runtime/writes/spec-not valid"
  run jig writes --json
  assert_contains "$OUT" '"target":"spec:idea-x"'
  assert_not_contains "$OUT" 'tmp'
  assert_not_contains "$OUT" 'not valid'
  assert_not_contains "$(jig writes)" 'tmp'
  assert_contains "$(jig status)" "writes: 1"
}

test_writes_list_a_spec_whose_id_has_tmp_in_it() {
  own_tree_repo commit
  _w_add "New"
  # A dot is legal in a spec id, so `.tmp.` in one is a name, not a leftover.
  cp .ai/runtime/writes/spec-idea-x .ai/runtime/writes/spec-v1.tmp.2
  run jig writes --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"target":"spec:idea-x"'
  assert_contains "$OUT" '"target":"spec:v1.tmp.2"'
}

test_writes_reads_ask_no_network() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "New"
  git remote set-url origin /nonexistent/origin.git
  printf 'exit 9\n' > stub-gh/gh
  run jig writes --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pr":"https://github.com/example/example/pull/42"'
  run jig spec list --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pr":"https://github.com/example/example/pull/42"'
}

# --- what the record knows, whatever the base; what origin holds, by its answer ----

# _w_open_epic — the spec gets an open epic on origin: the roadmap on origin's main says so,
# and the epic is cut from there, the way `jig spec epic` leaves it.
_w_open_epic() {
  git fetch -q origin
  git worktree add -q --detach "$PWD.epic" origin/main
  printf 'Epic: epic/idea-x\n\n' | cat - "$PWD.epic/.ai/specs/idea-x/roadmap.md" > roadmap.tmp
  mv roadmap.tmp "$PWD.epic/.ai/specs/idea-x/roadmap.md"
  git -C "$PWD.epic" commit -q -am "an epic"
  git -C "$PWD.epic" push -q origin HEAD:refs/heads/main HEAD:refs/heads/epic/idea-x
  git worktree remove --force "$PWD.epic"
  git fetch -q origin
}

# _w_squashed_and_deleted <branch> — its pull request squash-merged into origin's main, and
# the branch deleted there, as a forge's button does.
_w_squashed_and_deleted() {
  _w_on_origin_main squash "$1"
  git worktree remove --force "$PWD.other"
  git --git-dir=origin.git update-ref -d "refs/heads/$1"
}

test_writes_after_a_closed_pull_request_and_a_new_epic_do_not_bring_its_edits_back() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "Turned down"
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  _w_open_epic
  _w_add "After the epic"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2","base":"epic/idea-x"'
  assert_contains "$OUT" '"commits":1'
  assert_not_contains "$(own_tree_show spec/idea-x-2 .ai/specs/idea-x/roadmap.md)" "Turned down"
  assert_contains "$(own_tree_show spec/idea-x .ai/specs/idea-x/roadmap.md)" "Turned down"
  assert_contains "$(cat stub-gh/create.argv)" "$(printf -- '--base\nepic/idea-x\n--head\nspec/idea-x-2')"
}

test_writes_after_a_squash_merge_and_a_new_epic_do_not_send_it_again() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  # The epic changes the file again, so only the pull request can say that it landed.
  _w_on_origin_main squash spec/idea-x
  git worktree remove --force "$PWD.other"
  printf 'MERGED\n' > stub-gh/state
  rm stub-gh/url
  _w_open_epic
  _w_add "After the epic"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2","base":"epic/idea-x"'
  assert_contains "$OUT" '"commits":1'
}

test_writes_refuse_a_write_that_still_waits_for_another_base() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "Waiting for main"
  local tip before
  tip=$(git rev-parse spec/idea-x)
  before=$(cat .ai/runtime/writes/spec-idea-x)
  _w_open_epic
  _w_add "After the epic"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
  assert_contains "$OUT" "spec/idea-x still waits to go into main (https://github.com/example/example/pull/42), and this edit goes into epic/idea-x"
  assert_eq "$tip" "$(git rev-parse spec/idea-x)"
  assert_eq "$tip" "$(git --git-dir=origin.git rev-parse spec/idea-x)"
  assert_eq "$before" "$(cat .ai/runtime/writes/spec-idea-x)"
  assert_eq "" "$(git rev-parse --verify --quiet refs/heads/spec/idea-x-2)"
  own_tree_gone
  # What waits still ships where it was going.
  run jig writes ship spec:idea-x --json
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"base":"main"'
}

test_writes_after_a_base_change_keep_to_the_branch_the_record_names() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_squashed_and_deleted spec/idea-x
  printf 'MERGED\n' > stub-gh/state
  rm stub-gh/url
  _w_add "Second"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  rm stub-gh/state
  _w_open_epic
  # Still waiting: refused, and the message names the branch that waits.
  _w_add "After the epic"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
  assert_contains "$OUT" "spec/idea-x-2 still waits to go into main"
  assert_not_contains "$OUT" "branch-has-other-commits"
  # Turned down: a new name, from the epic, with neither edit on it.
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  _w_add "After the epic"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-3","base":"epic/idea-x"'
  assert_contains "$OUT" '"commits":1'
}

test_writes_after_a_squash_merge_a_pruned_branch_of_a_session_is_no_persons_commit() {
  own_tree_repo push
  git switch -q -c spec/idea-x
  printf -- '- [ ] From a session\n' >> .ai/specs/idea-x/roadmap.md
  git commit -q -am "from a session"
  git push -q origin spec/idea-x
  git switch -q main
  local old
  old=$(git rev-parse spec/idea-x)
  _w_squashed_and_deleted spec/idea-x
  git fetch -q --prune origin
  _w_add "New"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x-2"'
  assert_eq "$old" "$(git rev-parse spec/idea-x)"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
}

test_writes_say_nothing_of_a_push_to_a_clone_with_no_origin() {
  own_tree_repo commit
  git remote remove origin
  git switch -q -c spec/idea-x
  printf 'wip\n' > wip.txt
  git add wip.txt
  git commit -q -m "my unfinished wip"
  git switch -q main
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
  assert_contains "$OUT" "merge them yourself"
  assert_not_contains "$OUT" "push"
}

test_writes_do_not_take_a_branch_origin_deleted_for_one_it_holds() {
  own_tree_repo push
  git switch -q -c wip
  printf 'secret wip\n' > secret.txt
  git add secret.txt
  git commit -q -m "secret wip"
  git push -q origin wip
  git switch -q main
  git branch -q spec/idea-x wip
  # Deleted on origin, by a forge's button: this clone still has origin/wip.
  git --git-dir=origin.git update-ref -d refs/heads/wip
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/wip)"
}

test_writes_do_not_take_an_epic_origin_deleted_for_a_base_it_has() {
  own_tree_repo push
  _w_open_epic
  git --git-dir=origin.git update-ref -d refs/heads/epic/idea-x
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"base-not-on-origin"'
  assert_contains "$OUT" "epic/idea-x is not on origin"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  own_tree_gone
}

test_writes_ship_does_not_bring_back_a_branch_origin_dropped() {
  own_tree_repo push
  own_tree_stub_gh
  _w_add "Dropped"
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  own_tree_level merge
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"not-found"'
  assert_contains "$OUT" "origin no longer has spec/idea-x"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  assert_no_file stub-gh/create.argv "a pull request opened for what origin dropped"
  assert_no_file stub-gh/merged "what origin dropped merged"
  assert_contains "$(cat .ai/runtime/writes/spec-idea-x)" "ended: dropped"
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
}

test_writes_ship_does_not_send_again_what_a_squash_landed_with_no_pull_request() {
  own_tree_repo push
  own_tree_stub_gh
  _w_add "First"
  _w_squashed_and_deleted spec/idea-x
  # The file moves on, so the paths the branch touched no longer read the same on the base.
  git worktree add -q --detach "$PWD.later" origin/main
  printf 'later\n' >> "$PWD.later/.ai/specs/idea-x/roadmap.md"
  git -C "$PWD.later" commit -q -am "later"
  git -C "$PWD.later" push -q origin HEAD:refs/heads/main
  git fetch -q origin
  own_tree_level pr
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"not-found"'
  assert_no_file stub-gh/create.argv "a landed edit sent again"
}

test_writes_refuse_to_strand_edits_never_sent_above_a_branch_origin_dropped() {
  own_tree_repo push
  _w_add "First"
  git remote set-url --push origin /nonexistent/origin.git
  _w_add "Second"
  git remote set-url --push origin "$PWD/origin.git"
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  local second
  second=$(git rev-parse spec/idea-x)
  _w_add "Third"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
  assert_contains "$OUT" "spec/idea-x has 1 edit(s) that never reached origin, above edits origin no longer has"
  assert_eq "$second" "$(git rev-parse spec/idea-x)"
  assert_eq "" "$(git rev-parse --verify --quiet refs/heads/spec/idea-x-2)"
  assert_contains "$(jig writes)" "spec:idea-x  spec/idea-x -> main"
  own_tree_gone
  # Moved to a branch of the person's own, the next edit goes on.
  git branch -m spec/idea-x kept
  _w_add "Third"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"commits":1'
  assert_eq "$second" "$(git rev-parse kept)"
}

test_writes_know_origin_held_a_branch_it_dropped_after_a_prune_and_a_failed_push() {
  # The last push failed, so the record says pushed: 0, and `fetch --prune` took the
  # tracking ref: only the record's `sent` says origin ever held the branch.
  own_tree_repo push
  _w_add "First"
  git remote set-url --push origin /nonexistent/origin.git
  _w_add "Second"
  assert_contains "$OUT" '"pushed":false'
  git remote set-url --push origin "$PWD/origin.git"
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  git fetch -q --prune origin
  assert_eq "" "$(git rev-parse --verify --quiet refs/remotes/origin/spec/idea-x)"
  local second
  second=$(git rev-parse spec/idea-x)
  _w_add "Third"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
  assert_contains "$OUT" "spec/idea-x has 1 edit(s) that never reached origin, above edits origin no longer has"
  assert_eq "$second" "$(git rev-parse spec/idea-x)"
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
  own_tree_gone
}

test_writes_after_a_merge_and_a_prune_go_on_top_of_an_edit_whose_push_failed() {
  # What the record says origin held is in the base: the branch was merged and deleted,
  # not dropped, and the edit above it still waits to go out.
  own_tree_repo push
  _w_merged_and_moved_on
  git --git-dir=origin.git update-ref -d refs/heads/spec/idea-x
  git fetch -q --prune origin
  git remote set-url --push origin /nonexistent/origin.git
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":false'
  git remote set-url --push origin "$PWD/origin.git"
  _w_add "Third"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_contains "$OUT" '"commits":2'
  assert_contains "$OUT" '"pushed":true'
}

test_writes_whose_first_push_failed_go_on_top_and_push() {
  own_tree_repo push
  git remote set-url --push origin /nonexistent/origin.git
  _w_add "First"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"pushed":false'
  git remote set-url --push origin "$PWD/origin.git"
  _w_add "Second"
  assert_eq 0 "$RC"
  assert_contains "$OUT" '"branch":"spec/idea-x"'
  assert_contains "$OUT" '"commits":2'
  assert_contains "$OUT" '"pushed":true'
}

test_writes_refuse_to_strand_edits_never_sent_above_a_closed_pull_request() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  git remote set-url --push origin /nonexistent/origin.git
  _w_add "Second"
  git remote set-url --push origin "$PWD/origin.git"
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  _w_add "Third"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
  assert_contains "$OUT" "above edits whose pull request was closed unmerged"
  run jig writes ship spec:idea-x --json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"write-still-waits"'
}

test_writes_refuse_a_persons_commit_whatever_number_of_branches_origin_has() {
  own_tree_repo push
  local main i
  main=$(git rev-parse main)
  # More branch names than a Windows command line holds as arguments.
  i=0
  while [ "$i" -lt 2000 ]; do
    printf 'create refs/heads/many/branch-%04d %s\n' "$i" "$main"
    i=$((i + 1))
  done > refs.txt
  git --git-dir=origin.git update-ref --stdin < refs.txt
  rm refs.txt
  git switch -q -c spec/idea-x
  printf 'wip\n' > wip.txt
  git add wip.txt
  git commit -q -m "my unfinished wip"
  git switch -q main
  _w_add "New"
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"branch-has-other-commits"'
  assert_eq "" "$(git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x)"
}

# --- jig refresh closes what is over ----------------------------------------------

# _w_squash_then_moved — the write's pull request merged by squash, and the base changed
# the same file again after it: by ancestry and by content it still reads as waiting.
_w_squash_then_moved() {
  _w_on_origin_main squash spec/idea-x
  git -C "$PWD.other" switch -q --detach origin/main
  printf 'later\n' >> "$PWD.other/.ai/specs/idea-x/roadmap.md"
  git -C "$PWD.other" add -A .ai/specs/idea-x
  git -C "$PWD.other" commit -q -m "later"
  git -C "$PWD.other" push -q origin HEAD:refs/heads/main
  rm stub-gh/url
}

test_refresh_closes_a_write_a_squash_merged_and_the_base_moved_past() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_squash_then_moved
  printf 'MERGED\n' > stub-gh/state
  assert_contains "$(jig writes)" "spec:idea-x"
  run jig refresh --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"writes":[{"target":"spec:idea-x","branch":"spec/idea-x","reason":"merged"}]'
  assert_file_contains .ai/runtime/writes/spec-idea-x "merged: 1"
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
  # Closed once: the next refresh has nothing to close.
  run jig refresh
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "writes:"
}

test_refresh_says_in_words_which_write_it_closed() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_squash_then_moved
  printf 'MERGED\n' > stub-gh/state
  run jig refresh
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "writes: closed spec:idea-x on spec/idea-x (merged)"
}

test_refresh_leaves_a_write_whose_pull_request_is_still_open() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  printf 'OPEN\n' > stub-gh/state
  local before
  before=$(cat .ai/runtime/writes/spec-idea-x)
  run jig refresh --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"writes":[]'
  assert_eq "$before" "$(cat .ai/runtime/writes/spec-idea-x)"
  assert_contains "$(jig writes)" "spec:idea-x"
}

test_refresh_closes_a_write_whose_pull_request_was_closed_unmerged() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "Turned down"
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  run jig refresh --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"reason":"closed"'
  assert_file_contains .ai/runtime/writes/spec-idea-x "ended: closed"
  run jig writes --json
  assert_contains "$OUT" '"writes":[]'
}

# Judged on an old view, a write still open could read as over: without a fetch that
# reached origin, refresh asks the forge nothing.
test_refresh_after_a_failed_fetch_leaves_the_writes_alone() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_squash_then_moved
  printf 'MERGED\n' > stub-gh/state
  git fetch -q origin
  git remote set-url origin "$PWD/nowhere.git"
  local before
  before=$(cat .ai/runtime/writes/spec-idea-x)
  run jig refresh --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"fetch":{"outcome":"failed"'
  assert_contains "$OUT" '"writes":[]'
  assert_eq "$before" "$(cat .ai/runtime/writes/spec-idea-x)"
}

# Refresh is no write of Jig's: it closes a write at agent.git none too, since all it
# changes is the record.
test_refresh_closes_a_write_at_agent_git_none() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_squash_then_moved
  printf 'MERGED\n' > stub-gh/state
  own_tree_level none
  run jig refresh --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"reason":"merged"'
}


# Another write holds the lock: the record stays as it was, for the next refresh.
test_refresh_leaves_a_write_while_another_write_holds_the_lock() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "First"
  _w_squash_then_moved
  printf 'MERGED\n' > stub-gh/state
  mkdir -p .ai/runtime/writes/lock/busy
  # This shell lives, and it is not the jig below.
  printf 'checkout: elsewhere\npid: %s\n' "$$" > .ai/runtime/writes/lock/busy/run
  local before
  before=$(cat .ai/runtime/writes/spec-idea-x)
  run jig refresh --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"writes":[]'
  assert_eq "$before" "$(cat .ai/runtime/writes/spec-idea-x)"
  assert_contains "$(cat .ai/runtime/writes/lock/busy/run)" "pid: $$"
}

# What ot_judge refuses is `jig writes ship`'s to say: edits that never reached origin
# above a pull request closed unmerged leave the record as it was.
test_refresh_leaves_a_closed_write_with_edits_that_never_reached_origin() {
  own_tree_repo pr
  own_tree_stub_gh
  _w_add "Turned down"
  own_tree_level commit
  _w_add "Kept here"
  assert_eq 0 "$RC" "$OUT"
  printf 'CLOSED\n' > stub-gh/state
  rm stub-gh/url
  local before
  before=$(cat .ai/runtime/writes/spec-idea-x)
  run jig refresh --json
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" '"writes":[]'
  assert_eq "$before" "$(cat .ai/runtime/writes/spec-idea-x)"
  run jig writes ship spec:idea-x --json
  assert_contains "$OUT" '"code":"write-still-waits"'
}
