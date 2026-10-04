---
id: adr-20261004-a-route-stage-is-proven-by-its-record
type: adr
status: accepted
date: 2026-10-04
domains:
  - task
  - sdlc
  - skills
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - schemas/state.md
  - skills/jig-autopilot/SKILL.md
  - skills/jig-task/references/classification.md
summary: Why the completion gates refuse a task whose route skipped a stage that leaves a record (gate approval, review receipt, verify's ready), why only those records count, why tasks filed earlier are warned, why lowering a class takes a reason and resume an answer, and why there is no actor field.
---
# A stage of a task's route is proven by its record, and the completion gates refuse a route that skipped one

## Context

The class of a task decides its process (ADR-0009) — that is the product's central promise. An
external review found that the scripts did not keep it: `status ready`, `knowledge_consolidated
true` and `task ship` read only the findings ledger and the review receipt (the receipt's absence
only for T4). The gate record (`gate`, `gate_design`) was read by `jig status` alone. A T3 task
with no gate recorded shipped; `task set class T3` → `T1` passed in silence and collapsed the
route; `autopilot resume` required only `stopped`, and `stop` required no human, so an agent could
lift its own repair limit. The agent that ran the last day's T3 gates confirmed it: it recorded
every gate with `jig task gate`, and nothing ever read the record.

convention-required-records says a record resists ritual only when the machine checks it, and
adr-20261002-route-depth-is-a-personal-choice had rejected "scripts refusing a skipped stage" on
the ground that the floor was already held by the ledger, the receipt, verify and ship — which
was true for the review and false for the gate.

Two constraints bound the answer. A gate that is easy to work around is worse than none: it gives
false confidence. And a gate that an unattended run cannot pass stops the autopilot outright, so
the line between the two has to be named, not implied.

## Decision

- **Each stage of the route that leaves a record must have left it.** `_task_route_evidence_missing`
  (task.sh) walks the stages `_task_route_stages` prints for the task's class — its `full` route —
  and asks each for its record:

  | Stage | Record |
  |---|---|
  | specify, alternatives (T4) | `spec.md`, `alternatives.md` — shown at the gate, and pinned with the design by the gate's and the receipt's hash |
  | design (T3, T4) | `design.md` |
  | human gate (T3, T4) | `gate: approved` with `gate_design` equal to the current design hash |
  | review, independent review (T2, T4) | a receipt whose stages include `review` |
  | architecture review (T3) | a receipt whose stages include `architecture-review` |
  | verify | `status` `ready` or `consolidated` |
  | discover, analyze, plan, implement, consolidate | none asked |

  `status ready` (verify's sign-off) asks for everything before verify; `knowledge_consolidated
  true` and `task ship` — before it commits, and again right before a merge — ask for verify too.
  The check runs after the findings and the receipt, so their messages still come first. A
  refusal names every missing record and the command that writes it:
  `the route of <id> (T3) is missing: human gate (no approval recorded: jig task gate <id> approved)`.
  A task with no class has no route and is refused. A draft ship is not asked, as it is not asked
  for the other completion gates.
- **Absence is refused, presence still proves nothing.** ADR-0020 holds: a document on disk proves
  neither approval nor completion, and the gate does not read it as either. What is refused is the
  absence of the documents a T3/T4 gate shows — the human approves the document, not a summary in
  conversation (ADR-0031) — so a design that lives only in conversation was never shown whole.
  ADR-0020 rejected mandatory files for *every* stage; this asks for none at discover, analyze and
  plan.
- **Only records that pass convention-required-records count.** The gate approval pins the design
  and goes stale when it moves; the receipt is computed and written by the reviewer; `status
  ready` is itself a gated command. Discovery, analysis and the plan are prose the actor writes
  for itself — often legitimately in `task.md`, or already done by whoever wrote the task —
  and asking for a file would be a form to fill. Implementation's record is the diff, which ship
  already requires. The autopilot journal is not evidence: the actor writes it about itself, under
  stage names of its own choosing, and a run without autopilot has none.
- **The receipt remembers every stage.** `task receipt --stage X` writes `stages:`, the union of the
  previous receipt's stages and X, so a re-review under `review` after an architecture review
  does not erase the architecture review. A receipt without the line counts its own `stage:`.
- **The depth is not read.** The records asked for are those of the class's `full` route, so a
  person's local `route.depth` can never loosen a gate, and the route-depth ADR's rule — nothing
  that gates reads the depth — holds as written. `lean` trims only stages that leave no record (the
  plan; a second review round), so a lean and a full run are asked the same records; a depth that
  ever trimmed a recorded stage would be refused here rather than let through.
- **A task filed before this check is warned, not refused.** `jig task new` writes
  `route_evidence: required`. A task without the key began its route under the old rules — a T2
  receipt, for one, was optional — so the gates print the same list as `jig: warning: … passes
  without: …` and pass. No task in flight is stopped halfway; the gap it leaves is visible in its
  output. Nothing is configured: the key is written by the script and `task set` refuses it.
- **Lowering a class takes a reason, and is shown where the gate is.** Re-classification stays
  normal (ADR-0009, AGENTS.md); lowering is the direction that sheds stages, so `jig task set <id>
  class <lower> --reason <text>` is required for it and records `class_lowered_from` (the highest
  class it came from) and `class_lowered_reason`. `jig task route`, `jig status` (`lowered=Tn`), the
  status page and the autopilot report (in the pull request) show it; raising back clears it.
  What separates a lowering from a bypass is that a bypass is silent and a lowering leaves its
  reason where the person reads. Where nobody answers — the clone sets `autopilot.unattended`, or
  the task's run was started unattended and is `on` or `stopped` — a T3/T4 task is not lowered below
  T3: nobody there can read the reason before the gate is gone, and keeping the class is the
  cautious, reversible choice.
- **No actor field.** A shell script cannot tell who called it, and a field the actor writes about
  itself is self-certification. Independence of a review rests on what is already there: a fresh
  context, findings entered by the reviewer, a receipt nobody fills in. `gate_by` stays the one
  actor claim, and it is kept honest at the one place the script can see: `--by agent` is refused
  outside an unattended run, and an approval without it is refused inside one.
- **`resume` quotes the human's answer, and an unattended run never resumes.** `jig task autopilot
  <id> resume --answer <text>` is required; the answer is journaled and the report prints it under
  "Resumed on an answer (check it was yours)", so a run that resumed itself quotes an answer
  nobody gave where the person reads it. In an unattended run `resume` is refused: nobody answers
  there, and its repair-limit stop ends the run in a draft. Nor does such a run `end` before its
  knowledge decision is recorded, so `end` then `start` cannot hand it two fresh repairs.

**The boundary, stated.** The mechanics guarantee that no stage with a record was skipped. They do
not guarantee that a human approved: in an unattended run the gate is passed by the agent's own
`--by agent` approval (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci), still a record
that pins the design, with the design verbatim in the pull request. What an unattended run cannot
do is lower a task out of the gate, record its own approval as a human's, or reset its own repair
limit by `resume` or by `end` and `start`. In an attended run the approval and the answer are claims
a person can contradict, made where that person reads. A hand-edited state file is outside what any
of this claims: the scripts check records, not the filesystem's honesty.

## Alternatives

- **The autopilot journal as the record of a stage.** Written by the actor about itself, free stage
  names, absent outside autopilot — ritual by the convention's test.
- **Every document `_task_artifact_route` lists.** `discovery.md` and `plan.md` are often
  legitimately absent (a written task, the analysis in `task.md`); the gate would refuse honest
  runs and teach agents to write empty files.
- **Judging tasks filed earlier by the new rules.** Breaks T2 tasks in flight whose receipt was
  optional when they started.
- **Telling old tasks apart by `created_at`.** A date does not say which version filed the task.
- **Forbidding a lower class.** Contradicts ADR-0009 and AGENTS.md: re-classification is normal.
- **An actor field on findings, receipts and gates.** Self-certification; nothing can check it.
- **Letting an unattended run resume once.** The repair limit would again be lifted by the run it
  limits.

## Consequences

- A T3 task cannot reach `ready` without an approval that matches its design and an architecture
  review receipt; a T2 cannot without a review receipt; nothing is consolidated or shipped before
  verify's sign-off.
- Test fixtures that file a task and jump to the end now classify it and sign verify off first
  (`task_route_class`, `task_route_done` in tests/lib/assert.sh).
- `task set` takes `--reason` for a lower class; `autopilot resume` takes `--answer`. A caller on the
  old syntax gets a refusal that names the new one.
- The status record gained one field (`class_lowered_from`).
- Undoing it: revert. The `route_evidence` and `class_lowered_*` keys and the receipt's `stages:`
  are then read by nothing and harmless.

This refines ADR-0009 (the route is enforced, not only announced) and ADR-0020 (absence of a
gate's documents is refused; presence still proves nothing), amends
adr-20260921-review-receipt-pins-what-was-reviewed (a T2 and a T3 task now need a receipt, the
alternative it rejected, and a rewrite carries `stages:` over), amends
adr-20261002-route-depth-is-a-personal-choice (its rejected alternative "scripts refusing a skipped
stage" is now taken, for the stages that leave a record, without reading the depth) and
adr-20260921-autopilot-runs-a-task-to-its-stops (`resume` needs an answer, and an unattended run has
none).
