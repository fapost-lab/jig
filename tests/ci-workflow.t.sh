# Tests for .github/workflows/ci.yml itself — specifically, the division of the
# suite into shares on every platform, which is the one thing about the file
# that no CI run can check. A workflow whose shares do not cover the suite runs
# exactly what it was told to and reports green on the part it ran.
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
#
# The Linux and macOS suite (job `test`) is one matrix over two platforms with
# different share counts, so `strategy.job-total` cannot serve it: each entry
# names its share as '<i>/<n>'
# (adr-20261016-the-suite-runs-in-shares-on-every-platform). That writes n once
# per entry, and the tests below hold the copies together: per platform,
# exactly 1/n .. n/n with one n.
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

# cw_job_block <job> — the lines of one job, from its `  <job>:` line to the
# line before the next job.
cw_job_block() {
  awk -v job="  $1:" '
    $0 == job { f = 1; print; next }
    f && /^  [A-Za-z0-9_-]+:[ ]*$/ { exit }
    f { print }
  ' "$(cw_file)"
}

# cw_test_entries — the `include` entries of the test job, one "<os> <i>/<n>"
# per line, in the order written.
cw_test_entries() {
  cw_job_block test |
    sed -n "s/^ *- *{ *os: *\([A-Za-z0-9._-]*\) *, *shard: *'\([0-9]*\/[0-9]*\)' *} *$/\1 \2/p"
}

# Every entry of the test matrix is in the one form the checks below read. An
# entry written another way — unquoted, keys swapped, an extra key — would be
# a job the parser does not see, and so a share nobody checks.
test_ci_workflow_test_matrix_entries_are_all_readable() {
  local written parsed
  written=$(cw_job_block test | grep -c '^ *- *{' || true)
  parsed=$(cw_test_entries | grep -c . || true)
  [ "$written" -gt 0 ] || fail "no include entries in the test job of $(cw_file)"
  assert_eq "$written" "$parsed" \
    "every include entry of the test job must read - { os: <os>, shard: '<i>/<n>' }"
}

# The suite keeps running on both platforms it runs on today.
test_ci_workflow_test_runs_on_linux_and_macos() {
  local entries
  entries=$(cw_test_entries)
  assert_contains "$entries" "ubuntu-latest " "the test job must run the suite on ubuntu-latest"
  assert_contains "$entries" "macos-latest " "the test job must run the suite on macos-latest"
}

# Per platform, the shares are exactly 1/n .. n/n: n entries, one denominator,
# every number from 1 to n once.
test_ci_workflow_test_shares_cover_the_whole_suite_on_each_platform() {
  local entries os shares count expected i
  entries=$(cw_test_entries)
  [ -n "$entries" ] || fail "no shares in the test job of $(cw_file)"
  for os in $(printf '%s\n' "$entries" | awk '{print $1}' | sort -u); do
    shares=$(printf '%s\n' "$entries" | awk -v os="$os" '$1 == os {print $2}' | sort -t/ -k1,1n)
    count=$(printf '%s\n' "$shares" | grep -c .)
    expected=""
    i=1
    while [ "$i" -le "$count" ]; do
      expected="${expected}${i}/${count}
"
      i=$((i + 1))
    done
    expected=${expected%
}
    assert_eq "$expected" "$shares" \
      "the shares of $os must be 1/n .. n/n with n the number of its entries: a share missing from the list is part of the suite no job runs"
  done
}

# The share reaches the runner, and nothing else decides it.
test_ci_workflow_test_passes_its_share_to_the_runner() {
  local block
  block=$(cw_job_block test)
  # shellcheck disable=SC2016 # a workflow expression, matched literally
  printf '%s\n' "$block" | grep -qxF '          JIG_TEST_SHARD: ${{ matrix.shard }}' ||
    fail "the test job must run its own share: JIG_TEST_SHARD: \${{ matrix.shard }} in the Tests step"
  assert_eq 1 "$(printf '%s\n' "$block" | grep -c 'JIG_TEST_SHARD:')" \
    "the test job must set JIG_TEST_SHARD once, from the matrix"
}

# cw_test_matrix_keys — the keys directly under the test job's
# `strategy.matrix`, one per line; a matrix written inline on the `matrix:`
# line itself prints as `<inline>`, which no check below accepts.
cw_test_matrix_keys() {
  cw_job_block test | awk '
    /^      matrix:/ {
      rest = $0
      sub(/^      matrix:[ ]*/, "", rest)
      if (rest != "" && rest !~ /^#/) print "<inline>"
      f = 1
      next
    }
    f && /^[ ]*$/ { next }
    f && /^[ ]*#/ { next }
    f && !/^        / { exit }
    f && /^        [^ -]/ { k = $0; sub(/^ */, "", k); sub(/:.*/, "", k); print k }
  '
}

# The test matrix is its `include` list and nothing else. A base key beside it
# — `os: [ubuntu-latest, macos-latest]` — makes GitHub merge every entry into
# the combination with the same os, each overwriting the `shard` the one
# before it added: one job per platform runs the last share only, while the
# entries the checks above read still say 1/n .. n/n. `exclude` removes jobs
# the entries name.
test_ci_workflow_test_matrix_holds_only_include() {
  assert_eq "include" "$(cw_test_matrix_keys)" \
    "the test job's strategy.matrix must hold only include: another key beside it merges or removes the shares the include list names"
}
