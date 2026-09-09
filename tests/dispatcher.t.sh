# Tests for scripts/jig dispatcher and shared libraries.
# shellcheck shell=bash

test_version_prints_semver() {
  run jig version
  assert_eq 0 "$RC"
  case "$OUT" in jig\ [0-9]*.[0-9]*.[0-9]*) ;; *) fail "bad version output: $OUT" ;; esac
}

test_help_lists_commands() {
  run jig help
  assert_eq 0 "$RC"
  assert_contains "$OUT" "housekeeping"
  assert_contains "$OUT" "knowledge check"
}

test_unknown_command_fails() {
  run jig frobnicate
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown command"
}

test_symlinked_dispatcher_resolves_lib() {
  mkdir -p bin
  ln -s "$JIG_BIN" bin/jig
  run bin/jig version
  assert_eq 0 "$RC"
  assert_contains "$OUT" "jig "
}

test_cfg_reads_flat_yaml_subset() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, php]   # comment
housekeeping.trash_ttl: 7d
housekeeping.fetch: true
EOF
  # Exercise the library directly through a tiny harness.
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    printf "%s|%s|%s|%s|" "$(cfg housekeeping.trash_ttl)" "$(cfg_list profiles)" "$(cfg missing.key dflt)" "$(cfg profiles)"
    cfg_bool housekeeping.fetch && printf "T"
    cfg_bool nope && printf "X" || printf "F"
  '
  assert_eq 0 "$RC"
  assert_eq "7d|generic php|dflt|[generic, php]|TF" "$OUT"
}

test_duration_seconds() {
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; printf "%s %s %s %s" "$(jig_duration_seconds 1d)" "$(jig_duration_seconds 2h)" "$(jig_duration_seconds 30m)" "$(jig_duration_seconds 45)"'
  assert_eq "86400 7200 1800 3888000" "$OUT"
}

test_hash_matches_git_hash_object() {
  fixture_repo
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; jig_hash README.md'
  assert_eq "$(git hash-object README.md)" "$OUT"
}
