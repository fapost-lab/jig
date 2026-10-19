---
id: adr-20261019-a-re-review-reads-what-changed-since-review
type: adr
status: accepted
date: 2026-10-19
domains:
  - task
  - skills
summary: Why a re-review after a fix reads only the interdiff since the review when the script says it may, why design or knowledge changes force a full one, why the gates stay as they are, and why a P3 is never fixed after the review.
paths:
  - scripts/lib/task.sh
  - "skills/jig-review/**"
  - "skills/jig-architecture-review/**"
---
# A re-review reads what changed since the review, when the script says it may; a P3 is not fixed after it

This narrows the cost of a re-review under adr-20260921-review-receipt-pins-what-was-reviewed and
adr-20261003-receipt-pins-what-the-review-read. It does not touch what they gate.

## Context

Any change after a review makes its receipt stale, so a one-line fix, a renamed variable or a
reworded comment asks for a new review, and every re-review is a fresh reader (adr-20261015-every-review-is-a-fresh-reader)
that reads the whole task's diff again. Most of those rounds are cosmetic: the largest source is a P3
nit that was fixed after the review and then needed a round to confirm it. The cost of a round is
out of proportion to the size of the edit, and the gate is right to refuse: a "cosmetic" edit is
the claim the receipt exists to check.

## Decision

- The receipt gains a `merge_base:` line, the commit the task's diff was measured from. It is read
  only by `jig task receipt --since-review`, never compared by a gate.
- `jig task receipt <id> --since-review [--format report|paths]` prints the interdiff, from the receipt's
  `tree` to the current review tree, limited to the files of the task then and now, under the first line
  `re-review: narrow (<reasons>)`. It answers `re-review: none` (exit 0) when the receipt is current and
  `re-review: full — <why>` (exit 1) when there is no receipt, when `design` or `context` changed, when the
  receipt has no `merge_base` or only a `tree`, or when the reviewed tree or commit is no longer in the
  object store. Only `diff` and `findings` moving permits `narrow`. It belongs to `task receipt`, the
  command that owns the receipt, and not to `task changes`: ADR-0022 keeps that one an inventory from an
  explicit `--base`, with no baseline taken from task state, and an interdiff from the receipt is exactly
  such a baseline.
- The script decides whether a re-review may narrow, not the reviewer: whoever is reading must not be
  the one to judge that the earlier reading still holds. `design` and `context` are the norm the review
  applied, not code; when they move, what was reviewed against them is not the same question, so the
  re-review reads everything.
- The jig-review skill tells a narrow re-reviewer to read the interdiff, each `fixed` finding against the new
  code and the surrounding code as far as judging the interdiff needs. New findings are those the interdiff
  introduced; a P0 or P1 noticed anywhere is still recorded; a P2 or P3 outside the interdiff is not.
  jig-architecture-review narrows the same way, checking its five questions against the interdiff — on
  the T3 route it is the only review. An external reviewer cannot run Jig, so the coordinator runs
  `--since-review` and puts the verdict and the interdiff into its prompt.
- The gates are unchanged. The receipt still goes stale on any change, `ready`, the knowledge decision and
  `task ship` refuse as before, a re-review writes a new receipt, and every re-review is a fresh reader.
- A P3 is never fixed after the review, at any depth: it stays `open` and is listed in the pull request.
  A P2 is still fixed at full depth. A fix the person asks for after the review is an ordinary edit and a
  narrow re-review.

## Alternatives

- **A whitespace-insensitive pin**: misses most cosmetic edits (a renamed variable, a reworded
  comment), and misses meaningful indentation in Python, YAML, Makefile and markdown.
- **The author amends the receipt (`--amend`), the interdiff goes into the pull request**: ships a logic
  change within a line limit unreviewed, and contradicts adr-20261015-every-review-is-a-fresh-reader and
  ADR-0020. May be revisited if the narrow re-review is still too expensive.
- **A docs-only exemption**: contradicts the gate decision in adr-20260921-review-receipt-pins-what-was-reviewed.
- **Pin the reviewed tree with a ref**: a new ref lifecycle for housekeeping to cover a rare case; a full
  re-review is cheaper than owning it.

## Consequences

- A re-review after a small fix costs minutes, and the nits that caused most of the rounds are listed instead.
- Receipts written before this have no `merge_base`, so their first re-review is full.
- The unreferenced reviewed tree is collected by `git gc` after about two weeks; a re-review after that is full.
- The narrowing is honoured by the skill, not enforced. That is safe because a reviewer may always read
  more than the interdiff, and nothing a gate relies on depends on how much was read.
- Reverting is `git revert`: an extra `merge_base:` line is harmless to the old code.
