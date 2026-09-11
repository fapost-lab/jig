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
through a link and owns none; Housekeeping removes it through git when it purges that
Workspace (ADR-0029). Informal synonyms: agent tree, sandbox.

## State

The flat `key: value` file in a Workspace describing local task lifecycle.

## Consolidation

The SDLC stage that decides what from a task becomes Durable Knowledge.
`NO_DURABLE_KNOWLEDGE` is a valid outcome.

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
honoured (ADR-0013). Informal synonyms: filter, narrowing.

## Task Class

Risk/complexity class `T0`–`T4` assigned by the Agent that selects the workflow.

## Human Gate

A stage where the workflow stops until a human approves (T3, T4).
