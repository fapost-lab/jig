---
id: adr-0027-metrics-are-derived-not-stored
type: adr
status: accepted
date: 2026-09-11
domains: []
paths:
  - scripts/lib/measure.sh
  - scripts/lib/housekeeping.sh
summary: Why measurement is derived on demand rather than stored, and why the purge line records what outlives the task.
reviewed_at: 2026-09-11
---
# ADR-0027: Measurement is derived on demand, and the purge line is what outlives the task

## Context

Phase 6 was deferred from §40 of spec 0.3 with one constraint — no telemetry in the MVP —
and no content. §40 predates this repository: the first commit already carries spec 0.4
with the section removed, so nothing about the intended metrics is recoverable. The phase
table asked for "benchmarking, cost measurement, knowledge quality", and the design had to
establish what each of those can honestly mean here.

Three facts about the framework bound every option.

Scripts never call an LLM (ADR-0001), so the only component that can count is the one
component that cannot see a stage happening. The agent knows it ran `implement`; nothing
writes that down. Which stages ran, how long each took, how many sessions a task needed
and whether a human gate was passed have no trace anywhere.

Cost has no source. Tokens, turns and wall-clock effort are not recorded, and recording
them would need exactly the telemetry the spec forbids.

And the task workspace is designed to be destroyed (ADR-0006). Any measurement whose only
source is `.ai/workspace/tasks/<id>/` has a lifetime of `trash_ttl` days, which is not a
trend.

Meanwhile a great deal is already computed and thrown away: `knowledge check`,
`knowledge stale` and `knowledge paths` measure knowledge quality on every run;
`base_commit` (ADR-0026) makes a task's change size computable from git; and housekeeping
already derives whether work landed, uses the answer for one decision and discards it.

## Decision

- **`jig measure` derives its report when asked, and stores nothing.** Its sources are
  knowledge frontmatter, task `state`, git history, and `.ai/runtime/housekeeping.log`.
  There is no metrics file, no series, no collection step and no daemon. This is the bet
  ADR-0005 already made for remote merge state: a fact that must be true *now* is cheaper
  to derive than to keep correct forever.
- **The purge line is the point of record.** A workspace leaves through exactly one gate,
  `_hk_purge`, which already writes an append-only line that outlives it. That line gains
  the task's own `class=`, `created=` and `consolidated=`. A value the state file does not
  carry is omitted rather than defaulted, so a reader can tell "this task had no class"
  from "this line predates the field"; neither is read as `T0`.
- **"Cost measurement" is delivered as process weight against change size.** The report
  says how much process a change asked for (its class) and how large the change turned out
  to be (commits, files, lines, days from fork to tip). It does not claim to price the
  work, and the product specification was corrected to promise what can be delivered
  (that document has since been retired; see ADR-0028).
- **"Benchmarking" means the process, not the scripts.** Reclassification, outcomes and
  the spread of classes are what the framework can be judged on. Script runtime stays a
  task-level measurement, taken when it matters (ADR-0013, `fewer-spawns-on-install`).
- **The report names its own blind spots in its own output.** Every number it prints is a
  proxy, and a reader who never opens the documentation is still told that stage timing,
  session count and cost are recorded nowhere.
- **Measurement stays per-developer.** The log lives in `.ai/runtime/`, which is never
  committed (RULES.md). The half of the report that comes from git is identical for
  everyone anyway, because it grows out of the repository's own history.
- **Numbers must not depend on the machine that printed them.** Git reads pin
  `--no-renames` rather than inheriting `diff.renames`, and day counts floor towards minus
  infinity so a stale fork point cannot read as "finished the same day".

## Alternatives

- **Instrument the stages: `jig task event <stage>`, written by each skill.** Rejected. It
  buys the most interesting numbers with claims nothing can check, which is the distinction
  ADR-0020 already drew for artifact inputs, and it taxes every skill's context (§3.4) for
  a fact no reader can verify. Inferring stage completeness from artifact presence was
  rejected for the same reason: presence is evidence a file exists, not that a stage ran.
- **Persist a metric series in git (`.ai/metrics/`).** Rejected. It commits derived data,
  conflicts on every branch, needs a new fixed path, and has to be kept correct forever —
  the cost ADR-0005 avoided.
- **Persist to `.ai/runtime/metrics/`.** Rejected. The same storage cost for data that is
  per-developer and gone on a fresh clone regardless, in a directory where the housekeeping
  log already occupies the niche for free.
- **Telemetry for real cost.** Rejected by the product specification before its
  retirement, and by the reason
  behind it: a project-owned framework that phones home stops being project-owned.
- **Record the facts on every housekeeping decision rather than only on purge.** Rejected:
  a preserved task is re-reported on every run, so its attributes would be rewritten daily
  into a log nothing rotates. The purge is the only moment the information is about to be
  lost.
- **Do nothing; keep the qualitative assessment §33 left in place.** Rejected: knowledge
  quality is already computed and merely unaggregated, so the status quo discards work
  already paid for.

## Consequences

- The housekeeping log becomes an interface with a second consumer. `jig status` reads
  only the newest `--- run` block; `jig measure` reads the whole file as history. Its line
  shape can no longer be changed freely, and **nothing rotates it** — a log that was
  previously incidental is now load-bearing and grows without bound. Retention for it is an
  open question this decision creates and does not answer.
- Measurement starts now, not retroactively. A task needs `base_commit` (ADR-0026) and a
  surviving branch before its change can be sized, so every task created before that
  decision is permanently unmeasurable. The report states for how many tasks it could
  answer rather than quietly averaging the ones it could.
- Housekeeping now copies task-owned fields into its own log. It still never writes a task
  `state` file (ADR-0005), and the fields are read before the workspace moves — but the
  `task` domain now has a second reader of its schema, and a field renamed there silently
  empties a column here.
- The framework can be argued with using numbers. The first run over this repository found
  twenty-seven tasks and not one classified `T0` or `T1`, which is either a rubric that
  runs high or cheap work that never becomes a task. Nobody had noticed.
