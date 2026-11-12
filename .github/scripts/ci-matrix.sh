#!/usr/bin/env bash
# ci-matrix.sh — how many shares each platform's test job runs in
# (adr-20261110-a-pull-request-runs-the-tests-its-change-reaches). Run by the
# `scope` job of .github/workflows/ci.yml in the root of the checkout, after
# ci-scope.sh decided the suite.
#
# The number of shares follows the work, not a constant: the estimated time of
# the tests this run selects, on that platform, divided into shares of about
# CM_TARGET seconds, with a ceiling per platform. A full run of the suite
# reaches the ceilings — 4 Linux, 4 macOS and 10 Windows shares, which with
# the Windows smoke job is 19 of the 20 jobs the organisation may run at
# once, and 4 of its 5 macOS jobs. A pull request that reaches one test file
# gets one share a platform.
#
# The estimate is the sum of the tests' durations in the platform's table —
# the per-test reports of the last full run (tests/run.sh JIG_TEST_REPORT),
# `<rc>\t<secs>\t<file::test>` — divided by the runner's workers. A test the
# table does not know, or a platform with no table at all, costs the
# platform's average (CM_AVG_*, measured on the nightly run of 2026-11-09).
# The same table then partitions the tests (tests/run.sh JIG_TEST_DURATIONS),
# so the shares come out even; the count only has to be right on average.
#
# Usage: ci-matrix.sh <suite> <filters-file> <durations-dir>
#   <suite>          `all` or `selected`
#   <filters-file>   tests/run.sh filters, one per line (read when selected)
#   <durations-dir>  holds linux.tsv, macos.tsv, windows.tsv; any may be absent
#
# Prints two lines for $GITHUB_OUTPUT:
#   matrix_unix={"include":[{"os":"ubuntu-latest","shard":"1/2"},...]}
#   matrix_windows={"shard":["1/10",...]}
# and, on stderr, the estimate behind each count.
set -eu
set -o pipefail

CM_TARGET=360
# Workers per runner: tests/run.sh runs one test per CPU.
CM_CPUS_LINUX=4
CM_CPUS_MACOS=3
CM_CPUS_WINDOWS=4
# Seconds per test, in tenths, where no table answers.
CM_AVG_LINUX=16
CM_AVG_MACOS=25
CM_AVG_WINDOWS=140
CM_CAP_LINUX=4
CM_CAP_MACOS=4
CM_CAP_WINDOWS=10

_cm_die() {
  printf 'ci-matrix: %s\n' "$*" >&2
  exit 2
}

# _cm_tests — every test tests/run.sh would discover, as <file>::<function>,
# read from the text of tests/*.t.sh in the two forms the shell profile reads
# (`test_x()` and `function test_x`). A test defined some other way is missed
# here; that only skews the estimate, since tests/run.sh selects for itself.
_cm_tests() {
  local f base
  for f in tests/*.t.sh; do
    [ -f "$f" ] || continue
    base=${f#tests/}
    base=${base%.t.sh}
    sed -n -e "s/^[[:space:]]*\(test_[A-Za-z0-9_]*\)[[:space:]]*().*/$base::\1/p" \
      -e "s/^[[:space:]]*function[[:space:]][[:space:]]*\(test_[A-Za-z0-9_]*\).*/$base::\1/p" "$f"
  done
}

# _cm_selected <suite> <filters-file> — the tests this run selects.
_cm_selected() {
  if [ "$1" = all ]; then
    _cm_tests
    return 0
  fi
  _cm_tests | awk -v ff="$2" '
    BEGIN { while ((getline f < ff) > 0) if (f != "") filt[++n] = f }
    { for (i = 1; i <= n; i++) if (index($0, filt[i])) { print; break } }
  '
}

# _cm_shares <tests-file> <table> <avg-tenths> <cpus> <cap> <name> — the number
# of shares for one platform; the estimate goes to stderr.
_cm_shares() {
  local tests="$1" table="$2" avg="$3" cpus="$4" cap="$5" name="$6" out k n known wall
  [ -f "$table" ] || table=/dev/null
  # The table is read in BEGIN: an empty table read as the first file would
  # make FNR == NR true for the test list too.
  out=$(awk -F '\t' -v avg="$avg" -v cpus="$cpus" -v cap="$cap" -v target="$CM_TARGET" \
    -v table="$table" '
    BEGIN {
      while ((getline line < table) > 0) {
        sub(/\r$/, "", line)
        m = split(line, f, "\t")
        # The report form (rc, secs, name) and a plain (secs, name) form.
        if (m >= 3) { s = f[2]; t = f[3] } else if (m == 2) { s = f[1]; t = f[2] } else continue
        if (s !~ /^[0-9]+$/ || t == "") continue
        if (!(t in d) || s + 0 > d[t]) d[t] = s + 0
      }
    }
    $0 != "" {
      n++
      # Whole seconds round most tests down to 0; half a second is their
      # expected share of the rounding.
      if ($0 in d) { tenths += d[$0] * 10 + 5; known++ } else tenths += avg
    }
    END {
      wall = tenths / 10 / cpus
      k = int((wall + target - 1) / target)
      if (k < 1) k = 1
      if (k > cap) k = cap
      printf "%d %d %d %d\n", k, n, known, wall
    }
  ' "$tests")
  read -r k n known wall <<EOF
$out
EOF
  printf 'ci-matrix: %s: %s tests (%s timed), ~%ss of work at %s workers -> %s share(s)\n' \
    "$name" "$n" "$known" "$wall" "$cpus" "$k" >&2
  printf '%s\n' "$k"
}

# _cm_list <n> <os|-> — n shares as JSON objects (with an os) or strings.
_cm_list() {
  local n="$1" os="$2" i=1 sep=""
  while [ "$i" -le "$n" ]; do
    if [ "$os" = - ]; then
      printf '%s"%s/%s"' "$sep" "$i" "$n"
    else
      printf '%s{"os":"%s","shard":"%s/%s"}' "$sep" "$os" "$i" "$n"
    fi
    sep=","
    i=$((i + 1))
  done
}

main() {
  local suite="${1:-}" filters="${2:-}" dir="${3:-}" tests linux macos windows
  [ $# -eq 3 ] || _cm_die "usage: ci-matrix.sh <suite> <filters-file> <durations-dir>"
  case "$suite" in
    all) ;;
    selected) [ -s "$filters" ] || _cm_die "a selected suite needs a non-empty filters file" ;;
    *) _cm_die "suite must be all or selected: $suite" ;;
  esac

  tests=$(mktemp "${TMPDIR:-/tmp}/ci-matrix-tests.XXXXXX")
  CM_TMP="$tests"
  trap 'rm -f "$CM_TMP"' EXIT
  _cm_selected "$suite" "$filters" > "$tests"
  # Nothing found is a test this reading does not recognise, not an empty
  # run: tests/run.sh refuses a filter that selects nothing. One share each.
  [ -s "$tests" ] || printf 'ci-matrix: no test recognised for the selection; one share each\n' >&2

  linux=$(_cm_shares "$tests" "$dir/linux.tsv" "$CM_AVG_LINUX" "$CM_CPUS_LINUX" "$CM_CAP_LINUX" linux)
  macos=$(_cm_shares "$tests" "$dir/macos.tsv" "$CM_AVG_MACOS" "$CM_CPUS_MACOS" "$CM_CAP_MACOS" macos)
  windows=$(_cm_shares "$tests" "$dir/windows.tsv" "$CM_AVG_WINDOWS" "$CM_CPUS_WINDOWS" "$CM_CAP_WINDOWS" windows)

  printf 'matrix_unix={"include":[%s,%s]}\n' \
    "$(_cm_list "$linux" ubuntu-latest)" "$(_cm_list "$macos" macos-latest)"
  printf 'matrix_windows={"shard":[%s]}\n' "$(_cm_list "$windows" -)"
}

CM_TMP=""
main "$@"
