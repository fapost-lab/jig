#!/usr/bin/env bash
# ci-run-tests.sh — the `Tests` step of the test jobs in
# .github/workflows/ci.yml, on every platform: one share of the suite, as the
# `scope` job planned it (adr-20261110-a-pull-request-runs-the-tests-its-change-reaches).
#
# Reads the `plan` artifact, downloaded to $RUNNER_TEMP/plan:
#   filters               tests/run.sh filters, one per line; read when SUITE
#                         is `selected`, so a selected run is never the whole
#                         suite by accident and never nothing
#   durations/<os>.tsv    per-test durations of this platform, handed to the
#                         runner (JIG_TEST_DURATIONS) to divide the shares
#                         evenly; absent or empty, it divides by round-robin
# and writes this share's per-test report to $RUNNER_TEMP/report/report.tsv
# (JIG_TEST_REPORT), which the job keeps as an artifact: the nightly run's
# reports are the next plan's durations.
#
# Environment: SUITE (`all` or `selected`), JIG_TEST_SHARD, RUNNER_TEMP and
# RUNNER_OS (set by Actions), and whatever else tests/run.sh reads
# (JIG_TEST_SKIP). Exits as tests/run.sh exits.
set -eu
set -o pipefail

_rt_die() {
  printf 'ci-run-tests: %s\n' "$*" >&2
  exit 2
}

main() {
  local tmp os plan filters f
  tmp="${RUNNER_TEMP:-}"
  [ -n "$tmp" ] || _rt_die "RUNNER_TEMP is not set"
  # Git Bash gets D:\a\_temp; the runner and its tools want a POSIX path.
  if command -v cygpath >/dev/null 2>&1; then
    tmp=$(cygpath -u "$tmp")
  fi
  case "${RUNNER_OS:-}" in
    Linux) os=linux ;;
    macOS) os=macos ;;
    Windows) os=windows ;;
    *) _rt_die "unknown RUNNER_OS: ${RUNNER_OS:-}" ;;
  esac
  plan="$tmp/plan"
  mkdir -p "$tmp/report"
  export JIG_TEST_REPORT="$tmp/report/report.tsv"
  if [ -s "$plan/durations/$os.tsv" ]; then
    export JIG_TEST_DURATIONS="$plan/durations/$os.tsv"
  fi

  set --
  case "${SUITE:-}" in
    all) ;;
    selected)
      filters="$plan/filters"
      [ -s "$filters" ] || _rt_die "a selected suite without filters in $filters"
      while IFS= read -r f; do
        f=${f%$'\r'}
        [ -z "$f" ] || set -- "$@" "$f"
      done < "$filters"
      [ $# -gt 0 ] || _rt_die "a selected suite without filters in $filters"
      ;;
    *) _rt_die "SUITE must be all or selected: ${SUITE:-}" ;;
  esac
  echo "ci-run-tests: suite ${SUITE}, share ${JIG_TEST_SHARD:-1/1}, filters: ${*:-none}"
  exec tests/run.sh "$@"
}

main "$@"
