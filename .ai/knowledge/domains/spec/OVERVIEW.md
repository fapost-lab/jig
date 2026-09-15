---
id: domain-spec
type: domain
status: active
summary: "Specifications and the jig-idea skill: creating, listing and counting plans that are deliberately not knowledge."
domains:
  - spec
topics: []
load: domain
paths:
  - scripts/lib/spec.sh
  - "templates/spec/**"
  - "skills/jig-idea/**"
reviewed_at: 2026-09-14
---
# Spec

Specifications: committed plans for work larger than one task, and the skill that develops
them. Why they exist and why they are not knowledge is ADR-0035; the file format is
`schemas/spec.md`.

## Responsibility

- Creating a spec (`jig spec new`) from the framework-owned templates, with the id
  validated before any path is built.
- Reporting specs and their progress (`jig spec list`) and counting them for `jig status`,
  derived from files alone — a spec has no status.
- The `jig-idea` conversation: understand the idea, put weight on it, offer other shapes,
  record decisions, build the roadmap.

## Boundaries

Outside: knowledge. Nothing here is resolved by `jig context` or validated by
`jig knowledge check`, and nothing in `knowledge.sh` or `context.sh` may start reading
`.ai/specs/` — that would turn a plan into a description of the system.

Outside: task lifecycle. A spec never starts a task, and `spec.sh` never reads or writes a
task `state`. The id grammar is shared with tasks through `jig_valid_id` in `common.sh`,
because a roadmap names task ids; `spec.sh` must not source `task.sh`.

`status.sh` consumes `spec_count`, never recounts. The counting rules for roadmap lines
live in `spec_progress` only.

## Entry points

- `scripts/lib/spec.sh` — `cmd_spec`, `spec_new`, `spec_template`, `spec_list`,
  `spec_progress`, `spec_count`.
- `templates/spec/spec.md`, `templates/spec/roadmap.md` — installed as `.ai/templates/spec/`.
- `skills/jig-idea/SKILL.md` and `references/pressure.md`.
- `schemas/spec.md` — the directory layout and the roadmap line grammar the script counts.
