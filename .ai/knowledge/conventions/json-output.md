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
  - scripts/lib/common.sh
summary: "What a command offering --json may, must and must not do: one envelope through json_run, values from existing producers, no network, schema raised only on an incompatible change."
reviewed_at: 2026-10-16
---
# A command's `--json` output

The boundary every command that offers `--json` plugs into: `scripts/lib/json.sh` and the shape
pinned in `schemas/json.md` (adr-20261015-a-read-is-one-json-envelope). `jig task list` is the first
implementation; `jig spec list` and `jig status` (attention items) followed it, and legal actions
and failure codes will.

## Practice

```
A command with --json (scripts/lib/json.sh, json_run)

MAY:      add fields to an object (compatible, schema stays); print null for a fact it
          does not have; print warnings for a person on stderr
MUST:     look for --json among all its arguments before anything else runs, and run
          its whole body as the producer of json_run, so every refusal is an envelope;
          print exactly one JSON value on stdout from the producer; build every string
          with json_quote; read each value from the producer that already answers it
          for the text form, the status page or the gates; decide whether an action is
          offered by asking the command's own guard (_task_*_refusal), never a copy of
          its condition — it may withhold more than the guard refuses, never offer more;
          keep the text form's bytes; pin the whole shape of its data in its own test
          file and in schemas/json.md
MUST NOT: touch the network on the read path (no gh, no fetch, no ls-remote); print
          to stdout outside the producer; rename or remove a field, or change its type,
          without raising schema; write anything but what the dispatcher already records;
          change jig_die to print JSON; read the revision itself — json_run takes it,
          before the producer runs

A command that writes a record a read reports (scripts/lib/common.sh, jig_record_changed)

MUST:     call jig_record_changed right after the mv that lands the write, or call a
          writer that does (tests/json.t.sh lists every function with an mv that
          reaches neither)
MUST NOT: raise the revision before the write lands, or once at the command's end
          instead of after each write — except a batch whose many writes are one
          change and that runs only as its own command, never inside $(...):
          housekeeping registers jig_on_exit 'jig_revision_bump' before its first
          write, and only a run that writes (not --dry-run) registers it; call
          jig_record_changed from the status page's own redraw — the saved
          knowledge counts (_status_counts_save) raise with jig_revision_bump, and
          only when a count changed, so the redraw does not mark itself again
```

## Example

`task_list` (scripts/lib/task.sh) finds `--json` anywhere in its arguments, sources `json.sh` and
calls `json_run _task_list "$@"`; `_task_list` parses the same flags as the text form, shares
`_task_list_select` with it, and prints `{"tasks":[...],"hidden":n,"housekeeping":...}` built from
`task_state_get`, `_task_gate_state`, `_task_autopilot_facts`, `_task_autopilot_mode` and
`hklog_flagged_ids`; each task's `actions` come from `_task_actions`, whose rows ask the commands'
own refusal functions (adr-20261015-one-table-of-what-a-person-may-do); a pull request's state and
checks come from the forge cache housekeeping wrote (`forgecache_read`, `forgecache_entry`), never
from the forge. Its whole shape is compared in `tests/task.t.sh`.

A read that answers what a page already shows renders the page's own records. `jig status --json`
prints the items `_status_attention` (scripts/lib/status.sh) produces, and `_status_html_needs`
draws the same records as cards: a new "Needs you" card is a new item kind, added there once and
listed in schemas/json.md, and `tests/status.t.sh` compares every card with its item. Run in a task
worktree, such a read switches `JIG_PROJECT` to the main checkout inside its producer, so it reads
the runtime the page reads, answered by the jig that was asked.

## Rationale

Consumers re-read on every file change, in several projects at once: one parser, one envelope and
no network call keep them working and clear of forge rate limits. A second computation of an answer
is how a report and the command it summarises come to disagree (ARCHITECTURE.md, reporting
commands); the architecture review of the first implementation found exactly that, a mode
recomputed beside `_task_autopilot_mode`. JSON printed from `jig_die` would be lost inside `$(...)`
and doubled by the caller's own refusal, which is why the envelope is built around the producer. The
revision is taken before the data because a write landing during a read must leave the revision
behind the data, never ahead of it; and it is raised after every write, not once per command,
because a write inside `$(...)` or in a command that dies after it must still count
(adr-20261016-the-clone-revision-is-a-claimed-name).
