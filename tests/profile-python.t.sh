# Tests for the python profile (profiles/python/verify.sh + profile.yaml),
# the reference profile for profiles-scope-and-languages design.md D1/D2/D4/D5.
# shellcheck shell=bash
# Every `profiles_harness`/`_py_verify` call below intentionally passes a
# single-quoted script whose $VAR references expand inside the inner
# `bash -c`, not at this call site (same pattern as profiles_harness in
# tests/profiles.t.sh).
# shellcheck disable=SC2016

# --- detect (profiles_detect, same harness as tests/profiles.t.sh) ---------

# profiles_harness <script> — run <script> with profiles.sh (and its
# dependencies common.sh/config.sh) sourced. JIG_LIB points at the real
# framework checkout ($JIG_HOME); JIG_PROJECT is the current directory (a
# fixture repository set up by the caller).
profiles_harness() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
  '"$1"
}

test_profile_python_detect_pyproject_toml() {
  fixture_repo
  printf '[project]\nname = "x"\n' > pyproject.toml
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "python"
}

test_profile_python_detect_requirements_txt() {
  fixture_repo
  printf 'requests\n' > requirements.txt
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "python"
}

test_profile_python_detect_setup_py() {
  fixture_repo
  printf 'from setuptools import setup\nsetup()\n' > setup.py
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "python"
}

test_profile_python_detect_setup_cfg() {
  fixture_repo
  printf '[metadata]\nname = x\n' > setup.cfg
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "python"
}

test_profile_python_detect_pipfile() {
  fixture_repo
  printf '[packages]\n' > Pipfile
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "python"
}

test_profile_python_detect_absent_without_any_manifest() {
  fixture_repo
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "python"
}

# --- helpers: direct invocation, stubs, scope files -------------------------

# _py_verify — run profiles/python/verify.sh straight from the framework
# source tree, from the current (fixture) directory, the way the profile
# brief allows for testing scope directly: JIG_VERIFY_SCOPE/FILES/MAPPED are
# exported by the caller beforehand, never embedded here.
_py_verify() {
  run bash "$JIG_HOME/profiles/python/verify.sh"
}

# _py_scope <path>... — a changed-file list, one per line, written beside
# the test's own directory (never inside it — same reason _run_out in
# tests/lib/assert.sh lives beside $JIG_TEST_TMP). Exports JIG_VERIFY_SCOPE
# and JIG_VERIFY_FILES; does not touch JIG_VERIFY_MAPPED.
_py_scope() {
  local f="${JIG_TEST_TMP}.pyfiles" p
  : > "$f"
  for p in "$@"; do printf '%s\n' "$p" >> "$f"; done
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$f"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
}

# _py_map <line>... — a JIG_VERIFY_MAPPED file; each <line> is
# "<path><TAB><decision>" (build with $'...', e.g. $'a.py\tfilterA').
# Exports JIG_VERIFY_MAPPED. Call after _py_scope.
_py_map() {
  local f="${JIG_TEST_TMP}.pymapped" l
  : > "$f"
  for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
  JIG_VERIFY_MAPPED="$f"
  export JIG_VERIFY_MAPPED
}

_py_unscope() {
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
}

# _py_stub <path> <version-line> [<exit-code>] — a fake tool at <path> that
# answers `--version` with <version-line> and exit 0, and otherwise appends
# every argument it receives, one per line, followed by a "---" separator,
# to "<path>.log" (so a test can assert exactly which arguments a check
# received, and that one argument with a space in it stayed one argument),
# then exits <exit-code> (default 0).
_py_stub() {
  local path="$1" version="$2" rc="${3:-0}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$version"
  exit 0
fi
{
  for a in "\$@"; do printf '%s\n' "\$a"; done
  printf '%s\n' "---"
} >> "$path.log"
exit $rc
STUB
  chmod +x "$path"
}

# _py_poetry_stub <envdir> — a fake `poetry` answering `env info -p` with
# <envdir>, put on PATH ahead of anything else. Used only by tests of the
# poetry-environment fallback; command -v poetry is the one place this
# profile ever looks at the bare PATH (D2).
_py_poetry_stub() {
  local envdir="$1"
  mkdir -p poetry-bin
  cat > poetry-bin/poetry <<STUB
#!/usr/bin/env bash
if [ "\$1" = "env" ] && [ "\$2" = "info" ] && [ "\$3" = "-p" ]; then
  printf '%s\n' "$envdir"
  exit 0
fi
exit 1
STUB
  chmod +x poetry-bin/poetry
  PATH="$PWD/poetry-bin:$PATH"
  export PATH
}

PY_WHERE="not found in \$VIRTUAL_ENV, .venv, venv or the poetry environment"

# --- tool resolution order (D2) ---------------------------------------------

test_profile_python_tool_resolution_prefers_virtual_env_over_dot_venv() {
  fixture_repo
  _py_stub "$PWD/customenv/bin/ruff" "ruff 9.9.9-virtualenv"
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.1.1-dotvenv"
  VIRTUAL_ENV="$PWD/customenv"
  export VIRTUAL_ENV
  _py_verify
  unset VIRTUAL_ENV
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 9.9.9-virtualenv)"
}

test_profile_python_tool_resolution_uses_dot_venv_when_no_virtual_env() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.1.1-dotvenv"
  _py_stub "$PWD/venv/bin/ruff" "ruff 2.2.2-venv"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.1.1-dotvenv)"
}

test_profile_python_tool_resolution_uses_venv_when_no_dot_venv() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/venv/bin/ruff" "ruff 2.2.2-venv"
  printf 'poetry.lock\n' > poetry.lock
  _py_poetry_stub "$PWD/poetryenv"
  _py_stub "$PWD/poetryenv/bin/ruff" "ruff 3.3.3-poetry"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 2.2.2-venv)"
}

test_profile_python_tool_resolution_uses_poetry_env_when_no_venvs() {
  fixture_repo
  unset VIRTUAL_ENV
  printf 'poetry.lock\n' > poetry.lock
  _py_poetry_stub "$PWD/poetryenv"
  _py_stub "$PWD/poetryenv/bin/ruff" "ruff 3.3.3-poetry"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 3.3.3-poetry)"
}

test_profile_python_tool_resolution_scripts_layout_plain_name() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/Scripts/ruff" "ruff 4.4.4-scripts"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 4.4.4-scripts)"
}

test_profile_python_tool_resolution_scripts_layout_exe_name() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/Scripts/ruff.exe" "ruff 5.5.5-exe"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 5.5.5-exe)"
}

test_profile_python_tool_resolution_skips_with_reason_when_absent() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_verify
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: skip ($PY_WHERE)"
  assert_contains "$OUT" "python: mypy: skip ($PY_WHERE)"
  assert_contains "$OUT" "python: pytest: skip ($PY_WHERE)"
}

# The profile only ever looks in $VIRTUAL_ENV/.venv/venv/poetry env for
# pytest/ruff/mypy — never the bare PATH, even when something answering to
# the same name sits right there (D2: "a global pytest ... is never used").
test_profile_python_tool_resolution_ignores_a_global_pytest_on_path() {
  fixture_repo
  unset VIRTUAL_ENV
  mkdir -p decoy-bin
  cat > decoy-bin/pytest <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
  printf 'pytest 0.0.0-decoy\n'
  exit 0
fi
exit 0
EOF
  chmod +x decoy-bin/pytest
  PATH="$PWD/decoy-bin:$PATH"
  export PATH
  _py_verify
  assert_contains "$OUT" "python: pytest: skip ($PY_WHERE)"
  assert_not_contains "$OUT" "0.0.0-decoy"
}

# --- ruff --------------------------------------------------------------------

test_profile_python_ruff_full_run_when_unscoped() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.0.0)"
  assert_eq "$(printf 'check\n.\n---')" "$(cat .venv/bin/ruff.log)"
}

test_profile_python_ruff_scoped_to_changed_py_files() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0"
  printf 'a=1\n' > foo.py
  printf 'b=2\n' > bar.py
  printf 'not python\n' > notes.txt
  _py_scope "foo.py" "bar.py" "notes.txt"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.0.0, scope: 2 files)"
  assert_file_contains .venv/bin/ruff.log foo.py
  assert_file_contains .venv/bin/ruff.log bar.py
  assert_not_contains "$(cat .venv/bin/ruff.log)" "notes.txt"
}

test_profile_python_ruff_config_change_runs_whole_project() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0"
  _py_scope "pyproject.toml"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "python: ruff: pass (ruff 1.0.0, scope: ruff configuration changed, whole project)"
  assert_eq "$(printf 'check\n.\n---')" "$(cat .venv/bin/ruff.log)"
}

test_profile_python_ruff_skips_when_no_changed_py_files() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0"
  printf 'x\n' > notes.md
  _py_scope "notes.md"
  _py_verify
  _py_unscope
  # ruff is the only tool in the environment, and it skips too (nothing
  # narrows to it): no check produced a pass or fail, so the contract's
  # "nothing ran" exit code applies (jp_end).
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: skip (scope: no changed .py files)"
  assert_no_file .venv/bin/ruff.log
}

test_profile_python_ruff_fails_and_exits_1_on_lint_failure() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0" 1
  _py_verify
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: fail (ruff 1.0.0)"
}

# --- mypy ----------------------------------------------------------------------

test_profile_python_mypy_skipped_when_not_configured() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/mypy" "mypy 1.0.0"
  _py_verify
  assert_contains "$OUT" \
    "python: mypy: skip (not configured: no mypy.ini, .mypy.ini, [tool.mypy] or [mypy] in setup.cfg)"
  assert_no_file .venv/bin/mypy.log
}

test_profile_python_mypy_configured_via_mypy_ini() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/mypy" "mypy 1.0.0"
  printf '[mypy]\n' > mypy.ini
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: mypy: pass (mypy 1.0.0)"
}

test_profile_python_mypy_configured_via_dot_mypy_ini() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/mypy" "mypy 1.0.0"
  printf '[mypy]\n' > .mypy.ini
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: mypy: pass (mypy 1.0.0)"
}

test_profile_python_mypy_configured_via_pyproject_tool_mypy() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/mypy" "mypy 1.0.0"
  printf '[tool.mypy]\nstrict = true\n' > pyproject.toml
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: mypy: pass (mypy 1.0.0)"
}

test_profile_python_mypy_configured_via_setup_cfg_mypy() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/mypy" "mypy 1.0.0"
  printf '[mypy]\nignore_missing_imports = True\n' > setup.cfg
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: mypy: pass (mypy 1.0.0)"
}

test_profile_python_mypy_always_runs_full_even_when_scoped() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/mypy" "mypy 1.0.0"
  printf '[mypy]\n' > mypy.ini
  printf 'a=1\n' > foo.py
  _py_scope "foo.py"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: mypy: pass (mypy 1.0.0, scope: not narrowable, ran full set)"
  assert_eq "$(printf '.\n--exclude\n(^|/)(\\.venv|venv)/\n---')" "$(cat .venv/bin/mypy.log)"
}

test_profile_python_mypy_excludes_venv_directories() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/mypy" "mypy 1.0.0"
  printf '[mypy]\n' > mypy.ini
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_eq "$(printf '.\n--exclude\n(^|/)(\\.venv|venv)/\n---')" "$(cat .venv/bin/mypy.log)"
}

# --- pytest --------------------------------------------------------------------

test_profile_python_pytest_full_run_when_unscoped() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0)"
  assert_eq "$(printf '%s' '---')" "$(cat .venv/bin/pytest.log)"
}

test_profile_python_pytest_scoped_test_file_maps_to_itself() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  mkdir -p tests
  printf 'def test_a(): pass\n' > tests/test_foo.py
  _py_scope "tests/test_foo.py"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: 1 test files)"
  assert_eq "$(printf 'tests/test_foo.py\n---')" "$(cat .venv/bin/pytest.log)"
}

test_profile_python_pytest_scoped_module_maps_to_test_prefix_and_suffix() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  mkdir -p tests
  printf 'a=1\n' > foo.py
  printf 'def test_a(): pass\n' > tests/test_foo.py
  printf 'def test_b(): pass\n' > tests/foo_test.py
  _py_scope "foo.py"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: 2 test files)"
  assert_file_contains .venv/bin/pytest.log tests/test_foo.py
  assert_file_contains .venv/bin/pytest.log tests/foo_test.py
}

test_profile_python_pytest_unmapped_module_runs_full_with_reason() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  printf 'a=1\n' > lonely.py
  _py_scope "lonely.py"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
  assert_eq "$(printf '%s' '---')" "$(cat .venv/bin/pytest.log)"
}

test_profile_python_pytest_docs_only_change_skips() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  mkdir -p docs
  printf '# hi\n' > docs/readme.md
  printf '# hi\n' > CHANGES.rst
  _py_scope "docs/readme.md" "CHANGES.rst"
  _py_verify
  _py_unscope
  # pytest is the only tool in the environment and it skips too: nothing
  # produced a pass or fail, so jp_end reports "nothing ran".
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: skip (scope: no changed file maps to a test)"
  assert_no_file .venv/bin/pytest.log
}

test_profile_python_pytest_all_trigger_pyproject_toml() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  _py_scope "pyproject.toml"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
}

test_profile_python_pytest_all_trigger_requirements_dev() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  _py_scope "requirements-dev.txt"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
}

test_profile_python_pytest_all_trigger_requirements_dev_not_masked_by_sibling_on_disk() {
  # Regression: before the fix, PY_ALL_GLOBS ("requirements*.txt" among
  # others) was split with `for g in $LIST` with pathname expansion on, so
  # the word expanded to whatever requirements*.txt sibling sits on disk
  # (here requirements.txt) instead of staying the literal pattern — and a
  # changed requirements-dev.txt (deleted, never created on disk) no longer
  # matched it.
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  : > requirements.txt
  _py_scope "requirements-dev.txt"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
}

test_profile_python_pytest_all_trigger_conftest_in_subdir() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  _py_scope "tests/sub/conftest.py"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
}

test_profile_python_pytest_all_trigger_poetry_lock() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  _py_scope "poetry.lock"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
}

test_profile_python_pytest_exit_5_is_skip_no_tests_collected() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0" 5
  _py_verify
  # A skip is not a pass (RULES.md, ADR-0013): with pytest the only tool
  # present, "no tests collected" leaves nothing that ran, so jp_end exits 2.
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: skip (no tests collected; pytest 7.0.0)"
}

test_profile_python_pytest_failure_fails_profile_and_exits_1() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0" 1
  _py_verify
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: fail (pytest 7.0.0)"
}

# --- pytest: map decisions (JIG_VERIFY_MAPPED) ------------------------------

test_profile_python_pytest_map_filter_wins_over_builtin() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  printf 'a=1\n' > foo.py
  mkdir -p tests
  printf 'def test_c(): pass\n' > tests/custom_test.py
  _py_scope "foo.py"
  _py_map $'foo.py\ttests/custom_test.py'
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: 1 test files)"
  assert_eq "$(printf 'tests/custom_test.py\n---')" "$(cat .venv/bin/pytest.log)"
}

test_profile_python_pytest_map_dash_excludes_the_file() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  printf 'a=1\n' > foo.py
  _py_scope "foo.py"
  _py_map $'foo.py\t-'
  _py_verify
  _py_unscope
  # pytest is the only tool present and skips: nothing ran (jp_end).
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: skip (scope: no changed file maps to a test)"
  assert_no_file .venv/bin/pytest.log
}

test_profile_python_pytest_map_all_forces_full_run() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  mkdir -p tests
  printf 'def test_a(): pass\n' > tests/test_foo.py
  _py_scope "tests/test_foo.py"
  _py_map $'tests/test_foo.py\tALL'
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
  assert_eq "$(printf '%s' '---')" "$(cat .venv/bin/pytest.log)"
}

test_profile_python_pytest_map_question_mark_falls_back_to_builtin_rule() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  mkdir -p tests
  printf 'def test_a(): pass\n' > tests/test_foo.py
  _py_scope "tests/test_foo.py"
  _py_map $'tests/test_foo.py\t?'
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: 1 test files)"
  assert_eq "$(printf 'tests/test_foo.py\n---')" "$(cat .venv/bin/pytest.log)"
}

# A map filter naming a file that does not exist selects no test: the
# narrowing is void, not a pass over nothing (ADR-0041).
test_profile_python_pytest_map_filter_naming_missing_file_runs_full_with_reason() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  printf 'a=1\n' > foo.py
  _py_scope "foo.py"
  _py_map $'foo.py\ttests/does_not_exist_test.py'
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "python: pytest: pass (pytest 7.0.0, scope: filter 'tests/does_not_exist_test.py' selects no tests, ran full set)"
  assert_eq "$(printf '%s' '---')" "$(cat .venv/bin/pytest.log)"
}

# --- IFS regression: ruff's own file-list narrowing must not corrupt -------
# --- pytest's later scope decision (_jp_decide_raw / jp_path_matches) ------
# Before the fix, a profile narrowing a check to a changed-file list did
# `IFS='<newline>'; set -f; set -- $files; set +f` and then left IFS as
# that literal newline instead of restoring the default — so every
# space-separated split a LATER check in the same run needed (a project
# map decision naming two filters on one line, or a multi-word always-ALL
# glob list) silently broke. ruff runs before pytest in this profile, so
# these two tests exercise it taking the changed-file-list path first.

test_profile_python_pytest_map_decision_two_filters_after_ruff_file_list_path() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0"
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  mkdir -p pkg tests
  printf 'a=1\n' > pkg/foo.py
  printf 'def test_a(): pass\n' > tests/test_a.py
  printf 'def test_b(): pass\n' > tests/test_b.py
  _py_scope "pkg/foo.py"
  _py_map $'pkg/foo.py\ttests/test_a.py tests/test_b.py'
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.0.0, scope: 1 files)"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: 2 test files)"
  assert_file_contains .venv/bin/pytest.log tests/test_a.py
  assert_file_contains .venv/bin/pytest.log tests/test_b.py
}

test_profile_python_pytest_runs_full_after_ruff_file_list_path_with_conftest() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0"
  _py_stub "$PWD/.venv/bin/pytest" "pytest 7.0.0"
  mkdir -p pkg
  printf 'a=1\n' > pkg/foo.py
  : > conftest.py
  _py_scope "pkg/foo.py" "conftest.py"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.0.0, scope: 2 files)"
  assert_contains "$OUT" "python: pytest: pass (pytest 7.0.0, scope: not narrowable, ran full set)"
}

# --- version in every verdict -------------------------------------------------

test_profile_python_every_verdict_names_the_tool_version() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.2.3"
  _py_stub "$PWD/.venv/bin/pytest" "pytest 4.5.6"
  printf '[mypy]\n' > mypy.ini
  _py_stub "$PWD/.venv/bin/mypy" "mypy 7.8.9"
  _py_verify
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.2.3)"
  assert_contains "$OUT" "python: mypy: pass (mypy 7.8.9)"
  assert_contains "$OUT" "python: pytest: pass (pytest 4.5.6)"
}

# --- a path with a space is passed to the tool as one argument -------------

test_profile_python_ruff_scoped_path_with_a_space_stays_one_argument() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_stub "$PWD/.venv/bin/ruff" "ruff 1.0.0"
  printf 'a=1\n' > "my file.py"
  _py_scope "my file.py"
  _py_verify
  _py_unscope
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.0.0, scope: 1 files)"
  assert_eq "$(printf 'check\nmy file.py\n---')" "$(cat .venv/bin/ruff.log)"
}

# --- overall exit code (contract: 2 when nothing could run) ----------------

test_profile_python_exits_2_when_every_check_is_skipped() {
  fixture_repo
  unset VIRTUAL_ENV
  _py_verify
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: skip"
  assert_contains "$OUT" "python: mypy: skip"
  assert_contains "$OUT" "python: pytest: skip"
}
