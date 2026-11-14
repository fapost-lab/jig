---
id: adr-20261114-a-persons-pull-request-action-does-not-read-agent-git
type: adr
status: accepted
date: 2026-11-14
domains:
  - task
paths:
  - scripts/lib/prdo.sh
  - scripts/lib/land.sh
  - scripts/lib/promote.sh
  - scripts/lib/task.sh
  - scripts/lib/common.sh
  - scripts/lib/status.sh
summary: Why a person's land, promote, request-review and merge-pr (--by human) do not read agent.git yet never bypass the forge's protection, why they answer JSON with codes against a revision, why pr-status reads the forge live, and why shipping is a runtime record with pid liveness.
---
# A person's action on a task's pull request does not read agent.git, and the forge's protection is never bypassed

## Context

Jig UI puts buttons on a task's card: request a review, land on staging, prepare for prod, merge,
and show why a pull request hangs. Each is a person's decision, taken on what the card showed. Until
now the commands behind them were the agent's: `jig task land` refused below `agent.git: merge`
(exit 3, "the person lands it"), `jig task promote` below `pr`, and on the direct flow only
`jig task ship` merged, at `merge`. None answered JSON with refusal codes, so a UI could neither run
them nor say why one was refused. In a team project at `agent.git: none` a person could not land
from the card at all, and in an unattended clone `--without-review` was refused because "nobody
answers" — while the person pressing the button was the one answering. `agent.git` exists to limit
what the agent does on its own (adr-20260921-agent-git-rights-are-a-local-setting); it was never
meant to limit the person.

`jig task merge` was already taken: `jig task merge <from> --into <to>` absorbs one task into another
(adr-20261027-an-absorbed-task-is-archived-with-its-receiver).

## Decision

- **`--by human` marks a person's act.** `jig task land`, `jig task promote`, and the new
  `jig task request-review` and `jig task merge-pr` take it. With it the git level (`agent.git`,
  `autopilot.git`) is not read; without it each command keeps the agent's level as before (`land`
  and `merge-pr` need `merge`, `request-review` `pr`, `promote` `pr` and `merge` for auto-merge),
  refused in JSON as `git-level`. The same marker as `jig task autopilot <id> resume --by human`.
- **The actions table offers the person's form.** The rows `land`, `request-review`, `merge`
  (command `jig task merge-pr <id> --by human`), `promote` and `pr-status` carry `--by human` in
  their `command`, so "offered implies accepted" holds at every `agent.git`
  (adr-20261015-one-table-of-what-a-person-may-do). Each row asks the command's own guard.
- **What the person's form does not lift:** the forge's branch protection (never `--admin`; the
  forge's refusal is `forge-refused`), red or running CI, `git.staging_review: require`, a draft, a
  conflict, the task's ship gates for `land`, the release notes check for a merge that raises the
  version (`notes-stale`). It is refused while the agent works the task: an autopilot run `on`
  (`autopilot-running`) or a live `jig task ship` waiting for CI (`ship-running`).
  `_task_nobody_answers` is not applied: the person who pressed the button answers.
- **A person's command never waits and never resolves.** CI is looked at once
  (`JIG_SHIP_CI_TIMEOUT=0`): pending is `ci-pending`. A conflict on staging is refused as `conflict`
  without starting the direct merge; resolving it stays the agent's `jig task land <id>`.
- **Writes are checked against the revision** the caller read, claimed after every local and forge
  check and before the first thing sent: `stale-revision` means nothing was sent. The one Jig record
  `merge-pr` writes under that claim is the close (`status consolidated`), only when the knowledge
  decision is recorded; otherwise the answer says `close_blocked: knowledge-not-recorded`. It never
  moves a checkout or deletes a branch; housekeeping's sweep does that later.
- **The direct-flow merge is `jig task merge-pr`**, its action id `merge`.
- **`jig task pr-status <id> --json` is the second read that asks the forge**, after
  `jig pr reviewers --json`: checks with state, link and duration, the review and whom it waits for,
  mergeability, draft and the branch's protection, and the codes that block a merge now. Called when
  a person asks, never on a timer; it writes nothing.
- **A forge outcome's code comes from a variable, never from its words:** `JIG_SHIP_NOT_MERGED_CODE`
  beside every `not merged:` in common.sh, `_LAND_CODE` beside every `not landed:` in land.sh. A
  refusal of a shared guard (`_task_land_refusal`, `_task_merge_pr_refusal`, …) is Jig's own text,
  printed for the actions table too; the command maps it to a code by its opening words, and a
  test pins each mapping, so a reworded guard fails a test rather than changing a code silently.
- **`shipping` is a runtime record with liveness.** `jig task ship` writes
  `<clone root>/.ai/runtime/shipping/<id>` (`pid`, `since`) while it waits for CI to merge or land,
  and removes it on exit; a read reports it only while `kill -0 <pid>` succeeds. `jig task list
  --json` carries `shipping: {since} | null`, so a UI tells "the agent waits for CI and merges" from
  "the merge is yours" and "nobody watches".
- **Attention items about an open pull request carry its state and actions**: the forge cache's
  `ci` and `mergeable` beside `state`, words built from them, and the task's `merge` (or `land`) and
  `pr-status` rows.

## Alternatives

- **Rights from the output format (`--json` means a person).** A format is not a decision; a person
  in a terminal needs the same right.
- **A separate personal level for a person's actions.** A level limits an agent; a person's own
  click needs no setting (zero-config), and the forge's protection already says what the person may.
- **A UI-only confirmation token proving a person.** Hardening before working: the agent is told
  never to run the person's form, and a script cannot tell either way. Deferred, not rejected.
- **Overloading `jig task merge` by the absence of `--into`.** One name for two unrelated writes.
- **Letting the person's land resolve a conflict.** A UI cannot resolve; the temporary tree would be
  left for nobody.
- **Waiting for CI in the person's command.** A button that hangs for `agent.ci_timeout` minutes.

## Consequences

- An agent could run the person's form and pass its own level. Accepted for now: skills say it
  never does (jig-autopilot, jig-consolidate), and the forge's protection still holds.
- `jig task land --by human` below `merge` lands what `jig task land` would hand back with exit 3;
  the agent's form is unchanged, texts and exit codes 3 and 5 included.
- The forge cache carries no review state; the attention items say CI and conflicts only, and
  `pr-status` says the rest. A review state in the cache (task `staging-review-state-for-ui`) joins
  the same objects without raising `schema`.
- "working here" records outlive sessions by hours because they expire by mtime
  (`checkout.busy_ttl`, 12 h), not by liveness; `shipping` does not use them.

> **Amended 2026-11-14.** The Consequences line "The forge cache carries no review state" no longer holds: housekeeping keeps `<review>` and `<waiting_for>` for open pull requests (adr-20261113-reviewers-are-read-from-the-forge as amended), the pull-request attention items carry `pull_request.review`, and a task parked for review that is not approved yet gets its own item titled by that review. The actions table is fed what it was fed before; the review does not change which rows are offered.
