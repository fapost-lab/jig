---
id: adr-20261112-a-task-waiting-at-staging-is-parked-and-resuming-it-is-its-status
type: adr
status: accepted
date: 2026-11-12
domains:
  - task
paths:
  - scripts/lib/common.sh
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - scripts/lib/checkout.sh
summary: Why a task waiting at the staging branch is parked by a rule over git and the forge cache, why the owner's checkout lays only status, agent.git and park_resumed_at over it, and why a person taking it back for a fix is the one thing recorded.
reviewed_at: 2026-11-12
---
# A task waiting at the staging branch is parked by derivation, and only a person taking it back is recorded

## Context

In the staging flow (adr-20261109-the-team-names-its-git-flow-and-the-agent-writes-it-after-a-yes) a task ships into the staging branch through a pull
request, lands there, and waits — for a colleague's review, then for "prepare for prod" — often for
weeks, while the queue, concurrency limits and `jig status` fill up. The staging-branch specification decided that such a task has one state of its own, *parked*,
"derived from the branch and its pull requests alone, never written": a colleague, a CI runner and a
UI must read the same state, and task status and `agent.git` are local to one checkout. A parked
task holds no current-task slot, no place in `jig queue next` and no concurrency slot; `jig task
resume <id>` brings it back for a fix; autopilot stops there; `jig status` lists it on its own line.

The spec also says the owner's checkout knows what nobody else does: that the person resumed the
task for a fix, and whether they land its pull request themselves (`agent.git` below `merge`).
Before this, the checkout stayed on the task branch after a landing and `jig task current` kept
naming the task, its record kept the checkout occupied, and nothing told a run to stop there.

Two facts of the code shaped the answer. Every shipped task is `ready`: `task ship` asks for
verify's record (`status ready`), and a landing leaves the status alone. And a fix must be verified
again before it ships, so resuming has to take the task out of `ready` whatever else it does.

## Decision

- **One rule, in common.sh: `jig_parked_states <staging> <staging-land> <rows> <cache> [<states>]`.**
  For each `<id> <branch> <base> <pr-url> <promote-url> [<park-resumed-at>]` row it answers `review`, `signal` or
  nothing, from git (`jig_staging_states`) and the forge cache, in a fixed number of processes:
  1. a pull request from the branch into its base that is open or merged — the newest the cache
     has, or the one `promote_url` names, open until the cache has it — ends parking;
  2. the task's own work on origin's staging branch (`on`) is `signal`;
  3. an open pull request into the staging branch is `review`: the one `pr_url` names (open until
     the cache has it, and only under `staging_land: pr`), else the newest the cache has;
  4. anything else is not parked.
  A row whose `park_resumed_at` is set is not parked, whatever the rest says. The links and the
  record are the owner's; a caller without a workspace passes `-` and reads git and the cache
  alone. Why a task waits is written nowhere.
- **The owner's overlay, in task.sh (`_task_parked_read`):** only a `ready` task on the
  project's base is parked; `landing` is added to `review` when the flow lands by pull request and
  this person's `agent.git` is below `merge`. The answer is read once per listing.
- **Resuming is recorded, once.** `jig task resume <id>` of a parked task that is not paused moves
  it from `ready` to `active` and writes `park_resumed_at` (UTC, ISO) in the same write, checked
  against the revision like the end of a pause, and prints how to go on (fix, `jig verify`,
  `jig task ship`). `active` makes the fix pass verify again; `park_resumed_at` keeps the task out
  of parking through that verify (`ready` again) and up to the ship: the next `jig task ship` into
  the staging branch that is not a draft drops the key at every `agent.git` level — after the push
  at `push` and above, and before it hands the commit and the push to the person at `none` and
  `commit`, since the fix is shipped then by hand from what the ship told them. At `none` only once
  the completion gates pass (`_task_ship_refusal`), as every other level asks them before it ships:
  a fix with an open blocking finding or no receipt is not handed over, and keeps the key
  (amended 2026-11-12). The task is parked
  again as soon as git or the forge gives a reason. `jig task set` refuses the key: only resume
  writes it and only ship removes it. A paused task keeps ADR-0012: the resume ends the pause and it returns to `ready`, so a
  parked one says `still parked (<reason>)` and a second resume takes it back. Neither paused nor
  parked is refused `not-paused` (`not paused or parked`). `--json` adds `resume.parked`.
- **What it frees.** `jig task current` skips a parked task (asked only of a `ready` candidate on
  the staging flow, so the direct flow starts no new process); `jig_checkout_occupants` does not
  count its record, so another task starts in the checkout it was landed from (a dirty tree is
  still refused). checkout.sh does not decide parking and sources no command library: its
  callers that have task.sh, `task start` and `status`, pass the parked ids
  (`_task_parked_ids_here`, `_task_parked_ids`); `jig upgrade`, which has none, passes nothing and
  still counts a parked task's record, the stricter answer for a command that moves HEAD. `jig queue next` and the `autopilot.parallel` slot needed no change: the queue
  advises only `active` tasks, and a run's slot is held only until the knowledge decision, which
  comes before the first ship.
- **Autopilot stops there.** `jig task autopilot <id> start` and `stage` refuse a parked task with
  exit 3; `end`, `stop`, `report` and `handover` work as before. The skill ends the run at the
  landing or the wait for review; it never approves and never promotes.
- **Where it shows.** `jig task list` adds `parked=<reason>[,landing]`; `task list --json` adds
  `parked: {reason, hint} | null` on the staging flow only, and the actions table offers `resume`
  to a parked task. `jig status` names parked tasks on one `parked:` line instead of their task
  lines (the terminal form and the page show it apart too); a `signal` task makes no git-step or
  pull request item, and a `review, landing` one asks the reader to land it.

## Alternatives

- A `parked` key written by ship or land: it contradicts the spec and goes stale when the forge or
  CI (`staging_land: external`) lands the task.
- `ready → active` alone as the record of a resume, with no key (the design shown at the gate first):
  verify sets `ready` before the fix ships, so a fix answering a review read as parked (`review`)
  again between verify and `task ship`, and an autopilot run taking the fix refused its own next
  stage there. Found at the architecture review; the person chose the key instead (2026-11-12).
  The key was first rejected as a second source of truth beside `status`. It is accepted because it
  says only that a person took the task back to fix it — something no git ref or forge answer can
  say — while why the task waits, `review` or `signal`, is still derived from git and the forge on
  every read and never stored.
- `parked` as a value of `status`: breaks ADR-0005 and ADR-0012 and every reader of the status.
- A fetch or a forge call in `resume` or `task current`: reads in Jig never touch the network, and
  `task current` runs under nearly every command.
- The approval in the forge cache, so `landing` names only an approved pull request: GitHub would
  give it for free, GitLab would not; left for later.

## Consequences

- **The signal window.** `signal` is read from origin's staging branch as this checkout last
  fetched it. Under `staging_land: external`, between the push and the first fetch (`jig
  housekeeping`, `git fetch`) after CI merged the task, a shipped task has no pull request and no
  work on staging yet as far as this checkout knows: it is listed as an ordinary `ready` task and
  holds the current-task slot and the checkout until that fetch. Under `pr` there is no such
  window: the staging pull request keeps it parked (`review`) until the housekeeping run that hears
  of the merge, and that run fetches the staging branch too.
- A task resumed and then left without a fix stays out of parking until `jig task ship` runs for
  it; the record says when it was taken back. A person who pushes the fix with git alone, without
  that command, leaves the record, and runs `jig task ship` (at `none` it only hands over and
  drops it) to have the task parked again.
- A task shipped while `active` — a draft, or one filed before route evidence was required — is not
  parked in its owner's checkout; `jig task set <id> status ready` makes it so.
- `review` is as fresh as the last housekeeping run, except for the owner's own links.
- A CI runner has no forge cache and reads only `signal`; the readers here all run in the owner's
  workspace.
