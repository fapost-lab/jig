# Release plan — 2026-10-03

Last release: v0.19.0. Already on main since then, and in this release whatever is picked:
#167 (`jig task start --worktree` moves a started task), #168 (`worktree.share`),
#169 (`route.depth` / `--lean`), #170 (`jig-release`, `jig spec link`, `jig task list --goals`),
#171 (three flaky tests, tests only).

## What goes in, in order

Lies about state:
1. `adr-0038-premise-outlived-two-changes` — ADR-0038's load-bearing premise ("a worktree receives
   nothing from the checkout but its workspace link") is false after carry, the tasks-directory
   link and `worktree.share`; amend it and measure that `jig config get` in a worktree still sees
   the personal layer. T2 (T1 if the measure agrees with the ADR).
2. `skills-write-through-the-door-they-name` — skills require writing into the workspace with a
   redirect, which AGENTS.md forbids; the agent gets contradictory instructions. T2.

Slows work down:
3. `receipt-pins-more-than-the-task` — a review receipt goes stale when unrelated commits arrive
   (merging the default branch forced a re-review twice this week, #152) and does not go stale on
   changes that do touch the review. T3.

Notes:
4. `release-notes-0-20-0` — the changelog and upgrading sections, written against the diffs. T2.

## What stays out, and why

- `gate-is-a-gate` (T3) and `artifact-write-trusts-a-borrowed-directory-link` (T3) — "an agent
  could cheat here": they go last by the ordering rule and each needs a design; next release.
- `stage-delegation` (T3) — started and paused ("after the autopilot epic ships"); a started task
  cannot be linked to the epic. It reaches this release only if it merges into main before the
  epic is finished — it will not.

## Level

minor (0.20.0): main already carries new capabilities since v0.19.0 — `worktree.share`,
`route.depth`, the `jig-release` skill with `jig spec link` and `jig task list --goals`.
