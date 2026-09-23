# Tests for `.github/scripts/changelog-check.sh` (task changelog-page).
# shellcheck shell=bash
#
# Modelled on tests/release-tag.t.sh and tests/epic-pr-check.t.sh: no network,
# every "remote" is a local bare repository. The script reads the repository
# the *caller* stands in (`git rev-parse --show-toplevel`), so every test
# builds a small fixture repo under the test's own tmp dir and invokes
# "$JIG_HOME/.github/scripts/changelog-check.sh" with that fixture as the
# working directory (cc_check). Helpers below are prefixed cc_.

# --- fixture builders --------------------------------------------------------

# cc_new_repo <dir> <version> — a fresh git repo (one commit on main, via
# fixture_repo) with a second commit declaring JIG_VERSION=<version> in
# scripts/lib/version.sh.
cc_new_repo() {
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

# cc_write_changelog <dir> <content> — write docs/changelog.mdx with <content>
# verbatim (may be several lines) and commit it.
cc_write_changelog() {
  local dir="$1" content="$2"
  (
    cd "$dir" || exit 1
    mkdir -p docs
    printf '%s\n' "$content" > docs/changelog.mdx
    git add docs/changelog.mdx
    git commit -q -m "changelog"
  )
}

# cc_build_origin <work> <bare> — a bare remote outside <work>, with <work>'s
# main branch and every tag it has so far pushed, and origin configured.
cc_build_origin() {
  local work="$1" bare="$2"
  git init -q --bare "$bare"
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  (cd "$work" && git remote add origin "$bare" && git push -q origin main --tags)
}

# cc_tag <dir> <tag> <commit> <message> — an annotated tag directly on the
# fixture repo, to seed a release that already exists before the script runs.
cc_tag() {
  local dir="$1" tag="$2" commit="$3" msg="$4"
  (cd "$dir" && git tag -a "$tag" -m "$msg" "$commit")
}

# cc_check <dir> [args...] — run the script under test against the fixture
# repo in <dir>, the way the `changelog` job invokes it.
cc_check() {
  local dir="$1"
  shift
  (cd "$dir" && "$JIG_HOME/.github/scripts/changelog-check.sh" "$@")
}

# --- pass: the declared version is described, or already released -----------

test_changelog_check_entry_for_the_new_version_passes() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.2.0
  cc_write_changelog "$repo" "# Changelog

## 0.2.0 — 2026-09-14

- The first release."
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  assert_eq 0 "$RC" "changelog-check should pass when the version has a section: $OUT"
  assert_contains "$OUT" "changelog-check: docs/changelog.mdx describes 0.2.0"
}

# Every pull request that leaves the version alone: the release exists, so
# there is nothing new to describe and the changelog is not read at all.
test_changelog_check_released_version_passes_without_a_changelog() {
  local repo="$PWD/repo" bare="$PWD/origin.git" head
  cc_new_repo "$repo" 0.2.0
  head=$(git -C "$repo" rev-parse HEAD)
  cc_tag "$repo" v0.2.0 "$head" "Jig 0.2.0"
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  assert_eq 0 "$RC" "a released version needs no new entry: $OUT"
  assert_contains "$OUT" "changelog-check: v0.2.0 is already released, nothing to describe"
}

# The heading may carry a date or a release title after the version.
test_changelog_check_heading_with_title_passes() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.15.0
  cc_write_changelog "$repo" "## 0.15.0 — 2026-09-23 — agents that finish a task

- Autopilot."
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  assert_eq 0 "$RC" "a dated heading is still the version's section: $OUT"
  assert_contains "$OUT" "describes 0.15.0"
}

# --- fail: the release this branch declares is not described ----------------

test_changelog_check_missing_entry_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3.0
  cc_write_changelog "$repo" "# Changelog

## 0.2.0 — 2026-09-14

- The first release."
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "changelog-check must refuse a release nobody described: $OUT"
  assert_contains "$OUT" "has no '## 0.3.0' section"
}

test_changelog_check_missing_file_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3.0
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "changelog-check must refuse a missing changelog: $OUT"
  assert_contains "$OUT" "docs/changelog.mdx is missing"
}

# A section for 0.3.0 does not describe 0.3, and one for 0.3 does not
# describe 0.3.0: the version is matched as a whole, not as a prefix.
test_changelog_check_prefix_of_another_version_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3.0
  cc_write_changelog "$repo" "## 0.3.01 — not this one

- Something else."
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "a longer version must not satisfy the check: $OUT"
  assert_contains "$OUT" "has no '## 0.3.0' section"
}

# A mention in prose is not an entry: only a heading declares that the
# release was described.
test_changelog_check_version_only_in_prose_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3.0
  cc_write_changelog "$repo" "# Changelog

0.3.0 is coming soon.

## 0.2.0 — 2026-09-14

- The first release."
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "prose is not a section: $OUT"
  assert_contains "$OUT" "has no '## 0.3.0' section"
}

# --- fail: the version itself is unusable -----------------------------------

test_changelog_check_malformed_version_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3
  cc_write_changelog "$repo" "## 0.3 — 2026-09-15"
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "changelog-check must refuse a version that is not major.minor.patch: $OUT"
  assert_contains "$OUT" "is not major.minor.patch"
}

test_changelog_check_unknown_argument_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3.0
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo" --nope
  [ "$RC" != 0 ] || fail "changelog-check must refuse an unknown argument: $OUT"
  assert_contains "$OUT" "unknown argument: --nope"
}

# --changelog points the check at another file, which is how a release that
# renames the page keeps its gate.
test_changelog_check_explicit_path_is_used() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3.0
  cc_build_origin "$repo" "$bare"
  printf '## 0.3.0 — elsewhere\n' > "$PWD/elsewhere.mdx"

  run cc_check "$repo" --changelog "$PWD/elsewhere.mdx"
  assert_eq 0 "$RC" "an explicit path must be read instead of the default: $OUT"
  assert_contains "$OUT" "describes 0.3.0"
}

# --- fail: the checkout itself cannot answer the question -------------------

test_changelog_check_version_file_missing_fails() {
  local repo="$PWD/repo"
  mkdir -p "$repo"
  (cd "$repo" && fixture_repo)

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "changelog-check must refuse a missing scripts/lib/version.sh: $OUT"
  assert_contains "$OUT" \
    'changelog-check: error: cannot read a single JIG_VERSION="..." line from scripts/lib/version.sh'
}

# Two JIG_VERSION lines must not silently pick either one: jig_declared_version
# requires exactly one match.
test_changelog_check_version_duplicate_declaration_fails() {
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

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "changelog-check must refuse two JIG_VERSION lines: $OUT"
  assert_contains "$OUT" \
    'changelog-check: error: cannot read a single JIG_VERSION="..." line from scripts/lib/version.sh'
}

test_changelog_check_origin_unreachable_fails() {
  local repo="$PWD/repo" missing="$PWD/does-not-exist.git"
  cc_new_repo "$repo" 0.3.0
  (cd "$repo" && git remote add origin "$missing")

  run cc_check "$repo"
  [ "$RC" != 0 ] || fail "changelog-check must fail when origin is unreachable: $OUT"
  assert_contains "$OUT" "changelog-check: error: cannot list the tags of origin"
}

test_changelog_check_outside_a_repository_fails() {
  local plain="$PWD/not-a-repo"
  mkdir -p "$plain"

  run cc_check "$plain"
  [ "$RC" != 0 ] || fail "changelog-check must refuse a directory that is no repository: $OUT"
  assert_contains "$OUT" "changelog-check: error: not inside a git repository"
}

test_changelog_check_changelog_flag_without_a_value_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  cc_new_repo "$repo" 0.3.0
  cc_build_origin "$repo" "$bare"

  run cc_check "$repo" --changelog
  [ "$RC" != 0 ] || fail "changelog-check must refuse --changelog without a path: $OUT"
  assert_contains "$OUT" "changelog-check: error: --changelog needs a path"
}
