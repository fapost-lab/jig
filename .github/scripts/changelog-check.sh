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
#   - the repository installs Jig from itself (`.ai/manifest` names
#     `jig.source: .`) and the manifest records another version → fail:
#     the release's own pull request runs `jig upgrade`, so the repository
#     is on the release the moment it exists, not one pull request later;
#   - the release notes do not describe all of the base the branch will land
#     on (`--base <ref>`, default origin/main): no commit of the branch names
#     the base commit the notes describe in a Release-Notes-Through: trailer,
#     or the base has commits after it → fail. A release whose notes missed
#     what reached main in the meantime would tag a version whose changelog
#     is silent about part of it (jig_release_notes_gap, scripts/lib/common.sh);
#   - otherwise                                           → exit 0.
#
# The base check runs only for a release; a version already tagged reads
# neither the changelog nor the base. GitHub does not re-run it when the
# base moves unless strict status checks are on, so the pull request that
# is merged is also checked by `jig task ship`/`jig spec ship` against the
# freshest base right before they merge.
#
# So the check turns itself on the moment a branch raises JIG_VERSION and
# turns itself off again once that version is released.
#
# Usage: .github/scripts/changelog-check.sh [--changelog <path>] [--base <ref>]
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
  local changelog="" base="origin/main" repo version remote_tags existing gap

  while [ $# -gt 0 ]; do
    case "$1" in
      --changelog)
        [ $# -ge 2 ] || _changelog_die "--changelog needs a path"
        changelog="$2"; shift 2 ;;
      --base)
        [ $# -ge 2 ] || _changelog_die "--base needs a ref"
        base="$2"; shift 2 ;;
      *) _changelog_die "unknown argument: $1 (usage: changelog-check.sh [--changelog <path>] [--base <ref>])" ;;
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

  manifest_matches "$repo" "$version" \
    || _changelog_die ".ai/manifest records jig.version $(manifest_value "$repo/.ai/manifest" jig.version) while this branch releases $version; run jig upgrade in this branch so this repository records the release it makes"

  # The notes must describe all of the base — the default branch only. A
  # release epic's notes task opens its pull request into the epic: its notes
  # name a commit of main, the epic's own commits come after it, and the
  # question belongs to the epic's final pull request into main.
  if [ "$base" != "origin/main" ]; then
    printf 'changelog-check: %s describes %s; the notes are checked against main when the release reaches it, not against %s\n' \
      "$CHANGELOG_REL" "$version" "$base"
    return 0
  fi
  # The library reads JIG_PROJECT.
  JIG_PROJECT="$repo"
  export JIG_PROJECT
  git -C "$repo" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 \
    || _changelog_die "cannot resolve the base '$base'; the checkout needs its history (fetch-depth: 0) and the base branch"
  gap=$(jig_release_notes_gap "$base")
  [ -z "$gap" ] \
    || _changelog_die "the release notes do not describe all of $base: $gap"

  printf 'changelog-check: %s describes %s\n' "$CHANGELOG_REL" "$version"
}

# manifest_value <file> <key> — the value of a `key: value` header line.
manifest_value() {
  sed -n "s/^$2: *//p" "$1" | head -n 1
}

# manifest_matches <repo> <version> — true unless <repo> installs Jig from
# itself (`jig.source: .`) and its manifest records a version other than
# <version>. Any other project, or none, has nothing to say here.
manifest_matches() {
  local file="$1/.ai/manifest"
  [ -f "$file" ] || return 0
  [ "$(manifest_value "$file" jig.source)" = "." ] || return 0
  [ "$(manifest_value "$file" jig.version)" = "$2" ]
}

main "$@"
