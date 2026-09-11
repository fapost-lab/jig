---
id: adr-0029-task-worktrees-live-beside-the-repository
type: adr
status: accepted
date: 2026-09-11
domains:
  - task
  - housekeeping
paths:
  - scripts/lib/task.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/status.sh
summary: Why parallel agent sessions get a worktree per task beside the repository, borrow the workspace by link, and are cleaned up by git.
reviewed_at: 2026-09-11
---
# ADR-0029: A task can start in a worktree of its own, beside the repository, removed by git

## Context

Several agent sessions working in one checkout overwrite each other. On 2026-09-11 three
tasks in a row recorded a branch that belonged to another session, because a parallel
session moved HEAD between two commands, and one session's uncommitted scripts sat in the
tree while another ran `jig verify` against them. The dirty-tree refusal on `task start`
prevented the worst of it, and was overridden with `--force` every time.

Agents here do not commit, and review happens before the commit: the human reads the diff
and commits it. Agent-made commits reviewed as pull requests were considered and rejected.
A pull request coordinates people who are not in the same conversation, and here they are.
So a task worktree holds uncommitted work as its normal state, not as debris.

Worktrees need no install step here. Every framework symlink is relative and committed,
so each one resolves inside the worktree it is checked out in, and `.ai/workspace/` and
`.ai/runtime/` are gitignored, so a worktree starts empty — ADR-0008's model exactly.

## Decision

- **`jig task start <id> --worktree`** cuts the task's branch from the freshest base, as
  plain `task start` does, but checks it out in a new worktree instead of this checkout. It
  records `branch` and `base_commit`, prints the worktree's path, and stops. An agent
  session cannot leave its working directory mid-session, so opening a session there is
  the human's step (the stance of ADR-0024). It needs `git.branch_per_task: true`, because
  git will not check one branch out in two worktrees. A start that fails takes back what
  it made. `git worktree add -b` creates the branch before the directory, and a leftover
  branch would refuse every retry. The branch is deleted with `update-ref -d <ref> <commit>`,
  which only succeeds while it still points at the commit it was cut at.
- **`task pause --stash` refuses when the task's branch is checked out elsewhere.** It
  stashes the checkout it runs in, and for a task in its own worktree that is not the
  task's work.
- **The dirty-tree refusal names the worktree as the other road** — pause the owner with
  `--stash`, or start this task in its own worktree. The worktree is created on request,
  not automatically: the human is needed at that moment anyway, to open the session.
- **The workspace does not move.** The worktree gets one link, `.ai/workspace/tasks/<id>`,
  to the workspace in the checkout where the task was filed. That checkout keeps seeing
  every task, and the workspace's lifecycle stays in one place. `task artifacts` accepts
  exactly this link — to the same task's workspace in another worktree of this repository —
  and still refuses any other.
- **Where a task's branch is checked out is read from git** (`git worktree list`), never
  from another checkout's `.ai/`. `task list` and `jig status` show a task started in a
  worktree with `worktree=<path> uncommitted=<n>`: the queue waiting for review.
- **Worktrees live beside the repository**: `git.worktree_root`, by default
  `../<project>.worktrees`, relative to the project root unless absolute.
- **Housekeeping in the owning checkout removes a task's worktree when it purges the
  task's workspace**, and only then, so no new policy row exists. The worktree must be
  listed by git with the task's branch, lie under `git.worktree_root`, hold nothing under
  `.ai/workspace/tasks/` but links, and have no uncommitted changes. It is removed by
  `git worktree remove` without `--force`. When it has to stay, the workspace stays too,
  flagged `worktree-kept`, and `jig status` counts it. The branch is never deleted.

## Alternatives

- **One shared checkout, coordinated by pausing.** Rejected: the failure is not a missing
  signal but HEAD moving under a running session, which no amount of state prevents.
- **Agents commit to their own branch; the human reviews a pull request.** Rejected by the
  human for this project: review before the commit is strictly shorter when author and
  reviewer share a conversation.
- **Create the worktree automatically on a dirty tree.** Rejected: it saves no step, since
  the human has to open the session, and a dirty tree the agent caused itself would leave
  a stray worktree behind.
- **Worktrees inside the repository (`.ai/worktrees/`).** Cheaper for an agent's sandbox,
  and covered by the existing deletion invariant. Rejected because the cost lands on every
  adopting project: a nested copy of the whole tree is found twice by test runners, type
  checkers and IDE indexers, and jig can prune its own profiles but not their
  configuration. A worktree inside this repository has also reached the index once
  (`858b156`, removed in `f3ea409`).
- **Move the workspace into the worktree.** Rejected: the filing checkout loses the task
  from view, and an overview then needs the cross-worktree lookup ADR-0008 rules out.
  Copying it gives two `state` files that diverge from the first write.
- **Only report a finished worktree and print the command to remove it.** Rejected: that
  is cleanup by manual discipline (RULES.md, Scope invariants).
- **Remove with `--force`.** Rejected: it discards uncommitted work, which in a task
  worktree is the work waiting for review.

## Consequences

- A deletion outside `.ai/` now exists, and RULES.md names it: a task worktree, removed
  only by git, only under the three checks above. Measured before deciding: `git worktree
  remove` without `--force` removes the worktree and the link and leaves the owner's
  workspace intact. It refuses on tracked changes and untracked files, but it deletes
  *ignored* files silently. That is why a worktree holding a real workspace is kept.
- Creating a worktree writes outside the project directory, so an agent's sandbox may ask
  for permission once per worktree. Paths in reports are absolute.
- ADR-0008 gains a named exception: a worktree borrows exactly one workspace, by a link it
  was given at creation. Ownership — housekeeping, trash — stays with the filing checkout.
  Housekeeping run inside the worktree does not see the link at all, because it finds
  workspaces with `find`, which does not follow links.
- The link is absolute, like git's own worktree paths. Moving the repository breaks both
  alike, and `git worktree repair` fixes git's side of it.
- `git.worktree_root` is read on every run, not recorded per task. Changing it strands every
  worktree made under the old root: housekeeping keeps them, flagged `worktree-kept` with
  reason `outside-worktree-root` in the log, until they are moved or removed by hand.

> **Amendment (2026-09-11).** "An agent session cannot leave its working directory
> mid-session" holds for some runtimes, not all: Claude Code can switch a running session
> into an existing worktree. The decision stands, because it rests on the narrower fact
> that the script cannot move the session that called it. What changes is the guidance
> built on the premise: `jig-task` tells an agent that can switch to do so, and to ask the
> user for a new session only when it cannot. The rejection of an automatic worktree still
> holds on its second ground, the stray worktree a self-inflicted dirty tree would leave.
> A switched session may be fenced to the worktree: Claude Code's editing tools refuse the
> workspace link, because it resolves into the filing checkout, so task artifacts are
> written there with plain shell commands.
