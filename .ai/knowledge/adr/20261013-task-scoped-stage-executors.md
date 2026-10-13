---
id: adr-20261013-task-scoped-stage-executors
type: adr
status: accepted
date: 2026-10-13
domains:
  - task
  - config
  - skills
paths:
  - scripts/lib/task.sh
  - skills/jig-autopilot/references/phase-run.md
  - schemas/state.md
summary: Task-specific stage executor choices override clone-local settings and freeze before task start, preserving independent worktrees and the existing phase merge queue.
reviewed_at: 2026-10-13
---
# A roadmap wave chooses stage executors in each task's own state before it starts

## Context

Phase 2's `executor.*` keys are personal and shared by every worktree in one
clone. The existing phase-run coordinator starts separate task agents in
separate worktrees concurrently. Changing the shared local file between starts
would race with agents reading it later, so it cannot express two assignments
in one wave. The route evidence, review receipt and merge queue already belong
to each task; no new LLM scheduler is needed in Jig scripts (ADR-0001).

## Decision

- Four optional state keys, `executor_implement_runtime`,
  `executor_review_runtime`, `executor_implement_model` and
  `executor_review_model`, override their corresponding local config keys for
  one task. Each field inherits independently. `inherit` removes a task value.
- `jig task set` validates these values like the local config: runtime is
  `claude` or `codex`; model is an opaque nonempty scalar. It accepts changes
  only before `task start` records the branch. This conservative freeze covers
  both autopilot and manually run stages, which have no common stage-start
  record. At start, Jig snapshots all four effective values, even empty ones,
  and their `task`, `local config` or `default` sources. A later change to the
  shared local file cannot redirect a running task. A wrong choice after start
  requires stopping that task and filing a corrected one.
- `jig task route` shows the effective choice and whether it came from task
  state or local config. An absent choice keeps the current route. The agent
  follows the same bounded cross-runtime handoff as Phase 2. Scripts never
  launch an LLM, write an actor into a receipt or change completion gates.
- Phase-run keeps one writing agent per task worktree and one merge queue.
  Reviewers use fresh contexts. When an earlier task merges, remaining task
  branches update and recheck their receipt as phase-run already requires.

## Alternatives

- **Rewrite `config.local.yaml` before each launch:** agents can read it after
  another task changed it. A restore cannot remove that race.
- **A separate clone for every agent:** duplicates local state and obscures the
  existing task and merge queue without improving the ordinary wave.
- **Multiple writers in one task worktree:** loses ownership of a diff and can
  make a receipt describe an intermediate result.
- **Mutable assignment until each stage starts:** manual routes have no
  machine-readable stage-start record. A pre-start freeze is reproducible.

## Consequences

Two tasks in one wave can use different runtimes and models without a shared
configuration race. Assignments and effective snapshots are local workspace
state, never committed
project policy. A correction after start takes a new task, which is more work
but preserves the promised executor and review boundary. Removing the feature
leaves only ignored state keys; committed work needs no migration.
