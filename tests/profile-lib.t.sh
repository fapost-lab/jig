# Tests for scripts/lib/profile.sh, the shared library every language
# profile sources (adr-20260918-profiles-narrow-per-check-with-project-tools; domains/verify; profiles-scope-and-languages
# design.md D3). Tested directly, one function at a time, without any
# installed project or profile: a bare `bash -c` sources the library exactly
# the way a profile's verify.sh does
# (`. "$(dirname "$0")/../../scripts/lib/profile.sh"`), and each test drives
# one function's contract in isolation.
# shellcheck shell=bash
# Every `_lib_run` call below intentionally passes a single-quoted script
# containing $VAR references meant to expand inside the harness's inner
# `bash -c`, not at this call site (same pattern as profiles_harness in
# tests/profiles.t.sh).
# shellcheck disable=SC2016

# _lib_run <script> — run <script> after sourcing the library, in its own
# subshell (same shape as profiles_harness in tests/profiles.t.sh:
# `run bash -c '...'"$1"`). The caller exports whatever JIG_VERIFY_* the
# library reads *before* this runs, never embeds them in <script>, so a
# snippet stays a plain function-call sequence.
_lib_run() {
  run bash -c '. "$JIG_HOME/scripts/lib/profile.sh"; '"$1"
}

# _lib_file <path>... — a changed-file list, one per line, written beside the
# test's own directory (never inside it, so it never shows up in a
# `git status` a test asserts on — same reason _run_out in
# tests/lib/assert.sh lives beside $JIG_TEST_TMP, not inside it). Prints the
# file's path.
_lib_file() {
  local f="${JIG_TEST_TMP}.libfiles" p
  : > "$f"
  for p in "$@"; do printf '%s\n' "$p" >> "$f"; done
  printf '%s\n' "$f"
}

# _lib_map <line>... — a JIG_VERIFY_MAPPED file; each <line> is
# "<path><TAB><decision>" (build it with $'...' so the tab is real, e.g.
# $'a.py\tfilterA'). Prints the file's path.
_lib_map() {
  local f="${JIG_TEST_TMP}.libmap" l
  : > "$f"
  for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
  printf '%s\n' "$f"
}

# --- jp_begin / jp_scoped ----------------------------------------------------

test_profile_lib_jp_begin_unscoped_by_default() {
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; if jp_scoped; then echo SCOPED_YES; else echo SCOPED_NO; fi'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "SCOPED_NO"
}

test_profile_lib_jp_begin_scoped_when_scope_changed_and_files_file_exists() {
  local files
  files=$(_lib_file "a.py")
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; if jp_scoped; then echo SCOPED_YES; else echo SCOPED_NO; fi'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC"
  assert_contains "$OUT" "SCOPED_YES"
}

test_profile_lib_jp_begin_unscoped_when_files_file_is_missing() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="${JIG_TEST_TMP}.does-not-exist"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; if jp_scoped; then echo SCOPED_YES; else echo SCOPED_NO; fi'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_contains "$OUT" "SCOPED_NO"
}

test_profile_lib_jp_begin_unscoped_when_scope_is_not_changed() {
  local files
  files=$(_lib_file "a.py")
  JIG_VERIFY_SCOPE=full
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; if jp_scoped; then echo SCOPED_YES; else echo SCOPED_NO; fi'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_contains "$OUT" "SCOPED_NO"
}

# --- jp_changed ---------------------------------------------------------------

test_profile_lib_jp_changed_no_extension_lists_existing_changed_files() {
  : > a.py
  : > b.txt
  local files
  files=$(_lib_file "a.py" "b.txt" "missing.py")
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; jp_changed'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC"
  assert_contains "$OUT" "a.py"
  assert_contains "$OUT" "b.txt"
  assert_not_contains "$OUT" "missing.py"
}

test_profile_lib_jp_changed_filters_by_extension() {
  : > a.py
  : > b.txt
  local files
  files=$(_lib_file "a.py" "b.txt")
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; jp_changed py'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_contains "$OUT" "a.py"
  assert_not_contains "$OUT" "b.txt"
}

test_profile_lib_jp_changed_skips_deleted_files() {
  : > a.py
  local files
  files=$(_lib_file "a.py" "gone.py")
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; jp_changed'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_contains "$OUT" "a.py"
  assert_not_contains "$OUT" "gone.py"
}

test_profile_lib_jp_changed_unscoped_prints_nothing() {
  : > a.py
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; jp_changed'
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

# --- jp_changed_any -----------------------------------------------------------

test_profile_lib_jp_changed_any_matches_a_deleted_path() {
  local files
  files=$(_lib_file "deleted.py")
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; jp_changed_any "*.py"'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC"
}

test_profile_lib_jp_changed_any_returns_1_without_a_match() {
  local files
  files=$(_lib_file "a.txt")
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; jp_changed_any "*.py"'
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 1 "$RC"
}

test_profile_lib_jp_changed_any_unscoped_returns_1() {
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run 'jp_begin test; jp_changed_any "*"'
  assert_eq 1 "$RC"
}

# --- jp_decide -----------------------------------------------------------------

test_profile_lib_jp_decide_no_map_uses_builtin_fn_for_every_path() {
  local files
  files=$(_lib_file "a.py" "b.py")
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run '
    _t_fn() { printf "seen-%s\n" "$1"; }
    jp_begin test
    jp_decide _t_fn
  '
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC"
  assert_eq "$(printf 'seen-a.py\nseen-b.py')" "$OUT"
}

test_profile_lib_jp_decide_unscoped_prints_nothing() {
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _lib_run '
    _t_fn() { printf "seen-%s\n" "$1"; }
    jp_begin test
    jp_decide _t_fn
  '
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

# Per-path map decisions win over the builtin; `?` falls back to it; `-`
# excludes the path entirely (ADR-0041 map protocol).
test_profile_lib_jp_decide_map_per_path_and_question_mark_falls_back_to_builtin() {
  local files map
  files=$(_lib_file "a.py" "b.py" "c.py")
  map=$(_lib_map $'a.py\tfilterA' $'b.py\t?' $'c.py\t-')
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  JIG_VERIFY_MAPPED="$map"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _lib_run '
    _t_fn() { printf "builtin-%s\n" "$1"; }
    jp_begin test
    jp_decide _t_fn
  '
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq "$(printf 'builtin-b.py\nfilterA')" "$OUT"
}

test_profile_lib_jp_decide_all_wins_over_every_other_decision() {
  local files map
  files=$(_lib_file "a.py" "b.py")
  map=$(_lib_map $'a.py\t-' $'b.py\tALL')
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  JIG_VERIFY_MAPPED="$map"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _lib_run '
    _t_fn() { printf "x-%s\n" "$1"; }
    jp_begin test
    jp_decide _t_fn
  '
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq "ALL" "$OUT"
}

test_profile_lib_jp_decide_dedups_repeated_filters() {
  local files map
  files=$(_lib_file "a.py" "b.py")
  map=$(_lib_map $'a.py\tsame::' $'b.py\tsame::')
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  JIG_VERIFY_MAPPED="$map"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _lib_run '
    _t_fn() { :; }
    jp_begin test
    jp_decide _t_fn
  '
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq "same::" "$OUT"
}

# A map decision is a hand-edited string: `for tok in $decision` must not
# pathname-expand it against files that happen to sit in the project root
# (same bug class as the shell profile's own map-decision test).
test_profile_lib_jp_decide_glob_token_in_map_is_not_expanded_against_files() {
  : > a1
  : > a2
  local files map
  files=$(_lib_file "trigger.py")
  map=$(_lib_map $'trigger.py\ta*')
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$files"
  JIG_VERIFY_MAPPED="$map"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _lib_run '
    _t_fn() { :; }
    jp_begin test
    jp_decide _t_fn
  '
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq "a*" "$OUT"
}

# --- jp_path_matches --------------------------------------------------------
# Regression coverage for the bug this function was extracted to fix: a
# profile's own always-ALL glob list (e.g. "config/*") used to be split with
# `for g in $LIST` and pathname expansion left on, so a glob word was
# silently replaced by whatever it expanded to against the files that
# happen to sit on disk — never the pattern the profile author wrote. A
# sibling file matching the pattern made the expansion "succeed" (to that
# sibling alone), which then failed to match the actually-changed path,
# including a path that no longer exists (deleted) or one nested deeper
# than the glob's expansion would ever reach. jp_path_matches now splits
# the list with `set -f`, so the comparison is always against the literal
# pattern, regardless of what is on disk.

test_profile_lib_jp_path_matches_deleted_path_not_masked_by_sibling_on_disk() {
  mkdir -p config
  : > config/database.php
  # config/app.php is never created: the changed path was deleted. Old bug:
  # `config/*` expanded to "config/database.php" (the only sibling on disk)
  # before being compared, so a deleted file could never match its own
  # always-ALL glob.
  _lib_run 'jp_path_matches "config/app.php" "composer.json config/*"'
  assert_eq 0 "$RC"
}

test_profile_lib_jp_path_matches_nested_path_not_masked_by_sibling_on_disk() {
  mkdir -p config
  : > config/app.php
  # Old bug: `config/*` expanded via real pathname globbing, which does not
  # cross `/`, so it only ever matched config/app.php (a direct child) —
  # never a path nested one level deeper, regardless of the case pattern's
  # own `*`-crosses-`/` semantics (jp_changed_any's own doc comment).
  _lib_run 'jp_path_matches "config/nested/extra.php" "config/*"'
  assert_eq 0 "$RC"
}

test_profile_lib_jp_path_matches_no_match_returns_1() {
  mkdir -p config
  : > config/app.php
  _lib_run 'jp_path_matches "src/App.php" "config/*"'
  assert_eq 1 "$RC"
}

# --- jp_first_missing -----------------------------------------------------------

test_profile_lib_jp_first_missing_returns_1_when_everything_exists() {
  : > a.txt
  : > b.txt
  _lib_run 'jp_first_missing a.txt b.txt'
  assert_eq 1 "$RC"
  assert_eq "" "$OUT"
}

test_profile_lib_jp_first_missing_reports_the_first_gap() {
  : > a.txt
  _lib_run 'jp_first_missing a.txt gone.txt also-gone.txt'
  assert_eq 0 "$RC"
  assert_eq "gone.txt" "$OUT"
}

# --- jp_files --------------------------------------------------------------------

test_profile_lib_jp_files_inside_git_excludes_ignored_files() {
  fixture_repo
  printf 'tracked\n' > tracked.txt
  git add tracked.txt
  git commit -q -m "add tracked"
  printf 'untracked\n' > untracked.txt
  printf 'ignored.txt\n' >> .gitignore
  printf 'ignored\n' > ignored.txt
  _lib_run 'jp_files'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "tracked.txt"
  assert_contains "$OUT" "untracked.txt"
  assert_not_contains "$OUT" "ignored.txt"
}

test_profile_lib_jp_files_outside_git_prunes_dependency_dirs() {
  mkdir -p .venv/lib node_modules/pkg
  printf 'x\n' > .venv/lib/inside.py
  printf 'y\n' > node_modules/pkg/inside.js
  printf 'z\n' > plain.py
  _lib_run 'jp_files'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "plain.py"
  assert_not_contains "$OUT" ".venv/lib/inside.py"
  assert_not_contains "$OUT" "node_modules/pkg/inside.js"
}

# --- jp_version --------------------------------------------------------------------

test_profile_lib_jp_version_unknown_when_tool_fails_silently() {
  cat > failing-tool <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x failing-tool
  _lib_run 'jp_version ./failing-tool --version'
  assert_eq 0 "$RC"
  assert_eq "unknown" "$OUT"
}

test_profile_lib_jp_version_unknown_when_tool_does_not_exist() {
  _lib_run 'jp_version ./does-not-exist --version'
  assert_eq 0 "$RC"
  assert_eq "unknown" "$OUT"
}

test_profile_lib_jp_version_prints_only_the_first_line() {
  cat > tool-with-version <<'EOF'
#!/usr/bin/env bash
printf 'mytool 1.2.3\nextra line\n'
EOF
  chmod +x tool-with-version
  _lib_run 'jp_version ./tool-with-version --version'
  assert_eq 0 "$RC"
  assert_eq "mytool 1.2.3" "$OUT"
}

# --- jp_end ------------------------------------------------------------------------

test_profile_lib_jp_end_exits_2_when_nothing_ran() {
  _lib_run 'jp_begin test; jp_end'
  assert_eq 2 "$RC"
}

test_profile_lib_jp_end_exits_0_after_only_passes() {
  _lib_run 'jp_begin test; jp_pass foo >/dev/null; jp_end'
  assert_eq 0 "$RC"
}

test_profile_lib_jp_end_exits_1_after_a_failure() {
  _lib_run 'jp_begin test; jp_pass foo >/dev/null; jp_fail bar >/dev/null; jp_end'
  assert_eq 1 "$RC"
}

# --- AC-12: the library resolves from an installed project, not just source --------
# scripts/lib/profile.sh sits at the same depth relative to a profile's
# verify.sh in the framework source, a copy-mode install (.ai/scripts/lib/)
# and a link-mode install (design.md predisposition 5). Both are exercised
# through the real `jig init` / `jig verify` path, with no tool in the
# project's environment, so a bare `python: ruff: skip` line (rather than a
# shell "No such file" or "syntax error") is the proof the relative
# `../../scripts/lib/profile.sh` resolved correctly in each install mode.
# The python profile never searches the bare PATH for ruff/mypy/pytest
# (only `poetry` itself is), so this needs no PATH stripping to be
# deterministic.

test_profile_lib_resolves_from_copy_mode_install() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles python >/dev/null

  run jig verify --profile python
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: skip"
  assert_contains "$OUT" "python: mypy: skip"
  assert_contains "$OUT" "python: pytest: skip"
  assert_contains "$OUT" "RESULT python: skip"
  assert_not_contains "$OUT" "No such file"
  assert_not_contains "$OUT" "syntax error"
}

test_profile_lib_resolves_from_link_mode_install() {
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles python >/dev/null

  run jig verify --profile python
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: skip"
  assert_contains "$OUT" "python: mypy: skip"
  assert_contains "$OUT" "python: pytest: skip"
  assert_contains "$OUT" "RESULT python: skip"
  assert_not_contains "$OUT" "No such file"
  assert_not_contains "$OUT" "syntax error"
}
