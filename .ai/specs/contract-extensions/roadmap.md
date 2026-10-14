# Roadmap — Contract extensions

Destination: a program can read every task, spec and epic of a clone as data, in one envelope with
one revision of the clone, without parsing text and without touching the network.

Epic: epic/contract-extensions
Release: minor

## Phase 1 — Jig can be read by a program

Goal: what a tool needs to know about a clone is available as data, with no text parsing. Done
when each item below prints stable JSON in the shared envelope, the shapes are documented, and a
contract test pins each one.

- [ ] task list as JSON — every task of a clone in the shared envelope: class, status, gate, autopilot, branch, worktree, pull request, housekeeping flags
- [ ] clone revision — every Jig write raises one per-clone counter, and every JSON read reports it (after: task list — the envelope it is reported in)
- [ ] pull request and CI cache — housekeeping keeps what it already asks the forge, with `fetched_at`, and the task list reads it offline (after: task list — the fields it fills)
- [ ] spec and epic list as JSON — specs with phases and items, progress, epic branch, release level (after: task list — same envelope and conventions)
- [ ] attention items as data — what needs a person, from the logic behind the status page rather than a second copy of it (after: task list — same envelope)
- [ ] legal human actions per task state — Jig says what a person may do next (after: task list — actions are read from a task's state)
- [ ] stable failure codes — each refusal names a code that a tool can act on, in the envelope's `error` (after: task list — the envelope that carries it)
- [ ] fog: registration hook in `jig init` for an installed UI

## Waves

1. Task list as JSON.
2. Clone revision; pull request and CI cache; spec and epic list; attention items; legal actions; failure codes.

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
-->
