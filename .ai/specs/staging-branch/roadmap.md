# Roadmap — Staging branch

Destination: in a project that names a stage branch, a task goes from `main` to stage through
`jig task ship`, waits for QA without blocking other work, and reaches a pull request into `main`
on one "prepare for prod" — said by a person or run by CI — while a project without a stage
branch works exactly as before.

Epic: epic/staging-branch
Release: minor

## Phase 1 — Ship to stage

Goal: Jig does the stage step the team does by hand today, and everyone sees which tasks are on
stage. Done when: in a test project with `git.stage_branch: stage`, `jig task ship` leaves the
task branch merged into origin's stage and the task listed as waiting for QA, with no pull
request into `main`.

- [ ] Turn stage on — `git.stage_branch` in the shared config, offered by `jig init` and
  `jig-setup` when origin has a `stage`/`staging` branch.
- [ ] Ship a task to stage — `jig task ship` in a stage project merges the task branch into a
  fresh temporary worktree of stage, the agent resolves any conflict, stage is pushed (retried
  from a fresh fetch on rejection, never forced); no pull request into `main`. (after: Turn stage
  on — it reads the key)
- [ ] See a task's stage state — on stage / behind stage derived from git by branch name, in
  `jig task list --json`, `jig status` and housekeeping; a pull request merged into stage is no
  longer `wrong-base`. (after: Turn stage on — it reads the key)
- [ ] Wait for QA — a state of its own that frees the current-task slot and the queue; a new
  commit makes the task current again; autopilot stops there and never promotes. (after: Ship a
  task to stage — the state starts where that step ends)

## Phase 2 — Prepare for prod

Goal: one command takes a tested task to a pull request into `main`, from a person's checkout or
from a CI job. Done when: run on a runner with no Jig workspace and given a tested stage commit,
it opens the pull request into `main` and prints its link, and it refuses a task whose tip is not
in that commit.

- [ ] Prepare a task for prod — refuses unless the task tip is in the tested stage commit;
  merges `main` into the task branch on conflict; opens the pull request into `main`; prints the
  link; reads git and the forge only. (after: See a task's stage state — the refusal is that
  check)
- [ ] fog: who merges the promotion pull request — a shared `human` | `auto` setting beside
  `agent.git` and `release.merge`; cannot be stated until it is clear how the three combine.

## Phase 3 — Stage over time

Goal: stage stays explainable as tasks come and go, and a fully automated team can drive it.
Done when: `jig status` names tasks on stage nobody promoted for long and stage work no task
branch owns.

- [ ] Stage drift report — tasks on stage long unpromoted, and stage commits from no live
  `task/*` branch. (after: See a task's stage state — the report is built on it)
- [ ] fog: CI-driven promotion — which tasks one green stage run promotes (all contained in the
  tested commit, or those it names), and whether Jig's stage step stands aside when CI merges
  into stage itself.

## Waves

1. Turn stage on
2. Ship a task to stage; See a task's stage state
3. Wait for QA; Prepare a task for prod; Stage drift report

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
- A wave entry names an item by its title (the text before its first ` — `) or its task id,
  entries separated by `;` — `jig spec plan` reports an entry that names no item or several.
-->
