---
id: adr-0020-artifact-inputs-are-not-completion
type: adr
status: accepted
date: 2026-09-10
domains:
  - task
  - sdlc
paths:
  - scripts/lib/task.sh
  - schemas/state.md
  - "skills/**"
summary: Why artifact inputs and conversation claims never prove approval or completion.
reviewed_at: 2026-09-10
---
# ADR-0020: Artifact inputs are facts, not completion

## Context

Fixed T0-T4 routes consume information, while useful stage output can live in conversation.
File presence cannot prove approval, correctness or delivery (ADR-0001, ADR-0009).

## Decision

`jig task artifacts <id> [--provided discovery,design,...]` reports documentary dependencies
for the task class. A readable nonempty regular workspace file is present; an explicit
provided kind is a caller claim, never persisted. Missing and optional inputs have reasons.
Report inputs-available/needs-input and unassessed semantic prerequisites separately.
The fixed routes use discovery, spec, alternatives, design, plan and verification as
applicable. File presence and provided claims never establish approval or implementation.
Successful reporting exits 0 even with missing inputs; invalid invocation/inspection exits 1.
No state writes, scheduling or lifecycle inference. T0/T1 without workspaces need no report.

## Alternatives

Mandatory files for every stage contradict artifact-by-value. A configurable workflow engine
adds a second router. Automatically advancing state confuses documentation with delivery.

## Consequences

The route table and skills must agree. Callers must substantiate provided claims and check
semantic prerequisites. Task state remains compatible with ADR-0005/0012. Approved as part
of the SDD/OpenSpec design on 2026-09-10.
