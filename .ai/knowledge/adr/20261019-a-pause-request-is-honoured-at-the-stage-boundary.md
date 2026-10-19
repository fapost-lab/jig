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
summary: Why a pause request is a request line of the queue file written by jig queue request|cancel, honoured by jig task autopilot stage (exit 4, request taken out before the pause is set, run stays on) and by jig task pause, and why there is no resume request.
reviewed_at: 2026-10-19
---
# A pause request lives in the queue file and is honoured by `jig task autopilot <id> stage`, which pauses the task instead of entering the stage

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
- **Honour the request in more commands an agent calls** (`jig context`, `jig verify`): mid-stage,
  against "the agent finishes the step it is on".
- **The request in the task's `state`.** Rejected by the spec: `state` is written last-write-wins,
  and the queue has one writer checked against the revision.
- **Drop a request the task moved past.** Rejected by the spec: a request is sticky.

## Consequences

- An autopilot run, attended or not, pauses at its next stage boundary after a request, however long
  the current stage takes. A session without autopilot does not see a request; showing it in `jig
  status` and `jig context` is the queue readers' (contract-queue's `queue-status-context`).
- `stage` gains exit 4, distinct from 1 (bad arguments) and from repair's 3 (the run stopped).
- Honouring a request raises the revision by the cancel's two and the state writes'; a consumer that
  showed "requested" sees the change and reads `paused: true` and `pause_request: null`.
- **Accepted risk:** a request written between `stage`'s read of the queue and the journal line is
  honoured at the following boundary, one stage later.
