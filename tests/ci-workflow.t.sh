# Tests for .github/workflows/ci.yml itself — specifically, the division of the
# suite into shares on every platform, which is the one thing about the file
# that no CI run can check. A workflow whose shares do not cover the suite runs
# exactly what it was told to and reports green on the part it ran.
#
# That is the empty selection domains/verify/RULES.md refuses ("a narrowing
# that selects nothing is not a pass"), one level above a profile: not a filter
# matching no test, but a share of the suite nobody was asked to run at all.
#
# The shares used to be written into the matrices here, and the tests below
# held each platform's entries to 1/n .. n/n. Their number now follows the work
# the run selected (adr-20261110-a-pull-request-runs-the-tests-its-change-reaches):
# the `scope` job computes both matrices with .github/scripts/ci-matrix.sh,
# whose tests hold every platform to 1/n .. n/n with one n
# (tests/ci-matrix.t.sh). What is left to guard here is that the jobs take
# those matrices and nothing else, and hand each share to the runner as it
# was planned.
# shellcheck shell=bash

# cw_file — this repository's workflow, the subject of every test below.
cw_file() { printf '%s\n' "$JIG_HOME/.github/workflows/ci.yml"; }

# cw_job_block <job> — the lines of one job, from its `  <job>:` line to the
# line before the next job.
cw_job_block() {
  awk -v job="  $1:" '
    $0 == job { f = 1; print; next }
    f && /^  [A-Za-z0-9_-]+:[ ]*$/ { exit }
    f { print }
  ' "$(cw_file)"
}

# cw_has <block> <line> — whether <block> holds <line> exactly, leading
# spaces aside.
cw_has() {
  printf '%s\n' "$1" | sed 's/^ *//' | grep -qxF "$2"
}

# The scope job plans the shares with ci-matrix.sh and publishes both
# matrices and the plan every share reads.
test_ci_workflow_scope_plans_the_shares() {
  local block
  block=$(cw_job_block scope)
  # shellcheck disable=SC2016 # workflow expressions, matched literally
  cw_has "$block" 'matrix_unix: ${{ steps.plan.outputs.matrix_unix }}' ||
    fail "scope must publish matrix_unix from its plan step"
  # shellcheck disable=SC2016
  cw_has "$block" 'matrix_windows: ${{ steps.plan.outputs.matrix_windows }}' ||
    fail "scope must publish matrix_windows from its plan step"
  # shellcheck disable=SC2016 # a workflow line, matched literally
  assert_contains "$block" '.github/scripts/ci-matrix.sh "$SUITE"' \
    "the plan step must ask ci-matrix.sh for the shares"
  assert_contains "$block" 'name: plan' "scope must upload the plan artifact"
}

# Each test job's matrix is scope's answer, with no key of its own beside it:
# a base key would make GitHub merge entries and run one share per platform.
test_ci_workflow_test_jobs_take_their_matrix_from_scope() {
  local block
  block=$(cw_job_block test)
  # shellcheck disable=SC2016
  cw_has "$block" 'matrix: ${{ fromJSON(needs.scope.outputs.matrix_unix) }}' ||
    fail "the test job's matrix must be scope's matrix_unix, whole"
  block=$(cw_job_block test-windows)
  # shellcheck disable=SC2016
  cw_has "$block" 'matrix: ${{ fromJSON(needs.scope.outputs.matrix_windows) }}' ||
    fail "the test-windows job's matrix must be scope's matrix_windows, whole"
}

# The share reaches the runner as scope named it, through the one script
# that reads the plan, and nothing else decides it.
test_ci_workflow_test_jobs_pass_their_share_and_plan_to_the_runner() {
  local job block
  for job in test test-windows; do
    block=$(cw_job_block "$job")
    # shellcheck disable=SC2016
    cw_has "$block" 'JIG_TEST_SHARD: ${{ matrix.shard }}' ||
      fail "$job must run its own share: JIG_TEST_SHARD: \${{ matrix.shard }}"
    assert_eq 1 "$(printf '%s\n' "$block" | grep -c 'JIG_TEST_SHARD:')" \
      "$job must set JIG_TEST_SHARD once, from the matrix"
    cw_has "$block" 'run: .github/scripts/ci-run-tests.sh' ||
      fail "$job must run the suite through .github/scripts/ci-run-tests.sh"
    assert_contains "$block" 'uses: actions/download-artifact@v8' \
      "$job must download the plan before it runs"
    # shellcheck disable=SC2016 # a workflow expression, matched literally
    assert_contains "$block" 'path: ${{ runner.temp }}/report/report.tsv' \
      "$job must keep its report: the nightly reports are the next plan's durations"
  done
}

# A hand-written denominator next to the share would be a second copy of the
# count that can disagree with the matrix.
test_ci_workflow_writes_no_share_count_by_hand() {
  local literal
  literal=$(grep -n 'matrix\.shard *}}/' "$(cw_file)" || true)
  assert_eq "" "$literal" "the share is <i>/<n> as scope wrote it; nothing appends a denominator"
}

# The suite a run tested is in each test job's name: ci-reuse.sh reads it to
# tell a run of the whole suite from a run of part of it.
test_ci_workflow_test_job_names_carry_the_suite() {
  # shellcheck disable=SC2016
  cw_has "$(cw_job_block test)" 'name: ${{ matrix.os }} ${{ matrix.shard }} (${{ needs.scope.outputs.suite }})' ||
    fail "the test job's name must end in (\${{ needs.scope.outputs.suite }})"
  # shellcheck disable=SC2016
  cw_has "$(cw_job_block test-windows)" 'name: windows-latest (Git Bash) ${{ matrix.shard }} (${{ needs.scope.outputs.suite }})' ||
    fail "the test-windows job's name must end in (\${{ needs.scope.outputs.suite }})"
}

# Only a run of the whole suite releases.
test_ci_workflow_release_needs_the_whole_suite() {
  # shellcheck disable=SC2016
  assert_contains "$(cw_job_block release)" "needs.scope.outputs.suite == 'all'" \
    "release must tag only after a run of the whole suite"
}

# A pull request's run checks out the pull request merged into its base as the
# base is now. Measured from the event's base.sha — where the branch started —
# every commit that landed on the base since counts as the pull request's own:
# #394, two spec files, ran the full suite because main had changed
# scripts/lib/config.sh meanwhile. Both scope scripts take the merge commit's
# first parent instead, and nothing in the scope job reads base.sha.
test_ci_workflow_scope_measures_a_pull_request_from_its_merge_parent() {
  local block
  block=$(cw_job_block scope)
  printf '%s\n' "$block" | grep -qF "git rev-parse --verify --quiet 'HEAD^1'" ||
    fail "the scope job must take a pull request's base as the merge commit's first parent (HEAD^1)"
  # shellcheck disable=SC2016 # shell variables in a workflow, matched literally
  printf '%s\n' "$block" | grep -qF '.github/scripts/ci-scope.sh "$pr_base"' ||
    fail "the scope job must pass the merge parent to ci-scope.sh"
  # shellcheck disable=SC2016 # shell variables in a workflow, matched literally
  printf '%s\n' "$block" | grep -qF '.github/scripts/ci-windows-scope.sh "$pr_base"' ||
    fail "the scope job must pass the merge parent to ci-windows-scope.sh"
  if printf '%s\n' "$block" | grep -qF 'pull_request.base.sha'; then
    fail "the scope job must not read github.event.pull_request.base.sha: it is where the branch started, not what it merges into"
  fi
}
