---
id: adr-20261111-in-the-staging-flow-a-task-ships-into-the-staging-branch
type: adr
status: accepted
date: 2026-11-11
domains:
  - task
paths:
  - scripts/lib/task.sh
summary: Why jig task ship in the staging flow opens the pull request into git.staging_branch and none into the base, does not merge until landing is built, stops after the push for external landing, ships an epic task into its epic, and reads the flow from the base branch too.
reviewed_at: 2026-11-12
---
# In the staging flow a task ships into the staging branch, and `task ship` does not land it there yet

## Context

`jig task ship` opened a task's pull request into the task's recorded base
(adr-20260921-agent-git-rights-are-a-local-setting, ADR-0039) and, at `agent.git: merge`, merged it.
The staging-branch specification (adr-20261109-the-team-names-its-git-flow-and-the-agent-writes-it-after-a-yes
keeps its flow model) adds named git flows: in `git.flow: staging` a task is cut from the base
branch, goes to `git.staging_branch` through a reviewed pull request, and reaches the base branch
only on "prepare for prod". Its roadmap builds this in slices: "Ship a task to staging" (this
decision), then "Land a task on staging" (the approval check, the merge on the forge, the direct
merge when it conflicts) and "See a task's staging state". A ship built before those must neither
send the task into the base branch nor merge into staging past the review the flow exists to keep.

## Decision

- **The pull request goes into `git.staging_branch`, and none into the base branch**, for a task
  whose base is `git.base_branch` in a project on `git.flow: staging`. `task ship` says so
  (`task ship: git flow staging: the pull request goes into <staging>, not <base>`).
- **`merge` does not merge in the staging flow** until "Land a task on staging" is built: the ship
  stops at the open pull request (`not merged: landing a task on <staging> is not built yet; …`),
  the checkout stays on the task branch and the branch stays. Below `merge` it says the task is not
  on staging yet and the person lands it. *Superseded by the amendment below: landing is built.*
- **`git.staging_land: external` stops after the push** and opens no pull request: CI lands the
  task. Reading what CI landed is a later item. The task staging-land-external built it: the staging
  state reads what CI merged from git alone, with no pull request, and the ship files the triage task
  for open P2/P3 there, since no pull request will list them.
- **A task of an epic ships into its epic**, as before, with a line saying the staging flow does not
  apply to it: whether an epic's tasks pass through staging is an open question, held by the task
  `epic-in-staging-flow`.
- **The flow is read from the base branch too.** Before the commit, at every level, `git.flow` and
  `git.staging_branch` at the tip of `jig_base_ref <base>` are compared with the checkout's, read
  with the same parser (`_cfg_read_v`); a difference refuses and says to merge the base branch into
  the task branch first — unless the task made it itself (amendment of 2026-11-12, below). At `pr`
  and `merge` the base is fetched first (`jig_fetch_branches`; a failed fetch only warns and the
  refs this checkout has are used, as in `task start`); below `pr` the comparison reads the refs
  this checkout has (amendment of 2026-11-12, "the base is fetched only where a pull request is
  opened"). A base unknown here, or one with no config, leaves the checkout to
  decide. A flow `jig doctor` fails on (`jig_git_flow_problems`) refuses too, `--draft` included.
- **An open pull request from the task branch into another branch than staging refuses**, naming
  it, rather than being reported as the staging pull request. It is asked before the commit, so a
  refusal sends nothing (adr-20260925-a-ship-refuses-before-it-sends); a forge that cannot answer
  there lets the ship go on to the pull request step, where it fails as before. `jig_ship_pr` is
  unchanged and the direct flow asks nothing new of the forge.
- A version raise is not a release in the staging flow: that pull request does not reach the base
  branch (adr-20261026-a-task-that-raises-the-version-is-a-release); promotion will be.

## Alternatives

- **Merge into staging at `merge` now, on green CI.** Rejected: it skips the approval check and
  `git.staging_review` the next item builds, and the conflict fallback; the review the team holds
  to would be bypassed unseen.
- **Refuse to ship at all in the staging flow until landing exists.** Rejected: the pull request
  into staging is exactly what the team does by hand today, and opening it is safe.
- **Read the flow from the checkout only.** Rejected: a task branch cut before the team committed
  `git.flow: staging`, or one that dropped the key, would ship — and at `merge` merge — straight
  into the base branch.
- **Read the flow from the base branch only.** Rejected: a task branch that changes the flow itself
  (the one that turns it on) would be judged by a config it is about to replace; a disagreement is
  better named than silently resolved either way.
- **Send an epic's tasks through staging.** Rejected for now: left open until a real epic meets a
  staging branch (the task `epic-in-staging-flow`); today's behaviour changes nothing.

## Consequences

- A project on `direct` ships as before, with one fetch of its base added before the commit; the
  base-branch comparison finds no difference there and asks no forge.
- Until "See a task's staging state" lands, a staging pull request a person merges reads
  `wrong-base` in housekeeping (ADR-0039), since the task's recorded base is still the base branch.
  The task staging-state made that untrue: housekeeping now reads the task's staging state instead
  (ADR-0039 as amended 2026-11-11).
- Until "Land a task on staging" lands, a person merges every staging pull request, whatever
  `agent.git` says.
- A task branch behind its base on the flow must merge the base branch in before it ships.
- The existing-pull-request check in the staging flow costs one more forge query per ship.

> **Amendment (2026-11-11, prepare for prod).** "Promotion will be" a release: `jig task promote`
> says so when the task raises the version and leaves the merge to a person
> (adr-20261111-prepare-for-prod-opens-the-promotion-from-git-alone).

## Amendment (2026-11-11): landing is built

"Land a task on staging" is built
(adr-20261111-a-task-lands-on-staging-through-its-pull-request), so at `merge` `task ship` no longer
stops at the open pull request: right after opening it, it lands it as `jig task land` does — the
approval by `git.staging_review`, the merge on the forge when it merges cleanly, the direct merge when
it conflicts — and exits with that step's code (3 a person decides, 5 a conflict waits for the agent).
The checkout stays on the task branch and the branch stays, as before. Below `merge` and for a draft
nothing changes. One refusal is added before the commit, at every level: a task branch carrying
commits of the staging branch its base did not bring (`jig_branch_carries_staging`) is not shipped. The
consequence "until Land a task on staging lands, a person merges every staging pull request" no
longer holds at `merge`.

## Amendment (2026-11-12): the base is fetched only where a pull request is opened

Merging main brought "a commit or a push asks GitHub nothing about accounts"
(adr-20260925-a-ship-refuses-before-it-sends): the fetch of the base resolved the clone's GitHub
account at every level and warned at `commit` and `push` when it was ambiguous. Below `pr` the flow
decides nothing — no pull request is opened — so the base is fetched only at `pr` and `merge`; at the
lower levels the comparison reads the refs this checkout has. Under `git.staging_land: external` no
pull request is opened either, so the ship does not name the account of one (`jig_ship_account`).

## Amendment (2026-11-12): the task that changes the flow ships into the base

As first built, the comparison refused every task whose config differed from its base's, and so
refused the one task `jig-setup` §4 and adr-20261109-the-team-names-its-git-flow-and-the-agent-writes-it-after-a-yes
tell the agent to ship: the one that writes `git.flow: staging` (or turns the flow off, or renames
the staging branch). Merging the base in could not help: the branch exists to change the flow.

Now, when the checkout and the base tip disagree, the config at `merge-base(HEAD, <base>)` is read
too. When it is the base tip's, the base has not changed the flow since the branch was cut, so the
difference is the task's own change. Such a task ships into its base as on the direct flow, and says
so (`task ship: <id> changes the git flow; its pull request goes into <base>, as on the direct
flow`): turning the flow on, turning it off and renaming the staging branch alike. It opens no pull
request into a staging branch, lands on none, is judged by no clean-branch rule, and at `merge`
merges into the base as any direct-flow task does, after the same gates (green CI, findings,
receipt, a release's hold). Neither the flow it leaves nor the one it brings decides its way: the
change is the team's, reviewed in the pull request into the base. Only a base that changed the flow
after the branch was cut refuses, as before. `jig task promote` keeps the plain comparison: its
checkout is not the task's branch.

The rejected alternative "read the flow from the base branch only" stays rejected for a task that
does not touch the flow.

The cost of the staging flow's strict fetch is said here too: on that flow a ship fetches the
staging branch at every level, `commit` included, to judge the clean-branch rule, and refuses with
nothing committed when it cannot. Offline, a commit-level ship on the staging flow refuses where the
direct flow commits.
