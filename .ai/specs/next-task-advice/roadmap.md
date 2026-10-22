# Roadmap — Next task advice

Destination: an agent or a person asks Jig what to take next and gets an answer from the queue.

## Phase 1 — Advice

Goal: an agent, a person and Jig UI ask what to take next and get one answer. Done when
`jig queue next` advises by the decided rules, `jig status` shows it, and an agent asked
"what next" takes its answer.

- [x] `priority-scale` — priority scale — what `0`–`5` mean, written in the glossary and the queue docs page, so a person and an agent set "bugs first" the same way (after: nothing — it describes what 0.31.0 already stores)
- [x] `queue-next` — queue next — `jig queue next [--json]`: candidates, dependency landed or broken or unknown, priority, started-first tie-break, position across levels by the top-level item, `none` last, a count of unqueued tasks, and the reason when nothing can be advised; documented on the queue pages (after: priority-scale — it orders by that scale)
- [ ] next in status — `jig status` shows the advice as one `next:` line, and the status page beside it (after: queue next — it prints its answer)
- [ ] agents ask for the next task — the `jig-task` skill asks `jig queue next` when a person says "what next" or "take the next one", instead of choosing itself (after: queue next — it is what they ask)

## Waves

1. Priority scale (done).
2. Queue next.
3. Next in status; agents ask for the next task.

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
-->
