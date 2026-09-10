# Tests for adapters/claude/adapter.sh and adapters/codex/adapter.sh.
# These are unit tests: adapter libraries are sourced directly, without going
# through cmd_init, so the transform and copy primitives are exercised in
# isolation from the conflict-aware orchestration in scripts/lib/init.sh.
# shellcheck shell=bash

test_claude_skills_dir() {
  . "$JIG_HOME/adapters/claude/adapter.sh"
  assert_eq ".claude/skills" "$(adapter_claude_skills_dir)"
}

test_codex_skills_dir() {
  . "$JIG_HOME/adapters/codex/adapter.sh"
  assert_eq ".codex/skills" "$(adapter_codex_skills_dir)"
}

test_claude_install_skill_copies_verbatim() {
  . "$JIG_HOME/adapters/claude/adapter.sh"
  mkdir -p demo/refs project
  cat > demo/SKILL.md <<'EOF'
---
name: demo
---
Run `/jig-demo` please.
EOF
  echo "ref content" > demo/refs/notes.md

  local out
  out=$(adapter_claude_install_skill "$PWD/demo" "$PWD/project")
  assert_contains "$out" ".claude/skills/demo/SKILL.md"
  assert_contains "$out" ".claude/skills/demo/refs/notes.md"
  assert_file_contains project/.claude/skills/demo/SKILL.md 'jig-demo'
  assert_file_contains project/.claude/skills/demo/refs/notes.md "ref content"
}

test_codex_install_skill_transforms_invocations_only() {
  . "$JIG_HOME/adapters/codex/adapter.sh"
  mkdir -p demo project
  cat > demo/SKILL.md <<'EOF'
---
name: demo
---
# demo
Run `/jig-demo` to start.
See skills/jig-demo for source and skills/jig-demo/SKILL.md for details.
/jig-startline
EOF
  echo "unchanged" > demo/other.txt

  local out
  out=$(adapter_codex_install_skill "$PWD/demo" "$PWD/project")
  assert_contains "$out" ".codex/skills/demo/SKILL.md"
  assert_contains "$out" ".codex/skills/demo/other.txt"

  local content
  content=$(cat project/.codex/skills/demo/SKILL.md)
  # preceded by a backtick and by start-of-line: transformed
  # shellcheck disable=SC2016
  assert_contains "$content" '`$jig-demo`'
  # shellcheck disable=SC2016
  assert_contains "$content" '$jig-startline'
  # preceded by a letter (a file path, not an invocation): untouched
  assert_contains "$content" 'skills/jig-demo for source'
  assert_contains "$content" 'skills/jig-demo/SKILL.md for details'
  # the only occurrence that looked like an invocation was rewritten
  assert_not_contains "$content" '/jig-startline'

  assert_eq "unchanged" "$(cat project/.codex/skills/demo/other.txt)"
}

test_claude_install_instructions_creates_once() {
  mkdir -p templates project
  echo "@AGENTS.md" > templates/CLAUDE.md
  . "$JIG_HOME/adapters/claude/adapter.sh"

  local out
  out=$(adapter_claude_install_instructions "$PWD/project" "$PWD/templates")
  assert_eq "CLAUDE.md" "$out"
  assert_file_contains project/CLAUDE.md "@AGENTS.md"

  echo "user edit" > project/CLAUDE.md
  out=$(adapter_claude_install_instructions "$PWD/project" "$PWD/templates")
  assert_eq "" "$out"
  assert_file_contains project/CLAUDE.md "user edit"
}

test_codex_install_instructions_writes_nothing() {
  mkdir -p templates project
  echo "@AGENTS.md" > templates/CLAUDE.md
  . "$JIG_HOME/adapters/codex/adapter.sh"

  local out
  out=$(adapter_codex_install_instructions "$PWD/project" "$PWD/templates")
  assert_eq "" "$out"
  assert_no_file project/CLAUDE.md
}

# --- session hook installation (ADR-0024, as amended) ------------------------

adapters_source() {
  # shellcheck disable=SC1090
  . "$JIG_HOME/adapters/$1/adapter.sh"
}

test_adapter_claude_installs_the_hook_when_settings_are_absent() {
  fixture_repo
  adapters_source claude
  run adapter_claude_install_session_hook "$PWD"
  assert_eq 0 "$RC"
  assert_eq ".claude/settings.json" "$OUT"
  assert_file_contains .claude/settings.json "jig-session-hook"
  assert_file_contains .claude/settings.json "SessionStart"
}

test_adapter_claude_declines_when_settings_already_exist() {
  # The whole point of ADR-0024: an existing project-owned config is never
  # touched, because editing arbitrary JSON is what we cannot do safely.
  fixture_repo
  mkdir -p .claude
  printf '{ "mine": true }\n' > .claude/settings.json
  local before
  before=$(cat .claude/settings.json)

  adapters_source claude
  run adapter_claude_install_session_hook "$PWD"
  assert_eq 2 "$RC"
  assert_eq "$before" "$(cat .claude/settings.json)"
}

test_adapter_claude_declines_for_an_empty_settings_file() {
  # `-e`, not `-f`: an empty file, or a directory at that path, still counts
  # as "someone else owns this".
  fixture_repo
  mkdir -p .claude
  : > .claude/settings.json

  adapters_source claude
  run adapter_claude_install_session_hook "$PWD"
  assert_eq 2 "$RC"
  assert_eq "" "$(cat .claude/settings.json)"
}

test_adapter_codex_has_no_hook_to_install() {
  fixture_repo
  adapters_source codex
  run adapter_codex_install_session_hook "$PWD"
  assert_eq 2 "$RC"
  assert_no_file .codex/settings.json
}

test_adapter_claude_installed_hook_silences_the_hint() {
  fixture_repo
  adapters_source claude
  adapter_claude_install_session_hook "$PWD" >/dev/null
  run adapter_claude_session_hook_hint "$PWD"
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

test_adapter_claude_declines_for_a_dangling_symlink() {
  # `-e` is false for a dangling symlink and `>` writes straight through it,
  # so this path once reported success while the bytes landed outside the
  # project entirely.
  fixture_repo
  mkdir -p .claude outside
  ln -s "$PWD/outside/elsewhere.json" .claude/settings.json

  adapters_source claude
  run adapter_claude_install_session_hook "$PWD"
  assert_eq 2 "$RC"
  assert_no_file outside/elsewhere.json
}

test_adapter_claude_declines_for_a_live_symlink() {
  fixture_repo
  mkdir -p .claude outside
  printf '{ "mine": true }\n' > outside/real.json
  ln -s "$PWD/outside/real.json" .claude/settings.json

  adapters_source claude
  run adapter_claude_install_session_hook "$PWD"
  assert_eq 2 "$RC"
  assert_file_contains outside/real.json "mine"
  assert_not_contains "$(cat outside/real.json)" "jig-session-hook"
}

test_adapter_claude_declines_when_dot_claude_is_a_file() {
  # Must decline, not abort: under the dispatcher's `set -e` a failing
  # `mkdir -p` would take the whole init run down with a raw error.
  fixture_repo
  printf 'not a directory\n' > .claude

  adapters_source claude
  run adapter_claude_install_session_hook "$PWD"
  assert_eq 2 "$RC"
  assert_file_contains .claude "not a directory"
}

test_adapter_claude_leaves_no_temp_file_behind() {
  fixture_repo
  adapters_source claude
  adapter_claude_install_session_hook "$PWD" >/dev/null
  local leftovers
  leftovers=$(find .claude -name '.settings.json.tmp.*' | wc -l | tr -d ' ')
  assert_eq 0 "$leftovers"
}
