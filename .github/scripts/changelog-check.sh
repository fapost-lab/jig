#!/usr/bin/env bash
# changelog-check.sh — refuse a pull request that releases a version the
# changelog does not describe. Run by the `changelog` job of
# .github/workflows/ci.yml, in the root of the checkout.
#
# The changelog (docs/changelog.mdx) is the page a user reads to learn what a
# release changed, and the only moment anyone knows what a version contains is
# the pull request that declares it. A rule asking the author to remember
# would be maintenance that depends on memory, which is the kind this
# repository automates instead (RULES.md, scope invariants).
#
# The question it asks is stateless — no diff against a base branch, no
# knowledge of which commit bumped what:
#
#   - JIG_VERSION already has a release tag on origin → nothing to describe
#     yet, exit 0. That is every pull request that leaves the version alone;
#   - the version is not major.minor.patch                → fail;
#   - docs/changelog.mdx is missing, or carries no `## <version>` heading for
#     the declared version                                → fail;
#   - otherwise                                           → exit 0.
#
# So the check turns itself on the moment a branch raises JIG_VERSION and
# turns itself off again once that version is released.
#
# Usage: .github/scripts/changelog-check.sh [--changelog <path>]
set -eu
set -o pipefail

CHANGELOG_REL="docs/changelog.mdx"

_changelog_die() { printf 'changelog-check: error: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
. "$LIB_DIR/common.sh"
# shellcheck source=release-lib.sh
. "$SCRIPT_DIR/release-lib.sh"

# changelog_has_entry <file> <version> — true when <file> carries a heading
# for <version>: a line `## <version>` with anything after it, so a date or a
# release title on the same line is fine. The version is quoted in the `case`
# pattern, so a heading is matched as text and never as a glob.
changelog_has_entry() {
  local file="$1" version="$2" line rest
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "## $version"*) ;;
      *) continue ;;
    esac
    rest=${line#"## $version"}
    # A heading for 0.1.0 must not satisfy a check for 0.1: what follows the
    # version is separator or nothing, never another digit or dot.
    case "$rest" in
      "" | [!0-9.]*) return 0 ;;
    esac
  done < "$file"
  return 1
}

main() {
  local changelog="" repo version remote_tags existing

  while [ $# -gt 0 ]; do
    case "$1" in
      --changelog)
        [ $# -ge 2 ] || _changelog_die "--changelog needs a path"
        changelog="$2"; shift 2 ;;
      *) _changelog_die "unknown argument: $1 (usage: changelog-check.sh [--changelog <path>])" ;;
    esac
  done

  # The repository being checked is the one the caller stands in, not the one
  # this script was read from: in CI they are the same checkout, in tests the
  # script is run against a fixture.
  repo=$(git rev-parse --show-toplevel 2>/dev/null) \
    || _changelog_die "not inside a git repository"
  [ -n "$changelog" ] || changelog="$repo/$CHANGELOG_REL"

  version=$(jig_declared_version "$repo") \
    || _changelog_die "cannot read a single JIG_VERSION=\"...\" line from scripts/lib/version.sh"
  jig_release_version "v$version" >/dev/null \
    || _changelog_die "JIG_VERSION $version is not major.minor.patch"

  # Tags come from the remote, not the checkout: actions/checkout fetches one
  # commit and no tags, and the remote is where a release exists.
  remote_tags=$(git -C "$repo" ls-remote --tags origin 2>/dev/null) \
    || _changelog_die "cannot list the tags of origin"

  if existing=$(release_existing_tag "$version" "$remote_tags"); then
    printf 'changelog-check: %s is already released, nothing to describe\n' "$existing"
    return 0
  fi

  [ -f "$changelog" ] \
    || _changelog_die "$CHANGELOG_REL is missing; this branch releases $version and the changelog describes every release"
  changelog_has_entry "$changelog" "$version" \
    || _changelog_die "$CHANGELOG_REL has no '## $version' section; add the entry for the release this branch declares"

  printf 'changelog-check: %s describes %s\n' "$CHANGELOG_REL" "$version"
}

main "$@"
