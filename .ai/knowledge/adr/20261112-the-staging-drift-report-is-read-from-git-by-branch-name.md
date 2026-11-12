---
id: adr-20261112-the-staging-drift-report-is-read-from-git-by-branch-name
type: adr
status: accepted
date: 2026-11-12
domains:
  - task
  - housekeeping
paths:
  - scripts/lib/common.sh
  - scripts/lib/status.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/forgecache.sh
summary: "Why jig status and housekeeping read the staging drift report from git by branch name and from the forge cache: tasks are the template's branches, age is the landing commit's time against git.staging_stale_after, unowned work is staging minus base minus every task branch, and a conflicting promotion is the cache's new mergeable column."
---
# The staging drift report is read from git by branch name, and from the forge cache

## Context

On the staging flow (`.ai/specs/staging-branch/`) a staging branch drifts from the base branch in
three ways the spec asks `jig status` and housekeeping to name: a task left on staging that nobody
promotes, work on staging that no live task owns, and a promotion the forge reports as conflicting
with the base ("A stale promotion is refreshed by running it again"). The spec binds how: everything
shared is read from git and the forge by branch name, never required from one checkout's workspace
(failure mode 3), and the report counts only what staging has and the base does not, or every
promoted task whose branch was deleted would read as orphaned. A read never asks the forge
(adr-20261015-a-read-is-one-json-envelope), and the forge cache had no word for "conflicting".

## Decision

- **One producer, `jig_staging_drift` (common.sh)**, gives tagged records — `unpromoted`,
  `conflicting`, `unowned`, `invalid` — and `jig_staging_drift_lines` words them as `staging: `
  lines. `jig status` prints them after the `flow:` line (a terminal shows each as needing the
  reader), the page and `jig status --json` turn them into the items `staging-unpromoted`,
  `promotion-conflicting` and `staging-unowned`, and housekeeping prints them after its report. On
  `direct`, or a staging flow `jig doctor` faults, nothing is asked. `staging:` and not `drift:`,
  which already names an install's drift.
- **The tasks are the branches.** Every branch `git.branch_template` names, here or on origin, is a
  task; this checkout's workspaces add their own branch, base and `promote_url`. A branch no
  workspace knows is judged against `git.base_branch`. A template with nothing before `{id}` names
  no branch by itself, and then only this checkout's tasks are known.
- **Waiting with no promotion** is a task that `_jig_staging_walk` finds `on` or `behind`, with no
  promotion — the forge cache's newest pull request from its branch into its base is neither `open`
  nor `merged` (a promotion merged by a squash leaves the task's own commits on staging outside the
  base, and it waits for no promotion), or, where the cache knows none, the checkout records no
  `promote_url` — for
  `git.staging_stale_after` (a project key, `14d`) or longer. The time is that of the commit on
  staging's first-parent line that last brought the task's work in: the walk now also prints where
  it reached staging (`reach`), and one `rev-list --parents --timestamp` of staging's own commits
  dates each one by the first-parent commit that brought it. A fix shipped again starts the count
  over; a value that is not a duration is said (`invalid`) and names no task. A task known here
  only by its branch is named with `its owner runs jig task promote <id>`: this checkout cannot
  promote it.
- **Work no live task owns** is `git rev-list --count --no-merges <staging> ^<base> --not
  --branches='<prefix>*<suffix>' --remotes='origin/<prefix>*<suffix>' <refs>`, in one process, the
  globs being `git.branch_template`'s and `<refs>` this checkout's task branches the template does
  not name: merges are left out, since a landing merge or a conflict resolution on staging belongs
  to the task it lands. The line carries the same arguments as a `git log`, so what it lists is what
  was counted.
- **A conflicting promotion** is one this checkout opened (`promote_url`; the spec's "in the owner's
  checkout") whose forge cache entry is `open` and `conflicting`. The cache gains an eighth column,
  `<mergeable>`, written by housekeeping from calls it already makes: GitHub's `mergeable` in the
  second `gh pr list --state open`, GitLab's `detailed_merge_status` in its one `glab mr list`. No
  forge, or a cache from before the column: the line does not appear.
- **The processes do not grow with the tasks or the commits** (conventions/shell.md): one
  for-each-ref, the walk's rev-lists, the dating rev-list, the counting rev-list and one `date`.

## Alternatives

- **A personal threshold in `config.local.yaml`.** Whether a task has waited too long is the
  team's judgement of its own test cycle, like the flow itself; one person's number would name
  different tasks in different clones.
- **Age from the task's own commits, or from the reflog.** A commit's date says when it was
  written, not when it landed, and a reflog exists only in the clone that fetched, never on a CI
  runner or in a colleague's clone.
- **The checkout's tasks only.** Simpler, and exactly failure mode 3: a colleague's task, which
  is most of what waits on a shared staging branch, would never be named, and its commits would be
  counted as nobody's.
- **Ask the forge for mergeability from `jig status`.** A read never asks the forge; the cache
  already holds the open pull requests, one column wider.
- **A file of its own for mergeability.** One more file with the same rows and the same writer.

## Consequences

- A colleague's task left on staging is named in every clone that has fetched its branch; one
  whose branch was deleted before it reached the base is counted as work nobody owns, which is
  what it has become.
- A promotion merged into the base by a squash leaves the task's commits on staging out of the
  base, so they count as nobody's once the branch is deleted (docs/known-issues.mdx).
- GitHub may answer `UNKNOWN` for mergeability it has not computed yet; that reads as nothing, so
  a conflict shows from the next housekeeping run after GitHub computed it.
- `_jig_staging_walk` has one more tag; its callers already read only the tags they know.
- Asking `mergeable` makes GitHub judge each of up to 200 open pull requests in the list call it
  rides on, so that call grows slower on a repository with many open; it was left there rather than
  made a call per promotion.
