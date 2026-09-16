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
summary: Why every task records its own base branch, why bases resolve origin first, and why work merged elsewhere is flagged wrong-base rather than merged.
reviewed_at: 2026-09-16
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
`.ai/specs/epic-branches/` found three more ways the single setting fails: a base resolved by bare
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
