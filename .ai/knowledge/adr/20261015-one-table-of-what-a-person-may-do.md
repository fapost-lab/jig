---
id: adr-20261015-one-table-of-what-a-person-may-do
type: adr
status: accepted
date: 2026-10-15
domains:
  - task
  - scripts
paths:
  - scripts/lib/task.sh
  - schemas/json.md
summary: Why what a person may do next with a task is one table in task.sh whose rows ask the commands' own guards, why it is one-way (offered implies accepted), why close reads the forge cache, and where contract-queue's pause requests join.
reviewed_at: 2026-10-16
---
# What a person may do next with a task is one table in task.sh whose rows ask the commands' own guards

## Context

A program that shows Jig's tasks — Jig UI, a bot, an agent choosing what to take next — has to say
which moves a person can make on each one: approve a design, answer a stopped run, close a merged
task. The contract-extensions spec settled with the maintainer that Jig reports this and no consumer
keeps its own copy of the table (2026-10-14). A copy outside Jig drifts the day a command gains or
loses a refusal, and nobody sees it until a button fails.

The refusals were written inline in each command (`[ … ] || jig_die "…"`), so "may this run now" had
exactly one implementation, inside the command, and nothing else could ask it. One of them cannot be
asked on a read at all: `jig task set <id> status consolidated` asks the forge whether the pull request
merged, and a `--json` read never touches the network (adr-20261015-a-read-is-one-json-envelope).

## Decision

- **One table, `_task_actions` in `scripts/lib/task.sh`**, beside the commands it names. Ten rows in
  a fixed order, each a stable id and the Jig command it maps to: `start`, `pause`, `resume`,
  `approve-gate`, `answer-stop`, `set-class`, `ship`, `close`, `abandon`, `reopen`. The set comes from
  the commands a person runs (or asks the agent to run) and their refusals; there is no `reject-gate`,
  because no command records a rejection. The route's own mechanics — `autopilot start|stage|repair|
  stop|approve|decide|end`, findings, receipts, the knowledge decision — are the agent's, not rows.
- **Each row asks the command's own guard.** The state checks moved out of the commands into
  functions that print the refusal text or nothing — `_task_start_refusal`, `_task_pause_refusal`,
  `_task_resume_refusal`, `_task_gate_refusal`, `_task_autopilot_resume_refusal`,
  `_task_close_refusal`, `_task_ship_level_refusal`, `_task_ship_refusal` (with
  `_task_route_evidence_refusal`) and `_task_ship_branch_refusal` — and the command dies with that
  text where the inline check stood. The table calls the same function; a row withheld by a guard
  carries its refusal, word for word, as `reason`.
- **A guard that cannot decide refuses.** A guard returns non-zero when a check inside it failed; the
  command then exits, and the table withholds the row (`jig could not check whether <id> may
  <action> now`). A failure never reads as "nothing refuses".
- **The rule is one-way: offered implies the command accepts on this task's state.** The table may
  withhold more than a command refuses — a finished task offers only `reopen` (an abandoned one), an
  approved design is not offered for approval again, a merged pull request is not shipped — and says
  so in its own words. What a command refuses by the checkout it runs in (the current branch, a dirty
  tree, nothing staged), by the network, or by the value a person types (`--reason` when lowering a
  class) is the command's when it runs, never the table's.
- **`close` reads the forge cache.** `_task_close_refusal` takes the pull request's state as an
  argument: the command passes `forge` and asks `jig_pr_state`; the table passes the forge cache's
  state, `unknown` when the cache does not say. A merge is final, so a cache that says `merged` is
  never contradicted by the forge; a cache behind the forge can only withhold a close the command
  would allow, until the next housekeeping. A test runs the command against a stubbed forge to prove
  the two agree.
- **`jig task list --json` reports every row for every task** as `actions`, the last field of a task:
  `{"id", "command", "offered", "reason"}`, `reason` `null` when offered. `command` names the task
  and writes what a person supplies as `<text>`, `<Tn>` or `<file>`. Text output is unchanged.
- **Pause and resume requests are the seam for `contract-queue`.** They join as rows of the same
  table, with a guard of their own that reads the queue file. A new action id is a compatible change:
  `schema` stays, and a consumer ignores ids it does not know.

## Alternatives

- **A table with its own conditions, checked by a test.** Two copies of every refusal, with drift
  caught only after it happened, and only for the states a test thought of. Sharing the guard makes
  drift impossible where the guard can be shared, and the test is kept for the one that cannot
  (`close`).
- **Only the offered actions.** Shorter, but a consumer can then show neither a disabled button nor
  why, and goes back to guessing.
- **A separate `jig task actions <id> --json`.** A second read and a second shape for the same task;
  the spec places actions in the task list. One can be added later over the same function.
- **`command` as an argv array.** Its placeholders need the same substitution as in a string, and the
  string is how Jig already names a command in its refusals.

## Consequences

- A refusal added to one of these commands belongs in its `_task_*_refusal` function, or the table
  offers what the command then refuses; the agreement tests in `tests/task.t.sh` run every offered
  command and every guard-withheld one on fixtures and catch it there.
- A `--json` listing evaluates ten guards per task. The expensive one, `ship`'s receipt check
  (a diff hash and a `jig context` process), is reached only by a task whose knowledge decision is
  recorded and whose ledger has no blocking finding — as expensive as the ship it predicts.
- That `jig context` runs in the task's own checkout, and a read must leave no record of work there
  (adr-20260924-a-checkout-records-what-is-happening-in-it). The receipt check's nested run therefore
  carries `JIG_INTERNAL_REDRAW`, the marker the status page's redraw already uses for a re-entry that
  is not a session — for every caller of the check, `task ship` and `task receipt --check` included.
- One order of refusals changed, where both apply at once: `task ship` on a branch equal to its base,
  run from another branch, now names the base before the current branch. It still refuses.
