# Release 0.28.0

Planned with the maintainer on 2026-10-15 (jig-release); the plan below is the approved one.

## What goes in

Already on `main` since v0.27.0 (in the release whatever is picked):
- `link-jig-ui-docs` — a link to Jig UI's documentation site (#247).
- The `contract-extensions` (split by release, JSON contract, #245) and `contract-queue` (#246)
  specs — plans, not behaviour; one changelog line at most.

Reaches it through `main`, before the epic is finished:
- `independent-review` (T3) — every review is done by a reader who has not seen the
  implementation; T4 gets an extended review (#249). It is the reason for this release.

Filed tasks in the epic: none.

- `release-notes-0-28-0` (T2) — the release notes: `docs/changelog.mdx`, `docs/known-issues.mdx`,
  `docs/roadmap.mdx`, and a pass over `docs/` against the diffs. Last item.

## Conditions

- The epic is not finished before #249 (`independent-review`) is merged into `main`.
- The changelog's 0.28.0 section opens with `independent-review`.

## What stays out, and why

- `independent-review` is not on the epic's list: it was started from `main`, so `jig spec link`
  refuses it. It reaches the release through `main`.
- The nine queued tasks (`clone-revision`, `failure-codes`, `forge-cache`, `json-attention`,
  `json-legal-actions`, `json-spec-list`, `json-task-list`, `reduce-ci-feedback-time`,
  `spec-ship-removed-spec`) have an empty `## Goal` — no brief to build from; the `json-*` tasks
  belong to the `contract-extensions` epic, which is released on its own.
- The `contract-extensions` epic: its own release, when the feature is complete.

## Level

**minor** (0.27.0 → 0.28.0): skill behaviour changes in installed projects — every review now
starts a separate reviewer, and T4 gains required checks. No command or setting changes
incompatibly.

## Open questions

None.
