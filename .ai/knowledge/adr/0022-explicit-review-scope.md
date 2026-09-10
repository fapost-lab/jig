---
id: adr-0022-explicit-review-scope
type: adr
status: accepted
date: 2026-09-10
domains:
  - task
  - skills
paths:
  - scripts/lib/common.sh
  - scripts/lib/task.sh
  - "skills/jig-review/**"
  - "skills/jig-architecture-review/**"
summary: Why task review requires an explicit baseline and separate change layers.
reviewed_at: 2026-09-10
---
# ADR-0022: Review inventories explicit baselines without claiming task ownership

## Context

Plain git diff omits committed, staged and new work. A configured main baseline cannot
identify task-owned commits or hunks in a shared dirty checkout.

## Decision

`jig task changes <id> --base <ref> [--files <a,b|->] [--format report|paths]` inventories
base-to-HEAD, HEAD-to-index, index-to-worktree and untracked layers separately. Require a
valid explicit commit base; report resolved revisions, layers and excluded candidate count.
A literal repository-relative allowlist can narrow paths. Empty supplied scope stays empty;
invalid paths and Git errors fail. Renames include both names. Paths output is suitable
for the corresponding context request. Existing helper callers keep their default behavior.

The inventory is not a patch or ownership proof. Skills inspect standard Git diffs for
every selected layer and new contents, review all requirements, and disclose binary,
submodule/unmerged and mixed-file limitations. Record baseline/ownership evidence in task
artifacts before editing. An unresolved mixed-hunk boundary prevents a complete-review claim.
Neither new task state nor automatic baseline inference is introduced.

## Alternatives

Inferring ownership from main or dates is unsound. A persisted baseline does not repair
old mixed work. A bespoke patch exporter duplicates Git without proving semantic scope.

## Consequences

Historical ambiguity can require a human answer. Review/context share one file inventory,
while the agent retains responsibility for scope and evidence. Approved as part of the
SDD/OpenSpec design on 2026-09-10.
