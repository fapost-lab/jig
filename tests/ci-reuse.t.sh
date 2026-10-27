# Tests for `.github/scripts/ci-reuse.sh` (task reuse-green-tree-on-main).
# shellcheck shell=bash
#
# No network: `gh` is a stub on PATH. It answers the pull request that made a
# commit from $PWD/pulls.txt (the head commits the script's filter would
# keep), the pull-request runs from $PWD/runs.txt and a run's jobs from
# $PWD/jobs-<id>.txt, fails a call whose file is missing, and logs every call
# to $PWD/gh.log. Every test builds
# a fixture history under its own tmp dir — main, a pull request's branch and
# its merge — and runs the script there with HEAD at the merge (cr_check),
# the way the `scope` job does on a push to main. Helpers are prefixed cr_.

# --- fixture builders --------------------------------------------------------

# cr_commit <dir> <file> <content> <message> — write and commit one file.
cr_commit() {
  (
    cd "$1" || exit 1
    printf '%s\n' "$3" > "$2"
    git add "$2"
    git commit -q -m "$4"
  )
}

# cr_history <dir> <up-to-date> — main with one commit, a branch `pr` with a
# change, and HEAD on main at the merge of `pr`. When <up-to-date> is `yes`,
# `pr` contains main's tip (the branch merged main back in); with `no`, the
# branch never did, but made main's change itself, so the merge has the
# branch's own tree while main's tip is not in its history — the case only
# the ancestry test can tell. Prints nothing; read the commits with cr_sha.
cr_history() {
  local dir="$1"
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    fixture_repo
    git checkout -q -b pr
    printf 'feature\n' > feature.txt
    git add feature.txt
    git commit -q -m feature
    git checkout -q main
    printf 'other\n' > other.txt
    git add other.txt
    git commit -q -m "other change on main"
    git tag before
    git checkout -q pr
    if [ "$2" = yes ]; then
      git merge -q --no-edit main
    else
      printf 'other\n' > other.txt
      git add other.txt
      git commit -q -m "the same change, made on the branch"
    fi
    git checkout -q main
    git merge -q --no-ff --no-edit pr
  )
}

# cr_sha <dir> <rev> — the commit <rev> names in <dir>.
cr_sha() {
  git -C "$1" rev-parse "$2"
}

# cr_pulls <sha>... — the head commits of the pull requests into main merged
# as HEAD (what the script's --jq filter keeps).
cr_pulls() {
  printf '%s\n' "$@" > "$PWD/pulls.txt"
}

# cr_runs <line>... — the successful pull-request runs GitHub lists, newest
# first, each `<id> <head_sha> <url>`.
cr_runs() {
  printf '%s\n' "$@" > "$PWD/runs.txt"
}

# cr_jobs <id> <conclusion name>... — the jobs of run <id>.
cr_jobs() {
  local id="$1"
  shift
  printf '%s\n' "$@" > "$PWD/jobs-$id.txt"
}

# cr_full_jobs <id> — the jobs of a full pull-request run, Windows included,
# as the jobs API listed them for run 40490575838 (#323) under this ci.yml:
# every share by name, and the main-only jobs skipped.
cr_full_jobs() {
  cr_jobs "$1" "success changelog" "success scope" "success windows-latest smoke (install.ps1)" \
    "success ubuntu-latest 1/2" "success ubuntu-latest 2/2" \
    "success macos-latest 1/3" "success macos-latest 2/3" "success macos-latest 3/3" \
    "success windows-latest (Git Bash) 1/10" "success windows-latest (Git Bash) 2/10" \
    "success windows-latest (Git Bash) 3/10" "success windows-latest (Git Bash) 4/10" \
    "success windows-latest (Git Bash) 5/10" "success windows-latest (Git Bash) 6/10" \
    "success windows-latest (Git Bash) 7/10" "success windows-latest (Git Bash) 8/10" \
    "success windows-latest (Git Bash) 9/10" "success windows-latest (Git Bash) 10/10" \
    "skipped knowledge" "skipped epic-pr" "success ci-ok" "skipped release" "skipped red-main"
}

# cr_gh — install the stub `gh`.
cr_gh() {
  mkdir -p "$PWD/stub-bin"
  cat > "$PWD/stub-bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/gh.log"
case "\$*" in
  */pulls*)
    [ -f "$PWD/pulls.txt" ] || exit 1
    cat "$PWD/pulls.txt"
    ;;
  */jobs*)
    id="\$*"
    id=\${id#*actions/runs/}
    id=\${id%%/jobs*}
    [ -f "$PWD/jobs-\$id.txt" ] || exit 1
    cat "$PWD/jobs-\$id.txt"
    ;;
  *)
    [ -f "$PWD/runs.txt" ] || exit 1
    cat "$PWD/runs.txt"
    ;;
esac
STUB
  chmod +x "$PWD/stub-bin/gh"
}

# cr_check <dir> <before> — run the script under test in <dir>.
cr_check() {
  local stub="$PWD/stub-bin"
  (cd "$1" && PATH="$stub:$PATH" GITHUB_REPOSITORY=example/jig \
    "$JIG_HOME/.github/scripts/ci-reuse.sh" "$2")
}

# --- reuse -------------------------------------------------------------------

test_ci_reuse_full_run_of_an_up_to_date_branch_is_reused() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs "7 $pr https://github.com/example/jig/actions/runs/7"
  cr_full_jobs 7

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "reuse (https://github.com/example/jig/actions/runs/7 tested tree"
  # The question asked is the successful pull-request runs of ci.
  # The pull request is the one into main merged as HEAD, and its runs are
  # asked for by its head commit.
  assert_file_contains "$PWD/gh.log" "repos/example/jig/commits/$(cr_sha "$repo" HEAD)/pulls"
  assert_file_contains "$PWD/gh.log" 'select(.base.ref == "main" and .merge_commit_sha =='
  assert_file_contains "$PWD/gh.log" "repos/example/jig/actions/workflows/ci.yml/runs"
  assert_file_contains "$PWD/gh.log" "event=pull_request"
  assert_file_contains "$PWD/gh.log" "status=success"
  assert_file_contains "$PWD/gh.log" "head_sha=$pr"
  assert_file_contains "$PWD/gh.log" "repos/example/jig/actions/runs/7/jobs"
}

# A run that does not qualify is passed over for an older one that does: a
# re-run of the same head, say, after the first attempt skipped Windows.
test_ci_reuse_looks_past_a_run_that_was_not_full() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs "9 $pr https://github.com/example/jig/actions/runs/9" \
    "8 $pr https://github.com/example/jig/actions/runs/8"
  cr_jobs 9 "success scope" "skipped knowledge" "success ubuntu-latest 1/2" \
    "skipped windows-latest (Git Bash) \${{ matrix.shard }}/\${{ strategy.job-total }}" \
    "success ci-ok"
  cr_full_jobs 8

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "reuse (https://github.com/example/jig/actions/runs/8 tested"
}

# --- test everything ------------------------------------------------------------

# The merge has the branch's tree, but main's tip is not in the branch: the
# pull request's run may have tested a merge onto an older main, so nothing
# says this tree was tested.
test_ci_reuse_branch_behind_main_tests_everything() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" no
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs "7 $pr https://github.com/example/jig/actions/runs/7"
  cr_full_jobs 7

  [ "$(cr_sha "$repo" 'pr^{tree}')" = "$(cr_sha "$repo" 'HEAD^{tree}')" ] \
    || fail "the fixture must give the merge the branch's own tree"

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "did not contain main's tip $before"
  assert_contains "$OUT" "test (no full green pull-request run tested tree"
}

# The branch is up to date, but a later commit on main has a tree no pull
# request tested.
test_ci_reuse_a_different_tree_tests_everything() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  cr_commit "$repo" direct.txt direct "a commit after the merge"
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs "7 $pr https://github.com/example/jig/actions/runs/7"
  cr_full_jobs 7

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (no green run of the pull request has tree"
}

test_ci_reuse_a_light_run_tests_everything() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs "7 $pr https://github.com/example/jig/actions/runs/7"
  cr_jobs 7 "success scope" "success knowledge" "skipped \${{ matrix.os }} \${{ matrix.shard }}" \
    "success changelog" "success ci-ok"

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (no full green pull-request run tested tree"
}

# Windows skipped: Linux and macOS ran, the Git Bash shares did not.
test_ci_reuse_a_run_without_windows_tests_everything() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs "7 $pr https://github.com/example/jig/actions/runs/7"
  cr_jobs 7 "success scope" "skipped knowledge" "success ubuntu-latest 1/2" \
    "success macos-latest 1/3" "success windows-latest smoke (install.ps1)" \
    "success changelog" "skipped epic-pr" "skipped release" "success ci-ok"

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test ("
  assert_contains "$OUT" "it skipped the Windows Git Bash shares"
}

test_ci_reuse_no_pull_request_runs_tests_everything() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs ""

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (no green run of the pull request has tree"
}

# --- unmeasurable tests everything ------------------------------------------------

# A push no pull request made — or one GitHub has not linked yet — has no
# run to lean on.
test_ci_reuse_without_a_merged_pull_request_tests_everything() {
  local repo="$PWD/repo" before
  cr_history "$repo" yes
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls ""

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (no pull request into main was merged as $(cr_sha "$repo" HEAD))"
}

test_ci_reuse_pull_request_unreadable_tests_everything() {
  local repo="$PWD/repo" before
  cr_history "$repo" yes
  before=$(cr_sha "$repo" before)
  cr_gh

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (cannot read the pull request that made"
}

test_ci_reuse_runs_unreadable_tests_everything() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (cannot read the pull-request runs of ci)"
}

test_ci_reuse_jobs_unreadable_tests_everything() {
  local repo="$PWD/repo" pr before
  cr_history "$repo" yes
  pr=$(cr_sha "$repo" pr)
  before=$(cr_sha "$repo" before)
  cr_gh
  cr_pulls "$pr"
  cr_runs "7 $pr https://github.com/example/jig/actions/runs/7"

  run cr_check "$repo" "$before"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test ("
  assert_contains "$OUT" "its jobs cannot be read"
}

test_ci_reuse_without_before_tests_everything() {
  local repo="$PWD/repo"
  cr_history "$repo" yes
  cr_gh

  run cr_check "$repo" ""
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (no commit before the push)"
  assert_no_file "$PWD/gh.log" "GitHub must not be asked without a commit to compare"

  run cr_check "$repo" 0000000000000000000000000000000000000000
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (new branch, nothing before the push)"

  run cr_check "$repo" ffffffffffffffffffffffffffffffffffffffff
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (ffffffffffffffffffffffffffffffffffffffff is not in the history)"
}

test_ci_reuse_without_repository_slug_tests_everything() {
  local repo="$PWD/repo" before stub="$PWD/stub-bin"
  cr_history "$repo" yes
  before=$(cr_sha "$repo" before)
  cr_gh

  run env -u GITHUB_REPOSITORY sh -c "cd '$repo' && PATH='$stub:$PATH' '$JIG_HOME/.github/scripts/ci-reuse.sh' '$before'"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "test (GITHUB_REPOSITORY is not set"
}

# --- the second copies ---------------------------------------------------------

# ci-reuse.sh recognises the Windows Git Bash shares by the start of their job
# name. A rename in ci.yml alone would only make main test everything, but a
# silent fallback is a speed-up lost without anyone knowing: hold the two
# together here.
test_ci_reuse_windows_prefix_matches_the_workflow() {
  local prefix
  prefix=$(sed -n 's/^CR_WINDOWS_PREFIX="\(.*\)"$/\1/p' "$JIG_HOME/.github/scripts/ci-reuse.sh")
  [ -n "$prefix" ] || fail "no CR_WINDOWS_PREFIX in ci-reuse.sh"
  grep -qF "    name: $prefix\${{ matrix.shard }}" "$JIG_HOME/.github/workflows/ci.yml" \
    || fail "test-windows is no longer named '$prefix…'; update CR_WINDOWS_PREFIX in ci-reuse.sh"
}

# The workflow asks the script on a full push to main only, hands it the
# commit before the push, and publishes its answer as scope's `reuse`.
test_ci_reuse_workflow_asks_on_a_full_push_to_main() {
  local file="$JIG_HOME/.github/workflows/ci.yml"
  # shellcheck disable=SC2016 # workflow expressions, matched literally
  {
    grep -qF 'reuse: ${{ steps.scope.outputs.reuse }}' "$file" || fail "scope does not publish reuse"
    grep -qF 'BEFORE: ${{ github.event.before }}' "$file" || fail "scope does not pass github.event.before"
    grep -qF 'push:main:full*)' "$file" || fail "reuse is not limited to a full push to main"
    grep -qF '.github/scripts/ci-reuse.sh "$BEFORE"' "$file" || fail "scope does not run ci-reuse.sh"
  }
}

# Every job of ci.yml is either one a full pull-request run into main runs, or
# one such a run always skips (CR_PR_SKIPS in ci-reuse.sh), or `knowledge`,
# whose skip is what says the run was full. A job in neither list would make
# every run look partial and reuse would stop without anyone noticing — which
# is what `red-main` did before it was listed.
test_ci_reuse_every_workflow_job_is_classified() {
  local runs="scope test test-windows smoke-windows changelog ci-ok" skips jobs job
  skips=$(sed -n 's/^CR_PR_SKIPS="\(.*\)"$/\1/p' "$JIG_HOME/.github/scripts/ci-reuse.sh")
  [ -n "$skips" ] || fail "no CR_PR_SKIPS in ci-reuse.sh"
  jobs=$(awk '/^jobs:/{f=1; next} f && /^  [a-z][a-z0-9-]*:$/{sub(/^  /,""); sub(/:$/,""); print}' \
    "$JIG_HOME/.github/workflows/ci.yml")
  [ -n "$jobs" ] || fail "no jobs read from ci.yml"
  for job in $jobs; do
    case " $runs $skips knowledge " in
      *" $job "*) ;;
      *) fail "job '$job' of ci.yml is in neither list: add it to CR_PR_SKIPS in ci-reuse.sh if a pull request into main skips it, or to the runs list here" ;;
    esac
  done
  # And the skip list names only jobs that are there.
  for job in $skips; do
    case " $(printf '%s\n' "$jobs" | tr '\n' ' ')" in
      *" $job "*) ;;
      *) fail "CR_PR_SKIPS names '$job', which ci.yml no longer has" ;;
    esac
  done
}
