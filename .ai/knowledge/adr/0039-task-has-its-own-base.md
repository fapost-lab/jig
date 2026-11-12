---
id: adr-0039-task-has-its-own-base
type: adr
status: accepted
date: 2026-09-16
domains:
  - task
  - housekeeping
  - context
paths:
  - scripts/lib/task.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/common.sh
  - schemas/state.md
  - scripts/lib/verify.sh
summary: Why every task records its own base branch, why bases resolve origin first, and why work merged elsewhere is flagged wrong-base rather than merged.
reviewed_at: 2026-11-11
---
# ADR-0039: A task records the branch it is cut from and has to land on

## Context

Every judgement Jig makes about a task against a base read one project setting,
`git.base_branch`, in eight places: where `task start` cuts the branch, the `overlap:` report of
`task resume`, the files `jig context` and `jig knowledge paths` count as touched, and four places
in housekeeping — the ancestry tiers, the "branch is the base" rule (ADR-0025), the reason printed
for `unknown`, and the base reflog that tells a branch's own work from the base's (ADR-0032).

That holds while every task is cut from `main` and lands in `main`. Epic branches (ADR-0040) and,
later, maintenance lines break it: a phase's task is cut from `epic/<spec-id>` and lands there.
Judged against `main`, such a task never lands, every commit the epic gained reads as the branch's
own work, and a phase merged into `main` by mistake reads as done. The specification
`epic-branches` (removed when finished; in git history) found three more ways the single setting fails: a base resolved by bare
name picks a stale or missing local ref, a reflog cache kept for `main` alone, and a forge tier that
never read a pull request's base.

## Decision

- **`state` gains a script-owned `base_branch`**, written by `jig task start` in every path (a new
  branch, `--worktree`, `git.branch_per_task: false`) beside `branch` and `base_commit`, after
  `git check-ref-format --branch` accepts the name. `jig task set` refuses it. A task without the
  field — not started, or started before it existed — is judged against `git.base_branch`.
- **One answer, in `common.sh`.** `jig_task_base <id>` returns the field or the setting;
  `jig_base_ref <name>` resolves a base as `refs/remotes/origin/<name>`, else `refs/heads/<name>`,
  else nothing. Landed means landed on the remote, so origin comes first — for `main` too. Every
  consumer above takes the task's base through them; `jig_git_touched_files --base-branch <name>`
  is the form `context` and `knowledge paths` use.
- **Housekeeping reads the reflog of every distinct base** once per run, lines tagged with their
  base; `_hk_own_work` reads only the lines of the task's base.
- **Work that landed outside its base is flagged `wrong-base`, not reported merged.** The forge
  listing carries the base (`headRefName,baseRefName,state`; GitLab `target_branch`). A pull request
  into the task's base decides as before; with none, a merged one into another branch gives remote
  state `unknown` and the flag — which also catches a phase stacked on another phase's branch.
  Without a forge, a task whose base is not `git.base_branch`, which recorded a fork point and whose
  base still resolves, is flagged when its branch is merged into `git.base_branch`. The workspace is
  kept, housekeeping exits 3, the report files the task under "needs you", and `jig status` prints
  `wrong base: N task(s)`.
- **`jig task list` and `jig status` show `base=<name>`** only where it differs from the setting.

## Alternatives

- **A `--base` flag on `task start`.** Rejected: easy to forget, and a forgotten flag sends a phase
  to `main` silently. The base is decided by the spec the task links to (ADR-0040).
- **Infer the base from history** (the nearest branch containing `base_commit`). Rejected: a commit
  on both `main` and an epic is ambiguous, and where the work must land is not recorded in git.
- **A fifth remote state `wrong-base`.** Rejected: it changes ADR-0025's vocabulary and the log that
  `jig status` and `jig measure` read. A flag beside `unknown` keeps the policy table as it is.
- **The base as an environment variable to `jig_git_touched_files`.** Rejected: an implicit
  parameter, and bash 3.2 treats a temporary assignment before a function call inconsistently.
- **Local ref first.** Rejected: a teammate who never fetched the epic gets an empty answer, its
  author a stale one.
- **No ancestry check for `wrong-base`.** Rejected: without a forge, a phase merged into `main` would
  stay `unknown` for ever with nothing said.

## Consequences

- Nothing changes for a task whose base is `git.base_branch`, except that housekeeping now resolves
  `main` origin first: a merge is seen as soon as it is fetched, and a local commit nobody pushed no
  longer counts as landed.
- `jig knowledge paths --task <id>` counts touched files against that task's base.
- The reverse mistake — a task of `main` whose pull request went into an epic — is visible only with
  a forge.
- The forge stub in `tests/housekeeping.t.sh` prints three tab-separated fields per pull request.

> **Amendment (2026-11-11, the staging flow).** In a project on `git.flow: staging` a task keeps the
> base branch as its recorded base but ships into `git.staging_branch`; until the staging state is
> read, a staging pull request a person merges reads `wrong-base`
> (adr-20261111-in-the-staging-flow-a-task-ships-into-the-staging-branch). The task staging-state
> made that untrue: a merged staging pull request no longer reads `wrong-base` (the amendment below).

## Amendment (2026-11-11): the staging flow

In a project on the staging flow (`git.flow: staging`, adr-20261109-the-team-names-its-git-flow-and-the-agent-writes-it-after-a-yes),
a pull request merged into `git.staging_branch` is the flow's own step, not work landed outside the
task's base: `_hk_forge_state` passes over it, so it raises no `wrong-base`, and the task's remote
state falls through to ancestry as before (`unknown` until it reaches its base). What the run reports
instead is the task's staging state, `on` or `behind` (`jig_staging_states`, common.sh): derived
from git by the branch's name on every read and stored nowhere (ADR-0005). Own work is what the
branch reaches and its base does not; a merge whose other parents are all in the base or in
`origin/<staging>` brings those in and is not own work, and staging reached only through such a
parent does not count. A task on staging is kept from the stale archive (`STALE_CANDIDATE`), the
protection `wrong-base` used to give it. When a task has no pull request into its base, its newest pull request into the staging branch stands in for it: open or closed, it is the task's remote state, as one into the base would be; merged, it falls through as above. On any other flow nothing here changes.

> **Amendment (2026-11-11): `verify` is a consumer too.** Under `verify.full_run: ci` a flag-less
> `jig verify` measures its changed scope from the current task's `jig_task_base` (ADR-0041,
> amendment of the same day; issue #458): measured from `git.base_branch`, a task cut from an epic
> re-ran the whole epic's diff.
