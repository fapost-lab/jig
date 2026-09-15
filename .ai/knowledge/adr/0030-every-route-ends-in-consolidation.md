---
id: adr-0030-every-route-ends-in-consolidation
type: adr
status: accepted
date: 2026-09-13
domains:
  - task
  - housekeeping
paths:
  - "skills/jig-consolidate/**"
  - "skills/jig-verify/**"
  - "skills/jig-task/**"
  - scripts/lib/task.sh
  - schemas/state.md
  - AGENTS.md
  - templates/AGENTS.md
summary: Why every task route ends in consolidation, and why the knowledge decision is recorded before the commit but the task closes only after it lands.
reviewed_at: 2026-09-15
---
# ADR-0030: Every route ends in consolidation; a task closes after it lands

## Context

The routes gave consolidation only to T3 and T4. `jig-verify` ended every route with
`status ready` and sent a task on to consolidation "for T3 and T4, or whenever the task
produced knowledge worth keeping". A T0–T2 task with nothing durable therefore stopped at
`ready`.

Housekeeping purges only `consolidated:merged`; `ready:merged` is preserved and flagged
`needs-consolidation`. On 2026-09-11 the T2 task `knowledge-new-proposed` recorded
`NO_DURABLE_KNOWLEDGE` in its `plan.md`, stopped at `ready`, merged, and stayed. It became
purgeable only after two hand-typed `jig task set` commands. AGENTS.md already required
every task to end in updated knowledge or `NO_DURABLE_KNOWLEDGE`, but nothing recorded that
statement in task state.

Relaxing housekeeping to purge `ready:merged` was rejected by the maintainer: a merge does
not mean a task is finished, because errors and follow-up fixes come after it. Only an
explicit record says a task is done. That left the question this ADR answers: at which
moment is that record written?

ADR-0005 kept two fields, a `knowledge_consolidated` boolean and a `status` that includes
`consolidated`, and its own Context noted that the status duplicated the flag. Until now
both were written together at the end of `jig-consolidate`, before the commit.

## Decision

- **Every class's route ends with `consolidate`**, T0–T2 included. A task without a
  workspace states its knowledge decision in the report; there is no state to record it in.
- **The two fields record two different moments.**
  - `knowledge_consolidated: true` — *the knowledge decision is recorded*. Written at the
    end of the route, before the commit, `NO_DURABLE_KNOWLEDGE` included, so the knowledge
    and the code enter the repository together. The status stays `ready`, and the task
    stays a `task current` candidate while review fixes continue.
  - `status: consolidated` — *the task is closed*. Written after its change has landed and
    no fix is expected on it. The prompt is housekeeping's existing `needs-consolidation`
    flag on `ready:merged` (exit 3, `jig status`).
- **A task whose landing cannot be observed closes at the end of its route**: one with no
  `branch` recorded, or whose `branch` is the base branch (possible with
  `git.branch_per_task: false`). Ancestry answers `unknown` for it forever (ADR-0025), so
  housekeeping never flags it. Left at `ready`, such tasks would pile up as `task current`
  candidates on the base branch — the permanent ambiguity ADR-0012 excluded `consolidated`
  from candidates to prevent. A task sharing a branch other than the base branch is not
  exempt: that branch can still be seen to land.
- **`jig task set` enforces the order.** `status consolidated` is refused while
  `knowledge_consolidated` is not `true`, and `knowledge_consolidated false` is refused on
  a consolidated task. Closing without a recorded knowledge decision becomes impossible.
- **The housekeeping policy is unchanged.** Its flag keeps the name `needs-consolidation`
  even when only the close is missing: the flag is a line format read by `jig status` and
  `jig measure` (ADR-0027), and renaming it is a separate decision.

## Alternatives

- **Write both fields at the end of the route, before the commit** (the T3/T4 practice so
  far). One touch per task, and housekeeping then finishes alone. Rejected: it declares a
  task done before its change can have landed, so the merge itself ends the task's life.
  A fix after the merge finds the workspace in trash, and review fixes before the merge
  work on a task that has already dropped out of `task current`.
- **Purge `ready:merged` once `knowledge_consolidated` is true.** Rejected by the
  maintainer: housekeeping must not infer that a task is finished from a merge.
- **Housekeeping closes `ready:merged` itself after a quiet period** (for example seven days
  after the merge, with the knowledge decision recorded). Zero touches, and trash still
  keeps the workspace recoverable. Declined by the maintainer on 2026-09-13 in favour of
  an agent asking at session start: it is the same inference with a delay, it would make
  housekeeping write `state` (ADR-0005), and "no fix is expected" is a judgement a script
  cannot make (ADR-0001).
- **Write both fields after the change lands.** Rejected: the knowledge would reach the
  repository in a separate change, apart from the code whose intent it records.

## Consequences

- No task with a workspace ends at `ready` any more: `needs-consolidation` changes from an
  anomaly into the expected signal to close a task.
- Every task whose landing can be observed costs a second touch after it lands: a
  decision, not a cleanup — housekeeping still does the cleanup. Nobody has to remember
  it: `jig-task` runs `jig housekeeping --dry-run` at the start of a session, names each
  task flagged `needs-consolidation` and asks the user whether to close it, so the touch
  is an answer. The dry run fetches nothing and writes nothing, and it works where no
  session hook or scheduler is installed.
- For T3 and T4 the purge moves later, from "merged" to "merged and closed". Nothing becomes
  purgeable without an explicit `status consolidated`, as before.
- Tests and fixtures that set `status consolidated` directly must record the knowledge
  decision first.
- ADR-0005 and ADR-0009 stand; this decision fills in what they left open about the
  timing of the two fields and the routes of the lower classes.

> **Amendment (2026-09-15).** For a task linked to a specification, recording the knowledge
> decision includes checking its roadmap items (`jig spec done`), before the commit, for the reason
> this ADR records the decision there at all: what the task leaves behind enters the repository with
> the code. The close stays after the landing. See ADR-0035.
