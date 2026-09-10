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

## Not built yet

`jig housekeeping` is declared in the dispatcher and exits "not available in jig 0.1.0";
`scripts/lib/housekeeping.sh` does not exist. ADR-0005 and ADR-0006 are accepted and point
their `paths` at that file, which is why `jig knowledge paths` reports two unmatched globs.
Reconciling workspaces against remote state, and the two-stage purge, join this domain when
they land — until then, two of its four governing ADRs describe code nobody can read.
