# Contract extensions — Jig that a program can read and plan with

Depth: normal — split from the `jig-ui` spec (PR #232) with its decisions already taken by the
maintainer; what is new here is only the boundary.

Origin: on 2026-10-14 the maintainer moved Jig UI and everything about it into its own project,
`fapost-lab/jig-ui`, where its spec now lives. What Jig itself must provide stays here, described
as extensions of Jig's contracts that are useful without any UI.

## Idea

The maintainer's words, translated: Jig UI and all that is connected with it belong in a separate
project; Jig carries a link to Jig UI as an additional capability; the changes in Core that the UI
needs are shown as extensions of the contracts.

What the UI needs from Jig: to read every task, spec and epic of a clone as data; to know what
needs a person and what a person may do next; to keep priority, order and dependencies of tasks
and epics in Jig rather than in the UI; and to ask a running task to pause without losing the
request.

## Goal and problem

- Who is worse off without this, and how: any program that wants Jig's state — Jig UI, CI, a bot,
  an agent choosing what to take next — has to parse text written for a person. Priority and
  order exist nowhere, so they end up in whichever tool a person happens to use, invisible to the
  agents.
- What is true when the work is done: the commands that report state have a stable JSON form
  pinned by tests; a per-clone queue holds priority, order and dependencies, written by one
  command that refuses a stale write; a pause request reaches a running task and is honoured.

## Stress test

- **No machine-readable output exists.** Commands print text; only `gh` is called with `--json`.
- **The `state` file has no planning fields** and is written last-write-wins without a lock
  (ADR-0008); a priority written there by one writer can be lost to a concurrent `jig task set`.
- **One clone, one place.** A worktree borrows its task directory from the main checkout
  (ADR-0029), so the main checkout lists every task, and a per-clone file has one natural home.
- **The status page already computes "needs you"** (adr-20260922-the-status-page-stays-current-without-a-server);
  attention as data must reuse that logic, not make a second copy that drifts.
- **ADR-0002 holds:** JSON is written by shell, without `jq` or any new dependency.
- Weakest point: whether a running autopilot or agent reads a pause request at a stage boundary
  is not verified.

## Scope and non-goals

- In scope: JSON output and stable failure codes; the queue; attention items and legal actions as
  data; pause and resume requests.
- Not doing: anything with a server, a port or a watcher — that is Jig UI's; next-task selection
  until the queue has been used.

## Decisions

- Jig UI is a separate, optional project; Jig carries only a mention of it and works exactly as
  before without it (maintainer, 2026-10-14). Its plans live in `fapost-lab/jig-ui`.
- Everything a UI shows or changes lives in Jig, as new files or new fields (maintainer,
  2026-10-14). Rejected: a UI-side store of priority and order.
- Priority, order and dependencies live in one queue file per clone, not under git, in the main
  checkout beside `.ai/runtime/`; the only writer is a Jig command, atomic and checked against a
  revision the caller read (maintainer, 2026-10-14). Priority is 0–5, position is sparse
  (step 100), epics are a level of the same queue. Rejected: fields in each task's `state`
  (order scattered, last-write-wins loses moves) and a queue file under git (a drag becomes a
  commit, conflicts in pull requests). Prior art: aif-handoff (separate priority and sparse
  position), ai-workspace (revision checked on write).
- A pause request is sticky (maintainer, 2026-10-14): it holds until honoured or cancelled,
  whatever stage the task reaches in between. The agent finishes the step it is on, does not start
  another stage, sets the pause field (ADR-0012) and clears the request in the same Jig command.
  The request lives in the queue file (one writer), not in `state`. Rejected: dropping a request
  the task has moved past.
- Which actions a person may take in a given state is reported by Jig; no consumer keeps its own
  copy of that table.

## Open questions

- Queue file format, command names and the revision scheme.
- JSON envelope: one shape for all commands, how it is versioned.
- Whether `jig init` gets a hook that lets an installed UI register the project, without making
  the UI a dependency of Jig.

## Assumptions left untested

- That a running autopilot or agent reads a pause request at its next stage boundary — to check
  against `task autopilot` and ADR-0012 before the requests item is designed.
