# Claude Code adapter (ARCHITECTURE.md, Adapter contract; ADR-0003, ADR-0007).
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
  local src="$1" project="$2" name dest_rel dest_abs f dir last_dir=""
  # Parameter expansion instead of basename/dirname: this runs once per file
  # of every skill, for every adapter, and a spawn costs ~3 ms.
  name="${src%/}"
  name="${name##*/}"
  dest_rel="$(adapter_claude_skills_dir)/$name"
  dest_abs="$project/$dest_rel"
  mkdir -p "$dest_abs"
  ( cd "$src" && find . -type f ) | while IFS= read -r f; do
    f="${f#./}"
    # `find` walks depth-first, so files of one directory arrive together and
    # remembering the last one collapses almost every mkdir. The top-level
    # directory already exists, so a file with no slash needs none at all.
    # Assumes nothing deletes a destination directory mid-copy; nothing does.
    case "$f" in
      */*)
        dir="$dest_abs/${f%/*}"
        if [ "$dir" != "$last_dir" ]; then
          mkdir -p "$dir"
          last_dir="$dir"
        fi
        ;;
    esac
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

# adapter_claude_session_hook_hint <project-root>
# Advisory only: prints how to enable the housekeeping trigger, or nothing
# when it is already enabled. Writes no file. Exit 0 means the answer is
# actionable; exit 2 would mean the runtime has no session hook at all (see
# the codex adapter).
#
# `.claude/settings.json` is project-owned arbitrary JSON, and the framework
# has no JSON parser (ADR-0002 allows only `git` as a dependency). Editing it
# with shell text processing would risk a file the project owns and jig cannot
# rebuild, so jig ships the hook as a script it *does* own and leaves the one
# line to a human who can see what they are agreeing to (ADR-0024).
#
# Detection is a read-only substring test, which is safe on arbitrary JSON in
# a way that editing is not. A user who removes the entry stays removed.
# adapter_claude_install_session_hook <project-root>
# Install the housekeeping trigger, but only where doing so needs no
# understanding of an existing file. Prints the created path and exits 0;
# prints nothing and exits 2 when it declined, with the reason on stderr.
#
# The line ADR-0024 draws is between *editing* a project-owned config and
# *creating* an absent one. Editing arbitrary JSON without a JSON parser is
# what that decision refused (ADR-0002 admits only `git`); writing a file that
# does not exist parses nothing, so the reason for the refusal does not reach
# this case. An existing file is still never touched — not merged into, not
# reformatted, not read for anything but the substring test in the hint.
#
# Creating a project-owned file when it is absent and never overwriting it is
# the rule `_init_place_if_absent` already applies to CLAUDE.md and AGENTS.md
# (ADR-0003, RULES.md); this is the same rule, with an explicit request added.
adapter_claude_install_session_hook() {
  local project="$1"
  local settings="$project/.claude/settings.json"
  local tmp

  # `-L` before `-e`, because `-e` is FALSE for a dangling symlink while `>`
  # happily writes straight through it — that combination would report
  # "created .claude/settings.json" while the bytes landed wherever the link
  # pointed, possibly outside the project. A symlink at this path, live or
  # dangling, means someone else owns it.
  if [ -L "$settings" ] || [ -e "$settings" ]; then
    printf 'session hook: .claude/settings.json exists; not modified\n' >&2
    return 2
  fi

  # A non-directory at .claude/ would make `mkdir -p` fail and, under the
  # dispatcher's `set -e`, take the whole `init` run down with a raw mkdir
  # error. Declining is this function's documented way to fail.
  if [ -e "$project/.claude" ] && [ ! -d "$project/.claude" ]; then
    printf 'session hook: .claude exists and is not a directory; not modified\n' >&2
    return 2
  fi

  mkdir -p "$project/.claude" || {
    printf 'session hook: cannot create .claude/; not modified\n' >&2
    return 2
  }

  # Write in full, then link into place: `ln` fails when anything already
  # occupies the destination, so the create is atomic and a racing writer
  # cannot be clobbered between the check above and the write (the check is
  # for a clear message; this is the actual guarantee). A crash mid-write
  # leaves only the temp file, never a half-written config the framework is
  # then forbidden to repair (convention-shell: write tmp, then move).
  tmp="$project/.claude/.settings.json.tmp.$$"
  cat > "$tmp" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": ".ai/scripts/jig-session-hook" }
        ]
      }
    ]
  }
}
JSON
  if ln "$tmp" "$settings" 2>/dev/null; then
    rm -f "$tmp"
    printf '.claude/settings.json\n'
    return 0
  fi
  # Either something appeared at the destination, or the filesystem has no
  # hard links. Both resolve to "not installed", which is the safe direction.
  rm -f "$tmp"
  printf 'session hook: could not create .claude/settings.json; not modified\n' >&2
  return 2
}

adapter_claude_session_hook_hint() {
  local project="$1"
  local settings="$project/.claude/settings.json"
  if [ -f "$settings" ] && grep -q 'jig-session-hook' "$settings"; then
    return 0
  fi
  printf 'housekeeping: not triggered automatically. To run it at session start,\n'
  printf '  add to .claude/settings.json (see .ai/templates/scheduler/README.md):\n'
  printf '  "hooks": { "SessionStart": [ { "hooks": [\n'
  printf '    { "type": "command", "command": ".ai/scripts/jig-session-hook" } ] } ] }\n'
}
