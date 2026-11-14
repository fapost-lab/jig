---
id: adr-20261114-a-closed-task-never-started-goes-to-trash
type: adr
status: accepted
date: 2026-11-14
domains:
  - housekeeping
  - task
  - safety
paths:
  - scripts/lib/housekeeping.sh
summary: Why housekeeping purges a consolidated task that never had a branch, how narrowly 'never started' is read, and what stays kept.
reviewed_at: 2026-11-14
---
# ADR: A closed task that was never started goes to trash

## Context

Housekeeping purges a workspace to trash only when the task is `consolidated` and its remote state
is `merged` (ADR-0006), and it never destroys a workspace whose remote state is `unknown`
(RULES.md). A task that was closed without ever being started — no `branch:` and no `base_commit:`
in its state, the case of nearly every `<id>-findings` triage task closed by decision
(adr-20261029-a-ship-hands-open-findings-to-one-triage-task) — has no branch to ask, so its
remote state is `unknown` and it was kept forever under "kept, cannot tell whether it landed —
never started, so there is no branch to check". On this repository 31 such workspaces had
gathered within two weeks, and the "finished" count in `jig task list` only grew.

"Cannot tell whether it landed" protects work whose fate git cannot see. A task that never had a
branch has no such work: there is no change whose landing could be unknown, and the person's
close (`status consolidated`, which implies the knowledge decision, ADR-0030) is the whole
decision.

## Decision

**A `consolidated` task that was never started is purged to trash like a closed and merged one.**

- "Never started" is narrow and every doubt counts as started: the state has no `branch` and no
  `base_commit` (both written by `jig task start`), no ref exists locally or on origin at the
  task's `git.branch_template` name, and no pull request from that name — into any base, in any
  state — is in the list the forge gave this run. A forge that was asked and did not answer keeps
  the task. Where no forge is in use (`none`: no remote on a known host, or its CLI missing or
  signed out), git's refs are the whole check; the list holds a forge's newest pull requests only
  (200 on GitHub, 100 on GitLab), and an older one from a branch since deleted is not seen.
- A triage task (`triage_of`) stays while its source task's workspace is here: the source's next
  `task ship` reads it to hand its open findings over only once
  (adr-20261029-a-ship-hands-open-findings-to-one-triage-task). Once the source is purged, the
  triage task follows on the next run.
- A task kept by one of these doubts says which in the report, in place of "never started, so
  there is no branch to check".
- `housekeeping_decide` stays a pure function: it takes `started` as its tenth argument (default
  `true`), and `consolidated:unknown` with `started=false` is `purge`. The caller derives it.
- The log keeps `remote=unknown` on the task's line: the remote state is reported as it is, and
  the readers that match on it (`jig queue`, `jig status`, the status page) see no new value.
- Everything else stays kept: a task recorded on a detached HEAD or on the base branch, one whose
  branch was deleted (`its branch ... no longer exists`), and any `active`, `ready`, `abandoned`
  or `archived` task without a branch — those go on being preserved or archived as before.

## Alternatives

- **A new remote state `none` for a task with no branch.** Honest, but every reader of
  `remote=` in the log and the status page's contract would have to learn it, for one policy
  decision the caller can make.
- **Purge only bare triage tasks (`triage_of` set).** Narrower, but leaves the same clutter for
  any other task a person closed without starting, and the reason — no change to lose — is the
  same for both.
- **Keep them and hide them from the report.** The workspaces would still pile up in
  `.ai/workspace/tasks/` and in every count that reads it.

## Consequences

- The trash keeps such a workspace for `housekeeping.trash_ttl` days, then it is gone; the purge
  line in the log keeps its facts as for any purged task.
- A task worked on without `jig task start` and then closed loses its workspace notes after the
  trash TTL; its code is in git either way. That includes the task ADR-0030 closes in consolidation,
  before the commit, because its landing cannot be observed: when it recorded no branch at all, the
  next housekeeping run moves its workspace — its commit message included — to trash, possibly
  before the commit. A task recorded on the base branch (`branch: main`) is not affected. Whether
  that close should wait, or the purge, is left to a follow-up task.
- Amends the RULES.md rule that nothing is destroyed on `unknown`, ADR-0006's "only
  `consolidated` and merged tasks are purged", and adr-20261029-a-ship-hands-open-findings-to-one-triage-task,
  whose closed triage task was kept and neither purged nor archived.
