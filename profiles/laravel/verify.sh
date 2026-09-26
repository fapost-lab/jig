#!/usr/bin/env bash
# Verification for the laravel profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip. Only runs Laravel's
# own test runner; PHPUnit/Pest/PHPStan/Pint/composer validate are the php
# profile's job (requires: [php], domains/verify) and are not duplicated here.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools): the same file-to-test convention as the php
# profile — a changed *Test.php maps to itself, a changed Foo.php maps to
# any FooTest.php under tests/, and a path that maps to nothing or that
# changed a file that can affect any test (composer.json/lock, phpunit.xml*,
# or Laravel's own routes/, config/, database/, bootstrap/) runs the full
# suite. Kept as its own copy rather than shared with the php profile: each
# shipped verify.sh is an independent file (D2/D3), and `requires: [php]`
# is only a runtime activation dependency, not a code-sharing one.
#
# Full-stack is the ordinary shape of a Laravel application, and the rule is
# not "anything that is not .php needs no test". What decides is whether a
# path can change the result of `artisan test`, which runs PHP: a front-end
# source is neither bundled nor served by it, while the build that produces
# the assets a browser test (Dusk) loads is a different matter and keeps the
# full set. The two lists below draw that line; what neither describes still
# runs everything, so an unrecognised path costs time rather than coverage
# (ADR-0013).
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin laravel

# _laravel_is_test <path> — a PHPUnit/Pest test file by the stack's own
# naming convention.
_laravel_is_test() {
  case "${1##*/}" in
    *Test.php) return 0 ;;
  esac
  return 1
}

# _laravel_tests_named <stem> — the project's test files under tests/ named
# after a module. Not inlined into a `$( )`: bash 3.2 misparses a `case`
# written there.
_laravel_tests_named() {
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
# manifest/lock (autoloading), PHPUnit's own configuration, and the
# framework's own always-loaded directories.
LARAVEL_TEST_ALL_GLOBS="composer.json composer.lock phpunit.xml* routes/* config/* database/* bootstrap/*"

# Files that define how the front end is built: the package manifest, its
# lock file, and the bundler's configuration. A change to one can alter every
# built asset, and `artisan test` runs a project's browser tests (Dusk) like
# any other — those load the built assets. So the full set runs.
LARAVEL_BUILD_ALL_GLOBS="package.json package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb vite.config.* webpack.mix.js webpack.config.* rollup.config.* tailwind.config.* postcss.config.*"

# Front-end sources. `artisan test` neither bundles nor serves them, so
# changing one cannot change what a test observes. Two kinds of path are
# excluded and fall through to the rules below, because for them it can:
# public/ holds what a browser test actually loads (the built asset, not this
# source), and a file under tests/ may be a fixture or a snapshot a test
# asserts on. resources/views/ is deliberately absent — a Blade template is
# .php and keeps the name analysis below, because it can change a feature
# test's result and no naming convention narrows it.
LARAVEL_FRONTEND_GLOBS="*.vue *.svelte *.js *.mjs *.cjs *.jsx *.ts *.mts *.cts *.tsx *.css *.scss *.sass *.less *.styl resources/images/* resources/fonts/*"
LARAVEL_FRONTEND_NOT_GLOBS="public/* tests/*"

# _laravel_builtin <path> — the tests a changed path needs: itself for a
# test file, the tests/*Test.php files named after a module, ALL for a
# project-wide file or anything that maps to nothing, nothing for
# documentation.
_laravel_builtin() {
  local f="$1" g stem hits
  if jp_path_matches "$f" "$LARAVEL_TEST_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  case "$f" in
    *.md|*.rst|docs/*|.ai/*) return 0 ;;
  esac
  # Before the front-end list, not after it: vite.config.ts matches *.ts
  # there, and the build has to win over the extension.
  if jp_path_matches "$f" "$LARAVEL_BUILD_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  if ! jp_path_matches "$f" "$LARAVEL_FRONTEND_NOT_GLOBS" \
    && jp_path_matches "$f" "$LARAVEL_FRONTEND_GLOBS"; then
    return 0
  fi
  case "$f" in
    *.php) ;;
    *) printf 'ALL\n'; return 0 ;;
  esac
  if _laravel_is_test "$f"; then
    printf '%s\n' "$f"
    return 0
  fi
  stem=${f##*/}
  stem=${stem%.php}
  hits=$(_laravel_tests_named "$stem")
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
  else
    printf 'ALL\n'
  fi
  return 0
}

# _laravel_all_reason <path> — why the full set runs, for the path
# jp_decide_cause named. "not narrowable" was one shrug for four different
# situations, and the person reading it could not tell their package.json
# from a class no test is named after. An empty <path> means the project's
# own map asked for the full set; that line's author knows why, so the old
# wording stands rather than a guess at their reason.
_laravel_all_reason() {
  local f="$1"
  if [ -z "$f" ]; then
    printf 'not narrowable\n'
  elif jp_path_matches "$f" "$LARAVEL_BUILD_ALL_GLOBS"; then
    printf '%s changes the asset build, which browser tests load\n' "$f"
  elif jp_path_matches "$f" "$LARAVEL_TEST_ALL_GLOBS"; then
    printf '%s can affect any test\n' "$f"
  else
    case "$f" in
      *.php) printf 'no test is named after %s\n' "$f" ;;
      *) printf 'the profile cannot map %s to tests\n' "$f" ;;
    esac
  fi
  return 0
}

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  if [ ! -f artisan ] || ! command -v php >/dev/null 2>&1; then
    jp_plan "artisan test" skip "artisan or php not found"
  else
    filters=$(jp_decide _laravel_builtin)
    if [ -n "$filters" ] && [ "$filters" != ALL ]; then
      if missing=$(printf '%s\n' "$filters" | while IFS= read -r f; do
        if [ ! -e "$f" ]; then printf '%s\n' "$f"; break; fi
      done); then
        if [ -n "$missing" ]; then
          filters=ALL
        fi
      fi
    fi
    if [ "$filters" = ALL ]; then
      why=$(_laravel_all_reason "$(jp_decide_cause _laravel_builtin)")
    else
      why=
    fi
    jp_plan_selection "artisan test" "$filters" "test files" "$why"
  fi
  exit 0
fi

if [ ! -f artisan ] || ! command -v php >/dev/null 2>&1; then
  jp_skip "artisan test" "artisan or php not found"
  jp_end
fi

v=$(jp_version php --version)

if ! jp_scoped; then
  jp_run "artisan test" "$v" php artisan test
else
  filters=$(jp_decide _laravel_builtin)
  if [ -z "$filters" ]; then
    jp_skip "artisan test" "scope: no changed file maps to a test"
  elif [ "$filters" = ALL ]; then
    why=$(_laravel_all_reason "$(jp_decide_cause _laravel_builtin)")
    jp_run "artisan test" "$v, scope: $why, ran full set" php artisan test
  else
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    set -- $filters
    set +f
    IFS=$' \t\n'
    if missing=$(jp_first_missing "$@"); then
      jp_run "artisan test" "$v, scope: filter '$missing' selects no tests, ran full set" php artisan test
    else
      jp_run "artisan test" "$v, scope: $# test files" php artisan test "$@"
    fi
  fi
fi

jp_end
