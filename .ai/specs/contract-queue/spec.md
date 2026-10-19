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
  resume requests; filing a task from a program (`jig task new` in the JSON envelope).
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
- Resume is not a request (maintainer, 2026-10-19): while a task is paused no agent works on it,
  so nobody would read a resume request; `jig task resume`, already a legal action, resumes it at
  once. Jig UI's drop out of the paused column calls it directly. The request line keeps a kind
  column, so a resume request can be added later without a new format. Rejected: a sticky resume
  request (it would wait for a reader that never comes).
- Released on its own epic, after `contract-extensions` (maintainer, 2026-10-14).
- The epic is released `minor` (maintainer, 2026-10-19): new commands and fields, nothing existing
  changes its meaning, as with `contract-extensions` (0.29.0).
- `jig task new` answers in the JSON envelope and takes a short description as an argument
  (maintainer, 2026-10-19): Jig UI's Phase 2 files a minimal backlog task from the page and has to
  tell an id already taken from any other refusal. Rejected: the UI writing a file for `--from`
  and reading the exit status, which names no reason.

## Open questions

- Whether `jig init` gets a hook that lets an installed UI register the project, without making
  the UI a dependency of Jig (moved from `contract-extensions` when its epic was finished).

## Assumptions left untested

- Checked by `pause-requests` (2026-10-19): `jig task autopilot <id> stage` read nothing before;
  it now honours the request, since it is the one command an autopilot run calls at every stage
  boundary. A session without autopilot calls nothing there and does not see a request
  (adr-20261019-a-pause-request-is-honoured-at-the-stage-boundary).

## Release notes

Lines the epic's release pull request carries into `docs/changelog.mdx`, beside the new commands:

- `jig task autopilot <id> stage` on a paused task now refuses with exit code 4 instead of entering
  the stage, and a pending pause request makes it pause the task the same way.
