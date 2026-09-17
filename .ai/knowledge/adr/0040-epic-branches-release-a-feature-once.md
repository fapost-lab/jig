---
id: adr-0040-epic-branches-release-a-feature-once
type: adr
status: accepted
date: 2026-09-16
domains:
  - spec
  - task
  - housekeeping
paths:
  - scripts/lib/spec.sh
  - scripts/lib/task.sh
  - scripts/lib/housekeeping.sh
  - .github/workflows/ci.yml
  - .github/scripts/epic-pr-check.sh
  - schemas/spec.md
summary: Why a feature released once lives on an epic branch, how a spec declares, cuts and finishes it, and why phase workspaces wait for the epic to reach main.
reviewed_at: 2026-09-17
---
# ADR-0040: A feature released once lives on an epic branch until it is finished

## Context

A specification (ADR-0035) plans a feature in phases, and each phase is filed as its own task with
its own gate, review and pull request. With `main` the only base, that left two bad roads. A pull
request and a release per phase shipped half a feature: v0.5.0 shipped stubs nobody could accept
until a later phase. One task for every phase kept one release but lost per-phase gates and
knowledge decisions, and held weeks of work on one branch. Merging phases into `main` without a
version bump was rejected too: half a feature on `main` blocks a patch release from it, and any
unrelated pull request that raises the version ships it.

The specification `epic-branches` (removed when finished; in git history) settled the shape and records the failure hunt its
decisions answer. It stands on a base per task (ADR-0039).

## Decision

- **A spec released once, at the end, declares an epic** with one line in `roadmap.md`,
  `Epic: epic/<spec-id>`, after `Destination:`. A spec whose phases each ship on their own has no
  line and works against `main` as before. `jig-idea` writes the line when the spec is created, so
  it reaches `main` with the spec. The grammar is parsed once, by `jig_spec_epic` in `common.sh`;
  two disagreeing lines are refused.
- **`jig spec epic <id>`** writes the line when there is none and stops: the epic is cut from `main`
  and must carry the line, so the line has to be on `main` first. With the line on the freshest
  `main`, it creates `epic/<id>` there without a checkout; pushing is the human's step.
- **`jig task start` cuts a linked task from its spec's open epic.** It fetches the default branch
  and the epic from origin first — for every task, since a stale `main` is the same mistake — and
  refuses, instead of falling back to `main`, when the spec is not in the checkout, when the epic
  branch exists neither locally nor on origin, and when the epic is finished. It says which branch
  the task's pull request goes into. `Spec:` parsing moved to `common.sh` (`jig_spec_link`), and the
  freshest-ref rule with it (`jig_fresh_base_ref`), because `task.sh` and `spec.sh` never source each
  other.
- **A phase lands when its pull request is merged into the epic**: `needs-consolidation`, and the
  human closes it. Housekeeping keeps its workspace, flagged `base-unreleased`, until the task's work
  reaches `main` — a merged pull request from the epic into `main` on the forge, or the task's
  branch merged into `main` by ancestry. `housekeeping_decide` takes that answer as a seventh
  argument, `released`, and stays a pure function. Housekeeping never reads a spec: the task's
  `base_branch` is the link.
- **The epic is kept current by merging `main` into it directly**, never by rebasing. CI runs the
  tests on every push to `epic/**`. `jig status` prints one line per open epic with how many commits
  it is behind `main`.
- **An epic spec is edited only on its epic.** Elsewhere `jig spec list` shows
  `epic/<id> — progress is on the epic`, or `branch missing`.
- **Finishing is explicit.** On the epic, after the latest `main` was merged into it,
  `jig spec epic <id> --finish` rewrites the line to `Epic: epic/<id> — finished`, warning about
  unchecked items that are not `fog:`; it is committed with the version bump, and the human opens
  the pull request into `main`. `--reopen` takes it back when review needs a fix, which goes
  through ordinary tasks. The `epic-pr` CI job fails a pull request from `epic/*` into `main` whose
  `JIG_VERSION` is already released or whose roadmap line is not finished; the release check is
  shared with `release-tag.sh` in `.github/scripts/release-lib.sh`.

## Alternatives

- **Phase pull requests into `main` without a bump.** Rejected: see Context.
- **One task for the whole feature.** Rejected: one design, one knowledge decision and one
  `spec done` for every phase. This spec itself was built so, once, because the tooling did not
  exist yet.
- **Detect "epic merged" from git instead of the `— finished` mark.** Rejected: a freshly cut epic
  and a merged one are both ancestors of `main`; telling them apart needs first-parent history,
  which squash and fast-forward merges break. The mark is deterministic, CI enforces it, and it tells
  `spec list` the roadmap on `main` is current again.
- **The branch's existence as the signal.** Rejected: it cannot tell "no epic" from "never
  fetched", and a merged epic is never deleted here.
- **Syncing the epic through a `main` → epic pull request with a branch rule.** Rejected by the
  maintainer as too heavy. Accepted risk: a conflict in that merge is resolved without review; the
  push CI catches a broken result.
- **Rebasing the epic.** Rejected: it rewrites history under the task branches cut from it and
  defeats the reflog check of a branch's own work (ADR-0032).
- **Reading the epic's roadmap from `main` through `git show`.** Rejected as too complex; `main`
  shows where a feature is in progress, not how far it got.
- **Purging a closed phase on the usual `trash_ttl`.** Rejected: its records would be gone weeks
  before the epic is reviewed.

## Consequences

- An epic merged into `main` as a squash is invisible to ancestry: without a forge its phases'
  workspaces are kept until removed by hand. Merge epics with a merge commit.
- `task start` touches the network whenever the project has an origin; offline it warns and goes on
  with local refs.
- Knowledge written by phases lives only on the epic until the final merge, and parallel branches
  can pick the same ADR number; both are open questions of the specification.
- Maintenance lines (`release/<major>.x`) are the same foundation used another way, kept as a fog
  item in the specification.
- The `epic-pr` job and the push trigger are this repository's CI; projects adopting Jig get the
  commands and the housekeeping behaviour, not the CI.

> **Amendment (2026-09-17).** `jig spec epic <id> --finish` no longer writes `— finished`: after the same
> leftover gate as `jig spec close`, it removes the epic's spec, in the commit that raises the version,
> and the final pull request carries the removal to `main` (ADR-0035 as amended). `--reopen` restores the
> spec from git on the epic when review of that pull request needs a fix, so fixes remain ordinary tasks
> cut from the epic. The `epic-pr` check fails while any roadmap still names the branch in an `Epic:`
> line. A `— finished` line written by an earlier version is still parsed and refused, never read as "no
> epic", which would send a task to `main`.
