---
id: adr-20260921-the-status-page-is-the-one-file-a-report-writes
type: adr
status: superseded
date: 2026-09-21
domains:
  - task
paths:
  - scripts/lib/status.sh
summary: Why jig status --html writes one self-contained, escaped, script-free page to .ai/runtime/status.html — the only file a reporting command writes — and shows only answers status already consumes.
reviewed_at: 2026-09-21
---
# `jig status --html` writes one self-contained page into `.ai/runtime/`, the only file a reporting command writes

## Context

The autopilot specification (Phase 5) asks for a status view a person who does not live in a
terminal can read: tasks, findings, receipts and spec progress, with no server and no new
dependency (ADR-0002). Its decision names the shape — a static self-contained HTML file written by
`jig status --html` into `.ai/runtime/` — which collides with a rule of ARCHITECTURE.md: a
reporting command consumes its peers' answers, never recomputes them, *and never writes anything*.

A page also carries text people wrote — task ids, finding locations, spec titles, paused reasons,
paths — into a format where that text can become markup.

## Decision

- **One file, one fixed name.** `jig status --html` writes `.ai/runtime/status.html` atomically
  (`tmp.$$`, then `mv`), prints its absolute path, and prints and changes nothing else. Every run
  replaces the page; the page states when it was made. `.ai/runtime/` is ignored and never
  committed (RULES.md), and it is outside the review receipt's tree only because it is ignored.
- **It is the only write a reporting command makes.** The rest of ARCHITECTURE.md's rule stands:
  the page shows answers `status` already consumes — `_task_blocking_findings`,
  `task_receipt_check`, `_task_worktree_note`, `jig_task_base`, `spec_list_rows`,
  `spec_epic_status`, `km_proposed_count`, the housekeeping-log counts — and embeds the plain text
  report whole. Where a peer printed only formatted text, the peer gained an unformatted producer
  (`spec_list_rows`, which `spec list` now formats) rather than `status` parsing its columns.
- **Self-contained and inert.** Inline CSS, no script, no external asset, light and dark through
  `prefers-color-scheme`: it opens from disk with the network off. Every value is HTML-escaped
  (`& < > " '`) by one function, with `sed` — a `${var//&/…}` replacement means the matched text
  from bash 5.2 on.
- **An uninitialised project is refused**, not given a page: writing it would create `.ai/` in a
  repository that never asked for Jig.
- **Plain `jig status` output does not change.** It shares the per-task reading
  (`_status_task_facts`) and the current-task, housekeeping-age and flag counts with the page, so the
  two cannot drift apart.

## Alternatives

- **A separate `jig report` command** — a second reporting command with the same inputs; the
  specification named `status --html`, and a second command would be one more place to keep in step.
- **Print the HTML to stdout** — writes nothing, but a non-developer then has to redirect output to a
  file, which is the terminal skill the page exists to spare them.
- **A timestamped file per run** — history nobody asked for, growing in `.ai/runtime/` with no
  cleanup; a snapshot with its date on it answers "where do things stand".
- **Parse `jig status` text for the tables** — the text is for people; a path with a space breaks a
  column split. The text is embedded whole instead, and the tables come from the functions.
- **A small script for sorting or folding** — a page that needs JavaScript can be blocked by the
  viewer and is no longer inert; `<details>` folds the full report without it.

## Consequences

- A change to what a peer answers — the blocking-finding line, the receipt check line, a spec
  list state — shows on the page unchanged, and the page's tests in `tests/status.t.sh` assert
  those strings; renaming them is a change to both reports.
- A new value on the page must go through `_status_h`; the escaping test plants markup in every
  field people write.
- The page is a snapshot: it is only as fresh as its last run, and it says so.
