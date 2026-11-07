---
id: adr-20261107-a-finished-task-leaves-the-queue
type: adr
status: accepted
date: 2026-11-07
domains:
  - task
  - housekeeping
  - scripts
paths:
  - scripts/lib/queue.sh
  - scripts/lib/task.sh
  - scripts/lib/housekeeping.sh
  - schemas/json.md
summary: Why a closed, abandoned, archived or vanished task's queue item is taken out by jig queue prune at the command that finishes it and in every housekeeping run, why a wait on it goes only when the advice reads it as finished, and why a task taken back is not re-queued.
---
# A finished task leaves the queue — at the command that finishes it, and in every housekeeping run — and a wait on it goes only when the advice already reads it as met

## Context

The queue (adr-20261019-the-queue-is-one-file-written-against-a-revision) kept an item until a
person ran `jig queue remove`. `jig queue next` passes over a task that is not `active`
(adr-20261022-the-next-task-is-advised-from-the-queue), but `jig queue list`, the status page and
Jig UI showed every item: on 2026-11-07 this repository's queue held 33 entries, 21 of them tasks
already closed, abandoned, archived or gone, and the backlog looked three times bigger than the work
left. The archive decision (adr-20261027-a-task-nobody-finished-is-archived-not-purged) had kept an
archived task's item on purpose, so that `unarchive` would restore its place; in practice that place
was clutter nobody returned to.

A second fault sat under the first. A wait is judged from the task's state file, not from its item.
Once housekeeping purges a closed, merged task to trash, its state file is gone, and every wait on it
read `broken` — work that had landed blamed as work that never would.

## Decision

- **A task is finished** when its `status` is `consolidated`, `abandoned` or `archived`, or its
  state file is gone. `active`, `ready` and a paused task are not: a started task stays queued until
  it is finished. Epic items are not touched by this decision.
- **`jig queue prune [--dry-run] [--revision <n>] [--json]`** takes every finished task's item out
  of the queue in one write, with what each waited for and every pause request it held. In the same
  write it drops every wait on a task that `_queue_next_dep_state` reads as `finished` (closed, or
  merged as the last housekeeping run logged it): the same judgement the advice makes, so dropping
  the wait changes no advice, and the wait can no longer turn `broken` when the workspace is purged.
  A wait on an abandoned, archived or vanished task stays: it reads `broken`, and the advice still
  names `jig queue undepend`. Work that never landed unblocks nothing silently.
- **A task is gone only when this checkout sees the clone's task workspace** — the directory the
  main checkout holds, where a worktree's link leads. A checkout that cannot see it finds nothing
  gone, so it cannot empty the queue.
- **With nothing to take out nothing is written**, so no revision is claimed or checked. A dry run
  says what would go and writes nothing.
- **Who calls it.** The commands that finish a task — `jig task set <id> status consolidated` (with
  or without `--revision`/`--json`), `status abandoned` and so `jig task abandon`, and `_task_archive`
  and so `jig task archive`, housekeeping's archive and `jig task merge` — call it once the status is
  written, as `"$JIG_SELF" queue prune --json`: `jig queue` stays the queue's only writer, and
  `task.sh` does not source `queue.sh` for it. It is best effort: a stale revision is retried three
  times, and a queue that cannot be rewritten is warned about with the command to run, never a
  reason for the status write to fail. `jig housekeeping` calls it at the start of every run, before
  this run's log marker and before any workspace is purged (so a real run and a dry run both read
  the merges the last run logged, as the advice does), so a wait on a closed task is judged while its state still says so, and
  an entry left behind — a task deleted by hand, one closed before this version, a write that lost
  three races — goes at the next run. A dry run calls `--dry-run`. This is the second time
  housekeeping changes something outside its own runtime files and the trash, after archiving; it
  goes through the queue's command, as archiving goes through the task domain's writer.
- **A task taken back does not get its place back.** `jig task unarchive` to `active` or `ready`,
  and `jig task set <id> status active|ready` from `abandoned`, print the reminder `jig task new`
  prints (`not queued: <id> — jig queue set <id> --priority <0-5>`), and the task is counted under
  `not queued:` by the advice. An unarchive back to `abandoned` prints none: the task is still
  finished, and the next prune would take a new entry out again.

## Alternatives

- **Hide finished items in the listing, keep them in the file.** Every reader — `jig status`,
  `jig context`, Jig UI — would have to repeat the filter (ADR-0001), and the file would only grow.
- **Only housekeeping.** A closed task would stay listed until the next run.
- **Only the commands that finish a task.** A task deleted by hand, and every entry from before
  this version, would never go.
- **Read every wait on a finished task as met** (abandoned and archived included). It would unblock
  work that waits for something nobody did, against adr-20261022's `broken`.
- **Keep an archived task's item so `unarchive` restores it** (adr-20261027 as written). That place
  is what made the backlog unreadable; the reminder on the way back costs one command.
- **Source `queue.sh` in `task.sh`, as `jig task merge` does for `queue_absorb`.** A stale revision
  there ends the command after the status is already written; a child process keeps the refusal
  its own. `queue_absorb` stays as it is: it must refuse the merge before anything is written.

## Consequences

- `jig queue list` shows the work left. A close with `--revision`/`--json` raises the revision by
  two more when the queue changed; the envelope's revision is read before the producer runs, so a
  consumer reads again, as after any write.
- Once a task is finished its own waits are gone: `jig task unarchive` cannot restore them, as it
  never could restore the waits `task merge` moved.
- A legacy wait on a closed task whose workspace was purged before this version reads `broken`
  until someone runs `jig queue undepend`.
