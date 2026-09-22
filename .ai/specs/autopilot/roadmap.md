# Roadmap — Autopilot

Destination: a user who opted in hands a task to Jig and gets back an open pull request or a
stop that names a human decision, with completion refused by scripts while a serious finding
is open or the review no longer matches the code.

Epic: epic/autopilot

## Phase 1 — Commit rights are the user's choice

Goal: an agent commits, pushes or opens a pull request exactly as far as the clone's owner
allowed, and not at all by default. Done when: with `agent.git: pr` in `config.local.yaml` a
T1 task ends in an open pull request; without it, nothing changes; `jig status` says which
queue it is counting.

- [x] `agent-git-rights` — Agent git rights as a local setting — ADR replacing the unwritten "agents do not
  commit", the whitelisted key, skills that commit/push/open a PR up to the level, `jig
  status` and the README telling the two queues apart
- [x] `agent-git-epics` — Agent git rights reach spec work — with the level allowing it, the
  agent pushes the epic and opens the spec's final pull request (after: agent-git-rights — it
  uses that task's key and `jig task ship`)

## Phase 2 — Gates a script enforces

Goal: completion stops on its own when review found something serious or no longer matches
the code. Done when: a planted P1 or a change after review makes marking the task ready
(`task set … status ready`, the end of verification) and consolidation refuse, with a message naming what to do; the docs say how findings are
recorded and what to do when completion is refused.

- [x] `findings-ledger` — Findings ledger — review records findings with severity and status through a `jig task`
  subcommand; open or unre-reviewed P0/P1 refuse completion
- [x] `review-receipt` — Review receipt — review pins the reviewed working tree and the approved documents; changed
  content or a changed document refuses completion; required for T4 (after: findings ledger — the
  receipt records the ledger's state at review time)

## Phase 3 — Autopilot for one task

Goal: one task runs from classification to its end state without a human, stopping only on
the listed stops — or, in unattended mode, not stopping at all and ending in a merge that CI
deploys. Done when: a T1 and a T2 task each reach an open pull request unattended, an unattended
run of a T1 task ends merged after green CI,
and every stop condition has a test that ends the run; an "Autopilot" guide page on the docs
site says how to start a run, where it stops and what to do at each stop.

- [x] `autopilot-run` — Autopilot run for a task — entry, stop conditions, repair limit, a run report (after:
  Phase 1 — it ends in a commit or PR; Phase 2 — its stops on findings and stale review are
  those scripts)
- [x] `unattended-mode` — Unattended mode — a local-only opt-in under which a run asks nothing: every stop becomes a
  safe default recorded in the pull request in plain words (the gate approved by the agent with the
  design in the PR, the most reversible option for an unmade decision, no destructive operation
  ever, a draft PR when repairs run out), and a finished run merges once CI passed, without
  overriding branch protection, then closes the task; ADR refining ADR-0009 (after: autopilot
  run — the defaults replace its stops)
- [x] `local-setup` — Local setup — the agent asks, in plain words and one question at a time, how far it may go
  with git, whether to stop and ask or decide and record, how many agents to run at once, how long to
  wait for CI and how long to keep finished work; shows the resulting `.ai/config.local.yaml` whole and
  writes it after a yes, through `jig config set <key> <value> --local`, which accepts only local keys
  with valid values and writes atomically; offered by `jig init` and on "set up Jig for me" (after:
  unattended mode — its keys are among the answers)

## Phase 4 — Autopilot for a roadmap phase

Goal: a filed phase of a spec runs wave by wave, the tasks of a wave in parallel agents. Done
when: a phase with a two-task wave ends in two pull requests without a human between them, the two
tasks having run at the same time in their own worktrees; a stop in one task holds the next wave and
reaches the human as one message; the "Autopilot" page covers phase runs.

- [x] `phase-plan` — Phase plan — `jig spec plan <id> --phase <n>`: each wave's items, their task ids and task
  states, and which tasks may start now under the strict-wave rule; read by the coordinator and the
  status page
- [ ] Phase run — `jig-autopilot` runs a filed phase: tasks of a wave in parallel worktrees up to
  `autopilot.parallel`, the coordinator owning spec files and the merge queue, bringing branches up to
  the base with re-review after each merge, gathering stops into one message (attended) or ending a
  stuck task as a draft (unattended), and checking reviewers' ledgers (after: phase plan — it decides
  what may start; unattended mode — an unattended phase run merges through it)
- [x] `worktree-leaves-on-landing` — A closed task's worktree leaves when its change lands on its base,
  not with its workspace, so a phase run's worktrees do not pile up until the epic ends

## Phase 5 — Seeing and routing

Goal: a person who does not live in a terminal can see where things stand, and skill
descriptions are checked for overlap. Done when: `jig status --html` opens offline and shows
tasks, findings, receipts and spec progress, answers "what needs me" first and stays current
without being regenerated by hand; CI fails on a skill description that stops
winning its own prompts; the docs describe the status page and how to open it.

- [x] `routing-evals` — Routing evals — prompt cases per skill, a shell scorer in `tests/`, run in CI
- [x] `status-page` — Status page — `jig status --html`, one self-contained file (after: Phase 2 — findings and
  receipts are half of what it shows)
- [x] `status-page-live` — Live status page — answers "what needs me" first, then what is running and
  spec progress; rewritten by jig on every task state change and self-refreshing, `jig status --open`
  (after: status page — it reshapes that page; autopilot run — it shows the run's stage and stops)

## Phase 6 — Release

Goal: the public documentation tells one story about what this epic gave the user, and the epic
reaches the default branch as one release. Done when: the docs site's front page, Concepts,
Comparison, the README and the navigation present agent git rights, review findings and receipts,
autopilot (attended and unattended), the status page and phase runs as one path — not as pages
each task added on its own; every page this epic touched is re-read against the shipped behaviour;
CONTRIBUTING says which `jig` a contributor runs, since developing Jig with Jig means two
installations on one machine; the version is raised in the final pull request from the epic.

- [ ] Public docs pass — read the whole docs site and README as a new user would, bring the
  shared pages up to the epic's features, fix what the per-task pages say differently from what
  shipped, and tell a contributor in CONTRIBUTING which `jig` runs where: this checkout's own
  `.ai/scripts/jig` (link mode, a tracked symlink, so a worktree runs its own branch's code) against
  the released one on `PATH`, which never delegates to a project's copy (after: every other item —
  it describes what they built)

## Waves

1. Agent git rights as a local setting; findings ledger; routing evals
2. Review receipt; status page; agent git rights reach spec work; live status page
3. Autopilot run for a task
4. Unattended mode; `worktree-leaves-on-landing`
5. `local-setup`; phase plan
6. Phase run
7. Public docs pass

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
-->
