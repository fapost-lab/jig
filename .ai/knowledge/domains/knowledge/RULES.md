---
id: rule-knowledge
type: rule
status: active
summary: "Constraints on the document model: no cross-sourcing between knowledge and context, proposed is not resolvable, globs are never hand-edited."
domains:
  - knowledge
topics: []
load: domain
requires: []
paths:
  - scripts/lib/knowledge.sh
  - scripts/lib/context.sh
  - scripts/lib/frontmatter.sh
reviewed_at: 2026-09-09
---
# Knowledge rules

## Invariants

- `knowledge.sh` and `context.sh` never source each other. Anything both must agree on
  lives in `common.sh`. A command that reaches into the other's helpers makes the two
  able to drift on what a document *is*, which is the one thing they may not disagree
  about.
- A document is resolvable only if its status says so
  (`jig_knowledge_status_resolvable`). `proposed` is deliberately excluded: an inference
  must not reach another agent before a human accepted it (ADR-0016).
- `frontmatter.sh` stays semantics-free. It parses and writes fields; it never decides
  what a field means, so that the schema can change without touching the parser.
- Validation reports every failure it found, then exits non-zero once. `km_check` must
  not stop at the first bad document — an agent fixing knowledge needs the whole list.

## Rules

- `paths` globs are written by `jig knowledge paths add|remove`, never by hand
  (ADR-0001). Hand-edited globs are how coverage rots silently.
- **Frontmatter must parse as real YAML, not merely as jig's subset of it.** A scalar
  containing `: ` is double-quoted; `#` and `"` are refused outright. The reader here is
  forgiving — `fm_get` takes everything after the first `key: ` — so a document jig reads
  perfectly can be rejected outright by an editor, a linter or anything else that uses a
  YAML library. Write summaries with `jig knowledge summary`, which quotes correctly;
  `knowledge check` fails what another tool wrote wrong.
- Every document gets a `summary`. It is the only thing an agent sees in the catalog when
  deciding whether to open the document; without it the catalog entry is noise.
  Today fifteen of sixteen ADRs have none.
- A term that means the same thing project-wide belongs in the global `GLOSSARY.md`. This
  domain's glossary holds only what is specific to the document model.
- Uncovered and unmatched paths are reported, never repaired automatically. Deciding that
  a directory needs a document is a judgement; deleting a glob because it matches nothing
  destroys the evidence that code moved.
