---
id: adr-0019-a-domain-pack-has-one-slot
type: adr
status: accepted
date: 2026-09-09
domains:
  - knowledge
paths:
  - scripts/lib/knowledge.sh
  - "skills/jig-accept/**"
summary: Why a domain pack cannot be rejected and replaced, and why a nearly-right draft is revised in place instead.
reviewed_at: 2026-09-09
---
# ADR-0019: A domain pack has one slot, so a draft is revised in place and rejection means "not this domain"

## Context

ADR-0018 decided that rejecting a proposal records it rather than deletes it, so the next
map can see that the argument was already had. That reasoning holds for documents whose
path carries a slug: an ADR gets the next number, a feature or convention gets a different
file name, and a better proposal can sit beside the rejected one.

A domain pack has no slug. `km_domain_file` derives the path from the type and the domain
alone: `domain` is `domains/<d>/OVERVIEW.md`, `glossary` is `GLOSSARY.md`, `rule` is
`RULES.md`, and there is exactly one of each per domain. A rejected pack therefore keeps
the only slot its domain has, and no better pack can be proposed for that domain
afterwards. "Reject it and propose a better one" — the move ADR-0018's consequences invite
— is not available here.

This surfaced the first time `jig-accept` ran on a real map: a human asked for one of eight
proposals to be rewritten and accepted, and the reject-then-replace path was closed.

## Decision

**Rejecting a pack means "not this domain", not "not this draft."** The two are different
decisions and only one of them is what `reject` records.

**A draft is revised in place while it is still proposed.** A proposal that is nearly right
is edited where it sits — it has not resolved for anyone, so nothing downstream can have
read the discarded version, and git holds it. The revised text is then accepted. No second
path, no second document, no slot consumed.

`km_reject` warns when a rejected document is a pack, at the moment the distinction
matters, rather than relying on the reviewer having read this ADR. It does not refuse:
rejecting a whole domain is a legitimate answer, and the slot staying occupied is then
exactly right.

## Alternatives

- **Refuse `reject` on a pack.** Rejected: it would block the legitimate case — deciding a
  domain should not exist — to prevent a mistake in another one.
- **Move a rejected pack aside**, to `domains/<d>/OVERVIEW.rejected.md` or similar.
  Rejected: it invents a second naming rule for one case, and `km_docs` would then have to
  decide whether the moved file is still a knowledge document. The value recovered is a
  draft that git already keeps.
- **Give packs a slug** so several can coexist per domain. Rejected: the fixed path is what
  makes `domains/<d>/` navigable and what `km_check_domain_placement` validates against.
  Trading that for the ability to keep rejected drafts is a bad exchange.
- **Say nothing and let each reviewer discover it.** Rejected: this one cost a live review
  its momentum within an hour of ADR-0018 being accepted.

## Consequences

- ADR-0018 stands; this narrows one of its consequences for one document family rather than
  reversing it.
- A rejected pack is a statement about a domain, and reading it that way is now load-bearing:
  a future map proposing that domain should treat it as an argument to answer, not as a
  draft that was merely worded badly.
- Revision-in-place means a proposal's history lives only in git, not in `.ai/knowledge/`.
  That is the same place every other superseded draft lives, and it is not visible to
  `jig knowledge proposed`.
- The `jig-accept` skill gains the distinction explicitly, because it is the skill holding
  the conversation where the question gets asked.
