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

# _pr_stub_gh <dir> <head> — a gh that stands in for GitHub. `auth status`
# prints <dir>/auth; `auth token --user <login>` prints `tok-<login>` for an
# account <dir>/auth names. `api` answers each endpoint with a file of <dir>
# holding what its --jq filter would print — `api` (the pull request), `repo`,
# `compare`, `files`, `reviews`, `comments`; `<file>.<login>` first, the
# login being the one the token in GH_TOKEN stands for — and `user` with that
# login. A POST copies its --input file to <dir>/posted.<n>.<endpoint>, prints
# 900<n> as the new id, and lands every <dir>/*.landed file (the read-back
# after it). Every call goes to <dir>/calls and each filter to <dir>/jq.<file>.
_pr_stub_gh() {
  local main
  mkdir -p "$1"
  main=$(git rev-parse main)
  printf 'main\t%s\topen\t%s\tfalse\t2\n' "$2" "$main" > "$1/api"
  printf 'false true true false false false\n' > "$1/repo"
  printf '%s\n' "$main" > "$1/compare"
  printf 'F\tadded\t1\t1\nN\tfeature.txt\nH\t@@ -0,0 +1 @@\nF\tremoved\t1\t1\nN\told.txt\nH\t@@ -1 +0,0 @@\n' > "$1/files"
  : > "$1/reviews"
  : > "$1/comments"
  printf 'alice\n' > "$1/active"
  cat > "$1/auth" <<'EOF'
github.com
  ✓ Logged in to github.com account alice (keyring)
  - Active account: true
EOF
  cat > "$1/gh" <<STUB
#!/bin/sh
d='$1'
printf '%s\n' "\$*" >> "\$d/calls"
tok="\${GH_TOKEN:-\${GH_ENTERPRISE_TOKEN:-}}"
case "\$tok" in
  tok-*) who=\${tok#tok-} ;;
  '') who=\$(cat "\$d/active") ;;
  *) who=\$(cat "\$d/envlogin" 2>/dev/null || echo env) ;;
esac
case "\$1" in
  auth)
    case "\$2" in
      status) cat "\$d/auth"; exit 1 ;;
      token)
        shift 2
        user=""
        while [ \$# -gt 0 ]; do
          case "\$1" in --user) user="\$2"; shift 2 ;; *) shift ;; esac
        done
        [ ! -f "\$d/old-gh" ] || exit 1
        grep -q "account \$user " "\$d/auth" || exit 1
        printf 'tok-%s\n' "\$user"
        ;;
      *) exit 1 ;;
    esac
    ;;
  api)
    shift
    method=GET input="" ep="" jq=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --hostname) shift 2 ;;
        --jq) jq="\$2"; shift 2 ;;
        --method) method="\$2"; shift 2 ;;
        --input) input="\$2"; shift 2 ;;
        --paginate) shift ;;
        *) ep="\$1"; shift ;;
      esac
    done
    ep=\${ep%%\?*}
    case "\$ep" in
      user) printf '%s\n' "\$who"; exit 0 ;;
      repos/*/*/pulls/*/files) key=files ;;
      repos/*/*/pulls/*/reviews) key=reviews ;;
      repos/*/*/pulls/*/comments) key=comments ;;
      repos/*/*/compare/*) key=compare ;;
      repos/*/*/pulls/*) key=api ;;
      repos/*/*) key=repo ;;
      *) exit 1 ;;
    esac
    printf '%s\n' "\$jq" > "\$d/jq.\$key"
    if [ "\$method" = POST ]; then
      n=\$(cat "\$d/npost" 2>/dev/null || echo 0)
      n=\$((n + 1))
      echo "\$n" > "\$d/npost"
      cp "\$input" "\$d/posted.\$n.\$key"
      if [ -f "\$d/refuse-post" ]; then echo 'HTTP 422: Unprocessable Entity' >&2; exit 1; fi
      for f in "\$d"/*.landed; do
        if [ -f "\$f" ]; then mv "\$f" "\${f%.landed}"; fi
      done
      echo "900\$n"
      exit 0
    fi
    if [ -f "\$d/\$key.\$who" ]; then cat "\$d/\$key.\$who"
    elif [ -f "\$d/\$key" ]; then cat "\$d/\$key"
    else exit 1
    fi
    ;;
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
  assert_contains "$OUT" "login: ask (several accounts may comment: alice bob; active: alice)"
  # The right to comment, not to read: on a public repository bob reads, as
  # everybody does, and is not proposed.
  printf 'false true false false false false\n' > ../bin/repo.bob
  run jig pr fetch "$_pr_url"
  assert_contains "$OUT" "login: alice"
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

# --- comments: check ------------------------------------------------------------

# _pr_checked <draft lines>... — fetch, keep a draft with these blocks after
# the summary, and check it; the hash check printed in _pr_hash.
_pr_hash=""
_pr_checked() {
  run jig pr fetch "$_pr_url"
  assert_eq 0 "$RC" "$OUT"
  _pr_draft_file "$@"
  run jig pr draft 7 --from ../draft.md
  assert_eq 0 "$RC" "$OUT"
  run jig pr comments check 7
  assert_eq 0 "$RC" "$OUT"
  _pr_hash=$(printf '%s\n' "$OUT" | sed -n 's/^hash: //p')
  [ -n "$_pr_hash" ] || fail "check printed no hash: $OUT"
}

# _pr_valid_json <file> — the file is one JSON value, when a tool is here to
# say so.
_pr_valid_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -e . < "$1" >/dev/null || fail "not valid JSON: $(cat "$1")"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" || fail "not valid JSON: $(cat "$1")"
  fi
}

test_pr_comments_check_places_comments_and_prints_what_will_be_posted() {
  _pr_repo
  # shellcheck disable=SC2016 # a literal backtick: the text a review is made of
  _pr_checked '=== comment R1 feature.txt' 'Say "why", with a `tick` and a \ backslash.' '' \
    '=== comment L1 old.txt' 'Gone — на самом деле?' '' \
    '=== comment R5 feature.txt' 'Outside the diff.' '' \
    '=== personal R1 feature.txt' 'My own rule.'
  local head state
  head=$(git rev-parse refs/jig/pr/7/head)
  state=.git/jig/pr/7
  assert_contains "$OUT" "jig-pr-post: 1
url: $_pr_url
head: $head
login: alice
event: COMMENT

=== summary
Reads well."
  assert_contains "$OUT" "**R5 \`feature.txt\`**

Outside the diff."
  assert_contains "$OUT" "=== comment R1 feature.txt
Say \"why\""
  assert_contains "$OUT" "=== comment L1 old.txt"
  assert_contains "$OUT" "<!-- jig-pr-review id=$_pr_hash head=$head part=0 -->"
  assert_contains "$OUT" "<!-- jig-pr-review id=$_pr_hash head=$head part=2 -->"
  assert_not_contains "$OUT" "My own rule"
  assert_contains "$OUT" "moved into the summary: 1 comment(s)"
  assert_contains "$OUT" "left out: 1 personal block(s)"
  assert_file "$state/payload.json"
  _pr_valid_json "$state/payload.json"
  assert_file_contains "$state/payload.json" "\"commit_id\":\"$head\",\"event\":\"COMMENT\""
  assert_file_contains "$state/payload.json" '"path":"old.txt"'
  assert_file_contains "$state/payload.json" '"line":1,"side":"LEFT"'
  # shellcheck disable=SC2016 # the same backtick, escaped as JSON
  assert_contains "$(cat "$state/payload.json")" 'Say \"why\", with a `tick` and a \\ backslash.'
  assert_file_contains "$state/shown" "hash: $_pr_hash"
  # The same draft and the same diff are the same version.
  run jig pr comments check 7
  assert_contains "$OUT" "hash: $_pr_hash"
  # Nothing was posted, and no token reached an argument.
  if grep -q 'POST' ../bin/calls; then fail "check posted"; fi
  if grep -q 'tok-' ../bin/calls; then fail "a token was an argument"; fi
  if grep -q 'auth switch' ../bin/calls; then fail "the active account was switched"; fi
}

test_pr_comments_check_maps_renames_and_ranges_from_githubs_diff() {
  _pr_repo
  # GitHub's diff: old.txt renamed to feature.txt, two hunks, and a binary
  # file it shows no patch for.
  printf 'F\trenamed\t9\t1\nN\tfeature.txt\nO\told.txt\nH\t@@ -1,3 +1,4 @@ func\nH\t@@ -10,2 +11,3 @@\nF\tadded\t0\t0\nN\tlogo.png\nF\trenamed\t0\t0\nN\tb.txt\nO\ta.txt\nF\tmodified\t5000\t0\nN\tbig.txt\n' > ../bin/files
  _pr_checked '=== comment L1-2 old.txt' 'Old lines.' '' '=== comment R2-4 feature.txt' 'New lines.' '' \
    '=== comment R3-12 feature.txt' 'Across two hunks.' '' '=== comment R12 feature.txt' 'Second hunk.'
  local state=.git/jig/pr/7
  assert_contains "$OUT" "=== comment L1-2 feature.txt"
  assert_contains "$OUT" "=== comment R2-4 feature.txt"
  assert_contains "$OUT" "=== comment R12 feature.txt"
  assert_contains "$OUT" "**R3-12 \`feature.txt\`**"
  assert_contains "$OUT" "Not in GitHub's diff, so not commented on: \`logo.png\`, \`big.txt\`."
  assert_file_contains "$state/payload.json" '"path":"feature.txt","body":"Old lines.'
  assert_file_contains "$state/payload.json" '"line":2,"side":"LEFT","start_line":1,"start_side":"LEFT"'
  assert_file_contains "$state/payload.json" '"line":4,"side":"RIGHT","start_line":2,"start_side":"RIGHT"'
  assert_file_contains "$state/payload.json" '"line":12,"side":"RIGHT"}'
  _pr_valid_json "$state/payload.json"
}

test_pr_comments_check_names_the_files_github_does_not_list() {
  _pr_repo
  # GitHub lists one of the two files the pull request changes.
  printf 'F\tadded\t1\t1\nN\tfeature.txt\nH\t@@ -0,0 +1 @@\n' > ../bin/files
  _pr_checked
  assert_contains "$OUT" "Not in GitHub's diff, so not commented on: \`old.txt\`."
}

test_pr_comments_check_refuses_what_does_not_hold() {
  _pr_repo
  _pr_checked
  local head
  head=$(git rev-parse refs/jig/pr/7/head)
  # The head moved on GitHub since the review.
  cp ../bin/api ../bin/api.kept
  printf 'main\t%s\topen\t%s\tfalse\t2\n' 0123456789012345678901234567890123456789 "$(git rev-parse main)" > ../bin/api
  run jig pr comments check 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "moved since it was reviewed"
  cp ../bin/api.kept ../bin/api
  # GitHub's diff starts elsewhere.
  cp ../bin/compare ../bin/compare.kept
  printf '%s\n' "$head" > ../bin/compare
  run jig pr comments check 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "GitHub's diff starts at $head"
  cp ../bin/compare.kept ../bin/compare
  # The login cannot see the repository.
  printf 'true false false false false false\n' > ../bin/repo.alice
  run jig pr comments check 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "alice cannot reach acme/widget"
  # It reads, but the conversation is locked.
  printf 'false true false false false false\n' > ../bin/repo.alice
  printf 'main\t%s\topen\t%s\ttrue\t2\n' "$head" "$(git rev-parse main)" > ../bin/api
  run jig pr comments check 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is locked"
  cp ../bin/api.kept ../bin/api
  rm ../bin/repo.alice
  # The token in hand is somebody else's.
  rm .git/jig/pr/7/shown
  printf 'mallory\n' > ../bin/envlogin
  printf 'github.com\n  ✓ Logged in to github.com account carol (keyring)\n' > ../bin/auth
  touch ../bin/old-gh
  GH_TOKEN=secret run jig pr comments check 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the token for alice answers as mallory"
  assert_not_contains "$OUT" "secret"
  assert_no_file .git/jig/pr/7/shown
}

# --- comments: post -------------------------------------------------------------

# _pr_landed <hash> <parts>... — what GitHub will hold after the next POST:
# the summary's review and comments 1.. with their markers, by alice.
_pr_landed() {
  local h="$1" head k
  shift
  head=$(git rev-parse refs/jig/pr/7/head)
  : > ../bin/reviews.landed
  : > ../bin/comments.landed
  for k in "$@"; do
    if [ "$k" = 0 ]; then
      printf '9001\talice\tid=%s head=%s part=0\t%s#pullrequestreview-9001\n' "$h" "$head" "$_pr_url" >> ../bin/reviews.landed
    else
      printf '%s\talice\tid=%s head=%s part=%s\t1\tRIGHT\tnull\t%s#discussion_r%s\tfeature.txt\n' "$k" "$h" "$head" "$k" "$_pr_url" "$k" >> ../bin/comments.landed
    fi
  done
}

test_pr_comments_post_posts_the_shown_version_once_and_reads_it_back() {
  _pr_repo
  _pr_checked '=== comment R1 feature.txt' 'Say why.' '' '=== comment L1 old.txt' 'Gone?'
  local state=.git/jig/pr/7
  _pr_landed "$_pr_hash" 0 1 2
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "posted as: alice"
  assert_contains "$OUT" "review: $_pr_url#pullrequestreview-9001"
  assert_contains "$OUT" "landed: summary"
  assert_contains "$OUT" "landed: comment R1 feature.txt at RIGHT 1 feature.txt"
  assert_contains "$OUT" "landed: comment L1 old.txt at"
  # One review, its body the payload check wrote, sent as a file.
  assert_eq 1 "$(cat ../bin/npost)"
  assert_eq "$(cat "$state/payload.json")" "$(cat ../bin/posted.1.reviews)"
  _pr_valid_json ../bin/posted.1.reviews
  assert_contains "$(cat ../bin/calls)" "--method POST repos/acme/widget/pulls/7/reviews --input"
  assert_file_contains "$state/posted" "review: 9001"
  if grep -q 'tok-' ../bin/calls; then fail "a token was an argument"; fi
  if grep -q 'auth switch' ../bin/calls; then fail "the active account was switched"; fi
  # Again: everything is there, nothing is posted twice.
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "already posted: nothing is missing"
  assert_eq 1 "$(cat ../bin/npost)"
}

test_pr_comments_post_refuses_anything_but_the_version_shown() {
  _pr_repo
  run jig pr fetch "$_pr_url"
  _pr_draft_file '=== comment R1 feature.txt' 'Say why.'
  run jig pr draft 7 --from ../draft.md
  run jig pr comments post 7 --shown 0123
  assert_eq 1 "$RC"
  assert_contains "$OUT" "nothing was shown for pull request 7"
  run jig pr comments check 7
  local h
  h=$(printf '%s\n' "$OUT" | sed -n 's/^hash: //p')
  run jig pr comments post 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--shown <hash> is required"
  run jig pr comments post 7 --shown 0123
  assert_eq 1 "$RC"
  assert_contains "$OUT" "0123 is not the version shown last ($h)"
  # The draft changed after it was shown.
  _pr_draft_file '=== comment R1 feature.txt' 'Say why, edited.'
  run jig pr draft 7 --from ../draft.md
  run jig pr comments post 7 --shown "$h"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is not what was shown ($h)"
  # The head moved after it was shown.
  _pr_draft_file '=== comment R1 feature.txt' 'Say why.'
  run jig pr draft 7 --from ../draft.md
  printf 'main\t%s\topen\t%s\tfalse\t2\n' 0123456789012345678901234567890123456789 "$(git rev-parse main)" > ../bin/api
  run jig pr comments post 7 --shown "$h"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "moved since it was reviewed"
  assert_no_file ../bin/npost "something was posted"
}

test_pr_comments_post_posts_only_what_is_missing_after_a_half_done_post() {
  _pr_repo
  _pr_checked '=== comment R1 feature.txt' 'Say why.' '' '=== comment L1 old.txt' 'Gone?'
  # The summary and comment 1 landed; the answer was lost.
  _pr_landed "$_pr_hash" 0 1
  mv ../bin/reviews.landed ../bin/reviews
  mv ../bin/comments.landed ../bin/comments
  _pr_landed "$_pr_hash" 0 1 2
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 0 "$RC" "$OUT"
  assert_eq 1 "$(cat ../bin/npost)"
  assert_file ../bin/posted.1.comments
  _pr_valid_json ../bin/posted.1.comments
  assert_file_contains ../bin/posted.1.comments '"path":"old.txt"'
  assert_file_contains ../bin/posted.1.comments "\"commit_id\":\"$(git rev-parse refs/jig/pr/7/head)\""
  assert_file_contains ../bin/posted.1.comments "part=2 -->"
  assert_contains "$OUT" "landed: summary"
  # A post that leaves a part missing says so and how to finish it.
  rm -f ../bin/npost ../bin/posted.*
  _pr_landed "$_pr_hash" 0
  mv ../bin/reviews.landed ../bin/reviews
  mv ../bin/comments.landed ../bin/comments
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "missing: comment R1 feature.txt"
  assert_contains "$OUT" "half-done: 1 of 3 parts landed; run jig pr comments post 7 --shown $_pr_hash again"
}

test_pr_comments_post_refuses_where_a_retry_could_duplicate() {
  _pr_repo
  _pr_checked '=== comment R1 feature.txt' 'Say why.'
  local head
  head=$(git rev-parse refs/jig/pr/7/head)
  # Another version of a review of this head, by the same login, is there.
  printf '8001\talice\tid=%s head=%s part=0\t%s#pullrequestreview-8001\n' 0000 "$head" "$_pr_url" > ../bin/reviews
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already posted another version of a review of this head: $_pr_url#pullrequestreview-8001"
  # A half-done other version left only a comment.
  : > ../bin/reviews
  printf '3\talice\tid=%s head=%s part=1\t1\tRIGHT\tnull\t%s#discussion_r3\tfeature.txt\n' 0000 "$head" "$_pr_url" > ../bin/comments
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already posted another version of a review of this head: $_pr_url#discussion_r3"
  : > ../bin/comments
  # By somebody else, it is not ours to count.
  printf '8001\tbob\tid=%s head=%s part=0\t%s#pullrequestreview-8001\n' 0000 "$head" "$_pr_url" > ../bin/reviews
  # GitHub refuses the review: nothing landed, and it says why.
  touch ../bin/refuse-post
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "HTTP 422"
  assert_contains "$OUT" "nothing landed on $_pr_url"
  assert_no_file .git/jig/pr/7/posted
  # GitHub took it, but no marker came back: never post again blindly.
  rm ../bin/refuse-post
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "GitHub took review 9002, but none of its markers came back"
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "this version was posted as review 9002, but GitHub shows none of its markers"
  assert_eq 2 "$(cat ../bin/npost)"
}

test_pr_comments_filters_print_what_the_stub_stands_in_for() {
  command -v jq >/dev/null 2>&1 || skip "jq is not here to run gh's filters"
  _pr_repo
  _pr_checked '=== comment R1 feature.txt' 'Say why.'
  local head
  head=$(git rev-parse refs/jig/pr/7/head)
  # The filters jig gave gh, run over what GitHub answers.
  printf '[{"filename":"b.txt","previous_filename":"a.txt","status":"renamed","changes":3,"patch":"@@ -1,2 +1,3 @@ x\\n a\\n+b\\n@@ -9 +10 @@\\n-c\\n+d"},{"filename":"logo.png","status":"added","changes":0},{"filename":"big.txt","status":"modified","changes":900}]' > ../files.json
  assert_eq "$(printf 'F\trenamed\t3\t1\nN\tb.txt\nO\ta.txt\nH\t@@ -1,2 +1,3 @@ x\nH\t@@ -9 +10 @@\nF\tadded\t0\t0\nN\tlogo.png\nF\tmodified\t900\t0\nN\tbig.txt')" \
    "$(jq -r "$(cat ../bin/jq.files)" < ../files.json)"
  printf '{"base":{"ref":"main","sha":"b1"},"head":{"sha":"%s"},"state":"open","locked":false,"changed_files":3}' "$head" > ../pull.json
  assert_eq "$(printf 'main\t%s\topen\tb1\tfalse\t3' "$head")" "$(jq -r "$(cat ../bin/jq.api)" < ../pull.json)"
  printf '{"private":false,"permissions":{"admin":false,"maintain":false,"push":true,"triage":false,"pull":true}}' > ../repo.json
  assert_eq "false true true false false false" "$(jq -r "$(cat ../bin/jq.repo)" < ../repo.json)"
  printf '{"merge_base_commit":{"sha":"m1"}}' > ../compare.json
  assert_eq "m1" "$(jq -r "$(cat ../bin/jq.compare)" < ../compare.json)"
  _pr_landed "$_pr_hash" 0 1
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 0 "$RC" "$OUT"
  printf '[{"id":5,"user":{"login":"alice"},"body":"Text\\n\\n<!-- jig-pr-review id=h1 head=h2 part=0 -->","html_url":"u5"},{"id":6,"user":{"login":"bob"},"body":null,"html_url":"u6"}]' > ../reviews.json
  assert_eq "$(printf '5\talice\tid=h1 head=h2 part=0\tu5')" "$(jq -r "$(cat ../bin/jq.reviews)" < ../reviews.json)"
  printf '[{"id":7,"user":{"login":"alice"},"body":"x\\n\\n<!-- jig-pr-review id=h1 head=h2 part=1 -->","line":4,"side":"LEFT","start_line":2,"html_url":"u7","path":"a b.txt"},{"id":8,"user":{"login":"alice"},"body":"plain","line":1,"side":"RIGHT","start_line":null,"html_url":"u8","path":"c"}]' > ../comments.json
  assert_eq "$(printf '7\talice\tid=h1 head=h2 part=1\t4\tLEFT\t2\tu7\ta b.txt')" "$(jq -r "$(cat ../bin/jq.comments)" < ../comments.json)"
}

test_pr_cleanup_takes_back_what_check_and_post_wrote() {
  _pr_repo
  _pr_checked '=== comment R1 feature.txt' 'Say why.'
  _pr_landed "$_pr_hash" 0 1
  run jig pr comments post 7 --shown "$_pr_hash"
  assert_eq 0 "$RC" "$OUT"
  assert_file .git/jig/pr/7/posted
  printf 'x\n' > .git/jig/pr/7/part-3.json
  printf 'mine\n' > .git/jig/pr/7/part-2-notes.json
  run jig pr cleanup 7
  assert_eq 0 "$RC" "$OUT"
  assert_no_file .git/jig/pr/7/part-3.json
  assert_file .git/jig/pr/7/part-2-notes.json "cleanup deleted a file jig did not write"
  assert_contains "$OUT" "holds files jig did not write"
  rm .git/jig/pr/7/part-2-notes.json
  run jig pr cleanup 7
  assert_no_file .git/jig/pr/7
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
