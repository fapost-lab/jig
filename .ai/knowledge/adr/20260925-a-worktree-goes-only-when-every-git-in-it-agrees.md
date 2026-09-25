---
id: adr-20260925-a-worktree-goes-only-when-every-git-in-it-agrees
type: adr
status: accepted
date: 2026-09-25
domains:
  - housekeeping
  - task
paths:
  - scripts/lib/housekeeping.sh
  - scripts/lib/task.sh
summary: Why the cleanup asks the ignored paths of a worktree for repositories of their own, and keeps the worktree when one holds work that is nowhere else.
reviewed_at: 2026-09-25
---
# A task worktree goes only when every git inside it agrees

## Context

ADR-0029 rests on a measurement: `git worktree remove` without `--force` refuses on tracked
changes and on untracked files, but **deletes ignored files silently**. That sentence is in its
Consequences, and the cleanup was built on it — `_hk_worktree_retire` asks
`git status --porcelain` and treats an empty answer as proof that nothing is at stake.

The measurement is right and the conclusion drawn from it was too narrow. What git ignores is not
only what a build produced. Measured again here on git 2.48.1, in a worktree holding `.env`,
`node_modules/`, a clone in `vendor/` and a separate repository with one unpushed commit:

```
git status --porcelain            -> (nothing)
git status --porcelain --ignored  -> !! .env  !! local/  !! node_modules/  !! vendor/
git worktree remove ../wt         -> exit 0, no output, the directory is gone
```

The cleanup saw an empty tree and removed it. The unpushed commit existed in exactly one place on
earth and now exists in none. `worktree-bootstrap` raises the stakes: it puts `vendor/`,
`node_modules/` and `.env` into a worktree on purpose, which is the same class of path.

This is not a risk waiting to happen. It cost something on the night this was decided: a task
statement filed from inside a worktree was one step from going the same silent way, and
`worktree-bootstrap` measured the sharpest form of it. There, `worktree.carry` puts an ignored path
into the worktree, and when that path holds a real repository, removing the worktree destroyed both
the uncommitted files in it **and** a commit that existed in that clone and nowhere else.

That shape was measured again here, against this decision's check and in the layout
`worktree-bootstrap` used (git 2.48.1). An ignored `vendor/` holding a real clone is carried into a
worktree; a commit is made inside the carried clone and its working tree is left clean. Then:

- the clone's `status --porcelain` is empty, so the first question cannot be what answers;
- the clone has `origin`, so the second cannot either;
- `rev-list --all --not --remotes --tags` names that commit, and the worktree is kept, with the
  path of the clone in the note;
- `git status --porcelain` in the worktree around it is empty — the blind spot, exactly;
- `git cat-file -t <commit>` in the parent checkout fails: it never saw the object.

Asked to remove that same worktree without this check, git exits 0, prints nothing, the directory is
gone, and the commit is then in no repository anywhere. That the sharpest known case is caught, and
caught by the one question that was left to catch it, is the evidence this sign is the right one —
measured, not argued. It is also what makes `worktree.carry` safe to release **on the cleanup's
path**, and only there: carrying `vendor/` and `packages/` into a worktree no longer puts a commit
one Jig cleanup away from nothing. It is exactly as unsafe as it ever was when a person runs `git
worktree remove` by hand, and that half is git's, not Jig's — the two claims are different, and the
warnings written while the loss was unavoidable have to be narrowed to the second one, not deleted.

The obvious repair — ask with `--ignored` and keep the worktree when anything comes back — is
worse than the fault. Every installed project has a `node_modules/` or a `vendor/`, so the
cleanup would keep every worktree forever, which is cleanup by manual discipline (RULES.md,
Scope invariants) under another name. What was needed was a sign the machine can read on its own,
separating a folder that `npm install` recreates from work that exists nowhere else.

## Decision

- **Before removing a worktree, the cleanup asks git what it will delete without a word** —
  `git status --porcelain -z --ignored` — and searches those paths, and only those, for
  repositories of their own. Untracked files git refuses to delete by itself, so the ignored
  paths are exactly its blind spot.
- **Each repository found answers for itself.** Its own git is the only one that knows: the
  project around it does not track a line of it. The questions, in order, any of which keeps
  the worktree:
  - `git -C <repo> rev-parse --git-dir` does not answer — an uncertainty keeps the worktree,
    as every other uncertainty here does;
  - `git -C <repo> status --porcelain` is not empty;
  - the repository has no remote at all and has a commit: there is nowhere it could have pushed
    anything to, so that commit exists here and nowhere else;
  - otherwise `git -C <repo> rev-list --all --not --remotes --tags` is not empty.

  The last one is the whole test, and every part of it was chosen by measuring the cases rather
  than by reasoning about them (git 2.48.1). It reports a local branch, a stash and a commit made
  on a detached HEAD alike, and it does not fail on a repository with no commits, which naming
  `HEAD` does. Tags are on the excluding side because of a measurement that contradicted the first
  draft of this decision: a dependency cloned with `--depth 1 --branch <tag>` or `--single-branch
  --branch <tag>` has **no remote-tracking ref at all** — its only ref is `refs/tags/<tag>` — so
  `--not --remotes` excludes nothing and the pin reads as unpushed work. That draft would have kept
  every worktree holding a pinned dependency for ever, which is the rejected alternative arriving
  from the other side. The cost of excluding tags is named rather than hidden: in a repository that
  does have a remote, a local commit reachable only from a local tag is missed. A repository with
  no remote is not affected, because it never reaches this question.
- **The worktree is then kept with reason `nested-repository`**, which `jig status` counts like
  any other `worktree-kept`, and the note names the repository so a person can go and push it.
  When git will not say which files it ignores, the worktree is kept too, with reason
  `ignored-unknown`: those are the files it deletes without a word, so an unanswered question there
  has to keep the worktree, exactly as an unanswered question does everywhere else in this cleanup.
  Reading it the other way — "then nothing is ignored" — turns a failed question into a deletion.
  The task's workspace stays with it, as it does for every other kept worktree.
- **Everything else the project ignores still goes**, and `status --porcelain` is still asked
  without `--ignored`. A worktree holding nothing but `node_modules/` is a worktree with nothing
  to lose.
- **A removal names what went with it.** The log line gains `ignored=<paths>` — up to five, then
  a count — leaving out jig's own ignored paths, since `.ai/runtime` is derived and
  `.ai/workspace` holds only the link to a workspace that stays where it was filed. Nothing can
  tell a `.env` from a built folder, but "deleted" and "deleted silently" are different things,
  and afterwards the question "what was in there" has an answer.

## Alternatives

- **Keep a worktree whenever anything ignored is in it.** Rejected above: it turns the cleanup
  off in every project that installs dependencies, which is most of them.
- **A list of precious names — `.env`, `*.sqlite`, `*.key`.** Rejected: it is a guess dressed as
  a rule. It is wrong in both directions on the first project that names things differently, and
  it grows by bug report forever.
- **Predict what git will delete from the paths themselves.** Rejected on the record of
  `worktree-bootstrap`, where four findings in a row predicted what git sees in a tree and all
  four were wrong. Where an answer can be asked for, it is asked for.
- **Have the bootstrap record what it copied in, and treat anything else ignored as unaccounted
  for.** The most precise sign available, and rejected here: it covers only what jig put there,
  it is blind to what the work itself created, and it binds this fix to a task that has not
  landed. It stays open as a way to extend the protection later.
- **Remove with `--force`, or ask the person.** Both already rejected by ADR-0029, and the
  cleanup runs unattended.
- **Drop the `docs/known-issues.mdx` entry whole, on the grounds that what is left is a documented
  boundary rather than a fault.** Tried, and reversed: the entry describes silent deletion of
  ignored work, and this decision narrows that fault without ending it. A page that stops
  mentioning it tells the reader it cannot happen, and the reader then leaves a `.env` in a
  worktree trusting us.
- **Keep the whole entry, rewritten.** Also rejected, and this is where the two halves part. One
  half is a fault with an owner: a task filed from inside a worktree is created in the worktree's
  own `.ai/workspace/tasks/`, which is ignored and exists nowhere else, and this decision does not
  reach it because a task folder answers no git. It stays on the page, owned by
  `task-new-in-a-worktree-strands-the-task`, and leaves it when that is fixed. The other half — a
  `.env`, a local database — is not a fault and will not become one: it is git's contract, and no
  sign separates those from a built folder, which this decision measured rather than assumed. An
  entry that can never be removed would make `conventions/documentation.md`'s owner rule a
  preference at its first test, and the next ownerless entry would cite this one. So that half is
  stated where worktrees are described, as a property with a rule the reader can act on: do not
  leave in a worktree the only copy of something git does not have.

## Consequences

- The cleanup walks the ignored paths of a worktree it is about to remove, and that walk is a real
  one: git's answer is short — whole ignored directories come back as one entry — but `find`
  descends each of them, so an installed `node_modules` is read through. What bounds the cost is
  that it runs once, at removal time, for a task already closed and landed; `-prune` keeps it out
  of the object store of a repository it just found; and it is not given `-L`, so the link that
  borrows the owner's task directory leads nowhere. It runs last, after the cheap questions, and only for a worktree under
  `git.worktree_root`: a worktree jig did not create is not removed anyway.
- A repository nested inside an ignored folder that nobody will ever push now keeps a worktree,
  and its task, under "needs you" until a person deals with it. That is the intended trade: the
  alternative is a silent loss.
- **What this does not cover, said plainly so nobody reads it as covered:** the sign is a
  repository. An orphaned task directory under `.ai/workspace/` is not one — it is ignored files
  with no git of its own to ask — so a task filed from inside a worktree is still stranded and
  still goes silently. That is a different defect with a different fix, filed as
  `task-new-in-a-worktree-strands-the-task`, and the check here was deliberately not widened to
  reach it: widening it means keeping a worktree for ignored files as such, which is the
  alternative rejected above. The same holds for every ignored path that answers no git: a `.env`,
  a local database, generated fixtures. They are named in the log, not protected.
- RULES.md gains the condition, and ADR-0029's "it deletes *ignored* files silently. That is why
  a worktree holding a real workspace is kept" is no longer the whole story — the silent deletion
  is still true, and it is no longer the end of the reasoning.
- `_task_undo_worktree_start` in `scripts/lib/task.sh` removes a worktree too, and does not get
  this check. Its worktree is seconds old and was created empty by this very call, so there is no
  ignored work in it to lose; if `worktree-bootstrap` ever moves rather than copies files into a
  worktree before that undo can run, the check belongs there as well.

> **Amendment (2026-09-25, later the same day).** The consequence above — "a task filed from
> inside a worktree is still stranded and still goes silently" — no longer holds, and what closed
> it is not the widening this decision rejected. `jig task start --worktree` now gives the worktree
> one link to the owner's whole `.ai/workspace/tasks/` directory instead of one link to a single
> task inside a directory of its own (ADR-0029, amendment of 2026-09-25), so a task filed in a
> worktree is filed where every other task is and outlives the tree that wrote it. Nothing in this
> decision changed: the sign is still a repository, ignored files that answer no git are still
> named in the log rather than protected, and the check was not widened to reach them.
>
> The orphan survives in the two shapes that decision names, and in both it is refused instead of
> lost: where `task start` keeps the per-task link because a directory link would read as untracked,
> and in a worktree somebody made by hand, `jig task new` refuses and names the checkout the task
> belongs in. The `docs/known-issues.mdx` entry the alternative above left on the page, owned by
> `task-new-in-a-worktree-strands-the-task`, left it with that task's own pull request — which is
> what the alternative said would happen, and is `conventions/documentation.md`'s owner rule
> working rather than being made a preference.
