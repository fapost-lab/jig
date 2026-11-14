# Tests for a person's actions on a task's pull request (scripts/lib/prdo.sh;
# adr-20261114-a-persons-pull-request-action-does-not-read-agent-git):
# `jig task request-review`, `jig task merge-pr` and `jig task pr-status`, on a
# gh and a glab that answer from files.
# shellcheck shell=bash

# --- fixtures ------------------------------------------------------------------

# pd_split <command...> — run it with stdout in OUT and stderr in ERR.
pd_split() {
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

# pd_code — the failure code of the envelope in OUT.
pd_code() {
  printf '%s\n' "$OUT" | sed -n 's/.*"error":{"code":"\([^"]*\)".*/\1/p'
}

# pd_cfg_local <key> <value> — a key of .ai/config.local.yaml.
pd_cfg_local() {
  touch .ai/config.local.yaml
  grep -v "^$1:" .ai/config.local.yaml > c.tmp || true
  printf '%s: %s\n' "$1" "$2" >> c.tmp
  mv c.tmp .ai/config.local.yaml
}

# pd_stub_gh — a `gh` that answers from files in the test directory and logs
# every call to gh.log:
#   gh-view      `<STATE>|<isDraft>|<base>|<head>|<mergeable>|<mergeStateStatus>`
#                (default: an open, clean pull request at HEAD into main);
#                gh-view.fail makes `pr view` fail
#   gh-review    `<decision>|<latest review states>|<requested reviewers>`
#   gh-checks    one check a line: name, bucket, link, started, completed, tabbed
#   gh-rules     `<approvals>|<required checks>`; gh-rules.fail fails the call
#   gh-merge.rc / gh-edit.rc  the exit codes of `pr merge` and `pr edit`
# `pr merge` and `pr edit` keep their arguments in gh-merge.argv, gh-edit.argv.
pd_stub_gh() {
  mkdir -p stub-bin
  cat > stub-bin/gh <<'STUB'
#!/usr/bin/env bash
d="$PD_DIR"
printf '%s\n' "$*" >> "$d/gh.log"
val() { if [ -f "$d/$1" ]; then cat "$d/$1"; else printf '%s\n' "$2"; fi; }
view() {
  if [ -f "$d/gh-view.fail" ]; then printf 'HTTP 502: bad gateway\n' >&2; exit 1; fi
  val gh-view "OPEN|false|main|$(git -C "$d" rev-parse HEAD)|MERGEABLE|CLEAN"
}
checks() {
  val gh-checks "$(printf 'test\tpass\thttps://ci.example/1\t2026-11-13T10:00:00Z\t2026-11-13T10:07:00Z')"
}
case "$1 $2" in
  "auth status") exit 0 ;;
  "api user") val gh-self me ;;
  "api graphql") printf 'alice\tAlice Smith\nbob\tBob Sikora\nme\tMe Myself\n' ;;
  "api repos/{owner}/{repo}/rules/branches/main")
    [ ! -f "$d/gh-rules.fail" ] || { printf 'HTTP 403\n' >&2; exit 1; }
    val gh-rules "1|test" ;;
  "pr list") ;;
  "pr view")
    case "$*" in
      *reviewDecision*) val gh-review "|" ;;
      *"--json state,isDraft"*) view ;;
      *"--json state --jq"*) view | cut -d'|' -f1 ;;
      *"isDraft,headRefOid"*) view | awk -F'|' '{ print $2, $4 }' ;;
    esac ;;
  "pr checks")
    case "$*" in
      *"--json bucket"*) checks | cut -f2 ;;
      *) checks ;;
    esac
    [ ! -f "$d/gh-checks.pending" ] || exit 8 ;;
  "repo view") val gh-repo "true true true" ;;
  "pr merge")
    shift 2
    printf '%s\n' "$@" > "$d/gh-merge.argv"
    rc=$(val gh-merge.rc 0)
    [ "$rc" -eq 0 ] || printf 'GraphQL: Base branch policy prohibits the merge\n' >&2
    exit "$rc" ;;
  "pr edit")
    shift 2
    printf '%s\n' "$@" > "$d/gh-edit.argv"
    rc=$(val gh-edit.rc 0)
    [ "$rc" -eq 0 ] || printf 'GraphQL: Resource not accessible\n' >&2
    exit "$rc" ;;
esac
STUB
  chmod +x stub-bin/gh
}

# pd_stub_glab — the same for `glab`, logged to glab.log:
#   glab-mr        the merge request's JSON (default: open, clean, at HEAD)
#   glab-jobs      the head pipeline's jobs
#   glab-approvals the approvals endpoint's answer
#   glab-merge.rc / glab-update.rc  the exit codes of `mr merge` and `mr update`
# `mr merge` and `mr update` keep their arguments in glab-merge.argv and
# glab-update.argv.
pd_stub_glab() {
  mkdir -p stub-bin
  cat > stub-bin/glab <<'STUB'
#!/usr/bin/env bash
d="$PD_DIR"
printf '%s\n' "$*" >> "$d/glab.log"
val() { if [ -f "$d/$1" ]; then cat "$d/$1"; else printf '%s\n' "$2"; fi; }
head=$(git -C "$d" rev-parse HEAD)
case "$1 $2" in
  "auth status") exit 0 ;;
  "mr view")
    if [ -f "$d/glab-mr" ]; then cat "$d/glab-mr"; else
      printf '{"iid":99,"state":"opened","author":{"id":1,"username":"me","state":"active"},"draft":false,"has_conflicts":false,"detailed_merge_status":"mergeable","target_branch":"main","sha":"%s","reviewers":[],"head_pipeline":{"id":5,"sha":"%s","status":"success"}}\n' "$head" "$head"
    fi ;;
  "api user") printf '{"id":1,"username":"me","name":"Me Myself"}\n' ;;
  "api --paginate")
    printf '%s\n' '{"id":2,"username":"alice","name":"Alice Smith","state":"active"}' '{"id":3,"username":"bob","name":"Bob Sikora","state":"active"}' '{"id":1,"username":"me","name":"Me Myself","state":"active"}' ;;
  "api projects/:id/merge_requests/99/approvals") val glab-approvals '{"approved":true,"approvals_required":0,"approved_by":[]}' ;;
  "api projects/:id/pipelines/5/jobs?per_page=100") val glab-jobs '[]' ;;
  "api projects/:id") printf '{"id":1,"merge_method":"merge","squash_option":"default_off"}\n' ;;
  "mr update")
    shift 2
    printf '%s\n' "$@" > "$d/glab-update.argv"
    rc=$(val glab-update.rc 0)
    [ "$rc" -eq 0 ] || printf 'ERROR: 403 Forbidden\n' >&2
    exit "$rc" ;;
  "mr merge")
    shift 2
    printf '%s\n' "$@" > "$d/glab-merge.argv"
    rc=$(val glab-merge.rc 0)
    [ "$rc" -eq 0 ] || printf 'ERROR: 405 Method Not Allowed\n' >&2
    exit "$rc" ;;
esac
STUB
  chmod +x stub-bin/glab
}

# pd_setup <github|gitlab> [state-key:value...] — a project on that forge with
# a bare origin, the forge stubbed, and task T-1 on branch task/T-1 with its
# pull request open, the knowledge decision recorded.
pd_setup() {
  local kind="$1" url
  shift
  fixture_jig_repo
  sed "s|^forge:.*|forge: $kind|" .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  printf '%s\n' origin.git stub-bin 'gh-*' 'glab-*' '*.log' '*.argv' '*.tmp' >> .git/info/exclude
  PD_DIR=$PWD
  export PD_DIR
  if [ "$kind" = github ]; then
    pd_stub_gh
    url=https://github.com/example/example/pull/99
  else
    pd_stub_glab
    url=https://gitlab.example/example/example/-/merge_requests/99
  fi
  PATH="$PWD/stub-bin:$PATH"
  export PATH
  git branch -q task/T-1
  fixture_task T-1 task/T-1 active knowledge_consolidated:true "pr_url:$url" "$@"
}

# pd_state <id> <key> — a key of the task's state.
pd_state() {
  sed -n "s/^$2: //p" ".ai/workspace/tasks/$1/state" | head -n 1
}

# --- request-review: GitHub and GitLab -----------------------------------------

test_prdo_request_review_adds_the_named_people_on_github() {
  pd_setup github
  pd_split jig task request-review T-1 --reviewer alice --reviewer bob --by human --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"review_request":{"pull_request":"https://github.com/example/example/pull/99","requested":["alice","bob"],"author_left_out":false}'
  assert_contains "$OUT" '"task":{"id":"T-1"'
  assert_eq "$(printf 'https://github.com/example/example/pull/99\n--add-reviewer\nalice,bob')" "$(cat gh-edit.argv)"
}

test_prdo_request_review_resolves_a_name_and_leaves_the_author_out() {
  pd_setup github
  pd_split jig task request-review T-1 --reviewer Sikora --reviewer me --by human --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"requested":["bob"],"author_left_out":true'
  assert_contains "$ERR" "me opens the pull request"
  assert_contains "$ERR" "--reviewer Sikora: bob"
}

test_prdo_request_review_refuses_when_only_the_author_is_named() {
  pd_setup github
  pd_split jig task request-review T-1 --reviewer me --by human --json
  assert_eq 1 "$RC"
  assert_eq usage "$(pd_code)"
  assert_no_file gh-edit.argv
}

test_prdo_request_review_refuses_a_name_nobody_has() {
  pd_setup github
  pd_split jig task request-review T-1 --reviewer zed --by human --json
  assert_eq 1 "$RC"
  assert_eq reviewer-unknown "$(pd_code)"
  assert_no_file gh-edit.argv
  pd_split jig task request-review T-1 --reviewer team/devs --by human --json
  assert_eq reviewer-unknown "$(pd_code)"
}

test_prdo_request_review_adds_with_a_plus_on_gitlab() {
  pd_setup gitlab
  pd_split jig task request-review T-1 --reviewer alice --reviewer bob --by human --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"requested":["alice","bob"],"author_left_out":false'
  assert_eq "$(printf '99\n--reviewer\n+alice\n--reviewer\n+bob')" "$(cat glab-update.argv)"
}

test_prdo_request_review_refuses_a_closed_or_merged_pull_request() {
  pd_setup github
  printf 'CLOSED|false|main|abc|MERGEABLE|CLEAN\n' > gh-view
  pd_split jig task request-review T-1 --reviewer alice --by human --json
  assert_eq 1 "$RC"
  assert_eq pull-request-closed "$(pd_code)"
  printf 'MERGED|false|main|abc|UNKNOWN|UNKNOWN\n' > gh-view
  pd_split jig task request-review T-1 --reviewer alice --by human --json
  assert_eq pull-request-closed "$(pd_code)"
  assert_no_file gh-edit.argv
}

test_prdo_request_review_says_when_the_forge_cannot_be_asked() {
  pd_setup github
  : > gh-view.fail
  pd_split jig task request-review T-1 --reviewer alice --by human --json
  assert_eq 1 "$RC"
  assert_eq forge-unavailable "$(pd_code)"
  assert_no_file gh-edit.argv
}

test_prdo_request_review_reports_a_forge_refusal() {
  pd_setup github
  printf '1\n' > gh-edit.rc
  pd_split jig task request-review T-1 --reviewer alice --by human --json
  assert_eq 1 "$RC"
  assert_eq forge-refused "$(pd_code)"
  assert_contains "$OUT" "Resource not accessible"
}

test_prdo_request_review_refuses_a_stale_revision_before_sending() {
  pd_setup github
  pd_split jig task request-review T-1 --reviewer alice --by human --revision 999 --json
  assert_eq 1 "$RC"
  assert_eq stale-revision "$(pd_code)"
  assert_no_file gh-edit.argv
}

test_prdo_request_review_without_by_human_reads_the_agent_git_level() {
  pd_setup github
  pd_split jig task request-review T-1 --reviewer alice --json
  assert_eq 1 "$RC"
  assert_eq git-level "$(pd_code)"
  assert_no_file gh-edit.argv
  pd_cfg_local agent.git pr
  pd_split jig task request-review T-1 --reviewer alice
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" "requested review of https://github.com/example/example/pull/99 from alice"
  assert_file gh-edit.argv
}

test_prdo_request_review_refuses_while_the_agent_is_on_the_task() {
  pd_setup github autopilot:on
  pd_split jig task request-review T-1 --reviewer alice --by human --json
  assert_eq 1 "$RC"
  assert_eq autopilot-running "$(pd_code)"
  assert_no_file gh-edit.argv
}

test_prdo_request_review_needs_a_pull_request_and_a_reviewer() {
  pd_setup github pr_url:
  sed '/^pr_url:/d' .ai/workspace/tasks/T-1/state > s.tmp
  mv s.tmp .ai/workspace/tasks/T-1/state
  pd_split jig task request-review T-1 --reviewer alice --by human --json
  assert_eq no-pull-request "$(pd_code)"
  pd_split jig task request-review nosuch --reviewer alice --by human --json
  assert_eq not-found "$(pd_code)"
  pd_split jig task request-review T-1 --by human --json
  assert_eq usage "$(pd_code)"
}

# --- merge-pr -----------------------------------------------------------------

# pd_checkout_snapshot — what a merge must leave as it is: the checkout's
# commit, its branches and its working tree.
pd_checkout_snapshot() {
  printf '%s\n%s\n%s\n' "$(git rev-parse HEAD)" "$(git branch --list | tr -d ' *')" "$(git status --short)"
}

test_prdo_merge_pr_merges_and_closes_a_task_with_its_knowledge_recorded() {
  pd_setup github
  local before head
  before=$(pd_checkout_snapshot)
  head=$(git rev-parse HEAD)
  pd_split jig task merge-pr T-1 --by human --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"merge":{"pull_request":"https://github.com/example/example/pull/99","outcome":"merged","closed":true,"close_blocked":null}'
  assert_contains "$OUT" '"task":{"id":"T-1"'
  assert_contains "$(cat gh-merge.argv)" "--match-head-commit"
  assert_contains "$(cat gh-merge.argv)" "$head"
  assert_eq consolidated "$(pd_state T-1 status)"
  assert_eq "$before" "$(pd_checkout_snapshot)"
  assert_not_contains "$(cat gh.log)" "--admin"
  assert_not_contains "$(cat gh.log)" "--auto"
}

test_prdo_merge_pr_leaves_the_task_open_when_knowledge_is_not_recorded() {
  pd_setup github knowledge_consolidated:false
  pd_split jig task merge-pr T-1 --by human --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"outcome":"merged","closed":false,"close_blocked":"knowledge-not-recorded"'
  assert_file gh-merge.argv
  assert_eq active "$(pd_state T-1 status)"
}

test_prdo_merge_pr_closes_for_a_pull_request_already_merged() {
  pd_setup github
  printf 'MERGED|false|main|abc|UNKNOWN|UNKNOWN\n' > gh-view
  pd_split jig task merge-pr T-1 --by human --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"outcome":"already-merged","closed":true,"close_blocked":null'
  assert_no_file gh-merge.argv
  assert_eq consolidated "$(pd_state T-1 status)"
}

test_prdo_merge_pr_text_form_says_what_happened() {
  pd_setup github
  pd_split jig task merge-pr T-1 --by human
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" "merged https://github.com/example/example/pull/99"
  assert_contains "$OUT" "closed T-1"
}

test_prdo_merge_pr_merges_on_gitlab_at_the_head_it_read() {
  pd_setup gitlab
  pd_split jig task merge-pr T-1 --by human --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"outcome":"merged","closed":true'
  assert_contains "$(cat glab-merge.argv)" "--sha"
  assert_contains "$(cat glab-merge.argv)" "$(git rev-parse HEAD)"
  assert_contains "$(cat glab-merge.argv)" "--auto-merge=false"
}

# pd_refused <code> — the merge was refused with <code>, nothing merged, the
# task as it was.
pd_refused() {
  assert_eq 1 "$RC" "$ERR"
  assert_eq "$1" "$(pd_code)" "$OUT"
  assert_no_file gh-merge.argv
  assert_no_file glab-merge.argv
  assert_eq active "$(pd_state T-1 status)"
}

test_prdo_merge_pr_refuses_a_draft() {
  pd_setup github
  printf 'OPEN|true|main|%s|MERGEABLE|DRAFT\n' "$(git rev-parse HEAD)" > gh-view
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused draft
}

test_prdo_merge_pr_refuses_a_conflict_and_an_unknown_mergeability() {
  pd_setup github
  printf 'OPEN|false|main|%s|CONFLICTING|DIRTY\n' "$(git rev-parse HEAD)" > gh-view
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused conflict
  printf 'OPEN|false|main|%s|UNKNOWN|UNKNOWN\n' "$(git rev-parse HEAD)" > gh-view
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused mergeable-unknown
}

test_prdo_merge_pr_refuses_an_unapproved_pull_request_naming_whom() {
  pd_setup github
  printf 'CHANGES_REQUESTED|CHANGES_REQUESTED|\n' > gh-review
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused not-approved
  assert_contains "$OUT" "changes requested"
  printf '|COMMENTED|alice,bob\n' > gh-review
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused not-approved
  assert_contains "$OUT" "waiting for alice, bob"
}

test_prdo_merge_pr_refuses_a_review_the_forge_cannot_read() {
  pd_setup gitlab
  printf 'not json\n' > glab-approvals
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused forge-unavailable
}

test_prdo_merge_pr_refuses_red_pending_and_missing_checks() {
  pd_setup github
  printf 'test\tfail\thttps://ci.example/1\t-\t-\n' > gh-checks
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused ci-red
  printf 'test\tpending\thttps://ci.example/1\t-\t-\n' > gh-checks
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused ci-pending
  : > gh-checks
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused ci-none
}

test_prdo_merge_pr_reports_a_refusal_of_the_forge() {
  pd_setup github
  printf '1\n' > gh-merge.rc
  pd_split jig task merge-pr T-1 --by human --json
  assert_eq 1 "$RC"
  assert_eq forge-refused "$(pd_code)"
  assert_contains "$OUT" "Base branch policy prohibits the merge"
  assert_eq active "$(pd_state T-1 status)"
}

test_prdo_merge_pr_refuses_a_closed_pull_request() {
  pd_setup github
  printf 'CLOSED|false|main|abc|UNKNOWN|UNKNOWN\n' > gh-view
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused pull-request-closed
}

test_prdo_merge_pr_sends_a_staging_pull_request_to_land() {
  pd_setup github
  printf 'git.flow: staging\ngit.staging_branch: staging\n' >> .ai/config.yaml
  git branch -q staging main
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused wrong-flow
  assert_contains "$OUT" "jig task land T-1 --by human"
}

test_prdo_merge_pr_refuses_while_the_agent_is_on_the_task() {
  pd_setup github autopilot:on
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused autopilot-running
}

test_prdo_merge_pr_refuses_while_a_ship_waits_for_ci() {
  pd_setup github
  mkdir -p .ai/runtime/shipping
  printf 'pid: %s\nsince: 2026-11-13T10:00:00Z\n' "$$" > .ai/runtime/shipping/T-1
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused ship-running
  assert_contains "$OUT" "since 2026-11-13T10:00:00Z"
}

test_prdo_merge_pr_refuses_a_stale_revision_before_merging() {
  pd_setup github
  pd_split jig task merge-pr T-1 --by human --revision 999 --json
  pd_refused stale-revision
}

test_prdo_merge_pr_without_by_human_needs_the_merge_level() {
  pd_setup github
  pd_split jig task merge-pr T-1 --json
  pd_refused git-level
  pd_cfg_local agent.git pr
  pd_split jig task merge-pr T-1 --json
  pd_refused git-level
  pd_cfg_local agent.git merge
  pd_split jig task merge-pr T-1 --json
  assert_eq 0 "$RC" "$ERR"
}

test_prdo_merge_pr_refuses_a_release_whose_notes_are_behind_the_base() {
  pd_setup github
  printf '1.0.0\n' > VERSION
  git add VERSION
  git commit -q -m "declare the version"
  git push -q origin main
  git checkout -q -b rel
  printf '2.0.0\n' > VERSION
  git commit -q -am "raise the version"
  printf 'OPEN|false|main|%s|MERGEABLE|CLEAN\n' "$(git rev-parse HEAD)" > gh-view
  git checkout -q main
  pd_split jig task merge-pr T-1 --by human --json
  pd_refused notes-stale
  assert_contains "$OUT" "raises the version"
}

# --- pr-status ----------------------------------------------------------------

# pd_status_data — the `pull_request` of the envelope in OUT.
pd_status_pr() {
  printf '%s\n' "$OUT" | sed -e 's/.*"pull_request"://' -e 's/}$//'
}

test_prdo_pr_status_reads_a_github_pull_request() {
  pd_setup github
  local before head
  before=$(ls .ai/runtime/revision 2>/dev/null)
  head=$(git rev-parse HEAD)
  pd_split jig task pr-status T-1 --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"data":{"task_id":"T-1","pull_request":{"url":"https://github.com/example/example/pull/99","state":"open","draft":false,"base":"main","head":"'"$head"'","mergeable":"clean",'
  assert_contains "$OUT" '"checks":{"state":"green","list":[{"name":"test","state":"pass","url":"https://ci.example/1","started_at":"2026-11-13T10:00:00Z","completed_at":"2026-11-13T10:07:00Z","duration_s":420}]},'
  assert_contains "$OUT" '"review":{"state":"none","waiting_for":[]},"protection":{"merge_state":"clean","required_approvals":1,"required_checks":["test"]},"blockers":[]}}'
  assert_eq "$before" "$(ls .ai/runtime/revision 2>/dev/null)" "a read raises no revision"
}

test_prdo_pr_status_names_what_holds_the_merge_back() {
  pd_setup github
  printf 'test\tpending\thttps://ci.example/1\t2026-11-13T10:00:00Z\t0001-01-01T00:00:00Z\nlint\tpending\t-\t-\t-\nbuild\tskipping\t-\t-\t-\n' > gh-checks
  printf '|COMMENTED|alice\n' > gh-review
  printf 'OPEN|true|main|%s|CONFLICTING|DIRTY\n' "$(git rev-parse HEAD)" > gh-view
  pd_split jig task pr-status T-1 --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"draft":true'
  assert_contains "$OUT" '"mergeable":"conflict"'
  assert_contains "$OUT" '"checks":{"state":"pending"'
  assert_contains "$OUT" '"name":"test","state":"pending","url":"https://ci.example/1","started_at":"2026-11-13T10:00:00Z","completed_at":null,"duration_s":'
  assert_not_contains "$OUT" '"name":"test","state":"pending","url":"https://ci.example/1","started_at":"2026-11-13T10:00:00Z","completed_at":null,"duration_s":null'
  assert_contains "$OUT" '"name":"lint","state":"pending","url":null,"started_at":null,"completed_at":null,"duration_s":null'
  assert_contains "$OUT" '"name":"build","state":"skipped"'
  assert_contains "$OUT" '"review":{"state":"waiting","waiting_for":["alice"]}'
  assert_contains "$OUT" '"protection":{"merge_state":"dirty"'
  assert_contains "$OUT" '"blockers":["draft","conflict","ci-pending","not-approved"]'
}

test_prdo_pr_status_reads_red_and_missing_checks() {
  pd_setup github
  printf 'test\tfail\t-\t-\t-\nold\tcancel\t-\t-\t-\n' > gh-checks
  : > gh-checks.pending
  pd_split jig task pr-status T-1 --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"checks":{"state":"red"'
  assert_contains "$OUT" '"name":"old","state":"cancel"'
  assert_contains "$OUT" '"blockers":["ci-red"]'
  : > gh-checks
  pd_split jig task pr-status T-1 --json
  assert_contains "$OUT" '"checks":{"state":"none","list":[]}'
  assert_contains "$OUT" '"blockers":["ci-none"]'
}

test_prdo_pr_status_gives_null_for_rules_the_forge_will_not_say() {
  pd_setup github
  : > gh-rules.fail
  pd_split jig task pr-status T-1 --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"required_approvals":null,"required_checks":null}'
}

test_prdo_pr_status_of_a_merged_pull_request_has_no_blockers() {
  pd_setup github
  printf 'MERGED|false|main|abc|UNKNOWN|UNKNOWN\n' > gh-view
  pd_split jig task pr-status T-1 --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"state":"merged"'
  assert_contains "$OUT" '"blockers":[]}}'
}

test_prdo_pr_status_reads_a_gitlab_merge_request() {
  pd_setup gitlab
  printf '%s\n' '[{"id":1,"name":"test","status":"success","web_url":"https://gitlab.example/j/1","started_at":"2026-11-13T10:00:00.123Z","finished_at":"2026-11-13T10:07:00.456Z","user":{"state":"active"}},{"id":2,"name":"deploy","status":"manual","web_url":"https://gitlab.example/j/2","started_at":null,"finished_at":null}]' > glab-jobs
  printf '{"approved":false,"approvals_required":2,"approved_by":[]}\n' > glab-approvals
  pd_split jig task pr-status T-1 --json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"url":"https://gitlab.example/example/example/-/merge_requests/99","state":"open","draft":false,"base":"main","head":"'"$(git rev-parse HEAD)"'","mergeable":"clean",'
  assert_contains "$OUT" '"checks":{"state":"green","list":[{"name":"test","state":"pass","url":"https://gitlab.example/j/1","started_at":"2026-11-13T10:00:00Z","completed_at":"2026-11-13T10:07:00Z","duration_s":420},{"name":"deploy","state":"skipped","url":"https://gitlab.example/j/2","started_at":null,"completed_at":null,"duration_s":null}]}'
  assert_contains "$OUT" '"review":{"state":"none","waiting_for":[]}'
  assert_contains "$OUT" '"protection":{"merge_state":"mergeable","required_approvals":2,"required_checks":null}'
  assert_contains "$OUT" '"blockers":[]}}'
}

test_prdo_pr_status_says_when_the_forge_cannot_be_asked() {
  pd_setup github
  : > gh-view.fail
  pd_split jig task pr-status T-1 --json
  assert_eq 1 "$RC"
  assert_eq forge-unavailable "$(pd_code)"
  assert_contains "$OUT" "bad gateway"
}

test_prdo_pr_status_refusals_and_the_text_form() {
  pd_setup github
  pd_split jig task pr-status T-1
  assert_eq 1 "$RC"
  assert_contains "$ERR" "data only"
  pd_split jig task pr-status nosuch --json
  assert_eq not-found "$(pd_code)"
  sed '/^pr_url:/d' .ai/workspace/tasks/T-1/state > s.tmp
  mv s.tmp .ai/workspace/tasks/T-1/state
  pd_split jig task pr-status T-1 --json
  assert_eq no-pull-request "$(pd_code)"
}

# jig_pr_approval_github_v is the one place GitHub's words for a review become
# jig's: `task pr-status`, `task land` and housekeeping's forge cache all read
# them through it, so a change request wins, a requested reviewer is waited
# for, and a decision this does not know is never an approval.
test_prdo_github_review_words_are_decided_in_one_function() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"
    for row in "APPROVED|APPROVED|" "APPROVED|APPROVED|ann" "CHANGES_REQUESTED|APPROVED|" \
      "|CHANGES_REQUESTED,APPROVED|" "REVIEW_REQUIRED||" "REVIEW_REQUIRED|APPROVED|" "|APPROVED|" \
      "null|APPROVED,COMMENTED|" "||" "||bo" "SOMETHING_NEW|APPROVED|" "CHANGES_REQUESTED||ann"; do
      dec=${row%%|*}; rest=${row#*|}; reviews=${rest%%|*}; pending=${rest#*|}
      jig_pr_approval_github_v w "$dec" "$reviews" "$pending"
      printf "%s " "$w"
    done'
  assert_eq 0 "$RC"
  assert_eq "approved waiting changes changes none none approved approved none waiting unknown changes " "$OUT"
}

# forgecache_entry_url finds a pull request by its whole address: pull/1 is
# not the line of pull/12 written before it, and a line that ends at its url
# (no <mergeable> column) is found too.
test_prdo_forge_cache_finds_a_pull_request_by_its_whole_url() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/forgecache.sh"
    t=$(printf "\t")
    cache="task/b${t}staging${t}open${t}green${t}2026-11-14T00:00:00Z${t}bbb${t}https://f.test/pull/12${t}mergeable${t}approved${t}-
task/a${t}staging${t}open${t}red${t}2026-11-14T00:00:00Z${t}aaa${t}https://f.test/pull/1"
    forgecache_entry_url "$cache" https://f.test/pull/1
    printf "%s|%s|%s|%s|%s\n" "$_FORGECACHE_HEAD" "$_FORGECACHE_BASE" "$_FORGECACHE_CI" "$_FORGECACHE_REVIEW" "$_FORGECACHE_MERGEABLE"
    forgecache_entry_url "$cache" https://f.test/pull/12
    printf "%s|%s|%s|%s\n" "$_FORGECACHE_HEAD" "$_FORGECACHE_CI" "$_FORGECACHE_REVIEW" "$_FORGECACHE_MERGEABLE"
    forgecache_entry_url "$cache" https://f.test/pull/2
    printf "[%s]\n" "$_FORGECACHE_HEAD$_FORGECACHE_STATE"'
  assert_eq 0 "$RC" "$OUT"
  assert_eq "task/a|staging|red||
task/b|green|approved|mergeable
[]" "$OUT"
}
