---
id: adr-20261108-a-person-takes-over-a-stopped-run
type: adr
status: accepted
date: 2026-11-08
domains:
  - task
  - skills
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - scripts/lib/notify.sh
  - schemas/state.md
  - schemas/json.md
  - skills/jig-autopilot/SKILL.md
summary: Why a person ends a stopped autopilot run with handover --by human --answer, why the run ends (done) rather than turning attended, why no run starts after it, and what it does not waive.
reviewed_at: 2026-11-08
---
# A person takes a stopped autopilot run over, and the run ends there

## Context

A `stopped` run had one way on: `resume`. An unattended run at its repair limit had none, by
design (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci,
adr-20261013-human-answer-resumes-stopped-unattended-run): it ends in a draft. On 2026-11-07
`profile-covers-check` stopped there: an unattended T3 run had approved its own gate, used both
repairs on review findings, and stopped when `jig verify` turned red. Its design changed after that.
Then a person came. They answered and approved the current design, and every command that could
have recorded it refused:

- `task gate approved`: the stopped unattended run "exhausted its unattended repair limit".
- `resume --by human`: the limit.
- `start`: the limit.
- `end`: "no active autopilot run".
- `task ship`: the stale gate. It also shipped at `autopilot.git`.

The coordinator finished the task by hand. The whole time, the status page and `jig status` said the
task was waiting for the person. An attended run that a person finishes by hand has the same
problem: `end` needs `on`, so the stop card never leaves.

Every refusal comes from one predicate. A run that is `stopped` and `unattended` is "where nobody
answers" (`_task_run_unattended`), and nothing ever took a run out of `stopped` except `resume`.

## Decision

- **`jig task autopilot <id> handover --by human --answer <text>`** ends a `stopped` run, whatever
  its mode, and whether it stopped at the limit or before it.
  - It writes `autopilot: done` and a script-owned `autopilot_handover: <UTC time>`.
  - It journals `handover` with `human: <answer>` and sends the event to Telegram (mark `👤`).
  - It leaves `autopilot_mode` and `autopilot_repairs` as they were, because they record what the
    run was.
  - It refuses a run that is `on`: the person asks the agent to `stop` first. It also refuses a run
    that is `done` or never existed.
  - `--by human` and a non-empty single-line `--answer` are required, the same convention as the
    unattended `resume` (adr-20261013-human-answer-resumes-stopped-unattended-run).
- **The run ends; the task goes on without autopilot.** The run has left `stopped`, so:
  - `task gate approved` is the person's again (`gate_by: human`), and `--by agent` stays refused.
  - `task ship` goes by `agent.git`, not `autopilot.git`.
  - `jig status` prints `autopilot=handed-over`, which is a fact and not attention.
  - The stop card goes from the status page. A design that changed still shows its gate card, and
    the task's row shows "taken over by a person".
- **No fresh run after a handover.** `start` is refused while `autopilot_handover` is set, whichever
  mode the clone has now. Otherwise `handover` then `start` would hand an unattended clone two
  repairs nobody granted: the `end`-then-`start` hole that
  adr-20261004-a-route-stage-is-proven-by-its-record closed. `repair`, `stage`, `stop` and `end`
  refuse, because there is no run.
- **What it does not waive.** A handover approves no design and records no review. A design that
  changed is `changed` until the person approves it. The receipt pins the design hash, so it needs a
  re-review. The completion gates — findings, receipt, route evidence, the knowledge decision — are
  asked as for any task. A run nobody takes over still ends in a draft.
- **The refusals name the new road.** At the limit, `start`, `gate` and `resume` say "ship a draft, or,
  if a person takes the task on: jig task autopilot <id> handover --by human --answer <text>". The
  same text is the `answer-stop` row's reason. `end` on a stopped run names `handover`. At the
  limit, the stop card says that nothing resumes the run.
- **A row of its own.** `handover` joins `_task_actions`
  (adr-20261015-one-table-of-what-a-person-may-do) after `answer-stop`. It is offered on a `stopped`
  run and asks `_task_autopilot_handover_refusal`, the command's own guard. A new id is a compatible
  change.
- **`report` quotes it.** The report prints the block "Taken over by a person (check it was yours)",
  and its summary line says `done (handed over)`. The skill copies the block into the pull request.

**The boundary.** A shell script cannot tell a person from an agent
(adr-20261004-a-route-stage-is-proven-by-its-record: no actor field). An agent that fabricates a
handover gains a gate recorded as the person's, and a way out of the draft-only ending: at
`agent.git: merge` that way out can be a merge. It gains no repairs. The claim is exposed in four
places: the journal line with its `human:` marker, the report block in the pull request, the
Telegram message sent the moment it happens, and the status page. The skill forbids a handover the
person did not ask for, in their words. The maintainer chose this level of trust at the gate
(2026-11-08). It is the same trust an attended gate approval carries, and that approval also leads
to a merge at `agent.git: merge`.

## Alternatives

- **`end --by human` accepting a stopped run.** Almost the same mechanics, but `end` already means
  that the run reached the end of its route. Its reason says how the run ended, its Telegram message
  says "ended", and an unattended `end` waits for the knowledge decision. One verb with two meanings
  would still need its own marker against `end`-then-`start`.
- **Switching the run to attended.** adr-20261013-human-answer-resumes-stopped-unattended-run rejected
  this already: the recorded mode would stop explaining the run. An attended `resume` also resets the
  repair count, and that would be a third repair. This decision does not switch the mode: the run
  ends, and the work that remains is not a run.
- **`resume --by human` at the limit.** That is a third repair.
- **Allowing only `gate approved --by human` in a stopped unattended run.** It would fix one road of
  six. The ship would stay at `autopilot.git`, and the page would keep saying "waiting for you".
- **A fourth run state (`handed-over`).** Every reader already treats an unknown value as "not
  running", but the schema, the JSON and Jig UI would all carry the new state, and undoing it would
  leave tasks in that state. `done` plus a key leaves an inert key behind.
- **A terminal check, like `jig notify setup`.** It would cut off Jig UI's button and the
  coordinator who relays the person's words from chat. A terminal check guards a secret there, not a
  claim.
- **Capping the ship at `pr` after a handover at the limit.** Safer against a fabricated handover,
  but the person would have to merge by hand on the forge. Rejected at the gate in favour of
  visibility.

## Consequences

- A stopped run that a person takes on stops claiming to wait for them, and the gate, the ship level
  and the page follow the person.
- Undoing this is cheap: remove the verb, the row, the key, the notification event and the
  paragraphs in the skill and the docs. A task that was handed over keeps `autopilot: done` and an
  inert key.

This amends adr-20260921-autopilot-runs-a-task-to-its-stops (a run's actions),
adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci (the draft ends a run *nobody takes
over*), adr-20261004-a-route-stage-is-proven-by-its-record (`end` and `start`),
adr-20261013-human-answer-resumes-stopped-unattended-run (the alternative it rejected is not
reopened: the run ends rather than switching), adr-20261015-one-table-of-what-a-person-may-do
(the `handover` row), and extends adr-20261009-autopilot-stops-reach-telegram (a fifth event,
`handover`, with its mark `👤`).
