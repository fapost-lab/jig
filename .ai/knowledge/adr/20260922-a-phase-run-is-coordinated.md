---
id: adr-20260922-a-phase-run-is-coordinated
type: adr
status: accepted
date: 2026-09-22
domains:
  - task
  - spec
  - skills
  - config
paths:
  - scripts/lib/spec.sh
  - scripts/lib/task.sh
  - scripts/lib/config.sh
  - scripts/lib/status.sh
  - skills/jig-autopilot/SKILL.md
  - skills/jig-autopilot/references/phase-run.md
summary: Why a roadmap phase runs under a coordinator that owns the spec, files each wave in one unpushed epic commit, ships every task and checks roadmap items after the merge, and what autopilot.parallel counts.
reviewed_at: 2026-09-22
---
# A roadmap phase runs wave by wave under a coordinator that owns the spec, ships every task and keeps the merge queue

## Context

`jig-autopilot` runs one task. A specification's roadmap is a list of phases, each grouped into
waves whose items can be built at the same time (ADR-0040, `jig spec plan`). Running four tasks in
parallel by hand, on 2026-09-21, showed what a phase run has to solve: branches of one wave rewrote
neighbouring lines of the same `roadmap.md` and conflicted; an agent working outside its own
worktree raced another's tests; `jig spec plan` could not see a task until its tag reached the epic,
which happened only at the first merge; and every merge into the base made the other branches'
review receipts stale.

The runtime is not something a script can lean on. Claude Code can start background subagents;
Codex cannot. A subagent's working directory resets between Bash calls. No agent can be relied on
to still exist when a person answers, and none sees another's conversation. A `bash` script cannot
start an agent at all (ADR-0029). So the state of a phase run has to be recoverable from files, and
the orchestration itself has to be a skill.

## Decision

- **The coordinator is a session in the epic checkout, and it writes no code.** It files the wave's
  tasks, starts one agent per task in its own worktree, ships each task with `jig task ship` from
  that worktree, keeps the merge queue and ticks the roadmap off after each merge. A task agent ends
  at consolidation: the change staged, `knowledge_consolidated: true`, its commit message in the
  workspace. That it does not run `jig task ship` is a contract of the skills, not a refusal in
  the script: the coordinator ships from the task's own worktree with the task's own state, so no
  check could tell the two apart. `jig-consolidate` §5 stops a task with `autopilot_phase` before
  the ship step, and the coordinator's prompt to each agent repeats it. The queue is what keeps two
  tasks at `agent.git: merge` from merging past each other and keeps CI read in one place; an agent
  that ships anyway breaks the order, not the gates — its own findings, receipt and knowledge
  decision are still checked by `task ship` itself.
- **A wave is filed by one commit on the local epic, which the wave's pull requests carry.** The
  coordinator files the wave (`jig-idea` §10), commits the item tags plus any checkmarks it owes,
  and does not push. `jig_fresh_base_ref` takes the fresher of the local branch and `origin`'s, so
  `jig task start --worktree` cuts every branch of the wave from that commit, by the same SHA: no
  two branches rewrite the same roadmap lines, and `jig spec plan` knows the tasks from the first
  minute because the epic is checked out here. The commit reaches `origin` with the wave's first
  merged pull request. This is the "through a task" `spec_ship_epic` requires, in one commit per
  wave.
- **Checkmarks are the coordinator's, after the merge.** A task of a phase run does not run
  `jig spec done`; `spec done` refuses in the branch of a task whose state has `autopilot_phase`,
  and names the coordinator. The coordinator runs it in the epic checkout after each merge, and the
  edit travels with the next wave's filing commit. This refines ADR-0035's "the checkmark lands with
  the work": in a phase run the work of the wave is what lands, and the marks follow it. `spec plan`
  does not need them — a merged, closed task already reads as merged.
- **`autopilot.parallel`, local-only, default 2, 1 to 16.** It counts the agents *building* a task
  of the open wave: run `on`, knowledge not consolidated. A task waiting its turn to ship holds no
  slot, and the short-lived agents that repair the queue — a red check, a merge conflict — are
  outside the limit. `jig spec plan` prints `parallel <limit> <building>`, so no reader counts slots
  itself. It is local-only for the same reason as `agent.git`: how many agents may run unwatched is
  a question about one person's machine.
- **A stop holds the next wave, not the one in flight.** Attended, the coordinator gathers the
  wave's questions into one message, each with its document whole. Unattended there are no stops:
  a task whose repairs ran out becomes a draft pull request, and the phase run ends on that wave
  with a report — the next wave is a person's to start. Asking for a phase run is the person's yes
  to closing a task whose pull request merged, attended too; without that `spec plan` would not see
  a merge until housekeeping ran.
- **A phase run needs `agent.git` at `pr` or better, and an epic.** Below `pr` it would end as N
  uncommitted worktrees; without an epic there is nowhere to put the filing commit — on a protected
  default branch, nowhere at all. Both refusals name what is missing and offer the phase's tasks one
  at a time.
- **The slot count is per spec, and the page asks for it every time.** `parallel` counts the open
  wave of the phase being planned, so two phase runs of two specs on one machine each get the full
  limit; the local-only key bounds one run, not the machine. And the status page calls `spec plan`
  on every redraw rather than caching it — about 0.2 s per phase — because a cache beside the plan
  is the second store rejected below. Both are known, and both are cheap to revisit if a machine
  actually runs two phases at once.
- **No new store.** The run is derived from `jig spec plan` plus each task's own files — state,
  autopilot journal, findings ledger, review receipt. The one new key is `autopilot_phase:
  <spec-id>/<n>`, written by `jig task autopilot <id> start --phase`, so the two readers that must
  behave differently can see it: `spec done` refuses, and the status page's stopped-run card sends
  the person to the coordinator's session instead of the task's, one card per phase.
- **After every merge the rest of the wave is brought up to date and reviewed again when it is more
  than the roadmap tick.** The branches are merged (never rebased, never forced) with the epic, the
  targeted tests run, and `jig task receipt --check` decides: current, ship again; stale, re-review
  in a fresh context and sign a new receipt first. A receipt pins the whole tree minus
  `.ai/knowledge/` and `.ai/specs/` (ADR review-receipt-pins-what-was-reviewed), so a spec-only
  merge costs nothing and any code change costs a review.

This amends adr-20260921-autopilot-runs-a-task-to-its-stops — in a phase run the agent does not
ship its own task — and extends adr-20260921-agent-git-rights-are-a-local-setting with one more
local-only key.

## Alternatives

- **An orchestrator in bash (`jig spec run` that starts the agents).** A script cannot start an
  agent of the runtime; the same reason ADR-0029 leaves the session to the skill.
- **A journal of the phase run.** A second store next to `spec plan` and the task files would drift
  from them. Worth revisiting if `autopilot_phase` turns out not to be enough for the status page.
- **Agents ship their own tasks, the coordinator only merges.** At `merge` each `ship` would merge
  immediately, past the queue, onto a base nobody reviewed together; it would need a `--no-merge`
  flag, and the heads would still need their CI re-run after the base moved.
- **Each task's tag as the first commit of its own branch**, as a single task does today. The
  wave's branches then rewrite neighbouring roadmap lines and conflict, and `spec plan` is blind to
  the task until the first merge.
- **The same tag commit cherry-picked into every branch.** It merges cleanly — identical hunks —
  but the plan stays blind until the first merge. Kept as a fallback for a spec with no epic, and
  not implemented: such a spec runs one task at a time instead.
- **Pushing the roadmap edit straight to the epic.** `spec_ship_epic` deliberately requires it to
  go through a task, and on a protected base it is impossible.
- **A checkmark commit per merge, into the next branch of the queue.** More commits and more
  ordering rules for something `spec plan` does not read.
- **Starting tasks by their `after:` lines rather than by waves.** Nothing parses `after:`; the
  waves list is the specification's answer to ordering.

## Consequences

- A phase of a roadmap can be handed over whole, and the person is asked once per wave, in one
  session, instead of once per task in several.
- The spec has exactly one writer during a run, which is what removes the conflicts; the price is
  that a task agent cannot close its own roadmap item, and `spec done` refuses to let it.
- Every merge into a wave costs the other branches a re-review when it carried code. That is the
  honest price of a receipt that pins what was reviewed.
- The coordinator is a long session that holds the queue. If it dies, the run is recoverable from
  `jig spec plan` and the task files — that is why there is no separate store — but the queue's
  order is not, and a new coordinator re-derives it from what is ready.
- A runtime without subagents runs the wave one task at a time under the same contract, reviewing
  in the same session and saying so in the pull request; the invariants do not change, only the
  parallelism.
- Rolling this back is removing a config key, a state key, a plan row, one refusal, a page section
  and a skill reference. Nothing migrates and no history is rewritten.
