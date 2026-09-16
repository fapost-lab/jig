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
reviewed_at: 2026-09-16
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
  record decisions, build the roadmap, and file a phase's tasks when asked.
- The epic branch of a spec released once (ADR-0039): the `Epic:` line, `jig spec epic` to declare,
  cut, finish and reopen it, and how `spec list` and `jig status` show it.
- The link between a task and its spec: the `Spec:` line in the task's `task.md`, checking its
  roadmap items at the knowledge decision (`jig spec done`), and taking a spec out with its links
  (`jig spec remove`).

## Boundaries

Outside: knowledge. Nothing here is resolved by `jig context` or validated by
`jig knowledge check`, and nothing in `knowledge.sh` or `context.sh` may start reading
`.ai/specs/` — that would turn a plan into a description of the system.

Outside: task lifecycle. A spec never starts a task, and `spec.sh` never writes a task
`state`. It reads `status`, `branch` and `base_commit`, writes only the `Spec:` line out of a
`task.md`, and abandons a task by running `jig task abandon` through the dispatcher. The id grammar
is shared with tasks through `jig_valid_id` in `common.sh`, because a roadmap names task ids;
`spec.sh` must not source `task.sh`, so it builds a workspace path itself in `spec_task_dir`.

Ids are compared as strings everywhere a task or spec id meets a file's text: `.` is legal in an
id, and as a pattern it matches `a.b` against `axb`. `spec remove` abandons before it unlinks, so a
failed abandon leaves the `Spec:` line that lets a rerun find the task.

`Spec:` and `Epic:` are parsed in `common.sh` (`jig_spec_link`, `jig_spec_epic`), not here, because
`task start` reads both to choose a task's base. Nothing in housekeeping reads a spec: a phase's link to
its epic is the task's `base_branch`.

`status.sh` consumes `spec_count` and `spec_epic_status`, never recounts. The counting rules for roadmap lines
live in `spec_progress` only.

## Entry points

- `scripts/lib/spec.sh` — `cmd_spec`, `spec_new`, `spec_template`, `spec_list`,
  `spec_progress`, `spec_list_state`, `spec_count`, `spec_done`, `spec_remove`, `spec_epic`,
  `spec_epic_status`.
- `scripts/lib/common.sh` — `jig_trash_dest`, shared with housekeeping; `jig_spec_link`,
  `jig_spec_epic`, `jig_fresh_base_ref`, `jig_fetch_branches`, shared with `task start`.
- `.github/scripts/epic-pr-check.sh` — this repository's CI check of an epic's final pull request.
- `skills/jig-consolidate/SKILL.md` §5 and `skills/jig-task/SKILL.md` — where a linked task meets
  its spec.
- `templates/spec/spec.md`, `templates/spec/roadmap.md` — installed as `.ai/templates/spec/`.
- `skills/jig-idea/SKILL.md` and `references/pressure.md`.
- `schemas/spec.md` — the directory layout and the roadmap line grammar the script counts.
