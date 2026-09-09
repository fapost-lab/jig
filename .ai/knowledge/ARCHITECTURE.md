# Architecture

Layers, top to bottom (dependencies point downward only):

1. **Runtime** (Claude Code, Codex) — reads `AGENTS.md`, invokes skills.
2. **Skills** — `skills/jig-*`; semantic procedures executed by the agent.
   Installed per runtime by an adapter; vendor-neutral content.
3. **Scripts** — `scripts/` → installed as `.ai/scripts/jig <command>`;
   deterministic, no LLM. Housekeeping additionally runs from a scheduler/hook.
4. **Project state** — `.ai/knowledge` (durable, tracked), `.ai/workspace` and
   `.ai/runtime` (transient, ignored).

Cross-cutting:

- **Adapters** (`adapters/<runtime>/`) touch only layers 1↔2: copy, transform, hooks.
- **Profiles** (`profiles/<stack>/`) plug into scripts (`verify`) and knowledge (rules).

Invariant: no layer calls upward. Skills call scripts; scripts never call skills or the
runtime. See `docs/SPEC.md` §4.

## Scripts layout

`scripts/jig` is the single dispatcher: it resolves its own real path (symlink-safe),
sources `lib/version.sh`, `lib/common.sh`, `lib/config.sh`, then sources
`lib/<command>.sh` and calls `cmd_<command>`. One library file per command, one test
file per command (`tests/<command>.t.sh`). Shared parsers live in their own libraries
(`lib/frontmatter.sh`, `lib/manifest.sh`) and are sourced by the commands that need them.

Why a dispatcher and not one executable per command: every command needs the same
repository detection, config reader and error helpers; sourcing them once in the
dispatcher removes that boilerplate from each command and gives one place for `--help`
and version.

## Adapter contract

`adapters/<name>/adapter.sh` is sourced by `init` and `upgrade` and defines:

- `adapter_<name>_skills_dir` — project-relative directory for skills.
- `adapter_<name>_install_skill <src-skill-dir> <project-root>` — copies and transforms
  a skill, printing every written path so the caller can record it in the manifest.
- `adapter_<name>_install_instructions <project-root> <templates-dir>` — runtime
  instruction files (`CLAUDE.md` for Claude; nothing for Codex, which reads `AGENTS.md`).

Adapters contain no SDLC logic; the only transform today is Codex's invocation syntax
(`/jig-x` → `$jig-x`).

## Install modes

Framework-owned in a project: `.ai/scripts/`, `.ai/profiles/`, `.ai/templates/knowledge/`
and the installed skills. Project-owned: `.ai/knowledge/`, `.ai/config.yaml`, `AGENTS.md`.
The split matters to `upgrade`, which carries framework-owned files forward and never
touches the rest (ADR-0011).

`copy` (default): framework files are copied into the project and hashed in
`.ai/manifest`. `link` (developing the framework itself): `.ai/scripts`, profiles,
templates and skills are relative symlinks into the source checkout, the manifest has no hash lines
and `jig.source` is `.`. In link mode `upgrade` creates any symlink missing for the current config and rewrites the manifest header; nothing is copied.
