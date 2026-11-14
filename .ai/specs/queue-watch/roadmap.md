# Roadmap — Queue watch

Destination: a task put in the queue from anywhere reaches a merge or a stop that names what is
needed with nobody starting it, and the owner sees whether the watcher is alive and why it is idle.

## Phase 1 — The queue advises only what can be taken

Goal: `jig queue next` never names a task a watcher could not start now. Done when: a task with a
stopped or drafted run, a stub `task.md`, or a version bump is not advised, and a queue held by a
stop answers "blocked by <id>", not "empty".

- [ ] Next skips what cannot be taken — `queue next` (and `--json`) leaves out stopped, drafted and `not merged` runs, stub tasks and version-raising tasks, and tells "blocked by a stop" from "empty" (after: `start-follows-the-queue` — it changes the same `next` decision in `queue.sh`)

## Phase 2 — The watcher

Goal: one session drains the queue. Done when: with two tasks queued, a `/loop` session started
with the queue mode merges both or stops each with a reason, `jig status --json` shows the watcher
alive with its slots, and the stop command ends it.

- [ ] Tick and the watcher's record — one command answers start / wait / sleep / blocked / slot dead / stop from durable state, writes the watcher's record, `jig status --json` shows the `watcher` block, and a stop command ends the watcher and withdraws its "taken" records (after: Next skips what cannot be taken — the tick takes its candidates from `queue next`)
- [ ] Safeguards — a silent run is recorded as vanished and frees its slot, two runs in a row without a merge stop the watcher, one T3/T4 at a time, "blocked" reaches Telegram once (after: Tick and the watcher's record — they are answers of the tick)
- [ ] Queue mode of `jig-autopilot` — the skill drives the tick under `/loop`, runs `task ship` in the background with merges one at a time, and a docs page tells a person how to start, watch and stop it (after: Tick and the watcher's record — the skill only carries out its answers)
- [ ] Jig UI item — the `watcher` block contract and an item in `fapost-lab/jig-ui`'s spec, delivered by a pull request there (after: Tick and the watcher's record — the contract must exist)

## Waves

1. Next skips what cannot be taken
2. Tick and the watcher's record
3. Safeguards; Queue mode of `jig-autopilot`; Jig UI item

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
- A wave entry names an item by its title (the text before its first ` — `) or its task id,
  entries separated by `;` — `jig spec plan` reports an entry that names no item or several.
-->
