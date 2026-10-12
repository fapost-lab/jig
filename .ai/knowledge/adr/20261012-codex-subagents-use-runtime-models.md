---
id: adr-20261012-codex-subagents-use-runtime-models
type: adr
status: accepted
date: 2026-10-12
domains: []
paths:
  - scripts/lib/config.sh
  - scripts/lib/task.sh
  - skills/jig-task/references/delegation.md
  - skills/jig-implement/SKILL.md
  - skills/jig-review/SKILL.md
  - skills/jig-autopilot/SKILL.md
  - skills/jig-architecture-review/SKILL.md
summary: Codex model keys choose whole-stage subagents; a failed explicit Codex delegation stops the stage while route records remain runtime-neutral.
reviewed_at: 2026-10-12
---
# Codex subagent model choice uses local runtime keys and stops on failed delegation

## Context

ADR 20261005 named the roles and made Claude Code model keys personal and opaque. Codex
supports subagents with model choice, so a Codex session needs the same stage-level choice.
The configured executor is a deliberate personal choice. Quietly doing its work in the
coordinator session after it fails would misrepresent an independent review.

## Decision

- Add local-only `codex.implement_model` and `codex.review_model`, alongside the existing
  Claude keys. A session follows only the route lines for its own runtime. The model remains
  an opaque value interpreted by that runtime, never by Jig's shell.
- Delegate the whole implementation or review stage to a Codex subagent with the exact
  configured model. The reviewer gets a fresh context without the implementation conversation.
  Task files, findings, receipts, and verification remain the route evidence.
- If a selected Codex subagent cannot start or use the selected model, stop that stage and
  report the cause. Do not silently substitute another model or the coordinator session.
  With the keys unset, the existing session behavior remains in force.
- This extends ADR 20261005's runtime-named model design. Its Claude failure fallback remains
  a separate historical behavior; Codex's stop rule is deliberate.

## Alternatives

- One portable model key: model names and subagent launch are runtime-specific.
- Shell-launching a Codex process for this phase: process permissions and recovery require a
  separate cross-runtime contract.
- Silent fallback to the coordinator: would make the selected executor misleading, especially
  for an independent review.

## Consequences

Codex users can select implementation and review models without a vendor catalog or project
default. Each session must select its own runtime's route lines. A refused model now requires
the person to fix the setting or explicitly choose another executor before the stage proceeds.
