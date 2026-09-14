# Tests for `.github/scripts/release-tag.sh` (design.md, task release-v0.1.0,
# AC-01..AC-05). shellcheck shell=bash
#
# No network: every "remote" is a local bare repository, the same pattern
# tests/self-update.t.sh uses for its own remotes. Helpers below are
# prefixed rt_.
#
# The script tags the repository the *caller* stands in (`git rev-parse
# --show-toplevel` of the current directory), not the one it was read from,
# so every test builds a small fixture repo under the test's own tmp dir and
# invokes "$JIG_HOME/.github/scripts/release-tag.sh" with that fixture as the
# working directory (rt_release). The fixture only needs
# scripts/lib/version.sh — scripts/lib/common.sh is sourced from the real
# framework checkout ($JIG_HOME), never copied into the fixture.

# --- fixture builders --------------------------------------------------------

# rt_new_repo <dir> <version> — a fresh git repo (one commit on main, via
# fixture_repo) with a second commit that declares JIG_VERSION=<version> in
# scripts/lib/version.sh, properly quoted on a single line.
rt_new_repo() {
  local dir="$1" version="$2"
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    fixture_repo
    mkdir -p scripts/lib
    printf 'JIG_VERSION="%s"\n' "$version" > scripts/lib/version.sh
    git add scripts/lib/version.sh
    git commit -q -m "version $version"
  )
}

# rt_bump_version <dir> <version> — a further commit that changes
# JIG_VERSION, advancing HEAD (the "PR that bumps the version" step of
# design.md section 1).
rt_bump_version() {
  local dir="$1" version="$2"
  (
    cd "$dir" || exit 1
    printf 'JIG_VERSION="%s"\n' "$version" > scripts/lib/version.sh
    git add scripts/lib/version.sh
    git commit -q -m "version $version"
  )
}

# rt_plain_commit <dir> <name> — an ordinary commit that does not touch
# JIG_VERSION, for the "merge without a version bump" case (AC-02).
rt_plain_commit() {
  local dir="$1" name="$2"
  (
    cd "$dir" || exit 1
    printf '%s\n' "$name" > "$name.txt"
    git add "$name.txt"
    git commit -q -m "$name"
  )
}

# rt_tag <dir> <tag> <commit> <message> — create an annotated tag directly
# (bypassing the script under test), to seed a release that already exists
# before the script runs.
rt_tag() {
  local dir="$1" tag="$2" commit="$3" msg="$4"
  (cd "$dir" && git tag -a "$tag" -m "$msg" "$commit")
}

# rt_build_origin <work> <bare> — a bare remote outside <work>, with <work>'s
# main branch and every tag it has so far pushed, and origin configured. Must
# be created after any rt_tag calls a test wants already present in origin.
rt_build_origin() {
  local work="$1" bare="$2"
  git init -q --bare "$bare"
  # A bare repo's own default branch may be "master" regardless of what the
  # pushing client uses (see tests/self-update.t.sh su_build_upstream).
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  (cd "$work" && git remote add origin "$bare" && git push -q origin main --tags)
}

# rt_push <work> — push whatever is new in <work> (commits, tags) to its
# already-configured origin.
rt_push() { (cd "$1" && git push -q origin main --tags); }

# rt_release <dir> [args...] — run the script under test against the
# fixture repo in <dir>, exactly the way the release job invokes it.
rt_release() {
  local dir="$1"
  shift
  (cd "$dir" && "$JIG_HOME/.github/scripts/release-tag.sh" "$@")
}

# --- AC-01: new version, no prior tag -> annotated tag on HEAD, pushed ------

test_release_tag_new_version_no_remote_tags_creates_and_pushes() {
  local repo="$PWD/repo" bare="$PWD/origin.git" head
  rt_new_repo "$repo" 0.1.0
  rt_build_origin "$repo" "$bare"
  head=$(git -C "$repo" rev-parse HEAD)

  run rt_release "$repo"
  assert_eq 0 "$RC" "release-tag should succeed: $OUT"
  assert_contains "$OUT" "release: v0.1.0 created at $head"

  assert_eq "tag" "$(git -C "$bare" cat-file -t v0.1.0)" "must be an annotated tag object"
  assert_eq "$head" "$(git -C "$bare" rev-parse 'v0.1.0^{commit}')" "tag must point at HEAD"
  assert_contains "$(git -C "$bare" cat-file -p v0.1.0)" "Jig 0.1.0" "tag message"
}

# A bump on top of an already-released version must tag the new HEAD and
# leave the earlier release exactly where it is — design.md section 1: "an
# existing tag is never moved or deleted".
test_release_tag_bumped_version_creates_leaving_older_tag_unchanged() {
  local repo="$PWD/repo" bare="$PWD/origin.git" c1 c2
  rt_new_repo "$repo" 0.1.0
  c1=$(git -C "$repo" rev-parse HEAD)
  rt_tag "$repo" v0.1.0 "$c1" "Jig 0.1.0"
  rt_build_origin "$repo" "$bare"

  rt_bump_version "$repo" 0.2.0
  c2=$(git -C "$repo" rev-parse HEAD)
  rt_push "$repo"

  run rt_release "$repo"
  assert_eq 0 "$RC" "release-tag should succeed: $OUT"
  assert_contains "$OUT" "release: v0.2.0 created at $c2"

  assert_eq "$c2" "$(git -C "$bare" rev-parse 'v0.2.0^{commit}')" "new tag must point at the new HEAD"
  assert_eq "$c1" "$(git -C "$bare" rev-parse 'v0.1.0^{commit}')" "older release tag must not move"
}

# --- AC-02: the tag already exists -> exit 0, nothing new ------------------

test_release_tag_already_exists_at_head_is_noop() {
  local repo="$PWD/repo" bare="$PWD/origin.git" c1
  rt_new_repo "$repo" 0.1.0
  c1=$(git -C "$repo" rev-parse HEAD)
  rt_tag "$repo" v0.1.0 "$c1" "Jig 0.1.0"
  rt_build_origin "$repo" "$bare"

  run rt_release "$repo"
  assert_eq 0 "$RC" "release-tag should succeed: $OUT"
  assert_contains "$OUT" "release: v0.1.0 already exists, nothing to do"
  assert_eq "$c1" "$(git -C "$bare" rev-parse 'v0.1.0^{commit}')" "tag must not move"
}

# A normal merge that does not bump the version moves HEAD past the release
# commit; the tag must be reported as existing and stay exactly where it was,
# never follow HEAD (design.md section 1: "wherever the tag points").
test_release_tag_exists_on_older_commit_after_unrelated_merge_is_noop() {
  local repo="$PWD/repo" bare="$PWD/origin.git" c1
  rt_new_repo "$repo" 0.1.0
  c1=$(git -C "$repo" rev-parse HEAD)
  rt_tag "$repo" v0.1.0 "$c1" "Jig 0.1.0"
  rt_build_origin "$repo" "$bare"

  rt_plain_commit "$repo" merge-note
  rt_push "$repo"

  run rt_release "$repo"
  assert_eq 0 "$RC" "release-tag should succeed: $OUT"
  assert_contains "$OUT" "release: v0.1.0 already exists, nothing to do"
  assert_eq "$c1" "$(git -C "$bare" rev-parse 'v0.1.0^{commit}')" \
    "tag must stay on the release commit, not follow HEAD"
}

# --- AC-03: version too low, malformed, or unreadable -> exit 1, no tag ----

# Numeric comparison, not lexical: 0.9.0 is lower than 0.10.0 even though
# "0.9.0" sorts after "0.10.0" as a string (jig_version_newer, common.sh).
test_release_tag_lower_than_newest_release_fails_numeric_not_lexical() {
  local repo="$PWD/repo" bare="$PWD/origin.git" c_newest
  rt_new_repo "$repo" 0.10.0
  c_newest=$(git -C "$repo" rev-parse HEAD)
  rt_tag "$repo" v0.10.0 "$c_newest" "Jig 0.10.0"
  rt_build_origin "$repo" "$bare"

  rt_bump_version "$repo" 0.9.0
  rt_push "$repo"

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must refuse a version lower than the latest release: $OUT"
  assert_contains "$OUT" \
    "release: error: JIG_VERSION 0.9.0 is lower than the latest release v0.10.0; a version never goes back"

  assert_eq "" "$(git -C "$repo" tag -l v0.9.0)" "no local tag for the refused version"
  assert_eq "$c_newest" "$(git -C "$bare" rev-parse 'v0.10.0^{commit}')" "existing release must be untouched"
}

test_release_tag_version_two_fields_fails() {
  local repo="$PWD/repo"
  rt_new_repo "$repo" 1.0

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must refuse a two-field version: $OUT"
  assert_contains "$OUT" "release: error: JIG_VERSION 1.0 is not major.minor.patch"
  assert_eq "" "$(git -C "$repo" tag -l)" "no tag may be created"
}

test_release_tag_version_prerelease_suffix_fails() {
  local repo="$PWD/repo"
  rt_new_repo "$repo" 1.0.0-rc1

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must refuse a pre-release suffix: $OUT"
  assert_contains "$OUT" "release: error: JIG_VERSION 1.0.0-rc1 is not major.minor.patch"
  assert_eq "" "$(git -C "$repo" tag -l)" "no tag may be created"
}

# jig_declared_version requires the value to be quoted; an unquoted
# assignment must read as unreadable, not as a version to validate.
test_release_tag_version_unquoted_fails() {
  local repo="$PWD/repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    fixture_repo
    mkdir -p scripts/lib
    printf 'JIG_VERSION=1.0.0\n' > scripts/lib/version.sh
    git add scripts/lib/version.sh
    git commit -q -m "version 1.0.0 unquoted"
  )

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must refuse an unquoted JIG_VERSION: $OUT"
  assert_contains "$OUT" \
    'release: error: cannot read a single JIG_VERSION="..." line from scripts/lib/version.sh'
  assert_eq "" "$(git -C "$repo" tag -l)" "no tag may be created"
}

# Two JIG_VERSION lines must not silently pick either one: jig_declared_version
# requires exactly one match.
test_release_tag_version_duplicate_declaration_fails() {
  local repo="$PWD/repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    fixture_repo
    mkdir -p scripts/lib
    {
      printf 'JIG_VERSION="1.0.0"\n'
      printf 'JIG_VERSION="1.0.1"\n'
    } > scripts/lib/version.sh
    git add scripts/lib/version.sh
    git commit -q -m "two version lines"
  )

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must refuse two JIG_VERSION lines: $OUT"
  assert_contains "$OUT" \
    'release: error: cannot read a single JIG_VERSION="..." line from scripts/lib/version.sh'
  assert_eq "" "$(git -C "$repo" tag -l)" "no tag may be created"
}

test_release_tag_version_file_missing_fails() {
  local repo="$PWD/repo"
  mkdir -p "$repo"
  (cd "$repo" && fixture_repo)

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must refuse a missing scripts/lib/version.sh: $OUT"
  assert_contains "$OUT" \
    'release: error: cannot read a single JIG_VERSION="..." line from scripts/lib/version.sh'
  assert_eq "" "$(git -C "$repo" tag -l)" "no tag may be created"
}

test_release_tag_origin_unreachable_fails() {
  local repo="$PWD/repo" missing="$PWD/does-not-exist.git"
  rt_new_repo "$repo" 0.1.0
  (cd "$repo" && git remote add origin "$missing")

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must fail when origin is unreachable: $OUT"
  assert_contains "$OUT" "release: error: cannot list the tags of origin"
  assert_eq "" "$(git -C "$repo" tag -l)" "no tag may be created"
}

# --- AC-04: push rejected -> exit 1, remote and local state both clean -----

# A pre-receive hook rejects the push deterministically (a race against
# ls-remote is not reliable, per the task brief).
test_release_tag_push_rejected_leaves_remote_and_local_tag_clean() {
  local repo="$PWD/repo" bare="$PWD/origin.git" head
  rt_new_repo "$repo" 0.1.0
  rt_build_origin "$repo" "$bare"
  head=$(git -C "$repo" rev-parse HEAD)
  printf '#!/bin/sh\nexit 1\n' > "$bare/hooks/pre-receive"
  chmod +x "$bare/hooks/pre-receive"

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must fail when the push is rejected: $OUT"
  assert_contains "$OUT" "release: error: could not push v0.1.0 to origin; nothing was changed there"

  assert_eq "" "$(git -C "$repo" tag -l v0.1.0)" \
    "the local tag the run just made must be removed"
  assert_eq "" "$(git -C "$bare" tag -l v0.1.0)" "the remote must be left exactly as it was"
  # Prove the head this run started from was really untagged upstream.
  assert_not_contains "$(git -C "$bare" tag -l)" v0.1.0 "sanity: origin never got the tag"
  [ -n "$head" ] || fail "sanity: HEAD must resolve"
}

# --- AC-05: --dry-run -> exit 0, nothing created anywhere ------------------

test_release_tag_dry_run_reports_without_creating_anything() {
  local repo="$PWD/repo" bare="$PWD/origin.git" head
  rt_new_repo "$repo" 0.1.0
  rt_build_origin "$repo" "$bare"
  head=$(git -C "$repo" rev-parse HEAD)

  run rt_release "$repo" --dry-run
  assert_eq 0 "$RC" "release-tag --dry-run should succeed: $OUT"
  assert_contains "$OUT" "release: would create v0.1.0 at $head"

  assert_eq "" "$(git -C "$repo" tag -l v0.1.0)" "dry-run must not create a local tag"
  assert_eq "" "$(git -C "$bare" tag -l v0.1.0)" "dry-run must not push anything"
}

# --- argument and environment errors ----------------------------------------

test_release_tag_unknown_argument_fails_with_usage() {
  local dir="$PWD/plain"
  mkdir -p "$dir"

  run rt_release "$dir" --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "release: error: unknown argument: --bogus (usage: release-tag.sh [--dry-run])"
}

test_release_tag_not_inside_a_git_repository_fails() {
  local dir="$PWD/plain"
  mkdir -p "$dir"

  run rt_release "$dir"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "release: error: not inside a git repository"
}

test_release_tag_version_with_leading_zero_fails() {
  # The shared helpers read 01.0.0 as 1.0.0; a tag named v01.0.0 would still
  # be a second name for one release. The tagged version is canonical.
  local repo="$PWD/repo" bare="$PWD/origin.git"
  rt_new_repo "$repo" 01.0.0
  rt_build_origin "$repo" "$bare"

  run rt_release "$repo"
  [ "$RC" != 0 ] || fail "release-tag must refuse a leading zero: $OUT"
  assert_contains "$OUT" "release: error: JIG_VERSION 01.0.0 has a leading zero"
  assert_eq "" "$(git -C "$bare" tag -l)" "no tag may be published"
}

test_release_tag_numerically_equal_existing_tag_counts_as_released() {
  # Found in review: `v01.0.0` already published (by hand, before the check
  # existed) and JIG_VERSION 1.0.0 must be a no-op, not a second tag v1.0.0
  # for the same release on another commit.
  local repo="$PWD/repo" bare="$PWD/origin.git" c1
  rt_new_repo "$repo" 1.0.0
  c1=$(git -C "$repo" rev-parse HEAD)
  rt_tag "$repo" v01.0.0 "$c1" "Jig 01.0.0"
  rt_build_origin "$repo" "$bare"
  rt_plain_commit "$repo" later

  run rt_release "$repo"
  assert_eq 0 "$RC" "release-tag should succeed as a no-op: $OUT"
  assert_contains "$OUT" "release: v01.0.0 already exists, nothing to do"
  assert_eq "" "$(git -C "$bare" tag -l v1.0.0)" "no second tag for the same release"
}
