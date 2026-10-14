# Roadmap — Contract extensions

Destination: a program can read every task, spec and epic of a clone as data, and priority, order,
dependencies and pause requests live in Jig, written by one command that refuses a stale write.

## Phase 1 — Jig can be read by a program

Goal: what a tool needs to know about a clone is available as data, with no text parsing. Done
when each item below prints stable JSON, the shapes are documented, and a contract test pins
each one.

- [ ] task list as JSON — every task of a clone: class, status, gate, autopilot, branch, worktree, pull request, housekeeping flags
- [ ] spec and epic list as JSON — specs with phases and items, progress, epic branch, release level (after: task list — same envelope and conventions)
- [ ] attention items as data — what needs a person, from the logic behind the status page rather than a second copy of it (after: task list — same envelope)
- [ ] legal human actions per task state — Jig says what a person may do next (after: task list — actions are read from a task's state)
- [ ] stable failure codes — each refusal names a code that a tool can act on

## Phase 2 — The queue and requests

Goal: priority, order, dependencies and pause requests exist in Jig and agents honour them. Done
when `jig queue` orders tasks and epics, a stale write is refused, `jig status` shows the order,
and a pause request stops a running task at its next stage boundary.

- [ ] queue file and commands — one file per clone beside `.ai/runtime/`, not under git; priority 0–5, sparse position (step 100), dependencies with a reason, epics as a level; atomic write checked against a revision
- [ ] queue in status and context — `jig status` and `jig context` show a task's place (after: queue file — they read it)
- [ ] queue as JSON (after: queue file; task list as JSON — read together)
- [ ] pause and resume requests — sticky, kept in the queue file, honoured at the next stage boundary and cleared by the same command (after: queue file — the request lives there; legal actions — they say when a pause is offered)
- [ ] fog: next task by priority, order and dependencies — how an agent or a person is advised what to take is not stated yet
- [ ] fog: registration hook in `jig init` for an installed UI

## Waves

1. Task list as JSON; queue file and commands.
2. Spec list, attention items, legal actions, failure codes; queue in status and context.
3. Queue as JSON; pause and resume requests.

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
-->
