---
id: adr-0009-routing-rubric-and-explicit-gates
type: adr
status: accepted
date: 2026-09-08
domains: [skills, sdlc]
paths:
  - "skills/**"
summary: Why a written rubric picks the task class and human gates are full stops.
---
# ADR-0009: One entry skill routes by a fixed rubric; gates are explicit stops

## Context

Adaptive SDLC (SPEC §17) needs someone to decide how much process a task gets. Scripts
cannot: the decision is a judgement about risk and blast radius (ADR-0001). Left to the
agent without structure, the choice is inconsistent between sessions, and the framework
loses the property that makes it worth having.

The reference project ai-factory lets the human pick the process mode (`fast`, `full`,
`ultra`) per task, which moves the burden back onto the person the framework is meant to
help, and picks by effort rather than by risk.

## Decision

- **One entry skill.** `jig-task` classifies, creates the workspace and names the route.
  The stage skills (`jig-analyze`, `jig-implement`, `jig-review`, `jig-verify`,
  `jig-consolidate`, `jig-architecture-review`) do one stage each and can also be invoked
  directly when the user knows what they want.
- **A written rubric decides the class**, not the agent's mood:
  `skills/jig-task/references/classification.md` lists the signals for T0–T4 and two
  tie-break rules — uncertainty about scope routes down, uncertainty about risk routes up.
- **Risk sets the floor.** A one-line change to authentication is not T0.
- **Re-classification is normal.** When a task grows, `jig task set <id> class Tn` and the
  stages the new class requires are run; the route is never silently kept.
- **A stage whose output already exists is not re-run.** A task handed over as a written
  document has usually been through discovery and design; the agent splits it into
  `task.md` and `design.md`, argues with the design, verifies the premises it rests on,
  and takes it to the gate. Re-deriving what the author already wrote is ceremony, and
  accepting it unchallenged is not review.
- **Human gates are full stops.** For T3 and T4 the agent presents the design and waits.
  Approval must be given for this design, in this conversation; earlier general assent
  does not count.

## Alternatives

- **Human picks the process** (ai-factory) — rejected: puts the estimation burden on the
  user and keys process to effort rather than to risk.
- **A script classifies from diff size or file count** — rejected: size is a poor proxy
  for risk, and it would put an LLM-shaped judgement into a deterministic script.
- **One monolithic workflow skill** — rejected: a single skill covering every stage grows
  past a thousand lines and is loaded in full for a typo fix, which is exactly the context
  cost SPEC §3.4 forbids.

## Consequences

- Classification is auditable: the class is in the task state, the reason is stated once.
- Stage skills stay short because the router owns the sequencing.
- A wrong class is cheap to correct and expected to happen.
