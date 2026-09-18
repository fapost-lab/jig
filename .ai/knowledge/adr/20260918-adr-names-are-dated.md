---
id: adr-20260918-adr-names-are-dated
type: adr
status: accepted
date: 2026-09-18
domains:
  - knowledge
paths:
  - scripts/lib/knowledge.sh
  - templates/knowledge/adr.md
summary: Why a new ADR is named YYYYMMDD-<slug> by its day instead of a running number, and why the numbered ones stay.
---
# An ADR is named by the day it was written, not by a running number

## Context

`jig knowledge new adr` gave each record the highest existing number plus one. The number is taken on
the branch, so two branches cut from the same `main` take the same one, and nothing notices until both
reach one tree: the second pull request fails `knowledge check` with `duplicate ADR number` after the
first has merged. On 2026-09-16 this happened twice in a day with three parallel branches (0037 and
0038 were taken twice), and the fix was manual: rename the file, the id, the heading and every
citation. A team with more parallel work hits it constantly.

## Decision

- A new ADR is `adr/YYYYMMDD-<slug>.md` with id `adr-YYYYMMDD-<slug>`. The day is the one written into
  its `date:`, from the same clock, and `knowledge check` fails when the two differ, or when the name
  does not start with a real month and day.
- Two branches collide only by writing the same slug on the same day; that is the same path, so git
  reports an add/add conflict at merge instead of letting a duplicate through. The same slug on
  different days is two records with two ids.
- A new record is cited by its id (`adr-20260918-adr-names-are-dated`), the form `jig context --ids`
  and `supersedes` take. There is no short form: any short form needs a unique counter again.
- The 41 numbered records keep their names and their `ADR-NNNN` citations. `NNNN-<slug>.md` stays
  valid for good, here and in installed projects, with the duplicate-number check among them; jig no
  longer creates one. `ls` lists the numbered ones first and the dated ones after, which is also the
  order they were written in.
- A team's own decision records linked through stubs (ADR-0036) keep their own numbering; this is
  about `.ai/knowledge/adr/` only.

## Alternatives

- **Rename the 41 numbered records** — 693 citations in 113 files, plus commit messages, pull requests
  and installed projects that cannot be rewritten; it buys uniform names.
- **Date and time, `YYYYMMDD-HHMM-<slug>`** — longer, and adds nothing the slug does not already tell
  apart.
- **Slug only, `adr/<slug>.md`** — loses the order in the name and in `ls`; the date costs eight
  characters.
- **Number assigned by CI at merge, or a `renumber` command** — bot commits on `main`, or citations in
  open branches that break silently; both treat the symptom.
- **Hash or ULID** — unreadable.
- **The scheme as a project setting** — a second code path for a project that wants collisions; a
  team's own records already follow the team's convention.

## Consequences

- Parallel branches no longer renumber records at merge.
- Citations of new records are longer than `ADR-0042`.
- A replacement for an ADR rejected the same day needs another slug: the same slug is the same path,
  and the rejected record keeps it (ADR-0018, ADR-0019).
- Rolling back means renaming every dated record to a number, with its citations — cheaper the sooner.
