---
id: adr-0018-a-proposal-ends-in-a-recorded-decision
type: adr
status: accepted
date: 2026-09-09
domains:
  - knowledge
paths:
  - scripts/lib/knowledge.sh
  - schemas/frontmatter.md
  - "skills/jig-accept/**"
  - "skills/jig-map/**"
summary: Why proposals must be enumerable, why rejecting records rather than deletes, and why the review loop lives in a skill.
reviewed_at: 2026-09-09
---
# ADR-0018: A proposal ends in a recorded decision, and rejection is not deletion

## Context

ADR-0016 made `proposed` a lifecycle state and gave it one exit: `jig knowledge accept`.
It gave it no way to be found and no way to be declined.

Finding it: `jig context` refuses to resolve a proposed document, which is the whole point,
and `--all` does not surface it either. No `jig knowledge` subcommand listed proposals. The
only way to see what was waiting was `grep -r "status: proposed" .ai/knowledge/`. In
practice a `jig-map` run ended with eight proposed documents and a human who could only act
on them by copying ids out of a chat message — and only for as long as that message was in
front of them. The state was designed to outlive the session that wrote it; the interface
to it was not.

Declining it: there was no command. `jig-map` instructed the agent to delete what the human
turned down, and ADR-0016 recorded that as a consequence. So the tool supported agreement
and left disagreement to `rm`. `rejected` existed in the schema, but only for ADRs.

## Decision

**A proposal has two exits, both recorded.** `jig knowledge reject <id>...` sets
`status: rejected` and leaves the document at its path. Nothing in the review loop deletes
a file. `rejected` becomes valid for every document type, not only ADRs; the resolver's
allowlist of `active` and `accepted` (ADR-0016) already excludes it without change.

**`jig knowledge proposed` enumerates what is waiting** — id, type, path and summary, one
line each. An empty result is a normal answer, not an error.

**`accept` and `reject` take several ids and are all-or-nothing.** A batch containing one
bad id changes nothing: a half-applied review is worse than a refused one, because the
human has no way to tell which half landed.

**The conversation is the interface, and the human never types an id.** `jig-accept` is a
skill: it enumerates, presents each proposal with its body and its evidence, asks, and
translates "the first two, not the third" into ids. The script enumerates and applies; the
prompting stays out of it (ADR-0001).

## Alternatives

- **Delete on reject** — `jig-map`'s original instruction and ADR-0016's closing
  consequence. Rejected: a deleted proposal leaves no trace that the question was ever
  asked, so the next map proposes the same domain and the human argues it from scratch.
  That repetition is paid every time; a rejected document costs one file the resolver
  already ignores. Rejected knowledge is still knowledge — "we considered a `task` domain
  and decided its ADRs already carry the vocabulary" is exactly what consolidation exists
  to keep.
- **Reject for ADRs, delete for everything else.** Rejected: two semantics behind one verb,
  and the types that most need the memory — a domain proposal an agent will otherwise
  re-derive — are the ones that would lose it.
- **An interactive `jig knowledge accept --interactive` prompting on a TTY.** Rejected: the
  reviewer is a human in a conversation with an agent, not at a terminal prompt. Putting
  the loop in the script would duplicate the interface that already exists and would put
  dialogue inside a program that is meant to be deterministic (ADR-0001).
- **Leave enumeration to `git status` and grep.** Rejected: it works only for someone who
  already knows what to look for, and only while the proposals are still uncommitted. The
  person deciding is often not the person who proposed.
- **Fold the review into `jig-map` step 5 and add no skill.** Rejected: acceptance is
  deliberately allowed to happen later and by someone else, which is what the durable
  `proposed` state buys. A stage that can only run inside the session that created the
  proposals throws that away.

## Consequences

- `.ai/knowledge/` accumulates rejected documents. That is the accepted cost. They
  validate, they never resolve, and `jig knowledge proposed` does not list them.
- ADR-0016's closing consequence — that `jig-map` deletes what the human rejected — no
  longer holds. `jig-map` now rejects, and its step 5 says so.
- `rejected` is a terminal state for every type. The allowlist introduced in ADR-0016
  absorbs the new value with no change to the resolver, which is the argument for an
  allowlist making its second payment.
- Nothing in the accept/reject path removes a file, so the review loop needs none of the
  path-validation ceremony ADR-0006 requires of destructive operations.
- A proposal left undecided stays proposed and stays invisible to agents. That remains a
  valid end state for a session; it is now a discoverable one.
