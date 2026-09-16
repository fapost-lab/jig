# release-lib.sh — shared "does a release of this version already exist"
# check, used by both .github/scripts/release-tag.sh (which tags a release
# on a push to main) and .github/scripts/epic-pr-check.sh (which refuses to
# let an epic merge into main when its version was already released while
# the epic was in flight). Kept as one function so the two scripts can never
# disagree on what "already released" means.
#
# Requires scripts/lib/common.sh to already be sourced, for
# jig_release_version and jig_version_newer.
#
# Usage: . release-lib.sh
# shellcheck shell=bash

# release_existing_tag <version> <remote_tags> — print the name of the
# release tag in <remote_tags> (the output of `git ls-remote --tags origin`,
# or a plain list of tag names, one per line) whose version equals <version>
# and return 0; print nothing and return 1 when none does.
#
# "Equals" is numeric, not lexical: a tag name compared as a string would
# miss v01.0.0 when asked about 1.0.0, and publish v1.0.0 as a second tag for
# the same release.
release_existing_tag() {
  local version="$1" remote_tags="$2" line ref ref_version
  while IFS= read -r line; do
    ref=${line##*refs/tags/}
    ref=${ref%'^{}'}
    ref_version=$(jig_release_version "$ref") || continue
    if ! jig_version_newer "$ref_version" "$version" \
       && ! jig_version_newer "$version" "$ref_version"; then
      printf '%s\n' "$ref"
      return 0
    fi
  done <<EOF
$remote_tags
EOF
  return 1
}
