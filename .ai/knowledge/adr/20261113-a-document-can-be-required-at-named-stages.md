---
id: adr-20261113-a-document-can-be-required-at-named-stages
type: adr
status: accepted
date: 2026-11-13
domains: []
paths:
  - schemas/frontmatter.md
  - scripts/lib/context.sh
  - scripts/lib/knowledge.sh
summary: "Why load: stage requires a document at its named stages only, with no domain, and keeps it out of the catalog elsewhere."
---
# A document can be required at named stages of every task

## Context

A project rule often belongs to one stage of the route: "a change to the public API updates the
published docs" belongs to consolidation. Before this decision such a rule had two homes, both
wrong. `load: always` required it at every stage of every task, paying its context cost where it
is useless. `stages` (ADR-0021) promotes a `load: matched` document only inside an entered domain,
so the rule needed a domain it had no natural claim to. The case that started the
`project-hooks` specification was the first kind: a convention with `domains: []`, `paths: []`
and `load: always`.

Binding a document to a stage from `.ai/config.yaml` was proposed and rejected (below): metadata
stays the only authority on applicability (ADR-0004, ADR-0014).

## Decision

`load` gains a fourth value, `stage`. A document with `load: stage` declares the stages it is
required at in `stages`, and nothing else selects it:

- `jig context resolve|pending|guard` require it exactly when `--stage` is given and named in its
  `stages`, whether or not a task is named and whatever domains are entered. The reason printed is
  `load: stage; stage: <stage>`. Its `paths`, `domains` and `topics` never select it — they may
  still serve `jig knowledge paths` and `jig knowledge stale`.
- At any other stage, and with no `--stage`, it is neither required nor listed in the catalog,
  including the catalog of project-wide documents (ADR-0014, amendment of 2026-09-18).
- The stateless `jig context` form has no stage, so it never lists a `load: stage` document.
- Explicit selection still works: `--ids <id>` requires it at any stage, and the `requires`
  closure adds it wherever a selected document requires it. A `matched` document that requires a
  stage-only one therefore carries it wherever it is selected itself; that is the author's
  explicit choice, and nothing prevents it.
- `jig knowledge check` fails `load: stage` with no `stages` or with `stages: []` — such a
  document is required nowhere — and does not warn that it has neither `domains` nor `paths`,
  which is the expected shape of a stage-only rule.
- The resolver cache's fingerprint names the new selection rule, so a cache written before it is
  never served.
- `jig-consolidate` runs `jig context resolve --task <id> --stage consolidate --catalog` as a
  command, not only as prose, since consolidation is the stage the motivating rule belongs to.

This does not contradict ADR-0021's "stage relevance is additive, never an intersecting filter".
That rule protects documents from being hidden by a stage filter they did not ask for. Here the
author opts their own document into stage-only loading; no other document's selection changes,
and every existing value of `load` behaves as before.

## Alternatives

- **`stages.<stage>.require: [<id>]` in `.ai/config.yaml`.** Rejected: it gives applicability a
  second source against ADR-0004/0014, and the argument for it — "the project declares its own
  rules" — holds equally for `.ai/knowledge/`, which is the project's and which `jig upgrade`
  never touches. Its one advantage, every binding in one place, is a listing a command can print.
- **Let `stages` promote a `matched` document without a domain.** Rejected: it would silently
  change what existing documents with `stages` and a domain mean, turning domain-scoped stage
  guidance into project-wide guidance.
- **Keep `load: always`.** Rejected: it is the cost this decision exists to remove.

## Consequences

- No migration: no existing document uses `load: stage`, and the other three values are unchanged.
- A project that writes `load: stage` needs this version of Jig: an older `jig knowledge check`
  fails the value as invalid, so the mismatch shows at once rather than as a silently missed rule.
- A stage-only rule reaches an agent only when the stage resolves its context with `--stage`.
  Stage skills that resolve context must keep doing so through the command.
- Extends ADR-0014 (a fourth `load` value, and an exception to the project-wide catalog) and
  ADR-0021 (stage relevance an author opts into), each amended to point here.
