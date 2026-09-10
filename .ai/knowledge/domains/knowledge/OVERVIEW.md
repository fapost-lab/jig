---
id: domain-knowledge
type: domain
status: active
summary: The document model that outlives tasks, and the boundary between writing knowledge and resolving it.
domains:
  - knowledge
topics: []
load: domain
paths:
  - scripts/lib/knowledge.sh
  - scripts/lib/context.sh
  - scripts/lib/frontmatter.sh
  - schemas/frontmatter.md
  - "templates/knowledge/**"
reviewed_at: 2026-09-11
---
# Knowledge

The document model that outlives tasks, and the two commands that must never disagree
about it: `jig knowledge` writes and validates documents, `jig context` decides which of
them an agent has to read.

## Responsibility

- The shape of a knowledge document: frontmatter fields, their allowed values, and the
  templates new documents start from (`schemas/frontmatter.md`, ADR-0004).
- The lifecycle of a document: `proposed` → `active` or `rejected`, and the deprecated and
  superseded ends (ADR-0016, ADR-0018). A proposal has two recorded exits and neither
  deletes a file; `jig knowledge proposed` enumerates what is waiting and `jig status`
  counts it, so a decision may be taken later and by someone else.
- Whether a document still describes the code: `paths` coverage and `reviewed_at`
  staleness (ADR-0010).
- Which documents a task must read, how much of each, and the record that it did:
  resolution by selectors, the catalog, and the context ledger (ADR-0014, ADR-0015).

## Boundaries

Outside: the *content* of any particular project's knowledge — this domain owns the
model, never the facts written in it. Also outside: task lifecycle (domain `task`), which
supplies the task id the ledger is keyed by but knows nothing about documents.

Dependencies point one way. `knowledge.sh` and `context.sh` never source each other; the
handful of definitions both must agree on live in `scripts/lib/common.sh`
(`jig_knowledge_docs`, `jig_knowledge_is_global`, `jig_knowledge_status_resolvable`). A
new shared notion goes there, not into one command with the other reaching across.

`frontmatter.sh` is a parser and writer with no knowledge semantics: it does not know
what a `load` value means. Keep it that way — semantics belong above it.

Stage relevance extends resolution additively: optional stages metadata promotes matched
catalog documents within entered domains, without hiding constraints (ADR-0021). Stage
and --no-task are invocation selectors, never lifecycle. The shared stage vocabulary is
in common.sh; metadata validation/writing stays in knowledge.sh, selection in context.sh.
Missing mandatory context fails, and no-task guard reports that no ledger exists.

## Entry points

- `scripts/lib/knowledge.sh` — `km_init` (the prologue every other entry point assumes:
  the frontmatter parser and `KM_DIR`), `km_check` (validation entry), `km_new`,
  `km_paths_report`, `km_stale`, and the review loop: `km_proposed`, `km_accept`,
  `km_reject`. A command outside this domain that consumes these reports — `jig measure`
  does — calls `km_init` rather than transcribing the setup, so a step added here reaches
  it too.
- `scripts/lib/status.sh` — `cmd_status`'s `proposals:` line, the count that makes an
  undecided proposal discoverable after the session that wrote it.
- `scripts/lib/context.sh` — `ctx_resolve` (what to read), `ctx_acknowledge` /
  `ctx_guard` (the ledger).
- `schemas/frontmatter.md` — the field reference both commands are checked against.
