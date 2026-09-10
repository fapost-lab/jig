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
reviewed_at: 2026-09-10
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
It has its own domain — see `domains/housekeeping/` — and the split is worth stating,
because the two are easy to confuse: **`status` is local progress, owned here; remote
merge state is derived there, every run, and stored nowhere.**

One consequence lands squarely on this domain. Housekeeping can only establish that work
landed when the task had a branch of its own: a task whose `branch` is the base branch
resolves to `unknown` forever (ADR-0025), so on a trunk-based project no workspace is
ever purged automatically. `branch` is written once by `task new` from the current
checkout and is never a branch this domain created — which is exactly the deferred
`task-branch-lifecycle` work.
