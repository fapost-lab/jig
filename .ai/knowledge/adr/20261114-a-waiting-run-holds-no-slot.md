---
id: adr-20261114-a-waiting-run-holds-no-slot
type: adr
status: accepted
date: 2026-11-14
domains:
  - task
  - skills
  - scripts
paths:
  - scripts/lib/task.sh
  - scripts/lib/queue.sh
  - scripts/lib/status.sh
  - scripts/lib/common.sh
  - schemas/json.md
  - schemas/state.md
  - "skills/jig-autopilot/**"
summary: Why an autopilot run stopped for a person holds no autopilot.parallel slot, why the answer is recorded apart from the resume (task autopilot answer), why answered runs resume first on a free slot without preemption, and what jig status and jig queue next show of them.
---
# An autopilot run stopped for a person holds no slot; the person's answer is recorded apart from the resume, and an answered run resumes on the next free slot before any new task

## Context

A run over a set of tasks (`jig-autopilot` §7) started each next task as a slot of
`autopilot.parallel` freed, but the slots were counted by the agent, and a stop held the whole set:
the agent asked and waited, while every other task the person named stood still. The answer and the
resume were one command, `resume --answer`, so an answer could only arrive in the session that was
waiting, and the answer-stop action of the status page and Jig UI set a run `on` that nobody ran.
The question itself was visible only on the status page, quoted after an age. The queue-watch spec
session (2026-11-14) settled the rules with the owner: a waiting run frees its slot, an answered run
resumes before new tasks with no preemption, a task depending on a waiting one is not taken, and
there is no limit to how many runs may wait — a limit would bring the stop back.

## Decision

- **A `stopped` run holds no slot.** A slot is held by a run that is `on` with its knowledge not
  consolidated, one predicate for every reader (`jig_autopilot_building`, common.sh): `jig spec
  plan`'s per-wave `parallel` row (which already counted so) and `jig queue next`'s `slots:` line,
  which counts across the clone — one machine, one person, the same reason the key is local-only. A
  paused run that is still `on` keeps its slot; that is the pause's business, not this one's.
- **The answer is recorded, not acted on.** `jig task autopilot <id> answer --answer <text> [--by
  human]` writes an `answer` journal line and `autopilot_answered` (UTC), with the refusals of
  `resume` (`--by human` for an unattended run, refused at the repair limit). The run stays
  `stopped`; `jig status` marks it `autopilot=answered`. Answering again replaces the answer.
- **Whoever has a free slot resumes it.** `resume` without `--answer` takes the last recorded answer
  into its `resume` line, so the report's "Resumed on an answer" is unchanged; an unattended run
  needs no `--by human` there, since the person's form already wrote the answer. Every resume and a
  handover clear `autopilot_answered`. `resume --answer` works as before.
- **Answered runs first, never by preemption.** `jig queue next` lists them under `resume first:`
  (`--json` `resume`): every active task in the clone whose run is answered and not held by another
  session, by queue priority (none last), then the earlier stop, then the id. They are not
  `in_progress`. `next`, `reason` and the order `task start` enforces (`Q_AHEAD`) do not change: the
  coordinator resumes them before starting `next`, on a free slot, and the skill says so.
- **A dependency on a waiting task reads `waiting`.** It was already not finished, so the dependent
  was already held; the new state names why instead of sending the person to `jig housekeeping`.
- **`jig status` gathers the questions.** A `waiting for you:` block lists every unanswered stopped
  run — phase-run tasks and runs at their repair limit marked — with the journal's last stop reason
  word for word, and the command to answer it. The terminal form shows it once, under Needs you; the
  task line's `autopilot=stopped` alone no longer makes a second item. The `autopilot-stopped`
  attention item gains `question` and `stopped_at`, says the answer command, and an answered run is
  no item. The actions table's `answer-stop` now runs `answer`, not `resume`.

## Alternatives

- **A new `autopilot` value `answered`**: every reader of `stopped` (end, handover, the gate, the page)
  would need it; a separate key keeps them as they are.
- **Resume on the answer, as before**: the run turns `on` with nobody to run it, and takes a slot
  ahead of the queue — the preemption the owner ruled out.
- **Advise the answered run as `next`**: `next.started` is a contract read as always false, and
  `task start` reads the same order; a separate list keeps both.
- **Slots per set**: the set has no store, and the agents of two sets share one machine.
- **A limit on waiting runs**: the owner's decision — it would stop the set again.

## Consequences

- A set run goes on while its questions wait, and the person answers them in one go from any
  runtime. Starting each task in a session of its own is the next task
  (`session-per-autopilot-task`), not this one.
- `jig queue next --json` gains `resume`, `slots` and the `waiting` state; `jig task list --json`
  `autopilot.answered_at`; `jig status --json` `question` and `stopped_at`. Jig UI reads them.
- `autopilot.parallel` is still not enforced by `task start`; the coordinator reads `slots:`.

This amends adr-20260921-autopilot-runs-a-task-to-its-stops (a stop no longer holds a set run),
adr-20261013-human-answer-resumes-stopped-unattended-run (the answer may be recorded first),
adr-20261022-the-next-task-is-advised-from-the-queue (`resume`, `slots`, `waiting`) and
adr-20260922-a-phase-run-is-coordinated (the slot predicate is shared).
