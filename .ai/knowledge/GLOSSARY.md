# Glossary

Canonical terms for the Agent SDLC Framework. Use the canonical term in source,
scripts, skills, documentation and commit messages.

## Framework

Canonical term for the whole product (`agent-sdlc`).
Informal synonyms: tool, harness, SDLC layer.

## Runtime

The coding agent product that executes skills: Claude Code, Codex.
Informal synonyms: agent, AI, vendor. Do not use "agent" for the runtime — see Agent.

## Agent

The LLM-driven executor inside a Runtime session that follows skills.
Performs every semantic operation (analysis, classification, review, consolidation).

## Skill

A vendor-neutral markdown procedure (`SKILL.md`) executed by the Agent.
Installed per Runtime by an Adapter. Named `sdlc-<stage>`.
Informal synonyms: command, slash command, workflow.

## Script

A deterministic shell program under `.ai/scripts/`, invoked as `sdlc <command>`.
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

## Task Class

Risk/complexity class `T0`–`T4` assigned by the Agent that selects the workflow.

## Human Gate

A stage where the workflow stops until a human approves (T3, T4).
