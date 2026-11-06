---
id: adr-0015-context-acknowledgement-ledger
type: adr
status: accepted
date: 2026-09-09
domains:
  - context
paths:
  - scripts/lib/context.sh
reviewed_at: 2026-11-06
summary: Why reading knowledge is acknowledged per task, and what that ledger does not prove.
---
# ADR-0015: Reading knowledge is acknowledged in a per-task ledger, and the ledger claims nothing more

## Context

`jig context` returns paths. Returning a path is not evidence that anyone read the
document, and every stage downstream — implement, review — proceeds as if it were. The
observed failure is specific: review runs against changed files for which mandatory
knowledge was never opened, and nothing anywhere says so.

Two further facts shape the answer. Knowledge changes during a task, so "read once at the
start" stops being true halfway through. And exploration reaches new files and new
domains after the first resolution, so the required set is not fixed when the task begins.

## Decision

For a task with a workspace, Jig keeps a ledger at
`.ai/workspace/tasks/<id>/context`: one `<git-hash><TAB><repository-relative-path>` line
per acknowledged document, rewritten atomically through a temporary file.

`jig context acknowledge --task <id> --files <list>|-` records documents the agent states
it has read. `jig context pending` prints tracked documents with no acknowledgement or
whose hash no longer matches. `jig context guard` prints the pending set and exits 1
while any remain; stage skills run it before implementation and before review.

The hash, not a list of names, is the record: a document that changes after being
acknowledged becomes pending again, which is the behaviour the "knowledge changed
mid-task" case needs and the only reason to store anything but a path.

Tracking covers the globals and the required set. Workspace artifacts are returned by
`resolve` and never tracked — they are the task's own output, not knowledge it owes a
reading of.

T0 and T1 deliberately have no workspace, so they have no ledger. The guard then prints
`no task workspace; nothing tracked` and exits 0, rather than failing or passing silently.
A skill can call it unconditionally and the report never implies a check that did not
happen.

**What the ledger proves is narrow, and stating that is part of the decision.** An
acknowledgement records that the agent said it read the document. It is not evidence of
comprehension, and a passing guard is not evidence that the knowledge was applied. It has
exactly the standing of "a skip is not a pass": worth enforcing as a step, worthless if
anyone reports it as more than one.

## Alternatives

- **Trust the skill instruction to read what `context` returned.** Rejected: that is
  today's behaviour and the failure mode it produces is invisible — the run looks
  identical whether the document was read or not.
- **Store acknowledgements in the task `state` file.** Rejected: `state` is a flat
  `key: value` lifecycle record written only by `jig task` (ADR-0005, schemas/state.md);
  a growing list of hashed paths is neither lifecycle nor flat.
- **Record acknowledgements in durable knowledge or in Git.** Rejected: an
  acknowledgement is a fact about one session. Nothing under `.ai/workspace/` is ever
  committed (RULES.md), and this belongs there.
- **Store the full agent transcript as proof of reading.** Rejected: transcripts carry
  abandoned hypotheses and task history that no later reader wants, and they still would
  not prove comprehension.
- **Make the guard fatal when a task has no workspace.** Rejected: it would force a
  workspace onto T0 and T1 and contradict the routing rubric (ADR-0009). A loud no-op is
  honest and costs nothing.
- **Timestamps instead of hashes.** Rejected: mtime changes when nothing did, and does
  not change when a file is restored to an earlier content. `git hash-object` is already
  the framework's content hash (ADR-0003) and git is the only mandatory dependency.

## Consequences

- The ledger is one more transient file per workspace; housekeeping purges it with the
  workspace and no new cleanup rule is needed.
- Acknowledged paths come from a caller, so they are validated before being joined to the
  project root — repository-relative, no `..`, under `.ai/knowledge/`, and existing
  (ADR-0008).
- Stage skills gain a call they must make and a result they must report honestly; the
  guard's own output is written so that quoting it cannot overstate what it proves.
- Re-resolution during a task is now meaningful: an agent that reaches a new domain runs
  `resolve` again and the guard tells it what it newly owes.

> **Amendment (2026-09-16).** The tracked path of a stub is its source, so the ledger records the
> source's hash: an edited source is owed a new reading, and an edit to the stub's metadata alone is
> not (accepted in the specification `knowledge-adoption`). `jig context acknowledge` takes a path
> outside `.ai/knowledge/` only when it is the `source:` of an active or accepted stub — never any
> file of the repository. A selected stub with a missing source fails resolution before anything is
> hashed, so one missing file cannot fail the batch hash of every tracked document.

> **Amendment (2026-10-29).** A task's `Linked:` lines name a task or spec in a neighbouring
> repository, and the documents they reach are tracked too: the ledger holds their absolute path,
> and `jig context acknowledge` takes an absolute path only when the task's links give it at that
> moment. A link back to the task itself gives nothing, so its own artifacts stay untracked
> (adr-20261029-a-task-reads-a-neighbouring-repository-through-a-link).

> **Amendment (2026-11-06, task `context-acknowledge-friction`).** Four releases' worth of review
> showed the ledger inviting false claims: the guard listed dozens of paths with no reason, `acknowledge`
> refused the same document written as `./…` or as an absolute path in a task worktree and died on the
> first such path, a claim could not be withdrawn, and a reviewer's guard passed on the implementer's
> acknowledgements without saying so — one review was signed with 51 documents unread. Four changes,
> none of which changes what the guard passes:
>
> - **A line may carry a third field, the stage** the acknowledgement was made at
>   (`acknowledge --stage <stage>`, from `jig_valid_stage`; `-` when none was given):
>   `<git-hash><TAB><path><TAB><stage>`. A two-field line from before reads as made at no stage. It is
>   the acknowledger's own statement and has exactly the standing of the acknowledgement — not an actor
>   record: nothing gates on it (adr-20261004-a-route-stage-is-proven-by-its-record). The runtime's
>   session id is not stored: adr-20260924-a-checkout-records-what-is-happening-in-it keeps it out of
>   every record, and a subagent inherits its parent's anyway, so it would not tell a reviewer from the
>   implementer.
> - **A passing guard says whose acknowledgements it took**: one line per stage, and `none acknowledged
>   at <stage>: this guard passed on acknowledgements made elsewhere` when it was run for a stage none
>   was made at. A failing guard names the reason each pending document is required, as `resolve` does;
>   `pending` stays a bare list, because it is piped into `acknowledge`.
> - **`acknowledge --revoke`** withdraws acknowledgements, through the same atomic rewrite. A revoked
>   path must be in the ledger and pass the shape check (no `..`, absolute only as a linked document);
>   the document need not exist.
> - **A path is normalised before it is checked**: a leading `./` goes, and an absolute path inside the
>   project becomes repository-relative (compared physically). The check that follows is unchanged, and
>   a batch is still all or nothing — now with every refused path named in one message.
>
> Considered and left to a person: making a guard run for a stage accept only that stage's
> acknowledgements. It would close the gap the attribution only shows, and make each reader of every
> review round re-acknowledge twenty to seventy documents — the friction that produced the false claims.
