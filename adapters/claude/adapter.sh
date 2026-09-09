# Claude Code adapter (SPEC §31, ADR-0003, ADR-0007).
#
# Sourced by scripts/lib/init.sh and scripts/lib/upgrade.sh; must not be
# executed directly. Defines where Claude-facing files live in a project and
# how to install them. Never calls an LLM (ADR-0001); pure file operations.
# shellcheck shell=bash

# adapter_claude_skills_dir
# Prints the skills directory for this adapter, relative to the project root.
adapter_claude_skills_dir() {
  printf '%s\n' ".claude/skills"
}

# adapter_claude_install_skill <src-skill-dir> <project-root>
# Copies <src-skill-dir>/** verbatim (Claude reads skills as-is) into
# <project-root>/.claude/skills/<skill-name>/. Prints each destination path
# it wrote, relative to <project-root>, one per line, so the caller can
# record them in the manifest.
adapter_claude_install_skill() {
  local src="$1" project="$2" name dest_rel dest_abs f
  name=$(basename "$src")
  dest_rel="$(adapter_claude_skills_dir)/$name"
  dest_abs="$project/$dest_rel"
  mkdir -p "$dest_abs"
  ( cd "$src" && find . -type f ) | while IFS= read -r f; do
    f="${f#./}"
    mkdir -p "$(dirname "$dest_abs/$f")"
    cp -p "$src/$f" "$dest_abs/$f"
    printf '%s/%s\n' "$dest_rel" "$f"
  done
}

# adapter_claude_install_instructions <project-root> <templates-dir>
# Creates CLAUDE.md from templates/CLAUDE.md only if it does not exist yet
# (never overwrites, ADR-0003 / RULES.md). Prints the written relative path;
# prints nothing when CLAUDE.md already exists.
adapter_claude_install_instructions() {
  local project="$1" templates="$2"
  if [ ! -f "$project/CLAUDE.md" ]; then
    cp "$templates/CLAUDE.md" "$project/CLAUDE.md"
    printf 'CLAUDE.md\n'
  fi
}

# TODO(spec §33): session hook. Installing the housekeeping trigger means
# merging one hooks.SessionStart entry (tagged "_jig": true) into the
# project-owned .claude/settings.json instead of copying a file, which does
# not fit the manifest model of SPEC §6.2. Left for the decision in §33.
