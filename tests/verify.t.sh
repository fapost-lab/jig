# Tests for `jig verify` (SPEC §29, §30).
# shellcheck shell=bash

# run_no_tools <cmd...> — like `run`, but with PATH stripped down to the
# base system directories, so a profile's verify.sh takes its "nothing
# found" skip path deterministically regardless of what happens to be
# installed (composer/go/npm/php/shellcheck) on the machine running the
# tests. git and bash themselves live under /usr/bin and /bin, so the
# dispatcher and every verify.sh shebang still resolve.
run_no_tools() {
  set +e
  OUT=$(PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$@" 2>&1)
  RC=$?
  set -e
  export OUT RC
}

# _fixture_probe_profile <name> <scope-line> — install a fixture profile at
# .ai/profiles/<name> whose verify.sh reports the JIG_VERIFY_SCOPE /
# JIG_VERIFY_FILES it observes (including the contents of the files list, so
# a test can assert on individual changed paths) and touches "<name>.ran" in
# the project root so a test can prove whether it ran at all. <scope-line>
# is a full profile.yaml line (e.g. "scope: [changed]") to declare scope
# support, or "" to omit the key entirely.
_fixture_probe_profile() {
  local name="$1" scope_line="$2"
  mkdir -p ".ai/profiles/$name"
  {
    printf 'name: %s\n' "$name"
    printf 'description: fixture profile reporting the scope env vars it receives.\n'
    printf 'detect: always\n'
    [ -z "$scope_line" ] || printf '%s\n' "$scope_line"
  } > ".ai/profiles/$name/profile.yaml"
  cat > ".ai/profiles/$name/verify.sh" <<EOF
#!/usr/bin/env bash
touch "$name.ran"
echo "$name: scope=\${JIG_VERIFY_SCOPE:-<unset>}"
if [ -n "\${JIG_VERIFY_FILES:-}" ] && [ -f "\${JIG_VERIFY_FILES:-}" ]; then
  echo "$name: files-set"
  cat "\$JIG_VERIFY_FILES"
else
  echo "$name: files-unset"
fi
exit 0
EOF
  chmod +x ".ai/profiles/$name/verify.sh"
}

# --- shell profile -----------------------------------------------------------

test_verify_shell_profile_passes_on_clean_scripts() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null

  run jig verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT generic: pass"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_contains "$OUT" "verify: 2 profiles, 2 pass, 0 fail, 0 skip"
}

test_verify_shell_profile_fails_on_bad_script() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\necho $1\n' > bad.sh
  chmod +x bad.sh

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "RESULT shell: fail"
  assert_contains "$OUT" "verify: 2 profiles, 1 pass, 1 fail, 0 skip"
}

# --- the "not installed (run jig upgrade)" hint stays actionable (SPEC §32) -
# Activating a profile in config.yaml after init used to leave the hint a
# dead end: copy mode's own decision table already installed the profile,
# but link mode's `jig upgrade` was a pure no-op. Covers both modes.
#
# Since the stale-install-check task, the framework-level pending gate
# (below) catches this case earlier than the per-profile "not installed"
# check ever runs: activating `shell` without upgrading first now fails as
# a framework staleness problem, not a per-profile one — a strictly earlier
# and more actionable diagnosis of the same root cause, so these two tests
# assert on the new message instead of the old per-profile one.

test_verify_hint_resolved_by_upgrade_copy_mode() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "install .ai/profiles/shell/profile.yaml"
  assert_contains "$OUT" "install .ai/profiles/shell/verify.sh"
  assert_contains "$OUT" "FAIL framework: 2 framework files not installed (run jig upgrade)"
  assert_not_contains "$OUT" "RESULT"

  jig upgrade --from "$JIG_HOME" >/dev/null

  run jig verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_not_contains "$OUT" "not installed"
}

test_verify_hint_resolved_by_upgrade_link_mode() {
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "link .ai/profiles/shell"
  assert_contains "$OUT" "FAIL framework: 1 framework file not installed (run jig upgrade)"
  assert_not_contains "$OUT" "RESULT"

  jig upgrade --from "$JIG_HOME" >/dev/null

  run jig verify --list --profile shell
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell: installed"

  run jig verify
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "not installed"
}

# --- framework staleness gate runs no profile at all (stale-install-check) -
# A pass from a stale install is meaningless: prove no profile's verify.sh
# executes at all while framework files are pending, using a profile that
# *is* installed and would otherwise run cleanly (touching its own ".ran"
# marker) — its absence afterward is the evidence.

test_verify_fails_before_running_any_profile_when_framework_pending() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  _fixture_probe_profile probe ""
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, probe, shell]
adapters: [claude, codex]
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "install .ai/profiles/shell/profile.yaml"
  assert_contains "$OUT" "install .ai/profiles/shell/verify.sh"
  assert_contains "$OUT" "FAIL framework: 2 framework files not installed (run jig upgrade)"
  assert_not_contains "$OUT" "RESULT"
  assert_not_contains "$OUT" "SKIP"
  assert_no_file probe.ran

  jig upgrade --from "$JIG_HOME" >/dev/null

  run jig verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_contains "$OUT" "verify: 3 profiles, 3 pass, 0 fail, 0 skip"
  assert_file probe.ran
}

# A copy-mode install whose source checkout no longer exists on this
# machine must not turn into a verify failure (SPEC §32): pending state is
# simply unknown, so verify falls back to running the profiles normally.
test_verify_runs_profiles_when_source_root_unknown() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-del.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" --profiles generic >/dev/null
  rm -rf "$src"

  run jig_installed verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT generic: pass"
  assert_not_contains "$OUT" "FAIL framework"
}

# --- path traversal in profile names (profile-name-validation task) -------

test_verify_rejects_path_traversal_profile_names() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  local bad
  for bad in .. '../x' .hidden 'a b' ''; do
    run jig verify --profile "$bad"
    assert_eq 1 "$RC" "verify accepted profile [$bad]"
    assert_contains "$OUT" "invalid profile name"
  done
}

# Positive control for the reproduced bug: `jig verify --profile
# ../../../<dir>/evilprofile` used to run an arbitrary verify.sh outside the
# project. A rejected name must never reach the point of executing anything.
test_verify_profile_traversal_executes_nothing() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  local evil marker
  evil=$(mktemp -d "${TMPDIR:-/tmp}/jig-evil.XXXXXX")
  marker="$evil/ran"
  cat > "$evil/verify.sh" <<EOF
#!/usr/bin/env bash
touch "$marker"
EOF
  chmod +x "$evil/verify.sh"

  run jig verify --profile "../../../$(basename "$evil")"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
  assert_no_file "$marker"

  rm -rf "$evil"
}

# The same unvalidated name is reachable through .ai/config.yaml, without
# any CLI flag at all.
test_verify_config_profiles_reject_path_traversal() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [.., generic]
adapters: [claude, codex]
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
}

# --- profile-not-installed / no-verify.sh / --profile filter ---------------

test_verify_missing_profile_dir_fails_with_message() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --profile does-not-exist
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL does-not-exist: not installed (run jig upgrade)"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 1 fail, 0 skip"
}

test_verify_profile_without_verify_script_is_skipped() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/noverify

  run jig verify --profile noverify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "SKIP noverify: no verify.sh"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
}

test_verify_profile_verify_script_exit_2_is_skip() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/fake
  cat > .ai/profiles/fake/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "fake: nothing to do: skip"
exit 2
EOF
  chmod +x .ai/profiles/fake/verify.sh

  run jig verify --profile fake
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT fake: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
}

test_verify_profile_filter_accepts_comma_list() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null

  run jig verify --profile generic,shell
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT generic: pass"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_contains "$OUT" "verify: 2 profiles"
}

test_verify_profile_filter_accepts_repeated_flag() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null

  run jig verify --profile generic --profile shell
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT generic: pass"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_contains "$OUT" "verify: 2 profiles"
}

test_verify_profile_without_value_dies() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --profile
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires a value"
}

test_verify_unknown_argument_dies() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument"
}

test_verify_requires_init() {
  fixture_repo
  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig init"
}

# --- --list --------------------------------------------------------------------

test_verify_list_reports_active_and_installed_state() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null

  run jig verify --list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic: installed"
  assert_contains "$OUT" "shell: installed"
}

test_verify_list_reports_not_installed_profile() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --list --profile generic,ghost
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic: installed"
  assert_contains "$OUT" "ghost: not installed"
}

# --- php / go / node: skip paths (no toolchain in the fixture) -------------

test_verify_php_skips_every_check_without_toolchain() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles php >/dev/null

  run_no_tools jig verify --profile php
  assert_eq 0 "$RC"
  assert_contains "$OUT" "php: phpunit: skip"
  assert_contains "$OUT" "php: phpstan: skip"
  assert_contains "$OUT" "php: pint: skip"
  assert_contains "$OUT" "php: composer validate: skip"
  assert_contains "$OUT" "RESULT php: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
}

test_verify_php_passes_with_fake_phpunit_binary() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles php >/dev/null
  mkdir -p vendor/bin
  cat > vendor/bin/phpunit <<'EOF'
#!/usr/bin/env bash
echo "OK (0 tests)"
exit 0
EOF
  chmod +x vendor/bin/phpunit

  run_no_tools jig verify --profile php
  assert_eq 0 "$RC"
  assert_contains "$OUT" "php: phpunit: pass"
  assert_contains "$OUT" "RESULT php: pass"
  assert_contains "$OUT" "verify: 1 profiles, 1 pass, 0 fail, 0 skip"
}

test_verify_go_skips_without_toolchain() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles go >/dev/null

  run_no_tools jig verify --profile go
  assert_eq 0 "$RC"
  assert_contains "$OUT" "go: vet: skip"
  assert_contains "$OUT" "go: test: skip"
  assert_contains "$OUT" "RESULT go: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
}

test_verify_node_skips_without_toolchain() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles node >/dev/null
  printf '{"scripts": {"test": "echo ok", "lint": "echo ok"}}\n' > package.json

  run_no_tools jig verify --profile node
  assert_eq 0 "$RC"
  assert_contains "$OUT" "node: npm test: skip"
  assert_contains "$OUT" "node: npm run lint: skip"
  assert_contains "$OUT" "RESULT node: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
}

test_verify_node_skips_when_no_scripts_declared() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles node >/dev/null
  printf '{}\n' > package.json

  run jig verify --profile node
  assert_eq 0 "$RC"
  assert_contains "$OUT" "node: npm test: skip (no test script or npm not found)"
  assert_contains "$OUT" "node: npm run lint: skip (no lint script or npm not found)"
  assert_contains "$OUT" "RESULT node: skip"
}

# --- laravel: requires php, does not duplicate its checks -------------------

test_verify_laravel_skips_without_artisan_or_php() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null

  run_no_tools jig verify --profile laravel
  assert_eq 0 "$RC"
  assert_contains "$OUT" "laravel: artisan test: skip"
  assert_contains "$OUT" "RESULT laravel: skip"
}

test_verify_check_requires_warns_when_php_not_active() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null
  cat > .ai/config.yaml <<EOF
profiles: [laravel]
EOF

  run jig verify --profile laravel
  assert_eq 0 "$RC"
  assert_contains "$OUT" "requires 'php', which is not active"
}

# --- scope protocol (--changed / --base) (ADR-0013) -------------------------

test_verify_changed_scope_ignored_for_profile_without_declaration() {
  fixture_jig_repo

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic: ok"
  assert_contains "$OUT" "RESULT generic: pass (scope ignored: profile declares no scope support, ran full set)"
}

test_verify_changed_scope_passed_to_supporting_profile() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"
  echo unstaged-change >> README.md

  run jig verify --changed --profile probe
  assert_eq 0 "$RC"
  assert_file probe.ran
  assert_contains "$OUT" "probe: scope=changed"
  assert_contains "$OUT" "probe: files-set"
  assert_contains "$OUT" "README.md"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 1 files)"
}

# The important one: `upgrade` keeps a user-modified verify.sh as-is, so a
# profile that never declared `scope` must never observe one — not even
# when the caller's own environment happens to export the same variable
# names `jig verify` uses internally.
test_verify_changed_scope_cleared_for_nonsupporting_profile_even_when_exported() {
  fixture_jig_repo
  _fixture_probe_profile probe2 ""
  git add -A
  git commit -q -m "add probe2 profile"
  echo unstaged-change >> README.md

  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES=/tmp/should-not-leak
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  run jig verify --changed --profile probe2
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES

  assert_eq 0 "$RC"
  assert_file probe2.ran
  assert_contains "$OUT" "probe2: scope=<unset>"
  assert_contains "$OUT" "probe2: files-unset"
  assert_contains "$OUT" "RESULT probe2: pass (scope ignored: profile declares no scope support, ran full set)"
}

test_verify_changed_empty_file_list_skips_supporting_profile_without_running() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"

  run jig verify --changed --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT probe: skip (scope: changed, no changed files)"
  assert_not_contains "$OUT" "RESULT probe: pass"
  assert_no_file probe.ran
}

test_verify_changed_file_list_includes_staged_unstaged_and_untracked() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"

  echo staged-change >> staged.txt
  git add staged.txt
  echo unstaged-change >> README.md
  echo untracked-content > untracked.txt

  run jig verify --changed --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "probe: files-set"
  assert_contains "$OUT" "staged.txt"
  assert_contains "$OUT" "README.md"
  assert_contains "$OUT" "untracked.txt"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 3 files)"
}

test_verify_changed_base_flag_also_diffs_against_given_ref() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"
  local base
  base=$(git rev-parse HEAD)

  echo committed-after-base > committed-after-base.txt
  git add committed-after-base.txt
  git commit -q -m "second commit"
  echo unstaged-change >> README.md

  run jig verify --changed --base "$base" --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed-after-base.txt"
  assert_contains "$OUT" "README.md"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 2 files)"
}

test_verify_base_without_changed_dies() {
  fixture_jig_repo

  run jig verify --base HEAD
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: --base requires --changed"
}

test_verify_base_non_commit_ref_dies() {
  fixture_jig_repo

  run jig verify --changed --base not-a-real-ref
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: not a commit: not-a-real-ref"
}

test_verify_without_changed_flag_has_no_scope_text() {
  fixture_jig_repo

  run jig verify
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "scope"
}
