# Roadmap — Release 2026-10-28

Destination: the next agent finds what the last one knew — the goal, a neighbouring
repository's work, open findings, a move — and the status page shows a spec's real progress.

Epic: epic/release-2026-10-28
Release: minor

## Phase 1 — Release

Goal: every item below is merged into the epic and released as one minor version. Done when:
the release's pull request into `main` is merged and the version is tagged.

- [x] `start-warns-empty-goal` — `jig task start` warns, and refuses at T3/T4, when a task has no goal
- [x] `cross-repo-task-links` — a task links a task or spec in a neighbouring repository, and `jig context` returns its documents
- [x] `spec-progress-from-task-state` — the status page and `jig spec list` count an item done when its task merged or was consolidated
- [x] `ship-findings-triage-task` — shipping with open P2/P3 files one triage task, and the autopilot's end message names it
- [ ] `task-move-updates-roadmap-2` — abandoning or moving a task records why and rewrites the roadmap item that names it (after: `cross-repo-task-links` — the link form; `spec-progress-from-task-state` — how an abandoned item counts)
- [ ] `release-notes-2026-10-28` — the release notes, the changelog, the docs the release touches and the version raise (after: every other item — it describes their diffs)

## Waves

1. start-warns-empty-goal; spec-progress-from-task-state
2. cross-repo-task-links; ship-findings-triage-task
3. task-move-updates-roadmap-2
4. release-notes-2026-10-28
