# Release 2026-10-19

The release plan the owner approved on 2026-10-19, as shown.

## What goes in, in order

Already on main since `v0.29.0`, in the release whatever is picked:

- `cosmetic-edits-keep-receipt` (PR #266, T3) — a re-review reads only what changed since the
  review (`jig task receipt <id> --since-review`); a P3 is not fixed after the review, it is
  listed in the pull request.
- PR #264 — the `contract-queue` spec declaration; no user-visible change.

Tasks to build in this release: none.

Last item:

- `release-notes-2026-10-19` (T2) — the changelog section, `known-issues.mdx` and `roadmap.mdx`
  revised against the release (the item "A second review round must not open a new front" is
  half done: the narrow re-review shipped, "a blocker found only in the second round goes to the
  human" did not), and a walk over the other pages under `docs/`.

## What stays out, and why

- `queue-file`, `queue-json`, `queue-status-context`, `pause-requests`, `task-new-json` belong to
  the open `contract-queue` epic, a release of its own; `queue-file` is already started on it.
- `owner-gate-in-unattended-clone`, `spec-ship-removed-spec` (T2, not started) have an empty
  `## Goal` — a gap in their brief — and each would add a build round and a review.

## Level

minor → 0.30.0: a new capability (`--since-review` and a changed re-review process); nothing
breaks.
