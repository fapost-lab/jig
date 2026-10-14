# Roadmap — Contract queue

Destination: priority, order, dependencies and pause requests live in Jig, written by one command
that refuses a stale write, and agents honour them.

## Phase 1 — The queue and requests

Goal: priority, order, dependencies and pause requests exist in Jig and agents honour them. Done
when `jig queue` orders tasks and epics, a stale write is refused, `jig status` shows the order,
and a pause request stops a running task at its next stage boundary.

- [ ] queue file and commands — one file per clone beside `.ai/runtime/`, not under git; priority 0–5, sparse position (step 100), dependencies with a reason, epics as a level; atomic write checked against the clone revision; a reorder moves one item
- [ ] queue in status and context — `jig status` and `jig context` show a task's place (after: queue file — they read it)
- [ ] queue as JSON (after: queue file — it is what is read; contract-extensions' task list — read together, same envelope)
- [ ] pause and resume requests — sticky, kept in the queue file, honoured at the next stage boundary and cleared by the same command (after: queue file — the request lives there; contract-extensions' legal actions — they say when a pause is offered)
- [ ] fog: next task by priority, order and dependencies — how an agent or a person is advised what to take is not stated yet

## Waves

1. Queue file and commands.
2. Queue in status and context; queue as JSON; pause and resume requests.

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
-->
