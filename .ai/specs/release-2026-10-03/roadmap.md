# Roadmap — Release 0.20.0

Destination: 0.20.0 is released with the three picked tasks and its notes, and main's CI is green
on the release's merge commit.

Epic: epic/release-2026-10-03
Release: minor

## Phase 1 — Release 0.20.0

Goal: the picked tasks are on the epic and described. Done when: every item below is merged into
the epic and the notes describe them against their diffs.

- [ ] `adr-0038-premise-outlived-two-changes` — ADR-0038's premise matches what a worktree receives today, measured
- [ ] `skills-write-through-the-door-they-name` — skills no longer require what AGENTS.md forbids
- [ ] `receipt-pins-more-than-the-task` — a review receipt goes stale only on changes the review touches
- [ ] `release-notes-0-20-0` — the changelog and upgrading sections for 0.20.0, written against the diffs (after: every other item — the notes describe what merged)

## Waves

1. adr-0038-premise-outlived-two-changes; skills-write-through-the-door-they-name; receipt-pins-more-than-the-task
2. release-notes-0-20-0

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
- A wave entry names an item by its title (the text before its first ` — `) or its task id,
  entries separated by `;` — `jig spec plan` reports an entry that names no item or several.
-->
