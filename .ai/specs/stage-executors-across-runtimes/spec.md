# Stage executors across runtimes

Depth: normal — the three phases and their order are decided; executor failure and the scope of later orchestration still need design decisions.

## Idea

Choose the executor of an SDLC stage at three levels: the current session, a subagent of the same runtime, or another runtime. First add `codex.*` settings for delegation inside Codex; then hand a stage to another runtime through `codex exec`, checking the result through Jig's files and preserving reviewer independence; finally orchestrate multiple agents.

The original discussion and code review remain in `.ai/workspace/tasks/executor-per-stage-across-runtimes/task.md`. This specification develops that material; it does not file, start, or close that task.

## Goal and problem

- A person using Codex cannot currently make Jig's `implement` or `review` stage run on a chosen Codex subagent model. The shipped Claude settings apply only inside Claude Code.
- A person cannot choose Codex for review and Claude Code for implementation, or the reverse, through one Jig route. Stage records must keep the same meaning regardless of the runtime that wrote them.
- Success means `jig task route` states the chosen executor, the stage skill performs the handoff when supported, and the coordinator checks the task's diff, findings, receipt, and verification records before proceeding. An independent review uses a fresh context without the implementation conversation.
- Each phase must provide a useful capability on its own. This spec has no all-phases epic or release level.

## Starting point and evidence

- ADR `20261005-jig-names-the-roles-not-the-models` defines two local-only Claude model keys. `_task_route_delegates` in `scripts/lib/task.sh` only prints them; `skills/jig-task/references/delegation.md` makes the skill responsible for acting on them. The ADR must be amended or superseded before `codex.*` keys or cross-runtime execution ship.
- ADR `20261004-a-route-stage-is-proven-by-its-record` intentionally has no actor field. Findings, receipts, and verify prove recorded state, not the executor's identity or review quality.
- ADR `20260922-a-phase-run-is-coordinated` already coordinates task agents in waves and worktrees. Its statement that Codex lacks subagents is obsolete; current OpenAI documentation describes Codex subagents and per-subagent model choice: https://learn.chatgpt.com/docs/agent-configuration/subagents.
- OpenAI documents `codex exec` as a non-interactive runner, read-only by default, with explicit sandbox and approval options: https://learn.chatgpt.com/docs/non-interactive-mode. This is a candidate transport, not a proven reciprocal Claude Code transport.

## Stress test

- **Hidden assumptions:** A subagent can access the task worktree and write required records; the other runtime's CLI is installed and authenticated; the coordinator can detect a partial write; the selected client exposes model choice. Each needs a focused local check.
- **Main trade-off:** Explicit executor choice improves control and reviewer separation, while adding launch, permission, failure, and support costs. Keep route evidence runtime-neutral and launch behavior at the runtime boundary.
- **Weakest point:** A receipt pins reviewed content, not who reviewed it. Quietly falling back to self-review after an external reviewer fails would make the selection misleading.
- **Failure modes:** An unsupported model or disabled subagents prevents in-runtime delegation; missing CLI/auth or a read-only sandbox prevents external writes; a fix makes a receipt stale; concurrent writers can disturb review scope. The coordinator must surface failures and inspect files after return.
- **Other shapes:** Claude-only delegation with manual Codex use leaves the stated gap. One universal `executor` key from the outset combines subagents with cross-process security before either contract is tested. Prefer the three staged capabilities.

## Scope and non-goals

- **In scope:** local personal choice for implementation and review roles; Codex subagents; cross-runtime handoff; explicit failure handling; fresh-context review; existing task worktrees and ledger/receipt/verify gates; later coordination of several selected executors.
- **Open scope boundary:** Today's delegable roles are `implement` and `review`; review covers T2 review, T4 independent review, and T3/T4 architecture review. Assigning discovery, design, the gate, verify, consolidation, or ship needs a separate decision.
- **Not doing:** project-wide model defaults, a vendor model catalog, runtime-owned agent definitions written by Jig, an actor field in task state, or weaker route gates. This spec does not implement the phases.

## Decisions

- Use three levels of executor choice and deliver them in the stated order. Rejected: treating one configuration key as the whole design, because in-process and cross-process handoffs have different permission and recovery contracts.
- Keep zero configuration useful: with no executor setting, the current route continues to run. Rejected: mandatory executor setup.
- Keep task findings, receipts, and verify as authoritative stage records. Rejected: treating an executor's final message or self-declared actor name as completion evidence.
- Ship phases separately. Phase 1 closes a Codex gap without needing a second CLI; a final-only epic would delay that value.

## Open questions

- When a selected executor is unavailable, should the route stop for a human choice, or may a person configure a fallback in advance? Silent self-review must not count as independent review. Phase 1 must settle this for subagents; phase 2 for missing CLIs and auth.
- Which local-only settings express runtime, model, and optional reasoning effort? Phase 1 may add `codex.implement_model` and `codex.review_model`; phase 2 must decide whether an executor selector supersedes them.
- How does Claude Code launch Codex, and how does Codex launch Claude Code? Confirm both commands, auth, sandbox, Windows/Git Bash, timeout, interruption, and exit status before promising symmetry.
- What minimal observable record, if any, shows that a selected process actually ran without becoming a self-reported actor gate?
- What does phase 3 add beyond the existing phase-run coordinator: several agents within one stage, different runtimes across a wave, or both?

## Assumptions left untested

- Codex's documented subagent model override works in every Jig-supported Codex client. Test the relevant app, CLI, and IDE environments in phase 1.
- An external runner can use a task worktree and its borrowed workspace within its permission boundary. Test a local worktree and a failed/partial run in phase 2.
