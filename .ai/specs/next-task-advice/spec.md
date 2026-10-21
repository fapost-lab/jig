# Next task advice — which task to take next

Depth: easy — a placeholder that keeps a question the `contract-queue` epic left as fog; it is
stress-tested when the queue has been used.

## Idea

Moved from `contract-queue` when its epic was finished (maintainer, 2026-10-20): next-task
selection by priority, order and dependencies — how an agent or a person is advised what to take
— was not stated, and `contract-queue` deliberately left it out "until the queue has been used".

## Goal and problem

- Who is worse off without this, and how: since 0.31.0 the queue holds priority, order and
  dependencies, but nothing reads them to say what to take next; an agent or a person picks by
  hand, and a task waiting for another can be started first.
- What is true when the work is done: not stated yet.

## Stress test

- Not done yet: the question cannot be stated precisely before the queue has been used.

## Scope and non-goals

- In scope: advice on the next task from the queue (priority, order, dependencies, pause).
- Not doing: anything with a server or a UI — that is Jig UI's.

## Decisions

- The next task is chosen in three steps (maintainer, 2026-10-21):
  1. A task waiting for an unfinished dependency is never advised, whatever its priority and
     position: a dependency outranks both. The task it waits for comes first.
  2. Among the rest, the lower priority number goes first (`0` before `1`).
  3. At equal priority, position decides. Within one level positions compare directly; across
     levels — tasks in two epics, or a task in an epic and one without — the positions of their
     top-level items decide (the epic's position, or the task's own when it has no epic).
  Rejected: position before priority — priority would then mean nothing to the order, and the
  queue would need a drag for every urgent bug; comparing positions across levels as raw numbers —
  sparse positions are per level (adr-20261019-the-queue-is-one-file-written-against-a-revision),
  so `100` in one epic says nothing against `200` in another.

- Priorities `0`–`5` mean one scale (maintainer, 2026-10-21): `0` broken or dangerous (data loss,
  a destructive operation, install fails); `1` a bug a user meets; `2` not a bug, but stops a user
  doing their own work; `3` friction; `4` an improvement or a new capability; `5` some day. It goes
  into the glossary and the queue docs page, so "bugs first" is set the same way by every
  person and agent. Rejected: a separate task type (bug, feature) — a second field to keep in step
  with the priority, when the scale already orders bugs before features.

## Open questions

- Who asks — an agent at the start of a session, `jig status`, Jig UI — and in what form.
- Whether a started task goes before an unstarted one of the same priority. Recommended yes:
  finishing costs less than switching, and a half-done branch ages. Against: a position the person
  set on purpose is overridden.
- Where a task with no priority (`none`) stands — recommended after every task that has one, by
  position among themselves.
- When a dependency counts as finished: its change merged, or its task consolidated (ADR-0030).

## Assumptions left untested

- That the queue as shipped in 0.31.0 is enough input — to check once it has been used.
