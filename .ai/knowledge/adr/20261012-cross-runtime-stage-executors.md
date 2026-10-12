---
id: adr-20261012-cross-runtime-stage-executors
type: adr
status: accepted
date: 2026-10-12
domains:
  - config
  - task
  - skills
  - adapters
paths:
  - scripts/lib/config.sh
  - scripts/lib/task.sh
  - skills/jig-task/references/delegation.md
  - skills/jig-implement/SKILL.md
  - skills/jig-review/SKILL.md
  - skills/jig-autopilot/SKILL.md
  - skills/jig-architecture-review/SKILL.md
summary: Local runtime keys select a bounded external stage process launched by the agent; scripts stay deterministic, and the coordinator checks findings and receipts.
---
# A stage's external runtime is selected locally and launched by the agent

## Context

Phase 1 added model choices for subagents inside Codex, alongside Claude Code. A person
still could not make a Codex session hand implementation to Claude Code, or the reverse,
without an ad hoc prompt. The route's findings, receipt and verify already pin task
content without recording an actor. A worktree's task workspace may be linked outside
its directory, and an external process should not receive write access to that owner.
ADR-0001 and `RULES.md` explicitly prohibit scripts from invoking an LLM. The design
must keep that boundary even though a shell launcher would be simpler to test.

## Decision

- Four local-only keys select a stage's runtime and optional external model:
  `executor.implement_runtime`, `executor.review_runtime` (`claude` or `codex`), and
  `executor.implement_model`, `executor.review_model` (opaque). Empty runtime keeps the
  current session. A runtime matching the current session also stays there and uses
  its existing in-runtime subagent setting. A different runtime takes precedence over
  that subagent setting for the selected stage. A model key alone has no effect.
- `jig task route` prints the configured runtime and model. It does not launch either
  CLI, inspect vendor models or change a route gate. The current agent follows the
  delegation skill to launch the external CLI from the task worktree with bounded
  permissions. Scripts remain deterministic.
- External implementation is assigned source edits inside the worktree and is told not
  to run Jig lifecycle commands. Codex still has a shell, so this is an instruction,
  not a permission guarantee. The coordinator checks its exit, denied tools, HEAD,
  index, diff, untracked files and task workspace records; it runs tests and writes
  task artifacts. Unexpected lifecycle changes fail the stage.
  Codex workspace-write otherwise also permits `/tmp` and `$TMPDIR`; its external
  invocation explicitly excludes both roots. The sandbox header must name only the
  worktree as writable. A temporary symlink escape test was denied. Claude restricted
  file tools are confined to the worktree.
- External review starts as a new read-only process without the implementation
  conversation. It reports findings to the coordinator, who checks the report and
  current diff, writes the findings ledger and creates a review receipt. The receipt
  pins content, not the reviewer's identity. A change after review needs a new
  process and new receipt.
- Missing CLI or auth, unsupported model, permission denial, interruption, malformed
  output, or unexpected partial work stops the stage with the cause. There is no
  silent fallback to the coordinator or a wider sandbox. This extends Phase 1's
  explicit Codex failure behavior to external execution.

## Alternatives

- **A Jig script spawning `codex exec` or `claude -p`:** rejected because it directly
  violates ADR-0001 and would make scripts an AI process orchestrator.
- **Reuse `claude.*_model` and `codex.*_model`:** rejected because those keys mean a
  same-runtime subagent model, not a separate process or permission boundary.
- **Let the external reviewer write the linked task workspace:** rejected because the
  link can leave the restricted worktree. The coordinator transfers checked findings.
- **An actor field on the receipt:** rejected by the existing route-evidence ADR; the
  actor would certify itself without a mechanical check.

## Consequences

The person can choose the runtime for implementation and review without changing
project defaults. The skill owns vendor flags and failure handling; it needs live
smoke checks when a CLI changes. Scripts and route evidence remain runtime-neutral.
An unsupported host stops the selected stage instead of widening permissions.
Reverting this decision removes four keys, route output and skill instructions;
existing task state, findings and receipts need no migration.
