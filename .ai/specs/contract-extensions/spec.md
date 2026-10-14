# Contract extensions — Jig that a program can read

Depth: normal — split from the `jig-ui` spec (PR #232) with its decisions already taken by the
maintainer; what is new here is only the boundary.

Origin: on 2026-10-14 the maintainer moved Jig UI and everything about it into its own project,
`fapost-lab/jig-ui`, where its spec now lives. What Jig itself must provide stays here, described
as extensions of Jig's contracts that are useful without any UI. The same day the planning half —
priority, order, dependencies and pause requests — moved to its own spec, `contract-queue`, so
that each half is released on its own (see Decisions).

## Idea

The maintainer's words, translated: Jig UI and all that is connected with it belong in a separate
project; Jig carries a link to Jig UI as an additional capability; the changes in Core that the UI
needs are shown as extensions of the contracts.

What the UI needs from Jig, in this spec: to read every task, spec and epic of a clone as data,
and to know what needs a person and what a person may do next. Keeping priority, order and
dependencies in Jig, and asking a running task to pause, are `contract-queue`'s.

## Goal and problem

- Who is worse off without this, and how: any program that wants Jig's state — Jig UI, CI, a bot,
  an agent choosing what to take next — has to parse text written for a person, and calls the
  forge itself to learn what a pull request is doing.
- What is true when the work is done: the commands that report state have a stable JSON form in
  one envelope, pinned by tests; reading it never touches the network; every read carries one
  revision of the clone that a consumer can compare and send back.

## Stress test

- **No machine-readable output exists.** Commands print text; only `gh` is called with `--json`.
- **Pull request and CI state is not kept.** Housekeeping lists pull requests (`gh pr list`) and
  uses the answer in memory; CI is asked per pull request when shipping. Nothing a reader could
  take offline exists yet.
- **One clone, one place.** A worktree borrows its task directory from the main checkout
  (ADR-0029), so the main checkout lists every task, and a per-clone file has one natural home.
- **The status page already computes "needs you"** (adr-20260922-the-status-page-stays-current-without-a-server);
  attention as data must reuse that logic, not make a second copy that drifts.
- **ADR-0002 holds:** JSON is written by shell, without `jq` or any new dependency.
- **The revision is only as good as its writers.** Every Jig write must raise it; one forgotten
  writer, and a consumer misses a change.

## Scope and non-goals

- In scope: JSON output in one envelope and stable failure codes; the per-clone revision; the
  pull request and CI cache; attention items and legal actions as data.
- Not doing: anything with a server, a port or a watcher — that is Jig UI's; the queue and pause
  requests — `contract-queue`.

## Decisions

- Jig UI is a separate, optional project; Jig carries only a mention of it and works exactly as
  before without it (maintainer, 2026-10-14). Its plans live in `fapost-lab/jig-ui`.
- Everything a UI shows or changes lives in Jig, as new files or new fields (maintainer,
  2026-10-14). Rejected: a UI-side store of priority and order.
- Which actions a person may take in a given state is reported by Jig; no consumer keeps its own
  copy of that table.
- Each half ships as its own release on its own epic (maintainer, 2026-10-14), because Jig UI
  waits only for the machine-readable half, not for the queue. An epic covers a whole spec
  (ADR-0040), so the queue and requests moved to `contract-queue`; this spec's epic is released
  `minor`. Rejected: one epic for both halves (the UI waits for all of it) and phases straight
  into `main` (half a contract on `main`, ADR-0040).
- One JSON envelope for every command (maintainer, 2026-10-14): `--json` prints
  `{"schema": 1, "revision": …, "generated_at": …, "data": …}` on success and the same with
  `"error": {"code": …, "message": …}` instead of `data` on a refusal. `schema` is raised only on an
  incompatible change; adding a field is compatible. A contract test pins each command's shape.
  Rejected: a shape and a version per command (every consumer learns each one).
- Reading JSON never touches the network (maintainer, 2026-10-14). Pull request and CI state come
  from a cache housekeeping writes when it already asks the forge, each with its `fetched_at`; a
  consumer that re-reads on every file change in several projects stays clear of `gh` rate
  limits. Rejected: a `--refresh` flag (a consumer would call it in a loop).
- One revision per clone (maintainer, 2026-10-14): a counter raised by every Jig write — task
  state, artifacts, specs, and the queue once it exists — and reported in every JSON read. A
  consumer carries it in its change signals and sends it back with every write; Jig refuses a
  write made against a stale one (writes arrive with `contract-queue`). Rejected: a revision for
  the queue and one per task (finer, but a consumer has to track many, and a task changed by an
  agent is still missed by the queue's one). Accepted risk: a file edited by hand, not through
  Jig, does not raise it.

## Open questions

- Whether `jig init` gets a hook that lets an installed UI register the project, without making
  the UI a dependency of Jig.
