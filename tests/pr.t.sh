# Tests for `jig pr` (scripts/lib/pr.sh;
# adr-20261109-a-pull-request-is-read-in-a-detached-tree-of-the-clone): a
# GitHub pull request fetched into refs of Jig's own and a detached worktree,
# the person's checkout untouched, nothing of the head run, the draft checked
# and printed as it is shown, and cleanup taking back only what fetch made.
# shellcheck shell=bash

# _pr_repo [jig] — the test directory holds `origin.git` (bare), `bin/gh` (a
# stub) and `clone/`, the person's clone, which the test is left in. The clone
# reaches origin as https://github.com/acme/widget.git through insteadOf, and
# origin publishes pull request 7 as refs/pull/7/head: one commit adding
# feature.txt on top of main, a branch the clone itself never had. With `jig`,
# Jig is installed in the clone.
_pr_repo() {
  local top="$PWD" sha
  git init -q --bare origin.git
  mkdir clone
  cd clone || return 1
  if [ "${1:-}" = jig ]; then
    fixture_jig_repo
    git add -A >/dev/null 2>&1
    git commit -q -m "install jig" >/dev/null 2>&1 || true
  else
    fixture_repo
  fi
  printf 'old\n' > old.txt
  git add old.txt
  git commit -q -m "old"
  git push -q "$top/origin.git" main
  git checkout -q -b feature
  printf 'new\n' > feature.txt
  git rm -q old.txt
  git add feature.txt
  git commit -q -m "feature"
  git push -q "$top/origin.git" feature:refs/pull/7/head
  git checkout -q main
  git branch -q -D feature
  git remote add origin https://github.com/acme/widget.git
  git config url."$top/origin.git".insteadOf https://github.com/acme/widget.git
  sha=$(git --git-dir="$top/origin.git" rev-parse refs/pull/7/head)
  _pr_stub_gh "$top/bin" "$sha"
  PATH="$top/bin:$PATH"
  export PATH
  unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
}

# _pr_stub_gh <dir> <head> — a gh that answers `api` with <dir>/api (base,
# head, state; tab-separated) and `auth status` with <dir>/auth, and logs
# every call to <dir>/calls.
_pr_stub_gh() {
  mkdir -p "$1"
  printf 'main\t%s\topen\n' "$2" > "$1/api"
  cat > "$1/auth" <<'EOF'
github.com
  ✓ Logged in to github.com account alice (keyring)
  - Active account: true
EOF
  cat > "$1/gh" <<STUB
#!/bin/sh
d='$1'
printf '%s\n' "\$*" >> "\$d/calls"
case "\$1" in
  api) cat "\$d/api" ;;
  auth) cat "\$d/auth"; exit 1 ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$1/gh"
}

_pr_url="https://github.com/acme/widget/pull/7"

# A draft that keeps schemas/pr-draft.md for the fetched pull request; extra
# lines go after the summary.
_pr_draft_file() {
  local head
  head=$(git rev-parse refs/jig/pr/7/head)
  {
    printf 'jig-pr-draft: 1\nurl: %s\nhead: %s\nlogin: alice\nlanguage: en\n\n' "$_pr_url" "$head"
    printf '=== summary\nReads well.\n\n'
    printf '%s\n' "$@"
  } > ../draft.md
}

# --- fetch --------------------------------------------------------------------

test_pr_fetch_makes_refs_and_a_detached_worktree_and_leaves_the_checkout_alone() {
  _pr_repo
  # The person's own work in progress, on another branch.
  git checkout -q -b mine
  printf 'wip\n' >> README.md
  printf 'staged\n' > staged.txt
  git add staged.txt
  local before_head before_index before_refs head
  before_head=$(git rev-parse HEAD)
  before_index=$(git diff --cached --name-only)
  before_refs=$(git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/remotes)
  run jig pr fetch "$_pr_url/files"
  assert_eq 0 "$RC" "$OUT"
  head=$(git --git-dir=../origin.git rev-parse refs/pull/7/head)
  assert_eq "$head" "$(git rev-parse refs/jig/pr/7/head)"
  assert_eq "$(git rev-parse main)" "$(git rev-parse refs/jig/pr/7/base)"
  assert_contains "$OUT" "pull request: $_pr_url (open)"
  assert_contains "$OUT" "head: $head (the reviewed head)"
  assert_contains "$OUT" "merge base: $(git rev-parse main)"
  assert_contains "$OUT" "login: alice"
  local wt
  wt=$(cd -P .. && pwd -P)/clone.worktrees/.pr-7
  assert_contains "$OUT" "worktree: $wt"
  assert_file "$wt/feature.txt"
  assert_eq "$head" "$(git -C "$wt" rev-parse HEAD)"
  if git -C "$wt" symbolic-ref -q HEAD >/dev/null; then fail "the worktree is on a branch"; fi
  assert_eq "$before_head" "$(git rev-parse HEAD)"
  assert_eq "mine" "$(git symbolic-ref --short HEAD)"
  assert_eq "$before_index" "$(git diff --cached --name-only)"
  assert_contains "$(git diff --name-only)" "README.md"
  assert_eq "$before_refs" "$(git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/remotes)"
  assert_no_file .git/FETCH_HEAD
  # Without Jig here, the record is in the clone's git directory, not its tree.
  assert_file .git/jig/pr/7/record
  assert_file_contains .git/jig/pr/7/record "head: $head"
  assert_file_contains .git/jig/pr/7/record "merge_base: $(git rev-parse main)"
  assert_eq "" "$(git status --porcelain --untracked-files=all | grep -v -e README.md -e staged.txt || true)"
}

test_pr_fetch_runs_no_hook_of_the_head() {
  _pr_repo
  # The project keeps its hooks in the tree, and the pull request brings one.
  local top
  top=$(cd .. && pwd)
  git config core.hooksPath .githooks
  git checkout -q -b hook refs/heads/main
  mkdir .githooks
  printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$top" > .githooks/post-checkout
  chmod +x .githooks/post-checkout
  git add .githooks
  git -c core.hooksPath=/dev/null commit -q -m "hook"
  git push -q ../origin.git hook:refs/pull/7/head --force
  git -c core.hooksPath=/dev/null checkout -q main
  rm -f "$top/hook-ran"
  printf 'main\t%s\topen\n' "$(git rev-parse hook)" > ../bin/api
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  assert_file "$top/clone.worktrees/.pr-7/.githooks/post-checkout"
  assert_no_file "$top/hook-ran" "a hook from the pull request ran"
}

test_pr_fetch_keeps_its_state_in_the_workspace_when_jig_is_installed() {
  _pr_repo jig
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  assert_file .ai/workspace/pr/7/record
  assert_no_file .git/jig/pr/7/record
  assert_eq "" "$(git status --porcelain)"
}

test_pr_fetch_refuses_what_it_cannot_review() {
  _pr_repo
  run jig pr fetch "https://gitlab.com/acme/widget/-/merge_requests/7"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "GitLab merge requests are not supported yet"
  run jig pr fetch "https://github.com/acme/widget/issues/7"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a pull request URL"
  run jig pr fetch "https://github.com/acme/widget/pull/07"
  assert_eq 1 "$RC"
  run jig pr fetch "https://github.com/acme/other/pull/7"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no remote of this clone reaches acme/other on github.com"
  if git rev-parse --verify --quiet refs/jig/pr/7/head >/dev/null; then fail "a refusal fetched"; fi
}

test_pr_fetch_finds_the_remote_by_ssh_and_case() {
  _pr_repo
  git remote set-url origin git@github.com:Acme/Widget.git
  git config url."$(cd .. && pwd)/origin.git".insteadOf git@github.com:Acme/Widget.git
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "remote: origin"
}

test_pr_fetch_refuses_a_head_that_moved_while_it_fetched() {
  _pr_repo
  printf 'main\t%s\topen\n' "0123456789012345678901234567890123456789" > ../bin/api
  run jig pr fetch "$_pr_url"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "moved while it was fetched"
  assert_no_file ../clone.worktrees/.pr-7/feature.txt
}

test_pr_fetch_again_moves_the_worktree_to_the_new_head() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  git checkout -q -b more refs/jig/pr/7/head
  printf 'more\n' > more.txt
  git add more.txt
  git commit -q -m "more"
  git push -q ../origin.git more:refs/pull/7/head --force
  git checkout -q main
  printf 'main\t%s\topen\n' "$(git rev-parse more)" > ../bin/api
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  assert_eq "$(git rev-parse more)" "$(git -C ../clone.worktrees/.pr-7 rev-parse HEAD)"
  assert_file_contains .git/jig/pr/7/record "head: $(git rev-parse more)"
}

test_pr_fetch_refuses_the_same_number_of_another_repository() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  git remote add upstream https://github.com/other/widget.git
  run jig pr fetch "https://github.com/other/widget/pull/7"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is already $_pr_url; jig pr cleanup 7 first"
}

test_pr_fetch_refuses_a_path_in_the_way() {
  _pr_repo
  mkdir -p ../clone.worktrees/.pr-7
  printf 'mine\n' > ../clone.worktrees/.pr-7/notes.txt
  run jig pr fetch "$_pr_url"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is in the way"
  assert_file ../clone.worktrees/.pr-7/notes.txt
}

test_pr_fetch_asks_for_the_login_when_it_is_not_one() {
  _pr_repo
  cat > ../bin/auth <<'EOF'
github.com
  ✓ Logged in to github.com account alice (keyring)
  - Active account: true
  X Failed to log in to github.com account broken (keyring)
  ✓ Logged in to github.com account bob (keyring)
  - Active account: false
EOF
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "login: ask (several accounts: alice bob; active: alice)"
  printf 'github.com\n  ✓ Logged in to github.com account alice (keyring)\n' > ../bin/auth
  GH_TOKEN=secret run jig pr fetch "$_pr_url"
  assert_contains "$OUT" "login: ask (GH_TOKEN in the environment overrides every gh account)"
  assert_not_contains "$OUT" "secret"
  run jig pr fetch "$_pr_url"
  assert_contains "$OUT" "login: alice"
}

test_pr_refuses_to_run_inside_a_review_tree() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  cd ../clone.worktrees/.pr-7 || fail "no review tree"
  run jig pr cleanup 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is a pull request's review tree; run jig pr in your own checkout"
  assert_file feature.txt
}

# --- draft --------------------------------------------------------------------

test_pr_draft_keeps_a_good_draft_and_prints_it_as_it_is() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  _pr_draft_file '=== comment R1 feature.txt' 'Say why.' '' '=== comment L1 old.txt' 'Gone?' \
    '=== personal R1 feature.txt' 'My own rule.'
  run jig pr draft 7 --from ../draft.md
  assert_eq 0 "$RC" "$OUT"
  assert_eq "jig: draft: $(cd -P .git && pwd -P)/jig/pr/7/draft.md
$(cat ../draft.md)" "$OUT"
  run jig pr draft "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "=== personal R1 feature.txt"
  # A draft saved with CRLF is kept, and shown, without the CRs.
  sed 's/$/\r/' ../draft.md > ../crlf.md
  run jig pr draft 7 --from ../crlf.md
  assert_eq 0 "$RC" "$OUT"
  if grep -q "$(printf '\r')" .git/jig/pr/7/draft.md; then fail "a CR was kept"; fi
}

test_pr_draft_refuses_what_does_not_match_the_fetch() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  local head
  head=$(git rev-parse refs/jig/pr/7/head)
  printf 'jig-pr-draft: 1\nurl: %s\nhead: %s\nlogin: alice\nlanguage: en\n\n=== summary\nx\n' \
    "$_pr_url" "$(git rev-parse main)" > ../draft.md
  run jig pr draft 7 --from ../draft.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" "but the reviewed head is $head"
  printf 'jig-pr-draft: 1\nurl: %s\nhead: %s\nlogin: mallory\nlanguage: en\n\n=== summary\nx\n' \
    "$_pr_url" "$head" > ../draft.md
  run jig pr draft 7 --from ../draft.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" "gh holds no account mallory"
  assert_no_file .git/jig/pr/7/draft.md
}

test_pr_draft_refuses_a_malformed_draft() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  local bad
  for bad in '=== comment X1 feature.txt|a position is' '=== comment R0 feature.txt|a position is' \
    '=== comment R5-3 feature.txt|ends after it starts' '=== comment R1 nope.txt|not a file of the reviewed head' \
    '=== comment L1 feature.txt|not a file of the merge base' '=== comment R1 ../feature.txt|without . or ..' \
    '=== summary|a second summary' '=== note R1 feature.txt|unknown block' \
    '=== comment R1 feature.txt|the last block is empty'; do
    _pr_draft_file "${bad%%|*}" 'text'
    if [ "${bad##*|}" = "the last block is empty" ]; then _pr_draft_file "${bad%%|*}"; fi
    run jig pr draft 7 --from ../draft.md
    assert_eq 1 "$RC" "$bad"
    assert_contains "$OUT" "${bad##*|}"
  done
  printf 'jig-pr-draft: 1\nurl: %s\n\n=== summary\nx\n' "$_pr_url" > ../draft.md
  run jig pr draft 7 --from ../draft.md
  assert_contains "$OUT" "the header has no head"
}

test_pr_draft_needs_a_fetch_first() {
  _pr_repo
  printf 'x\n' > ../draft.md
  run jig pr draft 7 --from ../draft.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" "pull request 7 is not fetched here"
}

# --- list and cleanup ---------------------------------------------------------

test_pr_cleanup_takes_back_the_worktree_the_refs_and_the_state() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  _pr_draft_file
  run jig pr draft 7 --from ../draft.md
  run jig pr list
  assert_contains "$OUT" "7 $_pr_url head=$(git rev-parse refs/jig/pr/7/head)"
  assert_contains "$OUT" "draft=yes"
  run jig pr cleanup "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  assert_no_file ../clone.worktrees/.pr-7
  assert_eq "" "$(git for-each-ref refs/jig)"
  assert_no_file .git/jig/pr/7
  assert_eq "" "$(git worktree list --porcelain | grep detached || true)"
  run jig pr list
  assert_contains "$OUT" "no pull requests fetched in this clone"
  run jig pr cleanup 7
  assert_eq 0 "$RC"
  assert_contains "$OUT" "nothing to clean up for pull request 7"
}

test_pr_cleanup_keeps_a_worktree_with_changes() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  printf 'edited\n' >> ../clone.worktrees/.pr-7/feature.txt
  run jig pr cleanup 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "git kept the worktree"
  assert_file ../clone.worktrees/.pr-7/feature.txt
  git rev-parse --verify --quiet refs/jig/pr/7/head >/dev/null || fail "the ref went with the worktree kept"
  assert_file .git/jig/pr/7/record
}

test_pr_cleanup_leaves_a_worktree_with_a_branch_alone() {
  _pr_repo
  git worktree add -q -b by-hand ../clone.worktrees/.pr-7
  run jig pr cleanup 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "has a branch checked out"
  assert_dir ../clone.worktrees/.pr-7
}

# --- housekeeping -------------------------------------------------------------

test_pr_housekeeping_leaves_a_fetched_pull_request_alone() {
  _pr_repo jig
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  local head
  head=$(git rev-parse refs/jig/pr/7/head)
  run jig housekeeping --verbose
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" ".pr-7"
  assert_file ../clone.worktrees/.pr-7/feature.txt
  assert_eq "$head" "$(git rev-parse refs/jig/pr/7/head)"
  assert_file .ai/workspace/pr/7/record
  if grep -q 'pr-7' .ai/runtime/housekeeping.log 2>/dev/null; then fail "housekeeping logged the review tree"; fi
}

test_pr_usage() {
  _pr_repo
  run jig pr
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig pr fetch <url>"
  run jig pr bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown subcommand: bogus"
  run jig help
  assert_contains "$OUT" "pr fetch <url>"
}
