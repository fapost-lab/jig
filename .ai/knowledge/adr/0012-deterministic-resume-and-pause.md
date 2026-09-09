---
id: adr-0012-deterministic-resume-and-pause
type: adr
status: accepted
date: 2026-09-09
domains: [workspace, lifecycle]
paths:
  - "scripts/lib/task.sh"
  - "scripts/lib/context.sh"
  - "scripts/lib/status.sh"
  - "schemas/state.md"
---
# ADR-0012: Resume is ambiguous or exact, never a guess; pause is a field

## Context

`jig task current` (ADR-0008) resolved a task by branch, and the implementation broke ties
by status, then `updated_at`, then task id. Deterministic but arbitrary: on this very
repository `main` carried two active tasks, `jig task current` returned one of them, and
`jig context` silently loaded that workspace's `design.md`. An agent resuming there
continues the wrong work with full confidence — the poisoned-context failure the framework
exists to prevent, in the transient layer instead of the durable one.

Two related gaps: nothing recorded that a task was dormant, so "pause it" died with the
session, and nothing stopped a new task from starting on another task's dirty tree.

## Decision

- **Candidate** = a task in this checkout whose `branch` matches, whose `status` is
  `active` or `ready`, and which is not paused. `consolidated` and `abandoned` are
  excluded so that a trunk-based repository, where finished-but-unmerged workspaces pile
  up on `main`, does not become permanently ambiguous.
- **`jig task current` exits 2 on ambiguity**, printing the candidates on stderr and
  nothing on stdout; 0 with the id; 1 when there is none. Scripts report, skills ask
  (ADR-0001): the script cannot prompt because `context`, `status` and eventually
  housekeeping call it with no human present.
- **`jig context`** with several candidates warns and omits the workspace section rather
  than choosing. Read-only commands must not block, and omitting is safer than picking.
- **Pause is a field, not a `status` value.** `paused`, `paused_at`, `paused_reason`,
  `paused_stash`, all script-owned. `status` records lifecycle progress and pause is
  orthogonal to it: a task paused while `ready` must resume as `ready`. Same reasoning
  that kept `knowledge_consolidated` a separate boolean in ADR-0005.
- **Stashing is opt-in** (`pause --stash`) and records the **stash commit SHA**, not the
  index: `stash@{0}` shifts as other entries are pushed. Resume uses `git stash apply`,
  never `pop`, so the entry survives as a backup, and a failed apply clears nothing and
  exits non-zero.
- **Resume reports overlap, not distance**: which files this task changed also changed on
  the base branch. Sections are omitted when empty.
- **`jig task new` refuses a dirty working tree** (`--force` overrides), naming the task
  that likely owns the changes. This, not stashing, is the guarantee that a new task does
  not start on top of another one's work.

## Alternatives

- **Keep the ranking.** Rejected: silently continuing the wrong task is the expensive
  failure; a wrong guess costs more than a question.
- **`paused` as a `status` value.** Rejected: destroys the record of how far the task got.
- **Report commits on the base branch since the pause.** Rejected: distance is a poor
  proxy for relevance — forty commits elsewhere mean nothing, one in your own file means
  everything — and a metric that is usually noise trains people to ignore it.
- **Stash by default.** Rejected on asymmetric risk: an opt-in that turns out to be wanted
  costs one flag, a default that loses someone's work cannot be undone afterwards.
- **A config option to silence the resume report.** Rejected: a noisy signal should be
  fixed, not made switchable; a real one should not be off by default.

## Consequences

- Ambiguity becomes visible and cheap to resolve: pausing one of two live tasks restores
  unambiguous resume.
- The cleanup policy (SPEC §23) gains explicit rows for paused tasks, so pause exempts a
  task from auto-resume but never from being reported stale.
- ADR-0008 stands; this decision fills in what it left implicit about tie-breaking.
