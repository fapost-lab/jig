---
id: adr-0025-ancestry-answers-landed-not-open
type: adr
status: accepted
date: 2026-09-10
domains:
  - housekeeping
  - task
paths:
  - scripts/lib/housekeeping.sh
summary: Why git ancestry may only answer merged-or-unknown, and why a task on the base branch is unknown.
reviewed_at: 2026-09-10
---
# ADR-0025: Git ancestry answers "did it land", never "is it open"

## Context

Housekeeping derives remote state per task in three tiers (SPEC §24.3): a forge API, then
git ancestry, then `unknown`. The policy table of §23 acts on four values —
`merged | open | closed | unknown` — and the spec's wording implies the ancestry tier
produces the same four.

It cannot. Git knows whether a commit landed on the base branch; it knows nothing about
pull requests. "Not an ancestor" is not evidence that a PR is open — it is equally
consistent with a branch nobody ever proposed.

Worse, the naive ancestry check has a tautology in it. When a task's `branch` field is the
base branch itself — trunk-based work, which is the default in this very repository —
`merge-base --is-ancestor main main` is trivially true, because a commit is its own
ancestor. The first implementation therefore reported `merged` for every trunk-based task.
Independent review caught it against the live repository: 17 of 19 workspaces carried
`branch: main`, 13 `consolidated` ones became purge candidates on the first real run, and
every active task was flagged `needs-consolidation`, which would have made housekeeping's
exit code 3 meaningless from the first day.

## Decision

- **The ancestry tier returns `merged` or `unknown`, never `open` or `closed`.** Only a
  forge can distinguish an open pull request from a closed one. Since §23 gives `open` and
  `unknown` the same action (preserve), this costs no behaviour and removes a class of
  claims the tier has no evidence for.
- **A task whose `branch` equals `git.base_branch` resolves to `unknown` before any git
  command runs.** Trunk-based work leaves no local evidence of having landed, so there is
  nothing to detect; only a forge can resolve those tasks.
- `merged` from ancestry requires positive evidence of one of three shapes: the tip is an
  ancestor of the base (fast-forward or merge commit); the patch-id of the branch's whole
  contribution matches a commit on the base (squash); or every commit is individually
  upstream per `git cherry` (rebase).

## Alternatives

- **Report `open` when the branch exists but has not landed.** Rejected: it is a guess
  dressed as a fact, and it would appear in the log's `via=` audit trail as if the tier
  had established something.
- **Special-case the base branch as `merged`** (the work is on the base branch, so it is
  "in"). Rejected: this is precisely the bug. `consolidated` + `merged` means purge, so
  the rule would delete the workspace of every finished trunk-based task the moment
  housekeeping first ran, with no PR and no branch to appeal to.
- **Compare commit SHAs instead of branch names** to detect the tautology. Rejected: after
  a fast-forward merge the base and the merged branch point at the same commit, so SHA
  equality would reclassify a genuinely merged branch as undetectable.

## Consequences

- On a trunk-based project with no forge, housekeeping purges nothing. That is the honest
  answer — there is no evidence to act on — and it is a strong argument for giving each
  task its own branch (see the deferred `task-branch-lifecycle` work).
- The forge tier is not a nicety. It is the only tier that can produce `open` or `closed`,
  and therefore the only one that can drive the `abandoned?` row of the §23 table.
- The log's `via=` field is meaningful: a `merged` verdict names the tier that had the
  evidence, so "why was this deleted" stays answerable.
- Failure direction is preserved: every uncertainty in this tier resolves to `unknown`,
  and `unknown` never destroys anything (RULES.md).
- **A second route to `unknown` arrived with ADR-0026**: a branch that has committed
  nothing since the task forked it. Both routes exist for the same reason — a tip equal to
  the base is not evidence of anything — and this one is the reason a task must record
  where its branch started.
