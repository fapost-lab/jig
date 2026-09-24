# Tests for .github/workflows/ci.yml itself — specifically, the division of the
# Windows suite into shares, which is the one thing about the file that no CI
# run can check. A workflow whose shares do not cover the suite runs exactly
# what it was told to and reports green on the part it ran.
#
# That is the empty selection domains/verify/RULES.md refuses ("a narrowing
# that selects nothing is not a pass"), one level above a profile: not a filter
# matching no test, but a share of the suite nobody was asked to run at all.
#
# The number of shares used to be written three times — the matrix that creates
# the jobs, the job name, and the denominator of JIG_TEST_SHARD — and raising
# one of them and forgetting another ran half the suite silently. It is written
# once now: the denominator is ${{ strategy.job-total }}, which counts the
# matrix itself. What is left to guard is the matrix list, whose values are the
# share numbers: [1, 2, 3, 4, 5, 5] is six jobs, none of which is the sixth
# share, and nothing in a green run says so.
# shellcheck shell=bash

# cw_file — this repository's workflow, the subject of every test below.
cw_file() { printf '%s\n' "$JIG_HOME/.github/workflows/ci.yml"; }

# cw_shard_list — the share numbers of the test-windows matrix, one per line.
# A second `shard:` list anywhere in the file would be concatenated here, which
# the 1..n comparison below then reports as the mismatch it is.
cw_shard_list() {
  sed -n 's/^ *shard: *\[\([0-9, ]*\)\] *$/\1/p' "$(cw_file)" |
    tr ',' '\n' | tr -d ' ' | grep .
}

# Every share the runner is told to divide the suite into has a job to run it.
test_ci_workflow_windows_shares_cover_the_whole_suite() {
  local list count expected i
  list=$(cw_shard_list)
  [ -n "$list" ] || fail "no shard matrix in $(cw_file)"
  count=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
  expected=""
  i=1
  while [ "$i" -le "$count" ]; do
    expected="${expected}${i}
"
    i=$((i + 1))
  done
  expected=${expected%
}
  assert_eq "$expected" "$list" \
    "the shard matrix must be 1..n with no gaps or repeats: tests/run.sh divides the suite into n shares and a number missing from this list is a share no job runs"
}

# The count itself is the matrix's length, never a second copy of the number.
test_ci_workflow_windows_share_count_is_written_once() {
  local literal
  literal=$(grep -n 'matrix\.shard *}}/[0-9]' "$(cw_file)" || true)
  assert_eq "" "$literal" \
    "a hand-written denominator next to \${{ matrix.shard }} is a second copy of the share count that can disagree with the matrix; use \${{ strategy.job-total }}"
  # shellcheck disable=SC2016 # a workflow expression, matched literally
  grep -qF 'JIG_TEST_SHARD: ${{ matrix.shard }}/${{ strategy.job-total }}' "$(cw_file)" ||
    fail "the Windows suite must take its share count from the matrix: JIG_TEST_SHARD: \${{ matrix.shard }}/\${{ strategy.job-total }}"
}
