# Tests for the php profile's verify.sh (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools; domains/verify).
# shellcheck shell=bash
#
# Most tests run .ai/profiles/php/verify.sh directly with JIG_VERIFY_SCOPE /
# JIG_VERIFY_FILES / JIG_VERIFY_MAPPED set by hand, the same variables
# `jig verify` itself sets (scripts/lib/verify.sh) — this exercises the
# profile's own narrowing logic without depending on `jig verify`'s map
# parsing or its git-diff computation of "changed". enter_test_env already
# unsets these three (and CI) before every test, so nothing here leaks
# between tests.

_PHP_VERIFY=".ai/profiles/php/verify.sh"

# _php_install — a fixture repository with the php profile installed and a
# composer.json (so `detect` would also find it), no other setup.
_php_install() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles php >/dev/null
  printf '{}\n' > composer.json
}

# _php_stub_tool <name> <version> <rc> <log> — vendor/bin/<name>: answers
# `--version`, otherwise appends the arguments it received (one line, space
# joined) to <log> and exits <rc>.
_php_stub_tool() {
  local name="$1" version="$2" rc="$3" log="$4"
  mkdir -p vendor/bin
  cat > "vendor/bin/$name" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$version"
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
exit $rc
STUB
  chmod +x "vendor/bin/$name"
}

# _composer_stub <version> <rc> <log> — a `composer` on PATH with the same
# shape as _php_stub_tool, since composer is stack toolchain (PATH), not a
# vendor/bin dev tool (adr-20260918-profiles-narrow-per-check-with-project-tools).
_composer_stub() {
  local version="$1" rc="$2" log="$3"
  mkdir -p stub-bin
  cat > stub-bin/composer <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$version"
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
exit $rc
STUB
  chmod +x stub-bin/composer
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _files_list <path>... — a JIG_VERIFY_FILES file naming <path>, one per
# line; prints its name.
_files_list() {
  local f
  f=$(mktemp "$PWD/scope-files.XXXXXX")
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

# _mapped_file <line>... — a JIG_VERIFY_MAPPED file; each <line> is already
# "<path><TAB><decision>" (build with printf '%s\t%s' so the tab is real).
_mapped_file() {
  local f
  f=$(mktemp "$PWD/scope-mapped.XXXXXX")
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

# _php_scoped <files-file> [mapped-file] — run verify.sh narrowed to
# <files-file>, with <mapped-file> as JIG_VERIFY_MAPPED when given.
_php_scoped() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$1"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  if [ -n "${2:-}" ]; then
    JIG_VERIFY_MAPPED="$2"
    export JIG_VERIFY_MAPPED
  else
    unset JIG_VERIFY_MAPPED
  fi
  run bash "$_PHP_VERIFY"
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
}

# _php_no_tools_bin — a fresh directory of wrapper scripts for exactly the
# tools a profile run needs to reach git/bash/coreutils, resolved through
# `env -i` so an aliased `grep` on the developer's shell cannot leak in
# (conventions/shell.md). Not cached across tests (unlike verify.t.sh's
# run_no_tools, which every test file would need its own copy of): each
# test using this builds its own directory, and there is no shared state to
# race on.
_php_no_tools_bin() {
  local dir t p esc
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-php-no-tools.XXXXXX")
  for t in bash sh git sed awk grep find mktemp cat cp mv rm mkdir sort \
           tr head tail wc chmod ls date dirname basename cmp paste stat \
           readlink diff env; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*)
        esc=$(printf '%s' "$p" | sed "s/'/'\\\\''/g")
        {
          printf '#!/bin/sh\n'
          printf "exec '%s' \"\$@\"\n" "$esc"
        } > "$dir/$t"
        chmod +x "$dir/$t"
        ;;
    esac
  done
  printf '%s\n' "$dir"
}

# _php_no_tools <cmd...> — like run, but with PATH stripped to exactly the
# tools above, so composer (and any vendor/bin resolution, which does not
# use PATH at all) is deterministically unreachable regardless of what the
# machine running the tests happens to have installed.
_php_no_tools() {
  local bin
  bin=$(_php_no_tools_bin)
  PATH="$bin" run "$@"
}

# --- detect ------------------------------------------------------------------

test_profile_php_detected_for_composer_json() {
  fixture_repo
  printf '{}\n' > composer.json
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_HOME/profiles"
  '
  assert_eq 0 "$RC"
  assert_contains "$OUT" "php"
}

# --- full mode: unchanged observable behaviour, no tools ---------------------

test_profile_php_full_mode_skips_every_check_without_toolchain() {
  _php_install
  _php_no_tools jig verify --profile php
  # Every check skipped, so the run checked nothing and says so, exit 3
  # (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip (not found in vendor/bin)"
  assert_contains "$OUT" "php: phpstan: skip (not found in vendor/bin)"
  assert_contains "$OUT" "php: pint: skip (not found in vendor/bin)"
  assert_contains "$OUT" "php: composer validate: skip (composer not found in PATH)"
  assert_contains "$OUT" "RESULT php: skip"
}

# --- pass / fail / version per check ------------------------------------------

test_profile_php_phpunit_pass_and_fail_report_version() {
  _php_install
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  run jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9)"

  _php_stub_tool phpunit 9.9.9 1 phpunit.log
  run jig verify --profile php
  assert_eq 1 "$RC"
  assert_contains "$OUT" "php: phpunit: fail (9.9.9)"
}

test_profile_php_pest_fallback_when_phpunit_absent() {
  _php_install
  _php_stub_tool pest 3.1.0 0 pest.log
  run jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: pest: pass (3.1.0)"
  assert_not_contains "$OUT" "php: phpunit:"
}

test_profile_php_phpstan_pass_and_fail_report_version() {
  _php_install
  _php_stub_tool phpstan 1.10.0 0 phpstan.log
  run jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpstan: pass (1.10.0)"

  _php_stub_tool phpstan 1.10.0 1 phpstan.log
  run jig verify --profile php
  assert_eq 1 "$RC"
  assert_contains "$OUT" "php: phpstan: fail (1.10.0)"
}

test_profile_php_pint_pass_and_fail_report_version() {
  _php_install
  _php_stub_tool pint 1.0.0 0 pint.log
  run jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: pint: pass (1.0.0)"

  _php_stub_tool pint 1.0.0 1 pint.log
  run jig verify --profile php
  assert_eq 1 "$RC"
  assert_contains "$OUT" "php: pint: fail (1.0.0)"
}

test_profile_php_composer_validate_pass_and_fail_report_version() {
  _php_install
  _composer_stub 2.7.0 0 composer.log
  run jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: composer validate: pass (2.7.0)"

  _composer_stub 2.7.0 1 composer.log
  run jig verify --profile php
  assert_eq 1 "$RC"
  assert_contains "$OUT" "php: composer validate: fail (2.7.0)"
}

test_profile_php_composer_validate_always_runs_in_full_mode() {
  # Full mode: composer.json/lock did not "change" (there is no scope), and
  # the check still runs — narrowing only applies to a scoped run.
  _php_install
  _composer_stub 2.7.0 0 composer.log
  run jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: composer validate: pass"
  assert_file_contains composer.log "validate"
}

# --- narrowing: phpstan and pint on changed .php files (D4) ------------------

test_profile_php_phpstan_narrowed_to_changed_php_files() {
  _php_install
  mkdir -p src
  : > src/Foo.php
  : > src/Bar.txt
  _php_stub_tool phpstan 1.10.0 0 phpstan.log
  files=$(_files_list src/Foo.php src/Bar.txt)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpstan: pass (1.10.0, scope: 1 files)"
  assert_file_contains phpstan.log "src/Foo.php"
  assert_not_contains "$(cat phpstan.log)" "src/Bar.txt"
}

test_profile_php_phpstan_skips_when_no_changed_php_files() {
  _php_install
  _php_stub_tool phpstan 1.10.0 0 phpstan.log
  files=$(_files_list README.md)

  _php_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpstan: skip (scope: no changed .php files)"
  assert_no_file phpstan.log
}

test_profile_php_pint_narrowed_to_changed_php_files() {
  _php_install
  mkdir -p src
  : > src/Foo.php
  _php_stub_tool pint 1.0.0 0 pint.log
  files=$(_files_list src/Foo.php)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: pint: pass (1.0.0, scope: 1 files)"
  assert_file_contains pint.log "src/Foo.php"
}

test_profile_php_pint_skips_when_no_changed_php_files() {
  _php_install
  _php_stub_tool pint 1.0.0 0 pint.log
  files=$(_files_list README.md)

  _php_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "php: pint: skip (scope: no changed .php files)"
}

# --- always-ALL triggers (D4) --------------------------------------------------

test_profile_php_phpstan_runs_full_when_its_config_changed() {
  _php_install
  _php_stub_tool phpstan 1.10.0 0 phpstan.log
  files=$(_files_list phpstan.neon)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "php: phpstan: pass (1.10.0, scope: phpstan configuration changed, whole project)"
  assert_file_contains phpstan.log "analyse --no-progress"
  assert_not_contains "$(cat phpstan.log)" ".php"
}

test_profile_php_tests_run_full_when_phpunit_xml_changed() {
  _php_install
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list phpunit.xml.dist)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: phpunit.xml.dist can affect any test, ran full set)"
}

test_profile_php_composer_json_change_runs_composer_validate_and_full_tests() {
  # composer.json is this profile's own always-ALL trigger for both
  # `composer validate` (D4's dedicated rule) and the test suite (autoload
  # changes can affect any test), but not for phpstan/pint: no .php file
  # changed, so they skip narrowed rather than running in full.
  _php_install
  _composer_stub 2.7.0 0 composer.log
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  _php_stub_tool phpstan 1.10.0 0 phpstan.log
  _php_stub_tool pint 1.0.0 0 pint.log
  files=$(_files_list composer.json)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: composer validate: pass"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: composer.json can affect any test, ran full set)"
  assert_contains "$OUT" "php: phpstan: skip (scope: no changed .php files)"
  assert_contains "$OUT" "php: pint: skip (scope: no changed .php files)"
}

test_profile_php_composer_validate_skips_when_unchanged_in_scoped_run() {
  _php_install
  mkdir -p src
  : > src/Foo.php
  _composer_stub 2.7.0 0 composer.log
  files=$(_files_list src/Foo.php)

  _php_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "php: composer validate: skip (scope: composer.json/composer.lock not changed)"
  assert_no_file composer.log
}

# --- narrowing: tests (D4: Test.php -> itself, Foo.php -> FooTest.php) -------

test_profile_php_changed_test_file_maps_to_itself() {
  _php_install
  mkdir -p tests
  : > tests/FooTest.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list tests/FooTest.php)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: 1 test files)"
  assert_file_contains phpunit.log "tests/FooTest.php"
}

test_profile_php_changed_source_maps_to_named_test_under_tests() {
  _php_install
  mkdir -p src tests
  : > src/Foo.php
  : > tests/FooTest.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list src/Foo.php)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: 1 test files)"
  assert_file_contains phpunit.log "tests/FooTest.php"
}

test_profile_php_unmapped_source_runs_full_tests() {
  _php_install
  mkdir -p src
  : > src/Orphan.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list src/Orphan.php)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: no test is named after src/Orphan.php, ran full set)"
}

test_profile_php_doc_only_change_skips_tests() {
  _php_install
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list README.md)

  _php_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip (scope: no changed file maps to a test)"
  assert_no_file phpunit.log
}

test_profile_php_missing_selected_test_falls_back_to_full() {
  # The map names a test that no longer exists on disk: a narrowing that
  # selects nothing is not a pass (ADR-0041) — the full set runs instead.
  _php_install
  mkdir -p src
  : > src/Foo.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list src/Foo.php)
  mapped=$(_mapped_file "$(printf 'src/Foo.php\ttests/GoneTest.php')")

  _php_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "php: phpunit: pass (9.9.9, scope: filter 'tests/GoneTest.php' selects no tests, ran full set)"
}

# --- glob-list regression: an always-ALL glob must not be expanded against -
# --- files on disk (jp_path_matches) -----------------------------------------
# Before the fix, PHP_TEST_ALL_GLOBS was split with `for g in $LIST` with
# pathname expansion on, so "phpunit.xml*" could expand to whichever
# phpunit.xml* file happens to sit on disk instead of staying the literal
# pattern the profile wrote.

test_profile_php_phpunit_xml_glob_not_masked_by_sibling_on_disk() {
  _php_install
  : > phpunit.xml
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list phpunit.xml.dist)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: phpunit.xml.dist can affect any test, ran full set)"
}

# --- IFS regression: a map decision naming two filters on one line must ----
# --- still split on the space between them (_jp_decide_raw) ----------------
# Before the fix, a profile that consumed a changed-file list
# (`IFS='<newline>'; set -f; set -- $files; set +f`) left IFS as that
# newline instead of restoring the default, so a later `for tok in
# $decision` split on newline only and a two-filter decision collapsed into
# one token. phpunit is the first check the php profile runs, so this is a
# standalone correctness test for the multi-filter split itself, not a
# reproduction of the order-dependent corruption (see the report).

test_profile_php_phpunit_map_decision_with_two_filters_splits_into_two_args() {
  _php_install
  mkdir -p src tests
  : > src/Foo.php
  : > tests/FooATest.php
  : > tests/FooBTest.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list src/Foo.php)
  mapped=$(_mapped_file "$(printf 'src/Foo.php\ttests/FooATest.php tests/FooBTest.php')")

  _php_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: 2 test files)"
  assert_file_contains phpunit.log "tests/FooATest.php"
  assert_file_contains phpunit.log "tests/FooBTest.php"
}

# --- map filters (D5: a test file path; jig verify never lets a profile ------
# --- parse the map, so these hand the profile the already-decided value) ----

test_profile_php_map_filter_overrides_the_builtin_test_mapping() {
  _php_install
  mkdir -p src tests
  : > src/Foo.php
  : > tests/FooTest.php
  : > tests/CustomTest.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list src/Foo.php)
  mapped=$(_mapped_file "$(printf 'src/Foo.php\ttests/CustomTest.php')")

  _php_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains phpunit.log "tests/CustomTest.php"
  assert_not_contains "$(cat phpunit.log)" "tests/FooTest.php"
}

test_profile_php_map_dash_means_no_test() {
  _php_install
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list docs/change.md)
  mapped=$(_mapped_file "$(printf 'docs/change.md\t-')")

  _php_scoped "$files" "$mapped"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip (scope: no changed file maps to a test)"
}

test_profile_php_map_question_mark_falls_back_to_builtin() {
  _php_install
  mkdir -p src tests
  : > src/Foo.php
  : > tests/FooTest.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list src/Foo.php)
  mapped=$(_mapped_file "$(printf 'src/Foo.php\t?')")

  _php_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains phpunit.log "tests/FooTest.php"
}

# --- front end: what can and cannot change the result of the test run --------
# The same cut as the laravel profile, for the same reason: phpunit runs PHP
# and neither bundles a front-end source nor serves it, while the build that
# produces the assets a browser test loads is a different matter. Both halves
# are asserted, because a rule that cannot tell them apart is too wide.

# _php_explain <files-file> — run verify.sh's plan branch narrowed to
# <files-file>. No project tool may run in this mode, so tests using it also
# assert the stub's log was never written.
_php_explain() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$1"
  JIG_VERIFY_EXPLAIN=1
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_EXPLAIN
  unset JIG_VERIFY_MAPPED
  run bash "$_PHP_VERIFY"
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_EXPLAIN
}

test_profile_php_front_end_script_change_runs_no_test() {
  _php_install
  mkdir -p resources/js
  : > resources/js/app.js
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list resources/js/app.js)

  _php_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip (scope: no changed file maps to a test)"
  assert_no_file phpunit.log
}

# The cut must not have widened the other checks either: they narrow on their
# own terms and a change with no .php in it reaches none of them.
test_profile_php_front_end_change_skips_every_check() {
  _php_install
  mkdir -p resources/css
  : > resources/css/app.css
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  _php_stub_tool phpstan 1.1.1 0 phpstan.log
  _php_stub_tool pint 1.2.3 0 pint.log
  files=$(_files_list resources/css/app.css)

  _php_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip (scope: no changed file maps to a test)"
  assert_contains "$OUT" "php: phpstan: skip (scope: no changed .php files)"
  assert_contains "$OUT" "php: pint: skip (scope: no changed .php files)"
  assert_no_file phpunit.log
  assert_no_file phpstan.log
  assert_no_file pint.log
}

test_profile_php_package_json_change_runs_full_tests() {
  _php_install
  printf '{}\n' > package.json
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list package.json)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "php: phpunit: pass (9.9.9, scope: package.json changes the asset build, which browser tests load, ran full set)"
}

# vite.config.ts also matches the front-end extension list; the build list is
# checked first, and that order is what this pins.
test_profile_php_bundler_config_change_runs_full_tests() {
  _php_install
  : > vite.config.ts
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list vite.config.ts)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: vite.config.ts changes the asset build, which browser tests load, ran full set"
}

test_profile_php_built_asset_under_public_runs_full_tests() {
  _php_install
  mkdir -p public/build
  : > public/build/app.js
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list public/build/app.js)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "scope: the profile cannot map public/build/app.js to tests, ran full set"
}

test_profile_php_front_end_fixture_under_tests_runs_full_tests() {
  _php_install
  mkdir -p tests/fixtures
  : > tests/fixtures/sample.js
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list tests/fixtures/sample.js)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "scope: the profile cannot map tests/fixtures/sample.js to tests, ran full set"
}

test_profile_php_front_end_beside_php_runs_only_the_named_test() {
  _php_install
  mkdir -p src resources/js tests
  : > src/Foo.php
  : > tests/FooTest.php
  : > resources/js/app.js
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list resources/js/app.js src/Foo.php)

  _php_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass (9.9.9, scope: 1 test files)"
  assert_file_contains phpunit.log "tests/FooTest.php"
}

# --- explain: the plan says why, not just what -------------------------------

test_profile_php_explain_front_end_change_maps_to_no_test() {
  _php_install
  mkdir -p resources/js
  : > resources/js/app.js
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list resources/js/app.js)

  _php_explain "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "PLAN php: phpunit: skip (no changed file maps to this check)"
  assert_no_file phpunit.log
}

test_profile_php_explain_names_the_path_that_forces_the_full_set() {
  _php_install
  printf '{}\n' > package.json
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list package.json)

  _php_explain "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "PLAN php: phpunit: full (package.json changes the asset build, which browser tests load)"
  assert_no_file phpunit.log
}

test_profile_php_explain_says_no_test_is_named_after_the_file() {
  _php_install
  mkdir -p src
  : > src/Orphan.php
  _php_stub_tool phpunit 9.9.9 0 phpunit.log
  files=$(_files_list src/Orphan.php)

  _php_explain "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "PLAN php: phpunit: full (no test is named after src/Orphan.php)"
}
