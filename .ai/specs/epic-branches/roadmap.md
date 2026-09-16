# Roadmap — Epic branches: one release pull request per feature

Destination: a multi-phase feature is built on its own epic branch — each phase a task with its own
gate and pull request into the epic, tracked and cleaned up by housekeeping against that base — and
reaches `main` in one pull request and one release, while every other task still works against
`main` as today.

## Phase 1 — A base per task

Goal: Jig stops assuming every task forks from and lands on `main`. Done when: a task records its
base at start, and housekeeping, `task resume` and the touched-files helper judge it against that
base, with nothing changing for a task whose base is `main`.

- [x] `task-base-and-epics` — `base_branch` in task `state`, written by `jig task start`; resume, touched files and
  housekeeping ancestry resolve it as `origin/<base>`, with the base reflog read per base
  (ADR-0025, ADR-0026, ADR-0032 amended)
- [x] `task-base-and-epics` — Forge base check: a pull request merged into anything but the task's `base_branch` is flagged
  `wrong-base` and its workspace stays (after: `base_branch` in state — it is what the forge base is
  compared with)

## Phase 2 — Epic branches

Goal: a spec can be built on an epic and released once. Done when: `jig spec epic` declares and cuts
an epic, phase tasks start from it and land in it, closed phases keep their workspaces until the
epic reaches `main`, and CI guards both the epic and its final pull request.

- [x] `task-base-and-epics` — `jig spec epic <id>` writes the `Epic:` line and cuts `epic/<id>`; `jig task start` fetches and
  starts a linked task from the epic, refusing a missing or merged epic; `jig spec list` and
  `jig status` mark epic specs; `jig-idea` and `jig-task` explain the flow (after: phase 1 — a task
  needs a recorded base to start from an epic)
- [x] `task-base-and-epics` — Housekeeping keeps a closed phase task's workspace until its epic is merged into `main`
  (after: phase 1 — it needs the task's recorded base)
- [x] `task-base-and-epics` — CI: tests on push to `epic/*`; a check on a pull request from `epic/*` into `main` that fails
  when a release of its `JIG_VERSION` already exists (after: nothing — CI configuration only)

## Later

- [ ] fog: maintenance lines — `release/<major>.x` as a task base, tags cut from it, `jig self-update`
  within a major version; not needed until a second major version is developed beside the first

## Waves

1. `base_branch` in task state; CI for epics
2. Forge base check; `jig spec epic` and starting tasks from an epic; keeping phase workspaces
