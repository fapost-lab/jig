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
reviewed_at: 2026-09-30
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

> **Amendment (2026-09-13).** The two fields now record two different moments:
> `knowledge_consolidated: true` is written at the end of every route, before the commit,
> and `status: consolidated` closes the task after its change has landed. `jig task set`
> refuses the status while the flag is not `true`. See ADR-0030.

> **Amendment (2026-09-30).** "After its change has landed" was not, in fact, checked:
> `knowledge_consolidated` and `status: consolidated` are ordered, but neither asked whether
> a pull request the task opened (`pr_url` in state) had actually merged, so an autopilot
> run — or a human following the same route by hand — could close a task whose pull
> request was still open. `jig task set status consolidated` now asks the forge, live,
> exactly as this ADR always intended remote state to be asked rather than stored:
> `jig_pr_state <url>` (`scripts/lib/common.sh`) reads `merged | open | closed | unknown`
> from `gh`/`glab`, and the write is refused unless `pr_url` is empty (no pull request was
> ever opened) or the answer is `merged`. See task `autopilot-end-closes-unmerged-task`.
>
> Deliberately narrower than housekeeping's own remote-state tier: this gate asks only the
> forge, with no fallback to git ancestry/patch-id when the forge cannot answer, because it
> must decide synchronously, in the call the human or the route is waiting on, not on a
> background sweep's schedule. So a forge that is unreachable reads as `unknown` and refuses
> the close here even on a run where housekeeping's ancestry check would already call the
> same pull request merged — the two can disagree about the same fact for as long as the
> forge stays unreachable. That asymmetry is intentional: closing a task early cannot be
> taken back for free, so refusing on an inconclusive answer is the side to be wrong on.
