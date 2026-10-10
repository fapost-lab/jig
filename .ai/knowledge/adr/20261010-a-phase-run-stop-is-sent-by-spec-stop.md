---
id: adr-20261010-a-phase-run-stop-is-sent-by-spec-stop
type: adr
status: accepted
date: 2026-10-10
domains:
  - spec
  - task
paths:
  - scripts/lib/spec.sh
  - scripts/lib/notify.sh
  - skills/jig-autopilot/references/phase-run.md
summary: Why a phase run's coordinator records its stop with jig spec stop, which sends the Telegram message the way a task's stop does and keeps only the send's outcome under .ai/workspace/specs/, never a phase journal.
reviewed_at: 2026-10-10
---
# A phase run's stop is recorded by `jig spec stop`, which sends it to Telegram and keeps only the send's outcome

## Context

A task's autopilot stop reaches the person's Telegram because it is a journal event
(adr-20261009-autopilot-stops-reach-telegram). The coordinator of a phase run stops too — a wave
waiting for the person's answers, a `problem` row, the forge unreachable, and, unattended, a draft
that ends the run — but it said so only in its own session: a phase run has no journal
(adr-20260922-a-phase-run-is-coordinated rejected one as a second store beside `jig spec plan` and
the task files). So the costliest stop, a whole wave waiting, sent nothing.

## Decision

- **`jig spec stop <spec> --phase <n> --reason "<what is needed>"` is the record of a phase run's
  stop.** The coordinator runs it after telling the person in its session (`jig-autopilot` §6,
  `references/phase-run.md`). It checks its arguments — a valid spec id, a spec and a roadmap in
  this checkout, a `## Phase <n>` in that roadmap, a non-empty one-line reason — and prints
  `spec stop: <spec> phase <n>`. It reads the roadmap of the working tree, not the epic's ref as
  `spec plan` may: the coordinator runs in the epic's checkout, where the two are the same.
- **The message goes the way a task's does** (`jig_notify_phase`, notify.sh): the same three keys,
  the same cheap checks in the command, the same detached sender and `_notify_post`, the token never
  on a command line. Its text is `<mark> <project> · <spec-id> · phase <n>`, the spec's title
  (80 characters) and the reason (300). The mark is `⏸`, or `⛔` when the clone runs unattended
  (`autopilot.unattended` read at the stop — a phase run records no mode): nothing waits there, the
  run has ended.
- **Only the send's outcome is kept**, in `.ai/workspace/specs/<spec-id>/notify`, one line in the
  task file's format, replaced atomically. It is not a journal and holds no state of the run, so
  "no new store" stands. `jig_notify_failing` reads it beside the tasks' files and names its owner
  `task <id>` or `spec <id>`, which `jig status`'s `notify:` line and `jig notify test` print.
- **The directory has no lifecycle of its own.** Nothing removes it — not `spec close`, `remove` or
  `epic --finish`, not housekeeping. It is gitignored, one small file per spec that ever stopped,
  and a stale failure in it is cleared by the next successful send anywhere.

This extends adr-20261009-autopilot-stops-reach-telegram to one more sender, and refines
adr-20260922-a-phase-run-is-coordinated: the coordinator's stop now has a command.

## Alternatives

- **A journal of the phase run** — the second store the phase-run ADR rejected; a stop does not
  need one to be sent.
- **`jig task autopilot <task> stop` on a task of the wave** — the tasks are consolidated or ended
  by then; the message would name the wrong unit and the stop would rewrite a task's state.
- **A generic `jig notify send`** — any caller could send any text; the message would no longer be
  tied to a recorded event of the process.

## Consequences

- A person away from the coordinator's session learns within seconds that a wave waits or that an
  unattended phase run ended. A coordinator that dies before running `spec stop` still sends nothing.
- Removing a spec leaves its `notify` file behind until the workspace is cleaned by hand; harmless,
  and cheap to sweep later if it ever matters.
- Rolling this back is removing a subcommand, one sender in notify.sh, three mentions in the
  `jig-autopilot` skill and its phase-run reference, and two paragraphs of `docs/autopilot.mdx`.
