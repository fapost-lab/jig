---
id: adr-20260918-component-boundaries-are-conventions
type: adr
status: accepted
date: 2026-09-18
domains:
  - knowledge
paths:
  - skills/jig-task/references/component-boundaries.md
summary: Why a component boundary's MAY / MUST NOT is a convention on its interface and implementations, and why there is no contract type.
---
# What a component boundary allows is a convention on its interface and implementations, not a new knowledge type

## Context

An interface shows the shape of a boundary between components; it does not show what an
implementation may do through it. `NodeHandler` implementations may read `flow.*` and return
effects, and must not persist the session or commit a transaction: the engine owns both. An
agent asked for a new handler cannot read that from the code, and writes the `save()` that
works. A reviewer who does not know the rule passes it.

A specification (`contract-knowledge`, removed unstarted on 2026-09-18, history in git
`df7cd62`) proposed a seventh knowledge type, `contract`, aimed at public APIs, with `paths`
claiming the interface's surface only. Two facts sank it: `jig context` never looks at a
document's type, so a type buys a label for skills and nothing in resolution; and a document
reached through the interface file alone never reaches the agent writing an implementation in
another file — the party the rules bind.

## Decision

- A boundary's MAY / MUST / MUST NOT are written as a `convention` whose `paths` name the
  interface **and** its implementations, so `jig context` brings it to whoever writes one.
  Only what the code cannot say; no signatures.
- A new or changed boundary is a human's decision on every route: its lines are approved at the
  gate in `design.md` (T3, T4) or confirmed from `plan.md` before implementing (T2 — a changed
  interface is a T2 signal); consolidation moves only approved lines into the convention. `jig-map` proposes boundaries found in code with
  each line as a question for the human.
- In `jig-review` a MUST NOT in a resolved boundary document is a rule: breaking it is a
  blocking finding. `jig-architecture-review` checks Boundaries against these documents too.
- A domain made of one boundary may keep it in its `rule` document (Jig's profiles, in
  `domains/verify/RULES.md`). Dependency direction between layers stays in `ARCHITECTURE.md`.
- The guidance lives in one reference, `skills/jig-task/references/component-boundaries.md`,
  linked from the skills that use it.

## Alternatives

- **A `contract` type** — nothing in resolution uses a type; a seventh type every knowledge
  skill must route to and every user must tell apart, before anyone has written one such
  document. Revisit if boundary conventions become many and get lost among style conventions.
- **Paths on the interface only** — the implementer, whom MUST NOT binds, never sees it; a
  refactor-free staleness signal is not worth that.
- **`ARCHITECTURE.md`** (the former route for "a boundary") — loads for every task, so each
  boundary's rules reach agents that never touch it.
- **A domain `rule` for every boundary** — one slot per domain (ADR-0019) and domain-wide
  loading; fine when the domain is the boundary, not otherwise.

## Consequences

- A new implementation makes its boundary document stale; consolidation rereads the rules and
  stamps it, as for any convention with broad paths.
- The guidance is untested in an installed project: whether such documents get written and
  whether review cites them decides whether a type is ever needed.
