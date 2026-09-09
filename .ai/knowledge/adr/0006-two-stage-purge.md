---
id: adr-0006-two-stage-purge
type: adr
status: accepted
date: 2026-09-08
domains: [housekeeping, safety]
paths:
  - "scripts/lib/housekeeping.sh"
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
   directory, and `task-id` matches `^[A-Za-z0-9._-]+$`.
4. `--dry-run` prints the plan without touching the filesystem.
5. Every action is appended to `.ai/runtime/housekeeping.log`.

## Alternatives

- **Direct deletion** — rejected: a wrong merge inference destroys the only copy of
  in-progress task context.
- **Never delete, only report** — rejected: reintroduces manual discipline (spec §3.8).

## Consequences

- A false positive is recoverable for `trash_ttl` days with `mv`.
- Disk usage is bounded by the TTL, not by developer memory.
