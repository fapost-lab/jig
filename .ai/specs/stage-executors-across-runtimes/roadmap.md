# Roadmap — Stage executors across runtimes

Destination: A person can choose a stage executor at the session, same-runtime subagent, or cross-runtime level, and Jig coordinates the work while preserving the route's evidence and review boundaries.

## Phase 1 — Codex subagents

Goal: A Codex session can delegate implementation and review to a chosen Codex subagent model. Done when: a T2 task can be implemented and reviewed by separate Codex contexts, with the configured model used or an explicit stop, and its findings and receipt pass the ordinary gates.

- [ ] Codex model choice works for implementation and review — add local-only `codex.*` settings, route output, skill behavior, and focused tests for configured and unconfigured Codex sessions.
- [ ] A failed Codex delegation has an explicit outcome — test disabled subagents, an unsupported model, missing fresh context, and the chosen fallback or stop rule without claiming a delegated review occurred.

## Phase 2 — Cross-runtime stage handoff

Goal: A stage can run under a selected other runtime. Done when: a Claude Code session can hand a stage to Codex and a Codex session can hand one to Claude Code, and the coordinator verifies task files before continuing.

- [ ] A selected external runtime can implement a task stage — launch from the task worktree with bounded permissions, preserve the diff and workspace, and report missing CLI/auth, interruption, or partial output.
- [ ] A selected external runtime can review independently — give it a fresh context and explicit review scope, then check the findings ledger and current receipt; require a new review after implementation changes.
- [ ] Cross-runtime delegation works on supported hosts — verify both launch directions, Windows/Git Bash behavior, sandbox and approval settings, and the no-configuration path.

## Phase 3 — Several agents under one route

Goal: Jig can coordinate multiple chosen agents without losing task ownership or stage evidence. Done when: a defined multi-agent scenario completes with deterministic ownership, conflict handling, and one checkable route outcome.

- [ ] fog: Define the multi-agent scenario — decide what the existing phase-run coordinator does not cover and which simultaneous executors produce a user-visible benefit.
- [ ] fog: Define write ownership and merge order — settle whether agents share a task worktree or require separate worktrees before splitting this phase into tasks.

## Waves

Wave 2 follows wave 1 because failure behavior must exercise the actual Codex handoff. Wave 3 follows phase 1 because it extends the established executor contract. Wave 4 follows wave 3 because review needs the external launch path and file checks. Wave 5 follows wave 4 because host-level verification needs both external roles.

1. Codex model choice works for implementation and review
2. A failed Codex delegation has an explicit outcome
3. A selected external runtime can implement a task stage
4. A selected external runtime can review independently
5. Cross-runtime delegation works on supported hosts

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
