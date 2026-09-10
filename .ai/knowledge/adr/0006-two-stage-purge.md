---
id: adr-0006-two-stage-purge
type: adr
status: accepted
date: 2026-09-08
domains: [housekeeping, safety]
paths:
  - "scripts/lib/housekeeping.sh"
summary: Why workspace deletion happens in two stages and never on unknown remote state.
reviewed_at: 2026-09-10
---
# ADR-0006: Housekeeping purges in two stages via a local trash directory

## Context

Housekeeping runs unattended, without an LLM, and deletes directories based on
inferred remote state. The spec requires the destructive false-positive rate to approach
zero. A shell `rm -rf` on a computed path is the single riskiest operation in the
framework.

## Decision

1. A workspace selected for purge is **moved** to `.ai/runtime/trash/<date>/<task-id>/`.
2. Trash entries older than `trash_ttl` (default 7d) are deleted on a later run.
3. Before any move or delete the path is validated: resolves inside `.ai/`, is a
   directory, and `task-id` is well-formed.

   > **Correction (2026-09-10, Phase 5).** This point originally stated the pattern
   > `^[A-Za-z0-9._-]+$`, which matches `..` and is therefore not the rule that makes
   > the invariant true. The implemented rule — `_task_valid_id` in `scripts/lib/task.sh`,
   > applied at the single choke point `task_dir` — additionally rejects any leading dot,
   > which is what rules out `.` and `..`. `RULES.md` states it correctly. The decision
   > is unchanged; only its stated pattern was wrong. Implementations must call
   > `task_dir`/`_task_valid_id` rather than transcribe a regex from this document.
4. `--dry-run` prints the plan without touching the filesystem.
5. Every action is appended to `.ai/runtime/housekeeping.log`.

## Alternatives

- **Direct deletion** — rejected: a wrong merge inference destroys the only copy of
  in-progress task context.
- **Never delete, only report** — rejected: reintroduces manual discipline, which
  `RULES.md` rules out as a scope invariant.

## Consequences

- A false positive is recoverable for `trash_ttl` days with `mv`.
- Disk usage is bounded by the TTL, not by developer memory.
