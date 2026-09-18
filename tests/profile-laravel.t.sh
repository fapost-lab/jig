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
  assert_eq 0 "$RC" "$OUT"
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
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
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
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
}

test_profile_laravel_runs_full_when_composer_json_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list composer.json)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
}

test_profile_laravel_runs_full_when_routes_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list routes/web.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
}

test_profile_laravel_runs_full_when_config_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list config/app.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
}

test_profile_laravel_runs_full_when_database_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list database/migrations/2024_01_01_create_foo_table.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
}

test_profile_laravel_runs_full_when_bootstrap_changed() {
  _laravel_install
  _artisan_stub 0 artisan.log
  files=$(_files_list bootstrap/providers.php)

  _laravel_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
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
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
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
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.3.0, scope: not narrowable, ran full set)"
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
