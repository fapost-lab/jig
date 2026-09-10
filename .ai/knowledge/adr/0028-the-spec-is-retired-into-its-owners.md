---
id: adr-0028-the-spec-is-retired-into-its-owners
type: adr
status: accepted
date: 2026-09-11
domains:
  - knowledge
  - install
paths:
  - .ai/knowledge/RULES.md
  - README.md
summary: Why the 840-line product specification was dissolved into the schemas, domains and ADRs that already owned its content.
---
# ADR-0028: The product specification is retired into the documents that own its content

## Context

`docs/SPEC.md` was 840 lines across 37 sections, and it did two jobs at once. It was the
**plan** — §36 listed six development phases — and it was a **reference** describing the
lifecycle, the command surface, the frontmatter, the cleanup policy and the init/upgrade
decision table.

The plan finished on 2026-09-11 when Phase 6 landed. The reference half had already
become a third copy: `schemas/` owns the file formats, `.ai/knowledge/domains/` owns
orientation per domain, the ADRs own the decisions, and the code owns behaviour. The
project's own rule — code explains what, knowledge explains why — leaves nothing in the
middle.

Being a third copy has a measurable cost, paid on 2026-09-10 alone:

- §31 said the adapter *installs* the session hook. It offers it (ADR-0024).
- §15 said `branch` is the *current* branch. It is the branch `task new` created (ADR-0026).
- §32 step 8 said `init` offers to configure scheduling. It prints an advisory line.

Three sections repaired in one day, each because reality moved and the spec did not.
Meanwhile no agent ever read it: `jig context` resolves only `.ai/knowledge/`, so the
specification never reached a working session. It was maintained for a reader that did not
exist.

There is a second, sharper reason. `.ai/knowledge/` is the framework's designated home for
durable knowledge, and the `knowledge-adoption` work exists precisely to reconcile
documentation that lives outside it. Keeping such a document in Jig's own repository is
the contradiction that work is meant to remove.

## Decision

**`docs/` is deleted. Every claim it held moves to the document that already owns the
subject, and every citation is rewritten to point there.**

- Content with an existing owner — frontmatter, task state, classification, the cleanup
  policy, context resolution, scripts layout, the adapter contract, profiles, init and
  upgrade — keeps that owner. The citation moves; the content does not.
- Content with **no** owner moves to `RULES.md`, which gains a `Scope invariants` section:
  the non-goals list (§34) and "routine maintenance never depends on a developer
  remembering to run it" (§3.8). Both are constraints an agent must not violate, which is
  what `RULES.md` is for and why it is always in context.
- The delivered plan (§36) and the closed open questions (§33) are deleted outright, not
  rehomed. A finished roadmap is history, not knowledge.
- A citation is **never** repointed at `README.md`. The README describes the product to a
  human; it does not hold contracts an agent is bound by.
- Historical references to earlier spec versions inside an ADR's Context — "Spec §31
  (v0.3) required…" — are left as written. They describe what was true when the decision
  was taken, which is the job of that section.

## Alternatives

- **Keep the spec as a maintained product reference.** Rejected: that is the state it was
  already in, and it produced three false sections in a single day. A document nobody
  consults but everybody must update is a tax with no payer.
- **Freeze it as a historical artifact.** Rejected as the worst option: 94 live citations
  pointed at it, and a frozen-but-cited document is one readers still trust.
- **Move the whole thing into `.ai/knowledge/` unchanged.** Rejected: the duplication is
  the defect, not the location. Importing 37 sections that restate `schemas/`, `domains/`
  and the ADRs would move the drift rather than end it.
- **Delete it and let the citations dangle.** Rejected: the 94 citations were the map of
  what the spec actually still owned. Following each one is what turned a deletion into an
  inventory.

## Consequences

- Finding out where a claim lives now requires naming its owner, and that is the point.
  Rewriting the citations surfaced a wrong one: `measure.sh` cited "SPEC §21" for "no
  telemetry", but §21 is "Changes After Consolidation" — the author meant *line* 21. It
  now cites ADR-0027, which actually holds that decision.
- Four citations pointed a document at itself (`schemas/state.md` citing the spec section
  that described `schemas/state.md`). Those were dropped rather than redirected.
- The framework has one knowledge location again, which is what it asks of the projects
  that use it.
- `README.md` becomes the only human-facing entry point. Nothing enforces that it stays
  accurate; that is the same exposure the spec had, now with one document instead of two.
- Anyone looking for the shape of the whole system reads `ARCHITECTURE.md` plus the domain
  overviews. No single document describes it end to end any more. That is a real loss, and
  it is accepted: the end-to-end description was the part that kept going stale.
