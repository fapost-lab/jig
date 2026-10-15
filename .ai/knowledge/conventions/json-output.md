---
id: convention-json-output
type: convention
status: active
domains:
  - scripts
  - task
paths:
  - scripts/lib/json.sh
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - scripts/lib/spec.sh
  - schemas/json.md
  - scripts/lib/forgecache.sh
summary: "What a command offering --json may, must and must not do: one envelope through json_run, values from existing producers, no network, schema raised only on an incompatible change."
reviewed_at: 2026-10-15
---
# A command's `--json` output

The boundary every command that offers `--json` plugs into: `scripts/lib/json.sh` and the shape
pinned in `schemas/json.md` (adr-20261015-a-read-is-one-json-envelope). `jig task list` is the first
implementation; the spec list, attention items, legal actions and failure codes follow it.

## Practice

```
A command with --json (scripts/lib/json.sh, json_run)

MAY:      add fields to an object (compatible, schema stays); print null for a fact it
          does not have; print warnings for a person on stderr
MUST:     look for --json among all its arguments before anything else runs, and run
          its whole body as the producer of json_run, so every refusal is an envelope;
          print exactly one JSON value on stdout from the producer; build every string
          with json_quote; read each value from the producer that already answers it
          for the text form, the status page or the gates; keep the text form's bytes;
          pin the whole shape of its data in its own test file and in schemas/json.md
MUST NOT: touch the network on the read path (no gh, no fetch, no ls-remote); print
          to stdout outside the producer; rename or remove a field, or change its type,
          without raising schema; write anything but what the dispatcher already records;
          change jig_die to print JSON
```

## Example

`task_list` (scripts/lib/task.sh) finds `--json` anywhere in its arguments, sources `json.sh` and
calls `json_run _task_list "$@"`; `_task_list` parses the same flags as the text form, shares
`_task_list_select` with it, and prints `{"tasks":[...],"hidden":n,"housekeeping":...}` built from
`task_state_get`, `_task_gate_state`, `_task_autopilot_facts`, `_task_autopilot_mode` and
`hklog_flagged_ids`; a pull request's state and checks come from the forge cache housekeeping
wrote (`forgecache_read`, `forgecache_entry`), never from the forge. Its whole shape is compared in
`tests/task.t.sh`.

## Rationale

Consumers re-read on every file change, in several projects at once: one parser, one envelope and
no network call keep them working and clear of forge rate limits. A second computation of an answer
is how a report and the command it summarises come to disagree (ARCHITECTURE.md, reporting
commands); the architecture review of the first implementation found exactly that, a mode
recomputed beside `_task_autopilot_mode`. JSON printed from `jig_die` would be lost inside `$(...)`
and doubled by the caller's own refusal, which is why the envelope is built around the producer.
