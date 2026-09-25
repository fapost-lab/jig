# Codex adapter (ARCHITECTURE.md, Adapter contract; ADR-0003, ADR-0007).
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
  local src="$1" project="$2" name dest_rel dest_abs f dir last_dir=""
  # Parameter expansion instead of basename/dirname: this runs once per file
  # of every skill, for every adapter, and a spawn costs ~3 ms.
  name="${src%/}"
  name="${name##*/}"
  dest_rel="$(adapter_codex_skills_dir)/$name"
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

# adapter_codex_instructions_hint <project-root>
# Advisory only; writes no file. Prints what is missing and how to fix it, or
# nothing when the instructions Codex reads already carry Jig's workflow.
#
# Codex reads AGENTS.md. A project that had its own AGENTS.md before `jig init`
# keeps it untouched (ADR-0003), so the agent may never hear of the routes: the
# skills are installed, but nothing tells the agent to start with `jig-task`.
# The mention of `jig-task` is the marker: it is what the Workflow section of
# templates/AGENTS.md exists to say. Editing the file is the agent's job, with
# the human's consent (the jig-init skill), never a script's.
# adapter_codex_instructions_file
# Prints the project-relative instruction file this runtime reads, so reports
# can name it without parsing the hint's prose.
adapter_codex_instructions_file() {
  printf '%s\n' "AGENTS.md"
}

adapter_codex_instructions_hint() {
  local project="$1"
  if [ -f "$project/AGENTS.md" ] && grep -q 'jig-task' "$project/AGENTS.md"; then
    return 0
  fi
  if [ -f "$project/AGENTS.md" ]; then
    printf 'instructions: AGENTS.md does not mention Jig, so Codex will not follow its workflow.\n'
  else
    printf 'instructions: AGENTS.md is missing, so Codex will not follow the Jig workflow.\n'
  fi
  # shellcheck disable=SC2016  # `$jig-init` is Codex's invocation, not a variable
  printf '  Run $jig-init to merge the Jig section, or copy it — markers included — from\n'
  printf '  the marked part of .ai/templates/AGENTS.md into AGENTS.md.\n'
}

# adapter_codex_session_hook_hint <project-root>
# Advisory only; writes no file.
#
# Codex has no equivalent of Claude Code's SessionStart hook, so there is no
# in-session trigger to offer. Saying so plainly is the honest answer: the two
# runtimes get the same lifecycle semantics, but not the same cheap trigger,
# and pretending otherwise would leave Codex users assuming housekeeping runs
# when it never does (domains/housekeeping).
# Exit 2 means "not applicable to this runtime", the same skip convention a
# profile's verify.sh uses. `init` prints the text once; `status` stays quiet
# about it, because a line saying "not installed" that no one can ever act on
# is noise the reader cannot clear.
# adapter_codex_install_session_hook <project-root>
# Nothing to install: Codex has no session-start hook to point at. Declines
# the same way an existing config file does, so `init --session-hook` needs no
# per-runtime special case.
adapter_codex_install_session_hook() {
  printf 'session hook: Codex has no session-start hook to install\n' >&2
  return 2
}

adapter_codex_session_hook_hint() {
  printf 'housekeeping: Codex has no session-start hook; use a scheduler\n'
  printf '  (see .ai/templates/scheduler/README.md).\n'
  return 2
}

# adapter_codex_session_id
# Exits 2: not answered for this runtime.
#
# Not "Codex has no session id" — it has them, and names them. Its rollout
# files are `~/.codex/sessions/<year>/…/rollout-<timestamp>-<uuid>.jsonl`, so
# a session is identified internally. What could not be established is whether
# that identifier reaches the environment of a command Codex runs, and its
# `config.toml` carries a `[shell_environment_policy.set]` section — the
# environment handed to commands is curated, so the answer cannot be inferred
# from the fact that the id exists.
#
# Until someone verifies it with Codex in front of them, this exits 2, and a
# Codex session working in a checkout without a task of its own leaves no
# record. The consequence is named rather than papered over: `task start` then
# cannot tell that checkout from a free one, and such a session learns that its
# HEAD moved from the notice, after the fact
# (adr-20260924-a-checkout-records-what-is-happening-in-it).
#
# Whoever writes that line owes `tests/run.sh` the same variable in the list it
# unsets beside CLAUDE_CODE_SESSION_ID. A test suite that inherits a runtime's
# variable measures the machine it runs on, not the repository — it made three
# tests here pass or fail depending on who started them
# (adr-20260924-a-checkout-records-what-is-happening-in-it, and the
# `run_no_tools` row of conventions/shell.md, which is the same failure).
#
# Deriving an id from the newest rollout file was considered and rejected: the
# newest rollout is not necessarily the running session, several can run at
# once, and it reads private state the runtime is free to change.
adapter_codex_session_id() {
  return 2
}
