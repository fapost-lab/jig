---
id: adr-20261015-the-clone-revision-is-a-renamed-file
type: adr
status: accepted
date: 2026-10-15
domains:
  - task
  - scripts
paths:
  - scripts/lib/common.sh
  - scripts/lib/json.sh
  - schemas/json.md
summary: Why the clone revision is the name of one file in the main checkout's runtime, raised by an atomic rename after every Jig write through jig_record_changed, read by --json before the data, seeded with the time.
---
# The clone's revision is the name of one file, raised by renaming it after every Jig write

## Context

The contract-extensions spec settled with the maintainer (2026-10-14) that every `--json` read
reports one revision of the clone: a counter raised by every Jig write — task state, artifacts,
specs, and the queue once it exists — which a consumer compares between reads and, from
`contract-queue` on, sends back with a write so that Jig can refuse one made against a stale
state. Accepted risk: a file edited by hand does not raise it.
adr-20261015-a-read-is-one-json-envelope reported `null` until the counter existed.

What was left open, and is decided here: where the counter lives so that every worktree of a clone
shares it; how two writers raise it at once without losing an increment, with no new dependency
(ADR-0002) and in Git Bash as well (ADR-0037); which writes raise it and how a forgotten writer is
caught; and when a read takes it relative to its data.

## Decision

- **One counter per clone, in the main checkout**: `.ai/runtime/revision/` under
  `jig_config_clone_root`, the third user of ADR-0008's per-clone runtime exception (after the
  status page and the verify run record). Every worktree raises and reads the same one; a worktree
  keeps none of its own.
- **The value is the name of the one file in that directory**, and raising it is
  `mv <n> <n+1>`. rename is atomic on POSIX and in Git Bash, so it is a compare-and-swap: of two
  writers that saw `<n>`, one renames it and the other finds the source gone, scans again and raises
  `<n+1>`. No increment is lost to writers raising one counter, and there is no lock — nothing to
  go stale, wait for or break. A reader lists names with the shell's glob and never opens the file.
  A listing taken during a rename may show no name; reader and writer scan three times before they
  believe that.
- **The first write seeds the counter with the time in seconds**, not 1, with `set -C` so that two
  first writers make one file. A counter lost with `.ai/runtime` starts again above the value a
  consumer still holds, as long as there were fewer writes than seconds since the seed. Two names at
  once (two first writes in different seconds) read as the higher one. The one window that can lose
  an increment is there: a raise of `<n>` that lands on a `<n+1>` a racing first writer seeded a
  second later replaces it (rename overwrites). It needs two first writes and a raise in the same
  second or two, once in a clone's life; accepted rather than paid for with a lock.
- **A read before any write reports `0`** — a fact (Jig has written nothing in this clone), not
  "unknown", so never `null`.
- **Every writer calls one funnel right after its write lands**: `jig_record_changed` (common.sh)
  raises the revision now and marks the status page for its one redraw at the command's end
  (`jig_status_page_dirty`). Per write, not once per command: a write inside `$(...)`, or in a
  command that dies after it, is still counted. The writers: the eight state, journal, findings
  and receipt writers of `task.sh` plus `task.md`'s; every `mv` of a spec's files in `spec.sh`
  (new, epic, done, close, remove, link, unlink); `knowledge new` and every frontmatter write
  (`_fm_replace`, except on the file `knowledge new` is still building); `jig config set|unset`
  (`_config_set`, `_config_unset`), because a setting can change what a read reports — the git
  level and unattended mode decide the legal actions a read will list; and the pull request and CI
  cache (`forgecache_write`), which `task list --json` reads; and the knowledge counts a full
  `jig status` saves (`_status_counts_save`), which `jig status --json` reports — raised with
  `jig_revision_bump` (the page's own redraw must not mark the page again), and only when a count
  changed, not for the `at:` every redraw moves. `config.yaml` edited by hand
  (where `git.base_branch`, which `base_branch` falls back to, lives) is the accepted risk. A housekeeping run, which appends its log line by line, raises it once when it
  ends (`jig_on_exit`), registered before its first write; a dry run does not.
- **What does not raise it** is what no read reports: the context cache and ledger, the checkout
  record, the status page, the verify run record, notify's records (the Telegram settings).
- **Accepted risk, wider than hand edits**: a tracked file changed by git raises nothing, whoever
  ran it — a person's `pull` or `checkout`, but also Jig's own git steps: the checkout and
  fast-forward of the base after a ship merges (`jig_ship_leave`), a spec's branch switch,
  `upgrade` and `init` placing files. Those change specs and knowledge as git sees them, not as
  records Jig writes; a consumer that must see them watches the files.
- **A `--json` read takes the revision before the producer runs.** Data is then never older than
  the revision reported: a write landing during the read raises the counter past it, and the next
  read sees that. Taken after, a revision could cover a write the data missed, forever.
- **A counter that cannot be raised warns and the command goes on**: the write it follows has
  landed, and failing then would misreport it.
- **The test that no writer is forgotten is static and behavioural.** `tests/json.t.sh` lists
  every function in `config.sh`, `forgecache.sh`, `task.sh`, `spec.sh`, `knowledge.sh` and `frontmatter.sh` that moves a file
  into place without reaching `jig_record_changed`, transitively, and only two named exceptions
  may appear; a planted writer proves the guard sees one. Every record Jig writes is a temporary
  file and an `mv` (conventions/shell.md), which is why `mv` is where a writer shows. A second test
  runs each writing command in a fixture and requires the revision to rise, and each read to leave
  it.

## Alternatives

- **A number inside a file, under a `mkdir` lock** (the housekeeping and verify idiom). A lock
  needs a stale rule (pid, mtime, ttl), waiting for it means a retry loop with `sleep`, and a writer
  killed inside it blocks the rest until the ttl. The rename gives the same guarantee with none of
  those failure modes.
- **Append one byte per write; the revision is the file's size.** Lock-free on POSIX, but
  O_APPEND is emulated as seek-and-write under Git Bash, where concurrent writers overwrite each
  other; and the file grows for ever.
- **Raise once when the command exits** (`jig_on_exit`). The window to lose a write is then the
  whole command (SIGKILL under load is real here), and a write made inside `$(...)` registers in
  a subshell whose exit trap bash 3.2 skips. Kept only for housekeeping, whose many log lines are
  one change.
- **Start at 1.** After `.ai/runtime` is lost a value a consumer holds would come round again, and
  a stale write carrying it would pass contract-queue's check.
- **`null` before the first write.** Says "unknown" where the answer is known.
- **A revision per task and one for the queue.** Rejected by the spec: a consumer would track many.

## Consequences

- A new writer of a record calls `jig_record_changed` after its `mv`, or `tests/json.t.sh`
  fails; a new kind of write that is not an `mv` (an append) has to be covered by hand, as
  housekeeping's is.
- Each write costs one `mv` process and a glob; a command writes a handful of times.
- A file edited by hand, or changed by git — a person's pull or checkout, or Jig's own branch
  switches and post-merge fast-forward — raises nothing. A consumer that needs to see those re-reads
  on file change as well.
- An orphan name left by two racing first writes stays, harmless: the higher one is read and
  raised.
- contract-queue can build its stale-write check on the same rename: renaming exactly the
  revision a write carries succeeds only while the revision is still that one.
- The revision directory sits in `.ai/runtime/`, gitignored with the rest; `upgrade` and
  housekeeping never touch it.
