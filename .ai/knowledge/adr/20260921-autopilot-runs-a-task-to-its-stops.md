---
id: adr-20260921-autopilot-runs-a-task-to-its-stops
type: adr
status: accepted
date: 2026-09-21
domains:
  - task
  - skills
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - schemas/state.md
  - "skills/jig-autopilot/**"
summary: Why autopilot is its own skill run without a setting, why its two-repair limit is enforced by a script while the gate, re-classification, unmade decisions and destructive steps are the skill's stops.
reviewed_at: 2026-09-22
---
# An autopilot run takes one task through its route without pausing between stages, and stops only where a human is needed

## Context

Every stage transition went through the human: an agent finished a stage, reported and waited for
"go on". The autopilot specification (Phase 3) wants a task handed over and handed back finished —
an open pull request or a stop naming what only a human can decide — and it names the failure to
avoid: a run that loops on a failing repair and never stops. Phases 1 and 2 already give the
mechanical stops a run leans on: `task ship` goes as far as `agent.git` and no further, and the
findings and receipt gates refuse to finish a task that is not reviewed as it stands.

## Decision

- **A skill of its own, `jig-autopilot`.** It classifies and starts the task through `jig-task`, then
  runs the class's route without waiting between stages, has a subagent in a fresh context review,
  and ends in `jig-consolidate` and `task ship`. `jig-task` stays a short router (ADR-0009).
- **No setting grants it.** Asking for autopilot is consent for that one task; how far it goes with
  git is `agent.git` (adr-20260921-agent-git-rights-are-a-local-setting). At `none` a run ends with the
  change ready for the human's commit.
- **`jig task autopilot <id> start|stage|repair|stop|resume|end|report`** keeps a journal in the task's
  workspace and a state of `on`, `stopped` or `done`, which `jig status` shows as `autopilot=on` or
  `autopilot=stopped`.
- **The repair limit is a script's**: two repairs per run — a repair being one loop of fixing and
  reviewing or verifying again after a blocking finding or a red verification. The third `repair`
  is refused with exit 3, and the run is `stopped`. `resume`, after a human answers a stop, resets
  the count, since the human gave the run a new direction. Fixed at two, approved at the gate.
- **Which stops are mechanical.** The repair limit and the Phase 2 gates are enforced by scripts. The
  human gate of T3/T4 (ADR-0009), a re-classification into T3/T4, a decision nobody made, and a
  destructive operation are the skill's rules: the scripts cannot see an agent's commands or
  reasoning, and the documentation says so. A re-classification within T0–T2 continues and is noted.

## Alternatives

- **A mode of `jig-task`**: the router would carry the whole orchestration and load it for every task.
- **A local key allowing autopilot, or a class ceiling**: a per-task request is enough consent, git is
  bounded by `agent.git`, and the gate bounds the class. Worth revisiting when runs are started by
  something other than a person — a phase run.
- **The repair limit as a rule of the skill**: the loop the specification names is exactly what a
  rule of the skill does not stop.
- **Scripts intercepting destructive commands**: impossible without wrapping the runtime's shell;
  scripts never drive the agent (ADR-0001). The runtime's permissions are the real barrier.

## Consequences

- A task can go from a request to an open pull request with no human between stages, and a run
  cannot repair forever.
- Three stops still rest on the agent following its skill. The unattended mode — the next item of
  the specification — replaces the stops with recorded safe defaults for users who cannot answer
  them; without it, every stop asks the human.
- A new skill exists only after `jig upgrade` places it for each runtime.

> **Amendment (2026-09-22).** The unattended mode exists: with `autopilot.unattended: true` `start`
> records the run as unattended, and each stop of the skill becomes a recorded default — the gate
> self-approved, an unmade decision taken the most reversible way, a destructive step never taken
> (`approve` and `decide` events, refused in an attended run), exhausted repairs ending in a draft pull
> request. The repair limit is unchanged. See
> adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci.

> **Amendment (2026-09-22).** A run may be one task of a **phase run**: `jig task autopilot <id>
> start --phase <spec-id>/<n>` records `autopilot_phase`, and then the agent does not ship its own
> task and does not touch the spec — the coordinator that started it owns `.ai/specs/`, runs
> `jig task ship` and checks the roadmap item after the merge (`jig spec done` refuses in the task's
> own branch). The route, the stages, the repair limit and the stops are unchanged; a stop is
> answered in the coordinator's session, and it holds the next wave rather than the one in flight
> (adr-20260922-a-phase-run-is-coordinated).
