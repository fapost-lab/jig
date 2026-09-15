---
id: adr-0035-specifications-live-outside-knowledge
type: adr
status: accepted
date: 2026-09-14
domains:
  - skills
  - knowledge
  - install
paths:
  - scripts/lib/spec.sh
  - "templates/spec/**"
  - "skills/jig-idea/**"
summary: Why plans for work larger than one task are committed under .ai/specs/, never resolved as knowledge, and carry no status.
reviewed_at: 2026-09-15
---
# ADR-0035: Specifications are committed plans under `.ai/specs/`, outside knowledge, with no status

## Context

Work larger than one task had nowhere to keep its plan. A task's `task.md` belongs to that
task and is never committed; `.ai/knowledge/` describes the system as it is. Tasks that
belonged together described each other in their own `task.md` files, and an idea for a
project that did not exist yet had no home at all. Nothing in the framework questioned an
idea before work began either: every question a skill asked clarified what had been said.

A first design — a skill that ends a conversation in a verdict and files a task — was
rejected by the maintainer on 2026-09-14: it adds nothing over discussing an idea and
saying "file a task", and it does not answer where the roadmap of a hundred-task idea lives.

Two existing homes were measured and ruled out. A `feature` document with `status:
proposed` never resolves (ADR-0016), so the plan would never reach the agents of the tasks
it was written for; accepted, it becomes `active` and resolves as a description of code
that does not exist yet — `paths`, `reviewed_at` and staleness (ADR-0010) all mean
"matches the code". ADR-0028 removed the last document that mixed a plan with a reference,
for the same reason.

## Decision

- **A specification lives in `.ai/specs/<spec-id>/` and is committed.** `spec.md` and
  `roadmap.md` are required; other files (`architecture.md`, `stack.md`, …) are added as
  needed. It travels with the repository and is reviewed like any file.
- **It is not knowledge.** `.ai/specs/` is outside `.ai/knowledge/`, so `jig context` never
  resolves it and `jig knowledge check` never reads it. An agent reads a spec because its
  work points at it, not because resolution handed it over.
- **It has no status.** Progress is derived from `roadmap.md`: checked items are done,
  unchecked items that open with a backticked task id and a dash are filed, `fog:` items are
  not yet understood. Statuses were declined by the maintainer on 2026-09-14.
- **`jig spec new <id>` creates it** from `templates/spec/`, installed as the framework-owned
  `.ai/templates/spec/` by `init` and `upgrade` the way ADR-0011 installs knowledge
  templates. The id follows the task id grammar, validated by the one helper both use
  (`jig_valid_id`). The skill does not write the files itself: an agent creating
  `.ai/specs/My idea/` would produce a spec every listing skips without a word.
- **`jig spec list` lists specs with their progress, and `jig status` counts them** on its
  `specs:` line — the only way a session learns a spec exists, since resolution never
  mentions one.
- **The `jig-idea` skill develops a spec**: it questions and stress-tests the idea, writes
  what was decided and shows it verbatim (ADR-0031), and builds the roadmap. It starts no
  task and changes no code; `jig-task` stays the one entry into routes (ADR-0009).

This is a second committed location under `.ai/` beside `.ai/knowledge/`, and a deliberate
departure from "one knowledge location" in ADR-0028: a plan does not describe the system,
so it cannot live where everything is read as describing it.

## Alternatives

- **A verdict with no storage.** Rejected: see Context.
- **`features/` with `status: proposed`, accepted when work starts.** Rejected: proposed never
  reaches task agents, and active is read as present behaviour.
- **The spec inside a task workspace.** Rejected: local, uncommitted, removed when the task is
  purged, and owned by one task where a spec spans many.
- **A root-level `specs/` or `docs/`.** Rejected: it mixes the framework's process with the
  product's own documentation.
- **A status field (`draft`, `active`, `done`).** Declined for now: nothing consumes it that
  the roadmap cannot answer, and a stored status drifts from the checkboxes it summarises.
- **Finding specs with `ls .ai/specs`.** Rejected: no titles, no progress, and nothing at
  session start.
- **Templates in the skill's `references/`, instantiated by the agent.** The approved first
  cut; reversed by architecture review against RULES.md ("skills reference `jig <command>`
  for mechanics") — the name was never validated.
- **Adopting an external spec-driven plugin's skills as they are.** Rejected: they write to
  `docs/`, live outside the framework and file no Jig tasks. Their techniques — three
  conversation phases, pressure lenses, an independent failure hunt in a clean context,
  destination, fog and waves — are restated in `jig-idea`.

## Consequences

- A spec can go stale the way `docs/SPEC.md` did. The exposure is smaller — a spec is a plan,
  read before work, and a finished roadmap is history — but nothing checks it.
- Filed tasks and roadmap checkboxes can drift apart: task workspaces are local, the roadmap
  is shared. Linking tasks to their spec and checking items at consolidation are the next
  phase of this work (`.ai/specs/idea-workflow/roadmap.md`), not part of this decision.
- `.ai/templates/spec/` is new framework-owned content: copy-mode projects see it as pending
  until `jig upgrade` (ADR-0017).
- `jig spec new` is a third deletion outside a workspace or trash entry, named in RULES.md:
  on a failed copy it removes only its own temporary files and `rmdir`s the directory it
  just created.

> **Amendment (2026-09-15).** The next phase landed, and two statements above changed with it.
> **A task links to its spec** with one line in its `task.md`, `Spec: .ai/specs/<id>/ — Phase <n>`,
> and the roadmap items it covers start with its id; no field was added to `state`. **Its items are
> checked when its knowledge decision is recorded**, before the commit, by `jig spec done <task-id>`
> called from `jig-consolidate` — not at the close: the close comes after the merge, and a
> checkmark written then would need a second commit and pull request per task. The checkmark is on
> the base branch exactly when the work is. **`jig spec remove <id>`** unlinks the spec's open tasks
> in this checkout, found through their own `Spec:` lines because the roadmap is shared and
> workspaces are local; abandons never-started ones only with `--abandon-unstarted`, through the
> dispatcher so that `jig task` stays the only writer of `state`; leaves started and closed tasks
> alone; and moves the directory to trash. **Carrying a spec into a new project is a plain copy of
> its directory**, decided by the maintainer: the new project's Jig tracks it from there, so no
> mechanism or pointer was built.
