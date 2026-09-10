---
id: adr-0021-additive-stage-and-taskless-context
type: adr
status: accepted
date: 2026-09-10
domains:
  - context
  - knowledge
paths:
  - scripts/lib/context.sh
  - scripts/lib/knowledge.sh
  - schemas/frontmatter.md
summary: Why stage relevance is additive and standalone exploration bypasses task selection.
reviewed_at: 2026-09-10
---
# ADR-0021: Stage relevance adds knowledge; exploration can be taskless

## Context

ADR-0014/0015 resolve knowledge and track reading. Stage relevance and explicit standalone
research are missing; neither should select unrelated tasks or hide mandatory constraints.

## Decision

Progressive resolve/pending/guard accept an explicit --stage from the fixed route vocabulary.
Optional stages metadata promotes load: matched catalog documents only inside an entered
matching domain. All existing mandatory selection and requires closure remain additive.
The normal active/accepted allowlist stays intact. Unchanged hashes stay acknowledged;
newly selected or changed documents become pending. Missing mandatory globals, requested
IDs and dependencies fail loudly. Legacy context rejects --stage and points to resolve.
`jig knowledge stages add|remove` writes metadata, and knowledge check validates it.

Both context forms accept --no-task, mutually exclusive with --task. It bypasses implicit
task selection, task domains and workspace artifacts; explicit relevance selectors still
work. No-task guard reports absence of a ledger, not proof of reading. Stage and taskless
selection never write task state. Workspace artifacts remain discoverable without filtering.

## Alternatives

Intersecting stage filters could hide binding constraints. Global stage-topic aliases
could pull unrelated domains. Implicit research/current-task selection confuses intent.

## Consequences

Existing documents need no migration. Additional relevance can increase context size.
Stage changes require consistent selectors across resolve/pending/guard. Missing globals
now fail progressive requests rather than disappearing. This extends ADR-0014/0015 and
was approved in the SDD/OpenSpec design on 2026-09-10.
