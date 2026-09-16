---
id: adr-0032-ancestry-needs-the-branchs-own-work
type: adr
status: accepted
date: 2026-09-13
domains:
  - housekeeping
  - task
paths:
  - scripts/lib/housekeeping.sh
summary: Why git ancestry answers merged only for a branch with a reflog position of its own, and why a fast-forward onto the base is unknown.
reviewed_at: 2026-09-16
---
# ADR-0032: Ancestry answers `merged` only for a branch with work of its own, proven by the reflog

## Context

ADR-0026 made housekeeping ask "did this branch contribute anything" before "did it land":
with no commits in `base_commit..tip`, ancestry answers `unknown`. That check assumed every
commit after the fork point is the task's.

It is not. On 2026-09-13 a session ran `git merge origin/main` on `task/approve-the-document`
to bring the branch up to date. The branch had no commits of its own; its work sat
uncommitted in the worktree. The merge fast-forwarded it onto `main`, so `base_commit..tip`
held three pull requests merged by other tasks, and the tip was an ancestor of the base.
Ancestry answered `merged` and housekeeping printed "merged but not consolidated, run
jig-consolidate" — an invitation to close, and so to purge, a task that had not landed.
Only ADR-0029's uncommitted-changes check stood between that flag and the workspace; a task
worked on in the main checkout had no such check.

Refs cannot tell this case from a real fast-forward merge. In both, the tip is an ancestor
of the base and commits exist since the fork; SHAs, first-parent chains and patch-ids see the
same snapshot. The difference is only in time: did the base contain the commit before the
branch moved onto it, or after. Git records that time in the reflog, which is written by
default in every non-bare repository, for local branches and remote-tracking refs alike, and
which worktrees share.

## Decision

- **For a task with a valid `base_commit`, ancestry answers `merged` only when the branch
  has a position of its own.** A position is a reflog entry of the ref housekeeping resolved
  for the branch — the local branch, else `origin/<branch>`. It is the branch's own when:
  - it is neither `base_commit` nor behind it;
  - it is still contained in the tip, because a commit reset away landed nothing;
  - neither `refs/heads/<base>` nor `refs/remotes/origin/<base>` contained it at their latest
    reflog entry no later than the branch's entry.
- **A tie in time goes to the base.** `git pull` moves the remote-tracking base and the branch
  within one second, and that position must read as foreign. The cost is that a commit and its
  merge in the same second read as `unknown`; tests set `GIT_COMMITTER_DATE` explicitly.
- **No evidence means `unknown`.** A branch with no reflog, no base reflog, or no base entry old
  enough to judge a position gives `unknown`, like every other uncertainty in this tier
  (RULES.md). The report names the reason: "its branch has no commits of its own (only commits
  <base> already had)" or "no reflog for its branch, so its own commits cannot be told from
  <base>'s".
- **Positions are compared, not reflog messages.** IDEs and GUI clients write messages as they
  please, and `rebase (finish)` carries own commits as often as not.
- ADR-0026's check stays in front of this one: it is cheap and answers for the current tip,
  which the reflog rule alone does not when a branch was committed to and then reset back.
- The forge tier is unchanged and still decides first. A task without `base_commit` is checked
  as before.
- **Housekeeping keeps the workspace of a task whose branch is checked out in the checkout it
  runs in, while that checkout has uncommitted changes**, as ADR-0029 already does for a task
  worktree: flag `worktree-kept`, reason `uncommitted-changes`. A `merged` that turns out wrong
  by some other path must not take the workspace from beside the work.

## Alternatives

- **Treat a tip on the base's first-parent chain as `unknown`.** Rejected: that is also where a
  genuine fast-forward merge puts the tip, and `git merge` fast-forwards whenever it can. Projects
  without a forge would stop seeing `needs-consolidation` for their ordinary merges.
- **Use the forge's "no pull request for this branch" as the signal.** Rejected: it encodes one
  project's policy. Many projects merge without pull requests; this repository's PR-only `main`
  is a special case.
- **Record more at `task start`.** Rejected: the fast-forward happens later, and nothing known at
  the start distinguishes it.
- **Cache housekeeping's own sightings of the branch under `.ai/runtime/`.** Rejected: it misses
  a merge that happens between two runs, and `--dry-run` at session start must stay free of side
  effects (ADR-0030). The reflog is the same journal of sightings, kept by git and complete.
- **Classify reflog messages** (`Fast-forward`, `reset: moving to`). Rejected for the reason
  above: the text is not an interface.

## Consequences

- ADR-0025 gains a third route to `unknown`, and ADR-0026's step 0 is no longer the whole
  question "did this branch contribute anything".
- Ancestry now depends on local reflogs. Where they are disabled or have expired
  (`gc.reflogExpire`, 90 days by default), tasks with `base_commit` stay `unknown` without a
  forge: nothing is purged and nothing is flagged for closing, and the report says why.
- The cost per task is at most four `merge-base --is-ancestor` calls per reflog position of the
  branch (fork, tip, and one per base ref), stopping at the first position of its own; the base
  reflogs are read once per run.
- Tests that commit and merge within one second must move git's clock (`hk_tick`).
- A branch whose own work was squashed or rebased onto the base still lands as before: its own
  position is contained in the tip, and the squash and rebase shapes decide from there.

> **Amendment (2026-09-16).** The base reflogs are read for every distinct task base, not for
> `git.base_branch` alone, and a task's own work is judged only against its own base's reflog
> (ADR-0039). Against `main`'s reflog, every commit an epic gained would count as a phase branch's
> own.
