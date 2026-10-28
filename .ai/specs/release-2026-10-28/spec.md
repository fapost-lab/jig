# Release 2026-10-28 — what an agent should have known

## Release plan — approved by the agent, not a human

The owner answered the plan's questions in conversation on 2026-10-28 (T3 gates approved by
the agent, the fifth task included, level `minor`, progress through Telegram) and left; this
document was not shown to them before the declaration's pull request. The merge of that pull
request is where a person agrees.

### Why this release

Five faults seen on 2026-10-28, in this repository and in fapost-core, share one shape: a fact
the next agent needed existed, but not where that agent reads.

- The status page showed a spec as not moving while its tasks merged: a phase run's checkmarks
  stay on the local epic until the next pull request.
- Open P2/P3 review findings of an autopilot run went into a pull request the autopilot merged
  itself; nobody saw them.
- A Core task started from scratch while its prior design lay in a neighbouring repository's
  task, which Core's `jig context` cannot see.
- A task moved to another repository was recorded only in its gitignored `task.md`; the
  spec's roadmap still named the old repository, and the next agent followed it.
- A T3 task was started with a template-only `task.md`.

### What goes in, in order

Breaks work first, then lies about state.

1. `start-warns-empty-goal` — `jig task start` warns, and refuses at T3/T4, when a task has no
   goal. T1.
2. `cross-repo-task-links` — a task can link a task or spec in a neighbouring repository, and
   `jig context` returns its documents. T3.
3. `spec-progress-from-task-state` — the status page and `jig spec list` count an item done
   when its task merged or was consolidated, not only by its checkbox. T2.
4. `ship-findings-triage-task` — shipping with open P2/P3 files one triage task with all of
   them, and the autopilot's `end` message names it. T3.
5. `task-move-updates-roadmap` — abandoning or moving a task records why and rewrites the
   roadmap item that names it. T3; after 2 (the link form) and 3 (how such an item counts).
6. `release-notes-2026-10-28` — the release notes, the changelog and the docs pages the
   release touches, and the version raise. T2, last.

### What stays out

- `resume-after-stash-conflict` — started, its branch cut from `main`, so `jig spec link`
  refuses it. It reaches this release if it merges into `main` before the epic is finished.
- The specs `issue-intake`, `knowledge-sections`, `project-hooks`, `system-docs` — not
  scheduled.

### Level

`minor`: new flags and behaviour (`task abandon --reason`, links between repositories, a triage
task filed by `task ship`), nothing an existing project must change to keep working. The notes
task checks this against the diffs.
