# Tests for `jig config` (scripts/lib/config.sh: cmd_config, _config_set,
# _config_show, jig_config_value_problem) and the refactored
# _cfg_agent_git_level / _cfg_minutes. ADR-0038.
# shellcheck shell=bash

# _assert_no_tmp_leftovers — no leftover atomic-write temp file directly
# inside .ai/ (config.sh writes <file>.tmp.$$, then mv).
_assert_no_tmp_leftovers() {
  [ -z "$(find .ai -maxdepth 1 -name '*.tmp.*')" ] \
    || fail "leftover tmp file in .ai/"
}

# _config_accepts <key> <value> — `jig config set <key> <value> --local`
# succeeds.
_config_accepts() {
  run jig config set "$1" "$2" --local
  assert_eq 0 "$RC" "expected $1=$2 to be accepted: $OUT"
}

# _config_rejects <key> <value> — it refuses with "invalid value".
_config_rejects() {
  run jig config set "$1" "$2" --local
  assert_eq 1 "$RC" "expected $1=$2 to be rejected"
  assert_contains "$OUT" "invalid value" "rejection for $1=$2 did not name the value"
}

# --- jig config set --local: creating the file ---------------------------

test_config_set_local_creates_file_and_reports() {
  fixture_jig_repo
  local project_before
  project_before=$(cat .ai/config.yaml)
  assert_no_file .ai/config.local.yaml

  run jig config set agent.git pr --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config: agent.git: pr (.ai/config.local.yaml)"

  assert_file .ai/config.local.yaml
  assert_eq "$(printf '%s\n%s\n%s' \
    '# Your own Jig settings for this clone: gitignored, never committed.' \
    '# Only local keys are read from here (jig config set --local).' \
    'agent.git: pr')" "$(cat .ai/config.local.yaml)"

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config.local: agent.git=pr"

  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg agent.git
  '
  assert_eq 0 "$RC"
  assert_eq "pr" "$OUT"

  assert_eq "$project_before" "$(cat .ai/config.yaml)" "project config was touched"
  _assert_no_tmp_leftovers
}

# --- replacing in place ----------------------------------------------------

test_config_set_replaces_existing_key_preserves_other_lines_and_order() {
  fixture_jig_repo
  printf '%s\n' \
    "# a comment" \
    "housekeeping.cadence: 3d" \
    "agent.git: commit" \
    "other.key: val" > .ai/config.local.yaml
  # A file saved without a trailing newline must still work.
  printf '%s' "$(cat .ai/config.local.yaml)" > .ai/config.local.yaml

  run jig config set agent.git pr --local
  assert_eq 0 "$RC"

  assert_eq "$(printf '%s\n%s\n%s\n%s' \
    "# a comment" \
    "housekeeping.cadence: 3d" \
    "agent.git: pr" \
    "other.key: val")" "$(cat .ai/config.local.yaml)"
  _assert_no_tmp_leftovers
}

test_config_set_appends_a_key_not_already_present() {
  fixture_jig_repo
  printf 'agent.git: commit\n' > .ai/config.local.yaml

  run jig config set housekeeping.cadence 5d --local
  assert_eq 0 "$RC"

  assert_eq "$(printf '%s\n%s' \
    "agent.git: commit" \
    "housekeeping.cadence: 5d")" "$(cat .ai/config.local.yaml)"
}

test_config_set_several_pairs_in_one_call() {
  fixture_jig_repo

  run jig config set agent.git merge autopilot.unattended true --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config: agent.git: merge (.ai/config.local.yaml)"
  assert_contains "$OUT" "config: autopilot.unattended: true (.ai/config.local.yaml)"
  assert_file_contains .ai/config.local.yaml "agent.git: merge"
  assert_file_contains .ai/config.local.yaml "autopilot.unattended: true"
}

# --- --dry-run ---------------------------------------------------------------

test_config_set_dry_run_prints_result_and_writes_nothing_when_no_file() {
  fixture_jig_repo
  assert_no_file .ai/config.local.yaml

  run jig config set housekeeping.cadence 9d --local --dry-run
  assert_eq 0 "$RC"
  assert_eq "$(printf '%s\n%s\n%s\n%s' \
    '# Your own Jig settings for this clone: gitignored, never committed.' \
    '# Only local keys are read from here (jig config set --local).' \
    'housekeeping.cadence: 9d' \
    'config: dry run, nothing written to .ai/config.local.yaml')" "$OUT"

  assert_no_file .ai/config.local.yaml
  _assert_no_tmp_leftovers
}

test_config_set_dry_run_leaves_existing_file_unchanged() {
  fixture_jig_repo
  printf 'agent.git: commit\nhousekeeping.cadence: 1d\n' > .ai/config.local.yaml
  local before
  before=$(cat .ai/config.local.yaml)

  run jig config set housekeeping.cadence 9d --local --dry-run
  assert_eq 0 "$RC"
  assert_eq "$(printf '%s\n%s\n%s' \
    'agent.git: commit' \
    'housekeeping.cadence: 9d' \
    'config: dry run, nothing written to .ai/config.local.yaml')" "$OUT"

  assert_eq "$before" "$(cat .ai/config.local.yaml)" "dry-run modified the file"
  _assert_no_tmp_leftovers
}

# --- refusals ------------------------------------------------------------

test_config_set_without_local_refuses() {
  fixture_jig_repo
  local project_before
  project_before=$(cat .ai/config.yaml)

  run jig config set agent.git pr
  assert_eq 1 "$RC"
  assert_contains "$OUT" "only --local is supported"
  assert_contains "$OUT" ".ai/config.yaml is the team's file"

  assert_no_file .ai/config.local.yaml
  assert_eq "$project_before" "$(cat .ai/config.yaml)" "project config was touched"
  _assert_no_tmp_leftovers
}

test_config_set_non_local_key_refuses() {
  fixture_jig_repo

  run jig config set git.base_branch other --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "is not a local key"

  assert_no_file .ai/config.local.yaml
  _assert_no_tmp_leftovers
}

test_config_set_unknown_flag_refuses() {
  fixture_jig_repo

  run jig config set agent.git pr --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown flag: --bogus"

  assert_no_file .ai/config.local.yaml
  _assert_no_tmp_leftovers
}

test_config_set_odd_number_of_args_refuses() {
  fixture_jig_repo

  run jig config set agent.git --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "expected <key> <value> pairs"

  assert_no_file .ai/config.local.yaml
}

test_config_missing_subcommand_refuses() {
  fixture_jig_repo

  run jig config
  assert_eq 1 "$RC"
  assert_contains "$OUT" "missing subcommand"
}

test_config_unknown_subcommand_refuses() {
  fixture_jig_repo

  run jig config frobnicate
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown subcommand: frobnicate"
}

# A bad pair later in the same call must not leave an earlier, valid pair
# written: every pair is checked before anything touches the file.
test_config_set_atomic_across_pairs() {
  fixture_jig_repo
  printf 'other.key: keep\n' > .ai/config.local.yaml
  local before
  before=$(cat .ai/config.local.yaml)

  run jig config set agent.git pr agent.ci_timeout abc --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid value"

  assert_eq "$before" "$(cat .ai/config.local.yaml)" \
    "agent.git was written despite agent.ci_timeout failing"
  assert_not_contains "$(cat .ai/config.local.yaml)" "agent.git"
  _assert_no_tmp_leftovers
}

# --- value validation (jig_config_value_problem, via `jig config set`) ------

test_config_set_housekeeping_cadence_validation() {
  fixture_jig_repo
  _config_accepts housekeeping.cadence 3d
  _config_accepts housekeeping.cadence 2
  _config_rejects housekeeping.cadence 12h
  _config_rejects housekeeping.cadence d
  _config_rejects housekeeping.cadence ""
  _config_rejects housekeeping.cadence "3 d"
}

# housekeeping.trash_ttl, .abandoned_ttl and .stale_after share one case in
# jig_config_value_problem: exercised in full for trash_ttl, spot-checked for
# the other two so a typo that dropped one of them from the case would still
# be caught.
test_config_set_duration_keys_validation() {
  fixture_jig_repo
  _config_accepts housekeeping.trash_ttl 7d
  _config_accepts housekeeping.trash_ttl 12h
  _config_accepts housekeeping.trash_ttl 30m
  _config_accepts housekeeping.trash_ttl 90s
  _config_accepts housekeeping.trash_ttl 5
  _config_rejects housekeeping.trash_ttl 7x
  _config_rejects housekeeping.trash_ttl -1d

  _config_accepts housekeeping.abandoned_ttl 7d
  _config_rejects housekeeping.abandoned_ttl 7x

  _config_accepts housekeeping.stale_after 12h
  _config_rejects housekeeping.stale_after -1d
}

test_config_set_boolean_keys_validation() {
  fixture_jig_repo
  _config_accepts housekeeping.fetch true
  _config_accepts housekeeping.fetch false
  _config_rejects housekeeping.fetch yes
  _config_rejects housekeeping.fetch 1
  _config_rejects housekeeping.fetch on
  _config_rejects housekeeping.fetch TRUE

  _config_accepts autopilot.unattended true
  _config_accepts autopilot.unattended false
  _config_rejects autopilot.unattended yes
  _config_rejects autopilot.unattended 1
  _config_rejects autopilot.unattended on
  _config_rejects autopilot.unattended TRUE
}

test_config_set_agent_git_validation() {
  fixture_jig_repo
  _config_accepts agent.git none
  _config_accepts agent.git commit
  _config_accepts agent.git push
  _config_accepts agent.git pr
  _config_accepts agent.git merge
  _config_rejects agent.git yolo
  _config_rejects agent.git PR
}

# autopilot.parallel bounds how many task agents a phase run builds at once;
# 1..16 keeps a typo from starting a swarm
# (adr-20260922-a-phase-run-is-coordinated).
test_config_set_autopilot_parallel_validation() {
  fixture_jig_repo
  _config_accepts autopilot.parallel 1
  _config_accepts autopilot.parallel 3
  _config_accepts autopilot.parallel 16
  _config_rejects autopilot.parallel 0
  _config_rejects autopilot.parallel 17
  _config_rejects autopilot.parallel two
  _config_rejects autopilot.parallel -1
  _config_rejects autopilot.parallel 1.5
}

# It is local-only: a project value is ignored and said so, and with nothing
# set the default is 2 — the number `jig spec plan` counts slots against.
test_config_autopilot_parallel_is_local_only_and_defaults_to_two() {
  fixture_jig_repo
  printf 'autopilot.parallel: 8\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: autopilot.parallel in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"

  plan_spec_for_parallel
  run jig spec plan alpha --phase 1 --format tsv
  assert_eq 0 "$RC"
  assert_contains "$OUT" "parallel$(printf '\t')2$(printf '\t')0"

  run jig config set autopilot.parallel 4 --local
  assert_eq 0 "$RC"
  run jig spec plan alpha --phase 1 --format tsv
  assert_eq 0 "$RC"
  assert_contains "$OUT" "parallel$(printf '\t')4$(printf '\t')0"
}

# A one-phase, one-wave roadmap: enough for the `parallel` row to have
# something to count.
plan_spec_for_parallel() {
  mkdir -p .ai/specs/alpha
  cat > .ai/specs/alpha/roadmap.md <<'RM'
## Phase 1 - First

- [ ] `T-a` - Alpha - goal

## Waves

1. Alpha
RM
}

test_config_set_agent_ci_timeout_validation() {
  fixture_jig_repo
  _config_accepts agent.ci_timeout 0
  _config_accepts agent.ci_timeout 30
  _config_accepts agent.ci_timeout 9999
  _config_rejects agent.ci_timeout 10000
  _config_rejects agent.ci_timeout 1.5
  _config_rejects agent.ci_timeout abc
}

test_config_set_worktree_root_validation() {
  fixture_jig_repo
  _config_accepts git.worktree_root "../wt"
  assert_file_contains .ai/config.local.yaml "git.worktree_root: ../wt"

  # A backslash (a Windows path) is preserved verbatim: the value reaches the
  # awk rewrite through the environment rather than a sed replacement, so it
  # is never read as an escape. Checked with `case`, not assert_file_contains
  # (grep -q, not -F): "\w" in a BRE is a word-class extension, not a literal
  # backslash-w, so a grep match here would pass even if the value got mangled.
  _config_accepts git.worktree_root 'C:\wt\x'
  case "$(cat .ai/config.local.yaml)" in
    *'git.worktree_root: C:\wt\x'*) ;;
    *) fail "git.worktree_root value not preserved verbatim: $(cat .ai/config.local.yaml)" ;;
  esac

  _config_rejects git.worktree_root '"../wt"'
  _config_rejects git.worktree_root "with#hash"
  _config_rejects git.worktree_root " leading-space"
  _config_rejects git.worktree_root "$(printf 'line\nbreak')"
}

# --- not gitignored (ADR-0038) ---------------------------------------------

test_config_set_warns_when_local_file_is_not_gitignored() {
  fixture_jig_repo
  grep -v 'config.local.yaml' .gitignore > .gitignore.tmp
  mv .gitignore.tmp .gitignore

  run jig config set housekeeping.cadence 3d --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "is not ignored by git and can be committed (fix: jig init)"
}

test_config_set_no_warning_when_local_file_is_gitignored() {
  fixture_jig_repo

  run jig config set housekeeping.cadence 3d --local
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "is not ignored by git"
}

# --- worktree (one local file per clone) ------------------------------------

test_config_set_in_worktree_writes_main_checkouts_file() {
  # A nested directory first: "../wt" below must land inside this test's own
  # isolated tmp dir, not in the parent all parallel tests share (every
  # test's tmp dir is a sibling of every other's), or two tests racing on
  # "../wt" collide. tests/dispatcher.t.sh's own worktree test does the same.
  mkdir repo
  cd repo || fail "setup"
  fixture_repo
  mkdir -p .ai
  printf 'git.base_branch: main\n' > .ai/config.yaml
  git add .ai
  git commit -q -m "add .ai"
  local main_root
  main_root=$(pwd -P)

  git worktree add -q ../wt -b b >/dev/null

  run bash -c '
    cd ../wt || exit 1
    "$JIG_BIN" config set housekeeping.cadence 9d --local
  '
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config: housekeeping.cadence: 9d ($main_root/.ai/config.local.yaml)"

  assert_file "$main_root/.ai/config.local.yaml"
  assert_file_contains "$main_root/.ai/config.local.yaml" "housekeeping.cadence: 9d"
  assert_no_file "../wt/.ai/config.local.yaml"
}

# --- no .ai directory --------------------------------------------------------

test_config_set_dies_without_ai_directory() {
  fixture_repo

  run jig config set agent.git pr --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "run jig init there first"
}

# --- jig config show ---------------------------------------------------------

test_config_show_local_prints_file_verbatim() {
  fixture_jig_repo
  printf '%s\n' "# comment" "agent.git: pr" "other: 1" > .ai/config.local.yaml

  run jig config show --local
  assert_eq 0 "$RC"
  assert_eq "$(cat .ai/config.local.yaml)" "$OUT"
}

test_config_show_local_no_file() {
  fixture_jig_repo
  assert_no_file .ai/config.local.yaml

  run jig config show --local
  assert_eq 0 "$RC"
  assert_eq "no local settings: .ai/config.local.yaml does not exist" "$OUT"
}

test_config_show_without_local_refuses() {
  fixture_jig_repo

  run jig config show
  assert_eq 1 "$RC"
  assert_contains "$OUT" "only --local is supported"
  assert_contains "$OUT" ".ai/config.yaml is the team's file"
}

# --- readers unchanged (jig_agent_git, jig_ci_timeout) ---------------------

test_jig_agent_git_reports_invalid_value_and_fails() {
  fixture_repo
  mkdir -p .ai
  printf 'agent.git: yolo\n' > .ai/config.local.yaml

  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_agent_git
  '
  assert_eq 1 "$RC"
  assert_eq "yolo" "$OUT"
}

test_jig_ci_timeout_default_leading_zeros_and_failure() {
  fixture_repo
  mkdir -p .ai

  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_ci_timeout
  '
  assert_eq 0 "$RC"
  assert_eq "30" "$OUT"

  printf 'agent.ci_timeout: 007\n' > .ai/config.local.yaml
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_ci_timeout
  '
  assert_eq 0 "$RC"
  assert_eq "7" "$OUT"

  printf 'agent.ci_timeout: abc\n' > .ai/config.local.yaml
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_ci_timeout
  '
  assert_eq 1 "$RC"
  assert_eq "abc" "$OUT"
}
