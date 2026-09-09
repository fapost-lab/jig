# Tests for scripts/lib/profiles.sh (SPEC §30).
# shellcheck shell=bash
# Every profiles_harness call below intentionally passes a single-quoted
# script containing $VAR references meant to expand inside the harness's
# inner `bash -c`, not at this call site (same pattern as fm_harness in
# frontmatter.t.sh).
# shellcheck disable=SC2016

# profiles_harness <script> — run <script> with profiles.sh (and its
# dependencies common.sh/config.sh) sourced. JIG_LIB points at the real
# framework checkout ($JIG_HOME); JIG_PROJECT is the current directory
# (a fixture repository set up by the caller).
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

# --- profile_get ---------------------------------------------------------------

test_profile_get_reads_scalar() {
  fixture_repo
  mkdir -p fx
  cat > fx/profile.yaml <<'EOF'
name: fixture
description: A test fixture profile.
detect: always
EOF
  profiles_harness 'profile_get "$PWD/fx" name'
  assert_eq 0 "$RC"
  assert_eq "fixture" "$OUT"

  profiles_harness 'profile_get "$PWD/fx" description'
  assert_eq "A test fixture profile." "$OUT"
}

test_profile_get_missing_key_prints_nothing() {
  fixture_repo
  mkdir -p fx
  printf 'name: fixture\n' > fx/profile.yaml
  profiles_harness 'profile_get "$PWD/fx" requires'
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

test_profile_get_missing_file_prints_nothing() {
  fixture_repo
  profiles_harness 'profile_get "$PWD/does-not-exist" name'
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

test_profile_get_on_real_generic_profile() {
  fixture_repo
  profiles_harness 'profile_get "$JIG_HOME/profiles/generic" detect'
  assert_eq "always" "$OUT"
}

# --- profiles_active -------------------------------------------------------

test_profiles_active_defaults_to_generic() {
  fixture_repo
  mkdir -p .ai
  printf 'profiles: []\n' > .ai/config.yaml
  profiles_harness 'profiles_active'
  assert_eq 0 "$RC"
  assert_eq "generic" "$OUT"
}

test_profiles_active_dedups_and_puts_generic_first() {
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [php, generic, php, laravel]\n' > .ai/config.yaml
  profiles_harness 'profiles_active'
  assert_eq 0 "$RC"
  assert_eq "generic php laravel" "$OUT"
}

# --- profiles_detect -------------------------------------------------------

test_profiles_detect_empty_repo_is_generic_only() {
  fixture_repo
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_eq "generic" "$OUT"
}

test_profiles_detect_no_root_defaults_to_source_root() {
  fixture_repo
  profiles_harness 'profiles_detect'
  assert_eq 0 "$RC"
  assert_eq "generic" "$OUT"
}

test_profiles_detect_composer_json_is_php() {
  fixture_repo
  printf '{}\n' > composer.json
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic"
  assert_contains "$OUT" "php"
  assert_not_contains "$OUT" "laravel"
  assert_not_contains "$OUT" "go"
  assert_not_contains "$OUT" "node"
}

test_profiles_detect_artisan_pulls_in_php_via_requires() {
  fixture_repo
  printf '{}\n' > composer.json
  : > artisan
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic"
  assert_contains "$OUT" "laravel"
  assert_contains "$OUT" "php"
}

test_profiles_detect_artisan_alone_pulls_in_php_by_closure() {
  fixture_repo
  : > artisan
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "laravel"
  assert_contains "$OUT" "php"
}

test_profiles_detect_go_mod_is_go() {
  fixture_repo
  printf 'module example.com/x\n' > go.mod
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "go"
  assert_not_contains "$OUT" "node"
  assert_not_contains "$OUT" "php"
}

test_profiles_detect_package_json_is_node() {
  fixture_repo
  printf '{}\n' > package.json
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "node"
  assert_not_contains "$OUT" "go"
}

test_profiles_detect_shell_script_is_shell() {
  fixture_repo
  mkdir -p scripts
  printf '#!/usr/bin/env bash\necho hi\n' > scripts/x.sh
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell"
}

test_profiles_detect_result_is_one_per_line() {
  fixture_repo
  printf '{}\n' > composer.json
  : > artisan
  profiles_harness 'profiles_detect "$JIG_HOME/profiles" | wc -l | tr -d "[:space:]"'
  assert_eq 0 "$RC"
  assert_eq "3" "$OUT"
}

# --- profiles_check_requires -----------------------------------------------

test_check_requires_warns_when_dependency_not_active() {
  fixture_repo
  mkdir -p .ai/profiles/laravel
  cat > .ai/profiles/laravel/profile.yaml <<'EOF'
name: laravel
description: fixture
detect: [artisan]
requires: [php]
EOF
  mkdir -p .ai
  printf 'profiles: [laravel]\n' > .ai/config.yaml

  profiles_harness 'profiles_check_requires'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "profile 'laravel' requires 'php', which is not active"
}

test_check_requires_silent_when_dependency_active() {
  fixture_repo
  mkdir -p .ai/profiles/laravel .ai/profiles/php
  cat > .ai/profiles/laravel/profile.yaml <<'EOF'
name: laravel
description: fixture
detect: [artisan]
requires: [php]
EOF
  cat > .ai/profiles/php/profile.yaml <<'EOF'
name: php
description: fixture
detect: [composer.json]
EOF
  mkdir -p .ai
  printf 'profiles: [laravel, php]\n' > .ai/config.yaml

  profiles_harness 'profiles_check_requires'
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

# --- _profiles_valid_name / profiles_dir -----------------------------------

test_profiles_valid_name_accepts_well_shaped_names() {
  fixture_repo
  local name
  for name in generic php go-lang node_modules a X9; do
    profiles_harness "_profiles_valid_name '$name'"
    assert_eq 0 "$RC" "rejected well-shaped name [$name]"
  done
}

test_profiles_valid_name_rejects_traversal_and_bad_shapes() {
  fixture_repo
  local name
  for name in .. ../x .hidden . 'a b' ''; do
    profiles_harness "_profiles_valid_name '$name'"
    assert_eq 1 "$RC" "accepted bad name [$name]"
  done
}

test_profiles_dir_prints_path_for_valid_name() {
  fixture_repo
  profiles_harness 'profiles_dir "$JIG_HOME/profiles" generic'
  assert_eq 0 "$RC"
  assert_eq "$JIG_HOME/profiles/generic" "$OUT"
}

test_profiles_dir_dies_on_traversal_name() {
  fixture_repo
  local bad
  for bad in .. '../x' .hidden 'a b' ''; do
    profiles_harness "profiles_dir '$JIG_HOME/profiles' '$bad'"
    assert_eq 1 "$RC" "profiles_dir accepted [$bad]"
    assert_contains "$OUT" "invalid profile name"
  done
}

# --- _adapters_valid_name / adapters_dir ------------------------------------

test_adapters_dir_prints_path_for_valid_name() {
  fixture_repo
  profiles_harness 'adapters_dir "$JIG_HOME/adapters" claude'
  assert_eq 0 "$RC"
  assert_eq "$JIG_HOME/adapters/claude" "$OUT"
}

test_adapters_dir_dies_on_traversal_name() {
  fixture_repo
  local bad
  for bad in .. '../x' .hidden 'a b' ''; do
    profiles_harness "adapters_dir '$JIG_HOME/adapters' '$bad'"
    assert_eq 1 "$RC" "adapters_dir accepted [$bad]"
    assert_contains "$OUT" "invalid adapter name"
  done
}

# --- profiles_active rejects config-driven traversal -----------------------

test_profiles_active_dies_on_invalid_config_name() {
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [.., generic]\n' > .ai/config.yaml
  profiles_harness 'profiles_active'
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
}

# --- profiles_source_dir / profiles_installed_dir -------------------------

test_profiles_source_dir_points_at_source_profiles() {
  fixture_repo
  profiles_harness 'profiles_source_dir'
  assert_eq 0 "$RC"
  assert_eq "$JIG_HOME/profiles" "$OUT"
}

test_profiles_installed_dir_points_under_dot_ai() {
  fixture_repo
  profiles_harness 'profiles_installed_dir'
  assert_eq 0 "$RC"
  assert_eq "$(pwd)/.ai/profiles" "$OUT"
}
