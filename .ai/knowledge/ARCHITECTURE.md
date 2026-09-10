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
A helper that two commands must never disagree about lives in `lib/common.sh` instead —
`jig_git_touched_files` ("what did this task touch"), `jig_knowledge_docs` and
`jig_knowledge_is_global` ("which files are knowledge documents"). One command library
never sources another: `context` and `knowledge` share code only through `common.sh`.

Why a dispatcher and not one executable per command: every command needs the same
repository detection, config reader and error helpers; sourcing them once in the
dispatcher removes that boilerplate from each command and gives one place for `--help`
and version.

## Adapter contract

`adapters/<name>/adapter.sh` is sourced by `init`, `upgrade` and `status`, and defines:

- `adapter_<name>_skills_dir` — project-relative directory for skills.
- `adapter_<name>_install_skill <src-skill-dir> <project-root>` — copies and transforms
  a skill, printing every written path so the caller can record it in the manifest.
- `adapter_<name>_install_instructions <project-root> <templates-dir>` — runtime
  instruction files (`CLAUDE.md` for Claude; nothing for Codex, which reads `AGENTS.md`).
- `adapter_<name>_session_hook_hint <project-root>` — advisory only, writes nothing:
  prints how to enable the housekeeping trigger, prints nothing when it is already
  enabled, and **exits 2 when the runtime has no session hook at all** (ADR-0024).
- `adapter_<name>_install_session_hook <project-root>` — called only by
  `init --session-hook`. Creates the runtime's config file with the hook entry **when
  that file is absent**, printing the created path; exits 2, touching nothing, when a
  file already exists there or the runtime has no hook. It never edits an existing file:
  creating one parses nothing, editing one would need a JSON parser the framework does
  not have (ADR-0024, ADR-0002).

Adapters contain no SDLC logic; the only transform today is Codex's invocation syntax
(`/jig-x` → `$jig-x`).

Two notes on the fourth function, because it is the odd one out. It is the reason
`status` sources adapters at all — vendor knowledge (which config file, what shape,
how to detect the entry) belongs here, and `status` only prints a generic line from the
answer. And its exit 2 means *"not applicable to this runtime"* — a capability marker.
That is **not** the same as a profile's `verify.sh` exit 2, which means "this check did
not run"; the two share a number, not a meaning.

A command calls a capability function only when the adapter defines it (`command -v`),
so an adapter written before a capability existed keeps working — the same "granted,
never assumed" rule the profile contract below states.

## Profile contract

`profiles/<stack>/profile.yaml` declares what the profile is and what it can do:

- `name`, `description`;
- `detect` — globs whose presence means this stack is here, or `always`. This is the one
  place the mapping "manifest → stack" is written down; no command re-derives it.
- `requires` — another profile this one implies;
- `scope` — capabilities the profile understands, today only `[changed]` (ADR-0013).

`profiles/<stack>/verify.sh` is run from the repository root and exits 0 pass, 1 fail,
**2 skip**. It prints one line per check, because a profile runs several (shellcheck and
tests; phpunit and phpstan), and a profile-level result hides which of them ran.

Capabilities are granted, never assumed. `jig verify` passes `JIG_VERIFY_SCOPE` and
`JIG_VERIFY_FILES` only to a profile whose `scope` declares support, and explicitly
*unsets* both for every other profile rather than leaving whatever the caller's
environment held — profiles are copied into projects and `upgrade` preserves
user-modified ones, so a script written before a capability existed will meet a framework
that has it.

## Install modes

Framework-owned in a project: `.ai/scripts/`, `.ai/profiles/`, `.ai/templates/knowledge/`,
`.ai/templates/scheduler/` and the installed skills. Project-owned: `.ai/knowledge/`, `.ai/config.yaml`, `AGENTS.md`.
The split matters to `upgrade`, which carries framework-owned files forward and never
touches the rest (ADR-0011).

`copy` (default): framework files are copied into the project and hashed in
`.ai/manifest`. `link` (developing the framework itself): `.ai/scripts`, profiles,
templates and skills are relative symlinks into the source checkout, the manifest has no hash lines
and `jig.source` is `.`. In link mode `upgrade` creates any symlink missing for the current config and rewrites the manifest header; nothing is copied.
