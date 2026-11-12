#!/usr/bin/env bash
# ci-scope.sh — decide how much of CI a change needs (ADR-0041 as amended).
# Run by the `scope` job of .github/workflows/ci.yml in the root of the
# checkout, with the commit the change is measured from: for a pull request the
# first parent of the merge commit CI checks out — its base branch as it is now,
# not where the branch started — or for a push the commit of the last
# successful run on the branch.
#
# Prints one line, `full`, `selected` or `light`, and why:
#
#   - light: every changed path affects no test — the project map
#     (.ai/verify/shell.map, the one `jig verify` reads) decides it `-`, or
#     the map names no line for it and it is documentation (*.md, docs/,
#     .ai/knowledge/, .ai/specs/). CI then checks the knowledge only;
#   - selected: the change reaches some tests and the shell profile can name
#     them all (adr-20261110-a-pull-request-runs-the-tests-its-change-reaches).
#     The line ends in the tests/run.sh filters; with CI_SCOPE_FILTERS set
#     they are also written to that file, one per line;
#   - full: anything else, and every case where the change cannot be measured —
#     no base, a base of zeros (a new branch), a base not in the history, a
#     failing diff, an empty change, a map that does not parse.
#
# The tests are named by the shell profile itself, through the explain
# protocol `jig verify --explain` uses (adr-20260925-verify-explain-plans),
# with the inputs `jig verify` gives it — but without `verify.full_run: ci`:
# locally that setting defers an ALL to CI, and CI is where it was deferred
# to. Any ALL is therefore `full`, and so is a plan this script cannot read.
# Some paths are `full` whatever the map and the profile say: anything under
# .github/, the test harness (tests/run.sh, tests/lib/), what decides the
# selection itself (the map, the shell profile, scripts/lib/verify.sh and
# profile.sh — a change there would otherwise choose its own tests and those
# of every pull request after it), and a change of JIG_VERSION, because a
# release is tested whole.
#
# A selection always includes CI_KNOWLEDGE_TEST, the check of this
# repository's own knowledge: a `full` run ran it, the `knowledge` job runs
# only on a light one, and a change to code can break a document's `paths`.
#
# Documentation for a path the map does not name is a subset of the shell
# profile's own rules: where the two disagree, this script runs more, never
# less. A path under .github/ is always full: a change to CI is checked by
# CI, whatever the map says for local runs.
#
# It lives under .github/ rather than scripts/ because `jig init` copies
# scripts/ into every project, and this is this repository's CI only.
#
# Usage: .github/scripts/ci-scope.sh <base-commit>
set -eu
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_LIB="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"
# shellcheck source=../../scripts/lib/verify.sh
. "$CI_LIB/verify.sh"

MAP=".ai/verify/shell.map"
CI_PROFILE="$SCRIPT_DIR/../../profiles/shell/verify.sh"
CI_KNOWLEDGE_TEST="knowledge::test_real_repository_knowledge_passes_with_no_failures"
# Temporary files, removed by the EXIT trap; script-global for that reason.
CI_SCOPE_TMP=""
CI_SCOPE_BASE=""

_scope() {
  printf '%s (%s)\n' "$1" "$2"
  exit 0
}

# _select <files> <mapped> <all> — the shell profile's plan for tests/run.sh,
# as filters one per line on stdout; status 1 when the plan is a full set,
# names no test, or cannot be read. <all> is a scratch file of main's (this
# runs in a subshell, where a registration for the EXIT trap would be lost).
# Runs in the root of the checkout, as `jig verify` runs a profile.
_select() {
  local files="$1" mapped="$2" all="$3" plan line l filters
  [ -f "$CI_PROFILE" ] || return 1
  # Every tracked file a changed function may be called from, decided by the
  # map as `jig verify` decides them (scripts/lib/verify.sh).
  { git ls-files -co --exclude-standard \
      | grep -v -e '^tests/' -e '^docs/' -e '\.mdx\{0,1\}$' || true; } > "$all.list"
  if [ -f "$MAP" ]; then
    _verify_map_apply "$MAP" "$all.list" > "$all"
  else
    : > "$all"
  fi
  plan=$(JIG_VERIFY_EXPLAIN=1 JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$files" \
    JIG_VERIFY_BASE="$CI_SCOPE_BASE" JIG_VERIFY_FULL_RUN=local \
    JIG_VERIFY_MAPPED="$mapped" JIG_VERIFY_MAPPED_ALL="$all" \
    bash "$CI_PROFILE" 2>/dev/null) || return 1
  line=""
  while IFS= read -r l; do
    case "$l" in "PLAN shell: tests/run.sh: "*) line=$l ;; esac
  done <<EOF
$plan
EOF
  case "$line" in
    "PLAN shell: tests/run.sh: filtered (test filters: "*")") ;;
    *) return 1 ;;
  esac
  filters=${line#"PLAN shell: tests/run.sh: filtered (test filters: "}
  filters=${filters%)}
  [ -n "$filters" ] || return 1
  # A filter is a test name or a prefix of one; anything else is a plan this
  # script does not understand.
  case "$filters" in *[!A-Za-z0-9_:,.-]*) return 1 ;; esac
  { printf '%s\n' "$filters" | tr ',' '\n'; printf '%s\n' "$CI_KNOWLEDGE_TEST"; } \
    | sed '/^$/d' | LC_ALL=C sort -u
}

# _version_changed <base> — whether the change sets another JIG_VERSION.
# A diff that cannot be read counts as a change: the answer is then `full`.
_version_changed() {
  local diff
  diff=$(git diff "$1" HEAD -- scripts/lib/version.sh 2>/dev/null) || return 0
  case "$diff" in *$'\n'[-+]JIG_VERSION=*) return 0 ;; esac
  return 1
}

main() {
  local base="${1:-}" files mapped all path decision why="" filters
  [ $# -le 1 ] || { printf 'usage: ci-scope.sh <base-commit>\n' >&2; exit 2; }

  case "$base" in
    '') _scope full "no base commit" ;;
    *[!0]*) ;;
    *) _scope full "new branch, nothing to compare with" ;;
  esac
  git cat-file -e "$base^{commit}" 2>/dev/null || _scope full "base $base is not in the history"

  files=$(mktemp "${TMPDIR:-/tmp}/ci-scope-files.XXXXXX")
  mapped=$(mktemp "${TMPDIR:-/tmp}/ci-scope-mapped.XXXXXX")
  all=$(mktemp "${TMPDIR:-/tmp}/ci-scope-all.XXXXXX")
  CI_SCOPE_TMP="$files $mapped $all $all.list"
  CI_SCOPE_BASE="$base"
  # shellcheck disable=SC2086 # a list of mktemp paths, split on purpose
  trap 'rm -f $CI_SCOPE_TMP' EXIT

  git diff --name-only "$base" HEAD > "$files" 2>/dev/null || _scope full "cannot diff $base"
  [ -s "$files" ] || _scope full "no changed files"

  if [ -f "$MAP" ]; then
    _verify_map_check "$MAP" > /dev/null 2>&1 || _scope full "$MAP does not parse"
    _verify_map_apply "$MAP" "$files" > "$mapped"
  else
    while IFS= read -r path; do
      printf '%s\t?\n' "$path"
    done < "$files" > "$mapped"
  fi

  while IFS="$(printf '\t')" read -r path decision; do
    [ -n "$path" ] || continue
    case "$path" in
      .github/*) _scope full "$path changes CI" ;;
      tests/run.sh | tests/lib/*) _scope full "$path changes the test harness" ;;
      .ai/verify/* | profiles/shell/* | scripts/lib/verify.sh | scripts/lib/profile.sh)
        _scope full "$path decides which tests run"
        ;;
    esac
    case "$decision" in
      -) continue ;;
      '?')
        case "$path" in
          *.md | docs/* | .ai/knowledge/* | .ai/specs/*) continue ;;
        esac
        [ -n "$why" ] || why="$path may affect tests"
        ;;
      *) [ -n "$why" ] || why="$path maps to $decision" ;;
    esac
  done < "$mapped"

  [ -n "$why" ] || _scope light "$(wc -l < "$files" | tr -d ' ') changed files affect no test"
  ! _version_changed "$base" || _scope full "JIG_VERSION changes; a release is tested whole"
  filters=$(_select "$files" "$mapped" "$all") || _scope full "$why"
  if [ -n "${CI_SCOPE_FILTERS:-}" ]; then
    printf '%s\n' "$filters" > "$CI_SCOPE_FILTERS"
  fi
  _scope selected "$why; tests: $(printf '%s\n' "$filters" | paste -sd' ' -)"
}

main "$@"
