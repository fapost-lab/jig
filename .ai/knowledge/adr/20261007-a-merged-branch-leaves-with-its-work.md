---
id: adr-20261007-a-merged-branch-leaves-with-its-work
type: adr
status: accepted
date: 2026-10-07
domains:
  - housekeeping
  - task
  - install
paths:
  - scripts/lib/common.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/upgrade.sh
  - scripts/lib/task.sh
  - scripts/lib/spec.sh
summary: Why Jig deletes a branch it made once its work has landed, with git branch -d first and a lease push on origin second, and never a branch that is not its own or still in use.
---
# A branch Jig made leaves once its work has landed, and git does the deleting

## Context

An upgrade at `agent.git: merge` cut `jig/upgrade-<v>`, committed, opened a pull request and merged
it — and then left the checkout on that branch, the branch in the clone and, unless the forge was
set to delete head branches, on origin too. `jig task ship` and `jig spec ship`'s final merge did
the same, and housekeeping removed a closed task's worktree (`worktree-leaves-on-landing`) but never
its branch. On the owner's clone of this repository that came to 74 local branches and 110
`origin/` refs. Deleting a branch is destructive: a branch can hold the only copy of a commit.

## Decision

A branch is deleted only when it is Jig's, its work has landed, and nothing here still needs it.
On by default; `git.delete_merged_branches: false` (a local key) keeps every branch.

- **Jig's** (`jig_branch_is_jigs`, common.sh): `jig/upgrade-*`, `finish/<id>`, or the name
  `git.branch_template` gives a valid task id, when the template has literal text before `{id}`.
  Never the base branch, `epic/*` or `spec/*`, and never a branch checked out in any worktree.
- **Git deletes, never the script.** Locally `git branch -d`, never `-D` (amended 2026-10-10:
  past a refusal, a ref update guarded by the merged head — see the amendment below). On origin
  `git push --force-with-lease=refs/heads/<b>:<merged head> origin :refs/heads/<b>`, so a branch
  somebody pushed to after the merge stays.
- **Local first, then origin.** `git branch -d` checks a branch against its upstream when it has
  one. While `origin/<b>` still sits at the pushed commit, a squash-merged branch passes, and a
  branch with a commit origin never saw is refused — and then origin's copy is kept too. Measured
  on git 2.48.1: `-d` deletes a squash-merged branch "merged to refs/remotes/origin/t, but not yet
  merged to HEAD". For the same reason housekeeping's fetch says `--no-prune`, whatever the
  person's `fetch.prune` is; a stale `origin/` ref is dropped (`git branch -d -r`) one at a time,
  only after its local branch is gone and only when `ls-remote` says origin no longer has it.
- **Landed** means a merged pull request (the forge) or ancestry into the default branch. A squash
  shows only through the forge. Origin is touched only with a merged pull request whose head is
  where origin's branch still is; ancestry alone deletes locally at most. A branch with an open
  pull request is in use, whatever an older merged one says — as its head, or as the base another
  pull request is stacked on.
- **Origin is shared.** Right after its own merge Jig already holds the right to push (the
  merge needs `agent.git: merge`). Housekeeping runs for every contributor at session start, so
  it writes to origin only for a person whose `agent.git` or `autopilot.git` is `push` or above — the local-only
  keys that grant an agent the right to put a branch there in the first place
  (adr-20260921-agent-git-rights-are-a-local-setting). Below that it deletes local branches only.
  It may then delete a colleague's merged Jig branch on origin: one whose pull request the forge
  reports merged, still at the merged head, with no open pull request on it — exactly what the
  forge's own "delete head branches" setting would have done.
- **Right after a merge Jig made** (`jig_ship_leave`, called by `_upgrade_finish`, `task_ship`,
  `spec_ship_final`): in the clone's main checkout, switch to the base, fast-forward it to
  `origin/<base>`, delete the branch at the merged commit. A linked worktree is never moved —
  housekeeping finds a task's worktree by the branch git lists in it — so a task shipped from its
  own worktree keeps its branch, local and remote, for the next step.
- **Housekeeping** (`_hk_branch_sweep`), after its task loop and only in the main checkout: a
  candidate is any local branch or `origin/` ref that is Jig's, not in use by a workspace the run
  leaves in place, and checked out nowhere. The branch of a workspace the run purged becomes a
  candidate in the same run: it leaves with its work, as the worktree does, and not before —
  while a workspace stays, ancestry and an epic's final review still read its branch.

## Alternatives

- **`gh pr merge --delete-branch`.** Deletes the local branch with `git branch -D` and switches
  the checkout itself; both are what this decision forbids. `glab mr merge --remove-source-branch`
  is remote-only. One git path serves both forges and is testable without one.
- **`git update-ref -d` guarded by the merged head.** Would take a squash-merged branch whose
  upstream is gone, but it is `-D` with a precondition; refused in favour of git's own check.
  Such a branch is reported kept instead. (Reversed 2026-10-10 — see the amendment below.)
- **Delete at `task ship` from a worktree.** The worktree would have to be moved off the branch
  (and housekeeping would then never find it) or the remote deleted alone (and a squash-merged
  local branch would then never pass `-d`).
- **`git fetch --prune` in housekeeping.** Drops the upstream refs `-d` relies on before the
  sweep can use them.

## Consequences

- After a merged upgrade the person is on the base branch, with no `jig/upgrade-<v>` anywhere.
- A task shipped in the main checkout loses its branch before it is consolidated; the forge's
  merged pull request is what housekeeping and `status consolidated` read then, not ancestry.
  Without a forge Jig does not merge, so it does not delete either.
- A squash-merged branch whose upstream ref is already gone is kept and reported:
  `kept branch <b>: git does not see all of its commits merged`. The person deletes it.
  (Superseded 2026-10-10 for a tip inside the merged head — see the amendment below.)
- RULES.md's deletion paragraph names this site; the change that adds or re-guards a branch
  deletion re-reads it.

> **Amendment (2026-10-10).** The rejected `git update-ref -d` guarded by the merged head is now
> the fallback past a refusal of `-d`: a branch whose upstream someone else pruned goes when its tip
> is in the head of the pull request the forge reported merged, and the consequence "the person
> deletes it" no longer holds for it. (adr-20261010-a-gone-upstream-defers-to-the-merged-head)
