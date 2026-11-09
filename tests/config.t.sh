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
  _config_accepts git.delete_merged_branches false
  _config_rejects git.delete_merged_branches no

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
  _config_accepts autopilot.git pr
  _config_accepts autopilot.git merge
  _config_rejects autopilot.git yolo
  _config_rejects autopilot.git MERGE
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
  # The warning follows the report line, as it always did.
  assert_eq "config: housekeeping.cadence:" "$(printf "%s\n" "$OUT" | head -n 1 | cut -c1-29)"
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
  printf '%s\n' "# comment" "agent.git: pr" "housekeeping.cadence: 2d" > .ai/config.local.yaml

  run jig config show --local
  assert_eq 0 "$RC"
  assert_eq "$(cat .ai/config.local.yaml)" "$OUT"
}

# A key no reader answers from was printed like any other, so the command
# presented junk as a setting. It is named after the file, with the command
# that removes it — `jig config set` cannot.
test_config_show_local_names_the_keys_no_reader_answers_from() {
  fixture_jig_repo
  printf '%s\n' "# comment" "agent.git: pr" "other: 1" "housekeeping.cadense: 2d" \
    > .ai/config.local.yaml

  run jig config show --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: pr"
  assert_contains "$OUT" "ignored: other (not a local key; jig config unset other --local)"
  assert_contains "$OUT" "ignored: housekeeping.cadense (not a local key; jig config unset housekeeping.cadense --local)"
  # A key the readers do answer from is not called ignored.
  assert_not_contains "$OUT" "ignored: agent.git"
}

test_config_show_local_says_nothing_extra_when_every_key_is_local() {
  fixture_jig_repo
  printf '%s\n' "agent.git: pr" > .ai/config.local.yaml

  run jig config show --local
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "ignored:"
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

# --- jig config unset --local -------------------------------------------------
#
# `jig-setup` could show a person the keys in their own file that do nothing
# and had no way to remove them, which left a hand edit of a file the tooling
# owns as the only route (ADR-0001). `unset` takes any key the file holds —
# the ignored ones are exactly the ones worth removing.

test_config_unset_removes_a_key_and_leaves_the_rest() {
  fixture_jig_repo
  printf '%s\n' "# comment" "agent.git: pr" "housekeeping.cadence: 2d" > .ai/config.local.yaml

  run jig config unset agent.git --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config: unset agent.git (.ai/config.local.yaml)"
  assert_eq "$(printf '%s\n' '# comment' 'housekeeping.cadence: 2d')" \
    "$(cat .ai/config.local.yaml)"
  _assert_no_tmp_leftovers
}

test_config_unset_removes_a_key_no_reader_answers_from() {
  fixture_jig_repo
  printf '%s\n' "other: 1" "agent.git: pr" > .ai/config.local.yaml

  run jig config unset other --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config: unset other (.ai/config.local.yaml)"
  assert_eq "agent.git: pr" "$(cat .ai/config.local.yaml)"
}

test_config_unset_several_keys_in_one_call() {
  fixture_jig_repo
  printf '%s\n' "other: 1" "agent.git: pr" "autopilot.parallel: 3" > .ai/config.local.yaml

  run jig config unset other autopilot.parallel --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config: unset other"
  assert_contains "$OUT" "config: unset autopilot.parallel"
  assert_eq "agent.git: pr" "$(cat .ai/config.local.yaml)"
}

# `cfg` reads the first line for a key, so a duplicate left behind would keep
# setting a key reported as removed.
test_config_unset_removes_every_line_of_the_key() {
  fixture_jig_repo
  printf '%s\n' "agent.git: pr" "housekeeping.cadence: 2d" "agent.git: merge" \
    > .ai/config.local.yaml

  run jig config unset agent.git --local
  assert_eq 0 "$RC"
  assert_eq "housekeeping.cadence: 2d" "$(cat .ai/config.local.yaml)"
}

test_config_unset_a_key_that_is_not_set_says_so_and_writes_nothing() {
  fixture_jig_repo
  printf '%s\n' "agent.git: pr" > .ai/config.local.yaml
  local before
  before=$(cat .ai/config.local.yaml)

  run jig config unset housekeeping.cadence --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config: housekeeping.cadence is not set (.ai/config.local.yaml)"
  assert_eq "$before" "$(cat .ai/config.local.yaml)"
  _assert_no_tmp_leftovers
}

test_config_unset_no_file() {
  fixture_jig_repo
  assert_no_file .ai/config.local.yaml

  run jig config unset agent.git --local
  assert_eq 0 "$RC"
  assert_eq "no local settings: .ai/config.local.yaml does not exist" "$OUT"
  assert_no_file .ai/config.local.yaml
}

# stdout is the file that would be written and nothing else — `jig-setup`
# shows a dry run to a person as the file — so the report goes to stderr, and
# says "would unset" for a run that removed nothing. `run` merges the two
# streams, so this one captures them apart.
test_config_unset_dry_run_prints_the_file_on_stdout_and_the_report_on_stderr() {
  fixture_jig_repo
  printf '%s\n' "agent.git: pr" "other: 1" > .ai/config.local.yaml
  local before out err
  before=$(cat .ai/config.local.yaml)

  out=$(jig config unset other --local --dry-run 2>/dev/null)
  err=$(jig config unset other --local --dry-run 2>&1 >/dev/null)
  assert_eq "agent.git: pr" "$out"
  assert_contains "$err" "config: would unset other (.ai/config.local.yaml)"
  assert_contains "$err" "config: dry run, nothing written to .ai/config.local.yaml"
  assert_eq "$before" "$(cat .ai/config.local.yaml)"
  _assert_no_tmp_leftovers
}

test_config_unset_without_local_refuses() {
  fixture_jig_repo
  printf '%s\n' "agent.git: pr" > .ai/config.local.yaml

  run jig config unset agent.git
  assert_eq 1 "$RC"
  assert_contains "$OUT" "only --local is supported"
  assert_eq "agent.git: pr" "$(cat .ai/config.local.yaml)"
}

test_config_unset_without_a_key_refuses() {
  fixture_jig_repo

  run jig config unset --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "missing key"
}

test_config_unset_unknown_flag_refuses() {
  fixture_jig_repo

  run jig config unset agent.git --local --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown flag: --bogus"
}

test_config_unset_a_name_the_file_could_not_hold_refuses() {
  fixture_jig_repo

  run jig config unset "agent git" --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a key name"
}

test_config_unset_is_listed_in_help() {
  fixture_jig_repo

  run jig config help
  assert_eq 0 "$RC"
  assert_contains "$OUT" "jig config unset <key> [<key>...] --local [--dry-run | --revision <n>] [--json]"
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

# --- the key inventory agrees with the code and the three texts --------------
#
# `jig_config_keys` (config.sh) is written by hand. These four tests are the
# machine that keeps it honest, and they are the reason the report built on it
# can be trusted: the list of keys a project is told about is only as good as
# its agreement with the code that reads them, and nothing but a test computes
# that agreement. RULES.md says the same of its own deletion paragraph, which
# lapsed four times because nothing did.

# _config_normalise — a `<key><TAB><default>` stream with each default reduced
# to the space-separated form a reader is handed: `[claude, codex]` is how a
# person writes a list in the file, `claude codex` is what `cfg_list` gets as
# its default, and the two must not be called a disagreement.
_config_normalise() {
  awk -F'\t' '{
    d = $2
    gsub(/[][]/, "", d); gsub(/,/, " ", d)
    gsub(/  +/, " ", d); sub(/^ /, "", d); sub(/ $/, "", d)
    print $1 "\t" d
  }' | sort -u
}

# _config_declared — the inventory, normalised.
_config_declared() {
  bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_config_keys | awk "{ key = \$1; \$1 = \"\"; sub(/^ /, \"\"); print key \"\t\" \$0 }"
  ' | _config_normalise
}

# _config_read_sites — `<key><TAB><default>` for every literal call to a
# config reader in the framework's own scripts, computed, not listed.
# `cfg_v <var> <key> [default]` is read past its variable name. Comment
# lines are skipped, and a key written as a variable cannot match, so a reader
# called with one would go unseen — today none is, and the inventory test
# below is what would notice it as a missing key.
_config_read_sites() {
  # shellcheck disable=SC2016  # an awk program, not a shell expansion
  find "$JIG_HOME/scripts" -type f \( -name jig -o -name jig-session-hook -o -name '*.sh' \) -print0 \
    | xargs -0 awk '
        /^[[:space:]]*#/ { next }
        {
          line = $0
          while (match(line, /(^|[^A-Za-z0-9_.])(cfg|cfg_bool|cfg_list|cfg_list_lines|cfg_v[ \t]+[A-Za-z_][A-Za-z0-9_]*)[ \t]+[a-z][A-Za-z0-9_.]*/)) {
            seg = substr(line, RSTART, RLENGTH)
            line = substr(line, RSTART + RLENGTH)
            n = split(seg, part, /[ \t]+/)
            rest = line
            sub(/^[ \t]+/, "", rest)
            dflt = ""
            if (substr(rest, 1, 1) == "\"") {
              body = substr(rest, 2)
              if (match(body, /"/)) dflt = substr(body, 1, RSTART - 1)
            } else if (match(rest, /^[^ \t)|;&]+/)) {
              dflt = substr(rest, RSTART, RLENGTH)
            }
            print part[n] "\t" dflt
          }
        }
    ' | _config_normalise
}

test_config_inventory_matches_every_reader_call_site() {
  fixture_repo
  local declared sites worktree_default
  declared=$(_config_declared)
  sites=$(_config_read_sites)

  # `git.worktree_root` is the one key whose real default is not at its call
  # site: `cfg git.worktree_root ""`, and _task_worktree_root then builds
  # `../<project>.worktrees` from the project's own directory name, which no
  # literal could hold. Asserted rather than waved through, so that a literal
  # appearing there later fails here and has to be reconciled.
  worktree_default=$(printf '%s\n' "$sites" | awk -F'\t' '$1 == "git.worktree_root" { print $2 }')
  assert_eq "" "$worktree_default" \
    "git.worktree_root now passes a default at its call site; reconcile it with jig_config_keys"
  sites=$(printf '%s\n' "$sites" \
    | sed "s|^git\.worktree_root$(printf '\t')\$|git.worktree_root$(printf '\t')../<project>.worktrees|")

  # sort -u collapses repeated reads of one key, so two rows for the same key
  # mean two different defaults for it — which this comparison reports as
  # surely as a key nobody declared.
  assert_eq "$declared" "$sites" \
    "jig_config_keys and the cfg/cfg_bool/cfg_list call sites in scripts/ disagree"
}

test_config_inventory_matches_the_schema_table() {
  fixture_repo
  local declared schema tab
  tab=$(printf '\t')
  declared=$(_config_declared)
  # A key with no default — off until a person sets it — is tabled with a
  # bare `-` in the default column, and reads as the empty default it is.
  schema=$(sed -n -e "s/^| \`\([a-z][A-Za-z0-9_.]*\)\` | \`\([^\`]*\)\` |.*/\1${tab}\2/p" \
    -e "s/^| \`\([a-z][A-Za-z0-9_.]*\)\` | - |.*/\1${tab}/p" \
    "$JIG_HOME/schemas/config.md" | _config_normalise)
  assert_eq "$declared" "$schema" \
    "jig_config_keys and the table in schemas/config.md disagree"
}

test_config_inventory_is_covered_by_the_template_and_the_docs() {
  fixture_repo
  local key esc missing_template="" missing_docs=""

  # Every key a project's own file may answer for has to be in the template,
  # commented or not: a project installed today would otherwise be told on its
  # first day that it is missing a key Jig never offered it.
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    esc=${key//./\\.}
    grep -qE "^#?[[:space:]]*${esc}:" "$JIG_HOME/templates/config.yaml" \
      || missing_template="$missing_template $key"
  done < <(bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    while read -r key rest; do
      jig_config_local_only_key "$key" || printf "%s\n" "$key"
    done < <(jig_config_keys)
  ')
  assert_eq "" "$missing_template" "templates/config.yaml never mentions:$missing_template"

  # And every key, local-only included, is named on the page a person reads.
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    grep -qF "\`$key\`" "$JIG_HOME/docs/configuration.mdx" \
      || missing_docs="$missing_docs $key"
  done < <(_config_declared | cut -f1)
  assert_eq "" "$missing_docs" "docs/configuration.mdx never names:$missing_docs"
}

test_config_local_key_lists_are_inside_the_inventory() {
  fixture_repo
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    for key in $JIG_CFG_LOCAL_KEYS $JIG_CFG_LOCAL_ONLY_KEYS; do
      jig_config_key_known "$key" || printf "%s\n" "$key"
    done
  '
  assert_eq 0 "$RC"
  assert_eq "" "$OUT" "these local keys are in no jig_config_keys row: $OUT"
}

# route.depth trades one person's time against process
# (adr-20261002-route-depth-is-a-personal-choice): full or lean, local only.
test_config_set_route_depth_validation() {
  fixture_jig_repo
  _config_accepts route.depth full
  _config_accepts route.depth lean
  _config_rejects route.depth light
  _config_rejects route.depth Lean
}

# release.merge says who merges an epic's final pull request: agent or human,
# local only (ADR-0040, amendment of 2026-10-04).
test_config_set_release_merge_validation() {
  fixture_jig_repo
  _config_accepts release.merge agent
  _config_accepts release.merge human
  _config_rejects release.merge nobody
}

test_config_release_merge_is_local_only() {
  fixture_jig_repo
  printf 'release.merge: human\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: release.merge in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
}

# The model a stage is delegated to is the runtime's word, never Jig's
# (adr-20261005-jig-names-the-roles-not-the-models): any value the file can
# hold is accepted as written, and only what the file format cannot hold is
# refused.
test_config_set_model_keys_take_any_value_the_file_can_hold() {
  fixture_jig_repo
  _config_accepts claude.implement_model sonnet
  _config_accepts claude.review_model claude-opus-4-1
  _config_accepts claude.review_model 'opus[1m]'
  _config_accepts claude.implement_model 'a model nobody has heard of'
  assert_file_contains .ai/config.local.yaml "^claude.implement_model: a model nobody has heard of$"
  assert_file_contains .ai/config.local.yaml "^claude.review_model: opus\\[1m\\]$"
  _config_rejects claude.review_model 'opus#1'
  _config_rejects claude.review_model ''
}

test_config_model_keys_are_local_only_and_off_by_default() {
  fixture_jig_repo
  printf 'claude.review_model: opus\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: claude.review_model in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
  run jig config keys
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "claude.implement_model"
  assert_contains "$(printf '%s\n' "$OUT" | awk '$1 == "claude.review_model" { print $2, $3, $4 }')" "- local only"
}

test_config_codex_model_keys_are_opaque_local_only_and_off_by_default() {
  fixture_jig_repo
  _config_accepts codex.implement_model gpt-6-luna
  _config_accepts codex.review_model 'a model nobody has heard of'
  assert_file_contains .ai/config.local.yaml "^codex.implement_model: gpt-6-luna$"
  assert_file_contains .ai/config.local.yaml "^codex.review_model: a model nobody has heard of$"
  _config_rejects codex.review_model 'gpt#6'
  _config_rejects codex.implement_model ''
  printf 'codex.review_model: gpt-6.1-sol\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: codex.review_model in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
  run jig config keys
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(printf '%s\n' "$OUT" | awk '$1 == "codex.review_model" { print $2, $3, $4 }')" "- local only"
}

test_config_executor_runtime_keys_accept_only_supported_local_runtimes() {
  fixture_jig_repo
  _config_accepts executor.implement_runtime claude
  _config_accepts executor.review_runtime codex
  _config_rejects executor.implement_runtime gemini
  run jig config set executor.implement_runtime gemini --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a runtime: claude or codex"
  _config_rejects executor.review_runtime ''
  _config_accepts executor.implement_model 'a future model'
  _config_accepts executor.review_model 'opus[1m]'
  printf 'executor.review_runtime: claude\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: executor.review_runtime in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
  run jig config keys
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(printf '%s\n' "$OUT" | awk '$1 == "executor.review_runtime" { print $2, $3, $4 }')" "- local only"
}

test_config_route_depth_is_local_only() {
  fixture_jig_repo
  printf 'route.depth: lean\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: route.depth in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
}

# --- jig-setup covers every local key ----------------------------------------
#
# A key `jig config set --local` accepts but the `jig-setup` skill never names
# is a setting no person is asked about: release.merge,
# git.delete_merged_branches and notify.autopilot were lost that way. Every
# local key appears in the skill, whether asked about or named as left out.

test_jig_setup_names_every_local_key() {
  local keys key missing=""
  keys=$(sed -n 's/^JIG_CFG_LOCAL_KEYS="\(.*\)"$/\1/p' "$ROOT/scripts/lib/config.sh")
  [ -n "$keys" ] || fail "JIG_CFG_LOCAL_KEYS not found in scripts/lib/config.sh"
  for key in $keys; do
    grep -qF "\`$key\`" "$ROOT/skills/jig-setup/SKILL.md" || missing="$missing $key"
  done
  assert_eq "" "$missing"
}

# --- --json: jig config keys, set and unset ------------------------------------
#
# What Jig UI reads and writes through (schemas/json.md, "jig config keys
# --json" and "jig config writes"): every key with its value, source and
# metadata, and a write that answers with the same objects.

# _cj <args...> — run `jig config <args> --json`; stdout in OUT, stderr in ERR,
# status in RC.
_cj() {
  set +e
  jig config "$@" --json > cj.out 2> cj.err
  RC=$?
  set -e
  OUT=$(cat cj.out)
  ERR=$(cat cj.err)
  rm -f cj.out cj.err
}

# _cj_entry <key> — the object of <key> in the envelope in OUT.
_cj_entry() {
  printf '%s\n' "$OUT" | sed 's/},{"key":"/}\n{"key":"/g' \
    | grep -F "{\"key\":\"$1\"," | head -n 1 | sed 's/^.*"keys":\[//; s/\]}}$//; s/\],"removed".*$//'
}

# _cj_code — the error.code of the envelope in OUT.
_cj_code() {
  printf '%s\n' "$OUT" | sed -n 's/.*"error":{"code":"\([^"]*\)".*/\1/p'
}

# _cj_project_set <key> <value> — <key> in .ai/config.yaml replaced, or added.
_cj_project_set() {
  { grep -v "^$1:" .ai/config.yaml || true; printf '%s: %s\n' "$1" "$2"; } > .ai/config.yaml.new
  mv .ai/config.yaml.new .ai/config.yaml
}

# _cj_rev — REV <- the clone's revision, as a read reports it.
_cj_rev() {
  REV=$(jig config keys --json | sed -n 's/^{"schema":1,"revision":\([0-9][0-9]*\),.*/\1/p')
  [ -n "$REV" ] || fail "no revision in the keys read"
}

test_config_keys_json_lists_every_key_in_the_registry_order() {
  fixture_jig_repo
  local want got
  _cj keys
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  assert_contains "$OUT" '{"schema":1,"revision":'
  assert_contains "$OUT" '"data":{"keys":[{"key":"profiles",'
  want=$(bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_config_keys | cut -d" " -f1
  ')
  got=$(printf '%s\n' "$OUT" | grep -o '{"key":"[^"]*"' | sed 's/{"key":"//; s/"$//')
  assert_eq "$want" "$got" "the keys of the JSON read are not the keys of the text one"
  # One line, whatever it holds.
  assert_eq 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
}

test_config_keys_json_pins_the_shape_of_one_key() {
  fixture_jig_repo
  _cj keys
  assert_eq '{"key":"agent.git","value":"none","set":false,"source":"default","scope":"local only","kind":"choice","allowed":["none","commit","push","pr","merge"],"default":"none","description":"How far your agent takes a finished task with git.","secret":false}' \
    "$(_cj_entry agent.git)"
  # A key with no default and no answer has no value, not an empty one.
  assert_eq '{"key":"autopilot.git","value":null,"set":false,"source":"default","scope":"local only","kind":"choice","allowed":["none","commit","push","pr","merge"],"default":null,"description":"The git level of an autopilot run; when unset, agent.git answers.","secret":false}' \
    "$(_cj_entry autopilot.git)"
  assert_contains "$(_cj_entry git.delete_merged_branches)" '"kind":"boolean","allowed":["true","false"]'
  assert_contains "$(_cj_entry housekeeping.trash_ttl)" '"kind":"duration","allowed":null'
  assert_contains "$(_cj_entry autopilot.parallel)" '"kind":"number","allowed":null'
  assert_contains "$(_cj_entry worktree.carry)" '"kind":"list","allowed":null'
  assert_contains "$(_cj_entry run.exec)" '"kind":"text","allowed":null'
}

test_config_keys_json_reports_the_layer_that_answered() {
  fixture_jig_repo
  _cj_project_set git.base_branch develop
  _cj_project_set agent.git merge
  _cj_project_set housekeeping.cadence 5d
  printf '%s\n' 'housekeeping.cadence: 2d' 'agent.ci_timeout: 12' 'git.base_branch: hacked' 'route.depth:' > .ai/config.local.yaml
  _cj keys
  assert_eq 0 "$RC" "$ERR"
  # The project answers for a key it owns.
  assert_contains "$(_cj_entry git.base_branch)" '"value":"develop","set":true,"source":"project","scope":"project"'
  # The local file wins for a key it may answer, over the project's.
  assert_contains "$(_cj_entry housekeeping.cadence)" '"value":"2d","set":true,"source":"local","scope":"local"'
  # A local-only key is read from the local file alone.
  assert_contains "$(_cj_entry agent.ci_timeout)" '"value":"12","set":true,"source":"local","scope":"local only"'
  # The project's value for a local-only key is not read, so it is not the source.
  assert_contains "$(_cj_entry agent.git)" '"value":"none","set":false,"source":"default","scope":"local only"'
  # An empty local value falls through, and a local value for a project-only
  # key is never what the reader gets.
  assert_contains "$(_cj_entry route.depth)" '"value":"full","set":false,"source":"default"'
  assert_not_contains "$OUT" hacked
  # What is reported is what a reader reads.
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    printf "%s %s %s %s %s\n" "$(cfg git.base_branch main)" "$(cfg housekeeping.cadence 1d)" "$(cfg agent.ci_timeout 30)" "$(cfg agent.git none)" "$(cfg route.depth full)"
  '
  assert_eq "develop 2d 12 none full" "$OUT"
}

test_config_keys_json_is_valid_for_quotes_backslashes_and_unicode() {
  fixture_jig_repo
  _cj_project_set git.branch_template 'a"b\c {id} é'
  printf '%s\n' 'claude.implement_model: x"y\z' > .ai/config.local.yaml
  _cj keys
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$(_cj_entry git.branch_template)" '"value":"a\"b\\c {id} é","set":true,"source":"project"'
  assert_contains "$(_cj_entry claude.implement_model)" '"value":"x\"y\\z","set":true,"source":"local"'
  # A description with a brace is whole.
  assert_contains "$OUT" '"description":"The name of a task'"'"'s branch; {id} is the task id."'
}

test_config_keys_json_never_prints_a_secret() {
  fixture_jig_repo
  local token='1234:AB"cd\ef'
  printf '%s\n' "notify.telegram.token: $token" 'notify.telegram.chat_id: 42' > .ai/config.local.yaml
  _cj keys
  assert_eq 0 "$RC" "$ERR"
  assert_eq '{"key":"notify.telegram.token","value":null,"set":true,"source":"local","scope":"local only","kind":"text","allowed":null,"default":null,"description":"The Telegram bot token messages are sent with; never shown.","secret":true}' \
    "$(_cj_entry notify.telegram.token)"
  assert_not_contains "$OUT$ERR" "1234:AB"
  assert_not_contains "$OUT$ERR" 'cd\\ef'
  assert_not_contains "$OUT$ERR" 'cd\ef'
  # Unset, a secret reads as not set.
  : > .ai/config.local.yaml
  _cj keys
  assert_contains "$(_cj_entry notify.telegram.token)" '"value":null,"set":false,"source":"default"'
}

# The same token under the spelling `cfg` reads as the key (a pattern, so `_`
# answers for `.`), and in a project file that never answers for it.
test_config_json_never_prints_a_secret_under_another_name_or_in_a_write() {
  fixture_jig_repo
  local token='9:ZZ"top\secret'
  printf '%s\n' "notify_telegram_token: $token" 'housekeeping.cadence: 2d' > .ai/config.local.yaml
  printf '%s\n' "notify.telegram.token: $token" >> .ai/config.yaml
  _cj keys
  assert_eq 0 "$RC" "$ERR"
  assert_not_contains "$OUT$ERR" "9:ZZ"
  assert_not_contains "$OUT$ERR" 'top\secret'
  assert_not_contains "$OUT$ERR" 'top\\secret'
  _cj set housekeeping.cadence 3d --local
  assert_eq 0 "$RC" "$ERR"
  assert_not_contains "$OUT$ERR" "9:ZZ"
  _cj set notify.telegram.token "$token" --local
  assert_eq 1 "$RC"
  assert_eq secret-key "$(_cj_code)"
  assert_not_contains "$OUT$ERR" "9:ZZ"
  _cj set notify.telegram.chat_id 77 housekeeping.cadence 4d --local
  assert_eq 0 "$RC" "$ERR"
  assert_not_contains "$OUT$ERR" "9:ZZ"
  _cj unset notify.telegram.token notify_telegram_token housekeeping.cadence --local
  assert_eq 0 "$RC" "$ERR"
  assert_not_contains "$OUT$ERR" "9:ZZ"
  assert_not_contains "$OUT$ERR" 'top\\secret'
  assert_contains "$(_cj_entry notify.telegram.token)" '"value":null,"set":false'
}

test_config_json_set_answers_with_the_state_of_each_key() {
  fixture_jig_repo
  local project_before
  project_before=$(cat .ai/config.yaml)
  _cj set agent.git pr --local
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  assert_contains "$OUT" '"data":{"keys":[{"key":"agent.git","value":"pr","set":true,"source":"local","scope":"local only"'
  assert_not_contains "$OUT" 'config: agent.git'
  assert_eq 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  assert_eq "agent.git: pr" "$(sed -n 's/^\(agent\.git: .*\)$/\1/p' .ai/config.local.yaml)"
  # Several pairs: one object each, in the order given, written together.
  _cj set route.depth lean agent.ci_timeout 5 --local
  assert_eq 0 "$RC" "$ERR"
  assert_eq 'route.depth agent.ci_timeout' "$(printf '%s\n' "$OUT" | grep -o '{"key":"[^"]*"' | sed 's/{"key":"//; s/"$//' | tr '\n' ' ' | sed 's/ $//')"
  assert_contains "$(_cj_entry route.depth)" '"value":"lean","set":true,"source":"local"'
  assert_contains "$(_cj_entry agent.ci_timeout)" '"value":"5"'
  assert_eq "$project_before" "$(cat .ai/config.yaml)" "project config was touched"
  _assert_no_tmp_leftovers
  # The text form reads what the JSON write wrote.
  run jig config show --local
  assert_contains "$OUT" "route.depth: lean"
}

test_config_json_set_value_with_quotes_and_backslashes() {
  fixture_jig_repo
  _cj set claude.review_model 'a"b\c' --local
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$(_cj_entry claude.review_model)" '"value":"a\"b\\c","set":true,"source":"local"'
}

test_config_json_set_refusals_carry_a_code_and_write_nothing() {
  fixture_jig_repo
  printf '%s\n' 'agent.git: commit' > .ai/config.local.yaml
  local before
  before=$(cat .ai/config.local.yaml)

  _cj set no.such.key x --local
  assert_eq 1 "$RC"
  assert_eq unknown-key "$(_cj_code)"
  _cj set git.base_branch develop --local
  assert_eq 1 "$RC"
  assert_eq not-local "$(_cj_code)"
  _cj set agent.git yes --local
  assert_eq 1 "$RC"
  assert_eq invalid-value "$(_cj_code)"
  assert_contains "$OUT" "invalid value 'yes'"
  _cj set notify.telegram.token abc --local
  assert_eq 1 "$RC"
  assert_eq secret-key "$(_cj_code)"
  _cj set agent.git pr
  assert_eq 1 "$RC"
  assert_eq usage "$(_cj_code)"
  _cj set agent.git --local
  assert_eq 1 "$RC"
  assert_eq usage "$(_cj_code)"
  _cj set agent.git pr --local --dry-run
  assert_eq 1 "$RC"
  assert_eq usage "$(_cj_code)"
  _cj set agent.git pr --local --bogus
  assert_eq 1 "$RC"
  assert_eq usage "$(_cj_code)"
  # One bad pair spoils the call: the good one is not written either.
  _cj set route.depth lean agent.git nope --local
  assert_eq 1 "$RC"
  assert_eq invalid-value "$(_cj_code)"
  assert_eq "$before" "$(cat .ai/config.local.yaml)"
  _assert_no_tmp_leftovers

  # The text form says the same thing, in the words it always did.
  run jig config set no.such.key x --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no.such.key is not a local key"
}

test_config_json_write_without_a_repository_or_project_is_refused_by_code() {
  local dir="$JIG_TEST_TMP.empty"
  mkdir -p "$dir"
  ( cd "$dir" && jig config keys --json > out 2> err ) || true
  assert_contains "$(cat "$dir/out")" '"error":{"code":"not-a-repository"'
}

test_config_json_set_takes_an_optional_revision() {
  fixture_jig_repo
  _cj_rev
  local rev=$REV
  _cj set route.depth lean --local --revision "$rev"
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$(_cj_entry route.depth)" '"value":"lean"'
  # The write raised the revision past the one it was sent: that one is stale.
  _cj set route.depth full --local --revision "$rev"
  assert_eq 1 "$RC"
  assert_eq stale-revision "$(_cj_code)"
  assert_eq "route.depth: lean" "$(grep '^route.depth' .ai/config.local.yaml)"
  _assert_no_tmp_leftovers
  # A write raised the revision, so a reader sees something changed.
  _cj_rev
  assert_eq 1 "$([ "$REV" -gt "$rev" ] && echo 1 || echo 0)" "the write did not raise the revision"
  _cj set route.depth full --local --revision "$REV"
  assert_eq 0 "$RC" "$ERR"
  # A malformed revision is a usage error, and so is one without a value.
  _cj set route.depth lean --local --revision 08
  assert_eq usage "$(_cj_code)"
  _cj set route.depth lean --local --revision
  assert_eq usage "$(_cj_code)"
  _cj set route.depth lean --local --revision ""
  assert_eq usage "$(_cj_code)"
}

test_config_text_set_and_unset_take_a_revision_too() {
  fixture_jig_repo
  _cj_rev
  local rev=$REV
  run jig config set route.depth lean --local --revision "$rev"
  assert_eq 0 "$RC" "$OUT"
  run jig config set route.depth full --local --revision "$rev"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the clone changed since revision $rev"
  run jig config unset route.depth --local --revision "$rev"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the clone changed since revision $rev"
  assert_eq "route.depth: lean" "$(grep '^route.depth' .ai/config.local.yaml)"
}

test_config_json_unset_answers_with_the_state_and_what_was_removed() {
  fixture_jig_repo
  printf '%s\n' 'agent.git: pr' 'route.depth: lean' 'other.key: v' > .ai/config.local.yaml
  _cj unset agent.git other.key never.set --local
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  assert_contains "$OUT" '"data":{"keys":[{"key":"agent.git","value":"none","set":false,"source":"default"'
  # A key no reader answers from has no object, and is removed all the same.
  assert_not_contains "$OUT" '"key":"other.key"'
  assert_contains "$OUT" '"removed":["agent.git","other.key"]}}'
  assert_eq "route.depth: lean" "$(cat .ai/config.local.yaml)"
  assert_not_contains "$OUT" 'config: unset'
  _assert_no_tmp_leftovers
}

test_config_json_unset_that_changes_nothing_leaves_file_and_revision_alone() {
  fixture_jig_repo
  printf '%s\n' 'route.depth: lean' > .ai/config.local.yaml
  touch -t 202001010000 .ai/config.local.yaml
  _cj_rev
  local rev=$REV
  _cj unset agent.git --local
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"removed":[]}}'
  _cj_rev
  assert_eq "$rev" "$REV" "a no-op unset raised the revision"
  assert_eq "" "$(find .ai/config.local.yaml -newermt 2020-01-02)" "a no-op unset rewrote the file"
  assert_eq "route.depth: lean" "$(cat .ai/config.local.yaml)"
}

test_config_json_unset_without_a_local_file_answers_with_data() {
  fixture_jig_repo
  assert_no_file .ai/config.local.yaml
  _cj unset agent.git --local
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"data":{"keys":[{"key":"agent.git","value":"none","set":false'
  assert_contains "$OUT" '"removed":[]}}'
  assert_no_file .ai/config.local.yaml
}

test_config_json_unset_refusals_carry_a_code() {
  fixture_jig_repo
  printf '%s\n' 'agent.git: pr' > .ai/config.local.yaml
  _cj unset --local
  assert_eq usage "$(_cj_code)"
  _cj unset agent.git
  assert_eq usage "$(_cj_code)"
  _cj unset 'bad key' --local
  assert_eq usage "$(_cj_code)"
  _cj unset agent.git --local --dry-run
  assert_eq usage "$(_cj_code)"
  _cj_rev
  _cj unset agent.git --local --revision 1
  assert_eq stale-revision "$(_cj_code)"
  assert_eq "agent.git: pr" "$(cat .ai/config.local.yaml)"
}

test_config_keys_json_refuses_an_argument_and_a_project_without_jig() {
  fixture_jig_repo
  _cj keys extra
  assert_eq 1 "$RC"
  assert_eq usage "$(_cj_code)"
  rm -rf .ai/config.yaml
  _cj keys
  assert_eq 1 "$RC"
  assert_eq not-initialised "$(_cj_code)"
}

test_config_json_is_in_the_help() {
  run jig config help
  assert_contains "$OUT" "jig config keys [--json]"
  assert_contains "$OUT" "--revision <n>"
}

# --- the registry's metadata -----------------------------------------------------

# Every key has a kind and a description, and what a kind promises is true:
# the fixed sets are what the validator accepts, so a page that offers them
# offers nothing the command then refuses.
test_config_registry_rows_carry_their_metadata() {
  fixture_repo
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    n=0
    while IFS="|" read -r key default kind allowed desc extra; do
      n=$((n + 1))
      [ -z "$extra" ] || { echo "$key: more than five fields"; continue; }
      case "$kind" in
        boolean | choice | duration | number | text | list) ;;
        *) echo "$key: kind \"$kind\" is not one of the kinds"; continue ;;
      esac
      [ -n "$desc" ] || echo "$key: no description"
      case "$desc" in *\\\\*) echo "$key: backslash in description" ;; esac
      case "$kind" in
        boolean | choice) [ -n "$allowed" ] || echo "$key: a $kind with no allowed values" ;;
        *) [ -z "$allowed" ] || echo "$key: allowed values on a $kind" ;;
      esac
      [ "$kind" != boolean ] || [ "$allowed" = true,false ] || echo "$key: a boolean allows true,false"
    done < <(jig_config_key_rows)
    [ "$n" -eq "$(jig_config_keys | wc -l | tr -d " ")" ] || echo "row count differs from jig_config_keys"
    [ "$(jig_config_key_rows | grep -c "^[a-z][A-Za-z0-9_.]*|")" -eq "$n" ] || echo "a row does not start with its key"
  '
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

test_config_registry_allowed_values_are_what_the_validator_accepts() {
  fixture_repo
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    while IFS="|" read -r key default kind allowed desc; do
      case "$kind" in boolean | choice) ;; *) continue ;; esac
      jig_config_local_key "$key" || continue
      for v in ${allowed//,/ }; do
        jig_config_value_problem "$key" "$v" >/dev/null || echo "$key: allowed value $v is refused"
      done
      if jig_config_value_problem "$key" "not-one-of-them" >/dev/null; then
        echo "$key: a value outside the set is accepted"
      fi
    done < <(jig_config_key_rows)
  '
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

test_config_registry_default_of_a_choice_or_boolean_is_allowed() {
  fixture_repo
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    while IFS="|" read -r key default kind allowed desc; do
      case "$kind" in boolean | choice) ;; *) continue ;; esac
      [ -n "$default" ] || continue
      case ",$allowed," in *",$default,"*) ;; *) echo "$key: default $default is not allowed" ;; esac
    done < <(jig_config_key_rows)
  '
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

test_config_json_scope_and_secret_follow_the_lists_they_are_derived_from() {
  fixture_jig_repo
  _cj keys
  local json=$OUT
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    for key in $(jig_config_keys | cut -d" " -f1); do
      printf "%s %s\n" "$key" "$(jig_config_key_scope "$key")"
    done
  '
  local want="$OUT" key got=""
  OUT=$json
  while read -r key _; do
    [ -n "$key" ] || continue
    # `scope` is one or two words: re-read it from the object.
    got="$got$key $(_cj_entry "$key" | sed 's/.*"scope":"\([^"]*\)".*/\1/')
"
  done <<EOF
$want
EOF
  assert_eq "$want" "$(printf '%s' "$got")"
  assert_eq 1 "$(printf '%s\n' "$OUT" | grep -o '"secret":true' | wc -l | tr -d ' ')"
}

test_git_flow_is_not_a_local_key() {
  fixture_jig_repo
  run jig config set git.flow staging --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "git.flow is not a local key"
}

# _flow_ask <function> — what a config.sh reader of the git flow answers here.
_flow_ask() {
  run bash -c "
    JIG_PROJECT=\$(pwd -P); JIG_LIB=\"\$JIG_HOME/scripts/lib\"
    . \"\$JIG_LIB/common.sh\"; . \"\$JIG_LIB/config.sh\"
    $1"
}

test_git_flow_problems_name_what_cannot_work() {
  fixture_jig_repo
  _flow_ask jig_git_flow_problems
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"

  printf 'git.flow: staging\n' >> .ai/config.yaml
  _flow_ask jig_git_flow_problems
  assert_contains "$OUT" "needs the name of the staging branch"

  printf 'git.staging_branch: refs/heads/stage\n' >> .ai/config.yaml
  _flow_ask jig_git_flow_problems
  assert_contains "$OUT" "'refs/heads/stage' is a ref"
}

test_git_flow_problems_refuse_the_base_branch_and_unknown_bricks() {
  fixture_jig_repo
  printf 'git.flow: staging\ngit.staging_branch: main\ngit.staging_review: maybe\n' >> .ai/config.yaml
  _flow_ask jig_git_flow_problems
  assert_contains "$OUT" "'main' is the base branch"
  assert_contains "$OUT" "git.staging_review: 'maybe'"
}

test_git_flow_offer_reads_origin_and_stops_once_a_flow_is_named() {
  fixture_jig_repo
  git update-ref refs/remotes/origin/staging HEAD
  _flow_ask jig_staging_offer
  assert_eq "staging" "$OUT"

  printf 'git.flow: direct\n' >> .ai/config.yaml
  _flow_ask jig_staging_offer
  assert_eq "" "$OUT"
}

test_git_flow_problems_refuse_an_unknown_flow() {
  fixture_jig_repo
  printf 'git.flow: trunk\n' >> .ai/config.yaml
  _flow_ask jig_git_flow_problems
  assert_contains "$OUT" "git.flow: 'trunk' is not a flow"
}

test_git_flow_problems_name_a_name_git_rejects_and_every_brick() {
  fixture_jig_repo
  printf 'git.flow: staging\ngit.staging_branch: bad..name\ngit.staging_land: x\ngit.promote_merge: z\n' >> .ai/config.yaml
  _flow_ask jig_git_flow_problems
  assert_contains "$OUT" "git rejects the name 'bad..name'"
  assert_contains "$OUT" "git.staging_land: 'x'"
  assert_contains "$OUT" "git.promote_merge: 'z'"
}
