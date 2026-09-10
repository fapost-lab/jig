---
id: glossary-knowledge
type: glossary
status: active
summary: "Terms specific to the document model: resolution, selector, requires closure, coverage, staleness, placement."
domains:
  - knowledge
topics: []
load: domain
paths:
  - scripts/lib/knowledge.sh
  - scripts/lib/context.sh
  - scripts/lib/frontmatter.sh
  - schemas/frontmatter.md
---
# Knowledge glossary

Terms specific to the document model. Project-wide terms — Durable Knowledge, Domain
Pack, Load Policy, Catalog, Context Ledger, Proposed Knowledge — are defined once in the
global `GLOSSARY.md` and are not repeated here.

## Resolution

Turning a task's selectors (paths, domains, ids) into the set of documents an agent must
read. Performed by `ctx_resolve`; produces required rows, global rows, catalog rows and
workspace rows. Informal synonyms: lookup, context loading.

## Selector

An input to resolution — a changed path, an entered domain, an explicit `--ids` request.
Selectors are what a task *has*; `load` is what a document *claims*. A document is
required when the two meet.

## Requires closure

The transitive expansion of a document's `requires` field: pulling in document A pulls in
everything A declares it cannot be understood without. Computed by `_ctx_close_requires`;
validated for cycles and dangling ids by `km_check_requires`.

## Coverage

The relation between knowledge and code, reported by `jig knowledge paths` in two
directions. **Uncovered**: tracked code that no document's `paths` glob claims.
**Unmatched**: a document's glob that matches nothing, meaning the code moved or was never
written. Both are reports, never automatic edits.

## Staleness

A document whose `reviewed_at` predates the last change to the code its `paths` match.
Measured by `jig knowledge stale`; cleared by `jig knowledge reviewed`, which is a claim
that a human or agent reconciled the document with the code — not a timestamp refresh.

## Placement

The rule that a Domain Pack file must claim the domain of the directory it sits in
(`km_check_domain_placement`). A pack file at `domains/x/RULES.md` whose `domains:` does
not contain `x` is a validation failure, not a warning.
