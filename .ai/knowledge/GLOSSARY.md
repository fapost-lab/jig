# Glossary

Canonical terms for Jig, the Agent SDLC Framework. Use the canonical term in source,
scripts, skills, documentation and commit messages.

## Framework

Canonical term for the whole product. A jig guides the tool without cutting; Jig guides the agent without executing (ADR-0007).
Informal synonyms: tool, harness, SDLC layer.

## Runtime

The coding agent product that executes skills: Claude Code, Codex.
Informal synonyms: agent, AI, vendor. Do not use "agent" for the runtime — see Agent.

## Agent

The LLM-driven executor inside a Runtime session that follows skills.
Performs every semantic operation (analysis, classification, review, consolidation).

## Skill

A vendor-neutral markdown procedure (`SKILL.md`) executed by the Agent.
Installed per Runtime by an Adapter. Named `jig-<stage>`.
Informal synonyms: command, slash command, workflow.

## Script

A deterministic shell program under `.ai/scripts/`, invoked as `jig <command>`.
Never calls an LLM. Informal synonyms: CLI (deprecated in spec 0.4), tool.

## Adapter

Runtime-specific installer: knows where skills go, how to transform them, and how to
register hooks. Contains no SDLC logic.

## Profile

Technology-specific bundle (`profiles/<name>/`): detection rules, `verify.sh`, rules,
conventions. A project activates one or more.

## Knowledge (Durable Knowledge)

Information under `.ai/knowledge/` that must outlive any single task: glossary,
architecture, rules, invariants, conventions, feature knowledge, ADRs.
Informal synonyms: docs, context, memory.

## Workspace (Task Workspace)

Transient, gitignored directory `.ai/workspace/tasks/<task-id>/` holding task
artifacts and `state`. Informal synonyms: task dir, scratch.

## Task Worktree

A git worktree created by `jig task start --worktree`, beside the repository under
`git.worktree_root`, with the task's branch checked out. It borrows the task's Workspace
through a Directory Link and owns none; Housekeeping removes it through git when it purges that
Workspace (ADR-0029). Informal synonyms: agent tree, sandbox.

## Directory Link

A link from one directory to another that bash sees as a symlink (`-L`, `find -type l`): a
symbolic link where the machine can make one, an NTFS junction where it cannot. Made only by
`jig_link_dir`; `jig doctor` reports which kind this machine makes, or `none` (ADR-0037).
A task worktree's workspace link is one. Link mode's links are not: they must be relative
symbolic links. Informal synonyms: link, junction, symlink.

## State

The flat `key: value` file in a Workspace describing local task lifecycle.

## Consolidation

The SDLC stage that decides what from a task becomes Durable Knowledge. It ends every
route. `NO_DURABLE_KNOWLEDGE` is a valid outcome. It is recorded twice (ADR-0030): the
knowledge decision (`knowledge_consolidated: true`) before the commit, and the close
(`status: consolidated`) after the task's change has landed.

## Housekeeping

Scheduled, LLM-free reconciliation of Workspaces against remote merge state,
ending in a two-stage purge. Informal synonyms: cleanup, GC.

## Remote State

The derived answer to "did this task's work land": `merged | open | closed | unknown`.
Computed by Housekeeping on every run and **never stored** in a task's State (ADR-0005).
Only a Forge can produce `open` or `closed`; git ancestry produces `merged` or `unknown`
(ADR-0025). Informal synonyms: merge state, PR state.

## Forge

The hosting service that owns pull/merge requests — GitHub via `gh`, GitLab via `glab`.
Optional (ADR-0002): when absent, unauthenticated or configured `forge: none`,
Housekeeping falls through to git ancestry. Informal synonyms: host, remote, provider.

## Trash

`.ai/runtime/trash/<date>/<task-id>/`, where a purged Workspace is moved rather than
deleted. Recovery is a plain `mv` back for `trash_ttl` days (ADR-0006). Never committed.

## Purge

Ending a Workspace's life, in two stages: move to Trash, then permanent deletion once
`trash_ttl` expires. "Purged" is not a State — the directory is simply gone (ADR-0005).

## STALE_CANDIDATE

A report-only flag on a Workspace older than `stale_after`. It never triggers deletion:
semantic lifecycle has priority over TTL (domains/housekeeping). Informal synonyms: stale, old.

## Session Hook

`.ai/scripts/jig-session-hook`: the cheap Housekeeping trigger a Runtime runs at session
start. The framework owns the script and only *offers* the line that enables it; it never
edits the Runtime's own config file (ADR-0024). Codex has no equivalent.

## Domain Pack

The three documents a domain may keep under `.ai/knowledge/domains/<domain>/`:
`OVERVIEW.md` (type `domain`), `GLOSSARY.md` (`glossary`) and `RULES.md` (`rule`).
The directory is navigation only; applicability stays in frontmatter (ADR-0004, ADR-0014).

## Proposed Knowledge

A document written but not yet agreed to: `status: proposed`. It sits at its real path
and is validated, but `jig context` will not resolve it, so nothing inferred reaches an
Agent before a human runs `jig knowledge accept` (ADR-0016).
Informal synonyms: draft, candidate.

## Specification (Spec)

The committed plan for work larger than one task, under `.ai/specs/<spec-id>/`: `spec.md`
(the idea, its stress test, decisions, open questions) and `roadmap.md` (destination,
phases, items, fog, waves). Created by `jig spec new` and developed with the `jig-idea`
skill. A plan, not Knowledge: `jig context` never resolves it, and it has no status —
progress is read from the roadmap's checkboxes (ADR-0035). A task filed from it links back
with a `Spec:` line in its `task.md`. Not the retired product specification of ADR-0028.
Informal synonyms: plan, roadmap, design doc.

## Task Base

The branch a task was cut from and has to land on, recorded as `base_branch` in its State by
`jig task start`: `git.base_branch`, or the Epic Branch of the spec the task links to. Every
judgement of whether a task landed is made against it; work merged anywhere else is flagged
`wrong-base` (ADR-0039). Informal synonyms: base, target branch.

## Epic Branch

`epic/<spec-id>`: the branch a Specification released once, at the end, is built on. Its phases'
tasks are cut from it and merged into it; it reaches the default branch in one pull request with
the version raised, after `jig spec epic <id> --finish` (ADR-0040). Declared by the `Epic:` line of
the roadmap. Informal synonyms: epic, feature branch.

## Linked Source (Stub)

A knowledge document whose frontmatter names an existing tracked file with `source:`, so a project's own
rule document is adopted without being copied. It lives in `.ai/knowledge/sources/` and holds only
metadata; the source owns the rules. Once accepted, `jig context` hands an agent the source in the
stub's place, and `source_hash` records the text a human approved (ADR-0036). Informal synonyms: link, pointer, adopted document.

## Load Policy

A knowledge document's `load` field — `always`, `domain` or `matched` — stating how
strongly it applies. Decides whether `jig context resolve` requires its body or lists it
in the Catalog.

## Catalog (Context Catalog)

The compact `id`, path and `summary` listing of active documents in an entered domain
that are not required. Metadata only: the Agent pulls one in explicitly with `--ids`.
Informal synonyms: index, listing.

## Context Ledger

The per-task record of documents the Agent stated it has read:
`.ai/workspace/tasks/<id>/context`, one `<git-hash><TAB><path>` line each. Transient and
never committed. It records a claim of reading, not comprehension (ADR-0015).
Informal synonyms: acknowledgements, read tracking.

## Verify Scope

A narrowing passed to `jig verify`, expressed as a list of changed files rather than a
filter string, because a file list means the same thing in every stack. A Profile
receives it only if it declares support, and the report always says whether it was
honoured (ADR-0013). With `verify.full_run: ci` a flag-less `jig verify` narrows by default,
to what changed since the merge base (ADR-0041). Informal synonyms: filter, narrowing.

## Verify Map

`.ai/verify/<profile>.map`: a project's own rules for which changed path affects which of a
Profile's checks — `<glob> <decision>`, first match wins. Project-owned; parsed by
`jig verify` and handed to a profile that declares `map`, never read by the profile itself
(ADR-0041). Informal synonyms: scope map, test map.

## Task Class

Risk/complexity class `T0`–`T4` assigned by the Agent that selects the workflow.

## Human Gate

A stage where the workflow stops until a human approves (T3, T4). The decision is written
in `task.md`, and an approval is also recorded with `jig task gate <id> approved`, which
pins the approved design.

## Status Page

`.ai/runtime/status.html`: one self-contained page written by `jig status --html` or
`--open` that answers what needs the reader, what is running and how far the specifications
are. Once it exists, the commands that change a task, a spec or a housekeeping result redraw
it, and it reloads itself; one per clone, in the main checkout
(adr-20260922-the-status-page-stays-current-without-a-server). Informal synonyms: dashboard,
status view.
