---
id: adr-20261113-a-project-script-can-refuse-a-completion-gate
type: adr
status: accepted
date: 2026-11-13
domains:
  - task
  - config
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - scripts/lib/config.sh
  - schemas/config.md
summary: Why a project's hooks.ready|consolidate|ship scripts run in task set and task ship after Jig's own checks, why the exit code alone decides, how a hook is run and what it is told, why a misconfigured path refuses and jig status names it, and why hooks are a project key only.
reviewed_at: 2026-11-13
---
# A project's own script can refuse a completion gate

## Context

A project's rule that belongs to the end of a task — "a change to the public API updates the
published docs" — reached the agent only as knowledge: a request to a model, which no script could
check (`.ai/specs/project-hooks/`). Jig's own completion checks (open P0/P1 findings,
adr-20260921-review-findings-block-completion; the review receipt,
adr-20260921-review-receipt-pins-what-was-reviewed; the route's records,
adr-20261004-a-route-stage-is-proven-by-its-record) live at three commands, and they know nothing of
any one project. A stage cannot carry such a check: a stage is a skill, model behaviour, and a hook
fired on entering it runs only if the model calls the command — a reminder again. The commands
are the only points a script controls.

## Decision

**A project names its own scripts at the three completion gates**, in its `.ai/config.yaml`, as
inline lists of project-relative paths:

- `hooks.ready` runs in `jig task set <id> status ready`;
- `hooks.consolidate` runs in `jig task set <id> knowledge_consolidated true`, and in the close of a
  bare findings triage task, which records the same decision;
- `hooks.ship` runs in `jig task ship`, at every `agent.git` level including `none`.

Each runs **after** Jig's own checks at that gate — findings, receipt, route evidence — and before
anything is written, committed or sent (adr-20260925-a-ship-refuses-before-it-sends). A `--draft`
ship runs none, as it asks none of the gates; the recheck right before a merge does not run them
again, since they passed in the same call.

**The exit code decides.** `0` passes; whatever the script printed is shown on stderr as a warning.
Anything else refuses the gate with `jig_die`: the refusal names the key, each refusing script, its
exit code and its output. Every script of a list runs, in order, so one attempt shows every
refusal. There is no warn/block mode in the configuration: the script knows what is serious.

**Only the commands run a hook.** The shared refusals the actions table and `jig status` read
(`_task_ship_refusal`, `_task_close_refusal`) never do: a read must not execute project code. A hook
refusal is therefore one of the refusals adr-20261015-one-table-of-what-a-person-may-do leaves to
the command, like the checkout it runs in: the table may offer a ship or a close that a hook then
refuses. A misconfigured path does not withhold the row either; `jig status` names it instead.

**A hook checks; it never writes.** Jig hashes what git sees in the task's tree — the status lines,
untracked files included, and the diff against `HEAD` — before and after a gate's hooks, and refuses
the gate when they differ. `task ship` stages tracked edits, so a formatter run as a ship hook would
otherwise commit and push a change no review read (adr-20261003-receipt-pins-what-the-review-read).
The person keeps the change as the task's own, reviewed, or takes it back.

**How a hook runs.** In the task's tree — this checkout when the task's branch is checked out here
or the task has no branch, else the worktree that has it; when the branch is checked out nowhere,
the gate refuses, since there is no code to check. By its path when the file is executable, so its
shebang chooses the interpreter; as `bash <path>` when it is not, the fallback ADR-0037 gives Jig's
own scripts for a checkout that lost the executable bit (Git on Windows does not keep it). On this
machine, never through `run.exec`, for the reason
adr-20261026-a-worktree-is-finished-by-the-projects-command gives for `worktree.setup`. Stdin is
empty; stdout and stderr are captured together, and Jig shows them on its own stderr, since agents
read the stdout of `task set --json` and `task ship`.

**What a hook is told**: `JIG_TASK_ID`; `JIG_TASK_DIR`, the task's workspace; `JIG_GATE`, `ready`,
`consolidate` or `ship`; `JIG_BASE`, the task's base resolved as `jig_base_ref` resolves it, origin
first (ADR-0039), or the bare branch name when neither ref exists. Which files changed is the
hook's to compute against `JIG_BASE`: Jig passes no file protocol it would then have to version.

**Where the list and the file are read.** The list comes from `.ai/config.yaml` of the checkout the
command runs in, as every setting does; the file is resolved in the task's tree. Run from the task's
own checkout, as the route runs, the two are the same tree. Run from another checkout for a task in
a worktree, a hook the task's branch adds is not run there, and one the other checkout names that
the branch predates refuses as missing; `jig status` judges paths against its own checkout.

**Misconfiguration refuses, and is reported first.** A path that is absolute, that leaves the
project through `..`, or that names no file refuses its gate like a failing script. `jig status`
prints a `gate hook:` line for each such path, judged against the checkout it runs in, and never
runs a hook.

**Hooks are a project key only.** `hooks.*` is outside `JIG_CFG_LOCAL_KEYS`, so `cfg` never reads it
from `config.local.yaml` (ADR-0038), and `jig status` names one set there as ignored: a hook is a
team rule a clone must not switch off silently.

## Alternatives

- **Hooks fired by `jig context resolve --stage`.** They run only if the model runs the command: a
  reminder, not a stop.
- **A project check inside `jig verify`.** It would run in CI too, but verify is task-agnostic and
  cannot see the task, and profiles are framework-owned.
- **`warn` and `block` lists per gate.** Two keys per gate for no power the exit code lacks.
- **Always `sh <path>` (or always `bash <path>`).** It needs no executable bit, but ties every hook
  to one shell; running by path when executable keeps any language, and the `bash` fallback covers
  the lost bit.
- **Stop at the first refusing script.** Cheaper, but a person fixes one refusal per attempt.
- **Warnings only in a first version.** The reminder this set out to replace.

## Consequences

- **Safety.** A hook is project code, as the project's tests run by `jig verify` are; nothing runs
  until a person or their agent calls a gate. The hook file is read from the task's own tree, so a
  branch can change its own hook: what stops that is review of the diff, not a mechanism. A hook
  guards the Jig route, not the repository — CI never runs it, and a contributor who never calls a
  gate never meets it.
- **A hook with no end holds its gate**, and an autopilot run with it; whether a gate bounds a hook's
  run time is an open question of the spec (fog).
- **A refusal has no way around it yet** but fixing the script or the config. The per-task waiver
  with a reason, and autopilot treating a hook refusal as a stop, are the next task of the spec.
