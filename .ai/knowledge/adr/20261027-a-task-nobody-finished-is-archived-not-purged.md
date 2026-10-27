---
id: adr-20261027-a-task-nobody-finished-is-archived-not-purged
type: adr
status: accepted
date: 2026-10-27
domains:
  - housekeeping
  - task
  - safety
paths:
  - scripts/lib/housekeeping.sh
  - scripts/lib/task.sh
summary: Why an abandoned or idle task is archived in place with status archived instead of purged, who writes it, and what housekeeping may now write into state.
---
# ADR: A task nobody finished is archived, not purged

## Context

Housekeeping ended the life of a task nobody finished in one of two ways. An `abandoned` task was
moved to trash once it was older than `housekeeping.abandoned_ttl` (14 days), and deleted from
trash `trash_ttl` (7 days) later: three weeks from "I gave up on it" to gone, its `design.md`,
`discovery.md` and notes with it (ADR-0005, ADR-0006). A task that was merely idle — `active` or
`ready`, untouched for longer than `housekeeping.stale_after` — was only flagged
`STALE_CANDIDATE`, and the flag changed nothing: the task kept crowding `jig task list`, the status
page and the queue until a person closed or abandoned it by hand.

Both ends were wrong in the same period of a project's life. During active development tasks
arrive faster than they are done, so a long tail of half-started work is normal, not neglect. A
person who abandons a task usually means "not now", not "never"; the discovery behind it is the
expensive part, and three weeks later it was deleted. And the idle tail they did not abandon sat in
every list they read. The choice offered was between losing the work and living with the clutter.

## Decision

**A task nobody finished is archived: its `status` becomes `archived`, and the workspace stays
exactly where it is, without a time limit.**

- `status` gains a fifth value, `archived`. The workspace is not moved: `.ai/workspace/tasks/<id>/`
  stays, so every reader of that path (the queue, spec plans, measure, a task worktree's workspace
  link) keeps working. The state gains script-owned keys `archived_at` (`YYYY-MM-DD`),
  `archived_reason` (`abandoned`, `stale` or `manual`) and `archived_from` (the status before).
- The value is written only by `jig task archive <id>` (reason `manual`, from `active`, `ready` or
  `abandoned`; refused for `consolidated`, whose work is already in git) and by housekeeping.
  `jig task set` refuses to write `archived`, to write the three keys, and to change the status of an
  archived task, as it does for `paused`. `jig task unarchive <id>` returns `archived_from`, removes
  the keys and refreshes `updated_at`, so the next run does not archive the task again.
- Housekeeping's policy (`housekeeping_decide`) gains a third action, `archive`, beside `purge` and
  `preserve`:
  - `abandoned` older than `abandoned_ttl` is archived (reason `abandoned`) instead of moved to
    trash. It still tries to remove a clean worktree through git, as the purge did; if the worktree
    stays, the task is archived anyway and flagged `worktree-kept`.
  - `active` or `ready`, untouched for longer than `stale_after`, with no other flag and a remote
    state that is not `open`, `merged` or `closed`, is archived (reason `stale`). A stale task that has a
    worktree, or whose branch is checked out with changes, is not archived and keeps
    `STALE_CANDIDATE`: someone may be working there who never touched the state file.
  - `archived:*` is preserved; `archived:merged` is flagged `needs-consolidation`, because the work
    did land after all.
  - `consolidated` and merged is purged to trash, unchanged. Trash now holds only the workspaces of
    closed tasks, and specifications removed by `jig spec remove`.
- Housekeeping archives by calling the task domain's writer (`_task_archive`), as `jig spec remove`
  calls `task abandon`. This changes a boundary: housekeeping used to write nothing into `state`
  (domains/housekeeping). It now writes exactly the three archive keys and `status`, through the
  task domain, and nothing else. The log line is `action=archive reason=abandoned|stale`; a dry run
  prints `would-archive` and changes nothing.
- Branch, worktree, pull request, pause stash and queue place are not touched by archiving. The
  other readers of `status` treat `archived` like `abandoned`: checkout occupancy, pause requests,
  the queue (a dependency on an archived task is `broken`, the item itself stays so that
  `unarchive` restores its place), spec plans (item state `archived`; `spec link` refuses; `spec
  remove` keeps it), measure (its own `archived` count) and the status page's recheck.
- Archived tasks are hidden from live lists, as finished ones are, and shown on request:
  `jig task list --status archived`, a line `archived: N` in `jig task list` and `jig status`, a
  collapsed "Archive (N)" block on the status page. In `--json` a task object gains `archived_at`,
  `archived_reason` and `archived_from` (`null` otherwise), `task list --json` gains a top-level
  `archived` count, a subset of `hidden`, and the `status` enum gains `archived`. The schema version
  stays 1: an archived task appears only to a caller who asked for it (`--status archived`,
  `--all`), so a reader written against the four statuses sees nothing new unless it asks.
- Two new action ids join the table of what a person may do: `archive` and `unarchive`. An archived
  task offers only `unarchive`; `active`, `ready` and `abandoned` offer `archive` as well.

## Alternatives

- **Move the workspace to `.ai/workspace/archive/<id>/`.** Rejected: about forty places read
  `tasks/<id>`. A moved task would drop out of the queue (`broken` dependencies), out of spec plans
  (`no-workspace`), measure and the hklog, and a task worktree would lose the target of its
  workspace link. The only gain is a tidier directory.
- **Trash without a time limit.** Rejected: trash is listed nowhere, so an entry that never expires is
  deletion that has not happened yet, and no one finds what they cannot see.
- **Only a flag, as `STALE_CANDIDATE` was.** Rejected: the complaint was the clutter in the lists,
  and a flag leaves every list as it was.
- **A setting that turns stale-archiving off.** Rejected: a key the user must understand before the
  tool behaves is against zero-config. `stale_after` is already the threshold; nothing is deleted,
  so a policy that is too eager is corrected by `unarchive`, not by a switch.

## Consequences

- Abandoning is no longer a countdown to deletion. An abandoned or idle task leaves the lists after
  its period and stays recoverable by `jig task unarchive`, at any time, with its documents.
- The archive grows without bound. Workspaces are text and small; if that ever matters, a limit is a
  new decision, and the same table is where it would go.
- Housekeeping is no longer purely a reader of `state`. The write is narrow and goes through one
  function in the task domain, which is where the rule that `task set` refuses `archived` already
  lives; a change to what `archived` means is a `task` change.
- A stale task with a worktree stays flagged rather than archived, so the flag survives for the
  cases where archiving is unsafe, not as the report-only default it used to be.
- Undo of the release: a Jig that predates `archived` reads the value and hides the task as finished,
  but refuses to write it. Run `jig task unarchive` on every archived task before downgrading.
- Amends ADR-0005 (the status enum; an abandoned task is not purged) and ADR-0006 (what goes to
  trash).
