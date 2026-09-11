---
id: adr-0008-workspace-per-checkout-atomic-state
type: adr
status: accepted
date: 2026-09-08
domains: [workspace, lifecycle]
paths:
  - "scripts/lib/task.sh"
  - "scripts/lib/context.sh"
  - "schemas/state.md"
summary: Why a workspace belongs to its checkout and state is written atomically without locks.
reviewed_at: 2026-09-11
---
# ADR-0008: Task workspaces are per checkout; state writes are atomic, last-write-wins

## Context

Spec §33 left two questions for Phase 2. Git worktrees give one repository several
checkouts, and `.ai/workspace/` lives inside each; a task started in one worktree is
invisible from another. Separately, two agent sessions may run on the same task and
write the same `state` file.

## Decision

- **A workspace belongs to the checkout it was created in.** No cross-worktree lookup,
  no shared location under the common git dir. `jig task current` resolves the task by
  matching the checkout's current branch against `branch:` in local state files.
  Housekeeping runs per checkout and only sees that checkout's workspaces.
- **`state` is written atomically** (`state.tmp.$$` then `mv`) with **last-write-wins**
  semantics. No lock file. Every write goes through `jig task set`, which rewrites the
  whole file from the current on-disk content plus the one changed key, so concurrent
  writers can lose a field update but never corrupt the file.
- Script-owned keys (`task_id`, `branch`, `created_at`, `updated_at`) are refused by
  `task set`.

## Alternatives

- **Workspace under `git rev-parse --git-common-dir`** — rejected: moves task data out
  of the `.ai/` tree, breaks the "everything in the project" model and the gitignore
  rule, and worktrees usually map to distinct branches and tasks anyway.
- **Lock file for state** — rejected for now: adds a stale-lock failure mode for a race
  that produces at worst a lost single-field update; revisit if it shows up in practice.

## Consequences

- A worktree removed with `git worktree remove` takes its workspaces with it; nothing
  to clean.
- Two sessions on one task in one checkout must coordinate through the branch and
  the task artifacts, not through state locking.

> **Amendment (2026-09-11).** One named exception to "no cross-worktree lookup": a worktree
> made by `jig task start --worktree` borrows exactly one workspace, through a link to the
> task's workspace in the checkout where it was filed (ADR-0029). The link is given at
> creation, not looked up, and the workspace still belongs to that checkout — housekeeping
> and trash act there only. Where a task's branch is checked out is read from
> `git worktree list`, which reads git's data, not another checkout's `.ai/`. The
> consequence above about `git worktree remove` taking the workspaces with it still holds
> for a workspace filed inside a worktree. That is why housekeeping never removes a
> worktree that holds one.
