# Tests for cached preparation, independent from production init behavior.
# shellcheck shell=bash
# jig overrides are called indirectly by fixture_jig_repo in assert.sh.
# shellcheck disable=SC2329

test_fixture_install_is_reused_but_files_and_git_are_isolated() {
  # Keep the instrumented seed out of the runner's real default-install cache.
  JIG_TEST_CACHE="$JIG_TEST_TMP/cache"
  mkdir -p first second
  jig() {
    printf 'init\n' >> "$JIG_TEST_TMP/init-calls"
    mkdir -p .ai
    printf 'original\n' > .ai/example
  }
  ( cd first && fixture_jig_repo ) || fail 'first preparation failed'
  printf 'modified\n' > first/.ai/example
  ( cd first && git switch -qc other ) || fail 'branch change failed'
  ( cd second && fixture_jig_repo ) || fail 'second preparation failed'
  assert_eq init "$(cat init-calls)" 'installation ran more than once'
  assert_eq original "$(cat second/.ai/example)"
  assert_eq main "$(git -C second symbolic-ref --short HEAD)"
  assert_eq original "$(cat "$JIG_TEST_CACHE/installed/.ai/example")"
}

test_fixture_failed_install_is_not_cached_or_reported_as_success() {
  JIG_TEST_CACHE="$JIG_TEST_TMP/cache"
  mkdir -p first second
  jig() { return 17; }
  if ( cd first && fixture_jig_repo ); then
    fail 'failed initialization was reported as success'
  fi
  assert_no_file "$JIG_TEST_CACHE/ready"
  jig() { mkdir -p .ai; printf 'recovered\n' > .ai/example; }
  ( cd second && fixture_jig_repo ) || fail 'retry did not recover'
  assert_eq recovered "$(cat second/.ai/example)"
}

test_fixture_without_runner_cache_still_initializes() {
  unset JIG_TEST_CACHE
  jig() { mkdir -p .ai; }
  fixture_jig_repo || fail 'uncached initialization failed'
  assert_dir .git
  assert_dir .ai
}
