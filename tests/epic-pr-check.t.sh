# Tests for `.github/scripts/epic-pr-check.sh` (.ai/specs/epic-branches/spec.md,
# task task-base-and-epics). shellcheck shell=bash
#
# Modelled on tests/release-tag.t.sh: no network, every "remote" is a local
# bare repository (rt_build_origin's pattern, reused here as ec_build_origin).
# The script reads the repository the *caller* stands in (`git rev-parse
# --show-toplevel`), so every test builds a small fixture repo under the
# test's own tmp dir and invokes "$JIG_HOME/.github/scripts/epic-pr-check.sh"
# with that fixture as the working directory (ec_check). Helpers below are
# prefixed ec_.

# --- fixture builders --------------------------------------------------------

# ec_new_repo <dir> <version> — a fresh git repo (one commit on main, via
# fixture_repo) with a second commit declaring JIG_VERSION=<version> in
# scripts/lib/version.sh.
ec_new_repo() {
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

# ec_write_roadmap <dir> <spec-id> <content> — write
# .ai/specs/<spec-id>/roadmap.md with <content> verbatim (may be several
# lines) and commit it. <content> may be empty for "the file exists but says
# nothing about an epic".
ec_write_roadmap() {
  local dir="$1" spec_id="$2" content="$3"
  (
    cd "$dir" || exit 1
    mkdir -p ".ai/specs/$spec_id"
    printf '%s\n' "$content" > ".ai/specs/$spec_id/roadmap.md"
    git add ".ai/specs/$spec_id/roadmap.md"
    git commit -q -m "roadmap for $spec_id"
  )
}

# ec_build_origin <work> <bare> — a bare remote outside <work>, with <work>'s
# main branch and every tag it has so far pushed, and origin configured.
ec_build_origin() {
  local work="$1" bare="$2"
  git init -q --bare "$bare"
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  (cd "$work" && git remote add origin "$bare" && git push -q origin main --tags)
}

# ec_tag <dir> <tag> <commit> <message> — an annotated tag directly on the
# fixture repo, to seed a release that already exists before the script runs.
ec_tag() {
  local dir="$1" tag="$2" commit="$3" msg="$4"
  (cd "$dir" && git tag -a "$tag" -m "$msg" "$commit")
}

# ec_check <dir> [head-ref] — run the script under test against the fixture
# repo in <dir>, the way the `epic-pr` job invokes it.
ec_check() {
  local dir="$1"
  shift
  (cd "$dir" && "$JIG_HOME/.github/scripts/epic-pr-check.sh" "$@")
}

# --- pass: finished epic, unreleased version -> exit 0 ----------------------

test_epic_pr_check_finished_and_unreleased_passes() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "Epic: epic/epic-branches — finished"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  assert_eq 0 "$RC" "epic-pr-check should succeed: $OUT"
  assert_contains "$OUT" "epic-pr-check: epic/epic-branches is finished and v0.5.0 is a new version"
}

# A dash or a double dash in place of the em dash, and extra surrounding
# whitespace, must still count as "finished".
test_epic_pr_check_accepts_dash_variants_and_extra_whitespace() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "  Epic:   epic/epic-branches   --   finished   "
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  assert_eq 0 "$RC" "epic-pr-check should accept -- and loose whitespace: $OUT"
  assert_contains "$OUT" "epic-pr-check: epic/epic-branches is finished and v0.5.0 is a new version"
}

# --- version already released -> exit 1 -------------------------------------

test_epic_pr_check_version_already_released_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git" c1
  ec_new_repo "$repo" 0.5.0
  c1=$(git -C "$repo" rev-parse HEAD)
  ec_tag "$repo" v0.5.0 "$c1" "Jig 0.5.0"
  ec_write_roadmap "$repo" epic-branches "Epic: epic/epic-branches — finished"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  [ "$RC" != 0 ] || fail "epic-pr-check must refuse an already-released version: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: JIG_VERSION 0.5.0 is already released as v0.5.0; raise the version on epic/epic-branches before merging"
}

# --- epic declared but not finished -> exit 1 -------------------------------

test_epic_pr_check_epic_not_finished_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "Epic: epic/epic-branches"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  [ "$RC" != 0 ] || fail "epic-pr-check must refuse an unfinished epic: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: no roadmap marks epic/epic-branches finished; run 'jig spec epic epic-branches --finish' on the epic before merging"
}

# --- finished line names a different epic -> exit 1 -------------------------

test_epic_pr_check_finished_line_for_other_epic_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" other "Epic: epic/other — finished"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  [ "$RC" != 0 ] || fail "epic-pr-check must not accept another epic's finished line: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: no roadmap marks epic/epic-branches finished; run 'jig spec epic epic-branches --finish' on the epic before merging"
}

# --- head ref is not an epic branch -> exit 1 -------------------------------

test_epic_pr_check_head_ref_not_epic_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "Epic: epic/epic-branches — finished"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" feature/epic-branches
  [ "$RC" != 0 ] || fail "epic-pr-check must refuse a non-epic head ref: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: head ref 'feature/epic-branches' does not start with epic/"
}

test_epic_pr_check_missing_head_ref_fails() {
  local repo="$PWD/repo"
  ec_new_repo "$repo" 0.5.0

  run ec_check "$repo"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "epic-pr-check: error: usage: epic-pr-check.sh <head-ref>"
}

# --- the ref is matched literally, not as a pattern -------------------------

# A "." in a spec id must not act as a regex wildcard: a roadmap line for
# `epic/aXb` must not satisfy a head ref of `epic/a.b`.
test_epic_pr_check_ref_matched_literally_not_as_pattern() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" aXb "Epic: epic/aXb — finished"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" "epic/a.b"
  [ "$RC" != 0 ] || fail "epic-pr-check must not treat . as a wildcard: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: no roadmap marks epic/a.b finished; run 'jig spec epic a.b --finish' on the epic before merging"
}
