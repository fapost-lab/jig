# Findings — record them, so completion can refuse

A finding said only in the conversation stops nothing. Record every finding in the task's
ledger, and the scripts refuse to mark the task `ready`, to record its knowledge decision and
to ship it while a serious one is unresolved. A task without a workspace has no ledger;
report its findings in the conversation as before.

```
.ai/scripts/jig task finding add <id> --severity P1 --where <path:line> --summary "<one line>"
.ai/scripts/jig task finding set <id> <F-id> fixed|closed|open
.ai/scripts/jig task finding set <id> <F-id> dismissed --reason "<why>"
.ai/scripts/jig task findings <id> [--blocking]
```

## Severity

| | Means | Blocks completion |
|---|---|---|
| P0 | Breaks data or security, or violates an invariant or an accepted ADR | yes |
| P1 | A wrong result or a broken path that will be hit | yes |
| P2 | Worth fixing; the code is correct without it | no |
| P3 | A nit | no |

State the concrete input that breaks it, or it is not a P0 or P1. When unsure between two
levels, pick the higher one: a blocking finding costs a re-review, a missed one ships.

## Who moves a finding

- **Review records** every finding as `open`.
- **Implementation fixes** it and sets `fixed`. The author never closes a finding.
- **Re-review closes**: after the fixes, the reviewer reads each `fixed` finding against the
  new code and sets `closed`, or `open` when it is not fixed. A P0 or P1 in `fixed` still
  blocks until then.
- **Dismissing** — the finding is wrong, or the human decided not to fix it — needs a reason.
  A P2 or P3 you may dismiss on your own. A P0 or P1 only with the human's yes in the
  conversation: show the finding, say why, and put their decision in the reason.

`closed` and `dismissed` are final; a regression reopens the finding with `open`.
