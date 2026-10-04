# Tests for `.github/scripts/ci-ok.sh`, the verdict of the `ci-ok` job.
# shellcheck shell=bash
#
# The verdict must tell a skip that `scope` decided from a skip nobody decided:
# a job that had to run and came back `skipped` fails, a job that had no
# reason to run may be skipped. Both halves are tested, since a rule that only
# fails would refuse every light change.

# co_run <full> <windows> <event> <base-ref> <head-ref> <job=result>... — run
# the script the way the `ci-ok` job does.
co_run() {
  local full="$1" windows="$2" event="$3" base="$4" head="$5"
  shift 5
  run env FULL="$full" WINDOWS="$windows" EVENT="$event" BASE_REF="$base" HEAD_REF="$head" \
    "$JIG_HOME/.github/scripts/ci-ok.sh" "$@"
}

# A full push: everything but `knowledge`, `changelog` and `epic-pr` ran.
co_full_push() {
  co_run true true push "" "" \
    scope=success knowledge=skipped test=success test-windows=success \
    smoke-windows=success changelog=skipped epic-pr=skipped
}

test_ci_ok_passes_a_full_run_where_every_required_job_succeeded() {
  co_full_push
  assert_eq 0 "$RC" "$OUT"
}

# The case the old verdict could not see: `test` is required by a full scope.
test_ci_ok_fails_when_a_required_job_is_skipped() {
  co_run true true push "" "" \
    scope=success knowledge=skipped test=skipped test-windows=success \
    smoke-windows=success changelog=skipped epic-pr=skipped
  assert_eq 1 "$RC" "a skipped test job must not read as a pass"
  assert_contains "$OUT" "'test' was skipped"
}

# co_res <skipped-job> <job> — the result a job gets when <skipped-job> is the
# one that came back skipped.
co_res() {
  if [ "$1" = "$2" ]; then echo skipped; else echo success; fi
}

test_ci_ok_fails_when_each_required_job_is_skipped_in_turn() {
  local job
  for job in test test-windows smoke-windows; do
    co_run true true push "" "" \
      scope=success knowledge=skipped "test=$(co_res "$job" test)" \
      "test-windows=$(co_res "$job" test-windows)" \
      "smoke-windows=$(co_res "$job" smoke-windows)" \
      changelog=skipped epic-pr=skipped
    assert_eq 1 "$RC" "$job skipped on a full push"
    assert_contains "$OUT" "'$job' was skipped"
  done
}

# The other side: a light scope skips the suite and that is the design.
test_ci_ok_passes_a_light_pull_request_with_the_suite_skipped() {
  co_run false false pull_request main docs-branch \
    scope=success knowledge=success test=skipped test-windows=skipped \
    smoke-windows=skipped changelog=success epic-pr=skipped
  assert_eq 0 "$RC" "$OUT"
}

test_ci_ok_fails_a_light_scope_where_knowledge_was_skipped() {
  co_run false false pull_request main docs-branch \
    scope=success knowledge=skipped test=skipped test-windows=skipped \
    smoke-windows=skipped changelog=success epic-pr=skipped
  assert_eq 1 "$RC"
  assert_contains "$OUT" "'knowledge' was skipped"
}

# Windows shards are decided by `scope` too: a pull request that touches
# nothing platform-specific skips them, and smoke-windows still has to run.
test_ci_ok_passes_a_full_pull_request_that_skips_the_windows_shards() {
  co_run true false pull_request main feature \
    scope=success knowledge=skipped test=success test-windows=skipped \
    smoke-windows=success changelog=success epic-pr=skipped
  assert_eq 0 "$RC" "$OUT"
}

test_ci_ok_fails_when_the_windows_shards_are_skipped_but_scope_asked_for_them() {
  co_run true true pull_request main feature \
    scope=success knowledge=skipped test=success test-windows=skipped \
    smoke-windows=success changelog=success epic-pr=skipped
  assert_eq 1 "$RC"
  assert_contains "$OUT" "'test-windows' was skipped"
}

test_ci_ok_requires_the_changelog_check_on_a_pull_request_only() {
  co_run true true pull_request main feature \
    scope=success knowledge=skipped test=success test-windows=success \
    smoke-windows=success changelog=skipped epic-pr=skipped
  assert_eq 1 "$RC"
  assert_contains "$OUT" "'changelog' was skipped"
}

test_ci_ok_requires_the_epic_gate_for_a_pull_request_from_an_epic_branch() {
  co_run true true pull_request main epic/some-feature \
    scope=success knowledge=skipped test=success test-windows=success \
    smoke-windows=success changelog=success epic-pr=skipped
  assert_eq 1 "$RC"
  assert_contains "$OUT" "'epic-pr' was skipped"
  co_run true true pull_request main epic/some-feature \
    scope=success knowledge=skipped test=success test-windows=success \
    smoke-windows=success changelog=success epic-pr=success
  assert_eq 0 "$RC" "$OUT"
  # The finish branch `jig spec ship` cuts from the epic is gated the same way.
  co_run true true pull_request main finish/some-feature \
    scope=success knowledge=skipped test=success test-windows=success \
    smoke-windows=success changelog=success epic-pr=skipped
  assert_eq 1 "$RC"
  assert_contains "$OUT" "'epic-pr' was skipped"
  # Into another branch than main the gate has no reason to run.
  co_run true true pull_request epic/some-feature task/x \
    scope=success knowledge=skipped test=success test-windows=success \
    smoke-windows=success changelog=success epic-pr=skipped
  assert_eq 0 "$RC" "$OUT"
}

test_ci_ok_fails_on_a_failed_or_cancelled_job_wherever_it_is() {
  local result
  for result in failure cancelled; do
    co_run false false pull_request main docs-branch \
      scope=success knowledge="$result" test=skipped test-windows=skipped \
      smoke-windows=skipped changelog=success epic-pr=skipped
    assert_eq 1 "$RC" "knowledge $result"
    # A job that was not required to run does not get to fail either.
    co_run false false pull_request main docs-branch \
      scope=success knowledge=success test="$result" test-windows=skipped \
      smoke-windows=skipped changelog=success epic-pr=skipped
    assert_eq 1 "$RC" "test $result"
  done
}

test_ci_ok_fails_when_scope_itself_did_not_succeed() {
  co_run "" "" push "" "" scope=failure knowledge=skipped test=skipped \
    test-windows=skipped smoke-windows=skipped changelog=skipped epic-pr=skipped
  assert_eq 1 "$RC"
  assert_contains "$OUT" "scope ended as 'failure'"
}

test_ci_ok_fails_when_scope_published_no_answer() {
  co_run "" "" push "" "" scope=success knowledge=skipped test=skipped \
    test-windows=skipped smoke-windows=skipped changelog=skipped epic-pr=skipped
  assert_eq 1 "$RC" "an empty 'full' must not read as light"
}

test_ci_ok_fails_with_no_results_or_an_unknown_job() {
  co_run true true push "" ""
  assert_eq 1 "$RC"
  co_run true true push "" "" scope=success surprise=success
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown job 'surprise'"
}

# The workflow side: every job `ci-ok` waits for is also handed to the script,
# so a job added to `needs` cannot slip past the verdict unchecked.
test_ci_ok_workflow_passes_every_needed_job_to_the_script() {
  local file="$JIG_HOME/.github/workflows/ci.yml" needs job
  needs=$(awk '/^  ci-ok:/{f=1} f && /^    needs:/{print; exit}' "$file" |
    sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | tr -d ' ')
  [ -n "$needs" ] || fail "no needs list for ci-ok in $file"
  for job in $needs; do
    # shellcheck disable=SC2016 # a workflow expression, matched literally
    grep -qF "\"$job=\${{ needs.$job.result }}\"" "$file" ||
      fail "ci-ok waits for '$job' but does not pass its result to ci-ok.sh"
  done
}

# The expectations in ci-ok.sh are a second copy of each job's `if:`. This
# holds the copy against the original: change a condition in ci.yml and this
# fails until ci-ok.sh and its tests are taught the new one.
test_ci_ok_expectations_match_the_conditions_in_the_workflow() {
  local file="$JIG_HOME/.github/workflows/ci.yml" flat
  flat=$(tr -s ' \n' ' ' < "$file")
  # shellcheck disable=SC2016 # workflow expressions, matched literally
  {
    grep -qF "knowledge: needs: scope if: needs.scope.outputs.full != 'true'" <<< "$flat" ||
      fail "the condition of knowledge changed; update ci-ok.sh"
    grep -qF "name: \${{ matrix.os }} needs: scope if: needs.scope.outputs.full == 'true' runs-on:" <<< "$flat" ||
      fail "the condition of test changed; update ci-ok.sh"
    grep -qF "if: needs.scope.outputs.full == 'true' && needs.scope.outputs.windows == 'true'" <<< "$flat" ||
      fail "the condition of test-windows changed; update ci-ok.sh"
    grep -qF "name: windows-latest smoke (install.ps1) needs: scope if: needs.scope.outputs.full == 'true'" <<< "$flat" ||
      fail "the condition of smoke-windows changed; update ci-ok.sh"
    grep -qF "changelog: if: github.event_name == 'pull_request'" <<< "$flat" ||
      fail "the condition of changelog changed; update ci-ok.sh"
    grep -qF "&& github.event_name == 'pull_request' && github.base_ref == 'main' && (startsWith(github.head_ref, 'epic/') || startsWith(github.head_ref, 'finish/'))" <<< "$flat" ||
      fail "the condition of epic-pr changed; update ci-ok.sh"
  }
}
