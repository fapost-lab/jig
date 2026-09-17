# Tests for `.github/scripts/epic-pr-check.sh` (ADR-0040,
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

# --- pass: no roadmap declares the epic, unreleased version -> exit 0 -------
# `jig spec epic <id> --finish` removes the epic's spec outright (ADR-0040 as
# amended); a final pull request passes once no roadmap names the head ref at
# all, whether because the spec is gone or it never named this epic.

test_epic_pr_check_no_specs_at_all_passes() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  assert_eq 0 "$RC" "epic-pr-check should succeed when the spec was removed: $OUT"
  assert_contains "$OUT" "epic-pr-check: epic/epic-branches is finished and v0.5.0 is a new version"
}

test_epic_pr_check_roadmap_with_no_epic_line_passes() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "Destination: ship it."
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  assert_eq 0 "$RC" "epic-pr-check should succeed when no roadmap declares the epic: $OUT"
  assert_contains "$OUT" "epic-pr-check: epic/epic-branches is finished and v0.5.0 is a new version"
}

test_epic_pr_check_line_for_another_epic_only_passes() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" other "Epic: epic/other"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  assert_eq 0 "$RC" "epic-pr-check should not care about another epic's line: $OUT"
  assert_contains "$OUT" "epic-pr-check: epic/epic-branches is finished and v0.5.0 is a new version"
}

# --- fail: a roadmap still declares the epic, open or finished --------------
# Any Epic: line naming the head ref means the epic was not finished the way
# this jig finishes one (removing the spec) — including a legacy
# "— finished" line an older jig, or a hand edit, left behind (section 4 of
# the design; ADR-0040 as amended).

test_epic_pr_check_open_line_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "  Epic:   epic/epic-branches   "
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  [ "$RC" != 0 ] || fail "epic-pr-check must refuse an open Epic: line: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: .ai/specs/epic-branches/roadmap.md still declares epic/epic-branches; run 'jig spec epic epic-branches --finish' on the epic before merging"
}

test_epic_pr_check_legacy_finished_line_fails() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "Epic: epic/epic-branches — finished"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  [ "$RC" != 0 ] || fail "epic-pr-check must refuse a legacy finished line too: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: .ai/specs/epic-branches/roadmap.md still declares epic/epic-branches; run 'jig spec epic epic-branches --finish' on the epic before merging"
}

# A dash or a double dash in place of the em dash, and extra surrounding
# whitespace, must still count as declaring the epic.
test_epic_pr_check_legacy_finished_dash_variants_and_whitespace_fail() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" epic-branches "  Epic:   epic/epic-branches   --   finished   "
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" epic/epic-branches
  [ "$RC" != 0 ] || fail "epic-pr-check must refuse -- and loose whitespace on a finished line: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: .ai/specs/epic-branches/roadmap.md still declares epic/epic-branches; run 'jig spec epic epic-branches --finish' on the epic before merging"
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
# `epic/aXb` must not satisfy a head ref of `epic/a.b` — so the mismatched
# roadmap does not block this merge either.
test_epic_pr_check_ref_matched_literally_not_as_pattern() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" aXb "Epic: epic/aXb"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" "epic/a.b"
  assert_eq 0 "$RC" "epic-pr-check must not treat . as a wildcard: $OUT"
  assert_contains "$OUT" "epic-pr-check: epic/a.b is finished and v0.5.0 is a new version"
}

# The same literal match must still refuse the merge when the ref really is
# declared, "." and all.
test_epic_pr_check_ref_matched_literally_still_fails_a_real_match() {
  local repo="$PWD/repo" bare="$PWD/origin.git"
  ec_new_repo "$repo" 0.5.0
  ec_write_roadmap "$repo" a.b "Epic: epic/a.b"
  ec_build_origin "$repo" "$bare"

  run ec_check "$repo" "epic/a.b"
  [ "$RC" != 0 ] || fail "epic-pr-check must still refuse a real match: $OUT"
  assert_contains "$OUT" \
    "epic-pr-check: error: .ai/specs/a.b/roadmap.md still declares epic/a.b; run 'jig spec epic a.b --finish' on the epic before merging"
}
