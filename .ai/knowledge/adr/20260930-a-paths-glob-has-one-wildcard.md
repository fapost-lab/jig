---
id: adr-20260930-a-paths-glob-has-one-wildcard
type: adr
status: accepted
date: 2026-09-30
domains:
  - knowledge
paths:
  - scripts/lib/common.sh
  - scripts/lib/knowledge.sh
summary: A frontmatter paths glob has exactly one wildcard, *; ?, [...] and a bare directory are literal or file-only, so the one matcher context.sh and knowledge.sh share never has two answers for the same glob.
reviewed_at: 2026-09-30
---
# A `paths` glob has exactly one wildcard, and a directory glob matches files, not the directory

## Context

`paths` globs used to be tested two different ways: `jig context` matched a candidate list
with a bash `case` pattern, and `jig knowledge` asked `find -path ... -quit` whether the
glob matched anything in the repository. Both went through the same `**`-to-`*` collapse,
but `case` is a full shell glob (it also treats `?` and `[...]` as wildcards) while `find
-path` walks the filesystem (it also matches a *directory entry*, and it does not consult
`.gitignore`). Nothing in schemas/frontmatter.md said `?` or `[...]` were meaningful, so the
`case` matcher's extra behaviour was accidental, inherited from bash rather than designed.

Replacing `find` with a shared, in-memory matcher (ADR-20260930-resolve-guard-share-a-required-rows-cache's
sibling change, `jig_repo_files`/`jig_glob_matches_repo`, knowledge-costs-one-walk) meant
building a second, ERE-based test alongside the `case` one — and a first pass built it by
independently re-escaping `?`/`[`/`]`, which made it disagree with `case` on exactly the
characters `case` had always treated as wildcards. Two matchers had become one, and a new
disagreement over the same class of glob appeared inside it.

## Decision

`*` is the only wildcard a `paths` glob has (`**` collapses to it). `\`, `?`, `[` and `]`
are escaped to literal characters before any matching happens (`jig_glob_pattern`,
common.sh), so both the `case` matcher and the ERE matcher treat a glob containing one of
them the same way: as a literal character to match, not a wildcard, because
schemas/frontmatter.md never promised one. Brace groups (`{a,b}`) remain unsupported by
either matcher, unchanged from before.

A glob ending in `/` names a directory and is read as "any file under here, including
directly under it" — equivalent to appending `*` — never as a match against the directory
entry itself. `jig_repo_files` (the shared file list both matchers test against, built from
`git ls-files` plus untracked-but-not-ignored files) never contains a directory, only
files, so an empty directory can no longer "match" the way `find` used to report one.

## Alternatives

- **Give the ERE matcher full `?`/`[...]` support, matching `case`'s native behaviour.**
  Rejected: more matching logic to keep in sync between two independent implementations,
  for syntax the grammar never documented and no shipped document uses.
- **Leave `?`/`[...]` as wildcards in `case` and escape them only in the ERE builder.**
  Rejected: this is the bug the review caught — it is a second, different disagreement
  between the two matchers, replacing the one this change removed.
- **Keep `find`'s directory-entry match** (an empty directory "matches" its own glob).
  Rejected: a `paths` glob describes code; a directory with nothing in it describes
  nothing yet, and no test in this project relied on the old behaviour.

## Consequences

A knowledge document whose `paths` glob happens to contain a literal `?`, `[` or `]` (none
does today) now matches that literal character rather than acting as a wildcard — checked
against every document already in this repository, none are affected. Brace-glob support,
if ever added, must be designed once and implemented in `jig_glob_pattern` for both
matchers together, not in one and then the other.
