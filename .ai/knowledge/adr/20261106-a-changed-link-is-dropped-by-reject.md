---
id: adr-20261106-a-changed-link-is-dropped-by-reject
type: adr
status: accepted
date: 2026-11-06
domains:
  - knowledge
paths:
  - scripts/lib/knowledge.sh
  - skills/jig-accept/SKILL.md
  - schemas/json.md
summary: Why reject drops the link of an accepted stub whose source changed, why the stub becomes rejected, and why the knowledge reads and writes name what a decision cannot take yet (not-on-base, not-on-branch)
reviewed_at: 2026-11-06
---
# A changed link is dropped by `reject`, and a read says when a decision cannot be taken yet

## Context

Jig UI builds its knowledge decisions on `jig knowledge … --json` (fapost-lab/jig#392, after #364).
Two things it was told it could do, it could not.

- **Dropping a changed link.** ADR-0036 (amendment of 2026-09-16), `jig-accept` and the comment on
  `km_sources` all say that a linked source edited since it was approved is kept with `jig knowledge
  reviewed <id>` or dropped with `jig knowledge reject <id>`. `reject` has only ever taken proposals
  (ADR-0018), so it refused the accepted stub with `not-proposed`. Keep had a command; drop had none, in a
  session or from a page.
- **A proposal listed but not decidable.** A decision from outside a session is judged in Jig's own tree,
  on `knowledge/decisions` when that branch waits and on the base as `jig_base_ref` reads it otherwise
  (adr-20261104-a-write-goes-in-jigs-own-tree); `proposed --json` and `sources --json` read the checkout.
  A proposal committed only here, or that reached the base after the branch was cut, was listed and then
  refused `not-found`, "no document with id", which reads as a typo. The same held for a source edited
  only here: the read said `changed`, and in the tree there was nothing to drop.

Both are lifecycle semantics: which transitions a document may take, and what a page may offer.

## Decision

- **`reject` also takes an accepted stub whose source needs a decision**: a document with `source:`,
  `active` or `accepted`, whose source is `changed`, `unrecorded` or `missing` — the words
  `km_source_states` gives, asked for one document by `km_source_state`. It becomes `rejected`, at its
  path, with its `source_hash` as it was: it never resolves again, is not counted under `sources changed:`,
  and `knowledge changed` no longer reports its source. The check is `km_require_rejectable`, shared by the
  text form and the write in the tree, so both refuse the same things. Everything else stays
  `not-proposed`: a stub whose source is `ok`, any active document that links nothing, anything retired.
  A batch stays all-or-nothing, and a proposal and a changed link may share one.
- **`rejected`, not `deprecated` or a status of its own.** ADR-0018 already makes `rejected` the recorded
  "asked, and the answer was no", and the reads' `waiting` then says `"decision":"rejected"` without
  another rule.
- **A retired stub's source is not followed by `knowledge check`.** A stub that is neither proposed nor
  resolvable hands nobody its source, which may have gone — the case of a `missing` link dropped, and of a
  proposal rejected before its file was deleted. Its path is still checked for shape, and two stubs still
  may not link one file.
- **The reads say whether a decision sent now would be taken.** Every entry of `proposed --json` and
  `sources --json` carries `decidable` and `reason`, after the `offered` and `reason` of a task's actions
  (adr-20261015-one-table-of-what-a-person-may-do). The document is looked for where the write judges, as
  of the last fetch and with no network: the tip of the decisions waiting when one waits (`ot_waiting`),
  the base otherwise. For a `changed` or `missing` source the change is looked for too: the source there
  must not be the approved text. One `git ls-tree` per ref answers every document (`_km_ref_holds`).
- **The write refuses what is only here with a code of its own**, before the claim, with nothing written
  and no branch cut. It asks the read's question with the read's rows and `_km_ref_holds`, at the commit
  its tree stands on, so the two cannot disagree on what is there: `not-on-branch` when the base has it and the branch does not, `not-on-base` otherwise
  — only in this checkout, or only in commits origin's base does not have. The read's `reason` is the same
  word. An id no document has, here or there, is still `not-found`. A decision already waiting is still
  `not-proposed`, and `waiting` says so; `decidable` does not judge it. A document is looked for by its
  file, not its id: an id edited only here, at a path the tree has, reads decidable and is `not-found`.

## Alternatives

- **A command of its own, `jig knowledge drop <id>`.** A second verb for what three documents already call
  `reject`, and a second code for a page to learn; nothing it would do differs.
- **`deprecated` for a dropped link.** It reads better for knowledge that was once in force, but
  `waiting` would call it `accepted` and the record ADR-0018 keeps would split in two.
- **`reject` for any accepted stub, `ok` included.** Wider than anybody asked; ADR-0018 keeps `reject`
  narrow so that knowledge in force cannot be retired by accident. Undoing one is a status edit in git.
- **Only correcting `jig-accept`**, saying a link cannot be dropped. Leaves the page without its second
  button and ADR-0036's promise broken.
- **Bringing the base into `knowledge/decisions` before deciding** (a merge or a rebase), so that what
  reached the base later is there. It changes the mechanism roadmap writes share, puts Jig's merge commits
  in a person's pull request, or rewrites a published branch, which adr-20261104 refuses. A refusal with a
  code costs one wait.
- **`not-on-origin`, the issue's word.** Without origin, and for a proposal never committed, the ref
  judged is the local base: `not-on-base` is true in both.
- **Judging the status there as well** (a proposal accepted on the base while this checkout is behind).
  Another read of every document's text; the write already answers that with `not-proposed`.

## Consequences

- A dropped link keeps its file claimed: `knowledge new --source` refuses the same path again, as it does
  after a rejected proposal. Linking it anew means reverting the commit that dropped it.
- `reject` on a stub prints `link to <source> dropped`; the JSON row is `"decision":"rejected"`, as for a
  proposal.
- `decidable` is as of the last fetch: the write fetches first, so the answer can turn either way, and the
  write's code is the one that counts.
- A `reviewed` of a source edited only here is still taken, and records the base's text
  (adr-20261104's consequence); only `reject` refuses what the tree would find nothing to do with.
- The reads start two more git processes at most (one `ls-tree` for each ref), whatever the number of
  documents.

## Amends

- **ADR-0018**: a proposal is not the only thing `reject` takes; an accepted stub whose source needs a
  decision is the other.
- **ADR-0036** (amendment of 2026-09-16): "dropping the link is `reject`" now holds, and `knowledge check`
  no longer requires the source of a retired stub to be tracked.
- **adr-20261104-a-write-goes-in-jigs-own-tree**: a knowledge decision on what is only in the checkout is
  refused `not-on-base` or `not-on-branch`, not `not-found`, and the reads say so first.
