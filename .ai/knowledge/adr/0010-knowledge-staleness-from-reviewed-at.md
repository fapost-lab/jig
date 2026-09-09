---
id: adr-0010-knowledge-staleness-from-reviewed-at
type: adr
status: accepted
date: 2026-09-08
domains:
  - knowledge
  - consolidation
paths:
  - scripts/lib/knowledge.sh
  - schemas/frontmatter.md
  - "skills/jig-consolidate/**"
reviewed_at: 2026-09-09
---
# ADR-0010: Knowledge staleness is a `reviewed_at` date compared against git history

## Context

ADR-0004 made knowledge findable by matching a document's `paths` against the files a
task touches, and promised in its consequences that "stale knowledge becomes detectable
mechanically". Only the weakest half of that was built: `knowledge check` warns about a
glob that matches nothing.

That misses the case that actually costs the project. A document goes wrong not when its
globs stop resolving, but when the code under those globs moves on and the document
quietly keeps describing the old shape. Nothing in the repository records when a document
last agreed with the code, so nothing can tell a reconciled document from an abandoned
one.

## Decision

Knowledge documents carry an optional `reviewed_at: YYYY-MM-DD` field recording when the
document was last reconciled with the code it describes. `jig knowledge stale` reports:

| Verdict | Condition |
|---|---|
| `stale` | a file matching the document's `paths` has a commit newer than `reviewed_at` |
| `unreviewed` | the document has `paths` but no `reviewed_at` |
| `orphaned` | it has `reviewed_at`, and every one of its `paths` globs now matches nothing |
| `planned` | it has no `reviewed_at`, and its globs match nothing — the code is not written yet |

`reviewed_at` also separates rot from foresight, with no extra field: a document stamped
once did match code, so empty globs mean the code moved away; a document never stamped
never matched, so empty globs mean it is ahead of the code. The T3 route decides at the
gate and implements afterwards (ADR-0009), which makes forward-looking documents normal;
reporting them as rot would make the report noise in the framework's own workflow.
`--strict` fails on `stale`, `unreviewed` and `orphaned`, never on `planned`.

`jig knowledge reviewed <id>` stamps the field. `jig-consolidate` stamps every document
it touches, which is the only thing that keeps the field honest — an unmaintained
`reviewed_at` degrades to `unreviewed`, which is a true statement, not a wrong one.

Documents whose status is `superseded`, `deprecated` or `rejected` are skipped: they
describe the past on purpose.

The report is not a gate. `jig knowledge stale` exits 0 unless `--strict` is given, so
`verify` stays a correctness check and does not begin failing on knowledge that is merely
aging.

## Alternatives

- **Derive staleness with no new field** — only `paths` globs that resolve to nothing,
  plus broken links. Rejected: it is exactly the half that already exists, and it cannot
  see the expensive case, where the globs still resolve and the prose no longer matches
  what they resolve to.
- **`reviewed_commit: <sha>`**, with `git diff <sha>..HEAD -- <paths>` for precision.
  Rejected: a sha does not survive a rebase, a squash merge or a shallow clone, and it
  reads as noise in a diff. A date survives all three, and one day of granularity is
  enough for a signal whose only consequence is "an agent should look at this".
- **A generated index of document-to-file checksums under `.ai/runtime/`** — precise and
  invisible in diffs. Rejected: it is state that lives outside the document it describes,
  so a document copied, moved or merged between branches loses its freshness record,
  and the record cannot be reviewed in a pull request.
- **Fold the report into `knowledge check`**. Rejected: `check` validates structure and
  fails the build; staleness is a maintenance signal. Merging them makes every `verify`
  noisy and couples a report to a gate.

## Consequences

- Consolidation gains an obligation: stamp `reviewed_at` on every document it edits.
  A rule in `RULES.md` and a step in `jig-consolidate` carry it.
- Same-day granularity means a change committed after a review on the same date is not
  reported until the next commit touching those paths. Accepted deliberately: the
  alternative reports every document an agent just reviewed as stale.
- `--strict` fails on a project that has never stamped anything, because every document
  is `unreviewed`. That is the honest state of such a project; `--strict` is opt-in.
- The field is optional and additive. `knowledge check` validates its format when
  present, and documents without it stay valid.
