#!/usr/bin/env bash
# release-tag.sh — tag a Jig release when JIG_VERSION is new (ADR-0033; task
# release-v0.1.0). Run by the `release` job of .github/workflows/ci.yml after
# the tests passed on a push to main, in the root of the checkout to tag.
#
# A release is an annotated tag v<JIG_VERSION> on a commit that declares that
# version. This script is the one place that decides whether to create it:
#
#   - a release of this version already exists → nothing to do, exit 0. That
#     is every merge that did not bump the version, wherever the tag points.
#     "This version" is compared as numbers, so a v01.0.0 left by hand counts
#     as v1.0.0 and no second tag for the same release is ever made;
#   - the version is not major.minor.patch written without leading zeros, or
#     lower than the newest release    → fail, no tag;
#   - otherwise                          → create the tag on HEAD and push it.
#     A rejected push fails; an existing tag is never moved or deleted.
#
# It lives under .github/ rather than scripts/ because `jig init` copies
# scripts/ into every project, and releasing is this repository's business
# only. The release rules are the ones the installer and `jig self-update`
# use, sourced from scripts/lib/common.sh rather than copied.
#
# Usage: .github/scripts/release-tag.sh [--dry-run]
set -eu
set -o pipefail

_release_die() { printf 'release: error: %s\n' "$*" >&2; exit 1; }

RELEASE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
. "$RELEASE_LIB/common.sh"

main() {
  local dry=0 repo version tag remote_tags newest newest_version head
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1; shift ;;
      *) _release_die "unknown argument: $1 (usage: release-tag.sh [--dry-run])" ;;
    esac
  done

  # The repository being tagged is the one the caller stands in, not the one
  # this script was read from: in CI they are the same checkout, in tests the
  # script is run against a fixture.
  repo=$(git rev-parse --show-toplevel 2>/dev/null) \
    || _release_die "not inside a git repository"

  version=$(jig_declared_version "$repo") \
    || _release_die "cannot read a single JIG_VERSION=\"...\" line from scripts/lib/version.sh"
  jig_release_version "v$version" >/dev/null \
    || _release_die "JIG_VERSION $version is not major.minor.patch"
  # The shared helpers read 01.0.0 as 1.0.0, which is right for comparing and
  # wrong for naming: a tag v01.0.0 beside v1.0.0 would be two tags for one
  # release. The version that becomes a tag name is written canonically.
  case "$version" in
    0[0-9]* | *.0[0-9]*)
      _release_die "JIG_VERSION $version has a leading zero; write the release version without one" ;;
  esac
  tag="v$version"

  # Tags come from the remote, not the checkout: actions/checkout fetches one
  # commit and no tags, and the remote is where a release has to exist.
  remote_tags=$(git -C "$repo" ls-remote --tags origin 2>/dev/null) \
    || _release_die "cannot list the tags of origin"

  # Already released means a release tag with the same version number, not the
  # same spelling: a tag name compared as a string would miss v01.0.0 and
  # publish v1.0.0 as a second tag for one release.
  local line ref ref_version
  while IFS= read -r line; do
    ref=${line##*refs/tags/}
    ref=${ref%'^{}'}
    ref_version=$(jig_release_version "$ref") || continue
    if ! jig_version_newer "$ref_version" "$version" \
       && ! jig_version_newer "$version" "$ref_version"; then
      printf 'release: %s already exists, nothing to do\n' "$ref"
      return 0
    fi
  done <<EOF
$remote_tags
EOF

  if newest=$(printf '%s\n' "$remote_tags" | jig_newest_release); then
    newest_version=$(jig_release_version "$newest")
    if jig_version_newer "$newest_version" "$version"; then
      _release_die "JIG_VERSION $version is lower than the latest release $newest; a version never goes back"
    fi
  fi

  head=$(git -C "$repo" rev-parse HEAD) || _release_die "cannot read HEAD"

  if [ "$dry" = 1 ]; then
    printf 'release: would create %s at %s\n' "$tag" "$head"
    return 0
  fi

  git -C "$repo" tag -a "$tag" -m "Jig $version" "$head" \
    || _release_die "could not create tag $tag"
  if ! git -C "$repo" push origin "refs/tags/$tag"; then
    # Only the local tag this run just made is removed, so a rerun starts
    # clean; whatever the remote holds is left exactly as it is.
    git -C "$repo" tag -d "$tag" >/dev/null 2>&1 || true
    _release_die "could not push $tag to origin; nothing was changed there"
  fi
  printf 'release: %s created at %s\n' "$tag" "$head"
}

main "$@"
