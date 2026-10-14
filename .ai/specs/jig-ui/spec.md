# Jig UI — a local control center for Jig projects

Depth: normal — the shape is mostly set by the concept, but several decisions are irreversible (who owns planning fields, stack vs ADR-0002, how projects are found).

## Idea

From the concept document (`jig-ui-concept.md`, written by the maintainer, translated):

Jig UI is a separate repository and installable package. Frontend and backend are one local
application: the backend reads projects and serves an API, the frontend shows them in a
browser. Jig Core stays an independent shell framework that works without the UI. One Jig UI
instance connects many local projects and shows both one project's state and the whole
workspace. First version is local-first. The goal is to make the state, order and progress of
Jig tasks visible in one interface.

Principles stated in the concept:

- Task files and artifacts are the source of truth; the UI keeps no parallel task database.
- The UI keeps only a registry of connected projects and interface settings.
- Changes with an existing Jig command go through the CLI; direct file writes only for agreed
  planning fields.
- The board position ("how we plan the work") and the Jig SDLC state ("what happens in the
  workflow") are two independent dimensions; moving a card never starts a workflow.
- Priority (importance) and rank (order inside a queue) are visible to agents through project
  files.
- `jig init` optionally and idempotently registers the project in an installed UI; a UI
  failure never fails `init`.
- Starting hypotheses: Node.js + Vue, SSE for updates. Screens: workspace dashboard, project
  dashboard, project kanban, task details, activity/attention.

## Goal and problem

- Who is worse off without this, and how: a person running several agents across several
  projects cannot see, in one place, what is running, what waits for them and in what order
  work should go. Today `jig status` is a text report per checkout and `jig status --html` is
  a per-clone page.
- What is true when the work is done: (to settle — see open questions).

## Stress test

Findings from checking the concept against this repository (0.26.0):

- **The status page is a neighbour, not a rival.** `jig status --html` (adr-20260922-the-status-page-stays-current-without-a-server)
  is a read-only, serverless, per-clone page. Jig UI is a different level: many projects, an
  interactive board, priority and ordering of tasks and epics, task creation, and later remote
  management. The page stays as it is; the UI may reuse its "needs you" logic as a source of
  attention signals instead of recomputing it.
- **One clone, one place for its tasks.** A task started in a worktree borrows its task
  directory from the main checkout by link (ADR-0029), so the main checkout's
  `.ai/workspace/tasks/` lists every task of the clone, and the queue file can live there too.
  The registry still needs to point at a clone's main checkout, not at any worktree. (An earlier
  draft of this spec said worktree tasks were invisible from the main checkout; that was wrong.)
- **The `state` file has no planning fields.** It holds `task_id`, `class`, `status`,
  `branch`, `gate*`, `autopilot*`, `pr_url`, dates. No priority, rank, board column,
  dependency or blocker. Those would be new keys in Core, and writes are last-write-wins
  without a lock (ADR-0008), so a field written by the UI can be lost by a concurrent
  `jig task set`.
- **Board state can already be derived.** `status` (new/active/ready/…), gate, autopilot
  state, `pr_url` and the housekeeping flags (`needs consolidation`, `wrong-base`, …) already
  carry most of what a board column would say. A stored board column may be redundant.
- **ADR-0002 and the audience.** Core is bash with git as the only mandatory dependency, aimed
  at people who may be non-developers on Windows (zero-config principle). Node.js + Vue is
  fine for a separate package, but "install Node, run a server, open a port" is the opposite
  of zero-config for that audience. The UI is optional, so ADR-0002 is not contradicted, but
  the audience question is open.
- **Specs, epics and idea-stage work are invisible in the concept.** Jig already tracks specs
  with phased roadmaps and epic branches (`jig spec list`); the concept shows tasks only. A
  planning tool that ignores the roadmap duplicates it by hand.
- **There is no machine-readable output.** `jig status` and `task` commands print text; the
  concept's "CLI adapter" needs either parsing text or a `--json` mode in Core.
- Weakest point: the UI depends on a Core contract that does not exist yet (planning fields,
  machine-readable read, cross-checkout enumeration). Writing priority and order from two
  writers (UI and agents) into a last-write-wins `state` file is the riskiest part.

## Scope and non-goals

- In scope: (to settle)
- Not doing (from the concept): remote/cloud access, agent management, desktop packaging,
  automatic next-task selection — all after the first version.

## Decisions

- Jig UI is a separate, optional package on top of Jig; Core works exactly as before without it
  (maintainer, 2026-10-14). Rejected: widening `jig status --html` (cannot be an interactive,
  multi-project board without a server) and delaying the UI decision until Core is ready.
- Everything the UI shows or changes lives in Jig, as new files or new fields in existing ones;
  the UI itself stores only the project registry and interface settings (maintainer,
  2026-10-14). The problems this raises (concurrent writers, tasks spread over worktrees, no
  machine-readable read) are solved in Core, not avoided. Rejected: a UI-side store of
  priority and order.
- Priority, order and dependencies live in one queue file per clone, not under git, in the main
  checkout beside `.ai/runtime/`; the only writer is a Jig command, atomic and checked against a
  revision the caller read (maintainer, 2026-10-14). Priority is 0–5, position is sparse
  (step 100), epics are a level of the same queue. Rejected: fields in each task's `state`
  (order scattered over worktrees, last-write-wins loses moves) and a queue file under git
  (a drag becomes a commit, PR conflicts). Prior art: research.md.
- Board columns are derived from Jig's own state and are never stored (maintainer, 2026-10-14).
  A drop on another column is therefore not a state change but a request: the card stays where
  Jig says it is, shows "requested", and moves only when Core's state changes. A request is sticky: it holds until honoured or cancelled
  by the person, whatever stage the task has reached by then — the agent finishes the step it is
  on, stops at the next boundary without starting another stage, sets the pause field
  (ADR-0012) and clears the request in the same Jig command. The request lives in the queue
  file (one writer), not in the task's `state` (last-write-wins would lose it). A request that
  stays unanswered is shown with its age and can be cancelled. Which drops are
  offered comes from the legal actions Core reports for that state. Rejected: a stored board
  column the agent has to keep in step.
- The repository is named `jig-ui` (maintainer, 2026-10-14).

## Open questions

- Queue file format, command names and the revision scheme — design, not yet specified.
- Who is the user: a developer with a terminal, or a non-developer on Windows?

## Assumptions left untested

- That a running autopilot or agent reads a pause request at its next stage boundary — to check
  against `task autopilot` and the pause field of ADR-0012 before the legal-actions item is designed.

- That a stored board column adds anything over the derived status — would be tested with
  one week of using the status page as a board.
- That a file watcher over many repositories and worktrees stays cheap enough in a single
  Node process — tested by a prototype.
