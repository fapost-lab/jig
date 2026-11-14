---
id: adr-20261114-a-person-waives-a-gate-hooks-refusal-for-one-task
type: adr
status: accepted
date: 2026-11-14
domains:
  - task
  - config
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - skills/jig-autopilot/SKILL.md
summary: Why a gate hook's refusal is waived per task by gate and hook path with a reason, why a waived hook still runs and the hook-wrote-files check is never waived, where a waiver is shown (jig status, status page, JSON, commit and pull request body), and why autopilot never waives.
---
# A person waives a gate hook's refusal for one task, with a reason

## Context

A project's gate hook refuses `ready`, the knowledge decision or `task ship` when it exits non-zero
or its path is wrong (adr-20261113-a-project-script-can-refuse-a-completion-gate). A hook is the
project's code, and it can be wrong: a check that misreads one task, a tool missing on one machine,
a path renamed in the config. Without a way around it, one broken hook stops every task of the
project, and the only remedy — editing the hook or the config — leaves no trace in the task that
was let through. The spec (`.ai/specs/project-hooks/`) answers it with a per-task waiver with a
reason, shown where the work is read, and keeps it out of the agent's hands: autopilot treats a
hook's refusal as one of its stops.

## Decision

**A waiver sets aside one hook's refusal at one gate for one task.** `jig task waive <id>
<ready|consolidate|ship> <path> --reason <text>` records it in the task's workspace, in the file
`waivers`: one tab-separated line per gate and hook path, with the date and the reason, as a
dismissed finding carries its reason. Its key is the pair (gate, path): the same hook at another
gate, and every other hook of the gate, still refuse. The path must be one `hooks.<gate>` names in
this checkout, so a typo leaves no record that waives nothing. Waiving the pair again replaces its
reason; `--withdraw` takes it back.

**A waived hook still runs.** Its non-zero exit, or its path that cannot run, is shown as a warning
naming the waiver's reason, with the hook's output: the trail shows whether it still refuses. A
misconfigured path is waived like a failing exit — it is the case a waiver exists for.

**The check that a hook wrote nothing is never waived.** It guards what the review read, not the
script's verdict; a waiver lifts only the verdict.

**A waiver is never quieter than the gate it set aside.** `jig status` counts it on the task's line
(`waived=<n>`) and names each one below it, and a task with one needs the reader, as a lowered class
does; the status page marks the task, and the task's JSON carries `waivers`. `jig task ship` adds a
`Hook waivers:` block to the commit message and to the pull request's body, so the reviewer reads it
with the change, mechanically and not by a skill's copy.

**Autopilot never waives.** `jig task waive` refuses while the task's autopilot run is `on`. A
script cannot tell a person from an agent (ADR-0020); like `jig task gate --by agent` outside an
unattended run, it refuses where the move is certainly not the agent's. The skill makes a refusal
the task's work cannot satisfy a stop: attended, the run asks for a waiver or a fix of the hook;
unattended, it stops and ships a draft that says which hook refused, and a person waives and
resumes it.

**A waiver does not go stale** when the code changes after it: it judges the hook, not the code,
stays visible in `jig status` and in the pull request, and is withdrawn by hand. Whether it should
is still the spec's open question; staleness can be added later without changing the record.

## Alternatives

- **No waiver.** One broken hook stops every task of the project.
- **Removing the hook from the config for the task.** It leaves no trace in the task, and it
  switches the hook off for everyone else's tasks too.
- **A waiver of a whole gate, or of the task.** One broken hook would silence a working one beside
  it.
- **Skipping the waived hook.** It would also get past a hook that hangs, but it hides whether the
  hook still refuses; a hook's run time is the spec's open question, not this decision's.
- **A waiver that goes stale like a review receipt.** More to compute and to explain, for a record
  that judges the hook and not the code; left open in the spec.
- **Letting autopilot waive with a recorded reason.** A hook is the team's rule; an agent that may
  set it aside makes it a reminder again.

## Consequences

- A team can keep a strict hook: a wrong refusal costs a person one command and a reason, not a
  change to everyone's config.
- The waiver is a claim like every workspace record (ADR-0020): the script cannot tell who ran the
  command. What makes it visible is `jig status` and the pull request, not a mechanism.
- A hung hook still holds its gate; a waiver does not help with it.
- This amends adr-20261113-a-project-script-can-refuse-a-completion-gate, whose consequence "a
  refusal has no way around it yet" no longer holds.
