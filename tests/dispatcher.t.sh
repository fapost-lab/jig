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
  skip_unless_symlinks
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

# --- release versions (framework-self-update, AC-12) --------------------------
# Release tags are the update channel, so "which tag is newest" decides what a
# user gets. Ordering is numeric per field, in shell arithmetic, because
# `sort -V` is not everywhere jig runs.

# lib_run <shell code> — run code with common.sh sourced, the way these tests
# exercise shared helpers without the dispatcher.
lib_run() {
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; '"$1"
}

test_release_version_accepts_only_three_numeric_fields() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'for t in v0.1.0 v10.20.30 v01.2.3 0.1.0 v1.0.0-rc1 v1.0 v1.0.0.0 v1..0 va.b.c ""; do
      if v=$(jig_release_version "$t"); then printf "%s=%s " "$t" "$v"; else printf "%s=no " "$t"; fi
    done'
  assert_eq 0 "$RC"
  assert_eq "v0.1.0=0.1.0 v10.20.30=10.20.30 v01.2.3=01.2.3 0.1.0=no v1.0.0-rc1=no v1.0=no v1.0.0.0=no v1..0=no va.b.c=no =no " "$OUT"
}

test_version_newer_compares_fields_as_numbers() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'check() { if jig_version_newer "$1" "$2"; then printf "%s>%s " "$1" "$2"; else printf "%s!>%s " "$1" "$2"; fi; }
    check 0.10.0 0.9.0; check 1.0.0 0.99.99; check 0.1.1 0.1.0; check 0.1.0 0.1.0
    check 0.9.0 0.10.0; check 08.0.0 7.0.0; check 1.0.0-rc1 0.1.0; check 0.1.0 junk'
  assert_eq 0 "$RC"
  assert_eq "0.10.0>0.9.0 1.0.0>0.99.99 0.1.1>0.1.0 0.1.0!>0.1.0 0.9.0!>0.10.0 08.0.0>7.0.0 1.0.0-rc1!>0.1.0 0.1.0!>junk " "$OUT"
}

test_newest_release_reads_tags_and_ls_remote_lines() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'printf "%s\n" \
      "4e41650e	refs/tags/v0.9.0" "0b9ed917	refs/tags/v0.9.0^{}" \
      "v0.10.0" "v1.0.0-rc1" "not-a-release" "refs/tags/v0.2.0" | jig_newest_release'
  assert_eq 0 "$RC"
  assert_eq "v0.10.0" "$OUT"
}

test_newest_release_fails_without_a_release_tag() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'printf "%s\n" v1.0.0-rc1 latest | jig_newest_release; printf "rc=%s" "$?"'
  assert_eq "rc=1" "$OUT"
}

test_declared_version_reads_exactly_one_quoted_declaration() {
  mkdir -p one/scripts/lib two/scripts/lib bare/scripts/lib none
  printf '# comment\nJIG_VERSION="1.2.3"\nexport JIG_VERSION\n' > one/scripts/lib/version.sh
  printf 'JIG_VERSION="1.2.3"\nJIG_VERSION="2.0.0"\n' > two/scripts/lib/version.sh
  printf 'JIG_VERSION=1.2.3\n' > bare/scripts/lib/version.sh
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'for d in one two bare none; do
      if v=$(jig_declared_version "$d"); then printf "%s=%s " "$d" "$v"; else printf "%s=no " "$d"; fi
    done'
  assert_eq 0 "$RC"
  assert_eq "one=1.2.3 two=no bare=no none=no " "$OUT"
}

test_help_lists_self_update() {
  run jig help
  assert_contains "$OUT" "self-update"
}
