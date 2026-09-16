#!/usr/bin/env bash
# epic-pr-check.sh — gate a pull request from an epic branch into main
# (.ai/specs/epic-branches/spec.md, task task-base-and-epics). Run by the
# `epic-pr` job of .github/workflows/ci.yml, on the pull_request merge
# commit, in the root of the checkout.
#
# An epic branch (epic/<id>) collects a multi-phase feature and reaches
# `main` once, in one pull request that also raises JIG_VERSION. Two ways
# that final merge can go wrong without any other signal (spec.md,
# "Decisions", failure modes 6 and 7):
#
#   - the epic's JIG_VERSION was already released from `main` while the epic
#     was in flight (a patch release, or another epic finishing first). The
#     release job then finds its tag already there and exits 0, so this
#     merge would land a feature and tag nothing;
#   - the epic is merged before `jig spec epic <id> --finish` records it, so
#     `main` gains the feature's code while its roadmap still reads as work
#     in progress, with no task left open to say otherwise.
#
# This script fails the pull request in either case, before it can be merged:
#
#   - the head ref is missing or is not an epic branch  → fail;
#   - JIG_VERSION already has a release tag on origin    → fail;
#   - no roadmap marks the epic finished                → fail;
#   - otherwise                                          → exit 0.
#
# It never creates or pushes anything; release-tag.sh remains the only
# script that tags a release, on the push to `main` that follows this merge.
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
  local head_ref="" repo version remote_tags existing roadmap line norm found=0 epic_id

  if [ $# -eq 1 ] && [ -n "$1" ]; then
    head_ref="$1"
  else
    _epic_die "usage: epic-pr-check.sh <head-ref>"
  fi
  case "$head_ref" in
    epic/*) ;;
    *) _epic_die "head ref '$head_ref' does not start with epic/" ;;
  esac
  epic_id=${head_ref#epic/}

  repo=$(git rev-parse --show-toplevel 2>/dev/null) \
    || _epic_die "not inside a git repository"

  version=$(jig_declared_version "$repo") \
    || _epic_die "cannot read a single JIG_VERSION=\"...\" line from scripts/lib/version.sh"
  jig_release_version "v$version" >/dev/null \
    || _epic_die "JIG_VERSION $version is not major.minor.patch"

  # Tags come from the remote, not the checkout: actions/checkout fetches one
  # commit and no tags, and the remote is where a release has to exist.
  remote_tags=$(git -C "$repo" ls-remote --tags origin 2>/dev/null) \
    || _epic_die "cannot list the tags of origin"

  if existing=$(release_existing_tag "$version" "$remote_tags"); then
    _epic_die "JIG_VERSION $version is already released as $existing; raise the version on $head_ref before merging"
  fi

  # A roadmap marks its epic finished with a line "Epic: <ref> — finished"
  # (jig spec epic <id> --finish), written on the epic itself and carried to
  # `main` by this very pull request. Whitespace around the fields and the
  # dash spelling (—, -, --) vary by how the line was typed or re-wrapped;
  # the ref is matched as a literal string, never as a pattern, because a
  # spec id may contain a "." that a regex would read as "any character".
  for roadmap in "$repo"/.ai/specs/*/roadmap.md; do
    [ -e "$roadmap" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      norm=$(printf '%s' "$line" \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\{1,\}/ /g')
      if [ "$norm" = "Epic: $head_ref — finished" ] \
        || [ "$norm" = "Epic: $head_ref - finished" ] \
        || [ "$norm" = "Epic: $head_ref -- finished" ]; then
        found=1
        break
      fi
    done < "$roadmap"
    [ "$found" = 1 ] && break
  done

  [ "$found" = 1 ] \
    || _epic_die "no roadmap marks $head_ref finished; run 'jig spec epic $epic_id --finish' on the epic before merging"

  printf 'epic-pr-check: %s is finished and v%s is a new version\n' "$head_ref" "$version"
}

main "$@"
