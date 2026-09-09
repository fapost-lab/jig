---
id: adr-0001-skills-execute-scripts-are-deterministic
type: adr
status: accepted
date: 2026-09-08
domains: [core, skills, scripts]
paths:
  - "skills/**"
  - "scripts/**"
---
# ADR-0001: Skills execute the process; scripts are deterministic and never invoke an LLM

## Context

Spec v0.3 listed `agent-sdlc task run` and `agent-sdlc task classify` as CLI commands.
Both imply that a standalone executable performs semantic work (classifying a task by
risk, running an SDLC workflow). That is impossible without an LLM, and embedding LLM
invocation in the framework would turn it into a coding-agent orchestrator — an explicit
non-goal — and tie it to a specific runtime.

The reference project `lee-to/ai-factory` resolves this implicitly: its CLI only installs
files; every workflow step is a skill executed by the agent.

## Decision

- All semantic operations (analysis, classification, planning, review, consolidation)
  are performed by the agent following a skill.
- All mechanical operations (workspace creation, state writes, context assembly,
  running verification, housekeeping) are performed by scripts under `.ai/scripts/`.
- Scripts never call an LLM. Housekeeping is the only component that runs without an
  agent present.
- The term "CLI" is dropped from the spec in favour of "scripts".

## Alternatives

- **Scripts spawn the agent (`claude -p …`)** — rejected: vendor-specific, expensive,
  duplicates what the runtime already does.
- **Everything in skills, no scripts** — rejected: skills would have to describe file
  discovery, state parsing and cleanup in prose, bloating context (ai-factory's
  `aif-implement` is 1091 lines for this reason) and making housekeeping depend on
  an LLM session.

## Consequences

- Skills stay short and delegate mechanics to `jig <command>`.
- Scripts are fully testable without inference.
- Classification is recorded by `jig task set <id> class T2`, never computed by scripts.
