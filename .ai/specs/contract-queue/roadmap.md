# Roadmap — Contract queue

Destination: priority, order, dependencies and pause requests live in Jig, written by one command
that refuses a stale write, and agents honour them.

Epic: epic/contract-queue
Release: minor

## Phase 1 — The queue and requests

Goal: priority, order, dependencies and pause requests exist in Jig and agents honour them. Done
when `jig queue` orders tasks and epics, a stale write is refused, `jig status` shows the order,
and a pause request stops a running task at its next stage boundary.

- [x] `queue-file` — queue file and commands — one file per clone beside `.ai/runtime/`, not under git; priority 0–5, sparse position (step 100), dependencies with a reason, epics as a level; atomic write checked against the clone revision; a reorder moves one item
- [x] `queue-status-context` — queue in status and context — `jig status` and `jig context` show a task's place (after: queue file — they read it)
- [x] `queue-json` — queue as JSON (after: queue file — it is what is read; contract-extensions' task list — read together, same envelope)
- [x] `pause-requests` — pause requests — sticky, kept in the queue file, honoured at the next stage boundary and cleared by the same command; resume stays the direct `jig task resume` (after: queue file — the request lives there; contract-extensions' legal actions — they say when a pause is offered)
- [x] `task-new-json` — task new as JSON — `jig task new` takes a short description as an argument and answers in the shared envelope, a refusal with its failure code (an id already taken, an invalid id), so a program can file a task without writing a file first (after: contract-extensions' envelope and failure codes — it is answered in them)
- [x] `queue-claim-fixes` — exact claim and review leftovers of the queue — a claim at revision 0 lets at most one of two first writers land, the clone-revision regression test fails on the old code, and the queue and `task start` share one answer to which epic a task is built on (after: queue file — it fixes what that task left open)
- [x] `release-notes-0-31-0` — release notes — the 0.31.0 changelog, known issues and roadmap pages written against the diffs, and the other docs pages walked (after: every other item — it describes them)
- [x] `task-goal-without-template` — a clean goal — a task filed without `--goal` reads its goal as empty in the JSON, not as the template's comment (after: task new as JSON — it is that field)
- [x] `queue-refusal-codes` — pause request refusals and release wording — a request on a paused or closed task is refused as `failed` even when a request is pending, and the 0.31.0 pages say what the commands do (after: pause requests — they are its codes)
- [x] `status-tests-age-flake` — status tests without a minute boundary — the status page tests that expect "stopped just now" pass when the runner takes over a minute (after: nothing — CI of every pull request into the epic hits it)
- [ ] `pause-request-without-autopilot` — a pause request in a session without autopilot — an agent working on the task without autopilot sees a pending request and honours it (after: pause requests — it is the gap they left)
- [ ] fog: next task by priority, order and dependencies — how an agent or a person is advised what to take is not stated yet
- [ ] fog: registration hook in `jig init` for an installed UI — moved from contract-extensions when its epic was finished

## Waves

1. Queue file and commands; task new as JSON.
2. Queue in status and context; queue as JSON; pause and resume requests.

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
-->
