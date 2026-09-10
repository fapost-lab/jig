---
id: adr-0005-task-status-local-merge-state-derived
type: adr
status: accepted
date: 2026-09-08
domains: [workspace, lifecycle, housekeeping]
paths:
  - "scripts/lib/task.sh"
  - "scripts/lib/housekeeping.sh"
  - "schemas/state.md"
summary: Why task status is local and remote merge state is derived, never stored.
---
# ADR-0005: Task `status` is local-only; merge state is derived, never stored as truth

## Context

Spec v0.3 defined lifecycle states ACTIVE / READY / CONSOLIDATED / MERGED / PURGED and
a separate `knowledge_consolidated` flag. CONSOLIDATED duplicated the flag; MERGED and
PURGED are facts about the remote or the filesystem, not about the task's local
progress. Storing merge state locally invites drift (squash merges, deleted branches).
The spec also had no path for a PR closed without merge.

## Decision

- `status` ∈ `active | ready | consolidated | abandoned` describes only local progress
  and is written by skills via `jig task set`.
- `knowledge_consolidated` stays as an explicit boolean because consolidation may
  legitimately produce `NO_DURABLE_KNOWLEDGE` yet still be complete.
- Remote state ∈ `merged | open | closed | unknown` is computed by housekeeping on every
  run (forge → git ancestry/patch-id → unknown) and may be cached under `.ai/runtime/`,
  never written into `state`.
- A `closed` remote state flags the workspace as "abandoned?"; the `task abandon`
  command sets `status: abandoned`, after which it is purged after `abandoned_ttl`.
- "Purged" is not a state; the directory is gone.

## Alternatives

- **Single combined enum** — rejected: conflates two independent axes and forces
  local state to be rewritten by a background process.

## Consequences

- The cleanup policy is a two-axis table (`domains/housekeeping`) that is easy to test
  exhaustively.
- Abandoned work no longer lives forever under "not merged → preserve".
