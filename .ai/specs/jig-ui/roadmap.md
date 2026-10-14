# Roadmap — Jig UI

Destination: a person with several Jig projects opens one local page, sees every task and epic of
every project, orders and prioritises them, and files new tasks — and Jig works exactly as before
when that page is not installed.

## Phase 1 — Jig can be read by a program

Goal: everything the UI shows is available from Jig as data, with no text parsing. Done when each
command below prints stable JSON, the shapes are documented, and a contract test pins each one.

- [ ] task list as JSON — every task of a clone: class, status, gate, autopilot, branch, worktree, pull request, housekeeping flags
- [ ] spec and epic list as JSON — specs with phases and items, progress, epic branch, release level (after: task list — same envelope and conventions)
- [ ] attention items as data — what needs a person, using the logic behind the status page rather than a second copy of it
- [ ] legal human actions per task state — Core says what a person may do next; the UI never decides (after: task list — actions are read from a task's state)

## Phase 2 — The queue

Goal: priority, order and dependencies exist in Jig and agents can read them. Done when
`jig queue` orders tasks and epics, a stale write is refused, and `jig status` shows the order —
all without the UI.

- [ ] queue file and commands — one file per clone beside `.ai/runtime/`, not under git; priority 0–5, sparse position (step 100), dependencies with a reason, epics as a level; atomic write checked against a revision the caller read
- [ ] queue in status and context — `jig status` and `jig context` show a task's place (after: queue file — they read it)
- [ ] queue as JSON (after: queue file; task list — the UI reads both together)
- [ ] fog: next task by priority, order and dependencies — how an agent or a person is advised what to take is not stated yet

## Phase 3 — Read-only UI

Goal: the page exists and tells the truth. Done when a person connects two projects, sees both on
a workspace page and on a board per project, edits a task through an agent, and the page follows
without a reload; stopping the UI changes nothing in either project.

- [ ] prototype and stack choice — one local command, no native dependencies; checks Node + Vue and SSE against a small clone before the choice is recorded (after: Phase 1 — it needs real data)
- [ ] project registry and connect — manual connect, optional idempotent registration by `jig init`, path and slug rules (after: prototype — the registry is its first part)
- [ ] workspace dashboard and project board — columns derived from Jig status, no stored board column (after: registry; Phase 2 queue as JSON — ordering)
- [ ] task details — status, stage, gate, artifacts, dependencies, attention
- [ ] file watching with a periodic rescan — whole `.ai/workspace`, not a few files

## Phase 4 — Planning from the UI

Goal: the page changes things, only through Jig. Done when a drag, a priority change and a new
task all land through Jig commands, and a concurrent change by an agent shows as a conflict
instead of being overwritten.

- [ ] reorder and prioritise by drag (after: Phase 2 queue; Phase 3 board — writes go through `jig queue` with the revision)
- [ ] pause and resume as a request — a drop on the paused column writes a request through Jig; the request is sticky and kept in the queue file; the agent finishes its current step, stops at the next boundary without starting another and clears the request; the card shows "requested" with its age and a cancel until then (after: legal actions per state — they say when a pause is offered)
- [ ] file a minimal backlog task from the page (after: board — through `jig task new` with a short description)
- [ ] conflict display (after: reorder — the refusal from a stale revision is what it shows)

## Phase 5 — Further

- [ ] fog: remote access and a hosted view — first form is a read-only snapshot with a revision; authentication and file access rules are not stated
- [ ] fog: installation for people without a development environment, Windows first
- [ ] fog: epic and spec planning from the page

## Waves

1. Phase 1 items (parallel, at most two at a time); queue file.
2. Queue in status and context; queue as JSON; attention items and legal actions.
3. Phase 3 (new repository).
4. Phase 4.

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
-->
