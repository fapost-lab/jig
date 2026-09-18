# Tests for `jig doctor` (ARCHITECTURE.md, Scripts layout: reporting
# commands; the environment-check task).
# shellcheck shell=bash

# --- PATH fixtures ------------------------------------------------------------
#
# A curated tool directory, resolved with `env -i` rather than a bare
# `command -v` (conventions/shell.md: "a test that asserts a tool is absent
# controls PATH by enumerating the tools it needs, never by listing
# directories it believes are tool-free"). `jig doctor` itself needs bash,
# git and the usual text tools to run at all; cmd/cygpath are deliberately
# left off this list so a test can prove they are genuinely absent rather
# than merely unmentioned.
_DOCTOR_TOOLS="bash sh git sed awk grep find mktemp cat cp mv rm mkdir sort
tr head tail wc chmod ls date dirname basename cmp paste stat readlink diff
env printf cut"

_doctor_tools_bin() {
  local dir t p
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-doctor-tools.XXXXXX") || return 1
  for t in $_DOCTOR_TOOLS; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in /*) ln -sf "$p" "$dir/$t" ;; esac
  done
  printf '%s\n' "$dir"
}

# --- basic shape ---------------------------------------------------------------

test_doctor_rejects_arguments() {
  run jig doctor extra
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument: extra"
}

test_doctor_help_lists_doctor() {
  run jig help
  assert_contains "$OUT" "doctor"
}

test_doctor_outside_repository_reports_global_checks_only() {
  mkdir outside && cd outside || return 1
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "git: "
  assert_not_contains "$OUT" "project:"
  assert_not_contains "$OUT" "framework version:"
  assert_not_contains "$OUT" "upgrade check:"
  assert_contains "$OUT" "doctor: "
}

test_doctor_uninitialised_repository_warns_project_not_initialised() {
  fixture_repo
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  project: not initialised"
  assert_contains "$OUT" "fix: jig init"
  assert_not_contains "$OUT" "framework version:"
}

# --- git identity --------------------------------------------------------------
# The runner exports GIT_AUTHOR_NAME/EMAIL for commits but never sets the
# `user.name`/`user.email` config `git config --get` reads, so the default
# state really is unset; each test below still sets/unsets it explicitly
# rather than relying on that default staying true.

test_doctor_git_identity_warns_when_unset() {
  mkdir work && cd work || return 1
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  git identity: not set:"
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'fix: git config --global user.name "Your Name"'
  assert_contains "$OUT" "git config --global user.email you@example.com"
}

test_doctor_git_identity_ok_when_set() {
  mkdir work && cd work || return 1
  git config --global user.name "Doctor Test"
  git config --global user.email "doctor@example.com"
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ok    git identity: Doctor Test <doctor@example.com>"
}

# --- directory links (ADR-0029, common.sh's jig_link_detect) ------------------

test_doctor_directory_links_symlink_ok_on_this_machine() {
  skip_unless_symlinks
  mkdir work && cd work || return 1
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ok    directory links: symlink"
}

test_doctor_directory_links_none_warns() {
  skip_unless_link_simulation
  local tools stub
  tools=$(_doctor_tools_bin)
  stub=$(mktemp -d "${TMPDIR:-/tmp}/jig-doctor-none.XXXXXX")
  cat > "$stub/ln" <<'EOF'
#!/bin/sh
# Fake `ln`: every invocation fails, so jig_link_detect cannot make a
# symlink; cmd/cygpath are simply absent from this PATH, so the junction
# fallback fails too and the measurement settles on "none".
exit 1
EOF
  chmod +x "$stub/ln"

  run env PATH="$stub:$tools" "$JIG_BIN" doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  directory links: task worktrees are unavailable"
  assert_contains "$OUT" "fix: enable Windows Developer Mode, or use a local NTFS or POSIX filesystem"
}

# Optional per the task: proves the junction branch itself, not just that
# "no symlink" falls back to something. `ln -s` is made to fail so
# jig_link_detect reaches _jig_junction; the fake `cmd`/`cygpath` pair then
# fulfils that function's actual contract (cygpath -w echoes a path, cmd /c
# mklink /J makes the link) using the real `ln` underneath.
test_doctor_directory_links_junction_ok() {
  skip_unless_link_simulation
  local tools stub real_ln
  tools=$(_doctor_tools_bin)
  real_ln=$(command -v ln)
  stub=$(mktemp -d "${TMPDIR:-/tmp}/jig-doctor-junction.XXXXXX")

  cat > "$stub/ln" <<'EOF'
#!/bin/sh
# Refuse a real symlink so jig_link_detect falls through to the junction path.
exit 1
EOF
  chmod +x "$stub/ln"

  cat > "$stub/cygpath" <<'EOF'
#!/bin/sh
# cygpath -w <path>: this fixture only needs the path echoed back.
shift
printf '%s\n' "$1"
EOF
  chmod +x "$stub/cygpath"

  cat > "$stub/cmd" <<EOF
#!/bin/sh
# cmd /c mklink /J <link> <target>: fake an NTFS junction with a real symlink.
shift; shift; shift
"$real_ln" -s "\$2" "\$1"
EOF
  chmod +x "$stub/cmd"

  run env PATH="$stub:$tools" "$JIG_BIN" doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ok    directory links: junction (symlinks unavailable)"
}

# --- initialised project: the happy path ---------------------------------------

test_doctor_initialised_project_reports_no_failures() {
  fixture_jig_repo
  git add -A
  git commit -q -m "snapshot"

  run jig doctor
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "fail  "
  assert_contains "$OUT" "framework version:"
  assert_contains "$OUT" "upgrade check:"
  assert_contains "$OUT" "executable bits:"
  assert_contains "$OUT" "doctor: "
}

test_doctor_via_installed_copy() {
  fixture_jig_repo
  git add -A
  git commit -q -m "snapshot"

  run jig_installed doctor
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "fail  "
}

# --- executable bits (git ls-files -s, not the working tree's real mode) ------

test_doctor_executable_bit_warns_when_lost() {
  fixture_jig_repo
  git add -A
  git commit -q -m "snapshot"
  git update-index --chmod=-x .ai/scripts/jig

  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  executable bits: missing +x:"
  assert_contains "$OUT" ".ai/scripts/jig"
  assert_contains "$OUT" "fix: git add --chmod=+x"
}

test_doctor_executable_bit_not_committed_yet() {
  fixture_jig_repo
  # No commit at all: .ai/scripts/jig is untracked, so this check has
  # nothing in the index to read and must not treat that as a failure.
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ok    executable bits: not committed yet"
}

# --- upgrade check: reuses upgrade_pending's own 0/unknown contract -----------
# Same reproduction as tests/status.t.sh's
# test_status_omits_pending_when_source_root_unknown and tests/upgrade.t.sh's
# test_upgrade_still_dies_without_from_when_source_root_gone: a copy-mode
# install whose source checkout has since been deleted makes
# `cmd_upgrade --dry-run` die, which upgrade_pending turns into its "unknown"
# return (3) rather than propagating the die. Doctor, unlike status, reports
# that as a fail: an environment check exists to surface exactly this.

test_doctor_upgrade_check_fails_when_source_root_is_gone() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-doctor-src-del.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" >/dev/null
  rm -rf "$src"

  run jig_installed doctor
  assert_eq 1 "$RC"
  assert_contains "$OUT" "fail  upgrade check: cannot determine pending state"
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'fix: run `jig upgrade --dry-run` to see the error'
  local fail_count
  fail_count=$(printf '%s\n' "$OUT" | sed -n 's/^doctor: .* \([0-9]\{1,\}\) fail$/\1/p')
  [ "$fail_count" -ge 1 ] || fail "expected at least one fail, tally said $fail_count"
}

test_doctor_upgrade_check_warns_pending_items() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-doctor-src2.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" >/dev/null

  mkdir -p "$src/skills/jig-newthing"
  cat > "$src/skills/jig-newthing/SKILL.md" <<'EOF'
---
name: jig-newthing
description: fixture skill added to the source after init
---
# jig-newthing
Run `/jig-newthing` to do the thing.
EOF

  run jig_installed doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  upgrade check:"
  assert_contains "$OUT" "fix: jig upgrade"

  rm -rf "$src"
}

# --- session hook (mirrors status.sh's _status_session_hook contract) --------

test_doctor_session_hook_claude_not_installed_warns() {
  fixture_jig_repo
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  session hook (claude): not installed"
  assert_contains "$OUT" "fix: jig init --session-hook"
}

test_doctor_session_hook_claude_installed_ok() {
  fixture_jig_repo
  mkdir -p .claude
  printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": ".ai/scripts/jig-session-hook" } ] } ] } }\n' \
    > .claude/settings.json

  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ok    session hook (claude): installed"
}

test_doctor_session_hook_codex_not_applicable() {
  fixture_jig_repo
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ok    session hook (codex): not applicable to this runtime"
}

# --- config.local (mirrors status.sh's _status_config_local contract) -------

test_doctor_config_local_ok_when_gitignored() {
  fixture_jig_repo
  printf 'housekeeping.cadence: 3d\n' > .ai/config.local.yaml

  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ok    config.local: ignored by git"
}

test_doctor_config_local_warns_when_not_gitignored() {
  fixture_jig_repo
  printf 'housekeeping.cadence: 3d\n' > .ai/config.local.yaml
  grep -v 'config.local.yaml' .gitignore > .gitignore.tmp
  mv .gitignore.tmp .gitignore

  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  config.local: not ignored by git, can be committed"
  assert_contains "$OUT" "fix: jig init"
}

# --- final tally line -----------------------------------------------------------

test_doctor_tally_counts_every_line() {
  fixture_jig_repo
  git add -A
  git commit -q -m "snapshot"
  git update-index --chmod=-x .ai/scripts/jig

  run jig doctor
  assert_eq 0 "$RC"
  local ok warn fail
  ok=$(printf '%s\n' "$OUT" | grep -c '^ok    ')
  warn=$(printf '%s\n' "$OUT" | grep -c '^warn  ')
  fail=$(printf '%s\n' "$OUT" | grep -c '^fail  ')
  assert_contains "$OUT" "doctor: $ok ok, $warn warn, $fail fail"
}

# --- instruction files (mirrors status.sh's _status_instructions) -------------

test_doctor_instructions_ok_after_fresh_init() {
  fixture_jig_repo
  run jig doctor
  assert_contains "$OUT" "ok    instructions (codex): Jig section present"
}

test_doctor_instructions_warns_for_a_foreign_agents() {
  fixture_jig_repo
  printf '# Our own rules\n' > AGENTS.md
  run jig doctor
  assert_eq 0 "$RC"
  assert_contains "$OUT" "warn  instructions (codex): no Jig section in AGENTS.md"
  assert_contains "$OUT" "fix: run the jig-init skill"
}

test_doctor_instructions_warns_for_a_foreign_claude_md() {
  fixture_jig_repo
  printf '# Notes for Claude\n' > CLAUDE.md
  run jig doctor
  assert_contains "$OUT" "warn  instructions (claude): no Jig section in CLAUDE.md"
  assert_contains "$OUT" "ok    instructions (codex): Jig section present"
}
