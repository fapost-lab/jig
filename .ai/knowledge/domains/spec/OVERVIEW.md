---
id: domain-spec
type: domain
status: active
summary: "Specifications and the jig-idea skill: creating, listing and counting plans that are deliberately not knowledge, their epic branches, and shipping spec work by agent.git."
domains:
  - spec
topics: []
load: domain
paths:
  - scripts/lib/spec.sh
  - "templates/spec/**"
  - "skills/jig-idea/**"
reviewed_at: 2026-09-22
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
- The epic branch of a spec released once (ADR-0040): the `Epic:` line, `jig spec epic` to declare,
  cut, finish and reopen it, and how `spec list` and `jig status` show it; the `Release:` line recorded
  at declaration (`spec_release_check`).
- Shipping spec work (adr-20260922-spec-work-ships-by-the-agent-git-level): `jig spec ship` in the
  modes `declare`, `epic` and `final`, read from the checkout, as far as `agent.git` allows; the lines
  `spec epic` prints name the next step by that level (`spec_ship_hint`).
- Closing a spec whose work is done (ADR-0035 as amended): its leftovers (`spec_leftovers`), the
  `roadmap complete` line of `spec done`, and the removal by `spec close` or `spec epic --finish`, in
  the change that finished it.
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

`status.sh` consumes `spec_count` and `spec_epic_status`, never recounts, and its status page renders
`spec_list_rows` — the unformatted rows `spec list` aligns — so the page and `spec list` cannot disagree
about a spec's state. The counting rules for roadmap lines live in `spec_phase_counts` only: it counts
per `## Phase <n>` section, and `spec_progress` is its sum. The page's progress by phase is
`spec_phase_rows`, which reads the roadmap of a spec with an open epic from the epic's ref when the
checkout is elsewhere — progress is made there (ADR-0040) — without fetching, and names that branch.
A command that changes a spec redraws the status page (`jig_status_page_touch`).

`spec ship` takes its git steps from `common.sh` (`jig_ship_*`), the ones `task ship` takes, and keeps
only its modes and their refusals here. It never writes a spec file: what it commits is what `spec epic`
and the agent left staged. It merges one thing, the epic's final pull request, at `agent.git: merge` and
only when `autopilot.unattended` is set (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci):
with a merge commit only, after `spec_ship_final_ready` finds the epic holding the freshest default, the
spec gone, no non-fog item unchecked (`spec_unchecked_items`) and no task cut from the epic outside it
(`spec_epic_unmerged_tasks`, which reads task `state` files: `base_branch`, `branch`, `status`); a
`major` `Release:` opens a draft instead. A declaration is never merged.

## Entry points

- `scripts/lib/spec.sh` — `cmd_spec`, `spec_new`, `spec_template`, `spec_list`, `spec_list_rows`,
  `spec_progress`, `spec_phase_counts`, `spec_phase_rows`, `spec_list_state`, `spec_count`, `spec_done`, `spec_remove`, `spec_epic`,
  `spec_epic_status`, `spec_close`, `spec_leftovers`, `spec_ship`, `spec_ship_final_ready`, `spec_release_check`.
- `scripts/lib/common.sh` — `jig_trash_dest`, shared with housekeeping; `jig_spec_link`,
  `jig_spec_epic`, `jig_fresh_base_ref`, `jig_fetch_branches`, shared with `task start`; `jig_ship_*`,
  shared with `task ship`.
- `.github/scripts/epic-pr-check.sh` — this repository's CI check of an epic's final pull request.
- `skills/jig-consolidate/SKILL.md` §5 and `skills/jig-task/SKILL.md` — where a linked task meets
  its spec.
- `templates/spec/spec.md`, `templates/spec/roadmap.md` — installed as `.ai/templates/spec/`.
- `skills/jig-idea/SKILL.md` and `references/pressure.md`.
- `schemas/spec.md` — the directory layout and the roadmap line grammar the script counts.
