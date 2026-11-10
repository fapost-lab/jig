# Tests for `.github/scripts/ci-scope.sh` (ADR-0041 as amended). shellcheck shell=bash
#
# The script decides `full` or `light` from a diff against a base commit, so
# every test builds its own fixture repo under the test's own tmp dir (via
# fixture_repo) and invokes "$JIG_HOME/.github/scripts/ci-scope.sh" with that
# fixture as the working directory (cs_scope) — the same pattern
# tests/release-tag.t.sh uses for release-tag.sh. The script sources
# scripts/lib/verify.sh from $JIG_HOME by its own path, never from the
# fixture, so the fixture never needs a copy of it. Helpers below are
# prefixed cs_.

# --- fixture builders --------------------------------------------------------

# cs_scope <dir> [args...] — run the script under test against the fixture
# repo in <dir>, exactly the way the `scope` CI job invokes it.
cs_scope() {
  local dir="$1"
  shift
  (cd "$dir" && "$JIG_HOME/.github/scripts/ci-scope.sh" "$@")
}

# cs_new_repo <dir> — a fresh git repo (one commit on main, via fixture_repo)
# to build a test's history on top of. Prints nothing.
cs_new_repo() {
  mkdir -p "$1"
  (cd "$1" && fixture_repo)
}

# cs_write <dir> <path> <content> — write <content> (plus a trailing newline)
# to <path> inside <dir>, creating parent directories as needed. Does not
# stage or commit.
cs_write() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$(dirname "$dir/$path")"
  printf '%s\n' "$content" > "$dir/$path"
}

# cs_rm <dir> <path> — remove a tracked file, for a test that needs a
# deletion in its diff. Does not stage or commit.
cs_rm() {
  rm -f "$1/$2"
}

# cs_commit <dir> <message> — stage everything, including deletions, and
# commit.
cs_commit() {
  local dir="$1" msg="$2"
  (cd "$dir" && git add -A && git commit -q -m "$msg")
}

# cs_head <dir> — the commit sha at the head of <dir>.
cs_head() {
  git -C "$1" rev-parse HEAD
}

# cs_map <dir> <<'EOF' ... EOF — write .ai/verify/shell.map (the file
# ci-scope.sh reads, ADR-0041) from stdin.
cs_map() {
  local dir="$1"
  mkdir -p "$dir/.ai/verify"
  cat > "$dir/.ai/verify/shell.map"
}

# --- unmeasurable base: always full ------------------------------------------

test_ci_scope_no_base_argument_is_full() {
  local repo="$PWD/repo"
  cs_new_repo "$repo"

  run cs_scope "$repo"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (no base commit)"
}

test_ci_scope_base_all_zeros_is_full_new_branch() {
  local repo="$PWD/repo"
  cs_new_repo "$repo"

  run cs_scope "$repo" "0000000000000000000000000000000000000000"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (new branch, nothing to compare with)"
}

test_ci_scope_base_not_in_history_is_full() {
  local repo="$PWD/repo"
  cs_new_repo "$repo"

  # A well-formed sha (not all zeros) that this repository never made.
  run cs_scope "$repo" "ffffffffffffffffffffffffffffffffffffffff"
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "full (base ffffffffffffffffffffffffffffffffffffffff is not in the history)"
}

# --- measurable but empty diff: full -----------------------------------------

test_ci_scope_no_changed_files_is_full() {
  local repo="$PWD/repo" head
  cs_new_repo "$repo"
  head=$(cs_head "$repo")

  run cs_scope "$repo" "$head"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (no changed files)"
}

# --- no map: built-in doc rule ------------------------------------------------

# *.md, docs/, .ai/knowledge/ and .ai/specs/ — including a path deleted from
# under .ai/specs/ — are all documentation with no map present, so the whole
# change is light.
test_ci_scope_docs_only_changes_are_light() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_write "$repo" .ai/specs/gone/spec.md "to be removed"
  cs_commit "$repo" "add a spec that will later be deleted"
  base=$(cs_head "$repo")

  cs_write "$repo" README.md "# updated"
  cs_write "$repo" docs/x.txt "doc"
  cs_write "$repo" .ai/knowledge/x.md "knowledge"
  cs_write "$repo" .ai/specs/s/spec.md "spec"
  cs_rm "$repo" .ai/specs/gone/spec.md
  cs_commit "$repo" "docs only"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "light (5 changed files affect no test)"
}

test_ci_scope_script_change_is_full_and_names_the_path() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  base=$(cs_head "$repo")

  cs_write "$repo" scripts/foo.sh "#!/usr/bin/env bash"
  cs_commit "$repo" "add a script"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (scripts/foo.sh may affect tests)"
}

test_ci_scope_mixed_doc_and_script_change_is_full() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  base=$(cs_head "$repo")

  cs_write "$repo" docs/x.txt "doc"
  cs_write "$repo" scripts/foo.sh "#!/usr/bin/env bash"
  cs_commit "$repo" "docs and a script"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (scripts/foo.sh may affect tests)"
}

# --- with a project map ------------------------------------------------------

test_ci_scope_map_dash_decision_is_light() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_map "$repo" <<'EOF'
thing/** -
EOF
  cs_commit "$repo" "add the map"
  base=$(cs_head "$repo")

  cs_write "$repo" thing/a.txt "content"
  cs_commit "$repo" "add thing/a.txt"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "light (1 changed files affect no test)"
}

# The map's own decision wins over the built-in *.md doc rule: a path the
# map names is never left to the fallback, even when it would otherwise
# qualify as documentation.
test_ci_scope_map_decision_overrides_doc_pattern() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_map "$repo" <<'EOF'
templates/** init::
EOF
  cs_commit "$repo" "add the map"
  base=$(cs_head "$repo")

  cs_write "$repo" templates/x.md "template"
  cs_commit "$repo" "add templates/x.md"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (templates/x.md maps to init::)"
}

# A path under .github/ is always full, whatever the map says for it — CI
# configuration is checked by CI itself, never narrowed by a local map.
test_ci_scope_github_path_is_always_full_even_when_map_says_dash() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_map "$repo" <<'EOF'
.github/workflows/** -
EOF
  cs_commit "$repo" "add the map"
  base=$(cs_head "$repo")

  cs_write "$repo" .github/workflows/ci.yml "name: ci"
  cs_commit "$repo" "add a workflow"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (.github/workflows/ci.yml changes CI)"
}

test_ci_scope_map_that_does_not_parse_is_full() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  base=$(cs_head "$repo")

  # A line with a glob but no decision token: _verify_map_check rejects it.
  cs_map "$repo" <<'EOF'
foo
EOF
  cs_write "$repo" README.md "# updated"
  cs_commit "$repo" "docs change with a broken map"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (.ai/verify/shell.map does not parse)"
}

test_ci_scope_unmapped_non_doc_path_is_full() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_map "$repo" <<'EOF'
docs/** -
EOF
  cs_commit "$repo" "add the map"
  base=$(cs_head "$repo")

  cs_write "$repo" .ai/manifest "some manifest content"
  cs_commit "$repo" "add .ai/manifest"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (.ai/manifest may affect tests)"
}

# --- argument errors ----------------------------------------------------------

test_ci_scope_too_many_arguments_exits_2() {
  local dir="$PWD/plain"
  mkdir -p "$dir"

  run cs_scope "$dir" abc def
  assert_eq 2 "$RC"
  assert_contains "$OUT" "usage: ci-scope.sh <base-commit>"
}

# --- selected: the tests the change reaches ----------------------------------
# (adr-20261110-a-pull-request-runs-the-tests-its-change-reaches)

# cs_suite <dir> — a project the shell profile can narrow: an executable
# tests/run.sh and two test files, each named after a script.
cs_suite() {
  local dir="$1"
  cs_write "$dir" tests/run.sh "#!/usr/bin/env bash"
  chmod +x "$dir/tests/run.sh"
  cs_write "$dir" tests/foo.t.sh "test_foo_works() { :; }"
  cs_write "$dir" tests/bar.t.sh "test_bar_works() { :; }"
  cs_write "$dir" scripts/foo.sh "foo() { :; }"
  cs_write "$dir" scripts/bar.sh "bar() { :; }"
  cs_write "$dir" scripts/lib/version.sh 'JIG_VERSION="1.0.0"'
  cs_commit "$dir" "a suite"
}

test_ci_scope_a_script_with_its_own_tests_is_selected() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_suite "$repo"
  base=$(cs_head "$repo")

  cs_write "$repo" scripts/foo.sh "foo() { echo changed; }"
  cs_commit "$repo" "change foo"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "selected (scripts/foo.sh may affect tests; tests: foo:: knowledge::test_real_repository_knowledge_passes_with_no_failures)"
}

test_ci_scope_writes_the_selected_filters_to_the_named_file() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_suite "$repo"
  base=$(cs_head "$repo")

  cs_write "$repo" scripts/foo.sh "foo() { echo changed; }"
  cs_write "$repo" scripts/bar.sh "bar() { echo changed; }"
  cs_commit "$repo" "change both"

  # shellcheck disable=SC2016 # expanded by the inner bash, from its arguments
  run env CI_SCOPE_FILTERS="$PWD/filters" "$(command -v bash)" -c \
    'cd "$1" && "$2/.github/scripts/ci-scope.sh" "$3"' _ "$repo" "$JIG_HOME" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "tests: bar:: foo::"
  assert_eq "bar::
foo::
knowledge::test_real_repository_knowledge_passes_with_no_failures" "$(cat "$PWD/filters")"
}

test_ci_scope_a_profile_answer_of_all_is_full() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_suite "$repo"
  base=$(cs_head "$repo")

  # No test file is named after it and no other script calls it: the
  # profile cannot say what it reaches.
  cs_write "$repo" scripts/lonely.sh "lonely() { :; }"
  cs_commit "$repo" "add a lonely script"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (scripts/lonely.sh may affect tests)"
}

test_ci_scope_the_test_harness_is_always_full() {
  local repo="$PWD/repo" base path
  for path in tests/run.sh tests/lib/assert.sh; do
    rm -rf "$repo"
    cs_new_repo "$repo"
    cs_suite "$repo"
    base=$(cs_head "$repo")
    cs_write "$repo" "$path" "# changed"
    cs_commit "$repo" "change $path"

    run cs_scope "$repo" "$base"
    assert_eq 0 "$RC"
    assert_contains "$OUT" "full ($path changes the test harness)"
  done
}

test_ci_scope_a_version_change_is_full() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_suite "$repo"
  base=$(cs_head "$repo")

  cs_write "$repo" scripts/foo.sh "foo() { echo changed; }"
  cs_write "$repo" scripts/lib/version.sh 'JIG_VERSION="1.1.0"'
  cs_commit "$repo" "release 1.1.0"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full (JIG_VERSION changes; a release is tested whole)"
}

test_ci_scope_an_unreadable_profile_plan_is_full() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_suite "$repo"
  # No runner: the profile plans no tests at all, which is not a selection.
  cs_rm "$repo" tests/run.sh
  cs_commit "$repo" "drop the runner"
  base=$(cs_head "$repo")
  cs_write "$repo" scripts/foo.sh "foo() { echo changed; }"
  cs_commit "$repo" "change foo"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "full ("
  assert_not_contains "$OUT" "selected"
}

# What decides the selection is never selected by itself: a map line written
# today would choose the tests of the pull request that adds it and of every
# one after it.
test_ci_scope_what_decides_the_selection_is_always_full() {
  local repo="$PWD/repo" base path
  for path in .ai/verify/shell.map profiles/shell/verify.sh scripts/lib/verify.sh scripts/lib/profile.sh; do
    rm -rf "$repo"
    cs_new_repo "$repo"
    cs_suite "$repo"
    base=$(cs_head "$repo")
    cs_write "$repo" "$path" "# changed"
    cs_commit "$repo" "change $path"

    run cs_scope "$repo" "$base"
    assert_eq 0 "$RC"
    assert_contains "$OUT" "full ($path decides which tests run)"
  done
}

# A selection still checks the repository's knowledge, which the whole suite
# did and the `knowledge` job does only on a light run.
test_ci_scope_a_selection_with_a_knowledge_change_checks_the_knowledge() {
  local repo="$PWD/repo" base
  cs_new_repo "$repo"
  cs_suite "$repo"
  base=$(cs_head "$repo")
  cs_write "$repo" scripts/foo.sh "foo() { echo changed; }"
  cs_write "$repo" .ai/knowledge/x.md "broken"
  cs_commit "$repo" "code and knowledge"

  run cs_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "selected ("
  assert_contains "$OUT" "knowledge::test_real_repository_knowledge_passes_with_no_failures"
}
