---
id: adr-0016-proposed-knowledge-is-a-lifecycle-state
type: adr
status: accepted
date: 2026-09-09
domains:
  - knowledge
  - context
paths:
  - scripts/lib/common.sh
  - scripts/lib/knowledge.sh
  - scripts/lib/context.sh
  - "skills/jig-map/**"
  - schemas/frontmatter.md
summary: Why a proposal is a status on the real document, and why resolution filters by an allowlist.
reviewed_at: 2026-09-09
---
# ADR-0016: Proposed knowledge is a lifecycle state, and resolution filters by an allowlist

## Context

`jig-map` inspects a codebase and proposes what its domains are. That is a judgement
about someone else's system, made quickly, and it will sometimes be wrong. It must not
become project knowledge merely by being written.

The obvious protection — write proposals to a draft tree in the task workspace and copy
the accepted ones across afterwards — costs two trees for one document, an apply step
that is a semantic Markdown merge scripts are forbidden to perform (ADR-0001), and the
drift between draft and real file that every such pair eventually develops.

The obvious alternative — write straight into `.ai/knowledge/` and review the diff — has
a narrower flaw that matters more: the documents resolve the moment they are written, so
any agent running `jig context` between the write and the review is handed unreviewed
inferences as project knowledge. The gate would be after the fact.

## Decision

**A proposal is a lifecycle state of the real document, not a copy of it elsewhere.**

`status: proposed` is valid for every document type. The document sits at its real path,
is created by `jig knowledge new`, is validated by `jig knowledge check`, and shows up as
an ordinary git diff — the review surface the project already has. What it cannot do is
resolve: `jig context` will not return it, the catalog will not list it, and a `requires`
naming it fails as unresolvable. `jig knowledge accept <id>` promotes it to `active`
(`accepted` for an ADR) once a human has agreed. `--all` shows it, which is how it is
reviewed.

**Resolution filters by an allowlist.** Only `active` and `accepted` resolve. This is the
half of the decision that makes the other half true, and it was a behaviour change: the
resolver previously skipped a *denylist* of `superseded | deprecated | rejected`,
duplicated in two functions, so a value it had not heard of — `proposed`, or a typo, or
whatever lifecycle value is added next — resolved exactly as if it were active. The
guarantee "a proposed document cannot reach an agent" is not something a denylist can
provide. One helper, `jig_knowledge_status_resolvable`, now answers the question for the
resolver, the catalog and the `requires` closure alike.

`jig knowledge stale` already used an allowlist. The two halves of the codebase disagreed
about how to ask the same question, and the safe form was already the one in use.

## Alternatives

- **A `knowledge-draft/` tree in the task workspace** (the original design of this
  feature). Rejected: two trees, a forbidden merge step, and drift.
- **Write directly as `active`, gate on the diff.** Rejected: the gate lands after the
  documents are already resolvable.
- **A separate `proposed: true` field beside `status`.** Rejected: two fields encoding one
  lifecycle, and every consumer would have to check both — the same reasoning that kept
  pause a field and status a status in ADR-0012, applied in the opposite direction
  because here it genuinely *is* one lifecycle.
- **Add `proposed` to the two existing denylists.** Rejected as a fix that leaves the
  underlying hazard: the next value added would repeat the bug, in two places.
- **A branch per proposal.** Rejected: it moves the review out of the project's own
  history and needs a merge for the accepted subset, which is more ceremony than a status
  field for the same result.

## Consequences

- An unknown or missing `status` no longer resolves. That is deliberate and is the
  behaviour change worth knowing about: a document whose frontmatter is broken now
  disappears from context rather than resolving as if healthy — and `knowledge check`
  fails it loudly, which is where that should be noticed.
- `jig knowledge accept` refuses anything that is not `proposed`, so it cannot be used to
  revive a superseded document.
- Knowledge can now be written speculatively without cost to anyone else, which is what
  makes `jig-map` runnable on an unfamiliar codebase at all.
- A proposed document left unaccepted is noise the next map has to argue with; `jig-map`
  is instructed to delete what the human rejected.
