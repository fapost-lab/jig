---
id: adr-20261029-a-global-knowledge-edit-narrows-a-re-review
type: adr
status: accepted
date: 2026-10-29
domains:
  - task
  - skills
paths:
  - scripts/lib/task.sh
  - "skills/jig-review/**"
  - "skills/jig-architecture-review/**"
summary: Why a re-review after a knowledge change stays narrow when only global documents moved, why a change to the set or to a path-matched document still forces a full one, and why the receipt lists and stores the documents it read.
reviewed_at: 2026-10-29
---
# A re-review stays narrow when only a global knowledge document moved, and is shown its diff

This narrows one clause of adr-20261019-a-re-review-reads-what-changed-since-review: "when `design` or
`context` changed, the re-review is full". Everything else there stands, and the gates are unchanged.

## Context

The receipt's `context` is one hash over every document `jig context` resolves for the task's files
(adr-20261003-receipt-pins-what-the-review-read). The global documents — `GLOSSARY.md`,
`ARCHITECTURE.md`, `RULES.md` — resolve for any file, and every task's consolidation edits them. So a
merge of the base into a task on a busy repository moves `context` almost every time, and
`--since-review` answered `full`: a reviewer re-read every file of the task and every document, about ten
minutes, to judge code that had not changed against rules that had not changed for it. On
fapost-lab/jig-ui it happened twice in one day (issue #351). The hash could not say more, because the
receipt did not record which documents it covered.

## Decision

- The receipt lists the documents it hashed, one `context_doc: <path> <content hash>` line each, and
  stores each one's content as a git blob when it is written, so a later re-review can be shown what
  changed. The lines are read only by `--since-review`, never compared by a gate; `context` is the
  same hash over the same lines as before.
- When `context` moved, `--since-review` compares the lists:
  - the set of documents differs — one resolves for the task's files that did not at the review, or no
    longer does: `full`;
  - a document that resolves through the task's `paths` or domains changed: `full` — it is the norm
    applied to these very files;
  - only global documents changed: `narrow`, with `context` among the reasons. After the interdiff it
    prints `knowledge changed since review: N documents` and the diff of each, and the re-reviewer
    judges the reviewed change against that diff as well as the interdiff;
  - the receipt has no `context_doc` lines, or a stored blob is gone: `full`.
- A new document whose `paths` match no file of the task does not resolve, so it is in neither list and
  never a reason for `full`.
- `--format paths` still lists only the code interdiff; the global documents resolve for any path
  anyway.

## Alternatives

- **Narrow on any knowledge edit, the reviewer reads the knowledge diff**: a changed convention or ADR
  written for the task's own files is exactly the norm the review applied, and its effect on that code
  is not in the interdiff. Not taken.
- **Judge a global document by the paragraphs that changed**: someone must decide which paragraphs bear
  on the task, and that is the reviewer's judgement the script was meant to replace
  (adr-20261019-a-re-review-reads-what-changed-since-review: the script decides, not the reviewer).
- **Hashes without stored content**: `narrow` without the knowledge diff would let a rule change go
  unread.
- **A separate file next to the receipt**: two files to keep in step for one record.

## Consequences

- A merge of the base that only brings other tasks' consolidation into the global documents costs a
  narrow re-review that reads their diff, not a full one.
- The receipt grows by a line per resolved document, and writing it stores those documents as blobs;
  an unreferenced blob is collected by `git gc` like the reviewed tree, and the re-review after that is
  full.
- A receipt written before this has no `context_doc` lines, so its first re-review after a knowledge
  change is full.
- A wrong `narrow` is bounded: the reviewer still reads the global diff, and a P0 or P1 noticed anywhere
  is recorded.
- Reverting is `git revert`: extra `context_doc:` lines are harmless to the old code.
