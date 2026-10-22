# Next task advice — which task to take next

Depth: normal — started as an easy placeholder for a question the `contract-queue` epic left as
fog; raised on 2026-10-22, when its open questions came to be answered one decision at a time.

## Idea

Moved from `contract-queue` when its epic was finished (maintainer, 2026-10-20): next-task
selection by priority, order and dependencies — how an agent or a person is advised what to take
— was not stated, and `contract-queue` deliberately left it out "until the queue has been used".

## Goal and problem

- Who is worse off without this, and how: since 0.31.0 the queue holds priority, order and
  dependencies, but nothing reads them to say what to take next; an agent or a person picks by
  hand, and a task waiting for another can be started first.
- What is true when the work is done: an agent, a person and Jig UI ask Jig what to take next
  and get the same answer from the queue — a task, or the reason there is none.

## Stress test

- **The queue alone is not enough input.** Whether a dependency is finished and whether a task can
  be begun come from task state and git ancestry, not from the queue file; the advice reads all
  three.
- **Closed tasks stay in the queue.** Neither closing a task nor housekeeping removes its queue
  item, and `waits for` is printed whether or not the other task has landed; the advice has to
  tell a finished dependency from an open one itself.
- **Positions do not compare across levels**, so a raw position cannot rank a task in one epic
  against a task in another — decided below by the top-level item.
- Weakest point: the advice is only as good as the sorting behind it; a queue nobody keeps up
  advises stale work, and unqueued tasks are invisible to it except as a count.

## Scope and non-goals

- In scope: advice on the next task from the queue (priority, order, dependencies, pause).
- Not doing: anything with a server or a UI — that is Jig UI's.

## Decisions

- The next task is chosen in three steps (maintainer, 2026-10-21):
  1. A task waiting for an unfinished dependency is never advised, whatever its priority and
     position: a dependency outranks both. The task it waits for comes first.
  2. Among the rest, the lower priority number goes first (`0` before `1`).
  3. At equal priority, a started task goes before an unstarted one (maintainer, 2026-10-22, see
     below); after that, position decides. Within one level positions compare directly; across
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

- One command computes the advice, and every reader asks it (maintainer, 2026-10-22):
  `jig queue next [--json]` names the task to take by the three steps above, or says why there is
  none — everything waits for a dependency, everything is paused, the queue is empty. `jig status`
  shows its answer as one `next:` line; the `jig-task` skill asks it when a person says "what next"
  or "take the next one", instead of choosing itself; Jig UI reads the same JSON and keeps no rule
  of its own. Rejected: a `next:` line in `jig status` only — an agent and the UI would parse text;
  the rule in a skill only — prose each agent applies a little differently, the very drift the
  priority scale was written against (ADR-0001: mechanics go to scripts).

- A dependency is finished when its change has landed on its base (maintainer, 2026-10-22): Jig
  sees the task as merged — `needs consolidation` or `consolidated` — and an epic as merged into
  the default branch. The waiting task needs the code, not the closed record: its branch is cut
  from the base, where the code already is, while consolidation is bookkeeping and can lag a day
  behind the merge. A dependency on a task that was abandoned or is gone is not finished either:
  `jig queue next` calls it broken and names `jig queue undepend`, never drops it silently — a
  person set it with a reason. When ancestry answers `unknown`, the dependency counts as not
  finished and the advice says so, as housekeeping never acts on `unknown` (ADR-0025). Rejected:
  `consolidated` — the waiting task stands still until someone closes the other, with the code
  already in place; `ready` — too early, the change is not on the base and the waiting task's
  branch would be cut without it.

- Only work that can be begun or continued is advised (maintainer, 2026-10-22): a task not started
  yet, or an active one with its branch cut. Never advised: a paused task — a person set it aside,
  and taking it back is their call, not the queue's; a task with a pending pause request; a
  `ready` task — its work is done and only the ship is left, which the status page lists under
  "Needs you"; a merged or closed one. At equal priority a started task goes first, whatever its
  position: finishing costs less than switching, and a half-done branch ages away from its base.
  It only breaks a tie — a priority `1` not started yet still goes before a started `3`. Rejected:
  no weight for a started task, position alone — the queue would advise beginning something new
  while the old work hangs half-done, and unfinished work piles up; a started task before
  everything — a started "some day" `5` would hold a real bug `1` back.

- Unsorted work is never advised before sorted work (maintainer, 2026-10-22). A queued task with
  priority `none` goes after every task that has one, by position among themselves: no priority
  means "not sorted yet", not "urgent", and treating it as some number would be Jig guessing for
  the person. A task that is not in the queue at all — `jig task new` does not put it there — is
  not advised, but `jig queue next` names how many there are and the command that sorts them
  (`not queued: <n> tasks — jig queue set <id> --priority <p>`): advice comes from the order a
  person set, and an unsorted task is a reason to sort it, not to take it first. Rejected: treating
  unqueued tasks as `none` at the end — the advice is never empty, but it would pick by filing date
  what nobody meant to do; `jig task new` queueing every task at the bottom — it changes a shipped
  command, a decision of its own if it is ever wanted.

- Released without an epic (maintainer, 2026-10-22): `jig queue next` gives a user something on
  its own, so each item merges into the default branch as it is done, without a version bump; the
  pull request of the last item raises the version to `0.32.0` (minor — a new command and a new
  status line, nothing existing changes its meaning) and writes its release notes.

## Open questions

- None.

## Assumptions left untested

- That ancestry for every dependency is cheap enough for `jig status` to show `next:` on every
  run — status already asks it per task, but not yet for a queue with dozens of dependencies.
