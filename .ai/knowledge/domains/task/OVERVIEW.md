---
id: domain-task
type: domain
status: active
summary: "The two seams the task ADRs do not describe: the ledger belongs to knowledge, and class is a field not a judgement."
domains:
  - task
topics: []
load: domain
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - schemas/state.md
  - templates/task.md
reviewed_at: 2026-09-11
---
# Task

The local lifecycle of a unit of work. What the lifecycle *is* — the workspace, the state
file, pause and resume — is settled by ADR-0005, ADR-0008 and ADR-0012 and is not restated
here. This document exists for the two seams those ADRs do not describe, because neither
of them is visible from inside this domain's own code.

## Boundaries

**The context ledger lives here and belongs to `knowledge`.** The file sits in the task
workspace, and this domain supplies the task id and the directory it goes in — but it does
not interpret a single line of it. A change to what an acknowledgement means is a
`knowledge` change that happens to touch `.ai/workspace/`.

**`class` is a field here, not a judgement.** Storing and validating `T0`–`T4` is this
domain's job; deciding which one a piece of work deserves belongs to the `jig-task` skill
and its rubric (ADR-0009). Nothing in `task.sh` may start inferring a class, and no rule
about *how* to classify belongs in this domain's documents.

**Artifact inputs and review inventory are facts, not lifecycle.** `task artifacts`
reports fixed-route information dependencies without assessing approval or completion
(ADR-0020). `task changes` requires an explicit base and inventories all Git layers;
the agent establishes task/hunk ownership and reads patches (ADR-0022). Neither command
changes task state or decides the next stage.

## Where this domain ends

`jig housekeeping` reads this domain's `state` files and never writes them (ADR-0005).
It now also copies `class`, `created_at` and `knowledge_consolidated` onto its purge line,
so `jig measure` can count a task whose workspace no longer exists (ADR-0027). Renaming a
field here therefore empties a column in a report two domains away, silently — the
copy is by key, and an absent key is read as unknown rather than as an error.
It has its own domain — see `domains/housekeeping/` — and the split is worth stating,
because the two are easy to confuse: **`status` is local progress, owned here; remote
merge state is derived there, every run, and stored nowhere.**

One consequence lands squarely on this domain, and ADR-0026 is the answer to it.
Housekeeping can only establish that work landed when the task had a branch of its own: a
task whose `branch` is the base branch resolves to `unknown` forever (ADR-0025). So a task
gets a branch of its own — but at `jig task start`, not at `jig task new`.

**Filing and beginning are different acts**, and the distinction is carried by an absence:

- A filed task has **no `branch` and no `base_commit`**. That absence is what keeps it out
  of `_task_candidates_for_branch`, so it is never an ambiguous `task current` candidate
  and needs no pause to stay out of the way. `task list` shows it as `not-started`.
- `jig task start` writes both. It is the only command that may write `branch` after
  creation; `task set` still refuses every script-owned key, so ADR-0008's invariant is
  intact.
- `base_commit` is resolved when work begins rather than when the task is filed, because a
  fork point recorded weeks earlier is false by the time anything reads it. A task without
  one — legacy or unstarted — is one housekeeping must judge the old, weaker way.
- `paused` means "was being worked on, set aside". It is not the way to say "not begun";
  that is what the missing `branch` says.

**Where a started task runs is a second, independent choice** (ADR-0029). `task start`
checks the branch out here. `task start --worktree` checks it out in a Task Worktree beside
the repository, for when this checkout is busy with other uncommitted work — the case the
dirty-tree refusal now names as its other road. Three things about it are easy to get
wrong from inside this domain's code:

- The workspace never moves. The worktree gets a link to it, so everything that reads a
  workspace works there unchanged, and the filing checkout keeps listing every task.
  Nothing may delete or move a workspace through that link. `task artifacts`, which
  refuses links, accepts exactly this one.
- Which worktree a task is in is *derived* from `git worktree list` on every call, never
  stored. `task list` and `jig status` print it with the count of uncommitted files there,
  because agents do not commit and that count is the human's review queue.
- A task in a worktree is not `task current` in the filing checkout: its branch is checked
  out elsewhere, and ADR-0008's branch match is what decides.

