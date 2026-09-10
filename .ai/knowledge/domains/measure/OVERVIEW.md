---
id: domain-measure
type: domain
status: active
summary: What jig measure derives, why it stores nothing, and the rules that keep its numbers honest.
domains:
  - measure
topics: []
load: domain
paths:
  - scripts/lib/measure.sh
  - tests/measure.t.sh
reviewed_at: 2026-09-11
---
# Measure

Counting what the framework did, without ever asking an LLM and without collecting
anything. The domain is one command, and almost all of its difficulty is in one property:
it prints numbers that a reader will treat as facts, from sources that were never built
to be measurements.

## Responsibility

- Deriving the Phase 6 report on demand: knowledge quality, the distribution of task
  classes and their outcomes, and the size of the change each class produced (ADR-0027).
- Saying, in the report's own output, what it cannot see. Stage timing, session count and
  the cost of agent work are recorded nowhere, and the `blind spots:` line exists so a
  reader who never opens the documentation is still told.
- Reading the purge lines of `.ai/runtime/housekeeping.log` as the history of tasks whose
  workspace no longer exists.

## What governs it

- **Derived, never stored** (ADR-0027). No metrics file, no series, no collection step.
  A number that has to be kept correct forever is a number that will be wrong.
- **An absent fact is never a zero.** A task with no class is `unclassified`, and a purge
  line written before the field existed is `unclassified` too — never `T0`. The cheapest
  class must not be inflated by work nobody classified.
- **A number must not depend on the machine that printed it.** Git reads pin
  `--no-renames` rather than inheriting `diff.renames`; day counts floor towards minus
  infinity so a stale fork point cannot read as "finished the same day". This is
  convention-shell's "do not inherit the environment", applied to arithmetic.
- **The report consumes other commands, it does not reimplement them** (ARCHITECTURE.md,
  reporting commands). `knowledge` owns "how many documents are stale"; a second
  implementation here is how the two come to disagree invisibly.
- **Measurement begins at ADR-0026.** Sizing a change needs the recorded `base_commit` and
  a surviving branch, so tasks created before branch-per-task are permanently unmeasurable.
  The report states for how many tasks it could answer instead of averaging what it has.

## Boundaries

Outside: what any number *means* for the project. This domain computes; deciding that a
class distribution with no `T0` indicates a rubric running high is the reader's judgement,
and belongs in a conversation or an ADR, never in a threshold inside `measure.sh`.

Outside: the housekeeping log's own lifecycle. This domain reads it; `housekeeping` writes
it and owns its shape — including the purge line's task fields, which exist for this
consumer but are produced there.

Outside: `jig status`. It answers "what is going on right now" and is cheap enough for a
session hook to run; `measure` walks git history for every task and is deliberately not on
that path (ADR-0027).

## Entry points

- `scripts/lib/measure.sh` — `cmd_measure`, then one function per section:
  `_measure_knowledge`, `_measure_collect_tasks`, `_measure_process`, `_measure_change`.
  The two helpers worth knowing before editing are `_measure_num` (pulls counts out of
  another command's summary line) and `_measure_floor_days`.
- `tests/measure.t.sh` — every number is asserted exactly, because the whole report is a
  pure function of the repository. That is what lets a measurement command exist without
  an LLM (ADR-0001).

## Known gap

Nothing rotates `.ai/runtime/housekeeping.log`, and this domain is the reason it now has
to be kept. A retention rule for it is an open question ADR-0027 created and did not
answer.
