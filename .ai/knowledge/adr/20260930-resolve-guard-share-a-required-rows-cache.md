---
id: adr-20260930-resolve-guard-share-a-required-rows-cache
type: adr
status: accepted
date: 2026-09-30
domains:
  - context
paths:
  - scripts/lib/context.sh
summary: resolve, guard and pending cache the required-document set in the task workspace, fingerprinted by selectors and knowledge content, so a route's repeated calls with the same question don't recompute it.
reviewed_at: 2026-09-30
---
# `resolve`, `guard` and `pending` share one required-rows cache per task

## Context

`jig context resolve`, `jig context guard` and `jig context pending` are three separate
processes, and every one of them calls `_ctx_required_rows` from scratch: walk every
knowledge document, evaluate its `load` policy and selectors, close the `requires` graph.
A T2+ route calls one of these at nearly every stage with the *same* selectors — the task,
its stage, its touched files — because nothing about the question changed between stages,
only the answer's cost was paid again each time. Measured on this project's own knowledge
base (89 documents): a cold `resolve` costs ~8s; an immediately following `guard` with
identical selectors, recomputing the same thing from nothing, cost the same again.

## Decision

`_ctx_required_rows` (scripts/lib/context.sh) writes its result to
`<task workspace>/context-cache`, prefixed with a fingerprint: the selectors it resolved
against (`stage`, `files`, `domains`, `topics`, `ids`, `all`) plus one line per knowledge
document's git blob hash (`jig_hash_list`, one process for all of them). The next call —
`resolve`, `guard` or `pending`, in either order — recomputes the same fingerprint first;
if it matches the cached one, the cached rows are used and the whole document walk is
skipped. Any mismatch (different selectors, a document's content changed, one added or
removed) recomputes from scratch and overwrites the cache.

A cache hit still runs `_ctx_check_selected_sources` fresh: a stub's linked file can
disappear without touching the stub's own frontmatter, so "the knowledge documents are
unchanged" does not imply "every stub still resolves."

The cache lives in the task's own workspace directory (ADR-0008: workspace per checkout),
next to the acknowledgement ledger it does not otherwise interact with. Two checkouts
working two different tasks never share or race over it.

A cache-write failure (the workspace purged mid-run, a full disk) never fails the command
that just computed the correct rows — it is a saved recomputation, never a requirement to
have one.

## Alternatives

- **No cache; accept the repeated cost.** Rejected: this is exactly the cost the task
  `knowledge-costs-one-walk` was filed to remove, and it multiplies with every stage of a
  route that calls `resolve`/`guard`/`pending` more than once.
- **Cache keyed by mtimes instead of content hashes.** Rejected: a fresh `git checkout` or
  a no-op rewrite changes mtimes without changing content, which would invalidate the
  cache for no reason; content hashing (already used elsewhere via `jig_hash_list`) answers
  "did anything that matters change" directly.
- **A single shared cache across tasks, keyed by selectors alone.** Rejected: two tasks in
  two worktrees can have different base branches, different touched files and different
  knowledge trees (ADR-0008); a cache keyed only by selectors, without the task's own
  workspace as its boundary, would answer one task's question with another's cache.

## Consequences

`resolve`, `guard` and `pending` must keep agreeing on what `_ctx_required_rows` returns —
they already had to, and the cache does not change that contract, only how often the work
behind it is repeated. A future selector added to context resolution must be folded into
the fingerprint (`_ctx_cache_fingerprint`) or it silently serves a stale answer for that
selector while correctly invalidating on every other one.
