# Tests for `.github/scripts/ci-run-tests.sh`, the Tests step of the test jobs
# (adr-20261110-a-pull-request-runs-the-tests-its-change-reaches): it hands
# tests/run.sh the plan's filters and this platform's durations, and asks for
# the report. shellcheck shell=bash
#
# tests/run.sh is a stub here that prints its arguments and the variables it
# was given; each test works in its own directory as the job works in the
# checkout.

crt_setup() {
  mkdir -p tests temp/plan/durations
  cat > tests/run.sh <<'STUB'
#!/usr/bin/env bash
printf 'args:%s\n' "$*"
printf 'durations:%s\n' "${JIG_TEST_DURATIONS:-}"
printf 'report:%s\n' "${JIG_TEST_REPORT:-}"
printf 'shard:%s\n' "${JIG_TEST_SHARD:-}"
exit "${STUB_RC:-0}"
STUB
  chmod +x tests/run.sh
}

# The job these tests run in exports its own JIG_TEST_DURATIONS and
# JIG_TEST_REPORT; without taking them out, a test of "no table for this
# platform" read the real job's table and failed on a full Linux run.
crt_run() {
  run env -u JIG_TEST_DURATIONS -u JIG_TEST_REPORT RUNNER_TEMP="$PWD/temp" RUNNER_OS="${CRT_OS:-Linux}" SUITE="$1" \
    JIG_TEST_SHARD=2/3 "$JIG_HOME/.github/scripts/ci-run-tests.sh"
}

test_ci_run_tests_runs_the_whole_suite_with_this_platforms_durations() {
  crt_setup
  printf '0\t3\ta::test_x\n' > temp/plan/durations/macos.tsv
  CRT_OS=macOS crt_run all
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "args:
"
  assert_contains "$OUT" "durations:$PWD/temp/plan/durations/macos.tsv"
  assert_contains "$OUT" "report:$PWD/temp/report/report.tsv"
  assert_contains "$OUT" "shard:2/3"
  assert_dir temp/report
}

test_ci_run_tests_passes_the_selected_filters() {
  crt_setup
  printf 'task::\nqueue::test_q\n\n' > temp/plan/filters
  crt_run selected
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "args:task:: queue::test_q"
  # No table for Linux: the runner divides by round-robin.
  assert_contains "$OUT" "durations:
"
}

test_ci_run_tests_refuses_a_selection_without_filters() {
  crt_setup
  crt_run selected
  assert_eq 2 "$RC"
  assert_contains "$OUT" "a selected suite without filters"
  printf '\n\n' > temp/plan/filters
  crt_run selected
  assert_eq 2 "$RC"
  crt_run partial
  assert_eq 2 "$RC"
}

test_ci_run_tests_exits_as_the_runner_exits() {
  crt_setup
  STUB_RC=3 crt_run all
  assert_eq 3 "$RC"
}
