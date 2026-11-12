#!/usr/bin/env bash
# epic-pr-check.sh — gate a pull request from an epic branch into main
# (ADR-0040). Run by the
# `epic-pr` job of .github/workflows/ci.yml, on the pull_request merge
# commit, in the root of the checkout.
#
# An epic branch (epic/<id>) collects a multi-phase feature and reaches
# `main` once, in one pull request. That pull request does not raise
# JIG_VERSION: a release is made apart from the features, by a short notes
# pull request from fresh main (jig-release; `jig spec ship` enforces it for
# a feature epic, and a release epic is the exception it knows). So this
# script no longer asks whether the version is new. One way the final merge
# can still go wrong without any other signal (spec.md, "Decisions", failure
# mode 7):
#
#   - the epic is merged before `jig spec epic <id> --finish` removes its
#     spec, so `main` gains the feature's code while a spec still declares the
#     epic open, with no task left to close it.
#
# This script fails the pull request in that case, before it can be merged:
#
#   - the head ref is missing or is neither epic/<id> nor finish/<id> → fail;
#   - JIG_VERSION is not major.minor.patch               → fail;
#   - a roadmap still declares the epic in an Epic: line → fail;
#   - otherwise                                          → exit 0.
#
# The version-format check stays: it is cheap and a malformed version breaks
# the release job later, far from its cause. Whether the version is released
# is deliberately not asked.
#
# It never creates or pushes anything; release-tag.sh remains the only
# script that tags a release.
#
# Usage: .github/scripts/epic-pr-check.sh <head-ref>
set -eu
set -o pipefail

_epic_die() { printf 'epic-pr-check: error: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
. "$LIB_DIR/common.sh"
# shellcheck source=release-lib.sh
. "$SCRIPT_DIR/release-lib.sh"

main() {
  local head_ref="" epic_ref repo version roadmap line norm found=0 epic_id

  if [ $# -eq 1 ] && [ -n "$1" ]; then
    head_ref="$1"
  else
    _epic_die "usage: epic-pr-check.sh <head-ref>"
  fi
  # The final pull request of an epic comes from the epic itself, or from the
  # `finish/<id>` branch `jig spec ship` cuts from it where the epic is
  # protected like main (ADR-0040 as amended 2026-10-04). The roadmap line
  # that must be gone names the epic either way.
  case "$head_ref" in
    epic/*) epic_ref=$head_ref ;;
    finish/*) epic_ref="epic/${head_ref#finish/}" ;;
    *) _epic_die "head ref '$head_ref' starts with neither epic/ nor finish/" ;;
  esac
  epic_id=${epic_ref#epic/}

  repo=$(git rev-parse --show-toplevel 2>/dev/null) \
    || _epic_die "not inside a git repository"

  version=$(jig_declared_version "$repo") \
    || _epic_die "cannot read a single JIG_VERSION=\"...\" line from scripts/lib/version.sh"
  jig_release_version "v$version" >/dev/null \
    || _epic_die "JIG_VERSION $version is not major.minor.patch"

  # `jig spec epic <id> --finish` removes the epic's spec on the epic itself,
  # and this very pull request carries the removal to `main` (ADR-0040 as
  # amended). A roadmap that still names the branch in an Epic: line — open,
  # or marked finished the way an older jig did — means the epic was not
  # finished. Whitespace and the dash spelling vary by how the line was typed;
  # the ref is matched as a literal string, never as a pattern, because a spec
  # id may contain a "." that a regex would read as "any character".
  for roadmap in "$repo"/.ai/specs/*/roadmap.md; do
    [ -e "$roadmap" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      norm=$(printf '%s' "$line" \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\{1,\}/ /g')
      if [ "$norm" = "Epic: $epic_ref" ] \
        || [ "$norm" = "Epic: $epic_ref — finished" ] \
        || [ "$norm" = "Epic: $epic_ref - finished" ] \
        || [ "$norm" = "Epic: $epic_ref -- finished" ]; then
        found=1
        break
      fi
    done < "$roadmap"
    if [ "$found" = 1 ]; then
      _epic_die "${roadmap#"$repo"/} still declares $epic_ref; run 'jig spec epic $epic_id --finish' on the epic before merging"
    fi
  done

  printf 'epic-pr-check: %s is finished\n' "$head_ref"
}

main "$@"
