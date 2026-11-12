# Tests for `.github/scripts/ci-matrix.sh`
# (adr-20261110-a-pull-request-runs-the-tests-its-change-reaches): how many
# shares each platform's test job runs in. shellcheck shell=bash
#
# Every test builds a small tests/ directory of its own and runs the script
# there, as the `scope` job runs it in the root of the checkout. Helpers are
# prefixed cm_.

# cm_suite <n> — tests/a.t.sh with <n> tests and tests/b.t.sh with one.
cm_suite() {
  local i=1
  mkdir -p tests durations
  : > tests/a.t.sh
  while [ "$i" -le "$1" ]; do
    printf 'test_a_%s() { :; }\n' "$i" >> tests/a.t.sh
    i=$((i + 1))
  done
  printf 'test_b_one() {\n  :\n}\nfunction test_b_two {\n  :\n}\n' > tests/b.t.sh
}

cm_run() {
  run "$JIG_HOME/.github/scripts/ci-matrix.sh" "$@"
}

# cm_count <os> — how many shares OUT gives <os> (ubuntu-latest, macos-latest
# or windows).
cm_count() {
  local line
  case "$1" in
    windows)
      line=$(printf '%s\n' "$OUT" | sed -n 's/^matrix_windows=//p')
      printf '%s\n' "$line" | tr ',' '\n' | grep -c '/'
      ;;
    *)
      line=$(printf '%s\n' "$OUT" | sed -n 's/^matrix_unix=//p')
      printf '%s\n' "$line" | tr '}' '\n' | grep -c "\"os\":\"$1\""
      ;;
  esac
}

test_ci_matrix_a_small_selection_gets_one_share_each() {
  cm_suite 3
  printf 'b::\n' > filters
  cm_run selected filters durations
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'matrix_unix={"include":[{"os":"ubuntu-latest","shard":"1/1"},{"os":"macos-latest","shard":"1/1"}]}'
  assert_contains "$OUT" 'matrix_windows={"shard":["1/1"]}'
  assert_contains "$OUT" "linux: 2 tests (0 timed)"
}

test_ci_matrix_the_whole_suite_reaches_each_platform_ceiling() {
  cm_suite 4000
  cm_run all /dev/null durations
  assert_eq 0 "$RC"
  assert_eq 4 "$(cm_count ubuntu-latest)"
  assert_eq 4 "$(cm_count macos-latest)"
  assert_eq 10 "$(cm_count windows)"
}

test_ci_matrix_shares_are_numbered_one_to_n_with_one_n() {
  cm_suite 4000
  cm_run all /dev/null durations
  assert_contains "$OUT" '{"os":"ubuntu-latest","shard":"1/4"},{"os":"ubuntu-latest","shard":"2/4"},{"os":"ubuntu-latest","shard":"3/4"},{"os":"ubuntu-latest","shard":"4/4"}'
  assert_contains "$OUT" '"1/10","2/10","3/10","4/10","5/10","6/10","7/10","8/10","9/10","10/10"'
}

test_ci_matrix_the_durations_table_decides_the_count() {
  cm_suite 20
  printf 'a::\n' > filters
  # 20 tests of 300 s on Linux: 6000 s at 4 workers is 1500 s, five shares
  # of 360 s capped at four. A table in the report form, with garbage rows.
  : > durations/linux.tsv
  i=1
  while [ "$i" -le 20 ]; do
    printf '0\t300\ta::test_a_%s\n' "$i" >> durations/linux.tsv
    i=$((i + 1))
  done
  printf 'garbage\nx\tnot-a-number\ta::test_a_1\n' >> durations/linux.tsv
  cm_run selected filters durations
  assert_eq 0 "$RC"
  assert_eq 4 "$(cm_count ubuntu-latest)"
  assert_contains "$OUT" "linux: 20 tests (20 timed)"
  # macOS has no table: 20 tests at the average are one share.
  assert_eq 1 "$(cm_count macos-latest)"
}

test_ci_matrix_refuses_what_it_cannot_plan() {
  cm_suite 3
  cm_run selected /nonexistent durations
  assert_eq 2 "$RC"
  # A selection it cannot read tests for is one share each, not a refusal:
  # tests/run.sh decides what the filters select.
  printf 'nothing-matches::\n' > filters
  cm_run selected filters durations
  assert_eq 0 "$RC"
  assert_contains "$OUT" "one share each"
  assert_contains "$OUT" 'matrix_windows={"shard":["1/1"]}'
  cm_run partial filters durations
  assert_eq 2 "$RC"
  cm_run all /dev/null
  assert_eq 2 "$RC"
}

test_ci_matrix_reads_test_names_as_the_runner_discovers_them() {
  cm_suite 2
  cm_run all /dev/null durations
  # Two in a.t.sh and both forms in b.t.sh.
  assert_contains "$OUT" "linux: 4 tests"
}
