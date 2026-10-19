---
id: adr-20261019-the-queue-is-one-file-written-against-a-revision
type: adr
status: accepted
date: 2026-10-19
domains:
  - task
  - scripts
paths:
  - scripts/lib/queue.sh
  - scripts/lib/common.sh
  - schemas/json.md
summary: Why the queue is .ai/runtime/queue in the main checkout, one tab-separated record per line written only by jig queue, and why a write claims the revision above the caller's (jig_revision_claim) and refuses with stale-revision, then moves the file and raises the revision again.
reviewed_at: 2026-10-19
---
# The queue is one tab-separated file per clone, written only by `jig queue` against the revision its caller read

## Context

The contract-queue spec settled with the maintainer (2026-10-14) that priority, order and
dependencies of tasks and epics live in one queue file per clone, in the main checkout beside
`.ai/runtime/`, not under git; that its only writer is a Jig command, atomic and checked against the
clone revision the caller read (adr-20261016-the-clone-revision-is-a-claimed-name); that priority is
0–5, position sparse (step 100) and epics a level of the same queue; and that a reorder is one
command moving one item. Its consumer is Jig UI's Phase 2: reorder by drag, priority, and a
stale-revision refusal shown as a conflict. Left open, and decided here: the file's format and
place, the command names, and how "checked against the revision" is made exact without a lock or
a new dependency (ADR-0002, ADR-0037).

## Decision

- **The file is `.ai/runtime/queue` in the clone's main checkout** (`jig_config_clone_root`), the
  fourth user of ADR-0008's per-clone runtime exception (as amended 2026-10-19: the first that
  holds data a person wrote, so lost it is gone rather than rebuilt), after the status page, the verify run
  record and the revision. Every worktree reads and writes the same file. `.ai/runtime` is already
  ignored by every installed project, so no `.gitignore` changes, and neither `upgrade` nor
  housekeeping touches it. A lost `.ai/runtime` loses the queue together with the revision, and a
  write carrying a revision from before the loss is refused (below).
- **The format is one record per line, fields separated by a tab**, read and written by `awk`:
  a first line `# jig queue 1 — …` naming the format version; `item <ref> <level> <position>
  <priority>`; `dep <ref> <on-ref> <reason>`. `<ref>` is `task:<id>` or `epic:<spec-id>`;
  `<level>` is `-` (the top) or `epic:<spec-id>`; `<position>` a non-negative integer;
  `<priority>` `0`–`5` or `-`. A reason is one line: tabs and line breaks become spaces when it is
  written. The writer prints records in a canonical order (items by level, the top first, and
  position; then dependencies; then everything else) so the file reads and diffs the same way
  whoever wrote it.
- **A line of a kind the writer does not know is kept as it is, and another format version is
  refused, never rewritten.** The pause requests the same spec adds become a new kind of line; a
  writer that predates them neither drops them nor breaks on them.
- **The commands are `jig queue [list]`, `set <ref> --priority <0-5|none>`, `move <ref>
  (--before <ref> | --after <ref> | --top | --bottom)`, `depend <ref> --on <ref> --reason <text>`,
  `undepend <ref> --on <ref>` and `remove <ref>`.** Every write takes `--revision <n>` and `--json`.
  `set`, `move` and `depend` add an item that is not queued yet, so a consumer needs no separate
  "add". A bare id is a task. A task must have a workspace; an epic must be a spec in this checkout
  whose roadmap declares an epic branch — except for `remove` and `undepend`, which take any
  well-formed reference, so an item whose task went to trash or whose spec was retired can still be
  taken out.
- **`0` is the most urgent priority**, as P0 is for review findings. Priority is a label: the order
  is the positions'. Choosing the next task from priority, order and dependencies is the spec's fog,
  not this decision.
- **A task's level is computed at each write that touches it** — its `Spec:` line names a spec
  whose roadmap declares an open epic, asked of `jig_task_epic` (common.sh), the one answer
  `task start` cuts by too — and stored, so the readers that follow do not compute it again. A move
  places an item only against an item of its own level. Off the happy path the two commands share
  the answer, not the policy: a record that makes the answer a guess — two `Spec:` lines, two
  `Epic:` lines — is refused by both; a spec this checkout does not have and a finished epic make
  `task start` refuse, while the queue puts the task on the top level, because it records where
  work sits rather than where a branch is cut (and the first is the accepted risk below).
- **A move takes the integer halfway between the new neighbours; with none left, the same command
  respaces that level by 100 in the same single write.** The spec forbids a renumbering a consumer
  issues as several commands, because a reader could see half of it; one write is never seen half
  done. Without the respacing, about seven moves into one place would make the next one impossible.
- **The write is checked by a claim of the revision.** `jig_revision_claim <E>` (common.sh) is the
  revision ADR's `mkdir <E+1>` made exact, as its Consequences prescribed. Before the claim the
  highest name must be `<E>` (for `<E>` = 0: no name at all), or the call is stale and claims
  nothing — so a revision that is old, from before a lost `.ai/runtime`, or above the clone's never
  creates a name. Then `mkdir <E+1>`: of two writers holding one revision at most one creates it.
  After it, the claim must be the highest name; one that appeared above it in between — a cleared
  name created again, any other raise — makes it stale, and it is withdrawn (`rmdir` of the
  digits-only name the call just made). A claim is withdrawn only from under a higher name, so the
  revision never goes down, which the revision ADR relies on. For `<E>` = 0 the claim is the time in
  seconds, and two writers holding 0 claim different seconds, so `mkdir` alone keeps neither out:
  a claim of 0 must also be the only name. One that finds another name below it — another writer's
  claim of 0, or a first raise, which may already have landed — is stale and stays, being the
  highest name: it counts as one raise more, never as a revision lost. A stale call refuses with
  the failure code `stale-revision`, having written nothing; two writers holding one revision may
  both be refused, never both land.
  `<E>` is the caller's `--revision`, or the revision the command reads itself before it reads the
  queue, so a person in a terminal types no number and two of their commands still cannot
  overwrite each other.
- **The new file is built before the claim, moved into place right after it, and the revision is
  raised again (`jig_record_changed`).** The claim raises the revision before the write lands, the
  one exception to conventions/json-output.md's rule against that; a read that took the claimed
  revision with the old queue would otherwise never read again. A queue write therefore raises the
  revision by two.
- **Two failure codes are added** (schemas/json.md): `stale-revision`, and `not-found` for a
  reference that names no task or epic of this clone, or an item or dependency the queue does not
  hold. Everything else is `usage`, `not-initialised` or `failed`.
- **`remove` takes the item and what it waits for out; what waits for it stays**: a dependency is a
  relation between tasks, not a place in the queue.

## Alternatives

- **A `mkdir` lock around read, change and write.** It would close the window below, but a lock
  needs a stale rule (pid, ttl), waiting for it is a `sleep` loop, and a writer killed inside it
  blocks every other until the ttl — the reasons the revision ADR rejected it.
- **A separate claim directory for queue writes** (`queue.claims/<E>`), to avoid raising the
  revision before the write lands. The same window, a second directory to clear, and against the
  revision ADR's own prescription.
- **Compare without claiming** (read the revision, compare, move): two writers holding one revision
  both pass.
- **The file as JSON or YAML.** Without `jq` only a line format is read and written reliably; the
  YAML reader in `config.sh` has no lists of records.
- **`.ai/queue` beside the runtime directory.** Every installed project would need a new
  `.gitignore` line, and `upgrade` does not edit `.gitignore`.
- **Fields in each task's `state`, or a file under git** — rejected by the spec (scattered order and
  lost moves; a drag as a commit).
- **`--revision` required.** A person would have to read JSON before every change.
- **Separate `add`, `priority` and `reorder` commands.** One more thing a consumer must know, for
  what `set` and `move` already do.

## Consequences

- Jig UI drags an item with one `move … --revision <n> --json` and shows `stale-revision` as a
  conflict; a refused write changed nothing, so it reads again and lets the person decide again.
- Any Jig write in the clone — a `task set` from an agent — between a consumer's read and its write
  refuses that write, though the queue did not change. It is the safe side: read and retry.
- **Accepted risk:** a writer stopped (SIGSTOP, a machine under load) exactly between its claim and
  its `mv`, while another consumer reads the claimed revision, builds its own write and claims the
  next one, can have its write overwritten. The window is one glob between `mkdir` and `mv`, the new
  file being built before the claim; it is of the class the revision ADR accepts for sixteen raises
  between a `mkdir` and its next read.
- **Accepted: a task's level and an epic's existence are judged from the writing checkout's
  `.ai/specs`.** A spec or `Epic:` line present on one branch only makes the same write place the
  item on another level (at its end) depending on which worktree runs it, and a `move` against an
  item stored on the other level is then refused `usage`. Specs reach every checkout once their
  branch is merged, as `task start` already assumes; reading the main checkout's roadmap instead
  would judge by a branch the writer may not have.
- A file edited by hand raises nothing, as for every record; the next write rewrites it in the
  canonical order and keeps its lines of unknown kinds.
- The readers that follow in the spec — the queue in `jig status`, `jig context` and as JSON, the
  pause requests — read this file through `queue.sh`'s parser and add their own line kinds; a new
  incompatible field raises the format version.
