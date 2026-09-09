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
