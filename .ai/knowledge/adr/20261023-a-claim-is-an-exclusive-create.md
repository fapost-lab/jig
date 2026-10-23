---
id: adr-20261023-a-claim-is-an-exclusive-create
type: adr
status: accepted
date: 2026-10-23
domains:
  - task
  - install
paths:
  - scripts/lib/common.sh
  - scripts/lib/verify.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/task.sh
  - scripts/lib/spec.sh
summary: Why every lock, counter and id claim in Jig is a file created with O_EXCL by bash's noclobber (jig_claim_file) instead of mkdir, which uutils (Ubuntu 25.10+) lets two makers both win.
---
# A claim is a file created exclusively, never a mkdir

## Context

Jig's locks and counters were claimed with a plain `mkdir`: the revision counter
(adr-20261016-the-clone-revision-is-a-claimed-name), the queue's claim on a revision
(adr-20261019-the-queue-is-one-file-written-against-a-revision), the record that keeps one test run
per clone (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass), the housekeeping lock,
and the ids of `jig task new` and `jig spec new`. Each relied on `mkdir(2)` failing with EEXIST for
the second of two makers, and those ADRs call `mkdir` the one atomic primitive available on POSIX
and in Git Bash alike.

That stopped being true for the `mkdir` a script reaches. Ubuntu 25.10 and later ship coreutils
from uutils, and its `mkdir` returns success to both of two processes making one directory: 110
races in 300 on `ubuntu:26.04` (uutils 0.10.0), measured on 2026-10-23. GitHub's `ubuntu-latest`
moved to 26.04 that morning, and
`json::test_json_revision_loses_no_increment_to_concurrent_writers` failed on every Linux run since,
main included: the counter lost increments, the locks excluded nobody. The fault is the tool, not
the system call, and a script cannot reach the system call except through a tool — or through bash.

## Decision

**A claim is the creation of a file with O_EXCL, made by bash itself: `jig_claim_file <path>
[<content>]`, which runs `( set -C; : > <path> )` — noclobber — and exits 0 only for the process
that created the file.** No external tool decides it, so what coreutils a system ships does not
matter; bash 3.2 has noclobber, and Git Bash maps O_EXCL to CREATE_NEW.

- **The revision** claims `<n+1>` as a file. A reader takes the highest numeric name, file or
  directory, so a counter an earlier version left as directories reads and clears as it is; a
  stale claim is withdrawn with `rm -f` of the one name that call created.
- **The `verify` record and the housekeeping lock** keep `busy/` as a container, made with
  `mkdir -p`, and claim `busy/run`; the loser leaves `busy/` alone. Giving the record back is
  unchanged — remove `run`, then `rmdir` — so the shape RULES.md and ADR-0035 allow stands.
- **`jig task new` and `jig spec new`** keep their directory and its existence check, and claim the
  id with the first file, `state` or `spec.md`, created empty and then replaced whole by renaming
  the finished temporary over it — so no reader sees a partial `state` (ADR-0008). The second maker
  is refused as "already exists" and removes only its own temporary files.
- `install.sh` keeps its `mkdir`: one install runs at a time, and it only learns whether this run
  made the directory; what it deletes on failure is still bounded by `rmdir`.

## Alternatives

- **GNU `mkdir` by name** (`gnumkdir` on Ubuntu 26.04). Not on every system, and the name is a
  distribution's choice.
- **`ln -s` as the claim.** Another coreutils tool, open to the same replacement.
- **Pin CI to `ubuntu-24.04`.** Done for one day (#304) to unblock main; as the fix it would hide a
  fault every user on Ubuntu 25.10 and later has.

## Consequences

- Locks and counters exclude a second maker on every system bash runs on.
- Tests put a `mkdir` first on `PATH` that succeeds although the directory exists — uutils at its
  worst — and the revision, the `verify` record, the housekeeping lock and `task new` each still
  exclude the second maker; each test fails on the old claim.
- `mkdir` without `-p` is still how a directory is made, and its failure still means "there";
  it no longer decides who holds anything.
