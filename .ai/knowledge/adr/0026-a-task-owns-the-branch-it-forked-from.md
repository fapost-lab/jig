---
id: adr-0026-a-task-owns-the-branch-it-forked-from
type: adr
status: accepted
date: 2026-09-10
domains:
  - task
  - housekeeping
paths:
  - scripts/lib/task.sh
  - scripts/lib/housekeeping.sh
  - schemas/state.md
summary: Why task new creates its own branch, and why the fork point must be recorded before ancestry can be trusted.
reviewed_at: 2026-09-11
---
# ADR-0026: A task creates its own branch and records where it forked from

## Context

ADR-0008 decided that a workspace belongs to the checkout it was created in, and
`jig task current` resolves a task by matching the checkout's branch against `branch:` in
local state. That model assumes one task per branch. Nothing enforced it: `task new`
recorded whatever branch the checkout happened to be on, so on a trunk-based repository
every task shared `main`, `task current` was permanently ambiguous (ADR-0012 had to add an
exit code for it), and ADR-0025 had to make ancestry answer `unknown` for a task whose
branch *is* the base branch — because `merge-base --is-ancestor main main` is trivially
true.

The consequence was that Phase 5's housekeeping, fully implemented and tested, purged
nothing on the repository that developed it.

Creating the branch is the obvious repair and, on its own, a dangerous one. A branch that
has just been created has a tip identical to the base's, so ancestry answers `merged` for
it — measured, not reasoned. A task reaching `consolidated` without ever committing would
be purged while all of its work sat uncommitted in the working tree. The naive form of
this feature does not repair housekeeping; it arms it.

## Decision

- **`jig task start` creates and checks out a branch**, cut from `git.base_branch` rather
  than from `HEAD` — a task is work proposed against the base, and starting it wherever
  the checkout happened to be is how a task inherits an unrelated history. Configured by
  `git.branch_per_task` (default `true`) and `git.branch_template` (default `task/{id}`),
  with `--no-branch` for one invocation.
- **The branch name is validated by `git check-ref-format --branch`**, not by a
  hand-rolled pattern. The invalid set is long — `..`, a trailing `.lock`, control
  characters, a leading dash — and the failure mode is a ref nobody can delete without
  plumbing.
- **An existing branch of that name is a hard, early failure.** Reusing or suffixing it
  would silently attach a task to someone else's work.
- **`state` gains a script-owned `base_commit`**: the commit the branch forked from.
  Written once by `task new`, refused by `task set` like `task_id` and `branch`.
- **Housekeeping asks "did this branch contribute anything" before "did it land".** With
  no commits since `base_commit`, the answer is `unknown`, never `merged`. `base_commit`
  is verified with `cat-file -e <sha>^{commit}`, because `rev-parse --verify` accepts the
  all-zero SHA as a well-formed name and would let a stale fork point read as "did
  nothing" for a branch that may well have landed.
- **An absent `base_commit` means the old behaviour**, unchanged. That covers every
  workspace created before this decision and every `--no-branch` task.

## Alternatives

- **Create the branch and stop there.** Rejected: it is the dangerous half. Ancestry would
  report every fresh task branch as merged, and `consolidated` means purge.
- **Distinguish "did nothing" from "fast-forwarded" by comparing commit SHAs.** Rejected:
  after a fast-forward merge the base and the merged branch point at the same commit, so a
  genuinely merged branch becomes indistinguishable from an untouched one. Refs alone
  cannot separate the two cases, which is why the fork point has to be recorded at
  creation.
- **Measure squash and rebase detection from `base_commit` too.** Rejected on inspection:
  for a branch cut from the base, `merge-base(base, tip)` *is* `base_commit`, and where
  they diverge — a branch rebased onto a newer base — `merge-base` recomputes the true fork
  point while `base_commit` is stale. The recorded fork point answers "did this branch do
  anything"; `merge-base` answers "what did it contribute".
- **Derive the fork point on demand instead of storing it.** Rejected: the whole point is
  to know where the branch started *before* history moved. Recomputing it later gives the
  answer that history has since produced, which is the question already being asked.
- **A per-checkout pointer to the active task** (`.ai/runtime/`), to allow several tasks on
  one branch. Deferred: branch-per-task removes the ambiguity the pointer was invented for,
  and a second source of truth for "which task is active" drifts from the first.

> **Amendment (2026-09-11).** The branch was originally cut by `jig task new`. That was
> wrong for a task filed and started later: `base_commit` means "where this task's branch
> began", and a fork point recorded weeks before work starts is false by the time anything
> reads it. Measured on this repository the same week — six of seven live tasks had been
> filed for later and never started, so branch-at-filing fitted one task in seven.
>
> Creating the branch moved to **`jig task start <id>`**, and a task filed but not started
> now carries **no `branch` and no `base_commit` at all**. The absence does the work:
> `_task_candidates_for_branch` matches on `branch`, so an absent one keeps the task out of
> `task current` without a pause. Before this, filed tasks claimed whatever branch the
> checkout happened to be on — four of them claimed a foreign branch in one day.
>
> A second defect fixed with it: `_task_create_branch` resolved `refs/heads/<base>` before
> `refs/remotes/origin/<base>`, so a local base that had fallen behind produced a stale
> branch *and* a stale `base_commit`, silently. `task start` now prefers `origin/<base>`
> when local is strictly behind and says which it used; diverged bases are refused rather
> than guessed.
>
> `--no-branch` is gone: not creating a branch at `task new` is the behaviour now.
>
> The dirty-tree refusal ADR-0012 put on `task new` moved with the branch to `task start`,
> on both paths — with a branch per task and with one shared branch — and it has no
> `--force`. Filing touches nothing that uncommitted work could leak into; starting cuts
> the branch that work would ride into, or records a `base_commit` it already sits on top
> of. Every wrong `branch` field recorded on 2026-09-11 came through that override.
>
> Two consequences below are historical as written. A failed start leaves the task filed
> and unstarted instead of removing a workspace, because `task start` writes `branch` and
> `base_commit` only after the checkout succeeds. And the exposure and the tests attributed
> to `--no-branch` now belong to `git.branch_per_task: false`.
>
> Two follow-ups settled later the same day, with ADR-0029. **A `branch` with no
> `base_commit` counts as not started**: it was recorded at filing, from whatever the
> checkout was on, so `task start` rewrites both fields and says so. That repairs the tasks
> filed before this amendment without a new command and without hand-editing a
> script-owned key. **The per-checkout active-task pointer below is closed, not
> deferred.** Branch-per-task and worktrees give each checkout at most one live task by
> construction, and a pointer would be a second source of truth. It would disagree with the
> branch after the first `git checkout` — the failure class ADR-0012 exists to prevent.

## Consequences

- Jig now mutates git state. `task pause --stash` was the first such command; this is the
  first that creates a ref. Both are guarded the way ADR-0006 demands of irreversible
  operations: everything that can refuse refuses before anything is created, and a failed
  checkout removes the workspace this call just made. The guarantee does not extend to a
  local `mv` failing *after* the branch exists — a disk-full window too narrow to justify
  rolling back a checkout.
- `jig task current` becomes unambiguous in the ordinary case, and ADR-0012's exit code 2
  is reachable mainly where `branch_per_task` is off.
- ADR-0025 gains a second route to `unknown`: not only "the task is on the base branch"
  but also "the branch has done nothing since it forked".
- A `--no-branch` task keeps the old exposure. That is the price of the escape hatch and
  is documented in `schemas/state.md` rather than left to be discovered.
- Existing tests that needed two tasks on one branch — candidate ambiguity, detached HEAD —
  now say `--no-branch` explicitly, which documents that those behaviours survive only
  where branch-per-task is off.
