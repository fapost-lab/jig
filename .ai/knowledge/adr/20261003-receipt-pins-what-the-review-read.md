---
id: adr-20261003-receipt-pins-what-the-review-read
type: adr
status: accepted
date: 2026-10-03
domains:
  - task
  - skills
summary: Why the review receipt pins the task's own diff, merge-base aware, and the knowledge the review resolved instead of the whole tree, and what that leaves open.
paths:
  - scripts/lib/task.sh
  - schemas/state.md
  - "skills/jig-review/**"
---
# A review receipt pins what the review read — the task's own change and its resolved knowledge — not the whole tree

This amends adr-20260921-review-receipt-pins-what-was-reviewed: everything there stands except what
`tree` pinned.

## Context

The receipt pinned the git tree of the whole working tree (minus `.ai/knowledge/` and `.ai/specs/`).
That was right while the base moved once a day. When it moves several times an hour, merging it into the
task's branch changes the tree without changing a line of the task's change, and `jig task ship`
refuses with "review is stale: code changed since review (tree)": a full re-review of an unchanged
diff, and by the time it is signed the base has moved again. On 2026-10-01 the coordinator merged the
base into `task/start-refuses-an-occupied-checkout`, which brought two unrelated pull requests, and
that is exactly what happened. The receipt still has to do its job: it caught the tree changing
under a reviewer, and a reviewer who damaged `AGENTS.md` and the manifest.

A receipt says "I read this and found it sound". It must go stale when something its verdict depended
on changes. The whole tree is wider than that; the task's diff alone is narrower: the reviewer's verdict
also rested on a helper in `common.sh`, an invariant in `RULES.md` and accepted ADRs, none of which is in
the diff.

## Decision

The receipt compares four things, all by content. `tree`, `head` and `base_commit` stay in the file for
people and are no longer compared.

- **`diff`** is the task's own change: `git diff-tree -r --no-renames <merge-base> <tree>` hashed, where
  the merge base is that of the task's base branch (origin first, as `jig_base_ref` resolves it) and the
  checkout's HEAD, falling back to the task's recorded `base_commit`, and the tree is the same
  temporary-index tree as before, untracked files included, `.ai/knowledge/` and `.ai/specs/` left out.
  Merging the base moves the merge base with it, so what the base brought in is not the task's change
  and the receipt stays current; a base change to a file the task also touches does change the task's
  diff and makes it stale. With no merge base the pin is the whole tree, as before: stricter, never
  softer.
- **`context`** is the knowledge the review relied on: the documents `jig context` resolves for the files of
  the task's change, run as a process (`jig context --no-task --files - --domains <task's> --format paths`)
  in the checkout holding the task's branch, so the task's workspace is out and the global documents are
  in, as a hash of each document's path and content. Documents
  the task itself edited are left out: consolidation writes them after the review (ADR-0030), and they are
  the task's own change, so the task's own ADR does not stale the receipt of its own code, while
  another hand editing a convention or ADR the review applied does.
- **`design`** and **`findings`** are unchanged.

A stale answer names what moved and says what that means: `diff` is the task's own change, `context` the
knowledge under it, not the code. A receipt written before this change has no `diff` or `context` and is
compared by `tree` until it is next written.

The three overnight cases stay caught. A tree changed under a reviewer during the review changes the
task's diff (or the knowledge) and stales the receipt. A reviewer who damaged `AGENTS.md` and the
manifest did it in files outside `.ai/knowledge/` and `.ai/specs/`, which are in the diff. Neither needed
the whole tree, only the task's own change. The third, a mechanical guard, is `verify`'s, below.

The receipt answers for judgement. Mechanical guards (`tests/dispatcher.t.sh` and the like) are not
pinned: a new guard arriving with the base is caught by `jig verify` running on the merged tree before
shipping, which is what `verify` is for.

## Alternatives

- **Keep the whole tree**: the loop described above.
- **The task's diff only**: misses the knowledge and the helpers the verdict leaned on; changing an ADR
  the review applied would leave a current receipt.
- **Only the files in the task's surface, or the tree minus knowledge paths**: someone has to compute a
  surface, and that computation becomes the thing to trust; this uses git and the existing resolver.
- **Pin every file the reviewer opened**: the reviewer's reads are not recorded, and recording them is
  a new mechanism that an agent could under-report.

## Consequences

- Merging the base into a task branch no longer asks for a re-review unless it changes the task's diff
  or the knowledge that applies to it.
- Known holes, named: a file outside the diff that the reviewer leaned on (a helper in `common.sh`) is
  not pinned unless it is knowledge; the unrelated change of a mechanical guard is `verify`'s to catch;
  an unrelated merge that edits a global document (GLOSSARY, ARCHITECTURE, RULES) or a document that
  resolves for the task's files makes the receipt stale by `context` — deliberately, since the
  review read it; damage to the task's own knowledge files is not seen by the receipt, as before.
- Each check does a few more git calls and one knowledge resolution; it runs only for tasks that have a
  receipt.
- A task's own knowledge decisions can no longer be hidden behind the receipt, and no longer break it.
