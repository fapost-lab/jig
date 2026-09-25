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
  assert_contains "$OUT" "jig config unset <key> [<key>...] --local [--dry-run]"
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
# config reader in the framework's own scripts, computed, not listed. Comment
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
          while (match(line, /(^|[^A-Za-z0-9_.])(cfg|cfg_bool|cfg_list|cfg_list_lines)[ \t]+[a-z][A-Za-z0-9_.]*/)) {
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
  schema=$(sed -n "s/^| \`\([a-z][A-Za-z0-9_.]*\)\` | \`\([^\`]*\)\` |.*/\1${tab}\2/p" \
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
