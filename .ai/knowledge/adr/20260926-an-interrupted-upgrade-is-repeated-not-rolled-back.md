---
id: adr-20260926-an-interrupted-upgrade-is-repeated-not-rolled-back
type: adr
status: accepted
date: 2026-09-26
domains:
  - install
paths:
  - scripts/lib/upgrade.sh
  - scripts/lib/common.sh
summary: "An interrupted upgrade is finished by running it again: a file already holding the staged bytes is placed, both sides of every hash comparison share one hash space, and a real run names what it left behind."
reviewed_at: 2026-09-26
---
# An interrupted `jig upgrade` is finished by repeating it, never by rolling it back

## Context

`jig upgrade` places framework-owned files one at a time and writes `.ai/manifest`
once, at the end. An interruption between the first placement and that write —
Ctrl-C, a closed laptop, a killed process, a destination that cannot be written —
leaves new bytes on disk against the hash the manifest still records.

The decision table compared the recorded hash with the file and the file with the
staged source, but never the file with the staged source in the case that decides
this: a file whose hash differs from the manifest was read as one the user had
edited. That reading is wrong by the domain's own vocabulary — `keep-modified` is
defined as the outcome "for a file the user edited" — and it does not expire. Every
later run repeated it, `jig status` reported drift that nobody had caused, and the
install never finished. For a path the new version installs for the first time the
same interruption produced `keep-conflict`, which is worse: the path never became
framework-owned, so it was never updated again either.

Two more findings turned out to be the same defect wearing other clothes.

`git hash-object` reads two things from wherever it runs, and both decide whether
identical bytes hash equal: the repository's object format, and its clean filters.
The project was hashed inside the repository and the staging tree in `$TMPDIR`
outside it. In a repository whose object names are SHA-256 every framework path
therefore compared unequal: the first run replaced all 97 of them and wrote SHA-1
hashes into a SHA-256 manifest, and from the second run on the entire install read
as modified and stopped updating. A `filter=` driver over a framework path did the
same to that path. Neither needed an interruption.

And the run could not see its own leftovers. A live case on 2026-09-25 printed
"55 placed, 49 kept, 2 removed; manifest updated" and left `.ai/templates/AGENTS.md`
unplaced; it surfaced a day later in `jig doctor` as "1 pending item(s) although the
version is the same". The cause was not an interruption at all: an upgrade is carried
out by the code of the version being replaced, and 0.15.1 does not stage that
template — the line that copies it arrived in 0.16.0 — while the manifest did record
it, so the old code deleted it.

The audience makes all of this worse than untidy. Someone who needs Jig cannot tell
"the upgrade did not arrive" from "this is how it is", and the product quietly stops
updating.

## Decision

**A file that already holds exactly the bytes the run would install is placed,
whoever placed it.** The decision table asks that first, before any other row, and
reports `already-placed`; the manifest records the staged hash. The content is the
predicate. Nothing records progress, because a record can be lost, go stale or arrive
from somebody else's clone, and the bytes cannot. Repeating the command is what
finishes an interrupted run, and repeating it is always safe.

**The same question is asked of the marked section of `AGENTS.md`**, whose record
lives in the manifest header and so has the identical hole. ADR-20260924's invariants
are untouched: a record must already exist, which means a human consented to jig
owning that region, and not a byte of the text changes — only the hash the manifest
remembers of it.

**A reconciliation counts as applied.** It is the one outcome that changes the
manifest body while writing no file, so
`adr-20260922-upgrade-records-the-source-it-installed-from`'s "applied nothing, so
do not name this source" must not swallow it: a repeat of a run interrupted after its
last placement would otherwise find everything already placed, write nothing, and
report "manifest unchanged" — the broken state reached by the fix itself.

**Both sides of a hash comparison are computed in one hash space, filter-free.**
`jig_hash` and `jig_hash_list` run `git hash-object --no-filters` with the project's
own git directory, whatever directory the files being hashed live in. `--no-filters`
answers the filters and not the object format, so both halves are needed; an empty
`GIT_DIR` is fatal to git rather than meaning "unset", so a project outside any
repository keeps hashing as it always did.

**At the end of a real run, upgrade asks the install it has just made whether
anything is still not installed, and names it.** The predicate is not a new one: it
is `upgrade_pending`, the same question `jig doctor` asks. It is asked as a
subprocess of the project's own dispatcher, and that is load-bearing rather than
stylistic — the code that ran the upgrade is the old code, whose stage is satisfied
by construction, so asking in-process would stay silent in exactly the case the check
exists for. Never on a dry run: `status`, `verify` and `doctor` each run one on every
invocation (ADR-0017), and it would double their cost and recurse. It never fails the
upgrade it follows; a check that cannot answer says so.

## Alternatives

**Make the upgrade atomic — all or nothing.** Rejected, and this was the question put
to a human rather than settled here. A whole-tree swap is not available: after an
upgrade the tree is a merge of framework files and files the user changed
(`keep-modified`, `keep-conflict`, `keep-outside`), so swapping a directory would
overwrite exactly what `RULES.md` forbids overwriting (ADR-0003). What remains is
per-file backup and rollback, which buys one guarantee — the install is never mixed
from two versions — and costs four things: a failure during the rollback, from which
nothing recovers; a rollback that produces its own mixed state, old files under a new
process; a record of what to undo if it is to survive `kill -9`, which is the journal
below; and movement of files that `RULES.md` enumerates deletion sites for one by one,
so that paragraph would have to be reopened. It also fixes neither the hash
divergence nor the old-code case, which are orthogonal. The window it closes stays
open here: between the first placement and the last, the install holds files of two
versions. This decision does not remove that window, it makes it recoverable and
visible.

**Make the upgrade resumable with a progress journal.** Rejected as buying nothing
over the content comparison, at a real price. ADR-0017 has `status`, `verify` and
`doctor` reading pending state from `upgrade --dry-run` on every invocation, so the
journal would have to be readable without being advanced, and must not turn an
unfinished run into a permanent `pending` — which is how `verify` would come to refuse
everything for ever. `conventions/required-records.md` asks a record to be computed or
refutable by the machine; `>>` is atomic only up to `PIPE_BUF`, so each entry would be
a temporary file and a rename, a process per file, against the batching rule. A
journal answers "did I place this file", and the file answers that already.

**The precedent that decided it.** `adr-20260924-a-worktree-carries-what-git-does-not`
faced the same choice for a different tree and chose staging-and-rename plus an
idempotent retry that "reads an existing destination as already carried", with
"nothing rolled back, because the tree and the branch are exactly what a retry needs".
This is that shape applied to the install.

**Leave `keep-conflict` alone for an adopted path.** Rejected. The file is identical
to the one this version ships, so adopting it changes not a byte; refusing to adopt
means the path is never maintained again, which is the defect and not a safeguard.

**Ask `upgrade_pending` in this process instead of a subprocess.** Rejected: it is the
old version's decision table, satisfied by construction. Removing the subprocess while
keeping the check leaves the test for the live case red, which is how this is held in
place.

## Consequences

`jig upgrade` is safe to interrupt and safe to repeat, and a project whose manifest was
already poisoned — by an interruption, by SHA-256 object names or by a clean filter —
heals on the first run of the fixed code, with no manual reconciliation: measured on a
poisoned install, 97 files reported modified before and none after.

**The run that installs the fix is not that run**, and a SHA-256 project sees the gap. That
upgrade is carried out by the old code, which writes SHA-1 hashes into a SHA-256 manifest
one last time; the fixed code is on disk from that moment, so the next `jig status` hashes
in the project's space and reports every framework file as modified — measured: `97 placed`
by the old code, then `drift: 97 modified`, then `drift: 0 modified` after one more
`jig upgrade`. Nothing is wrong with the files and `jig verify` is not blocked, which gates
on pending rather than drift, but the run cannot warn about it either: the self-check it
would warn from is the new code's, and the run belongs to the old. It is a transitional
false positive with one cure, `jig upgrade` again, and it is on
`docs/troubleshooting.mdx` because that is where somebody who sees it will look. A project
with clean filters does not see it: the old code replaces exactly those paths on its way
out and records them unfiltered, so the manifest is already consistent.

`already-placed` joins the decision table's vocabulary. It counts in `kept`, like every
other outcome that writes no file, and stays out of `upgrade_pending`'s verbs because
the file is current. It is reported only when the manifest did not already agree, so an
ordinary run stays as quiet as it was. A new outcome row must add itself to the tally
that decides whether the manifest is written — `reconciled_count` — or a repeat can
write nothing and say so.

An upgrade now costs one extra dry run: 0.78 s against 0.88 s for the run itself on 97
files, for a command that runs once per release. A dry run costs nothing extra, which
is what keeps `status`, `verify` and `doctor` where they were.

Hashing is no longer whatever `git hash-object` happens to do in the current directory.
Any future reader that compares a file to a manifest hash goes through `jig_hash` or
`jig_hash_list`, and a third one would have to repeat both halves of the rule.
`jig_section_hash` is unaffected: it hashes through stdin, where no path attributes
apply, and both sides of its comparison are computed in the same process.
