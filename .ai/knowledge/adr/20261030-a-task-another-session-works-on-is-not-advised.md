---
id: adr-20261030-a-task-another-session-works-on-is-not-advised
type: adr
status: accepted
date: 2026-10-30
domains:
  - task
  - scripts
paths:
  - scripts/lib/checkout.sh
  - scripts/lib/queue.sh
  - schemas/json.md
summary: Why a session that works a task records it per clone under runtime/taken, and why jig queue next names such a task as taken instead of advising it.
---
# A task another session works on is not advised: the session that works a task records it for the clone, and `jig queue next` names it as taken

## Context

On 2026-10-30 `jig queue next` advised `review-smells-and-two-axes` (P0, T3) as "not started" while
another session was writing its `discovery.md` and `task.md` in the main checkout. There was no
branch yet — discovery comes before `jig task start` — and nothing else the queue reads had changed.
An agent following the advice would have started the same task in parallel, and an unattended
autopilot would have approved its T3 gate on the person's behalf.

What jig already recorded could not answer the question:

- `runtime/working/<name>` (adr-20260924-a-checkout-records-what-is-happening-in-it) is **per
  checkout**, and `jig queue next` may be asked from any worktree; no checkout reads another's
  `.ai/` (ADR-0008, ADR-0029).
- A working record named by a task **cannot say which session wrote it** — that ADR names the false
  refusal this causes — so the caller's own task and another session's look the same.
- Its naming counts every mention of a task (`task show`, `queue set <id>`) as work, so a coordinator
  reading or ordering the queue would appear to work every task in it.

## Decision

- **A second record, for the clone:** `<clone root>/.ai/runtime/taken/<task-id>/<session-id>`, in
  the clone's main checkout, found as the queue's own file is (`jig_config_clone_root`). Which session
  holds which task is a fact about the clone, one answer for every worktree, which is the test
  ADR-0008's per-clone runtime exception admits by (fifth user, amendment of this date).
- **Its body** is a flat record — `checkout:` (the checkout the command ran in), `since:` (UTC, when
  this session took the task) and `command:` (what last ran) — and its mtime is when the session was
  last active. Only what nothing can compute afterwards is stored. The session id is only the file
  name: compared with the caller's id, never shown, never sent.
- **Working a task is how a session takes it** — not a claim in the sense of adr-20261023-a-claim-is-an-exclusive-create: two sessions may both hold a record, and the newest holds the task. The dispatcher's recorder (`jig_checkout_record`) writes it before
  the command runs, for `jig task start|bootstrap|set|artifact|finding|autopilot|gate|receipt <id>`
  and `jig context … --task <id>`; the task is the first argument that is a valid id with a
  workspace. Reading, filing, ordering, shipping and closing a task are not taking it. **No record
  without a session id**: a record that cannot say whose it is could not tell the caller's own task
  from another's (Codex today, the boundary the working record names too).
- **The newest live record holds the task**, live meaning younger than `checkout.busy_ttl` (12 h by
  default, the working record's window). On a tie of mtimes the caller's own record wins. A person
  takes over the task of a session that died by working on it; nothing is released by hand and
  nothing is deleted (RULES.md: a file here is neither a workspace nor a trash entry).
- **The queue reads it** (`jig_checkout_taken`, `scripts/lib/checkout.sh`). In `jig queue next` a
  candidate held by another session is not advised; the answer names it — `task:<id> is taken by
  another session in <checkout>, since <since>, last active <n> ago` — and `--json` lists it under
  `taken` (schemas/json.md). With nothing left to advise, `reason` is `taken`, after `waiting` and
  before `paused`, so every answer that existed before reads the same. `jig queue list` prints the
  same line under an active task another session holds; `jig status` prints the verdict line, as
  before.
- **Every write of a record raises the clone's revision** (`jig_record_changed`), because a read
  reports it (conventions/json-output.md, adr-20261016-the-clone-revision-is-a-claimed-name): a
  board that compares revisions sees a task become taken even when the command that took it, such
  as `jig context resolve --task <id>`, wrote nothing else. Most commands that take a task raise it
  themselves anyway. `idle_seconds` grows with the clock, not with a write, as `generated_at` does.
- **It advises; it does not refuse.** `jig task start` of a taken task still works, and the person who
  takes it then holds it.

## Alternatives

- **Read every checkout's `runtime/working/`** — a lookup into another checkout's `.ai/`, which
  ADR-0008 forbids, and the records still cannot say which session wrote them.
- **Freshness of the task's workspace files** — the caller's own writes look exactly like another
  session's.
- **An explicit `jig task claim` / `release`** — a claim a skill must remember to make is the ritual
  conventions/required-records.md warns about; the incident happened in a session that followed the
  skill. Working the task already says it.
- **The record inside the task's workspace** — every writer of a workspace asks
  `_task_workspace_root` (task.sh), which the recorder that runs before every command must not
  source; and a session's presence is not task data.
- **A refusal in `task start`** — a refusal blocks a person on evidence that may be hours old; the
  queue's advice is where the parallel start began.

## Consequences

- `jig queue next` is one stat per queued task with a record, plus one session lookup per command.
- A task advised to nobody for up to `checkout.busy_ttl` after its session died, unless someone works
  on it; the answer says who and since when, so a person can decide.
- A runtime without session ids neither holds tasks nor recognises its own; every live record is
  another's to it.
- `checkout.sh` now holds two records; the per-checkout one keeps its own subject and rules.
- A `jig queue` write carrying a revision read before another session took a task is refused as
  `stale-revision`: the clone did change, and the writer reads again.
