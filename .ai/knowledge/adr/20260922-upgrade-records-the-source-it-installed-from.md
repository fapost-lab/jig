---
id: adr-20260922-upgrade-records-the-source-it-installed-from
type: adr
status: accepted
date: 2026-09-22
domains:
  - install
paths:
  - scripts/lib/upgrade.sh
  - scripts/lib/manifest.sh
summary: Why an upgrade that placed nothing leaves .ai/manifest untouched, and why the recorded source may always be written back.
reviewed_at: 2026-09-22
---
# `jig upgrade` records a source only when it installed something from it

## Context

`.ai/manifest`'s header says where a project's framework came from: `jig.source`, the
version that checkout declared, and the day it was written. `jig upgrade` rewrote that
header at the end of every run that was not a dry run, whatever the run had done.

On 2026-09-22 that turned a refused upgrade into a silent relocation. The global jig had
been moved to a release checkout at `~/.local/share/jig`; in a link-mode project installed
from its own checkout (`jig.source: .`) a `jig upgrade --from ~/.local/share/jig` reported
28 `keep-conflict` lines and not one `link` — every symlink already pointed at the recorded
source, and ADR-0003 forbids overwriting what is already there. Nothing was placed, and the
only change in the working tree was `jig.source: .` → `/Users/.../.local/share/jig`. The
next plain `jig upgrade` would have read from a checkout no file of that project came from,
and the person had just watched the attempt be rejected in full.

Copy mode had the same fork: a run in which every path ends `keep-modified` or
`keep-conflict` installs nothing and still wrote the other checkout's path and version into
the header, over files that were none of its doing.

The run said nothing about any of this. The only summary was link mode's
`nothing to link (N already linked)`, printed only when there was no conflict either.

## Decision

- An upgrade rewrites `.ai/manifest` only when it applied something to the project —
  installed, replaced, linked or deleted at least one framework-owned path — **or** when the
  source it would record is the one the manifest already records. Otherwise the file is left
  untouched, `jig.source` and `jig.version` included.
- The recorded source is always writable, applied or not: there the header only restates
  where the project already comes from, and `jig.version` has to keep following that
  checkout. In link mode the project runs the source's scripts directly, so a source pulled
  to a new version changes the project's version without a single link being created; were
  the header frozen there, `jig status` would report a version mismatch no `jig upgrade`
  could ever clear.
- Moving a project onto another checkout stays what it was: an upgrade that really does
  place files from it records it. What no longer happens is a move nobody performed.
- Sources are compared as physical paths (`pwd -P`), the way `manifest_write_entries`
  already compares the source with the project: one checkout reached through a symlinked
  parent is not two.
- Every run ends in one summary line in both modes —
  `jig upgrade: <placed> placed, <kept> kept[, <removed> removed], <conflicts> conflict(s); manifest <updated|unchanged>`
  — and a run that kept the recorded source says so and names `jig init --from <dir>`, the
  command whose job is choosing where a project's framework comes from.

## Alternatives

- **Refuse when `--from` names a checkout other than the recorded one**, pointing at
  `jig init`. Rejected: upgrading from a *different* checkout is the normal way a project
  moves forward — a new release lives at a new path — and the test suite exercises exactly
  that. The refusal would have banned the working case to stop the empty one.
- **Never let `upgrade` change `jig.source` at all; only `init` chooses it.** A clean rule,
  but it takes away the one command that can move a copy-mode project onto a new checkout
  while replacing the files it has not edited. `init` copies conflict-aware and would leave
  every unmodified file behind as a conflict, which is strictly worse at the job.
- **Write nothing at all when nothing was applied**, the recorded source included. Rejected
  for the link-mode version freeze above.
- **A flag (`--set-source`, `--relocate`) to move the source deliberately.** Rejected for
  now: it is new surface for a case the rule above already covers correctly, and a flag
  cannot be un-added.
- **Leave it and document it.** Rejected: a manifest that names a source the project never
  took a file from is not a documentation problem; the next upgrade acts on it.

## Consequences

- A refused upgrade leaves the project exactly as it was, and says so.
- `installed_at` no longer moves on a run that did nothing from another checkout, so a
  no-op upgrade stops producing a diff to review.
- Link mode's `link mode: nothing to link (N already linked)` line is gone; the summary
  carries the same count as `kept`. `upgrade_pending` no longer has to filter it out.
- A copy-mode project whose recorded source checkout was deleted and whose files are all
  current keeps pointing at the dead path: nothing was placed from the new one, so nothing
  is recorded. `jig init --from <dir>`, which the run names, moves it.
- The decision table now keeps a tally as it runs. A new action row has to add itself to it,
  or the summary quietly under-reports.
