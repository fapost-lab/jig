# Tests for `jig task promote`, "prepare for prod" (scripts/lib/promote.sh;
# adr-20261111-prepare-for-prod-opens-the-promotion-from-git-alone;
# .ai/specs/staging-branch/): the refusals against the tested staging commit,
# the conflict with the base handed to a person, the pull request into the
# base found by head and base, and a run on a CI runner with no workspace.
# shellcheck shell=bash

# --- fixtures -----------------------------------------------------------

# promote_cfg_local <key> <value> — a key of .ai/config.local.yaml (ADR-0038).
promote_cfg_local() {
  printf '%s: %s\n' "$1" "$2" >> .ai/config.local.yaml
}

# promote_stub_gh — a fake `gh`, every call logged to gh.log. Its answers come
# from files in the test directory:
#   gh-open-main  the pull request `pr list --base main` finds (default: none)
#   gh-staging    "<url><TAB><title>" for `pr list --base staging`
#   gh-headonly   what a `pr list` naming no base finds: the open pull request
#                 into staging that a search by head alone would return
# `pr create` records its arguments in gh-create.argv and the body it was
# given in gh-create.body.
promote_stub_gh() {
  local dir="$PWD"
  mkdir -p stub-bin
  cat > stub-bin/gh <<STUB
#!/usr/bin/env bash
d="$dir"
printf '%s\n' "\$*" >> "\$d/gh.log"
val() { if [ -f "\$d/\$1" ]; then cat "\$d/\$1"; fi; }
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr list")
    case "\$*" in
      *"--base main"*) val gh-open-main ;;
      *"--base staging"*) val gh-staging ;;
      *) val gh-headonly ;;
    esac ;;
  "pr create")
    shift 2
    printf '%s\n' "\$@" > "\$d/gh-create.argv"
    while [ \$# -gt 0 ]; do
      if [ "\$1" = --body-file ]; then cat "\$2" > "\$d/gh-create.body"; fi
      shift
    done
    printf 'https://github.com/example/example/pull/7\n' ;;
esac
STUB
  chmod +x stub-bin/gh
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# promote_land <id> — merge task/<id> into staging as a person landing it
# would, and push both; the checkout goes back to where it was.
promote_land() {
  local back
  back=$(git symbolic-ref --short HEAD)
  git push -q origin "task/$1"
  git checkout -q staging
  git merge -q --no-ff -m "Land $1 on staging" "task/$1"
  git push -q origin staging
  git checkout -q "$back"
}

# promote_task <id> <file> <text> — file and start task <id> from main, commit
# <text> into <file> on its branch and push it.
promote_task() {
  git checkout -q main
  jig task new "$1" >/dev/null
  jig task start "$1" >/dev/null
  printf '%s\n' "$3" > "$2"
  git add "$2"
  git commit -q -m "Work of $1"
  git push -q origin "task/$1"
}

# promote_setup — a project on `git.flow: staging` (staging branch `staging`
# on origin, GitHub as the forge, VERSION 1.0.0, all committed on main), a
# bare origin, `agent.git: pr`, and T-1 started, committed and landed on
# staging; the checkout is on task/T-1.
promote_setup() {
  fixture_jig_repo
  sed "s|^forge:.*|forge: github|" .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml
  printf 'git.flow: staging\ngit.staging_branch: staging\n' >> .ai/config.yaml
  printf '1.0.0\n' > VERSION
  printf 'base\n' > shared.txt
  git add -A
  git commit -q -m "fixture: the staging flow"
  git branch -q staging main
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  printf '%s\n' origin.git stub-bin 'gh*' >> .git/info/exclude
  promote_cfg_local agent.git pr
  promote_stub_gh
  promote_task T-1 one.txt "work of T-1"
  promote_land T-1
}

# assert_nothing_sent — no pull request was opened, and origin's task/T-1 is
# still <sha>.
assert_nothing_sent() {
  assert_no_file gh-create.argv
  assert_eq "$1" "$(git ls-remote origin refs/heads/task/T-1 | cut -f1)" "task/T-1 must not be pushed"
}

# --- opening the pull request ----------------------------------------------

test_promote_opens_the_pull_request_into_the_base() {
  promote_setup

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: tested commit $(git rev-parse --short origin/staging) of staging"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/7"
  assert_contains "$OUT" "task promote: the merge is the person's (git.promote_merge: human)"
  assert_contains "$(cat gh-create.argv)" "$(printf -- '--base\nmain')"
  assert_contains "$(cat gh-create.argv)" "$(printf -- '--head\ntask/T-1')"
  assert_contains "$(cat gh-create.argv)" "Work of T-1"
  assert_contains "$(cat gh-create.body)" "Promotes task/T-1 to main, tested on staging at $(git rev-parse --short origin/staging)."
  assert_file_contains .ai/workspace/tasks/T-1/state "promote_url: https://github.com/example/example/pull/7"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "pr_url:"
}

# The title and the link of the staging pull request, where the forge has one.
test_promote_takes_the_title_of_the_staging_pull_request() {
  promote_setup
  printf 'https://github.com/example/example/pull/3\tT-1: the work\n' > gh-staging

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(cat gh-create.argv)" "T-1: the work"
  assert_contains "$(cat gh-create.body)" "Staging pull request: https://github.com/example/example/pull/3"
}

test_promote_a_second_run_prints_the_same_link() {
  promote_setup
  printf 'https://github.com/example/example/pull/5\n' > gh-open-main

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/5 (already open)"
  assert_no_file gh-create.argv
}

# An open pull request into staging is not the promotion: the search names
# the base as well as the head.
test_promote_does_not_take_a_staging_pull_request_for_the_promotion() {
  promote_setup
  printf 'https://github.com/example/example/pull/3\n' > gh-headonly

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/7"
  assert_not_contains "$OUT" "pull/3 (already open)"
  assert_contains "$(cat gh.log)" "pr list --head task/T-1 --base main"
}

test_promote_names_a_version_raise() {
  promote_setup
  promote_task T-2 VERSION 1.1.0
  promote_land T-2

  run jig task promote T-2
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: this promotion raises the version in VERSION: 1.0.0 -> 1.1.0; it is a release, and its merge is a person's"
  assert_contains "$(cat gh-create.body)" "Release: this promotion raises the version in VERSION: 1.0.0 -> 1.1.0"
  assert_not_contains "$(cat gh-create.argv)" "--draft"
}

test_promote_a_task_already_in_the_base_is_nothing_to_do() {
  promote_setup
  git checkout -q main
  git merge -q --no-ff -m "Merge T-1" task/T-1
  git push -q origin main

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-1 is already in main; nothing to promote"
  assert_no_file gh-create.argv
}

test_promote_says_promote_merge_auto_is_not_built() {
  promote_setup
  printf 'git.promote_merge: auto\n' >> .ai/config.yaml

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: git.promote_merge is auto, which is not built yet; the merge is the person's"
}

# --- against the tested commit ----------------------------------------------

test_promote_refuses_a_task_not_on_staging() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"

  run jig task promote T-2
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-2 is not in the tested commit $(git rev-parse --short origin/staging) of staging: none of its own commits is there."
  assert_no_file gh-create.argv
}

# A fix pushed after the test run is not in the tested commit, even once it
# is on staging: --commit names what was tested.
test_promote_refuses_a_fix_after_the_tested_commit() {
  promote_setup
  local tested before
  tested=$(git rev-parse origin/staging)
  printf 'fix\n' >> one.txt
  git commit -q -am "Fix of T-1"
  promote_land T-1
  before=$(git rev-parse origin/task/T-1)

  run jig task promote T-1 --commit "$tested"
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-1 has commit(s) of its own that the tested commit $(git rev-parse --short "$tested") does not have:"
  assert_contains "$OUT" "Fix of T-1"
  assert_contains "$OUT" "A fix made after the test must be tested before it reaches main"
  assert_nothing_sent "$before"

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
}

# The promotion and the staging pull request share the task branch: a fix
# after the promotion was opened cannot reach staging while that one is open,
# so the refusal says to close it first (finding F16).
test_promote_a_fix_after_an_open_promotion_says_to_close_it_first() {
  promote_setup
  local tested before
  tested=$(git rev-parse origin/staging)
  printf 'https://github.com/example/example/pull/5\n' > gh-open-main
  printf 'fix\n' >> one.txt
  git commit -q -am "Fix of T-1"
  promote_land T-1
  before=$(git rev-parse origin/task/T-1)

  run jig task promote T-1 --commit "$tested"
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "The open pull request https://github.com/example/example/pull/5 already carries them"
  assert_contains "$OUT" "Close it first: it comes from this same branch, so jig task ship refuses while it is open"
  assert_contains "$OUT" "run jig task promote again after the test"
  assert_nothing_sent "$before"
}

test_promote_refuses_a_commit_nobody_pushed() {
  promote_setup
  local before
  before=$(git rev-parse origin/task/T-1)
  printf 'fix\n' >> one.txt
  git commit -q -am "Unpushed fix"

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "Unpushed fix (not pushed)"
  assert_nothing_sent "$before"
}

test_promote_refuses_a_branch_staging_was_merged_into() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge staging into task/T-1" origin/staging
  git push -q origin task/T-1
  promote_land T-1
  local before
  before=$(git rev-parse origin/task/T-1)

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-1 is not a clean task branch: it carries work that main does not have and that is not its own:"
  assert_contains "$OUT" "  a merge of staging into task/T-1 ($(git rev-parse --short origin/task/T-1))"
  assert_contains "$OUT" "Rebuild the branch from main with its own commits only"
  assert_nothing_sent "$before"
}

test_promote_refuses_a_tested_commit_off_staging() {
  promote_setup
  local before
  before=$(git rev-parse origin/task/T-1)

  # main is on staging but holds nothing of T-1: a commit of staging, tested
  # before T-1 landed.
  run jig task promote T-1 --commit main
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task/T-1 is not in the tested commit"

  git checkout -q -b elsewhere main
  printf 'x\n' > x.txt
  git add x.txt
  git commit -q -m "elsewhere"
  rm -f gh-create.argv
  run jig task promote T-1 --commit elsewhere
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: elsewhere is not a commit of origin/staging"
  assert_nothing_sent "$before"

  run jig task promote T-1 --commit 0123456789abcdef0123456789abcdef01234567
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "names no commit here; fetch it and run again"
}

test_promote_refuses_a_branch_that_diverged_from_origin() {
  promote_setup
  local before
  git checkout -q main
  git clone -q origin.git other
  (cd other && git checkout -q task/T-1 && printf 'b\n' > b.txt && git add b.txt \
    && git commit -q -m "theirs" && git push -q origin task/T-1)
  before=$(git rev-parse origin/task/T-1)
  git fetch -q origin
  before=$(git rev-parse origin/task/T-1)
  git checkout -q task/T-1
  printf 'a\n' > a.txt
  git add a.txt
  git commit -q -m "ours"

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-1 here and on origin have diverged; nothing is forced."
  assert_nothing_sent "$before"
}

# --- the conflict with the base ---------------------------------------------

# promote_conflict — main changes shared.txt one way and T-1, landed on
# staging, another.
promote_conflict() {
  git checkout -q main
  printf 'main side\n' > shared.txt
  git commit -q -am "Main changes shared.txt"
  git push -q origin main
  git checkout -q task/T-1
  printf 'task side\n' > shared.txt
  git commit -q -am "T-1 changes shared.txt"
  promote_land T-1
}

test_promote_hands_a_conflict_with_the_base_to_a_person() {
  promote_setup
  promote_conflict
  local before head worktrees
  before=$(git rev-parse origin/task/T-1)
  head=$(git rev-parse HEAD)
  worktrees=$(git worktree list | wc -l)

  run jig task promote T-1
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-1 conflicts with main in:"
  assert_contains "$OUT" "  shared.txt"
  assert_contains "$OUT" "Nothing was pushed. Merge main into the task branch"
  assert_nothing_sent "$before"
  assert_eq "$head" "$(git rev-parse HEAD)"
  assert_eq "$worktrees" "$(git worktree list | wc -l)" "the trial merge's worktree must be gone"
  assert_no_file .git/MERGE_HEAD
  assert_eq "" "$(git status --porcelain --untracked-files=no)"
}

# Run again with a promotion open, the conflict still prints its link.
test_promote_a_conflict_on_an_open_promotion_keeps_its_link() {
  promote_setup
  promote_conflict
  printf 'https://github.com/example/example/pull/5\n' > gh-open-main

  run jig task promote T-1
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/5 (already open)"
}

# The merge of the base a person resolved is pushed, and it is not the task's
# own work: the task stays on staging.
test_promote_pushes_the_resolved_merge_of_the_base() {
  promote_setup
  promote_conflict
  git merge -q origin/main >/dev/null 2>&1 || true
  printf 'resolved\n' > shared.txt
  git add shared.txt
  git commit -q --no-edit

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pushed task/T-1"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/7"
  assert_eq "$(git rev-parse HEAD)" "$(git ls-remote origin refs/heads/task/T-1 | cut -f1)"
  run jig task list --json
  assert_contains "$OUT" '"staging":"on"'
}

# --- dependencies -------------------------------------------------------------

test_promote_warns_of_a_dependency_still_on_staging() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  jig queue depend T-2 --on T-1 --reason "needs one.txt" >/dev/null

  run jig task promote T-2
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: warning: T-2 depends on T-1 (queue: needs one.txt), which is on staging but not in main; promote T-1 with this task or before it"
  assert_contains "$(cat gh-create.body)" "Depends on"
  assert_contains "$(cat gh-create.body)" "- T-2 depends on T-1 (queue: needs one.txt)"
}

test_promote_says_nothing_of_a_dependency_in_the_base() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  jig queue depend T-2 --on T-1 --reason "needs one.txt" >/dev/null
  git checkout -q main
  git merge -q --no-ff -m "Merge T-1" task/T-1
  git push -q origin main
  git checkout -q task/T-2

  run jig task promote T-2
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "warning"
  assert_not_contains "$(cat gh-create.body)" "Depends on"
}

# --- a CI runner ----------------------------------------------------------------

# A clone of origin with no workspace, no queue and no agent.git.
test_promote_runs_on_a_ci_runner_with_no_workspace() {
  promote_setup
  git clone -q origin.git runner
  cd runner || return 1

  run env CI=true "$JIG_BIN" task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/7"
  assert_contains "$(cat ../gh-create.argv)" "$(printf -- '--head\ntask/T-1')"
  [ ! -d .ai/workspace/tasks/T-1 ] || fail "a runner must not get a workspace"
}

test_promote_in_a_checkout_needs_agent_git_pr() {
  promote_setup
  git clone -q origin.git runner
  cd runner || return 1

  run "$JIG_BIN" task promote T-1
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: agent.git is none in this clone; opening the pull request into main is the person's. Nothing was pushed."
  assert_no_file ../gh-create.argv

  run env CI=false "$JIG_BIN" task promote T-1
  assert_eq 3 "$RC" "$OUT"
}

test_promote_refuses_a_shallow_clone() {
  promote_setup
  git clone -q --depth 1 --no-single-branch "file://$PWD/origin.git" runner
  cd runner || return 1

  run env CI=true "$JIG_BIN" task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: this clone is shallow"
  assert_no_file ../gh-create.argv
}

# --- refused before anything is sent ---------------------------------------------

test_promote_refuses_off_the_staging_flow() {
  promote_setup
  sed 's/^git.flow:.*/git.flow: direct/' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: the git flow is direct, not staging; a task reaches main by jig task ship"
  assert_no_file gh-create.argv
}

test_promote_refuses_a_task_of_an_epic() {
  promote_setup
  sed 's/^base_branch:.*/base_branch: epic\/x/' .ai/workspace/tasks/T-1/state > s.tmp
  mv s.tmp .ai/workspace/tasks/T-1/state

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: T-1 is cut from epic/x, not main; the staging flow does not apply to it"
}

test_promote_refuses_a_task_on_autopilot() {
  promote_setup
  printf 'autopilot: on\n' >> .ai/workspace/tasks/T-1/state

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "runs on autopilot, which never promotes"
  assert_no_file gh-create.argv
}

test_promote_refuses_a_call_with_no_task() {
  promote_setup

  run jig task promote
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "usage: jig task promote <id>"
  assert_contains "$OUT" "jig task promote --commit <sha> --all"
  assert_no_file gh-create.argv
}

test_promote_refuses_a_task_with_no_branch() {
  promote_setup

  run jig task promote T-9
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: origin has no branch task/T-9; what was not pushed was not tested"
}

test_promote_with_no_forge_needs_a_person() {
  promote_setup
  sed 's/^forge:.*/forge: none/' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  run jig task promote T-1
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: no forge available; open the pull request from task/T-1 into main by hand"
}

test_promote_url_is_refused_by_task_set() {
  promote_setup

  run jig task set T-1 promote_url https://example.invalid/1
  assert_eq 1 "$RC" "$OUT"
}

# A fetch that fails is a refusal, not a warning: judged on a stale
# origin/task/T-1, the pull request would open on origin's real branch, which
# here holds a fix pushed from another clone after the test.
test_promote_refuses_when_a_branch_cannot_be_fetched() {
  promote_setup
  local real theirs
  git clone -q origin.git other
  (cd other && git checkout -q task/T-1 && printf 'late\n' > late.txt && git add late.txt \
    && git commit -q -m "Untested fix" && git push -q origin task/T-1)
  theirs=$(git ls-remote origin refs/heads/task/T-1 | cut -f1)
  real=$(command -v git)
  mkdir -p nofetch-bin
  cat > nofetch-bin/git <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = fetch ]; then printf 'fatal: could not read from remote repository\n' >&2; exit 128; fi
done
exec "$real" "\$@"
STUB
  chmod +x nofetch-bin/git

  run env PATH="$PWD/nofetch-bin:$PATH" "$JIG_BIN" task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: could not fetch main from origin, so it cannot be judged as origin has it now. Nothing was pushed and no pull request opened"
  assert_contains "$OUT" "could not read from remote repository"
  assert_no_file gh-create.argv
  assert_eq "$theirs" "$(git ls-remote origin refs/heads/task/T-1 | cut -f1)"

  run jig task promote T-1
  assert_eq 1 "$RC" "the fetched branch holds the untested fix: $OUT"
  assert_contains "$OUT" "Untested fix"
  assert_no_file gh-create.argv
}

# --- a merged branch of another task (decided by the person, 2026-11-11) -----

# promote_merge_dep — T-2 started from main, landed on staging, then merged
# into task/T-1, which lands on staging again.
promote_merge_dep() {
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge task/T-2 into task/T-1" task/T-2
  git push -q origin task/T-1
  promote_land T-1
}

test_promote_takes_a_merged_clean_task_branch_with_a_warning() {
  promote_setup
  promote_merge_dep
  local m
  m=$(git rev-parse --short task/T-1)

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: warning: T-1 carries task/T-2 (merged at $m); it reaches main with this task"
  assert_contains "$(cat gh-create.body)" "- T-1 carries task/T-2 (merged at $m); it reaches main with this task"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/7"
}

# Its commits go to main with the task, so each must be in the tested commit.
test_promote_judges_a_merged_task_branch_as_its_own_commits() {
  promote_setup
  local tested
  tested=$(git rev-parse origin/staging)
  promote_task T-2 two.txt "work of T-2"
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge task/T-2 into task/T-1" task/T-2
  git push -q origin task/T-1
  promote_land T-1

  run jig task promote T-1 --commit "$tested"
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "has commit(s) of its own that the tested commit"
  assert_contains "$OUT" "Work of T-2"
  assert_no_file gh-create.argv
}

test_promote_refuses_a_merged_task_branch_that_carries_staging() {
  promote_setup
  promote_task T-3 three.txt "work of T-3"
  promote_land T-3
  promote_task T-2 two.txt "work of T-2"
  git merge -q --no-ff -m "Merge staging into task/T-2" origin/staging
  git push -q origin task/T-2
  promote_land T-2
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge task/T-2 into task/T-1" task/T-2
  git push -q origin task/T-1
  promote_land T-1

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "a merge of staging into task/T-2"
  assert_contains "$OUT" "a merge of task/T-2 into task/T-1 ($(git rev-parse --short task/T-1)), which carries the above"
  assert_no_file gh-create.argv
}

test_promote_refuses_a_merged_feature_branch() {
  promote_setup
  git checkout -q -b feature/x main
  printf 'f\n' > f.txt
  git add f.txt
  git commit -q -m "Feature work"
  git push -q origin feature/x
  git checkout -q staging
  git merge -q --no-ff -m "Land feature/x" feature/x
  git push -q origin staging
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge feature/x into task/T-1" feature/x
  git push -q origin task/T-1
  promote_land T-1

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "a merge of feature/x into task/T-1 ($(git rev-parse --short task/T-1))"
  assert_no_file gh-create.argv
}

# Autopilot never promotes, on a runner too.
test_promote_refuses_a_task_on_autopilot_on_a_ci_runner() {
  promote_setup
  printf 'autopilot: on\n' >> .ai/workspace/tasks/T-1/state

  run env CI=true "$JIG_BIN" task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "runs on autopilot, which never promotes"
  assert_no_file gh-create.argv
}

# --- where a branch was cut (second architecture review, F7 and F8) ----------

# promote_task_from <id> <ref> <file> — task <id> filed and started, its branch
# then moved to <ref> (cut from it instead of main), a commit on top, pushed.
promote_task_from() {
  git checkout -q main
  jig task new "$1" >/dev/null
  jig task start "$1" >/dev/null
  git reset -q --hard "$2"
  printf 'work of %s\n' "$1" > "$3"
  git add "$3"
  git commit -q -m "Work of $1"
  git push -q -f origin "task/$1"
}

test_promote_refuses_a_task_cut_from_staging() {
  promote_setup
  promote_task_from T-3 origin/staging three.txt
  promote_land T-3

  run jig task promote T-3
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task/T-3 is cut from staging ("
  assert_no_file gh-create.argv
}

test_promote_refuses_a_dependency_cut_from_staging() {
  promote_setup
  promote_task_from T-4 origin/staging four.txt
  promote_land T-4
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge task/T-4 into task/T-1" task/T-4
  git push -q origin task/T-1
  promote_land T-1

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task/T-4 is cut from staging ("
  assert_contains "$OUT" "a merge of task/T-4 into task/T-1 ($(git rev-parse --short task/T-1)), which carries the above"
  assert_no_file gh-create.argv
}

test_promote_refuses_a_dependency_cut_from_a_feature_branch() {
  promote_setup
  git checkout -q -b feature/x main
  printf 'f\n' > f.txt
  git add f.txt
  git commit -q -m "Feature work"
  git push -q origin feature/x
  git checkout -q staging
  git merge -q --no-ff -m "Land feature/x" feature/x
  git push -q origin staging
  promote_task_from T-4 origin/feature/x four.txt
  promote_land T-4
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge task/T-4 into task/T-1" task/T-4
  git push -q origin task/T-1
  promote_land T-1

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task/T-4 is cut from feature/x"
  assert_contains "$OUT" "which carries the above"
  assert_no_file gh-create.argv
}

# Staging newer than the tested commit, merged in, is named for what it is,
# not listed as the task's own commits.
test_promote_names_a_newer_staging_merged_in() {
  promote_setup
  local tested
  tested=$(git rev-parse origin/staging)
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge staging into task/T-1" origin/staging
  git push -q origin task/T-1

  run jig task promote T-1 --commit "$tested"
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "a merge of staging into task/T-1 ($(git rev-parse --short task/T-1))"
  assert_not_contains "$OUT" "has commit(s) of its own"
  assert_not_contains "$OUT" "Work of T-2"
  assert_no_file gh-create.argv
}

# --- third architecture review (F11, F13) ------------------------------------

# A merge of a clean dependency made after the tested commit is the task's own
# work: whatever the merge itself changed was never tested.
test_promote_refuses_a_dependency_merge_made_after_the_test() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  git checkout -q task/T-1
  git merge -q --no-ff --no-commit task/T-2 >/dev/null 2>&1 || true
  printf 'evil\n' > evil.txt
  git add evil.txt
  git commit -q -m "Merge task/T-2 into task/T-1"

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "has commit(s) of its own that the tested commit"
  assert_contains "$OUT" "Merge task/T-2 into task/T-1 (not pushed)"
  assert_no_file gh-create.argv
}

test_promote_refuses_a_plain_dependency_merge_made_after_the_test() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge task/T-2 into task/T-1" task/T-2
  git push -q origin task/T-1

  run jig task promote T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "Merge task/T-2 into task/T-1"
  assert_no_file gh-create.argv
}

# A dependency cut from another task's branch: both tasks are named.
test_promote_names_every_task_in_a_chain_of_dependencies() {
  promote_setup
  promote_task T-6 six.txt "work of T-6"
  promote_land T-6
  promote_task_from T-7 task/T-6 seven.txt
  promote_land T-7
  git checkout -q task/T-1
  git merge -q --no-ff -m "Merge task/T-7 into task/T-1" task/T-7
  git push -q origin task/T-1
  promote_land T-1
  local m
  m=$(git rev-parse --short task/T-1)

  run jig task promote T-1
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: warning: T-1 carries task/T-7 (merged at $m); it reaches main with this task"
  assert_contains "$OUT" "task promote: warning: T-1 carries task/T-6 (merged at $m); it reaches main with this task"
  assert_contains "$(cat gh-create.body)" "- T-1 carries task/T-6"
}

# --- several tasks, "Promote from CI" -------------------------------------------
# (.ai/specs/staging-branch/, "A CI run promotes the tasks it names, or all of
# them only when told")

# promote_created <branch> — whether the stub forge was asked to open a pull
# request from <branch> into main.
promote_created() {
  local line
  [ -f gh.log ] || return 1
  while IFS= read -r line; do
    case "$line" in "pr create --base main --head $1 "*) return 0 ;; esac
  done < gh.log
  return 1
}

test_promote_several_ids_each_opens_its_pull_request() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  local tested
  tested=$(git rev-parse origin/staging)

  run jig task promote --commit "$tested" T-1 T-2
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: promoting T-1"
  assert_contains "$OUT" "task promote: T-1: promoted"
  assert_contains "$OUT" "task promote: T-2: promoted"
  assert_contains "$OUT" "task promote: 2 promoted, 0 refused, 0 need a person (tested commit $(git rev-parse --short "$tested") of staging)"
  promote_created task/T-1 || fail "no pull request for task/T-1: $(cat gh.log)"
  promote_created task/T-2 || fail "no pull request for task/T-2: $(cat gh.log)"
  assert_file_contains .ai/workspace/tasks/T-2/state "promote_url: https://github.com/example/example/pull/7"
}

# One task's refusal is that task's result: the next one is still promoted,
# and the run exits 1. Without --commit, every task is judged against the one
# tip of origin/staging the run fetched.
test_promote_a_refused_task_does_not_stop_the_others() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"

  run jig task promote T-2 T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-2 is not in the tested commit"
  assert_contains "$OUT" "task promote: T-2: refused"
  assert_contains "$OUT" "task promote: T-1: promoted"
  assert_contains "$OUT" "task promote: 1 promoted, 1 refused, 0 need a person"
  promote_created task/T-1 || fail "T-1 must still be promoted: $(cat gh.log)"
  if promote_created task/T-2; then fail "T-2 must not be promoted"; fi
}

# A conflict needs a person: the run exits 3 when nothing was refused, and
# the trial merge's worktree is gone with the task's subshell.
test_promote_a_task_that_needs_a_person_exits_3() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  promote_conflict
  local worktrees
  worktrees=$(git worktree list | wc -l)

  run jig task promote T-1 T-2
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: task/T-1 conflicts with main in:"
  assert_contains "$OUT" "task promote: T-1: needs a person"
  assert_contains "$OUT" "task promote: T-2: promoted"
  assert_contains "$OUT" "task promote: 1 promoted, 0 refused, 1 need a person"
  assert_eq "$worktrees" "$(git worktree list | wc -l)" "the trial merge's worktree must be gone"
}

# A refusal outweighs a person needed: the run exits 1.
test_promote_a_refusal_outweighs_a_person_needed() {
  promote_setup
  promote_conflict
  promote_task T-2 two.txt "work of T-2"

  run jig task promote T-1 T-2
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: T-1: needs a person"
  assert_contains "$OUT" "task promote: T-2: refused"
}

# What would refuse every task refuses the run before the first one.
test_promote_several_refuses_a_tested_commit_off_staging_once() {
  promote_setup
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  local off
  git checkout -q main
  printf 'off\n' > off.txt
  git add off.txt
  git commit -q -m "Not on staging"
  off=$(git rev-parse HEAD)

  run jig task promote --commit "$off" T-1 T-2
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "is not a commit of origin/staging"
  assert_not_contains "$OUT" "promoting"
  assert_no_file gh-create.argv
}

test_promote_refuses_mixed_or_incomplete_several() {
  promote_setup
  printf 'body\n' > body.md

  run jig task promote --all
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: --all needs --commit <sha>, the staging commit that was tested"
  run jig task promote --commit "$(git rev-parse origin/staging)" --all T-1
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "give ids or --all, not both"
  run jig task promote --title "One title" T-1 T-2
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: --title and --body-file are for one task"
  run jig task promote --commit "$(git rev-parse origin/staging)" --all --body-file body.md
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: --title and --body-file are for one task"
  assert_no_file gh-create.argv
}

# --all on a CI runner with no workspace: ids come from the branch names on
# origin, and only a branch whose tip the tested commit holds and the base
# does not is promoted. One tested and fixed after the test is named as
# skipped; one never tested is not mentioned.
test_promote_all_takes_only_tested_branches_not_in_the_base() {
  promote_setup
  # T-2: tested and already merged into main.
  promote_task T-2 two.txt "work of T-2"
  promote_land T-2
  git checkout -q main
  git merge -q --no-ff -m "Merge T-2" task/T-2
  git push -q origin main
  # T-3: pushed, never landed.
  promote_task T-3 three.txt "work of T-3"
  # T-4: landed, then a fix pushed after the tested commit.
  promote_task T-4 four.txt "work of T-4"
  promote_land T-4
  local tested
  tested=$(git rev-parse origin/staging)
  git checkout -q task/T-4
  printf 'fix\n' >> four.txt
  git commit -q -am "Fix of T-4 after the test"
  git push -q origin task/T-4
  # feature/x: on staging, not a task branch.
  git checkout -q -b feature/x main
  printf 'x\n' > x.txt
  git add x.txt
  git commit -q -m "Feature x"
  git push -q origin feature/x
  git clone -q origin.git runner
  cd runner || return 1

  run env CI=true "$JIG_BIN" task promote --commit "$tested" --all
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: promoting T-1"
  assert_not_contains "$OUT" "promoting T-2"
  assert_not_contains "$OUT" "promoting T-3"
  assert_not_contains "$OUT" "promoting T-4"
  assert_not_contains "$OUT" "promoting feature"
  # T-4 was tested, then fixed: said, not promoted, and no failure.
  assert_contains "$OUT" "task promote: skipped T-4: it has commits the tested commit $(git rev-parse --short "$tested") does not have; promote it after they are tested"
  assert_not_contains "$OUT" "skipped T-3"
  assert_not_contains "$OUT" "skipped T-2"
  assert_contains "$OUT" "task promote: 1 promoted, 0 refused, 0 need a person"
  cd .. || return 1
  promote_created task/T-1 || fail "no pull request for task/T-1: $(cat gh.log)"
  [ ! -d runner/.ai/workspace/tasks/T-1 ] || fail "a runner must not get a workspace"
}

test_promote_all_with_nothing_tested_is_nothing_to_do() {
  promote_setup
  git checkout -q main
  git merge -q --no-ff -m "Merge T-1" task/T-1
  git push -q origin main

  run jig task promote --commit "$(git rev-parse origin/staging)" --all
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: no task branch on origin is in the tested commit $(git rev-parse --short origin/staging) of staging and not yet in main; nothing to promote"
  assert_no_file gh-create.argv
}

# The ids --all reads follow git.branch_template.
test_promote_all_follows_the_branch_template() {
  promote_setup
  sed 's|^git.branch_template:.*|git.branch_template: work/{id}-x|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml
  git add .ai/config.yaml
  git commit -q -m "fixture: another branch template"
  git push -q origin HEAD
  git checkout -q main
  git merge -q task/T-1 >/dev/null
  git push -q origin main
  git checkout -q -b work/T-5-x
  printf 'five\n' > five.txt
  git add five.txt
  git commit -q -m "Work of T-5"
  git push -q origin work/T-5-x
  git checkout -q staging
  git merge -q --no-ff -m "Land T-5 on staging" work/T-5-x
  git push -q origin staging

  run jig task promote --commit "$(git rev-parse origin/staging)" --all
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: promoting T-5"
  assert_contains "$OUT" "task promote: 1 promoted, 0 refused, 0 need a person"
  promote_created work/T-5-x || fail "no pull request for work/T-5-x: $(cat gh.log)"
}

# A template with nothing before {id} would make every branch whose name is a
# valid id a task's, staging and main included: --all refuses it.
test_promote_all_refuses_a_template_with_no_prefix() {
  promote_setup
  sed 's|^git.branch_template:.*|git.branch_template: {id}|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml

  run jig task promote --commit "$(git rev-parse origin/staging)" --all
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: --all cannot tell a task branch by git.branch_template {id}"
  assert_not_contains "$OUT" "promoting"
  assert_no_file gh-create.argv
}

# The same id twice is one task: the one-task path, --title included.
test_promote_a_repeated_id_is_one_task() {
  promote_setup

  run jig task promote T-1 T-1 --title "The title"
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "promoting T-1"
  assert_contains "$(cat gh-create.argv)" "The title"
  assert_eq 1 "$(grep -c '^pr create' gh.log)"
}

# Origin's branches that cannot be listed refuse the run: --all cannot tell
# what the tested commit holds.
test_promote_all_refuses_when_origin_cannot_be_listed() {
  promote_setup
  local real
  real=$(command -v git)
  mkdir -p nolist-bin
  cat > nolist-bin/git <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = ls-remote ]; then printf 'fatal: could not read from remote repository\n' >&2; exit 128; fi
done
exec "$real" "\$@"
STUB
  chmod +x nolist-bin/git

  run env PATH="$PWD/nolist-bin:$PATH" "$JIG_BIN" task promote --commit "$(git rev-parse origin/staging)" --all
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task promote: could not list the branches on origin, so --all cannot tell which tasks the tested commit holds."
  assert_contains "$OUT" "could not read from remote repository"
  assert_not_contains "$OUT" "promoting"
  assert_no_file gh-create.argv
}
