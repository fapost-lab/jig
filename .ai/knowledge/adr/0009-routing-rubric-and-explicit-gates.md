---
id: adr-0009-routing-rubric-and-explicit-gates
type: adr
status: accepted
date: 2026-09-08
domains: [skills, sdlc]
paths:
  - "skills/**"
summary: Why a written rubric picks the task class and human gates are full stops.
reviewed_at: 2026-09-24
---
# ADR-0009: One entry skill routes by a fixed rubric; gates are explicit stops

## Context

Adaptive SDLC (`jig-task/references/classification.md`) needs someone to decide how much process a task gets. Scripts
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
  cost ADR-0001 forbids.

## Consequences

- Classification is auditable: the class is in the task state, the reason is stated once.
- Stage skills stay short because the router owns the sequencing.
- A wrong class is cheap to correct and expected to happen.

> **Amendment (2026-09-13).** Every class's route, T0–T2 included, now ends with
> `consolidate`; a task stopped at `ready` was never closed and never cleaned up. See
> ADR-0030.

> **Amendment (2026-09-13).** "The agent presents the design" said nothing about how the
> design reaches the human, and the skills filled the gap with "in a few lines". ADR-0031
> makes it concrete: the document is shown verbatim, the agent's commentary follows it, and
> an approval covers the document as it was shown. The gate itself is unchanged.

> **Amendment (2026-09-14).** `jig-idea` sits before the entry skill, not beside it: it tests
> an idea and keeps a specification with a roadmap, but starts no task. Work on a roadmap item
> still enters through `jig-task`. See ADR-0035.

> **Amendment (2026-09-22).** In an unattended autopilot run (`autopilot.unattended: true`, a
> local-only key) the gate is not a stop: the agent approves its own design with
> `jig task gate <id> approved --by agent`, recorded as `gate_by: agent`, journaled, noted in `task.md`,
> and the design goes verbatim into the pull request as approved by the agent, not a human. Everywhere
> else the gate is still a full stop. See adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci.

> **Amendment (2026-09-24).** "Lists the signals for T0–T4" described a rubric that lost to
> its own illustration. Under each class's abstract heading stood a concrete list, so the
> agent matched the list — cheaper than reasoning about the heading — and work no list named
> fell to a lower class. The rubric now leads with a risk test (reversibility, radius,
> detectability) and the lists follow it as open examples, labelled `Looks like:` and stated
> not to be a checklist. The class is the **highest** one whose test is answered yes, not the
> first whose examples match; the file previously said the opposite, which contradicted "risk
> sets the floor" in the same document. The decision here is unchanged — a written rubric
> decides the class, and both tie-breaks stand. What is new is a constraint on editing it: an
> example list under a class is an illustration, and turning it back into something an agent
> can match against re-breaks the rubric. The same test has a human-facing half in
> `docs/concepts.mdx`, shorter and without the reference's example lists; the two move
> together, because a rubric edit that leaves the site describing the old rule gives the
> person at the gate and the agent different meanings for the same class
> (convention-documentation).

> **Amendment (2026-09-24, after the rubric rewrite above).** `a version bump` stood in T0's
> examples and survived that rewrite, which changed the headings and missed the item under them.
> It is removed: ADR-0034 calls the merge that raises the version "the irreversible moment", and
> across 73 merged tasks it is the single most frequent real irreversibility, larger than every
> other cause combined (convention-required-records). It was deliberately **not** moved into T4's
> examples. The class is the highest whose test is answered yes, and the version is raised in the
> pull request that becomes the release (ADR-0034), so naming it there would route every release
> through specify, alternatives and a human gate — a change to lifecycle semantics, which needs its
> own decision rather than an edit to an illustration. It is named once in the tie-break instead,
> beside "trivial to write but hard to undo is not T0": that is a rule the agent reasons from, not
> a list it matches, and it fixes no class.
