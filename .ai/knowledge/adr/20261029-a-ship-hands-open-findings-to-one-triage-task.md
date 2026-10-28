---
id: adr-20261029-a-ship-hands-open-findings-to-one-triage-task
type: adr
status: accepted
date: 2026-10-29
domains:
  - task
paths:
  - scripts/lib/task.sh
  - scripts/lib/notify.sh
  - skills/jig-consolidate/SKILL.md
  - "skills/jig-review/**"
summary: Why jig task ship hands a task's open P2/P3 findings to one not-started triage task when its pull request exists, why the source ledger stays untouched, and why knowledge gaps go to consolidation instead.
reviewed_at: 2026-10-29
---
# A ship hands the open P2 and P3 findings to one triage task, and leaves the ledger as it is

## Context

By the findings rules a P3 is never fixed after the review and a P2 stays `open` on a lean route;
both were only listed in the pull request's body. At `agent.git: merge` the autopilot merges that
pull request itself, so the list reached nobody but the agent, and `jig_notify_autopilot` sent
`end` without a word about it. A real lean run left three that way: an untested scrub path (P2), a
case the scrub missed (P3), and a new module written into RULES.md but not ARCHITECTURE.md (P3).

## Decision

- **`jig task ship` files the triage task**, once its pull request exists (`pr_url` was just
  written), before the merge: at levels `pr` and `merge`, without autopilot too. Not at `commit`
  or `push`, where no pull request exists to link and the person opens one, and not for a
  `--draft`, which is an unfinished task whose findings are still its own.
- **One task per ship, never one per finding**: `<id>-findings`, filed through `jig task new` in a
  process of its own, with no class, not started and not queued — `jig queue next` takes only
  queued tasks, so no autopilot picks it up. Its `task.md` holds the findings verbatim (id,
  severity, where, summary), the pull request and the source task; its goal is to decide each one
  with a person: a task filed for it, or a dismissal with a reason. The open findings are the P2
  and P3 lines in status `open` (`_task_open_minor_findings`); `fixed` waits for a re-review and is
  not among them.
- **The two are linked in state**: `triage_task` on the source, `triage_of` on the triage task. A
  repeated ship finds either and files nothing, and adds no finding to the task already filed —
  its `task.md` may be a person's by now. An `<id>-findings` without `triage_of: <id>` is somebody
  else's task and is left alone.
- **The source ledger is not touched.** The review's receipt pins its hash and `task ship` checks
  the receipt again right before the merge: a status written here would leave every such pull
  request unmerged. `jig task findings <id>` says `handed to <triage>: <n> open P2/P3` instead.
- **Filing never stops the ship.** A refusal — a worktree whose own workspace would lose the task,
  an id that is taken — is a `task ship: warning:` line; the findings are still in the body.
- **`end` names them.** The autopilot's `end` message carries `<n> open findings → task <triage>`
  when the task has open P2/P3 and a triage task, and `<n> open findings, not handed to a triage
  task` when it has open P2/P3 and none (the hand-over warned, or no pull request was opened). No
  message is added; a task without open P2/P3 gets no such line.
- **A gap in durable knowledge is not a finding.** The review lists it for consolidation, which
  writes it before the commit (knowledge edits leave the receipt current); one already recorded
  keeps its status and the pull request body names where it was written.

## Alternatives

- **At `jig task autopilot end`.** A ship without autopilot would lose the findings as before.
- **In housekeeping after the merge.** Later than `end`, so the message could not name the task,
  and housekeeping derives state; it does not create work.
- **Mark each finding `dismissed` ("handed to …") or add a status.** Either edits the ledger after
  the review and stales the receipt the merge rechecks; a new status changes every reader of the
  ledger for what state already says.
- **A summary on the status page.** It shows the present: once the source task is closed and its
  workspace trashed, the findings would go with it. A task stays until someone decided it.
- **A separate kind of task the queue never takes.** "Not started and not queued" already behaves
  that way.

## Consequences

- A merged autopilot run can no longer bury its P2/P3: the person gets one task and one line on
  their phone.
- Reverting the code leaves the triage tasks already filed; they are ordinary tasks, archived with
  `jig task archive`, and no ledger was changed.
- The triage task's `task.md` is in English, as every brief a script writes.
- A triage task is an ordinary filed task: housekeeping archives it as `stale` after
  `housekeeping.stale_after` untouched, like any other (adr-20261027-a-task-nobody-finished-is-archived-not-purged).
  Archived, not purged: it can be returned with `jig task unarchive`.
- `triage_of` is written after `task new` returns; an interruption between the two leaves
  `<id>-findings` unlinked, and the next ship warns that the id is taken instead of naming it.
