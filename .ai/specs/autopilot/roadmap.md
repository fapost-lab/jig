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
- [ ] `agent-git-epics` — Agent git rights reach spec work — with the level allowing it, the
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
- [ ] Unattended mode — a local-only opt-in under which a run asks nothing: every stop becomes a
  safe default recorded in the pull request in plain words (the gate approved by the agent with the
  design in the PR, the most reversible option for an unmade decision, no destructive operation
  ever, a draft PR when repairs run out), and a finished run merges once CI passed, without
  overriding branch protection, then closes the task; ADR refining ADR-0009 (after: autopilot
  run — the defaults replace its stops)

## Phase 4 — Autopilot for a roadmap phase

Goal: a filed phase of a spec runs task after task, wave by wave. Done when: a two-task phase
ends in two pull requests without a human between them; the "Autopilot" page covers phase
runs.

- [ ] fog: phase run — ordering across waves, what a stop in one task does to the rest, and
  whether tasks of one wave run in parallel worktrees cannot be stated before single-task
  runs are proven

## Phase 5 — Seeing and routing

Goal: a person who does not live in a terminal can see where things stand, and skill
descriptions are checked for overlap. Done when: `jig status --html` opens offline and shows
tasks, findings, receipts and spec progress; CI fails on a skill description that stops
winning its own prompts; the docs describe the status page and how to open it.

- [x] `routing-evals` — Routing evals — prompt cases per skill, a shell scorer in `tests/`, run in CI
- [ ] Status page — `jig status --html`, one self-contained file (after: Phase 2 — findings and
  receipts are half of what it shows)

## Waves

1. Agent git rights as a local setting; findings ledger; routing evals
2. Review receipt; status page; agent git rights reach spec work
3. Autopilot run for a task
4. Unattended mode
5. fog: phase run

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
