---
id: adr-0008-workspace-per-checkout-atomic-state
type: adr
status: accepted
date: 2026-09-08
domains: [workspace, lifecycle]
paths:
  - scripts/lib/task.sh
  - scripts/lib/context.sh
  - schemas/state.md
  - scripts/lib/config.sh
summary: Why a workspace belongs to its checkout and state is written atomically without locks.
reviewed_at: 2026-09-16
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

> **Amendment (2026-09-16).** A second named exception, and the only one that is looked up
> rather than given: every checkout reads `.ai/config.local.yaml` from the main checkout of
> its clone, found through git's own `.git` and `commondir` files (ADR-0038). It is a setting
> of the clone, not task data, and it is only read — nothing is written, moved or owned
> through that path. Workspaces stay exactly as above: no lookup, no shared location.

> **Amendment (2026-09-25).** A third named exception, and the first that **writes**: state
> that belongs to the clone rather than to any checkout lives in the main checkout's
> gitignored `.ai/runtime/`, reached the same way the second exception reads
> `.ai/config.local.yaml` — through git's own `.git` and `commondir` files
> (`jig_config_clone_root`). Two things use it: the live status page, which has been written
> there since 2026-09-22 (adr-20260922-the-status-page-stays-current-without-a-server), and
> `jig verify`'s run record
> (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass). The test that admits
> something here is not "is it convenient" but **whose it is**: one page per clone and one
> test run per clone are facts about the clone, because the reader and the CPU are one for
> all its worktrees, whereas a workspace is a fact about the checkout that filed it.
> Everything such a path holds is gitignored, derived, and rebuilt if it is lost; nothing
> here is task data, and workspaces stay exactly as above — no lookup, no shared location.
>
> This is narrower than it looks, and the case that shows the line is
> adr-20260924-a-checkout-records-what-is-happening-in-it, which considered a shared
> per-clone directory for *its* record and rejected it. That record answers "what is
> happening in **this checkout**", so a shared home would have made it answer the wrong
> question. The rejection is about the record's subject, not about the location, and it
> stands.
