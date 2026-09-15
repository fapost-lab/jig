# Specifications and the jig-idea skill

Depth: deep — the first design was rejected, and the result changes where plans live in every
Jig project.

## Idea

"What if an idea is big and needs 10–20–100 tasks — where is its roadmap kept then? I thought
that is exactly what this is for: create a specification with phases, a roadmap and so on, and
only then take that spec and create tasks from it. Or the second option: research a new idea
for a future project, work out the architecture, the stack and so on, and then move these
documents into a new project and build it. That is, use this skill in an 'idea generation'
project. What we have now is the same as me asking an agent a question, discussing it and
saying 'create a task'. Why a separate idea skill then?"

Added during the design: the skill should ask questions, criticise, analyse the idea and check
whether it holds up; an agent must be able to list the specs; a spec must be removable, cleaning
up the links from its unfinished tasks.

## Goal and problem

- Who is worse off without this, and how: a person with work bigger than one task has nowhere
  to keep its plan. `task.md` belongs to one task and is not committed; knowledge describes the
  system as it is, not as it will be. Ideas for a project that does not exist yet have no home
  at all. And nothing in Jig challenges an idea before work starts: every existing question
  clarifies what was said.
- What is true when the work is done: an idea is tested in conversation and kept as a committed
  specification with a roadmap; tasks are filed from it phase by phase and linked back; the
  roadmap shows progress; a spec can be removed cleanly or carried into a new project.

## Stress test

- Hidden assumptions:
  - A plan outside knowledge stays readable to the agents that need it — holds only if the task
    links the spec. Without the link a spec is invisible to task agents; hence the fixed
    `Spec:` line (phase 2).
  - Progress without statuses is enough — holds only if roadmap checkboxes are kept up to date.
    Consolidation sets `[x]`; a task closed outside Jig leaves the item open.
- The main trade-off: a second place for documents next to `.ai/knowledge/` (against ADR-0028's
  single place) in exchange for never reading a plan as a description of the current system.
- The weakest point: the roadmap and task workspaces can drift apart. Workspaces are local, so
  tasks filed on another machine are invisible to `jig spec remove` and to any cross-check.
- Failure modes:
  - Specs are written and never turned into tasks — signal: `jig spec list` shows no filed
    items for months.
  - The skill becomes a slow questionnaire people skip — signal: specs created without a stress
    test section filled in.
  - A spec is read as knowledge after all — signal: task agents cite a spec's decisions as
    current behaviour.
- Other shapes considered: a verdict with no storage (rejected — nothing over "discuss, then
  file a task"); a spec as a proposed `feature` knowledge document (rejected — proposed never
  resolves, active would read as present behaviour); a spec inside a task workspace (rejected —
  local and cleaned up).

## Scope and non-goals

- In scope: `.ai/specs/<id>/` storage; the `jig-idea` skill; `jig spec list` and the `specs:`
  status line; filing phase tasks with a `Spec:` link; roadmap checkmarks at consolidation;
  `jig spec remove`; carrying a spec into a new project.
- Not doing: spec statuses; a `parent` field in task state; dates or point estimates in
  roadmaps; copying the SDD plugin's skills.

## Decisions

- Specs live in `.ai/specs/<id>/`, committed, outside knowledge — rejected: `features/` with
  `proposed` status, task workspace, repository-root `specs/` or `docs/`.
- `spec.md` and `roadmap.md` are required; other files as needed.
- No statuses; progress is derived from roadmap checkboxes — decided by the human 2026-09-14.
- The link is the roadmap (index of task ids) plus a fixed `Spec: .ai/specs/<id>/ — Phase <n>`
  line in `task.md` — rejected: a `parent` field in state, free-text links.
- Tasks are filed per phase on explicit request and not started — rejected: filing all phases
  at once (later phases get rewritten).
- `jig spec remove` unlinks unfinished tasks, abandons unstarted ones only with
  `--abandon-unstarted`, never abandons started ones, and moves the spec to trash — rejected:
  `rm -rf` or `git rm`.
- Carrying a spec to a new project is a copy with one living copy, through guided project
  init — its own phase.
- SDD plugin techniques (three conversation phases, pressure lenses, an independent failure
  hunt, destination, fog, waves) are restated, not copied.

## Open questions

- Phase 3: what the source project keeps after a spec moves out (pointer form) without
  statuses.
- Phase 2: whether `jig-task` should warn when a task with a `Spec:` line is started before the
  items it depends on are done.

## Assumptions left untested

- The easy / normal / deep budget matches how people actually want to be questioned — tested
  by using the skill on real ideas.
- Checkbox counting survives hand-edited roadmaps — tested by `jig spec list` on specs written
  by people, not only by the skill.
