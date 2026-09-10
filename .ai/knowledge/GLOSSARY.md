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

## State

The flat `key: value` file in a Workspace describing local task lifecycle.

## Consolidation

The SDLC stage that decides what from a task becomes Durable Knowledge.
`NO_DURABLE_KNOWLEDGE` is a valid outcome.

## Housekeeping

Scheduled, LLM-free reconciliation of Workspaces against remote merge state,
ending in a two-stage purge. Informal synonyms: cleanup, GC.

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
