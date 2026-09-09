# Codex adapter (SPEC §31, ADR-0003, ADR-0007).
#
# Sourced by scripts/lib/init.sh and scripts/lib/upgrade.sh; must not be
# executed directly. Defines where Codex-facing files live in a project and
# how to install them. Never calls an LLM (ADR-0001); pure file operations.
# shellcheck shell=bash

# adapter_codex_skills_dir
# Prints the skills directory for this adapter, relative to the project root.
adapter_codex_skills_dir() {
  printf '%s\n' ".codex/skills"
}

# adapter_codex_install_skill <src-skill-dir> <project-root>
# Copies <src-skill-dir>/** into <project-root>/.codex/skills/<skill-name>/.
# SKILL.md content is rewritten: a skill invocation `/jig-<name>` becomes
# `$jig-<name>`, matched only when preceded by start-of-line, whitespace or a
# backtick, so file paths such as `skills/jig-init` are left untouched. Every
# other file is copied verbatim. Prints each destination path it wrote,
# relative to <project-root>, one per line.
adapter_codex_install_skill() {
  local src="$1" project="$2" name dest_rel dest_abs f
  name=$(basename "$src")
  dest_rel="$(adapter_codex_skills_dir)/$name"
  dest_abs="$project/$dest_rel"
  mkdir -p "$dest_abs"
  ( cd "$src" && find . -type f ) | while IFS= read -r f; do
    f="${f#./}"
    mkdir -p "$(dirname "$dest_abs/$f")"
    case "$f" in
      SKILL.md)
        # shellcheck disable=SC2016
        sed -e 's/^\/jig-/\$jig-/g' \
            -e 's/\([[:space:]`]\)\/jig-/\1\$jig-/g' \
            "$src/$f" > "$dest_abs/$f"
        ;;
      *)
        cp -p "$src/$f" "$dest_abs/$f"
        ;;
    esac
    printf '%s/%s\n' "$dest_rel" "$f"
  done
}

# adapter_codex_install_instructions <project-root> <templates-dir>
# Codex reads AGENTS.md natively; nothing to install. Prints nothing.
adapter_codex_install_instructions() {
  :
}

# TODO(spec §33): session hook. Codex has no equivalent of a Claude Code
# SessionStart hook at the time of writing; the housekeeping trigger for
# Codex is an open question left to SPEC §33.
