# Contract queue — priority, order and pause requests that live in Jig

Depth: normal — split from `contract-extensions` on 2026-10-14 with its decisions already taken by
the maintainer; it carries that spec's planning half unchanged.

Origin: `contract-extensions` held two halves, Jig that a program can read and Jig that a program
can plan with. The maintainer chose to release them separately, and an epic covers a whole spec
(ADR-0040), so the planning half moved here. It builds on `contract-extensions`: its JSON envelope,
its per-clone revision and its legal actions.

## Idea

The maintainer's words, translated: Jig UI and all that is connected with it belong in a separate
project; the changes in Core that the UI needs are shown as extensions of the contracts.

What the UI needs from Jig, in this spec: to keep priority, order and dependencies of tasks and
epics in Jig rather than in the UI, and to ask a running task to pause without losing the request.

## Goal and problem

- Who is worse off without this, and how: priority and order exist nowhere, so they end up in
  whichever tool a person happens to use, invisible to the agents; a person who wants a running
  task to stop has no way to say so that the agent will see.
- What is true when the work is done: a per-clone queue holds priority, order and dependencies,
  written by one command that refuses a stale write; a pause request reaches a running task and
  is honoured.

## Stress test

- **The `state` file has no planning fields** and is written last-write-wins without a lock
  (ADR-0008); a priority written there by one writer can be lost to a concurrent `jig task set`.
- **One clone, one place.** A worktree borrows its task directory from the main checkout
  (ADR-0029), so a per-clone file has one natural home.
- **ADR-0002 holds:** the queue is read and written by shell, without `jq` or any new dependency.
- Weakest point: whether a running autopilot or agent reads a pause request at a stage boundary
  is not verified.

## Scope and non-goals

- In scope: the queue and its command; the queue in `jig status`, `jig context` and JSON; pause and
  resume requests.
- Not doing: anything with a server, a port or a watcher — that is Jig UI's; next-task selection
  until the queue has been used.

## Decisions

- Priority, order and dependencies live in one queue file per clone, not under git, in the main
  checkout beside `.ai/runtime/`; the only writer is a Jig command, atomic and checked against the
  clone revision the caller read (maintainer, 2026-10-14; the revision is `contract-extensions`').
  Priority is 0–5, position is sparse (step 100), epics are a level of the same queue. Rejected:
  fields in each task's `state` (order scattered, last-write-wins loses moves) and a queue file
  under git (a drag becomes a commit, conflicts in pull requests). Prior art: aif-handoff
  (separate priority and sparse position), ai-workspace (revision checked on write).
- A reorder is one command that moves one item (sparse position), never a renumbering a consumer
  issues as several commands: those are not atomic, and an agent can read a half-applied order
  between them (raised by Jig UI's failure hunt, 2026-10-14).
- A pause request is sticky (maintainer, 2026-10-14): it holds until honoured or cancelled,
  whatever stage the task reaches in between. The agent finishes the step it is on, does not start
  another stage, sets the pause field (ADR-0012) and clears the request in the same Jig command.
  The request lives in the queue file (one writer), not in `state`. Rejected: dropping a request
  the task has moved past.
- Released on its own epic, after `contract-extensions` (maintainer, 2026-10-14).

## Open questions

- Queue file format and command names.
- The release level of this spec's epic — asked when the epic is declared.
- Whether `jig init` gets a hook that lets an installed UI register the project, without making
  the UI a dependency of Jig (moved from `contract-extensions` when its epic was finished).

## Assumptions left untested

- That a running autopilot or agent reads a pause request at its next stage boundary — to check
  against `task autopilot` and ADR-0012 before the requests item is designed.
