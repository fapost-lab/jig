---
id: adr-20260921-review-findings-block-completion
type: adr
status: accepted
date: 2026-09-21
domains:
  - task
  - skills
paths:
  - scripts/lib/task.sh
  - skills/jig-review/references/findings.md
  - scripts/lib/status.sh
  - schemas/state.md
  - "skills/jig-verify/**"
  - "skills/jig-implement/**"
  - "skills/jig-architecture-review/**"
  - "skills/jig-review/**"
summary: Why review findings go into a per-task ledger with severity P0–P3, why an open or unre-reviewed P0/P1 refuses ready, consolidation and ship, and why jig verify stays task-agnostic.
reviewed_at: 2026-09-21
---
# Review findings go into a per-task ledger, and a serious unresolved one refuses completion

## Context

Review and architecture review reported findings in the conversation: "a review that ends
without a decision on every finding is unfinished" was a request to a model, and nothing a
script could see stopped a task with a known serious defect from being marked `ready`,
consolidated and shipped. The autopilot specification makes that the precondition for running a
task without a human: its stops must be mechanical, and a review finding is the first of them.

Its roadmap said "`jig verify` and consolidation refuse". Discovery found that `jig verify` knows
nothing of tasks — a profile's exit code alone decides its result (`domains/verify`) — and that
CI, where it also runs, has no workspace, so a findings check there would always pass silently.

## Decision

- **A ledger per task**: `.ai/workspace/tasks/<id>/findings`, one tab-separated line per finding —
  id `F<n>`, severity, status, where, summary, date, and a reason when dismissed. Gitignored like
  the rest of the workspace; written atomically; owned by the task domain and changed only through
  `jig task finding add|set`, read through `jig task findings`.
- **Severity P0–P3.** P0 breaks data or security or violates an invariant or accepted ADR; P1 is a
  wrong result on a path that will be hit; P2 is worth fixing; P3 is a nit. The definitions live in
  `skills/jig-review/references/findings.md`, shared by review and architecture review.
- **Statuses `open → fixed → closed`, and `dismissed` with a reason.** A finding is **blocking**
  while it is P0 or P1 and `open` or `fixed`: a fix counts once a re-review closes it, not when the
  author says so. `closed` and `dismissed` go back only to `open`.
- **Completion refuses in the task domain**, in three places: `jig task set <id> status ready` (the
  end of verification), `jig task set <id> knowledge_consolidated true` (consolidation) and
  `jig task ship`. Each message names the blocking findings and the two ways out. `jig verify`
  is unchanged — a deliberate departure from the roadmap's wording, approved at the gate.
- **Dismissing a P0 or P1 is the human's decision.** The script accepts a dismissal of any
  severity with a reason, since it cannot know who calls it; the skills allow the agent to dismiss
  a P2 or P3 alone and a P0 or P1 only with the human's yes in the conversation, recorded in the
  reason.
- A task without a workspace has no ledger, and nothing changes for it.

## Alternatives

- **Refuse in `jig verify`**, as the roadmap first said: the verify domain would learn about tasks,
  and in CI the check would pass on an absent ledger every time.
- **A committed ledger**, so a pull request's reviewer sees the findings: rejected for now — nothing
  under `.ai/workspace/` is ever committed (RULES.md), and what was reviewed is the review receipt's
  question, the next item of the specification.
- **The author closes their own findings**: then the ledger stops nothing. The rule that review
  closes is the skills'; the script cannot check who calls it, and the review receipt is what will
  pin the ledger's state to a review.
- **Free-form Markdown**: a script has to read severity and status.

## Consequences

- A task with a recorded P0 or P1 cannot be marked `ready`, consolidated or shipped until a
  re-review closes it or the human dismisses it — the stop the autopilot needs.
- The ledger is a claim an agent writes (ADR-0020): it protects against forgetting, not against an
  agent that closes its own finding. The review receipt binds it to a reviewed commit.
- `task set` now has three cross-key rules instead of one; `jig status` shows `blocking=<n>` on a
  task's line.
