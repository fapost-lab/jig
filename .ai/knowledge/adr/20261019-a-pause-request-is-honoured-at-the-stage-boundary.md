---
id: adr-20261019-a-pause-request-is-honoured-at-the-stage-boundary
type: adr
status: accepted
date: 2026-10-19
domains:
  - task
  - scripts
paths:
  - scripts/lib/queue.sh
  - scripts/lib/task.sh
  - scripts/lib/common.sh
  - schemas/json.md
  - skills/jig-autopilot/SKILL.md
  - scripts/lib/context.sh
  - skills/jig-task/SKILL.md
summary: Why a pause request is a request line of the queue file written by jig queue request|cancel, honoured where a stage begins — by jig task autopilot stage and by jig context resolve --task --stage through jig task pause --if-requested (exit 4, request taken out before the pause is set, run stays on) — and by jig task pause, and why there is no resume request.
reviewed_at: 2026-10-21
---
# A pause request lives in the queue file and is honoured where a stage begins — `jig task autopilot <id> stage`, and `jig context resolve --task <id> --stage <stage>` — which pauses the task instead of entering the stage

## Context

The contract-queue spec settled with the maintainer (2026-10-14) that a pause request is sticky: it
holds until honoured or cancelled, whatever stage the task reaches in between; the agent finishes
the step it is on, does not start another stage, sets the pause field (ADR-0012) and clears the
request in the same Jig command; the request lives in the queue file, whose one writer is `jig
queue` (adr-20261019-the-queue-is-one-file-written-against-a-revision). Its consumer is Jig UI's
Phase 2: a drop on the paused column writes a request, and the card shows "requested", its age and
a cancel until Jig's state changes.

The spec left one assumption untested: that a running autopilot or agent reads anything at a stage
boundary where a request can be honoured. Checked against the code, it does not: `jig task
autopilot <id> stage <name>` checked only that the run was `on` and appended a journal line. But it
is the one Jig command an autopilot run must call on entering every stage (jig-autopilot §2), so it
is the stage boundary Jig can see. A session working without autopilot calls no command there.

(Amended 2026-10-21, task `pause-request-without-autopilot`.) It does: every stage skill's first
step is `jig context resolve --task <id> --stage <stage>` — `jig-analyze`, `jig-implement`,
`jig-review`, `jig-architecture-review`, `jig-verify`, `jig-consolidate`, and `jig-task` for the
first stage of a route — with or without autopilot. The session hook Jig installs runs once, at
`SessionStart`, and prints nothing into the session; the receipts, the gate and `status ready` are
written at the end of a stage, not at its entry.

## Decision

- **The record is a `request` line of the queue file**: `request <ref> <kind> <requested_at>
  <reason>`, tab-separated. `<ref>` is a `task:<id>` (an epic is not paused), `<kind>` is `pause`,
  `<requested_at>` UTC to the second, `<reason>` one line or empty. One request per reference and
  kind. The queue's format stays `1`: the writer before this kept unknown line kinds as they are,
  reserved for this. The writer prints requests after the dependencies, ordered by reference and
  kind. A request is independent of the task's item: a task need not be queued to be asked, and
  `remove` does not take its request.
- **Two queue writes, `jig queue request <ref> pause [--reason <text>]` and `jig queue cancel <ref>
  pause`**, with `--revision` and `--json` like every queue write and the same claim. `request`
  refuses `already-exists` for a pending request (its time is what the card shows, so it is never
  reset), `failed` for a task that is paused, `consolidated` or `abandoned`, `not-found` for no such
  task, `usage` for an epic or another kind. `cancel` takes any well-formed reference and refuses
  `not-found` when there is nothing to cancel. The state condition is one guard in `common.sh`
  (`jig_pause_request_refusal`, `jig_pause_cancel_refusal`), which the actions table asks too, with
  the path of the queue file (`jig_queue_file`): `task` reads the queue and may not source
  `queue.sh`.
- **`jig task autopilot <id> stage <name>` honours it.** A paused task enters no stage: exit 4.
  A pending request is taken out first, by running `"$JIG_SELF" queue cancel task:<id> pause` —
  the queue's one writer, as a process (ARCHITECTURE.md) — and only then is the task paused
  (`paused`, `paused_at`, `paused_reason: pause requested at <time>[: <reason>]`), the journal
  given a `pause` line instead of the stage, and the command ends with exit 4. A cancel that finds
  nothing (cancelled in between) lets the stage start; one refused as stale is read again, up to
  three times, without a wait.
- **The run stays `on`.** A pause is not a stop: a stop waits for an answer and locks an
  unattended run until a human resumes it, while here the person has said all they meant to.
  `jig task resume <id>` ends the pause, and a new session continues the run at the stage it did
  not enter. The skill ends the session on exit 4 and records no stop.
- **`jig task pause <id>` honours a pending request too**, taking it out the same way before it
  sets the fields.
- **`jig context resolve --task <id> --stage <stage>` honours it for any agent** (amended
  2026-10-21). A named task resolving the context of a named stage is entering that stage, so a
  pending request is honoured there, before any context is printed. The pause is `task`'s to write,
  so `context` runs `"$JIG_SELF" task pause <id> --if-requested --stage <stage>` as a process
  (ARCHITECTURE.md). `--if-requested` pauses only when a request is pending, with the request's
  reason (it refuses `--reason` and `--stash`: the reason is the person's, a stash is their call),
  through the same function as `autopilot stage` (`_task_honour_pause_request`: take the request
  out, set the fields, a `pause` journal line when a run is `on`, the `paused:` line), and exits 4;
  nothing pending, or a task already paused, is exit 0 and silent. `context resolve` then adds a
  `next:` line telling the agent to end the session and exits 4 itself, with no context. A pause
  the process could not make (exit other than 0 or 4) is a warning on stderr: the request stays,
  sticky, and the context is printed — reading context never breaks on the queue. Not honoured:
  `resolve` without `--stage`, or with a task guessed from the branch rather than named, `pending`,
  `guard`, `acknowledge` and the stateless `jig context` — those run inside a stage. The `jig-task`
  and `jig-autopilot` skills say in one sentence what exit 4 from it means. It is the one exception to
  ADR-0021's "stage selection never writes task state", amended there: the write is `task pause`'s,
  and it happens only when a person asked for it.
- **`jig task list --json` carries the request** on each task (`pause_request`, its time and
  reason), and the actions table gains `request-pause` and `cancel-pause-request` after `resume`.
  A pending request leaves `pause` offered: a direct pause takes the request with it. A finished
  task still offers `cancel-pause-request` while a request of it is pending — one made during its
  last stage, after which no stage comes — so a card never shows a request it cannot take back.
- **`common.sh` reads `request` lines with a parser of its own** (`jig_pause_request`), a departure
  from the queue ADR's consequence that every later reader goes through `queue.sh`'s parser:
  `task` may not source `queue.sh`. It reads the one record it needs, only from a file of format
  `1` — another format holds no request it can read — and writes nothing.

## Alternatives

- **Pause first, then take the request out.** A request that could not be taken out would outlive
  the pause it caused and pause the task again after `resume`. Taking it out first leaves, on
  failure, the request standing and the task unpaused — still sticky.
- **Stop the run (`autopilot: stopped`).** The status page would show a question nobody asked, and
  an unattended run would need `resume --by human` with an answer that is not one.
- **A resume request.** While a task is paused nobody runs to read one; `jig task resume` is offered
  by the actions table and does it at once. The `<kind>` column leaves room for one.
- **Honour the request in more commands an agent calls** (`jig verify`, `jig context guard` and
  `pending`, `resolve` without `--stage`, receipts, `status ready`): mid-stage or at a stage's end,
  against "the agent finishes the step it is on". `resolve --stage` is the exception adopted in
  2026-10-21, because it is a stage's first step.
- **The session hook** (`SessionStart`, amended 2026-10-21). It runs once per session, not per
  stage, and by its contract prints nothing into the session and touches no git: an agent that
  started before the request would never see it.
- **A runtime hook on every prompt or tool call.** One runtime's feature, a change to the runtime's
  own configuration that Jig does not edit (ADR-0024), and it fires mid-stage.
- **A new stage-entry command in every stage skill** (`jig task stage <id> <name>`). One more step
  six skills must remember, doing what `context resolve --stage` already declares.
- **The request in the task's `state`.** Rejected by the spec: `state` is written last-write-wins,
  and the queue has one writer checked against the revision.
- **Drop a request the task moved past.** Rejected by the spec: a request is sticky.

## Consequences

- An autopilot run, attended or not, pauses at its next stage boundary after a request, however long
  the current stage takes. Since 2026-10-21 so does a session without autopilot, at the next stage
  that resolves its context; showing a request in `jig status` and `jig context` is the queue
  readers' (contract-queue's `queue-status-context`).
- A stage without a skill of its own — plan, design, a discover that is not a route's first stage —
  resolves no context, so a request made during the stage before it is honoured one stage later.
- **Accepted risk:** an agent that resolves the context of the stage it is already in again, in the
  middle of it, is paused there. The step it is on is a read, so no work is lost, but the stage is
  left unfinished; without autopilot no record says which stage came last, and adding one for this
  would be new state.
- `jig context resolve`, a read, writes when a person asked for a pause. No program reads Jig
  through it: they have the `--json` reads.
- `stage` gains exit 4, distinct from 1 (bad arguments) and from repair's 3 (the run stopped).
- Honouring a request raises the revision by the cancel's two and the state writes'; a consumer that
  showed "requested" sees the change and reads `paused: true` and `pause_request: null`.
- **Accepted risk:** a request written between `stage`'s read of the queue and the journal line is
  honoured at the following boundary, one stage later.
