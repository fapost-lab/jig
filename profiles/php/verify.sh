#!/usr/bin/env bash
# Verification for the php profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "php: <check>: pass|fail|skip (<note>)".
#
# Tools come from the project's own environment only (adr-20260918-profiles-narrow-per-check-with-project-tools): phpunit,
# pest, phpstan and pint are read from vendor/bin/ and nowhere else — a
# global install would check the project with another version and other
# rules. composer is the stack's own toolchain and comes from PATH.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools), per check: phpstan and pint each lint the
# changed .php files; phpstan runs in full when its own configuration
# changed. phpunit/pest run the test files the changed paths map to — a
# changed *Test.php itself, or any FooTest.php under tests/ for a changed
# Foo.php — and everything when a path maps to nothing or a file that can
# affect any test (composer.json/lock, phpunit.xml*) changed. composer
# validate is not narrowable by files: in a scoped run it runs only when
# composer.json or composer.lock changed, and skips with a reason otherwise;
# in a full run it always runs.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin php

PHP_WHERE="not found in vendor/bin"

# _php_tool <name> — the path of <name> in vendor/bin/, Unix and Windows
# layouts both probed by what exists, never by OS name (ADR-0037).
_php_tool() {
  local name="$1" b
  for b in "" .bat .exe; do
    if [ -f "vendor/bin/$name$b" ]; then
      printf 'vendor/bin/%s%s\n' "$name" "$b"
      return 0
    fi
  done
  return 0
}

# _php_is_test <path> — a PHPUnit/Pest test file by the stack's own naming
# convention.
_php_is_test() {
  case "${1##*/}" in
    *Test.php) return 0 ;;
  esac
  return 1
}

# _php_tests_named <stem> — the project's test files under tests/ named
# after a module. Not inlined into a `$( )`: bash 3.2 misparses a `case`
# written there.
_php_tests_named() {
  local g
  while IFS= read -r g; do
    case "$g" in
      tests/*) ;;
      *) continue ;;
    esac
    case "${g##*/}" in
      "${1}Test.php") printf '%s\n' "$g" ;;
    esac
  done < <(jp_files)
  return 0
}

# Files whose change can alter the result of any test: the dependency
# manifest/lock (autoloading) and PHPUnit's own configuration.
PHP_TEST_ALL_GLOBS="composer.json composer.lock phpunit.xml*"

# _php_builtin <path> — the tests a changed path needs: itself for a test
# file, the tests/*Test.php files named after a module, ALL for a
# project-wide file or anything that maps to nothing, nothing for
# documentation.
_php_builtin() {
  local f="$1" g stem hits
  if jp_path_matches "$f" "$PHP_TEST_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  case "$f" in
    *.md|*.rst|docs/*|.ai/*) return 0 ;;
  esac
  case "$f" in
    *.php) ;;
    *) printf 'ALL\n'; return 0 ;;
  esac
  if _php_is_test "$f"; then
    printf '%s\n' "$f"
    return 0
  fi
  stem=${f##*/}
  stem=${stem%.php}
  hits=$(_php_tests_named "$stem")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
  else
    printf 'ALL\n'
  fi
  return 0
}

# --- phpunit / pest ------------------------------------------------------

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  test_bin=$(_php_tool phpunit)
  test_check=phpunit
  if [ -z "$test_bin" ]; then
    test_bin=$(_php_tool pest)
    test_check=pest
  fi
  if [ -z "$test_bin" ]; then
    jp_plan phpunit skip "$PHP_WHERE"
  else
    filters=$(jp_decide _php_builtin)
    if [ -n "$filters" ] && [ "$filters" != ALL ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ ! -e "$f" ]; then filters=ALL; break; fi
      done <<EOF
$filters
EOF
    fi
    jp_plan_selection "$test_check" "$filters" "test files"
  fi

  for check in phpstan pint; do
    tool=$(_php_tool "$check")
    if [ -z "$tool" ]; then
      jp_plan "$check" skip "$PHP_WHERE"
    elif [ "$check" = phpstan ] && jp_scoped && jp_changed_any phpstan.neon phpstan.neon.dist; then
      jp_plan "$check" full "phpstan configuration changed"
    elif jp_scoped; then
      files=$(jp_changed php)
      if [ -z "$files" ]; then
        jp_plan "$check" skip "no changed .php files"
      else
        jp_plan "$check" filtered "changed .php files: $(printf '%s\n' "$files" | paste -sd, -)"
      fi
    else
      jp_plan "$check" full "full scope"
    fi
  done

  if ! command -v composer >/dev/null 2>&1; then
    jp_plan "composer validate" skip "composer not found in PATH"
  elif jp_scoped && ! jp_changed_any composer.json composer.lock; then
    jp_plan "composer validate" skip "composer.json/composer.lock not changed"
  else
    jp_plan "composer validate" full "manifest validation"
  fi
  exit 0
fi

test_bin=$(_php_tool phpunit)
test_check=phpunit
if [ -z "$test_bin" ]; then
  test_bin=$(_php_tool pest)
  test_check=pest
fi

if [ -z "$test_bin" ]; then
  jp_skip "phpunit" "$PHP_WHERE"
else
  v=$(jp_version "$test_bin" --version)
  if ! jp_scoped; then
    jp_run "$test_check" "$v" "$test_bin"
  else
    filters=$(jp_decide _php_builtin)
    if [ -z "$filters" ]; then
      jp_skip "$test_check" "scope: no changed file maps to a test"
    elif [ "$filters" = ALL ]; then
      jp_run "$test_check" "$v, scope: not narrowable, ran full set" "$test_bin"
    else
      IFS='
'
      set -f
      # shellcheck disable=SC2086
      set -- $filters
      set +f
      IFS=$' \t\n'
      if missing=$(jp_first_missing "$@"); then
        jp_run "$test_check" "$v, scope: filter '$missing' selects no tests, ran full set" "$test_bin"
      else
        jp_run "$test_check" "$v, scope: $# test files" "$test_bin" "$@"
      fi
    fi
  fi
fi

# --- phpstan ---------------------------------------------------------------

phpstan=$(_php_tool phpstan)
if [ -z "$phpstan" ]; then
  jp_skip "phpstan" "$PHP_WHERE"
else
  v=$(jp_version "$phpstan" --version)
  if jp_scoped && ! jp_changed_any phpstan.neon phpstan.neon.dist; then
    files=$(jp_changed php)
    if [ -z "$files" ]; then
      jp_skip "phpstan" "scope: no changed .php files"
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
      jp_run "phpstan" "$v, scope: $n files" "$phpstan" analyse --no-progress "$@"
    fi
  elif jp_scoped; then
    jp_run "phpstan" "$v, scope: phpstan configuration changed, whole project" "$phpstan" analyse --no-progress
  else
    jp_run "phpstan" "$v" "$phpstan" analyse --no-progress
  fi
fi

# --- pint --------------------------------------------------------------------

pint=$(_php_tool pint)
if [ -z "$pint" ]; then
  jp_skip "pint" "$PHP_WHERE"
else
  v=$(jp_version "$pint" --version)
  if jp_scoped; then
    files=$(jp_changed php)
    if [ -z "$files" ]; then
      jp_skip "pint" "scope: no changed .php files"
    else
      n=$(printf '%s\n' "$files" | grep -c .)
      IFS='
'
      set -f
      # shellcheck disable=SC2086
      set -- $files
      set +f
      IFS=$' \t\n'
      jp_run "pint" "$v, scope: $n files" "$pint" --test "$@"
    fi
  else
    jp_run "pint" "$v" "$pint" --test
  fi
fi

# --- composer validate -------------------------------------------------------
# Not narrowable by files: composer.json describes the whole project. Runs
# always in full mode; in a scoped run, only when the manifest or lock file
# it validates actually changed.

if command -v composer >/dev/null 2>&1; then
  v=$(jp_version composer --version)
  if jp_scoped && ! jp_changed_any composer.json composer.lock; then
    jp_skip "composer validate" "scope: composer.json/composer.lock not changed"
  else
    jp_run "composer validate" "$v" composer validate --no-check-publish
  fi
else
  jp_skip "composer validate" "composer not found in PATH"
fi

jp_end
