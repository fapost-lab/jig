# Queue watch — one agent drains the queue on its own

Depth: normal, with the independent failure hunt — the watcher runs for hours without a person
and merges on green CI, so a wrong step reaches main unread; the design space is small, because
`jig-autopilot` already runs one task and a set of tasks.

## Idea

The owner, 2026-11-13, as relayed by the session that started this one:

> One agent that watches the backlog and takes a task as soon as one appears: a queue mode for
> `jig-autopilot` — loop `jig queue next` → start in its own worktree → run the route to merge or
> to a human stop → next; at most `autopilot.parallel` tasks at once; tests with
> `JIG_TEST_JOBS=3` (machine shared); sleeps when the queue is empty (in Claude Code `/loop` wakes
> a session).

The owner, 2026-11-14:

> Наблюдатель за тачками не обязательно работает только с ишью. Если я сам создам задачу через юай
> он должен так же ее подхватить.

(The watcher is not only for issues. A task I create myself in the UI must be picked up the same
way.)

## Goal and problem

- Who is worse off without this, and how: the owner, who keeps a session open to start each next
  task by hand and to fill a free slot — and who, doing it by attention, took a lower priority
  over a higher one three times in two days (2026-11-12, 2026-11-13).
- What is true when the work is done: a task put in the queue from anywhere — an issue, Jig UI, a
  conversation — reaches a merge or a stop that names what is needed, with nobody starting it; at
  most `autopilot.parallel` tasks run at once; the owner sees whether the watcher is alive and
  why it is idle.

## Stress test

- Hidden assumptions — "this holds only if …":
  - The watcher survives hours of context compaction only if no decision lives in the session:
    every step is read from the queue, task state and the autopilot journal.
  - "Takes everything `queue next` names" is safe only if `queue next` never names a task that
    cannot be taken now — a stopped run, a draft, a half-filed task, a release.
  - A finishing background subagent wakes a `/loop` session in Claude Code.
- The main trade-off: how much the watcher does alone versus how much waits for the owner — every
  safeguard below trades throughput for a stop the owner reads.
- The weakest point: a slot whose agent died (usage limit, app restart, laptop sleep, exit 139)
  is told from a working one only by silence in its journal, so a dead agent holds its slot until
  the threshold passes.
- Failure modes — cause, what breaks, the signal that shows it (from the independent hunt, ranked):
  1. `queue next` knows nothing of autopilot runs — a stopped, drafted or `not merged` task is
     advised again and the watcher spins on it — the same task id in consecutive ticks while
     slots stay free.
  2. A subagent dies — its slot stays held for good while the record says alive — recent ticks,
     full slots, no journal or file change for hours.
  3. Dependents of a stopped task wait for ever — it reads as an empty queue and the watcher
     sleeps — `waiting`, not `empty`, in `queue next --json`.
  4. The watcher takes a release's notes task — a release ships with nobody looking — an
     unplanned version and changelog section.
  5. A task is taken between `task new` and its `task.md` — it starts on an empty goal; a T3 gets
     an agent-approved design built on a guess — `task.md` holding only the stub.
  6. "Taken" records outlive the watcher by `checkout.busy_ttl`, and Codex writes none — the
     owner's own session sees tasks as taken, or two sessions start one task — two branches for
     one id.
  7. Test parallelism is per process — two slots, repairs and the owner's session page the
     machine; timeouts and exit 139 count as failures and push tasks to drafts.
  8. `task ship` waits for CI inside the watcher's session — no ticks for up to `agent.ci_timeout`;
     neighbouring merges conflict and spend repairs.
  9. Agent-approved T3 designs pile up overnight and may contradict each other.
  10. In an attended clone stops pile up while the watcher moves on.
  11. Nothing bounds spend — loops of 1 and 8 burn tokens with nothing to show.
- Other shapes considered, and why this one: a daemon (`jig watch`) that starts the agent's CLI
  per task — rejected, see Decisions; the rule kept as prose in `jig-autopilot` §7 — rejected,
  see Decisions.

## Scope and non-goals

- In scope: `queue next` refusing what cannot be taken now; one command that decides each step of
  the watcher; the watcher's record, its `status --json` block and a stop command; safeguards
  against dead agents, repeated failure, stacked T3 designs; a queue mode of `jig-autopilot`
  driven by `/loop`; the Jig UI item, delivered as a contract and an item in their spec.
- Not doing: work with issues (two tasks of their own, below); a daemon or anything Jig starts by
  itself; Codex as the watcher's runtime; test parallelism (task `verify-waits-for-a-slot`).

## Decisions

- The spec is the queue watcher only; it takes any queued task, whatever filed it. — rejected:
  issue work in the same spec, because reading an issue, filing a task from it and answering
  already work by hand; their gaps are two tasks: a linked issue makes `task ship` write
  `Closes #n` (today it rests on a line of prose in `task.md`), and `status --json` counts issues
  nobody answered. — rejected: building on `.ai/specs/issue-intake/`, which is about requests
  from outside the team and documentation-only fixes.
- Each step is decided by one script command (working name `jig autopilot tick`) from durable
  state, answering one action: start a task, wait (slots full), sleep (queue empty), blocked
  (everything waits on a stop), slot dead, stop (the watcher was stopped). The agent only carries
  it out (ADR-0001). — rejected: the loop as prose in `jig-autopilot` §7, because the prose rule
  "take `jig queue next`" was broken three times in two days.
- `queue next` stops advising what cannot be taken now: a task whose autopilot run is stopped or
  ended in a draft or `not merged`, a task whose `task.md` holds only the stub, a task that raises
  the version. It answers "blocked by a stop of <id>" apart from "empty". — rejected: a filter of
  the tick's own, because two answers to "what next" drift apart.
- The watcher is one long-lived Claude Code session woken by `/loop`: while tasks run, a finishing
  subagent wakes it; with the queue empty it sleeps about 20 minutes, so a task filed in Jig UI
  waits up to that long. — rejected: a daemon `jig watch` starting the agent's CLI per task,
  because it is a new long-running process with its own permission and Windows problems.
- It takes every class up to T3 that `queue next` names, but holds at most one T3/T4 in flight;
  in an unattended clone that gate is approved by the agent as `jig-autopilot` §5 says. It never
  takes a task that raises the version: a release stays the person's. — rejected: skipping T3/T4,
  because architectural work would stand until the owner takes it.
- It works in attended clones too: a stop frees its slot, the task waits for a person in the list
  of stops, the watcher goes on. — rejected: unattended clones only, because an ordinary user
  would have no watcher.
- A stopped task frees its slot. — rejected: holding the slot until a person answers, because one
  stuck task would take half the capacity for good.
- Safeguards: a run whose journal has been silent past a threshold is recorded as stopped
  ("the agent vanished"), its slot freed, the owner told on Telegram, and the task is not
  restarted by itself; two runs in a row that end without a merge stop the watcher, with the
  reason on Telegram; "everything blocked" reaches Telegram once, not every wake-up; `task ship`
  runs in the background and merges go one at a time, so the second sees the first. — rejected:
  a spend budget key, because zero-config and the breaker already stops the loops that burn it.
- Each tick writes the watcher's record — alive, last tick, the slots and their tasks, the last
  action and why it is idle — shown as a `watcher` block in `jig status --json`; a stop command
  ends the watcher and withdraws its "taken" records.
- Jig UI shows the block and a stop button; it cannot start a Claude Code session, so it shows the
  command that does. Jig's side is the contract; the UI work goes as an item into
  `fapost-lab/jig-ui`'s spec through a pull request, never a task there.
- Depends on `start-follows-the-queue` (`next` without started tasks, position by priority) and on
  `verify-waits-for-a-slot` (machine load; `verify.jobs` in place of `JIG_TEST_JOBS=3` belongs
  there). — rejected: `verify.jobs` as an item of this spec, because a per-process key does not
  bound the machine.

## Open questions

- The tick command's final name, and the silence threshold for "the agent vanished" (proposed
  2 hours) — settled at the analysis of the tick's task.
- Whether a T3 the owner runs in another session counts towards "one T3/T4 in flight" — decides
  what the tick reads.
- The watcher sorts new issues itself — the owner's "later"; needs the two issue tasks first.
- Codex as the watcher's runtime — Codex has no session id, so it writes no "taken" record.
- Waking the watcher from Jig UI without the ~20 minute sleep — no way to wake a Claude Code
  session from outside is known.
- GitLab issues through `glab` — after the GitHub issue tasks.

## Set aside

- None.

## Assumptions left untested

- A finishing background subagent wakes the `/loop` session — taken at normal; the first real
  run of the queue mode tests it.
- About 20 minutes of sleep on an empty queue is short enough — taken from the owner's yes; the
  first week of use tests it.
