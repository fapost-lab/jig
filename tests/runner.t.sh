# Tests for tests/run.sh itself: JIG_TEST_SHARD and JIG_TEST_SKIP (README.md,
# .github/workflows/ci.yml windows share).
#
# Each test builds a throwaway copy of the runner under ./root/tests/ (the
# real tests/run.sh and tests/lib/, a stub scripts/jig) and a couple of tiny
# *.t.sh fixture files, then invokes the copy with `env -u JIG_TEST_SHARD -u
# JIG_TEST_SKIP` plus whatever the test under it needs — never inheriting
# this outer run's own JIG_TEST_SHARD/JIG_TEST_SKIP (CI sets both on the
# Windows share). Every run below forces JIG_TEST_JOBS=1: the parallel path
# builds a fixture cache through a real `jig init`, which the stub does not
# implement, and these tests are about sharding/skip, not about jig init.
# shellcheck shell=bash

# rn_build_suite — a copy of the real runner and its assertion library under
# ./root/tests/, plus a scripts/jig stub that always exits 0. The stub is
# enough for fixture_cache_prepare's `jig init --from ...` too, which is why
# a JIG_TEST_JOBS=2 run does not need the real framework (see the jobs=2 test
# below).
rn_build_suite() {
  mkdir -p root/tests/lib root/scripts
  cp "$JIG_HOME/tests/run.sh" root/tests/run.sh
  chmod +x root/tests/run.sh
  cp -R "$JIG_HOME/tests/lib/." root/tests/lib/
  cat > root/scripts/jig <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x root/scripts/jig
}

# rn_write_ab_fixture — two files, seven trivial passing tests, discovered in
# this exact order (files alphabetically, test_* functions alphabetically
# within a file — bash's `declare -F` order):
#
#   1 a::test_1_drop   2 a::test_2_keep   3 a::test_3_drop   4 a::test_4_keep
#   5 b::test_1_keep    6 b::test_2_drop    7 b::test_3_keep
#
# The "_keep"/"_drop" suffixes exist so a single, unambiguous name filter
# ("keep") selects exactly {2, 4, 5, 7} — a non-contiguous subset spanning
# both files — to prove a shard position is counted after the filter runs,
# not before it.
rn_write_ab_fixture() {
  cat > root/tests/a.t.sh <<'EOF'
# shellcheck shell=bash
test_1_drop() { :; }
test_2_keep() { :; }
test_3_drop() { :; }
test_4_keep() { :; }
EOF
  cat > root/tests/b.t.sh <<'EOF'
# shellcheck shell=bash
test_1_keep() { :; }
test_2_drop() { :; }
test_3_keep() { :; }
EOF
}

# rn_write_c_fixture — one file, three tests, the middle one failing on
# purpose (for the skip-covers-a-failure and unknown-name-ignored tests).
rn_write_c_fixture() {
  cat > root/tests/c.t.sh <<'EOF'
# shellcheck shell=bash
test_1_ok() { :; }
test_2_bad() { fail "boom"; }
test_3_ok() { :; }
EOF
}

# rn_run <shard> <skip> [filter] — invoke the copied runner with JIG_TEST_JOBS
# forced to 1 and JIG_TEST_SHARD/JIG_TEST_SKIP cleared, then set back only to
# the non-empty values given. Leaves OUT/RC set (assert.sh's run()).
rn_run() {
  local shard="$1" skip="$2" filter="${3:-}"
  local -a envargs=(-u JIG_TEST_SHARD -u JIG_TEST_SKIP JIG_TEST_JOBS=1)
  [ -z "$shard" ] || envargs+=("JIG_TEST_SHARD=$shard")
  [ -z "$skip" ] || envargs+=("JIG_TEST_SKIP=$skip")
  run env "${envargs[@]}" "$PWD/root/tests/run.sh" "$filter"
}

# rn_names <output> — the full names the runner reported ok/FAIL/skip for, in
# the order it printed them. Anchored on the line's own verdict word so the
# "slowest:" section (which also prints full names) is never picked up.
rn_names() {
  printf '%s\n' "$1" | grep -E '^(ok|FAIL|skip) ' | awk '{print $2}'
}

# --- JIG_TEST_SHARD ------------------------------------------------------

test_runner_shard_shares_partition_the_suite() {
  rn_build_suite
  rn_write_ab_fixture

  rn_run "" "" ""
  local full share1 share2 share3
  full=$(rn_names "$OUT" | sort)
  assert_eq 7 "$(printf '%s\n' "$full" | grep -c .)" "full suite size"

  rn_run "1/3" "" ""
  share1=$(rn_names "$OUT")
  rn_run "2/3" "" ""
  share2=$(rn_names "$OUT")
  rn_run "3/3" "" ""
  share3=$(rn_names "$OUT")

  assert_eq "$(printf 'a::test_1_drop\na::test_4_keep\nb::test_3_keep')" "$share1" "share 1/3"
  assert_eq "$(printf 'a::test_2_keep\nb::test_1_keep')" "$share2" "share 2/3"
  assert_eq "$(printf 'a::test_3_drop\nb::test_2_drop')" "$share3" "share 3/3"

  local union dup
  union=$(printf '%s\n%s\n%s\n' "$share1" "$share2" "$share3" | sort)
  assert_eq "$full" "$union" "the shares union to the whole list"
  dup=$(printf '%s\n%s\n%s\n' "$share1" "$share2" "$share3" | sort | uniq -d)
  assert_eq "" "$dup" "the shares are pairwise disjoint"
}

test_runner_shard_counts_positions_after_name_filter() {
  rn_build_suite
  rn_write_ab_fixture

  # Filtered to "*keep*", the discovery order becomes:
  #   1 a::test_2_keep   2 a::test_4_keep   3 b::test_1_keep   4 b::test_3_keep
  # A shard computed from the *unfiltered* positions (2, 4, 5, 7) would give a
  # different split, so this also pins down that the filter runs first.
  rn_run "1/2" "" "keep"
  assert_eq "$(printf 'a::test_2_keep\nb::test_1_keep')" "$(rn_names "$OUT")" "1/2 of the filtered list"

  rn_run "2/2" "" "keep"
  assert_eq "$(printf 'a::test_4_keep\nb::test_3_keep')" "$(rn_names "$OUT")" "2/2 of the filtered list"
}

test_runner_shard_unset_or_1_of_1_runs_everything() {
  rn_build_suite
  rn_write_ab_fixture

  rn_run "" "" ""
  local unset_all
  unset_all=$(rn_names "$OUT" | sort)
  assert_eq 7 "$(printf '%s\n' "$unset_all" | grep -c .)" "unset JIG_TEST_SHARD runs everything"

  rn_run "1/1" "" ""
  assert_eq "$unset_all" "$(rn_names "$OUT" | sort)" "1/1 matches unset"
}

test_runner_shard_rejects_invalid_values() {
  rn_build_suite
  rn_write_ab_fixture

  local bad
  for bad in 0/2 3/2 2 a/b 1/0 1/2/3 /2 1/ 01/2; do
    rn_run "$bad" "" ""
    assert_eq 2 "$RC" "JIG_TEST_SHARD=$bad should exit 2"
    assert_contains "$OUT" \
      "tests/run.sh: JIG_TEST_SHARD must be <i>/<n> with 1 <= i <= n: $bad" \
      "message for JIG_TEST_SHARD=$bad"
  done
}

# --- JIG_TEST_SKIP ---------------------------------------------------------

test_runner_skip_list_reports_and_counts_skipped() {
  rn_build_suite
  rn_write_ab_fixture

  rn_run "" "b::test_2_drop" ""
  assert_eq 0 "$RC" "an all-passing suite with one test skipped still exits 0"
  assert_contains "$OUT" "skip b::test_2_drop (JIG_TEST_SKIP)"
  assert_contains "$OUT" "6 passed, 0 failed, 1 skipped"
}

test_runner_skip_list_covers_a_failing_test() {
  rn_build_suite
  rn_write_c_fixture

  rn_run "" "c::test_2_bad" ""
  assert_eq 0 "$RC" "a failing test in the skip list must not fail the run"
  assert_contains "$OUT" "skip c::test_2_bad (JIG_TEST_SKIP)"
  assert_contains "$OUT" "2 passed, 0 failed, 1 skipped"
}

test_runner_skip_list_ignores_unknown_names() {
  rn_build_suite
  rn_write_c_fixture

  rn_run "" "c::test_missing,other::nope" ""
  assert_eq 1 "$RC" "an unmatched skip name must not swallow the real failure"
  assert_not_contains "$OUT" "JIG_TEST_SKIP"
  assert_contains "$OUT" "FAIL c::test_2_bad"
  assert_contains "$OUT" "2 passed, 1 failed, 0 skipped"
}

test_runner_skip_combined_with_shard() {
  rn_build_suite
  rn_write_ab_fixture

  # Shard 2/3 of the seven-test suite keeps only a::test_2_keep and
  # b::test_1_keep (see the shares test above); skip one of those two.
  rn_run "2/3" "a::test_2_keep" ""
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip a::test_2_keep (JIG_TEST_SKIP)"
  assert_contains "$OUT" "1 passed, 0 failed, 1 skipped"
  assert_not_contains "$OUT" "test_3_drop"
  assert_not_contains "$OUT" "test_4_keep"
}

# --- parallel path (JIG_TEST_JOBS=2) ---------------------------------------

# The scripts/jig stub always exits 0, which is enough for
# fixture_cache_prepare's `jig init --from ...`, so the parallel path builds
# its cache without needing the real framework. Confirms sharding and the
# skip list both still apply once tests run out of discovery order.
test_runner_shard_and_skip_still_apply_with_two_jobs() {
  rn_build_suite
  rn_write_ab_fixture

  run env -u JIG_TEST_SHARD -u JIG_TEST_SKIP JIG_TEST_JOBS=2 \
    JIG_TEST_SHARD=1/3 JIG_TEST_SKIP=a::test_4_keep \
    "$PWD/root/tests/run.sh"
  assert_eq 0 "$RC"
  local names
  names=$(rn_names "$OUT" | sort)
  # Share 1/3 is {a::test_1_drop, a::test_4_keep, b::test_3_keep} (see the
  # shares test above); all three still get a verdict line, one of them a
  # skip rather than an ok (rn_names captures skip lines too).
  assert_eq "$(printf 'a::test_1_drop\na::test_4_keep\nb::test_3_keep')" "$names"
  assert_contains "$OUT" "skip a::test_4_keep (JIG_TEST_SKIP)"
  assert_contains "$OUT" "2 passed, 0 failed, 1 skipped"
}

# --- not completed (a killed test is a third outcome) -----------------------
# adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass: a test
# killed by a signal is neither a pass nor a failure. bash reports a child
# that died on signal N as 128+N. Each test execs a fresh `sh` to kill: a
# test function runs inside run_test's own `( ... )` subshell, and bash's
# `$$` there still names the *original* shell process (unlike `$BASHPID`,
# not available in bash 3.2), so a plain `kill -9 $$` would reach for the
# outer runner instead of the one process under test.

rn_write_killed_fixture() {
  cat > root/tests/d.t.sh <<'EOF'
# shellcheck shell=bash
test_1_dies() { exec sh -c 'kill -9 $$'; }
EOF
}

rn_write_fail_and_kill_fixture() {
  cat > root/tests/e.t.sh <<'EOF'
# shellcheck shell=bash
test_1_bad() { fail "boom"; }
test_2_dies() { exec sh -c 'kill -9 $$'; }
EOF
}

test_runner_killed_test_is_reported_as_not_completed() {
  rn_build_suite
  rn_write_killed_fixture

  rn_run "" "" ""
  assert_eq 3 "$RC"
  assert_contains "$OUT" "KILLED d::test_1_dies (signal 9)"
  assert_contains "$OUT" "NOT COMPLETED d::test_1_dies (killed by signal 9)"
  assert_contains "$OUT" "0 passed, 0 failed, 0 skipped, 1 not completed"
  assert_contains "$OUT" \
    "tests/run.sh: the run did not finish, so it neither passed nor failed"
}

test_runner_not_completed_outranks_failed() {
  rn_build_suite
  rn_write_fail_and_kill_fixture

  rn_run "" "" ""
  assert_eq 3 "$RC"
  assert_contains "$OUT" "FAIL e::test_1_bad"
  assert_contains "$OUT" "NOT COMPLETED e::test_2_dies (killed by signal 9)"
  assert_contains "$OUT" "0 passed, 1 failed, 0 skipped, 1 not completed"
}

test_runner_ordinary_summary_names_zero_not_completed() {
  rn_build_suite
  rn_write_ab_fixture

  rn_run "" "" ""
  assert_eq 0 "$RC"
  assert_contains "$OUT" "7 passed, 0 failed, 0 skipped, 0 not completed"
}

test_runner_failure_only_summary_still_exits_1() {
  rn_build_suite
  rn_write_c_fixture

  rn_run "" "" ""
  assert_eq 1 "$RC"
  assert_contains "$OUT" "2 passed, 1 failed, 0 skipped, 0 not completed"
}
