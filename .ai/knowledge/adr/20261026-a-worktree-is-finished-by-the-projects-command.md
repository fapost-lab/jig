---
id: adr-20261026-a-worktree-is-finished-by-the-projects-command
type: adr
status: accepted
date: 2026-10-26
domains:
  - task
  - config
paths:
  - scripts/lib/bootstrap.sh
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - scripts/lib/config.sh
summary: Why a project may name worktree.setup, run on the host after share and carry with JIG_SHARED and JIG_DANGLING, bounded and never fatal, its outcome kept on the task, and why a directory can be shared for one task with --share.
---
# ADR: A task worktree is finished by the project's own command, and a directory can be shared for one task

## Context

A task worktree gets the state git does not track by a copy from the checkout beside it
(adr-20260924-a-worktree-carries-what-git-does-not), and a directory of repositories under edit by
a mirror of links (adr-20261002-a-worktree-shares-a-directory-by-mirroring-it). Both assumed that
what the owning checkout has is what the task should run on.

fapost-core showed where that breaks. Its main checkout runs a local development setup:
`composer dev:link` turns `vendor/fapost/*` into links into `packages/`, and an overlay adds
packages of its own. The copied `vendor/` kept those links. Without `worktree.share: [packages]`
they led nowhere; with it, every task ran against the current branches of the local package
checkouts and the overlay's packages instead of `composer.lock`, and Core's own test suite, written
for bare Core, failed under the pre-commit hook. The project could not fix this inside Jig: there
was no step after the carry, so the only remedy was an instruction to every agent. And Jig itself
had pushed it the wrong way — `jig status` and `task start --worktree` named `worktree.share` as
the fix, a declaration that holds for every task, while only the tasks that edit the packages need
them.

## Decision

**A project may name a command, `worktree.setup`, that Jig runs in a new task worktree after the
share and the carry**, from `jig task start --worktree` and every `jig task bootstrap`. Jig still
installs nothing of its own: the command is the project's, read from its `.ai/config.yaml`, as
`jig verify` already runs the project's own tools. What the earlier decision ruled out — Jig
deciding to install — stays ruled out.

- **The order is the contract: share, then carry, then setup.** The command finds the mirrors and
  everything carried, a personal file such as `.make.local` among them, which is how a project
  reaches its container without Jig knowing about it.
- **It runs on this machine, never through `run.exec`.** `run.exec` is a person's setting; wrapping
  the project's line in it would make one line of a shared file mean something else for every
  person, and resolving it at start would bring its refusals where nobody expects them. A project
  that lives in a container reaches it from its own command.
- **It is told what it needs**: `JIG_TASK_ID`, `JIG_OWNER_CHECKOUT`, `JIG_SHARED` (the directories
  shared into this worktree, project's and task's) and `JIG_DANGLING` (links inside carried paths
  that lead nowhere in this worktree). `JIG_SHARED` is how one command serves both kinds of task:
  the lock's versions when nothing is shared, the local setup when the packages are. `JIG_DANGLING`
  exists because composer reads a dangling path-repository link as installed and leaves it so; Jig
  names those links and does not remove them, because what a link is for is the project's to know.
- **Stdin is empty, both outputs go to stderr**: stdout of `task start` is the worktree's path,
  and agents read it.
- **Bounded by `worktree.setup_timeout`** (`10m`, `0` for none). The command runs in a process
  group of its own (`set -m`); at the limit the group gets SIGTERM and, five seconds later,
  SIGKILL, so `make`, the `docker exec` under it and what that started on this machine all stop.
  A process a container started inside itself may not hear it; that boundary is the container's.
  The timer is rolled by hand, as `jig_ls_remote_tags` is (ADR-0002).
- **Never fatal, and never taken back.** The task is started either way. The outcome is kept as the
  task's `setup` — `ok`, `failed (exit n)`, `timed out (d)` — and a failure is shown by `jig status`
  and `jig task route` until a bootstrap succeeds, because in a phase run the coordinator starts the
  task and a warning on stderr is easily lost. Files the command leaves that git can see are named,
  since they strand the worktree, but not removed: Jig does not know what they are.
- **It runs again on every `jig task bootstrap`**, so it must be safe to repeat, and in a phase run
  it may run in several worktrees at once. Jig does not serialise it.

**A directory can be shared for one task**: `jig task start <id> --worktree --share <dir>`, and
`jig task bootstrap <id> --share <dir>` for a task already running. The task keeps the list as its
`share`, which only grows — taking links out of a running worktree is a deletion nothing needs —
and every bootstrap mirrors the project's `worktree.share` and the task's `share` together, a
repeat between them silently once. Paths are checked as `worktree.share` paths are.

**The hints follow.** A directory of repositories nobody shares is named at a worktree's start as
an information line with the per-task command, no longer as a warning to edit the project's file:
running on the lock's versions is the right default for a task that does not edit the packages.
`jig status` names both roads, and says nothing when the project has a `worktree.setup`, which
means it took preparing worktrees on itself.

## Alternatives rejected

- **Only documentation.** An instruction to every agent is exactly what the carry was introduced to
  replace; agents skip steps nothing enforces.
- **Jig resets `vendor/` to the lock itself.** That is installing, needs a toolchain the host may
  not have (devilbox), and knows nothing of overlays.
- **Run the command through `run.exec`.** Rejected above.
- **`jig task new --share`**, so a phase run's coordinator could share at start. Deferred: a task
  that finds it needs the packages runs `jig task bootstrap <id> --share`, and no phase run has
  needed more yet.

## Consequences

- Projects whose main checkout is a development setup can give tasks the lock's versions by
  default and the local packages on request, with one line of configuration and a script of
  their own.
- Jig now runs a project command when a worktree is made, not only when checks run. Its reach is
  the project's own `.ai/config.yaml`, the same trust `jig verify` already extends.
- Reverting restores the code, not the decision: projects that wrote `worktree.setup` would get a
  doctor warning about an unknown key and worktrees no longer finished.
- adr-20260924-a-worktree-carries-what-git-does-not and
  adr-20261002-a-worktree-shares-a-directory-by-mirroring-it are amended by this decision.
