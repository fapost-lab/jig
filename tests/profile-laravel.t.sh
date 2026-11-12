# Tests for the laravel profile's verify.sh (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools;
# domains/verify).
# shellcheck shell=bash
#
# Most tests run .ai/profiles/laravel/verify.sh directly with
# JIG_VERIFY_SCOPE / JIG_VERIFY_FILES / JIG_VERIFY_MAPPED set by hand — see
# the same note at the top of tests/profile-php.t.sh. laravel duplicates the
# php profile's file-to-test convention rather than sourcing it: each
# shipped verify.sh is an independent file (D2/D3), and `requires: [php]`
# is a runtime activation dependency, not a code-sharing one, so this file
# exercises laravel's own copy, not php's.

_LARAVEL_VERIFY=".ai/profiles/laravel/verify.sh"

# _laravel_install — a fixture repository with the laravel profile
# installed, an `artisan` file and `php` reachable (laravel's own two
# preconditions), no other setup.
_laravel_install() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null
  : > artisan
}

# _artisan_stub <rc> <log> — a `php` on PATH: answers `--version`, and for
# `artisan test ...` appends the arguments it received to <log> and exits
# <rc> (laravel only ever calls `php artisan test`, besides the version
# probe).
_artisan_stub() {
  local rc="$1" log="$2"
  mkdir -p stub-bin
  cat > stub-bin/php <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf 'PHP 8.3.0\n'
  exit 0
fi
if [ "\$1" = "artisan" ] && [ "\$2" = "test" ]; then
  shift 2
  printf '%s\n' "\$*" >> "$PWD/$log"
  exit $rc
fi
exit 127
STUB
  chmod +x stub-bin/php
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

# _laravel_scoped <files-file> [mapped-file] — run verify.sh narrowed to
# <files-file>, with <mapped-file> as JIG_VERIFY_MAPPED when given.
_laravel_scoped() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$1"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  if [ -n "${2:-}" ]; then
    JIG_VERIFY_MAPPED="$2"
    export JIG_VERIFY_MAPPED
  else
    unset JIG_VERIFY_MAPPED
  fi
  run bash "$_LARAVEL_VERIFY"
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
}

# --- detect ------------------------------------------------------------------

test_profile_laravel_detected_for_artisan_and_pulls_in_php() {
  fixture_repo
  printf '{}\n' > composer.json
  : > artisan
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
  assert_contains "$OUT" "laravel"
  assert_contains "$OUT" "php"
}

# --- full mode: unchanged observable behaviour --------------------------------

test_profile_laravel_skips_without_artisan_or_php() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null
  run jig verify --profile laravel
  # Every check skipped, so the run checked nothing and says so, exit 3
  # (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip (artisan or php not found)"
  assert_contains "$OUT" "RESULT laravel: skip"
}

test_profile_laravel_does_not_duplicate_php_checks() {
  _laravel_install
  _artisan_stub 0 artisan.log
  run jig verify --profile laravel
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "phpunit"
  assert_not_contains "$OUT" "phpstan"
  assert_not_contains "$OUT" "pint"
  assert_not_contains "$OUT" "composer validate"
}

# --- pass / fail --------------------------------------------------------------

test_profile_laravel_full_mode_pass_and_fail() {
  _laravel_install
  _artisan_stub 0 artisan.log
  run jig verify --profile laravel
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass"

  _artisan_stub 1 artisan.log
  run jig verify --profile laravel
  assert_eq 1 "$RC"
  assert_contains "$OUT" "laravel: artisan test: fail"
}

# --- narrowing: same php-> test convention as the php profile (D4) ----------

test_profile_laravel_changed_test_file_maps_to_itself() {
  _laravel_install
  mkdir -p tests
  : > tests/FooTest.php
  _artisan_stub 0 artisan.log
  files=$(_files_list tests/FooTest.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: 1 test files)"
  assert_file_contains artisan.log "tests/FooTest.php"
}

test_profile_laravel_changed_source_maps_to_named_test_under_tests() {
  _laravel_install
  mkdir -p app tests
  : > app/Foo.php
  : > tests/FooTest.php
  _artisan_stub 0 artisan.log
  files=$(_files_list app/Foo.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: 1 test files)"
  assert_file_contains artisan.log "tests/FooTest.php"
}

test_profile_laravel_unmapped_source_runs_full() {
  _laravel_install
  mkdir -p app
  : > app/Orphan.php
  _artisan_stub 0 artisan.log
  files=$(_files_list app/Orphan.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: no test is named after app/Orphan.php, ran full set)"
  assert_file_contains artisan.log '^$'
}

test_profile_laravel_doc_only_change_skips() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list README.md)

  _laravel_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip (scope: no changed file maps to a test)"
  assert_no_file artisan.log
}

test_profile_laravel_missing_selected_test_falls_back_to_full() {
  _laravel_install
  mkdir -p app
  : > app/Foo.php
  _artisan_stub 0 artisan.log
  files=$(_files_list app/Foo.php)
  mapped=$(_mapped_file "$(printf 'app/Foo.php\ttests/GoneTest.php')")

  _laravel_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "laravel: artisan test: pass (PHP 8.3.0, scope: filter 'tests/GoneTest.php' selects no tests, ran full set)"
}

# --- always-ALL triggers (D4: php's own set, plus routes/, config/, --------
# --- database/, bootstrap/) --------------------------------------------------

test_profile_laravel_runs_full_when_phpunit_xml_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list phpunit.xml.dist)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: phpunit.xml.dist can affect any test, ran full set)"
}

test_profile_laravel_runs_full_when_composer_json_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list composer.json)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: composer.json can affect any test, ran full set)"
}

test_profile_laravel_runs_full_when_routes_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list routes/web.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: routes/web.php can affect any test, ran full set)"
}

test_profile_laravel_runs_full_when_config_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list config/app.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: config/app.php can affect any test, ran full set)"
}

test_profile_laravel_runs_full_when_database_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list database/migrations/2024_01_01_create_foo_table.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: database/migrations/2024_01_01_create_foo_table.php can affect any test, ran full set)"
}

test_profile_laravel_runs_full_when_bootstrap_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list bootstrap/providers.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: bootstrap/providers.php can affect any test, ran full set)"
}

# --- map filters (D5: a test file path) --------------------------------------

test_profile_laravel_map_filter_overrides_the_builtin_test_mapping() {
  _laravel_install
  mkdir -p app tests
  : > app/Foo.php
  : > tests/FooTest.php
  : > tests/CustomTest.php
  _artisan_stub 0 artisan.log
  files=$(_files_list app/Foo.php)
  mapped=$(_mapped_file "$(printf 'app/Foo.php\ttests/CustomTest.php')")

  _laravel_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains artisan.log "tests/CustomTest.php"
  assert_not_contains "$(cat artisan.log)" "tests/FooTest.php"
}

test_profile_laravel_map_dash_means_no_test() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list docs/change.md)
  mapped=$(_mapped_file "$(printf 'docs/change.md\t-')")

  _laravel_scoped "$files" "$mapped"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip (scope: no changed file maps to a test)"
}

# --- glob-list regression: an always-ALL glob must not be expanded --------
# --- against the files that happen to be on disk (jp_path_matches) --------
# Before the fix, LARAVEL_TEST_ALL_GLOBS was split with `for g in $LIST`
# with pathname expansion on: a sibling file matching "config/*" made the
# word expand to that sibling alone, so it stopped matching the actual
# changed path and the run fell through to the stem-based tests/*Test.php
# lookup instead of the full suite — silently narrowing a change that D4
# says must run everything.

test_profile_laravel_deleted_config_file_runs_full_despite_sibling_on_disk() {
  _laravel_install
  mkdir -p config tests
  : > config/database.php
  : > tests/appTest.php
  _artisan_stub 0 artisan.log
  # config/app.php itself is never created on disk: the change deleted it.
  files=$(_files_list config/app.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: config/app.php can affect any test, ran full set)"
  # Old bug: config/* expanded to config/database.php (the only sibling on
  # disk), missed config/app.php, and fell through to stem "app" ->
  # tests/appTest.php, running only that one test instead of the full suite.
  assert_file_contains artisan.log '^$'
  assert_not_contains "$(cat artisan.log)" "tests/appTest.php"
}

test_profile_laravel_nested_config_file_runs_full_despite_sibling_on_disk() {
  _laravel_install
  mkdir -p config tests
  : > config/app.php
  : > tests/extraTest.php
  _artisan_stub 0 artisan.log
  files=$(_files_list config/nested/extra.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: config/nested/extra.php can affect any test, ran full set)"
  # Old bug: config/* expanded via real pathname globbing (never crosses
  # `/`), matching only the direct child config/app.php on disk, so a
  # nested config/nested/extra.php never matched and fell through to stem
  # "extra" -> tests/extraTest.php instead of the full suite.
  assert_file_contains artisan.log '^$'
  assert_not_contains "$(cat artisan.log)" "tests/extraTest.php"
}

test_profile_laravel_map_question_mark_falls_back_to_builtin() {
  _laravel_install
  mkdir -p app tests
  : > app/Foo.php
  : > tests/FooTest.php
  _artisan_stub 0 artisan.log
  files=$(_files_list app/Foo.php)
  mapped=$(_mapped_file "$(printf 'app/Foo.php\t?')")

  _laravel_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains artisan.log "tests/FooTest.php"
}

# --- front end: what can and cannot change the result of `artisan test` -------
# The cut is not "everything that is not .php needs no test": a front-end
# source is not read by the PHP test run, but the build that turns it into
# assets is, because a browser test (Dusk) loads the built assets and
# `artisan test` runs it. Both halves are asserted; a test that cannot tell
# resources/js/app.js from package.json would not cover this at all.

# _laravel_explain <files-file> — run verify.sh's plan branch narrowed to
# <files-file>. No project tool may run in this mode, so the tests that use
# it also assert the stub's log was never written.
_laravel_explain() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$1"
  JIG_VERIFY_EXPLAIN=1
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_EXPLAIN
  unset JIG_VERIFY_MAPPED
  run bash "$_LARAVEL_VERIFY"
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_EXPLAIN
}

test_profile_laravel_front_end_script_change_runs_no_test() {
  _laravel_install
  mkdir -p resources/js
  : > resources/js/app.js
  _artisan_stub 0 artisan.log
  files=$(_files_list resources/js/app.js)

  _laravel_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip (scope: no changed file maps to a test)"
  assert_no_file artisan.log
}

test_profile_laravel_front_end_component_and_style_change_runs_no_test() {
  _laravel_install
  mkdir -p resources/js/Pages resources/css
  : > resources/js/Pages/Dashboard.vue
  : > resources/css/app.css
  _artisan_stub 0 artisan.log
  files=$(_files_list resources/js/Pages/Dashboard.vue resources/css/app.css)

  _laravel_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip (scope: no changed file maps to a test)"
  assert_no_file artisan.log
}

test_profile_laravel_package_json_change_runs_full_set() {
  _laravel_install
  printf '{}\n' > package.json
  _artisan_stub 0 artisan.log
  files=$(_files_list package.json)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "laravel: artisan test: pass (PHP 8.3.0, scope: package.json changes the asset build, which browser tests load, ran full set)"
  assert_file_contains artisan.log '^$'
}

test_profile_laravel_lock_file_change_runs_full_set() {
  _laravel_install
  printf '{}\n' > package-lock.json
  _artisan_stub 0 artisan.log
  files=$(_files_list package-lock.json)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: package-lock.json changes the asset build, which browser tests load, ran full set"
}

# vite.config.ts also matches the front-end extension list; the build list is
# checked first, so the order of the two rules is what this pins.
test_profile_laravel_bundler_config_change_runs_full_set() {
  _laravel_install
  : > vite.config.ts
  _artisan_stub 0 artisan.log
  files=$(_files_list vite.config.ts)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: vite.config.ts changes the asset build, which browser tests load, ran full set"
}

# A built asset is what a browser test actually loads, so public/ is excluded
# from the front-end rule even though the extension matches.
test_profile_laravel_built_asset_under_public_runs_full_set() {
  _laravel_install
  mkdir -p public/build/assets
  : > public/build/assets/app.js
  _artisan_stub 0 artisan.log
  files=$(_files_list public/build/assets/app.js)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "scope: the profile cannot map public/build/assets/app.js to tests, ran full set"
  assert_file_contains artisan.log '^$'
}

# A file under tests/ can be a fixture or a snapshot a test asserts on.
test_profile_laravel_front_end_fixture_under_tests_runs_full_set() {
  _laravel_install
  mkdir -p tests/fixtures
  : > tests/fixtures/sample.js
  _artisan_stub 0 artisan.log
  files=$(_files_list tests/fixtures/sample.js)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "scope: the profile cannot map tests/fixtures/sample.js to tests, ran full set"
}

# A Blade template is .php and keeps the full set: it can change a feature
# test's result and no naming convention narrows it.
test_profile_laravel_blade_template_change_runs_full_set() {
  _laravel_install
  mkdir -p resources/views
  : > resources/views/dashboard.blade.php
  _artisan_stub 0 artisan.log
  files=$(_files_list resources/views/dashboard.blade.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "scope: no test is named after resources/views/dashboard.blade.php, ran full set"
}

# A front-end file alongside a php one must not widen that php file's
# selection back to the full set, and must not swallow it either.
test_profile_laravel_front_end_beside_php_runs_only_the_named_test() {
  _laravel_install
  mkdir -p app resources/js tests
  : > app/Foo.php
  : > tests/FooTest.php
  : > resources/js/app.js
  _artisan_stub 0 artisan.log
  files=$(_files_list resources/js/app.js app/Foo.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: 1 test files)"
  assert_file_contains artisan.log "tests/FooTest.php"
}

# --- explain: the plan says why, not just what -------------------------------

test_profile_laravel_explain_front_end_change_maps_to_no_test() {
  _laravel_install
  mkdir -p resources/js
  : > resources/js/app.js
  _artisan_stub 0 artisan.log
  files=$(_files_list resources/js/app.js)

  _laravel_explain "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "PLAN laravel: artisan test: skip (no changed file maps to this check)"
  assert_no_file artisan.log
}

test_profile_laravel_explain_names_the_path_that_forces_the_full_set() {
  _laravel_install
  printf '{}\n' > package.json
  _artisan_stub 0 artisan.log
  files=$(_files_list package.json)

  _laravel_explain "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "PLAN laravel: artisan test: full (package.json changes the asset build, which browser tests load)"
  assert_no_file artisan.log
}

test_profile_laravel_explain_says_no_test_is_named_after_the_file() {
  _laravel_install
  mkdir -p app
  : > app/Orphan.php
  _artisan_stub 0 artisan.log
  files=$(_files_list app/Orphan.php)

  _laravel_explain "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "PLAN laravel: artisan test: full (no test is named after app/Orphan.php)"
}

# --- verify.full_run: ci leaves the full set to CI (adr-0041, 2026-10-08) ---
#
# The owner's Laravel project declares `verify.full_run: ci`, and a change to
# routes/ or database/ still ran the whole suite locally. Under `ci` a narrowed
# run never starts the full set: what it can name it runs, the rest is CI's.

# _laravel_ci_project — an installed laravel project that declares
# `verify.full_run: ci`, committed, with the artisan stub logging to
# artisan.log.
_laravel_ci_project() {
  _laravel_install
  printf '\nverify.full_run: ci\n' >> .ai/config.yaml
  git add -A
  git commit -q -m "laravel project, CI runs the full set"
  _artisan_stub 0 artisan.log
}

test_profile_laravel_full_run_ci_leaves_a_routes_change_to_ci() {
  _laravel_ci_project
  mkdir -p routes
  printf '<?php\n' > routes/web.php

  run jig verify --profile laravel
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "laravel: artisan test: skip (scope: routes/web.php can affect any test, full set left to CI)"
  assert_contains "$OUT" "verify: 1 check(s) left their full set to CI (verify.full_run: ci); jig verify --full runs it here"
  assert_contains "$OUT" "left its full set to CI, so this run verified nothing here"
  assert_no_file artisan.log
}

test_profile_laravel_full_run_ci_runs_the_named_tests_beside_a_migration() {
  _laravel_ci_project
  mkdir -p app tests database/migrations
  : > tests/FooTest.php
  git add -A
  git commit -q -m "a test"
  printf '<?php\n' > app/Foo.php
  printf '<?php\n' > database/migrations/2024_01_01_create_foo_table.php

  run jig verify --profile laravel
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "laravel: artisan test: pass (PHP 8.3.0, scope: 1 test files, full set left to CI)"
  assert_contains "$OUT" "verify: 1 check(s) left their full set to CI (verify.full_run: ci); jig verify --full runs it here"
  assert_eq "tests/FooTest.php" "$(cat artisan.log)"
}

test_profile_laravel_full_run_ci_leaves_a_filter_that_selects_nothing_to_ci() {
  _laravel_install
  mkdir -p app
  : > app/Foo.php
  _artisan_stub 0 artisan.log
  files=$(_files_list app/Foo.php)
  mapped=$(_mapped_file "$(printf 'app/Foo.php\ttests/GoneTest.php')")

  JIG_VERIFY_FULL_RUN=ci
  export JIG_VERIFY_FULL_RUN
  _laravel_scoped "$files" "$mapped"
  unset JIG_VERIFY_FULL_RUN
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" \
    "laravel: artisan test: skip (scope: filter 'tests/GoneTest.php' selects no tests, full set left to CI)"
  assert_no_file artisan.log
}

test_profile_laravel_full_run_ci_full_flag_runs_the_full_set() {
  _laravel_ci_project
  mkdir -p routes
  printf '<?php\n' > routes/web.php

  run jig verify --full --profile laravel
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "verify: full run (--full)"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0)"
  assert_not_contains "$OUT" "left to CI"
  assert_file_contains artisan.log '^$'
}

test_profile_laravel_full_run_local_still_runs_the_full_set() {
  _laravel_install
  git add -A
  git commit -q -m "laravel project"
  _artisan_stub 0 artisan.log
  mkdir -p routes
  printf '<?php\n' > routes/web.php

  run jig verify --changed --profile laravel
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "laravel: artisan test: pass (PHP 8.3.0, scope: routes/web.php can affect any test, ran full set)"
  assert_not_contains "$OUT" "left to CI"
  assert_file_contains artisan.log '^$'
}

test_profile_laravel_full_run_ci_explain_says_the_full_set_is_left_to_ci() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list routes/web.php)

  JIG_VERIFY_FULL_RUN=ci
  export JIG_VERIFY_FULL_RUN
  _laravel_explain "$files"
  unset JIG_VERIFY_FULL_RUN
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "PLAN laravel: artisan test: skip (scope: routes/web.php can affect any test, full set left to CI)"
  assert_no_file artisan.log
}

# --- one suite, not two: laravel covers php:tests ----------------------------
# `php artisan test` runs the same PHPUnit/Pest suite the php profile would.
# laravel declares `covers: [php:tests]`, php names its test check `tests`, and
# jig verify hands the check over: in a run with both, php's tests are
# laravel's and php says so; alone, or without an `artisan`, php runs them.

# _laravel_php_install — a Laravel project as `jig init` activates it: laravel
# and the php it requires, with an `artisan`.
_laravel_php_install() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel,php >/dev/null
  : > artisan
  # A passing `composer`, so a composer on the machine running the suite does
  # not decide php's result: these tests are about its tests, not its manifest.
  mkdir -p stub-bin
  # shellcheck disable=SC2016  # a script written for the stub to expand, not this shell
  printf '#!/usr/bin/env bash\n[ "$1" = --version ] && echo "Composer 2.8.0"\nexit 0\n' > stub-bin/composer
  chmod +x stub-bin/composer
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _phpunit_stub <log> — vendor/bin/phpunit: answers `--version`, otherwise
# appends its arguments to <log>.
_phpunit_stub() {
  local log="$1"
  mkdir -p vendor/bin
  cat > vendor/bin/phpunit <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf 'PHPUnit 11.0.0\n'
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
exit 0
STUB
  chmod +x vendor/bin/phpunit
}

# _laravel_php_committed — the project as a commit, so a later change is what
# `jig verify --changed` narrows to.
_laravel_php_committed() {
  git add -A >/dev/null 2>&1
  git commit -qm base >/dev/null 2>&1
}

test_profile_laravel_and_php_run_the_suite_once() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  run jig verify
  assert_eq 0 "$RC" "$OUT"
  assert_file artisan.log
  assert_no_file phpunit.log
  assert_contains "$OUT" "php: phpunit: skip (scope: covered by laravel, php:tests)"
}

test_profile_laravel_and_php_explain_plans_the_suite_once() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  run jig verify --explain
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "PLAN php: phpunit: skip (scope: covered by laravel, php:tests)"
  assert_contains "$OUT" "PLAN laravel: artisan test: full"
  assert_no_file phpunit.log
}

test_profile_php_alone_runs_its_tests_beside_an_artisan() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  run jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_file phpunit.log
  assert_contains "$OUT" "php: phpunit: pass"
}

test_profile_php_runs_its_tests_when_laravel_has_no_artisan() {
  _laravel_php_install
  rm artisan
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  run jig verify
  # laravel's stack is not here (its `detect` matches nothing), so it covers
  # nothing and the suite runs where it can.
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip (artisan or php not found)"
  assert_file phpunit.log
  assert_contains "$OUT" "php: phpunit: pass"
}

test_profile_laravel_doc_only_change_beside_php_is_scope_narrowing() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  # phpstan and pint present, so every skip below is about this change and
  # none about a missing tool.
  cp vendor/bin/phpunit vendor/bin/phpstan
  cp vendor/bin/phpunit vendor/bin/pint
  _laravel_php_committed
  printf 'notes\n' > README.md
  run jig verify --changed
  # Every check skipped because this change is not theirs: not a gap in
  # coverage, so not "no verdict" (domains/verify RULES, the third state).
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip (scope: covered by laravel, php:tests)"
  assert_no_file phpunit.log
}

test_profile_laravel_reads_php_map_with_the_tests_it_covers() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  mkdir -p .ai/verify
  printf 'resources/js/** ALL\n' > .ai/verify/php.map
  _laravel_php_committed
  mkdir -p resources/js
  printf 'x\n' > resources/js/app.js
  run jig verify --changed
  # php.map's decision follows the tests to laravel: the full suite runs once,
  # in artisan test, and php does not run it a second time.
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip (scope: covered by laravel, php:tests)"
  assert_no_file phpunit.log
  assert_file artisan.log
  assert_eq "" "$(cat artisan.log)"
  assert_contains "$OUT" "RESULT laravel: pass (scope: changed, 1 files, map .ai/verify/php.map)"
}

test_profile_laravel_explain_reads_php_map_with_the_tests_it_covers() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  mkdir -p .ai/verify
  printf 'resources/js/** ALL\n' > .ai/verify/php.map
  _laravel_php_committed
  mkdir -p resources/js
  printf 'x\n' > resources/js/app.js
  run jig verify --changed --explain
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "PLAN php: phpunit: skip (scope: covered by laravel, php:tests)"
  assert_contains "$OUT" "PLAN laravel: artisan test: full"
  assert_no_file artisan.log
}

test_profile_laravel_map_comes_before_the_php_map_it_reads() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  mkdir -p .ai/verify tests/Feature resources/js
  : > tests/Feature/AppTest.php
  # No final newline: the two maps must not run into each other.
  printf 'resources/js/app.js tests/Feature/AppTest.php' > .ai/verify/laravel.map
  printf 'resources/js/** ALL\n' > .ai/verify/php.map
  _laravel_php_committed
  printf 'x\n' > resources/js/app.js
  run jig verify --changed
  # Both maps match app.js; laravel's own line comes first and wins, so one
  # test file runs rather than php.map's full set.
  assert_eq 0 "$RC" "$OUT"
  assert_no_file phpunit.log
  assert_eq "tests/Feature/AppTest.php" "$(cat artisan.log)"
  assert_contains "$OUT" "map .ai/verify/laravel.map, .ai/verify/php.map)"
}

test_profile_laravel_fails_on_a_broken_php_map_it_reads() {
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  mkdir -p .ai/verify
  printf 'resources/js/**\n' > .ai/verify/php.map
  _laravel_php_committed
  mkdir -p resources/js
  printf 'x\n' > resources/js/app.js
  run jig verify --changed
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "RESULT laravel: fail (map .ai/verify/php.map:1: no decision for resources/js/**)"
  assert_no_file artisan.log
}

test_profile_laravel_tests_go_to_a_project_profile_with_php_map() {
  # A project profile over a stock profile: one over stock laravel takes laravel's
  # tests, and so php's, which laravel covers; php.map follows them all the way.
  _laravel_php_install
  _artisan_stub 0 artisan.log
  _phpunit_stub phpunit.log
  mkdir -p .ai/profiles/myapp .ai/verify
  printf 'name: myapp\ndescription: the project runs its own suite.\nscope: [changed, map]\ncovers: [laravel:tests]\n' \
    > .ai/profiles/myapp/profile.yaml
  # shellcheck disable=SC2016  # a script written for the stub to expand, not this shell
  printf '#!/usr/bin/env bash\necho "myapp: mapped=$(cat "${JIG_VERIFY_MAPPED:-/dev/null}" | tr "\\t\\n" ":;")"\nexit 0\n' \
    > .ai/profiles/myapp/verify.sh
  printf 'profiles: [laravel, php, myapp]\nadapters: [claude, codex]\n' > .ai/config.yaml
  printf 'resources/js/** ALL\n' > .ai/verify/php.map
  _laravel_php_committed
  mkdir -p resources/js
  printf 'x\n' > resources/js/app.js
  run jig verify --changed
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip (scope: covered by myapp, laravel:tests)"
  assert_contains "$OUT" "php: phpunit: skip (scope: covered by myapp, php:tests)"
  assert_contains "$OUT" "myapp: mapped=resources/js/app.js:ALL;"
  assert_contains "$OUT" "map .ai/verify/php.map)"
  assert_no_file artisan.log
  assert_no_file phpunit.log
}

test_profile_laravel_explain_plans_its_tests_covered() {
  _laravel_install
  _artisan_stub 0 artisan.log
  JIG_VERIFY_COVERED="tests=myapp"
  JIG_VERIFY_EXPLAIN=1
  export JIG_VERIFY_COVERED JIG_VERIFY_EXPLAIN
  run bash .ai/profiles/laravel/verify.sh
  assert_contains "$OUT" "PLAN laravel: artisan test: skip (scope: covered by myapp, laravel:tests)"
  unset JIG_VERIFY_EXPLAIN
  run bash .ai/profiles/laravel/verify.sh
  unset JIG_VERIFY_COVERED
  assert_contains "$OUT" "laravel: artisan test: skip (scope: covered by myapp, laravel:tests)"
  assert_no_file artisan.log
}
