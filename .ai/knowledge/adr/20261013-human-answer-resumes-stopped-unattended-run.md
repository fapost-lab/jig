---
id: adr-20261013-human-answer-resumes-stopped-unattended-run
type: adr
status: accepted
date: 2026-10-13
domains:
  - task
  - skills
paths:
  - scripts/lib/task.sh
  - skills/jig-autopilot/SKILL.md
  - schemas/state.md
summary: A direct human answer can resume a manually stopped unattended run without resetting its repair limit.
reviewed_at: 2026-11-08
---
# A direct human answer may resume a manually stopped unattended run without renewing its repair budget

## Context

`autopilot.unattended: true` tells an agent to use recorded safe defaults and not ask a person at each stage (ADR 20260922). A stopped run was intentionally final because the old `resume` reset the two-repair budget (ADR 20261004). In practice, a human can answer a stop in the active chat. The `attended-answer-in-unattended-clone` task and `cross-runtime-stage-handoff` both reproduced a dead end: `start`, `resume`, and either form of gate approval refused, although the person had supplied the missing decision. The only allowed ship was an unfinished draft.

## Decision

- A stopped run whose recorded mode is `unattended` may use `jig task autopilot <id> resume --answer <text> --by human` when an actual person answered a manual stop. The answer is required, kept verbatim in the journal with a `human:` marker, and shown by `report`. Jig cannot authenticate the caller; the visible claim lets the person dispute a fabricated answer, like the attended answer record already does.
- This path is refused once `autopilot_repairs` reaches two. It never resets that count. The third `repair` therefore still ends in a draft, even if `--by human` is passed. A manual stop after two repairs also remains final: the conservative ambiguity avoids reopening the repair limit.
- The run remains `unattended` after resume. A T3/T4 design changed during the stop is re-approved by the agent with `gate --by agent`, never mislabeled as a human approval of the whole design. The human's answer may decide one criterion without approving everything else.
- An attended run keeps `resume --answer` and its repair-count reset. `--by human` is specific to the exceptional unattended recovery. `start` and `gate` errors point to this path when available and to a draft when the limit is exhausted.
- The skill still does not ask questions during an unattended run. It uses this recovery only when a person independently answers a stop. Scripts keep the lifecycle record; they never launch an agent or infer identity.

## Alternatives

- Allow all unattended resumes: rejected because it restores the repair-limit bypass.
- Reset repairs on a claimed human answer: rejected because shell cannot authenticate the claim.
- Switch the run to attended: rejected because its recorded mode would stop explaining the remaining stages and the local user's choice.
- Keep the draft-only dead end: rejected because it discards a concrete human answer and strands the task's gate.

## Consequences

A person can unblock an already stopped unattended task without editing protected state. The remaining repair budget and gate origin stay visible. Agents must quote the actual answer; a fabricated answer remains possible at the agent boundary and is exposed in the pull request report.

This narrows the unattended no-resume rule in ADR 20261004 and ADR 20260922; their repair-limit guarantee remains in force.

> **Amendment (2026-11-08).** A person who takes a stopped run on, at the repair limit too, ends it with `handover --by human --answer`. A stop after two repairs stays final for the run, not for the task: no `resume` and no new `start` reopen it, and the work the person takes on goes on without autopilot and without a repair count. The run is not switched to attended, the alternative rejected above: it ends, its mode and repair count stay as recorded, and no run starts after it (adr-20261108-a-person-takes-over-a-stopped-run).

> **Amendment (2026-11-14).** The person's answer may be recorded first, with `jig task autopilot <id> answer --answer <text> --by human` under the same refusals, and the run resumed later by whoever has a free slot with `resume` and no `--answer`, which needs no `--by human`: the person's form already wrote the answer. The repair count is preserved as before (adr-20261114-a-waiting-run-holds-no-slot).
