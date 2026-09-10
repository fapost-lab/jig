---
id: adr-0004-knowledge-frontmatter-for-context-resolution
type: adr
status: accepted
date: 2026-09-08
domains: [knowledge, context]
paths:
  - "schemas/**"
  - "scripts/lib/context.sh"
  - "scripts/lib/frontmatter.sh"
  - "scripts/lib/knowledge.sh"
  - "templates/knowledge/**"
reviewed_at: 2026-09-09
summary: "Why knowledge carries frontmatter: it makes context resolution deterministic without an LLM."
---
# ADR-0004: Knowledge documents carry frontmatter so context resolution is deterministic

## Context

Spec §31 (v0.3) required that an agent receives only knowledge relevant to the task,
but did not say how relevance is determined without an LLM. Reading an index and
choosing costs inference on every task and is non-reproducible.

## Decision

Every document under `.ai/knowledge/features/`, `adr/`, `conventions/` starts with
frontmatter:

```yaml
---
id: feature-trigger-resolution
type: feature | adr | convention
status: active | deprecated | superseded   # adr: accepted | superseded | deprecated | rejected
domains: [flow, triggers]
paths: ["src/Flow/**", "app/Services/Trigger*"]
---
```

`GLOSSARY.md`, `ARCHITECTURE.md`, `RULES.md` are global and carry no frontmatter.

`jig context` matches changed/affected files against `paths` (and task tags against
`domains`) and prints the list of relevant documents. `jig knowledge check` validates
required fields, unique ids, and reports documents whose `paths` match nothing in the
repository (stale-knowledge signal). Frontmatter is limited to flat scalars and
one-level lists (see ADR-0002).

## Alternatives

- **Agent picks from `INDEX.md`** — rejected as the primary mechanism: costs inference
  each time and is unstable; remains the fallback when nothing matches.
- **Directory-per-domain layout instead of metadata** — rejected: a document often
  spans domains and paths.

## Consequences

- Consolidation must maintain `paths` when it edits a document. Delivered as
  `jig knowledge paths` (report and `add`/`remove`).
- Stale knowledge becomes detectable mechanically. `knowledge check`'s "glob matches
  nothing" warning is the structural half; drift between a document and the code it
  describes needed a freshness record and is settled by ADR-0010.
- Documents without frontmatter are reported by `knowledge check`, not silently ignored.
- Extended, not replaced, by ADR-0014: `load`, `topics`, `requires` and `summary` say
  *how* a document applies, and domain directories were added without giving directories
  any authority. The rejection of "directory-per-domain layout instead of metadata"
  above still stands and is what ADR-0014 enforces.
