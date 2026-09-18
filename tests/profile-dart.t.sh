# Tests for the dart profile (profiles/dart/verify.sh; design.md D2/D4/D5;
# adr-20260918-profiles-narrow-per-check-with-project-tools). Runs the profile script directly rather than through `jig
# verify`, setting JIG_VERIFY_SCOPE/JIG_VERIFY_FILES/JIG_VERIFY_MAPPED the
# way `jig verify` does (ADR-0013, ADR-0041), so each test controls its own
# scope without a full init. This file is sourced alone (tests/run.sh), so
# it carries its own fixtures and stubs rather than reusing
# tests/verify.t.sh's.
# shellcheck shell=bash

# --- fixtures and stubs ------------------------------------------------------

# dart_fixture [flutter] — a minimal pubspec.yaml (a plain Dart package, or
# one declaring a Flutter SDK dependency when "flutter" is given), plus the
# lib/ and test/ directories a test plants files under.
dart_fixture() {
  mkdir -p lib test
  if [ "${1:-}" = flutter ]; then
    cat > pubspec.yaml <<'EOF'
name: my_flutter_app
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
EOF
  else
    cat > pubspec.yaml <<'EOF'
name: my_pkg
environment:
  sdk: '>=3.0.0 <4.0.0'
EOF
  fi
}

# dart_stub_tool <name> [<rc-analyze>] [<rc-format>] [<rc-test>] — a
# `<name>` stub on PATH (dart or flutter) that logs each subcommand's
# arguments to "<name>-<subcommand>.args" (one line, space-joined; empty
# for no extra arguments) and exits with the code configured for that
# subcommand (0 when omitted). `<name> --version` answers a fixed string
# without touching any log.
dart_stub_tool() {
  local name="$1" rc_analyze="${2:-0}" rc_format="${3:-0}" rc_test="${4:-0}"
  mkdir -p stub-bin
  cat > "stub-bin/$name" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s stub-version\n' "$name"
  exit 0
fi
sub="\$1"
shift
printf '%s\n' "\$*" >> "\$PWD/$name-\$sub.args"
case "\$sub" in
  analyze) exit $rc_analyze ;;
  format) exit $rc_format ;;
  test) exit $rc_test ;;
esac
exit 0
STUB
  chmod +x "stub-bin/$name"
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# The tools scripts/lib/profile.sh and profiles/dart/verify.sh actually use
# once dart and flutter are out of the picture — matches
# tests/verify.t.sh's _NO_TOOLS_LIST, minus the point of this list: neither
# dart nor flutter is ever on it.
_DART_NO_TOOLS_LIST="bash sh sed awk grep find mktemp cat cp mv rm mkdir sort tr head tail wc chmod ls date dirname basename cmp paste stat readlink diff env"

# dart_notools_path — a directory of wrapper scripts for every tool in
# _DART_NO_TOOLS_LIST, resolved through `env -i` so a shell alias cannot
# leak in as a self-referential symlink (conventions/shell.md). No `dart`
# or `flutter` wrapper is ever created.
dart_notools_path() {
  local dir="${JIG_TEST_TMP}.dart-notools" t p
  mkdir -p "$dir"
  for t in $_DART_NO_TOOLS_LIST; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*)
        printf '#!/bin/sh\nexec %s "$@"\n' "$p" > "$dir/$t"
        chmod +x "$dir/$t"
        ;;
    esac
  done
  printf '%s\n' "$dir"
}

# dart_scope <files> — export JIG_VERIFY_SCOPE/JIG_VERIFY_FILES for a
# narrowed run; <files> is the changed-path list, one per line.
dart_scope() {
  printf '%s\n' "$1" > "${JIG_TEST_TMP}.dart-files"
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="${JIG_TEST_TMP}.dart-files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
}

# dart_mapped <tsv> — export JIG_VERIFY_MAPPED with the given
# "<path><TAB><decision>" lines (already formatted, one per line).
dart_mapped() {
  printf '%s\n' "$1" > "${JIG_TEST_TMP}.dart-mapped"
  JIG_VERIFY_MAPPED="${JIG_TEST_TMP}.dart-mapped"
  export JIG_VERIFY_MAPPED
}

dart_verify() {
  run bash "$JIG_HOME/profiles/dart/verify.sh"
}

# --- detect ------------------------------------------------------------------

test_profile_dart_detect_pubspec_yaml_is_dart() {
  mkdir -p fx
  : > fx/pubspec.yaml
  run bash -c '
    JIG_LIB="$1/scripts/lib"
    JIG_PROJECT="$2"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_LIB/../../profiles"
  ' _ "$JIG_HOME" "$PWD/fx"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic"
  assert_contains "$OUT" "dart"
  assert_not_contains "$OUT" "ruby"
  assert_not_contains "$OUT" "go"
}

# --- toolchain absent: skip every check, one reason each -------------------

test_profile_dart_skips_everything_without_toolchain() {
  dart_fixture
  local bin
  bin=$(dart_notools_path)
  PATH="$bin" dart_verify
  assert_eq 2 "$RC"
  assert_contains "$OUT" "dart: analyze: skip (dart not found on PATH)"
  assert_contains "$OUT" "dart: format: skip (dart not found on PATH)"
  assert_contains "$OUT" "dart: test: skip (dart not found on PATH)"
}

# --- flutter detection (sdk: flutter) --------------------------------------

test_profile_dart_flutter_project_uses_flutter_and_skips_format_without_dart() {
  dart_fixture flutter
  local bin
  bin=$(dart_notools_path)
  dart_stub_tool flutter 0 0 0
  PATH="$PWD/stub-bin:$bin" dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: analyze: pass (flutter stub-version)"
  assert_contains "$OUT" "dart: format: skip (dart not found on PATH)"
  assert_contains "$OUT" "dart: test: pass (flutter stub-version)"
}

# --- analyze / format / test: pass, fail, version in the verdict ----------

test_profile_dart_analyze_pass_and_fail_name_version() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: analyze: pass (dart stub-version)"

  dart_stub_tool dart 1 0 0
  dart_verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "dart: analyze: fail (dart stub-version)"
}

test_profile_dart_format_pass_and_fail_name_version() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: format: pass (dart stub-version)"
  assert_eq "--output=none --set-exit-if-changed ." "$(cat dart-format.args)"

  dart_stub_tool dart 0 1 0
  dart_verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "dart: format: fail (dart stub-version)"
}

test_profile_dart_test_pass_and_fail_name_version() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: test: pass (dart stub-version)"

  dart_stub_tool dart 0 0 1
  dart_verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "dart: test: fail (dart stub-version)"
}

# --- analyze / format narrowing (D4: changed .dart files as arguments) ----

test_profile_dart_analyze_and_format_narrow_to_changed_dart_files() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  printf 'int add(int a, int b) => a + b;\n' > lib/math.dart
  printf '# fixture\n' > README.md
  dart_scope "$(printf 'lib/math.dart\nREADME.md\n')"
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: analyze: pass (dart stub-version, scope: 1 files)"
  assert_eq "lib/math.dart" "$(cat dart-analyze.args)"
  assert_contains "$OUT" "dart: format: pass (dart stub-version, scope: 1 files)"
  assert_eq "--output=none --set-exit-if-changed lib/math.dart" "$(cat dart-format.args)"
}

test_profile_dart_analyze_and_format_scope_selects_nothing_skips() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  printf '# fixture\n' > README.md
  dart_scope "README.md"
  dart_verify
  assert_eq 2 "$RC"
  assert_contains "$OUT" "dart: analyze: skip (scope: no changed .dart files)"
  assert_contains "$OUT" "dart: format: skip (scope: no changed .dart files)"
  assert_contains "$OUT" "dart: test: skip (scope: no changed file maps to a test)"
}

test_profile_dart_full_run_when_pubspec_changes() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  dart_scope "pubspec.yaml"
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: analyze: pass (dart stub-version, scope: pubspec or analysis options changed, whole project)"
  assert_eq "" "$(cat dart-analyze.args)"
  assert_contains "$OUT" "dart: format: pass (dart stub-version, scope: pubspec or analysis options changed, whole project)"
  assert_eq "--output=none --set-exit-if-changed ." "$(cat dart-format.args)"
  assert_contains "$OUT" "dart: test: pass (dart stub-version, scope: not narrowable, ran full set)"
  assert_eq "" "$(cat dart-test.args)"
}

# --- test narrowing (D4: lib/a/b.dart -> test/a/b_test.dart; *_test.dart itself) -

test_profile_dart_test_narrows_lib_file_to_matching_test_file() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  mkdir -p test
  printf 'int add(int a, int b) => a + b;\n' > lib/math.dart
  printf 'void main() {}\n' > test/math_test.dart
  dart_scope "lib/math.dart"
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: test: pass (dart stub-version, scope: 1 test files)"
  assert_eq "test/math_test.dart" "$(cat dart-test.args)"
}

test_profile_dart_changed_test_file_maps_to_itself() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  printf 'void main() {}\n' > test/math_test.dart
  dart_scope "test/math_test.dart"
  dart_verify
  assert_eq 0 "$RC"
  assert_eq "test/math_test.dart" "$(cat dart-test.args)"
}

test_profile_dart_test_missing_target_falls_back_to_full_run() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  printf 'int x = 1;\n' > lib/nomatch.dart
  dart_scope "lib/nomatch.dart"
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: test: pass (dart stub-version, scope: filter 'test/nomatch_test.dart' selects no tests, ran full set)"
  assert_eq "" "$(cat dart-test.args)"
}

# --- project map (ADR-0041, D5: filters are test file paths) --------------

test_profile_dart_map_filter_overrides_builtin_mapping() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  printf 'int add(int a, int b) => a + b;\n' > lib/math.dart
  printf 'void main() {}\n' > test/custom_test.dart
  dart_scope "lib/math.dart"
  dart_mapped "$(printf 'lib/math.dart\ttest/custom_test.dart')"
  dart_verify
  assert_eq 0 "$RC"
  assert_eq "test/custom_test.dart" "$(cat dart-test.args)"
}

# --- IFS regression: analyze/format's own file-list narrowing must not -----
# --- corrupt test's later scope decision (_jp_decide_raw) ------------------
# Before the fix, a profile narrowing a check to a changed-file list did
# `IFS='<newline>'; set -f; set -- $files; set +f` and then left IFS as
# that literal newline instead of restoring the default. analyze and
# format both run before test in this profile.

test_profile_dart_test_full_after_analyze_and_format_file_list_path() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  printf 'int add(int a, int b) => a + b;\n' > lib/a.dart
  dart_scope "$(printf 'lib/a.dart\npubspec.yaml\n')"
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: test: pass (dart stub-version, scope: not narrowable, ran full set)"
}

# A map decision naming two filters on one line, after analyze took the
# changed-file-list path for a single changed .dart file (not a
# project-wide one, so analyze/format actually narrow instead of running
# whole-project): the strongest reproduction of the reported bug, since a
# two-filter decision only splits correctly when the later check's own IFS
# is still the default, not whatever analyze left behind.
test_profile_dart_test_map_decision_two_filters_after_analyze_file_list_path() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  mkdir -p test
  printf 'int add(int a, int b) => a + b;\n' > lib/math.dart
  printf 'void main() {}\n' > test/math_a_test.dart
  printf 'void main() {}\n' > test/math_b_test.dart
  dart_scope "lib/math.dart"
  dart_mapped "$(printf 'lib/math.dart\ttest/math_a_test.dart test/math_b_test.dart')"
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: analyze: pass (dart stub-version, scope: 1 files)"
  assert_contains "$OUT" "dart: test: pass (dart stub-version, scope: 2 test files)"
  assert_eq "test/math_a_test.dart test/math_b_test.dart" "$(cat dart-test.args)"
}

test_profile_dart_map_dash_selects_nothing_skips() {
  dart_fixture
  dart_stub_tool dart 0 0 0
  printf 'int add(int a, int b) => a + b;\n' > lib/math.dart
  dart_scope "lib/math.dart"
  dart_mapped "$(printf 'lib/math.dart\t-')"
  dart_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dart: test: skip (scope: no changed file maps to a test)"
}
