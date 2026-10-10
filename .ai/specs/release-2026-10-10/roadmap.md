# Roadmap — Release 0.26.0

Destination: 0.26.0 is released with the four picked tasks and its notes, and main's CI is green
on the release's merge commit.

Epic: epic/release-2026-10-10
Release: minor

## Phase 1 — Release 0.26.0

Goal: the picked tasks are on the epic and described. Done when: every item below is merged into
the epic and the notes describe them against their diffs.

- [ ] `phase-run-stops-notify` — a phase run's coordinator stop reaches Telegram
- [ ] `notification-hook-for-sessions` — an ordinary session waiting for the person sends a Telegram message, behind `notify.interactive`
- [ ] `tracker-issue-id` — a task carries its tracker issue id, read from the task id by a project pattern, and ship puts it into the commit and the pull request title
- [ ] `linked-sources-in-pr-body` — the autopilot report and the pull request body name changed linked knowledge sources that wait for the person's review
- [ ] `release-2026-10-10-notes` — the changelog section for 0.26.0, written against the diffs (after: every other item — the notes describe what merged)

## Waves

1. phase-run-stops-notify; notification-hook-for-sessions
2. tracker-issue-id
3. linked-sources-in-pr-body
4. release-2026-10-10-notes

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
