---
id: adr-20261022-the-next-task-is-advised-from-the-queue
type: adr
status: accepted
date: 2026-10-22
domains:
  - task
  - scripts
paths:
  - scripts/lib/queue.sh
  - schemas/json.md
summary: Why jig queue next is the one place the next task is chosen, how a dependency counts as landed from task state, the last housekeeping run and a local epic-branch check, why priority, a started task and the top-level position order the rest, and why unqueued work is only counted.
---
# The next task is advised by `jig queue next`, from the queue, task state and the last housekeeping run — never a task waiting for a dependency that has not landed, then priority, a started task, and position

## Context

Since 0.31.0 the queue holds priority, order and dependencies
(adr-20261019-the-queue-is-one-file-written-against-a-revision), but that decision left "which task
to take next" as fog. Without an answer an agent or a person picks by hand, and a task waiting for
another can be started first. The next-task-advice spec settled the rules with the maintainer
(2026-10-21/22); this records them and how they are read, so they outlive the spec.

## Decision

- **One command computes the advice; every reader asks it.** `jig queue next [--json]` names the
  task to take, or says why there is none (`waiting`, `paused`, `empty`). `jig status`, the
  `jig-task` skill and Jig UI read its answer and keep no rule of their own (ADR-0001).
- **Candidates** are queued tasks with `status: active`, not paused and with no pending pause
  request. A `ready`, closed, abandoned or deleted task and an epic item are never advised.
- **A dependency must have landed.** On a task: `finished` when it is `consolidated` or the last
  housekeeping run logged it `remote=merged`; `broken` when it is abandoned or its workspace is
  gone (the advice names `jig queue undepend`); `open` when the last run logged `remote=open|closed`;
  `unknown` otherwise (the advice names `jig housekeeping`). On an epic: `open` while its spec
  declares an open epic; `finished` for the legacy `— finished` mark or, once the spec is gone, when
  the local `epic/<id>` branch is an ancestor of the default base; `broken` when that branch exists
  and is not; `unknown` with no branch. Only `finished` lets the waiting task through. A task of an
  epic waits for its epic's dependencies too.
- **Order among the rest:** the lower priority (`none` after `5`), then a started task (`branch`
  and `base_commit` set) before an unstarted one, then the position of the top-level item (an
  epic's tasks by the epic's position; an epic level not in the queue after every queued top-level
  item), then the task's own position.
- **Unqueued work is counted, not advised:** active, unpaused tasks with no queue item are reported
  as `not queued: <n>`.
- **It is a read.** No write, no revision raise, no network: merge state comes from what
  housekeeping already logged (`hklog_ids`), the precedent `jig spec plan` set, and the one git call
  is a local `merge-base --is-ancestor` for an epic dependency whose spec is gone. `queue.sh`
  sources `lib/hklog.sh` but not `lib/task.sh`, so it reads state through
  `_jig_task_state_value`.

## Alternatives

- **Position before priority** — priority would mean nothing to the order, and every urgent bug
  would need a drag.
- **Raw positions across levels** — positions are sparse per level; `100` in one epic says nothing
  against `200` in another.
- **A dependency finished at `consolidated` only** — the waiting task stands still until someone
  closes the other, with the code already on the base; **at `ready`** — the code is not on the base
  yet.
- **Live ancestry per dependency** — housekeeping's ancestry is costly and bound to its run's
  globals; reading its log keeps the command cheap enough for `jig status` to call on every run.
- **Unqueued tasks as `none` at the end** — the advice would pick by filing date what nobody meant
  to do.
- **A missing spec and branch read as `broken`** — an epic branch is often deleted on the forge
  after its merge, so a finished epic would be blamed; `unknown` holds the task without blaming it.

## Consequences

- The advice is only as fresh as the last housekeeping run: right after a merge a dependency reads
  `unknown` until housekeeping has run, and the advice says so.
- The rules live in one awk (`_queue_next_decide`); `jig status` and the skill must call the command
  rather than restate them.
- `jig queue next --json` is a contract Jig UI reads (schemas/json.md); its fields follow
  conventions/json-output.md.

> **Amendment (2026-10-30).** A candidate another session holds is not advised
> (adr-20261030-a-task-another-session-works-on-is-not-advised): the newest live record under
> `.ai/runtime/taken/<id>/` in the clone's main checkout belongs to a session other than the caller.
> The answer names each such task with the checkout that session works in, since when and how long
> ago it was last active; `--json` lists them under `taken`, and `reason` gains `taken`, read after
> `waiting` and before `paused`. The facts reach `_queue_next_decide` as `tk` lines, so the rules stay
> in the one awk. The read is still a read: the records are only stat'ed and read.
