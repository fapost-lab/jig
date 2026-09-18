#!/usr/bin/env bash
# ci-scope.sh — decide how much of CI a change needs (ADR-0041 as amended).
# Run by the `scope` job of .github/workflows/ci.yml in the root of the
# checkout, with the commit the change is measured from: a pull request's
# base, or for a push the commit of the last successful run on the branch.
#
# Prints one line, `full` or `light`, and why:
#
#   - light: every changed path affects no test — the project map
#     (.ai/verify/shell.map, the one `jig verify` reads) decides it `-`, or
#     the map names no line for it and it is documentation (*.md, docs/,
#     .ai/knowledge/, .ai/specs/). CI then checks the knowledge only;
#   - full: anything else, and every case where the change cannot be measured —
#     no base, a base of zeros (a new branch), a base not in the history, a
#     failing diff, an empty change, a map that does not parse.
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

_scope() {
  printf '%s (%s)\n' "$1" "$2"
  exit 0
}

main() {
  local base="${1:-}" files mapped path decision
  [ $# -le 1 ] || { printf 'usage: ci-scope.sh <base-commit>\n' >&2; exit 2; }

  case "$base" in
    '') _scope full "no base commit" ;;
    *[!0]*) ;;
    *) _scope full "new branch, nothing to compare with" ;;
  esac
  git cat-file -e "$base^{commit}" 2>/dev/null || _scope full "base $base is not in the history"

  files=$(mktemp "${TMPDIR:-/tmp}/ci-scope-files.XXXXXX")
  mapped=$(mktemp "${TMPDIR:-/tmp}/ci-scope-mapped.XXXXXX")
  trap 'rm -f "$files" "$mapped"' EXIT

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
    esac
    case "$decision" in
      -) continue ;;
      '?')
        case "$path" in
          *.md | docs/* | .ai/knowledge/* | .ai/specs/*) continue ;;
        esac
        _scope full "$path may affect tests"
        ;;
      *) _scope full "$path maps to $decision" ;;
    esac
  done < "$mapped"

  _scope light "$(wc -l < "$files" | tr -d ' ') changed files affect no test"
}

main "$@"
