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
    if cfg_bool nope; then printf "X"; else printf "F"; fi
  '
  assert_eq 0 "$RC"
  assert_eq "7d|generic php|dflt|[generic, php]|TF" "$OUT"
}

# jig_has_line is how a script asks "is this a line of that text" without
# piping printf into grep -q (conventions/shell.md, pipefail): whole lines,
# compared as strings, never as patterns.
test_jig_has_line_matches_whole_lines_as_strings() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"
    text=$(printf "alpha\nb*ta\ngamma")
    for probe in alpha "b*ta" gamma alph lpha "b?ta" beta ""; do
      if jig_has_line "$probe" "$text"; then printf "%s=1 " "$probe"; else printf "%s=0 " "$probe"; fi
    done
    jig_has_line x "" || printf "empty=0"
  '
  assert_eq 0 "$RC"
  assert_eq "alpha=1 b*ta=1 gamma=1 alph=0 lpha=0 b?ta=0 beta=0 =0 empty=0" "$OUT"
}

# No script pipes a shell value into a reader that can quit before the end of
# its input: bash writes the pipe line by line, the writer dies of SIGPIPE and
# pipefail turns a match into a failure about once in a hundred runs on Linux.
test_no_script_pipes_printf_into_an_early_quitting_reader() {
  local hits
  hits=$(grep -rnE "(printf|echo)[^|#]*\|[[:space:]]*(grep -[a-zA-Z]*q|head([[:space:]]|$))" \
    "$JIG_HOME/scripts" "$JIG_HOME/profiles" | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)
  assert_eq "" "$hits"
}

# --- .ai/config.local.yaml (ADR-0038) ----------------------------------------

test_cfg_local_value_wins_for_a_whitelisted_key() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
housekeeping.cadence: 1d
housekeeping.fetch: true
EOF
  cat > .ai/config.local.yaml <<'EOF'
housekeeping.cadence: 9d
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    printf "%s|%s|%s" "$(cfg housekeeping.cadence)" "$(cfg housekeeping.fetch)" "$(cfg housekeeping.trash_ttl dflt)"
  '
  assert_eq 0 "$RC"
  # cadence: local overrides project. fetch: absent locally, project answers.
  # trash_ttl: absent from both, the default is used.
  assert_eq "9d|true|dflt" "$OUT"
}

test_cfg_ignores_a_non_whitelisted_key_in_the_local_file() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
git.base_branch: main
EOF
  cat > .ai/config.local.yaml <<'EOF'
git.base_branch: other
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg git.base_branch
  '
  assert_eq 0 "$RC"
  assert_eq "main" "$OUT"
}

test_cfg_empty_local_value_falls_through_to_project() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
housekeeping.cadence: 3d
EOF
  cat > .ai/config.local.yaml <<'EOF'
housekeeping.cadence:
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg housekeeping.cadence
  '
  assert_eq 0 "$RC"
  assert_eq "3d" "$OUT"
}

test_cfg_in_a_worktree_reads_the_main_checkouts_local_file() {
  mkdir repo
  cd repo || fail "setup"
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
housekeeping.cadence: 1d
EOF
  cat > .ai/config.local.yaml <<'EOF'
housekeeping.cadence: 9d
EOF
  local main_root
  main_root=$(pwd -P)

  git worktree add -q ../wt -b wtbranch >/dev/null

  # A local file placed inside the worktree itself must not be read: one
  # local file serves every worktree of a clone (ADR-0038).
  mkdir -p ../wt/.ai
  cat > ../wt/.ai/config.local.yaml <<'EOF'
housekeeping.cadence: 5d
EOF

  # A plain checkout's clone root is itself.
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_config_clone_root
  '
  assert_eq 0 "$RC"
  assert_eq "$main_root" "$OUT"

  run bash -c '
    cd ../wt || exit 1
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    printf "%s|%s" "$(cfg housekeeping.cadence)" "$(jig_config_clone_root)"
  '
  assert_eq 0 "$RC"
  assert_eq "9d|$main_root" "$OUT"
}

# --- JIG_CFG_LOCAL_ONLY_KEYS: agent.git (design.md, .ai/specs/autopilot/) ----
# A value committed to .ai/config.yaml would hand every contributor's agent
# the same git rights, so `cfg` must never read `agent.git` from the project
# layer — only from .ai/config.local.yaml, or the `none` default.

test_cfg_agent_git_in_project_config_is_never_read() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
agent.git: pr
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg agent.git none
  '
  assert_eq 0 "$RC"
  assert_eq "none" "$OUT"
}

test_cfg_agent_git_local_value_is_read() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
agent.git: pr
EOF
  cat > .ai/config.local.yaml <<'EOF'
agent.git: commit
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg agent.git none
  '
  assert_eq 0 "$RC"
  assert_eq "commit" "$OUT"
}

test_jig_agent_git_default_is_none() {
  fixture_repo
  mkdir -p .ai
  : > .ai/config.yaml
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_agent_git
  '
  assert_eq 0 "$RC"
  assert_eq "none" "$OUT"
}

test_jig_agent_git_rejects_an_unknown_value_but_still_prints_it() {
  fixture_repo
  mkdir -p .ai
  : > .ai/config.yaml
  cat > .ai/config.local.yaml <<'EOF'
agent.git: yolo
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_agent_git
  '
  assert_eq 1 "$RC"
  assert_eq "yolo" "$OUT"
}

test_jig_config_project_ignored_reports_agent_git_set_in_project_config() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
agent.git: pr
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_config_project_ignored
  '
  assert_eq 0 "$RC"
  assert_eq "$(printf 'agent.git\tpr')" "$OUT"
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

test_help_lists_spec_list() {
  run jig help
  assert_contains "$OUT" "spec list"
}

test_help_lists_spec_new() {
  run jig help
  assert_contains "$OUT" "spec new <id>"
}

test_help_lists_spec_done() {
  run jig help
  assert_contains "$OUT" "spec done <task-id>"
}

test_help_lists_spec_remove() {
  run jig help
  assert_contains "$OUT" "spec remove <id>"
}

test_help_lists_spec_close() {
  run jig help
  assert_contains "$OUT" "spec close <id>"
}

test_help_lists_spec_epic() {
  run jig help
  assert_contains "$OUT" "spec epic <id>"
}

# --- jig_trash_dest (shared by housekeeping and `jig spec remove`) -----------

test_jig_trash_dest_no_collision() {
  fixture_repo
  local today root
  today=$(date +%Y-%m-%d)
  # JIG_PROJECT is the physical path in bash's own spelling (jig_require_repo):
  # `pwd -P` matches it, where plain $PWD keeps macOS's /tmp -> /private/tmp
  # link and git's --show-toplevel prints C:/... on Windows.
  root=$(pwd -P)
  lib_run 'jig_require_repo; jig_trash_dest foo'
  assert_eq 0 "$RC"
  assert_eq "$root/.ai/runtime/trash/$today/foo" "$OUT"
}

test_jig_trash_dest_appends_suffix_on_collision() {
  fixture_repo
  local today root
  today=$(date +%Y-%m-%d)
  root=$(pwd -P)
  mkdir -p ".ai/runtime/trash/$today"
  touch ".ai/runtime/trash/$today/foo"

  lib_run 'jig_require_repo; jig_trash_dest foo'
  assert_eq 0 "$RC"
  assert_eq "$root/.ai/runtime/trash/$today/foo-2" "$OUT"

  mkdir -p ".ai/runtime/trash/$today/foo-2"
  lib_run 'jig_require_repo; jig_trash_dest foo'
  assert_eq 0 "$RC"
  assert_eq "$root/.ai/runtime/trash/$today/foo-3" "$OUT"
}

test_jig_trash_dest_creates_nothing() {
  fixture_repo
  lib_run 'jig_require_repo; jig_trash_dest bar'
  assert_eq 0 "$RC"
  assert_no_file .ai/runtime/trash
}

# --- jig_task_base / jig_base_ref (ADR-0039) ----------------------------------
# The one answer `task`, `housekeeping`, `context` and `knowledge` must never
# disagree about: the branch a task was cut from and has to land on.

# base_run <shell code> — like lib_run, but with config.sh also sourced:
# jig_task_base reads the configured fallback through `cfg`.
base_run() {
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"; '"$1"
}

test_jig_task_base_reads_the_state_field() {
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\n' > .ai/config.yaml
  mkdir -p .ai/workspace/tasks/T-1
  printf 'task_id: T-1\nbranch: task/T-1\nbase_branch: epic/x\n' > .ai/workspace/tasks/T-1/state

  base_run 'jig_require_repo; jig_task_base T-1'
  assert_eq 0 "$RC"
  assert_eq "epic/x" "$OUT"
}

test_jig_task_base_falls_back_to_configured_base_without_the_field() {
  # A workspace started before base_branch existed carries no such line, and
  # a project can also configure a base other than main.
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\ngit.base_branch: develop\n' > .ai/config.yaml
  mkdir -p .ai/workspace/tasks/T-1
  printf 'task_id: T-1\nbranch: task/T-1\n' > .ai/workspace/tasks/T-1/state

  base_run 'jig_require_repo; jig_task_base T-1'
  assert_eq 0 "$RC"
  assert_eq "develop" "$OUT"
}

test_jig_task_base_falls_back_when_the_state_file_is_missing() {
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\n' > .ai/config.yaml

  base_run 'jig_require_repo; jig_task_base no-such-task'
  assert_eq 0 "$RC"
  assert_eq "main" "$OUT"
}

test_jig_task_base_invalid_id_uses_the_configured_base() {
  # An id jig_valid_id rejects (empty, leading dash, leading dot) must never
  # be built into a path under .ai/workspace/tasks/ — only the fallback.
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\n' > .ai/config.yaml

  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  base_run 'jig_require_repo; for id in "" "-x" "../etc"; do printf "%s=%s " "$id" "$(jig_task_base "$id")"; done'
  assert_eq 0 "$RC"
  assert_eq "=main -x=main ../etc=main " "$OUT"
}

test_jig_base_ref_prefers_the_remote_tracking_ref() {
  # Landed means landed on the remote (a local base can be behind or ahead of
  # it). Faked without a real remote: jig_base_ref only asks whether the ref
  # resolves to a commit.
  fixture_repo
  git branch feature
  git update-ref refs/remotes/origin/feature "$(git rev-parse HEAD)"

  base_run 'jig_require_repo; jig_base_ref feature'
  assert_eq 0 "$RC"
  assert_eq "refs/remotes/origin/feature" "$OUT"
}

test_jig_base_ref_falls_back_to_the_local_branch() {
  fixture_repo
  git branch feature

  base_run 'jig_require_repo; jig_base_ref feature'
  assert_eq 0 "$RC"
  assert_eq "refs/heads/feature" "$OUT"
}

test_jig_base_ref_prints_nothing_when_neither_resolves() {
  fixture_repo

  base_run 'jig_require_repo; jig_base_ref does-not-exist; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

test_jig_base_ref_empty_name_prints_nothing() {
  fixture_repo

  base_run 'jig_require_repo; jig_base_ref; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

# --- jig_spec_epic (ADR-0040) --------------------------------------------------
# Parses the roadmap's Epic: line; moved to common.sh so both spec.sh and
# task.sh can read it without one command library sourcing another.

test_jig_spec_epic_open_line() {
  printf 'Destination: x\n\nEpic: epic/alpha\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha open" "$OUT"
}

test_jig_spec_epic_finished_line() {
  printf 'Destination: x\n\nEpic: epic/alpha — finished\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha finished" "$OUT"
}

test_jig_spec_epic_dash_variants_before_finished() {
  local sep
  for sep in '—' '-' '--'; do
    printf 'Destination: x\n\nEpic: epic/alpha %s finished\n' "$sep" > roadmap.md
    lib_run 'jig_spec_epic roadmap.md'
    assert_eq 0 "$RC" "separator [$sep]"
    assert_eq "epic/alpha finished" "$OUT" "separator [$sep]"
  done
}

test_jig_spec_epic_no_line_prints_nothing() {
  printf 'Destination: x\n\nNothing here.\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

test_jig_spec_epic_two_conflicting_lines_fails() {
  printf 'Destination: x\n\nEpic: epic/alpha\nEpic: epic/beta\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md; printf "rc=%s" "$?"'
  assert_eq "rc=2" "$OUT"
}

test_jig_spec_epic_two_lines_disagreeing_only_on_state_fails() {
  # Same branch, different state — still a guess about which base a task is
  # cut from, so it is refused exactly like a disagreement on the branch.
  printf 'Destination: x\n\nEpic: epic/alpha\nEpic: epic/alpha — finished\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md; printf "rc=%s" "$?"'
  assert_eq "rc=2" "$OUT"
}

test_jig_spec_epic_same_line_repeated_is_fine() {
  printf 'Destination: x\n\nEpic: epic/alpha\nEpic: epic/alpha\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha open" "$OUT"
}

test_jig_spec_epic_reads_stdin_as_dash() {
  # spec_epic_declare pipes `git show <ref>:<roadmap>` into it as `-`.
  lib_run 'printf "Destination: x\n\nEpic: epic/alpha\n" | jig_spec_epic -'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha open" "$OUT"
}

# --- jig_fetch_branches (ADR-0040) ---------------------------------------------

test_jig_fetch_branches_without_origin_is_a_noop() {
  fixture_repo
  base_run 'jig_require_repo; jig_fetch_branches "who" main; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

test_jig_fetch_branches_failure_warns_and_is_not_fatal() {
  fixture_repo
  git remote add origin "$PWD/no-such-remote"
  base_run 'jig_require_repo; jig_fetch_branches "spec epic" main; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "spec epic: could not fetch main from origin; using the refs this checkout has"
  assert_contains "$OUT" "rc=0"
}

test_jig_fetch_branches_one_bad_branch_does_not_stop_the_others() {
  # Each branch is fetched on its own so that one origin does not have does
  # not take the rest down with it.
  fixture_repo
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git branch real-branch
  git push -q origin real-branch
  # Never fetched generically: refs/remotes/origin/real-branch does not exist
  # here yet, so it can only appear through jig_fetch_branches's own fetch.

  base_run 'jig_require_repo; jig_fetch_branches "who" no-such-branch real-branch'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "who: could not fetch no-such-branch from origin"

  base_run 'jig_require_repo; jig_base_ref real-branch'
  assert_eq "refs/remotes/origin/real-branch" "$OUT"
}
