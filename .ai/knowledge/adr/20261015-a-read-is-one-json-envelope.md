---
id: adr-20261015-a-read-is-one-json-envelope
type: adr
status: accepted
date: 2026-10-15
domains:
  - task
  - scripts
paths:
  - scripts/lib/json.sh
  - scripts/lib/hklog.sh
  - scripts/lib/task.sh
  - schemas/json.md
summary: Why every --json read is one envelope line built by json.sh around a producer run in a subshell, why revision is null and error.code failed for now, and why housekeeping flags are read through the shared hklog.sh.
reviewed_at: 2026-10-15
---
# A `--json` read prints one envelope, built by json.sh around a producer run in a subshell

## Context

A program that wants Jig's state — Jig UI, CI, a bot, an agent choosing work — had to parse text
written for a person. The contract-extensions spec settled the outer shape with the maintainer
(2026-10-14): one envelope for every command, `{"schema": 1, "revision": …, "generated_at": …,
"data": …}`, with `"error": {"code": …, "message": …}` in place of `data` on a refusal; `schema`
raised only on an incompatible change; reading never touches the network. `jig task list --json`
is the first command to print it, and six more items of the same phase reuse it.

What was left open, and is decided here: who writes the JSON, how a refusal becomes an envelope,
what `revision` says before the counter exists, and where the housekeeping flags a task carries
are read from without a second copy of the status page's logic. ADR-0002 rules out `jq` and every
other new dependency. ARCHITECTURE.md rules out `task.sh` sourcing `status.sh`, where the one
answer to "which housekeeping flags still stand" lived (`_status_flagged_ids`).

## Decision

- **`scripts/lib/json.sh` is the one place Jig writes JSON.** A command offering `--json` sources
  it and calls `json_run <producer> [args]`. Strings go through `json_quote`, which escapes `"`, `\`
  and every control byte without a process per value; other bytes pass through, so the output is
  UTF-8 whenever what Jig read was.
- **The producer runs in a subshell and the envelope is built around what it did.** `json_run`
  captures the producer's stdout and stderr to temporary files, passes stderr on unchanged, and
  prints exactly one line: `data` holding the producer's stdout when it exited 0 and printed
  something; otherwise `error`, with `message` taken from the last `jig: error:` the producer
  printed (to the end of its stderr) or `exited with status <n>`. The command exits with the
  producer's status. The subshell runs under its own `set -e`, outside any condition, because
  bash ignores `set -e` for a whole subshell that sits in an `||`.
- **A command looks for `--json` among all its arguments before it does anything else**, and runs
  its whole body as the producer. An unknown argument, a project without jig, any `jig_die` far
  below — every refusal becomes an envelope by the same path, and `jig_die` itself is not changed.
- **`revision` is `null`** until the per-clone counter exists; `json_revision` is the one function
  that changes then. **`error.code` is `failed`** for every refusal until stable failure codes
  exist; the one line in `json_run` that writes it is where a code will be read.
- **Output is one compact line**, `generated_at` UTC `YYYY-MM-DDTHH:MM:SSZ`, a fact Jig lacks is
  `null` (never an empty string or a missing key), and a value is read from the producer that
  already answers it for the text form, the status page or the gates — never computed twice.
- **The housekeeping log is read through a shared parser, `scripts/lib/hklog.sh`.** The functions
  that decided for the status page which flags still stand moved there unchanged, renamed
  `hklog_*`; `status.sh` and `task.sh` both source it, after `task.sh`, whose `task_state_get` its
  rechecks ask. The page, both reports and the JSON therefore cannot disagree about a flag.
- **`jig task list --json`** lists the tasks the text listing would, with the same flags, as
  `{"tasks": [...], "hidden": n, "housekeeping": {...}|null}`; schemas/json.md pins every field and
  `tests/task.t.sh` compares the whole shape. Its `pull_request` holds only `url`: state and CI
  join it from a cache housekeeping writes (task forge-cache), never from the forge on read.

## Alternatives

- **JSON printed by `jig_die` under a mode flag.** `jig_die` is often called inside `$(...)`,
  whose stdout the caller swallows, so the envelope would be lost there; the caller's own
  `jig_die` would then print a second one. It would also touch `common.sh`, which every command
  loads.
- **Each command writes its own JSON.** A consumer learns one shape per command and one escaping
  bug per writer; the spec rejected per-command envelopes for the same reason.
- **Pretty-printed output.** Indentation in shell without a JSON library is code with no reader
  that needs it: every parser reads a compact line, and a person can pipe it through one.
- **`revision: 0` as the placeholder.** A consumer comparing revisions would read "unknown" as
  "nothing changed" and keep showing stale state.
- **`task.sh` sources `status.sh`, or recomputes the flags.** The first breaks the dependency rule
  in ARCHITECTURE.md; the second is a second copy of the status page's recheck, which would drift
  from it — the failure the reporting-command rule exists to prevent.
- **Every task by default in JSON.** It would contradict the listing rule (finished work is hidden
  and counted) and the text form of the same command; `--all` gives every task and `hidden` says
  how many were left out.

## Consequences

- Every later `--json` command is a producer plus one `json_run` call; its shape goes into
  schemas/json.md and a whole-shape test in its own test file.
- Renaming a task state key the producer reads, or a word `_task_gate_state`,
  `_task_autopilot_facts` or the housekeeping log uses, changes the JSON contract; adding a field is
  free, removing or retyping one raises `schema`.
- A `--json` read costs one more subshell and two temporary files than the text form; the files
  are registered with `jig_cleanup_add`.
- The producer's stdout is held in a file until it ends, so nothing streams; a read that must
  stream would need another design.
- `hklog.sh` depends on `task_state_get` being defined by its caller. A third reader sources
  `task.sh` first, or the rechecks die.
