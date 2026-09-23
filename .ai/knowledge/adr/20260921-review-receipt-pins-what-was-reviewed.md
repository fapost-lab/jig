---
id: adr-20260921-review-receipt-pins-what-was-reviewed
type: adr
status: accepted
date: 2026-09-21
domains:
  - task
  - skills
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - schemas/state.md
  - "skills/jig-review/**"
  - "skills/jig-architecture-review/**"
  - "skills/jig-verify/**"
  - "skills/jig-consolidate/**"
summary: Why a review ends in a receipt pinning the working tree (not HEAD), the approved design and the findings ledger, and why a stale receipt, or none on a T4, refuses completion.
reviewed_at: 2026-09-21
---
# A review ends in a receipt that pins the reviewed working tree, and completion refuses once it is stale

## Context

The findings ledger (adr-20260921-review-findings-block-completion) stops a task while a serious
finding is unresolved, but it does not know what was reviewed: code changed after the review
reached `ready`, consolidation and `task ship` unchecked, and an author could close their own
finding. The autopilot specification asked for a receipt pinned to "the reviewed commit", refusing
on "a moved HEAD".

Discovery found that a commit is the wrong thing to pin. With `agent.git: none` a review reads an
uncommitted working tree, so HEAD is the base and pins nothing; with a higher level, a commit after
review moves HEAD without changing a line. And consolidation runs after review and writes
`.ai/knowledge/` and `.ai/specs/` by the route (ADR-0030), so a pin over the whole tree would break
on every task.

## Decision

- **A receipt per task**, `.ai/workspace/tasks/<id>/receipt`, written by
  `jig task receipt <id> --stage review|architecture-review` as the review's last step, and
  rewritten by each re-review. It records `tree`, `design`, `findings`, plus `stage`,
  `reviewed_at`, `base_commit` and `head` for people.
- **`tree` is the content, not a commit**: the git tree id of everything `git add -A` sees,
  built in a temporary index so the real one is never touched, minus `.ai/knowledge/` and
  `.ai/specs/`. Documentation and every other path are pinned like code — approved at the gate.
  A commit or amend that changes no content leaves the receipt current; one that does makes it
  stale.
- **The tree is read where the task's branch is checked out** — this checkout or a task worktree
  (ADR-0029), whichever git lists with it. Writing a receipt for a branch checked out nowhere
  refuses; checking one counts the unreadable tree as changed, so no gate passes on a change it
  could not look at.
- **`design`** hashes the approved `design.md` (for T4 also `spec.md` and `alternatives.md`);
  `task.md` is the task's log and is not pinned. **`findings`** hashes the ledger, so any change to
  it after review — an author closing their own finding included — makes the receipt stale.
- **The same three gates** as the ledger refuse on a stale receipt, naming what changed:
  `task set status ready`, `task set knowledge_consolidated true`, `task ship`. A T4 task without a
  receipt refuses; T0–T3 without one pass. `jig task receipt <id> --check` and `review=stale` on
  `jig status` report the same answer from the same function.

## Alternatives

- **Pin HEAD**, as the specification first said: pins nothing for an uncommitted review, and refuses
  after a content-free commit.
- **Hash `git diff <base>`**: misses untracked files unless they are added to the real index.
- **Pin the whole tree and review after consolidation**: lengthens every route and moves the
  knowledge decision off the last step before the commit (ADR-0030).
- **Require a receipt for T2 and T3 too**: stricter than the specification asked; a T2/T3 task gets
  one whenever review runs, and a receipt that exists is always checked.
- **Pin `task.md`**: decisions and deviations are written to it after review by design.
- **Exclude documentation too**: rejected at the gate — it is part of the reviewed change, and in an
  installed project it has no fixed path.

## Consequences

- A change is finished only as reviewed: code edited after review, or a finding closed without a
  re-review, sends the task back to review.
- The receipt binds the ledger to a review, which the findings ADR left open — within the limits of
  ADR-0020: it is written by an agent, and it proves a review was recorded, not that it was good.
- Every gate check builds one temporary index: a cost of one `git add -A` over the working tree,
  which also writes a blob for each new or changed file into the object store. Nothing refers to
  them, and `git gc` prunes them like any unreferenced object.
