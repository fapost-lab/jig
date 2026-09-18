#!/usr/bin/env bash
# Verification for the dart profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "dart: <check>: pass|fail|skip (<note>)".
#
# The stack toolchain comes from PATH (adr-20260918-profiles-narrow-per-check-with-project-tools, D2): `flutter` for a
# Flutter project (pubspec.yaml declares `sdk: flutter` under a
# dependency), `dart` otherwise. `dart format` is always the `dart` binary,
# even in a Flutter project, because `flutter format` does not exist as a
# subcommand; a project with only `flutter` on PATH (no plain `dart`) skips
# the format check.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools), per check: analyze and format take the
# changed .dart files as arguments; test runs the test files the changed
# paths map to — a changed *_test.dart itself, or test/a/b_test.dart for a
# changed lib/a/b.dart — and everything when a path maps to nothing or a
# project-wide file changed.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin dart

# Files whose change can alter the result of any check.
DART_ALL_GLOBS="pubspec.yaml pubspec.lock analysis_options.yaml"

# _dart_is_flutter — whether pubspec.yaml declares a dependency on the
# Flutter SDK, the one signal that decides which binary runs the checks.
_dart_is_flutter() {
  [ -f pubspec.yaml ] || return 1
  grep -qE 'sdk:[[:space:]]*flutter' pubspec.yaml
}

DART_RUNNER=dart
if _dart_is_flutter; then
  DART_RUNNER=flutter
fi

# --- analyze ---------------------------------------------------------------

if ! command -v "$DART_RUNNER" >/dev/null 2>&1; then
  jp_skip analyze "$DART_RUNNER not found on PATH"
else
  v=$(jp_version "$DART_RUNNER" --version)
  if jp_scoped && ! jp_changed_any pubspec.yaml pubspec.lock analysis_options.yaml; then
    files=$(jp_changed dart)
    if [ -z "$files" ]; then
      jp_skip analyze "scope: no changed .dart files"
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
      jp_run analyze "$v, scope: $n files" "$DART_RUNNER" analyze "$@"
    fi
  elif jp_scoped; then
    jp_run analyze "$v, scope: pubspec or analysis options changed, whole project" "$DART_RUNNER" analyze
  else
    jp_run analyze "$v" "$DART_RUNNER" analyze
  fi
fi

# --- format ------------------------------------------------------------------

# `dart format` is bundled with the Dart SDK, and the Flutter SDK bundles
# its own copy of `dart` too, so a project with either toolchain installed
# ordinarily has it; a project with only a bare `flutter` shim on PATH does
# not, and the check skips rather than guessing at `flutter format`.
if ! command -v dart >/dev/null 2>&1; then
  jp_skip format "dart not found on PATH"
else
  v=$(jp_version dart --version)
  if jp_scoped && ! jp_changed_any pubspec.yaml pubspec.lock analysis_options.yaml; then
    files=$(jp_changed dart)
    if [ -z "$files" ]; then
      jp_skip format "scope: no changed .dart files"
    else
      n=$(printf '%s\n' "$files" | grep -c .)
      IFS='
'
      set -f
      # shellcheck disable=SC2086
      set -- $files
      set +f
      IFS=$' \t\n'
      jp_run format "$v, scope: $n files" dart format --output=none --set-exit-if-changed "$@"
    fi
  elif jp_scoped; then
    jp_run format "$v, scope: pubspec or analysis options changed, whole project" dart format --output=none --set-exit-if-changed .
  else
    jp_run format "$v" dart format --output=none --set-exit-if-changed .
  fi
fi

# --- test --------------------------------------------------------------------

# _dart_builtin_test <path> — the tests a changed path needs: itself for a
# *_test.dart file, test/<rest>_test.dart for a changed lib/<rest>.dart, ALL
# for a project-wide file or anything that maps to nothing, nothing for
# documentation.
_dart_builtin_test() {
  local f="$1" rest
  if jp_path_matches "$f" "$DART_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  case "$f" in
    *.md|*.rst|docs/*|.ai/*) return 0 ;;
  esac
  case "$f" in
    *.dart) ;;
    *) printf 'ALL\n'; return 0 ;;
  esac
  case "$f" in
    *_test.dart) printf '%s\n' "$f"; return 0 ;;
  esac
  case "$f" in
    lib/*)
      rest=${f#lib/}
      rest=${rest%.dart}
      printf 'test/%s_test.dart\n' "$rest"
      ;;
    *) printf 'ALL\n' ;;
  esac
  return 0
}

if ! command -v "$DART_RUNNER" >/dev/null 2>&1; then
  jp_skip test "$DART_RUNNER not found on PATH"
else
  v=$(jp_version "$DART_RUNNER" --version)
  if ! jp_scoped; then
    jp_run test "$v" "$DART_RUNNER" test
  else
    filters=$(jp_decide _dart_builtin_test)
    if [ -z "$filters" ]; then
      jp_skip test "scope: no changed file maps to a test"
    elif [ "$filters" = ALL ]; then
      jp_run test "$v, scope: not narrowable, ran full set" "$DART_RUNNER" test
    else
      IFS='
'
      set -f
      # shellcheck disable=SC2086
      if missing=$(jp_first_missing $filters); then
        set +f
        IFS=$' \t\n'
        jp_run test "$v, scope: filter '$missing' selects no tests, ran full set" "$DART_RUNNER" test
      else
        n=$(printf '%s\n' "$filters" | grep -c .)
        # shellcheck disable=SC2086
        set -- $filters
        set +f
        IFS=$' \t\n'
        jp_run test "$v, scope: $n test files" "$DART_RUNNER" test "$@"
      fi
    fi
  fi
fi

jp_end
