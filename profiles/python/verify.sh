#!/usr/bin/env bash
# Verification for the python profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "python: <check>: pass|fail|skip (<note>)".
#
# Tools come from the project's own environment only (adr-20260918-profiles-narrow-per-check-with-project-tools): the active
# $VIRTUAL_ENV, then .venv/ or venv/ (bin/ on Unix, Scripts/ on Windows),
# then the poetry environment when the project has poetry.lock. A global
# pytest or ruff is never used — another version with other plugins says
# nothing about this project.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools), per check: ruff lints the changed .py
# files; mypy always runs in full, because checking a file alone misses
# errors in the unchanged code that calls it; pytest runs the test files the
# changed paths map to — a changed test file itself, or test_<stem>.py /
# <stem>_test.py for a changed <stem>.py — and everything when a path maps
# to nothing or a project-wide file changed.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin python

# Files whose change can alter the result of any test.
PY_ALL_GLOBS="pyproject.toml requirements*.txt setup.py setup.cfg Pipfile Pipfile.lock poetry.lock uv.lock tox.ini pytest.ini conftest.py */conftest.py"

# _py_poetry_env — the poetry environment's directory, when the project uses
# poetry and poetry is installed; nothing otherwise.
_py_poetry_env() {
  [ -f poetry.lock ] || return 0
  command -v poetry >/dev/null 2>&1 || return 0
  poetry env info -p 2>/dev/null | sed -n '1p' || true
}

# _py_tool <name> — the path of <name> in the project's environment, or
# nothing. Both layouts are probed on every machine: the question is what
# the environment contains, not which OS this is (ADR-0037).
_py_tool() {
  local name="$1" d b
  for d in "${VIRTUAL_ENV:-}" .venv venv "$(_py_poetry_env)"; do
    [ -n "$d" ] || continue
    for b in bin Scripts; do
      if [ -f "$d/$b/$name" ]; then
        printf '%s\n' "$d/$b/$name"
        return 0
      fi
      if [ -f "$d/$b/$name.exe" ]; then
        printf '%s\n' "$d/$b/$name.exe"
        return 0
      fi
    done
  done
  return 0
}

PY_WHERE="not found in \$VIRTUAL_ENV, .venv, venv or the poetry environment"

# _py_is_test <path> — a pytest test file by pytest's default naming.
_py_is_test() {
  case "${1##*/}" in
    test_*.py|*_test.py) return 0 ;;
  esac
  return 1
}

# _py_tests_named <stem> — the project's test files named after a module.
# Not inlined into a `$( )`: bash 3.2 misparses a `case` written there.
_py_tests_named() {
  local g
  while IFS= read -r g; do
    case "${g##*/}" in
      "test_$1.py"|"${1}_test.py") printf '%s\n' "$g" ;;
    esac
  done < <(jp_files)
  return 0
}

# _py_builtin <path> — the tests a changed path needs: itself for a test
# file, the test files named after a module, ALL for a project-wide file or
# anything that maps to nothing, nothing for documentation.
_py_builtin() {
  local f="$1" g stem hits
  if jp_path_matches "$f" "$PY_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  case "$f" in
    *.md|*.rst|docs/*|.ai/*) return 0 ;;
  esac
  case "$f" in
    *.py) ;;
    *) printf 'ALL\n'; return 0 ;;
  esac
  if _py_is_test "$f"; then
    printf '%s\n' "$f"
    return 0
  fi
  stem=${f##*/}
  stem=${stem%.py}
  hits=$(_py_tests_named "$stem")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
  else
    printf 'ALL\n'
  fi
  return 0
}

# --- ruff --------------------------------------------------------------------

ruff=$(_py_tool ruff)
if [ -z "$ruff" ]; then
  jp_skip "ruff" "$PY_WHERE"
else
  v=$(jp_version "$ruff" --version)
  if jp_scoped && ! jp_changed_any pyproject.toml ruff.toml .ruff.toml; then
    files=$(jp_changed py)
    if [ -z "$files" ]; then
      jp_skip "ruff" "scope: no changed .py files"
    else
      n=$(printf '%s\n' "$files" | grep -c .)
      # One argument per line, so a path with a space stays one path.
      IFS='
'
      set -f
      # shellcheck disable=SC2086
      set -- $files
      set +f
      IFS=$' \t\n'
      jp_run "ruff" "$v, scope: $n files" "$ruff" check "$@"
    fi
  elif jp_scoped; then
    jp_run "ruff" "$v, scope: ruff configuration changed, whole project" "$ruff" check .
  else
    jp_run "ruff" "$v" "$ruff" check .
  fi
fi

# --- mypy --------------------------------------------------------------------

# mypy runs only where the project configured it: without a configuration it
# reports on code nobody asked it to type-check.
_py_mypy_configured() {
  if [ -f mypy.ini ] || [ -f .mypy.ini ]; then return 0; fi
  if [ -f pyproject.toml ] && grep -q '^\[tool\.mypy\]' pyproject.toml; then return 0; fi
  if [ -f setup.cfg ] && grep -q '^\[mypy\]' setup.cfg; then return 0; fi
  return 1
}

mypy=$(_py_tool mypy)
if [ -z "$mypy" ]; then
  jp_skip "mypy" "$PY_WHERE"
elif ! _py_mypy_configured; then
  jp_skip "mypy" "not configured: no mypy.ini, .mypy.ini, [tool.mypy] or [mypy] in setup.cfg"
else
  v=$(jp_version "$mypy" --version)
  note="$v"
  if jp_scoped; then note="$v, scope: not narrowable, ran full set"; fi
  # The virtualenv lives inside the project; mypy would otherwise walk it.
  jp_run "mypy" "$note" "$mypy" . --exclude '(^|/)(\.venv|venv)/'
fi

# --- pytest ------------------------------------------------------------------

# _py_pytest <note> [<path>...] — pytest, with exit 5 ("no tests collected")
# reported as a skip: a run that collected nothing proved nothing.
_py_pytest() {
  local note="$1" rc=0
  shift
  "$pytest" "$@" || rc=$?
  case "$rc" in
    0) jp_pass "pytest" "$note" ;;
    5) jp_skip "pytest" "no tests collected${note:+; $note}" ;;
    *) jp_fail "pytest" "$note" ;;
  esac
}

pytest=$(_py_tool pytest)
if [ -z "$pytest" ]; then
  jp_skip "pytest" "$PY_WHERE"
else
  v=$(jp_version "$pytest" --version)
  if ! jp_scoped; then
    _py_pytest "$v"
  else
    filters=$(jp_decide _py_builtin)
    if [ -z "$filters" ]; then
      jp_skip "pytest" "scope: no changed file maps to a test"
    elif [ "$filters" = ALL ]; then
      _py_pytest "$v, scope: not narrowable, ran full set"
    else
      IFS='
'
      set -f
      # shellcheck disable=SC2086
      set -- $filters
      set +f
      IFS=$' \t\n'
      if missing=$(jp_first_missing "$@"); then
        _py_pytest "$v, scope: filter '$missing' selects no tests, ran full set"
      else
        _py_pytest "$v, scope: $# test files" "$@"
      fi
    fi
  fi
fi

jp_end
