---
id: adr-0014-progressive-context-loading
type: adr
status: accepted
date: 2026-09-09
domains:
  - knowledge
  - context
paths:
  - schemas/frontmatter.md
  - scripts/lib/context.sh
  - scripts/lib/knowledge.sh
  - "templates/knowledge/**"
  - docs/SPEC.md
reviewed_at: 2026-09-09
summary: Why knowledge declares how it should be loaded, and why directories never decide applicability.
---
# ADR-0014: Knowledge declares how it should be loaded, and directories never decide

## Context

ADR-0004 made context resolution deterministic: a document declares `paths` and
`domains`, and `jig context` matches them against the affected files and the task's
domains. That answers "does this document apply", but not three questions a working
agent keeps hitting.

A conceptual document owns no path. An ADR about idempotency applies to a task about
retries, and no glob will ever say so, so it is either loaded for everything or found by
accident.

Domain membership is too coarse to be a loading rule. Entering `payments` and loading
every document that mentions payments defeats the point of resolving context at all; not
loading them means the domain's own rules are missed.

And knowledge has dependencies. A rule that only makes sense on top of an ADR is
routinely selected without it, and nothing detects that the context is incomplete.

The pressure to answer these with directories is constant — put the payments knowledge
in a payments folder and load the folder. ADR-0004 already rejected that, because
documents cross domains, and the rejection has to survive the addition of the
directories themselves.

## Decision

Frontmatter gains four optional fields, and the type list gains three values.

- `load`: `always | domain | matched`, default `matched`. It is the document's own
  statement of how strongly it applies: always, on entering one of its domains, or only
  when a path or topic actually hits.
- `topics`: tags for conceptual applicability, so a document reaches a task that touches
  no file it claims.
- `requires`: ids that must be loaded whenever this document is. Transitive, acyclic,
  validated by `jig knowledge check`, and fatal during resolution when unresolvable.
- `summary`: one line, shown in the catalog.
- Types `domain`, `glossary` and `rule` — the three files of a domain pack.

A domain may keep a pack under `.ai/knowledge/domains/<domain>/` with `OVERVIEW.md`,
`GLOSSARY.md` and `RULES.md`. **The directory is navigation, never applicability.** A
document filed under `domains/<d>/` must declare `<d>` in its own `domains` or
`knowledge check` fails it, and a document filed anywhere else may belong to the domain
just as well. ADR-0004 stands unamended in substance: metadata remains the only
authority.

`jig context resolve` splits its answer in two. Required documents, whose body the agent
must read. And a catalog — id, path, summary — of the remaining active documents of the
entered domains. A `matched` document whose domain matches but whose paths and topics do
not is catalog, not required: domain membership is a discovery signal, not proof the body
is relevant. The agent pulls one in with `--ids` when it decides the entry matters.

Two consequences of this fall out of the code and are part of the decision:

Enumeration walks `.ai/knowledge/` recursively, once, in a helper shared by `context` and
`knowledge`. Two walks that disagreed about which files exist is how a domain document
would end up validated but never resolved.

The three global documents are recognised by repository-relative path, not by basename.
A pack file named `RULES.md` is an ordinary document; a basename test would have exempted
it from validation and hidden it from every consumer, silently.

## Alternatives

- **Load every document of an entered domain.** Rejected: it is the cost problem this
  feature exists to solve, and membership is not relevance.
- **Derive applicability from the directory.** Rejected again, for ADR-0004's reason:
  documents cross domains and components. Directories stay organisational.
- **Keep domain knowledge in nested `AGENTS.md` files.** Rejected: loading and precedence
  are runtime-specific, cross-domain knowledge has nowhere to live, and it duplicates the
  vendor-neutral store. Correctness must not depend on a runtime supporting nested
  instruction files.
- **An `INDEX.md` the agent reads and chooses from.** This is the catalog, minus the
  determinism: an index costs inference every task and drifts. The catalog is generated
  from the same frontmatter the resolver uses.
- **Require a code graph to find the file frontier.** Rejected as a dependency (ADR-0002).
  An agent may use one and pass the files it finds to the resolver.

## Consequences

- `jig knowledge check` gains a whole-graph pass: `requires` targets must exist, be
  active, and contain no cycle. No single document can check this.
- Three document types mean three templates, shipped framework-owned (ADR-0011). They
  live in `templates/knowledge/domain/` rather than as `glossary.md` beside the global
  `GLOSSARY.md`: on a case-insensitive filesystem those are one file, and writing one
  destroys the other.
- `jig knowledge new <domain|glossary|rule> <domain>` builds a path from a domain name,
  so the name is validated at the single function that builds it (`km_domain_dir`),
  like task ids, profile names and adapter names before it (ADR-0008).
- Existing documents need no migration: absent `load` means `matched`, which is what they
  already did.
- Extended by ADR-0016: `proposed` joins the status values, and resolution stopped
  filtering by a denylist of retired values — which is what makes "a document declares
  how it should be loaded" also mean "a document nobody has agreed to is not loaded".
- The stateless `jig context` form keeps promoting a domain match to `matched:`. The two
  forms differ on exactly that point, deliberately, and it is written down in
  `schemas/frontmatter.md` rather than left to be discovered.
