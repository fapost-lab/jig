---
id: adr-20261027-an-absorbed-task-is-archived-with-its-receiver
type: adr
status: accepted
date: 2026-10-27
domains:
  - task
  - housekeeping
paths:
  - scripts/lib/task.sh
  - scripts/lib/queue.sh
summary: Why a task another task does the work of is archived with reason absorbed instead of getting a new status, what is copied, how the queue and the tracker are handled.
reviewed_at: 2026-10-27
---
# ADR: An absorbed task is archived with its receiver

## Context

Two filed tasks sometimes turn out to be one piece of work: a task is filed, then another that
covers it, or a bigger one swallows a smaller. Jig had no word for this. The person abandoned one
task (its notes then aged towards archive, with nothing saying where the work went) or left both
open and let a second agent redo the first's analysis. Queue waits on the dropped task went
`broken`. And the tracker issue behind it stayed open with nothing linking it to the pull request
that actually did the work.

The task was to record "task B does task A's work" so that A's documents are not lost, A leaves the
live lists, the queue stays consistent, and the tracker can close A's issue without Jig calling it.

## Decision

**`jig task merge <from> --into <to> [--partial]` copies `<from>`'s documents into `<to>` and
records the link in both states. A fully absorbed task is an archived task with reason `absorbed`.**

- Copy, not move. `<from>`'s `*.md` documents, and whatever it had absorbed itself, go to
  `<to>/absorbed/<from>/`. `<to>`'s `task.md` gains `## Absorbed: <from> (whole)` (or `(partly)`)
  with `<from>`'s goal and a pointer to the folder. Nothing is merged or rewritten: the texts are
  kept as their author wrote them.
- Whole merge: `<to>` gets `absorbs` (comma list); `<from>` gets `absorbed_into: <to>` and is
  archived through the task domain's writer with the new `archived_reason` `absorbed` (the reasons
  are now `abandoned`, `stale`, `manual`, `absorbed`). It happens at once, not when `<to>`
  consolidates: the documents are already copied, and `jig task unarchive` brings `<from>` back.
- Queue (`queue_absorb`): waits on `<from>` move to `<to>`; `<from>`'s own waits move to `<to>`; a wait
  between the two disappears. A move that would close a cycle refuses the merge before anything is
  copied or written. `<from>`'s item stays, as any archived task's does.
- Partial merge: the same copy, with `(partly)` in the section. `<from>` stays live with `partly_in`
  (list) and a `## Partly in <to>` section; `<to>` gets `absorbs_partly`. The queue is not touched.
- Refusals: a task into itself; a receiver that is not `active` or `ready`; a `<from>` that is
  `consolidated` or archived; a whole merge when `absorbed/<from>` already exists.
- The four keys (`absorbed_into`, `absorbs`, `absorbs_partly`, `partly_in`) are script-owned; `jig
  task set` refuses them. `jig task unarchive` of an absorbed task removes `absorbed_into`; the
  receiver keeps `absorbs` as history.
- Tracker: Jig never calls a tracker API. `jig task ship` of the receiver appends one line
  `Absorbs: <ref>, <ref>` (the issue refs of the tasks it absorbed, wholly or partly; `#N` for a
  numeric issue) to the commit message and to the pull request body, once. The tracker's own
  integration links them (adr-20261010-a-task-carries-its-tracker-issue).
- Visibility: `task list` text rows show the four keys when set; `task list --json` task objects gain
  `absorbed_into` (string or null) and `absorbs`, `absorbs_partly`, `partly_in` (arrays, empty when
  none), after `archived_from`. The schema version stays 1: these are additions.
  `merge` is not in the actions table, as it has no one ready form without a target.

## Alternatives

- **A `superseded` status.** Rejected: archived is already kept without limit, visible apart from
  live work, and understood by every reader (queue, spec plans, checkout, measure, the status page).
  A new status would touch about fifteen readers again for no distinction a reader needs; the reason
  and `absorbed_into` carry it.
- **Archive on the receiver's consolidation.** Rejected: until then the absorbed task sits in every
  live list and the queue, and the copy has already happened. If the merge was a mistake, `unarchive`
  undoes it.
- **Close the issues through the tracker API.** Rejected: it is an outward-facing write to a system
  Jig has never called, with its own credentials and failure modes. The `Absorbs:` line lets the
  tracker's own integration do it where the person's team already trusts it.
- **Move the documents.** Rejected: the same reason the archive keeps the workspace in place; `<from>`
  must stay readable and restorable, and a move makes `unarchive` lossy.
- **An agent merges the texts into one.** Rejected: it rewrites what people wrote, silently, and the
  result cannot be checked against the sources. Keeping both under `absorbed/` costs a folder.

## Consequences

- Absorbing a task takes one command and loses nothing; undoing it is `jig task unarchive`.
- The reasons for archiving grow to four, and every reader of `archived_reason` must tolerate
  `absorbed` (schemas/state.md, schemas/json.md).
- `task ship` reads the state of other tasks (the absorbed ones' `issue`), a small new coupling inside
  the task domain.
- A partial merge records intent only: Jig does not track which part of `<from>` is covered; the
  section in `task.md` is where a person or agent says so.
- The receiver's `absorbs` outlives an unarchive, so after one the two states disagree on purpose:
  the history says it was once absorbed.
- Undo of the release: a Jig that predates `absorbed` reads the archived task and hides it, but
  refuses to write the reason; unarchive absorbed tasks before downgrading.
