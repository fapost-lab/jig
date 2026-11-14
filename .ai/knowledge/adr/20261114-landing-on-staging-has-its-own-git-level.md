---
id: adr-20261114-landing-on-staging-has-its-own-git-level
type: adr
status: accepted
date: 2026-11-14
domains:
  - config
  - task
  - skills
paths:
  - scripts/lib/task.sh
  - scripts/lib/config.sh
  - "skills/jig-setup/**"
  - scripts/lib/prdo.sh
  - scripts/lib/status.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/doctor.sh
summary: Why a task whose pull request goes into the staging branch has its own personal git level, agent.git_staging, resolved in the one ship resolver, and why autopilot.git, when set, still answers for a run.
---
# A task landing on the staging branch has its own git level, agent.git_staging

## Context

On the staging flow one level, `agent.git`, decided both the landing of a task on the staging
branch and everything that goes into the main branch: the Jig upgrade pull request, `jig spec ship`,
epics, releases, promotion. A person who wants the agent to land its tasks on staging by itself had
to set `agent.git: merge`, and then upgrade and specification pull requests merged into the main
branch on green CI without them. The agent's level exists to limit the agent
(adr-20260921-agent-git-rights-are-a-local-setting); one level for two blast radii could not.
The case that triggered this also sits at `agent.git: none`, where `jig task ship` exits before it
reaches the landing step.

## Decision

A new personal key `agent.git_staging` (`none|commit|push|pr|merge`), local-only like `agent.git`
and unset by default. It is the git level of a task whose pull request goes into the staging
branch: the whole `jig task ship` (commit, push, pull request and, at `merge`, the landing), the
agent's `jig task land` and `request-review` of such a task. Unset, `agent.git` answers there, so
nobody who does not touch the key sees a change.

`_task_ship_git_v` stays the one resolver. In order: a run of autopilot that is `on` (or an
unattended `stopped` one) with `autopilot.git` set answers `autopilot.git`, the run's explicit
level; else a task that ships into staging (`git.flow: staging`, a sound staging branch, the task
cut from `git.base_branch`: local reads only) with `agent.git_staging` set answers that; else
`agent.git`. An invalid `agent.git_staging` is refused with its name and never falls back to
`agent.git`, like `autopilot.git`. Everything into the main branch keeps `agent.git`: upgrade,
`spec ship`, epics and their tasks, releases, promotion, `jig writes ship`, `merge-pr`. `--by human`
reads no level at all, and still does not.

`jig task ship` reads the level before it knows where the pull request goes. When the flow then
turns out to be the task's own (`_TASK_SHIP_OWN_FLOW`: the task changes the git flow, so it ships
into its base), and the level came from `agent.git_staging`, it is read again from `agent.git`
before anything is committed. Refusal texts name the key that answered
(`task land: landing <id> on <staging> needs <key>: merge ...`); the prefix patterns that choose
exit codes accept both keys. The ship line `git level <level> (<key>)`, `jig task route` and
`autopilot start` (a second line `autopilot git on <staging>: ...`), the parked `landing` hint,
the `git-step` attention and housekeeping's right to delete merged branches on origin read the new
key where they read the level of staging work. `jig-setup` asks about it only on the staging flow.

## Alternatives

- **A key that governs only the landing step.** Rejected: at `agent.git: none`, the motivating
  case, the ship exits before the landing, so the key would change nothing.
- **A ceiling `agent.git_base` for everything into the main branch, with `agent.git` for staging.**
  Rejected: it changes what `agent.git` means for everyone already on the staging flow, and is not
  zero-config.
- **The lower of `autopilot.git` and `agent.git_staging` inside a run.** Rejected: two keys for one
  decision in one run read worse; `autopilot.git` is already defined as the run's level, so when it
  is set it answers for the whole run.
- **`autopilot.git_staging`.** Rejected: nobody asked for it, and a key nobody needs is a key to
  explain.
- **A project-level key in `.ai/config.yaml`.** Rejected by adr-20260921: git rights do not leak
  into the project.

## Consequences

- A person can let the agent land on staging (`agent.git: pr`, `agent.git_staging: merge`) while
  upgrades, specifications and releases still stop at a pull request.
- `agent.git_staging` limits only what Jig does for the agent. An agent that runs `gh pr merge`
  itself is held by the "Jig first" rules and by the forge's branch protection, as before.
- One more place to look when a ship stops at a level: the line names the key.
- A ship at `agent.git_staging: none` for a task that changes the flow itself refuses before the
  flow is known, although `agent.git` might have allowed it; the person commits, as at `none`.
- The ship records where its pull request went (`pr_into` in the task's state). From then on
  the resolver reads it, so `jig task land` and `request-review` of a task whose pull request went
  into the base answer to `agent.git`, and `land_task` refuses (`wrong-flow`) to land a pull
  request that does not go into the staging branch, whoever asks.
- Before a task's first ship, the actions table may offer `ship` for a task that changes the flow
  at `agent.git: none` with `agent.git_staging` at `commit` or above, and the command then exits 3:
  whether a task changes the flow is the command's to find out, like the other flow refusals.
- Rolling the code back returns every staging task to `agent.git`; nothing is migrated.
