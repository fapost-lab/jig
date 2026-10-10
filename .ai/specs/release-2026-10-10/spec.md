# Release 0.26.0

Planned with the owner on 2026-10-10 (jig-release); the owner approved this document.

## What goes in, in order

1. `phase-run-stops-notify` (T2) — when a phase run's coordinator stops (a wave waiting for the
   person, a draft ending the run), a Telegram message names the spec, the phase and what is
   needed. Today the costliest stop sends nothing: the person does not know a whole wave waits.
2. `notification-hook-for-sessions` (T3) — an ordinary session that waits for the person's
   permission or input sends the same short Telegram message, behind `notify.interactive`
   (default `false`).
3. `tracker-issue-id` (T3) — a task is linked to a tracker issue: the issue id is read from the
   task id by a project-level pattern (alphanumeric `PROJ-123` or numeric `123`), stored as a
   field of its own, shown by `task show`/`status`, and put into the commit's first line and the
   pull request title by `task ship`. No pattern configured, no issue read.
4. `linked-sources-in-pr-body` (T2) — `jig task autopilot <id> report` and the pull request
   body name the changed linked knowledge sources that wait for the person's review
   (`jig-accept`), so a person sees it before the merge, not after `git pull`. Added by the owner
   on 2026-10-10 after the plan was approved.
5. `release-2026-10-10-notes` (T2) — the release notes, written against the merged pull
   requests' diffs; the version raised by the recorded level.

Order: the first two make stops visible that today slow work down silently, the narrower and
costlier one first; the tracker link and the linked-sources block are new capability and go
after them.

## What stays out

- `release-0-25-1` — released as 0.25.1 from `main` (PR #219) before this spec was declared; the
  epic gets it through `main`.

## Level

minor — new keys and behaviour (`notify.interactive`, the tracker pattern), nothing an existing
project must change.
