# Tests for `.github/scripts/main-green-check.sh` (task release-pr-runs-full-ci).
# shellcheck shell=bash
#
# Modelled on tests/changelog-check.t.sh: no network, the remote is a local
# bare repository, and `gh` is a stub on PATH that answers from mg_gh's
# arguments and logs how it was called. The script reads the repository the
# caller stands in, so every test builds a fixture repo under its own tmp dir
# and runs the script there (mg_check). Helpers below are prefixed mg_.

# --- fixture builders --------------------------------------------------------

# mg_new_repo <dir> <version> — a fresh git repo declaring JIG_VERSION=<version>,
# with a bare origin holding its main branch and tags.
mg_new_repo() {
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
  git init -q --bare "$dir.git"
  git -C "$dir.git" symbolic-ref HEAD refs/heads/main
  (cd "$dir" && git remote add origin "$dir.git" && git push -q origin main)
}

# mg_release <dir> <tag> — publish a release tag on the fixture's origin.
mg_release() {
  (cd "$1" && git tag -a "$2" -m "$2" && git push -q origin "$2")
}

# mg_gh <rc> [answer] — a stub `gh` that prints <answer> and exits <rc>; every
# call is appended to $PWD/gh.log.
mg_gh() {
  mkdir -p "$PWD/stub-bin"
  cat > "$PWD/stub-bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/gh.log"
printf '%s' "${2:-}"
exit $1
STUB
  chmod +x "$PWD/stub-bin/gh"
}

# mg_check <dir> — run the script under test in <dir>, the way the
# `changelog` job does.
mg_check() {
  local stub="$PWD/stub-bin"
  (cd "$1" && PATH="$stub:$PATH" GITHUB_REPOSITORY=example/jig \
    "$JIG_HOME/.github/scripts/main-green-check.sh")
}

# mg_check_without_slug <dir> — mg_check, with GITHUB_REPOSITORY unset.
mg_check_without_slug() {
  local stub="$PWD/stub-bin"
  (cd "$1" && unset GITHUB_REPOSITORY && PATH="$stub:$PATH" \
    "$JIG_HOME/.github/scripts/main-green-check.sh")
}

# --- a pull request that releases nothing --------------------------------------

test_main_green_check_released_version_asks_nothing() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.2.0
  mg_release "$repo" v0.2.0
  mg_gh 1

  run mg_check "$repo"
  assert_eq 0 "$RC" "a version already tagged releases nothing: $OUT"
  assert_contains "$OUT" "main-green-check: v0.2.0 is already released"
  assert_no_file "$PWD/gh.log" "GitHub must not be asked when nothing is released"
}

# --- a release ---------------------------------------------------------------

test_main_green_check_green_main_passes() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.3.0
  mg_release "$repo" v0.2.0
  mg_gh 0 "success https://github.com/example/jig/actions/runs/1"

  run mg_check "$repo"
  assert_eq 0 "$RC" "a release onto a green main passes: $OUT"
  assert_contains "$OUT" "main is green (https://github.com/example/jig/actions/runs/1), 0.3.0 can be released"
  # The question asked is the latest completed run of ci on main.
  assert_file_contains "$PWD/gh.log" "repos/example/jig/actions/workflows/ci.yml/runs"
  assert_file_contains "$PWD/gh.log" "branch=main"
  assert_file_contains "$PWD/gh.log" "status=completed"
}

test_main_green_check_red_main_fails_with_the_run() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.3.0
  mg_gh 0 "failure https://github.com/example/jig/actions/runs/2"

  run mg_check "$repo"
  [ "$RC" != 0 ] || fail "a release onto a red main must be refused: $OUT"
  assert_contains "$OUT" "main is red (failure): https://github.com/example/jig/actions/runs/2; fix it first"
  assert_contains "$OUT" "releases 0.3.0"
}

# Only success is green: a cancelled or timed-out run tested nothing to the end.
test_main_green_check_cancelled_main_fails() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.3.0
  mg_gh 0 "cancelled https://github.com/example/jig/actions/runs/3"

  run mg_check "$repo"
  [ "$RC" != 0 ] || fail "a cancelled main run is not green: $OUT"
  assert_contains "$OUT" "main is red (cancelled)"
}

test_main_green_check_no_completed_run_passes() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.1.0
  mg_gh 0 ""

  run mg_check "$repo"
  assert_eq 0 "$RC" "a main with no completed run has nothing to wait for: $OUT"
  assert_contains "$OUT" "main has no completed ci run yet"
}

# --- unmeasurable refuses ----------------------------------------------------------

test_main_green_check_github_unreachable_fails() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.3.0
  mg_gh 1

  run mg_check "$repo"
  [ "$RC" != 0 ] || fail "an unanswered question must not pass a release: $OUT"
  assert_contains "$OUT" "cannot read the CI runs of main; re-run this job"
}

test_main_green_check_origin_unreachable_fails() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.3.0
  (cd "$repo" && git remote set-url origin "$PWD/does-not-exist.git")
  mg_gh 0 "success https://github.com/example/jig/actions/runs/1"

  run mg_check "$repo"
  [ "$RC" != 0 ] || fail "main-green-check must fail when origin is unreachable: $OUT"
  assert_contains "$OUT" "main-green-check: error: cannot list the tags of origin"
}

test_main_green_check_without_repository_slug_fails() {
  local repo="$PWD/repo"
  mg_new_repo "$repo" 0.3.0
  mg_gh 0 "success https://github.com/example/jig/actions/runs/1"

  run mg_check_without_slug "$repo"
  [ "$RC" != 0 ] || fail "without GITHUB_REPOSITORY there is no one to ask: $OUT"
  assert_contains "$OUT" "GITHUB_REPOSITORY is not set"
}
