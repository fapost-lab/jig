---
id: adr-20261010-a-task-carries-its-tracker-issue
type: adr
status: accepted
date: 2026-10-10
domains:
  - task
  - config
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - scripts/lib/config.sh
  - schemas/state.md
summary: Why a task's tracker issue is read from the start of its id only by the project's task.issue_pattern (no flag, no guess without it), stored as the state key issue, refused by task set, and named once by task ship in the commit subject and the pull request title, after the subject for a numeric issue.
---
# A task carries its tracker issue, read from its id by the project's `task.issue_pattern`, and `task ship` names it in the commit subject and the pull request title

## Context

Projects that keep their work in a tracker (YouTrack, Jira, Linear, GitHub or GitLab issues) name a
task after its issue — `SRD-2455-fix-login`, `123-fix-login` — and the id grammar already allows it.
Jig knew nothing of the issue: it was not stored, not shown, and `task ship` did not put it where a
tracker's VCS integration looks for it, the commit's first line and the pull request title
(spec: `.ai/specs/release-2026-10-10/`). The owner settled four things before the design: the issue
is a field of its own; there is no `--issue` flag, the id is read; it is read only by a pattern the
project configures, so nothing is guessed without one; and both `PROJ-123` and `123` are issues.

## Decision

- **`task.issue_pattern`**, a project key with no default, is an extended regular expression as
  awk reads it, one pair of surrounding quotes removed. Unset, no issue is read from any id: the
  feature costs a project without a tracker nothing (zero-config).
- **Read at the start of the id, to a boundary.** `jig task new` matches `^(<pattern>)` against the
  id, takes awk's longest match and keeps it only when it ends at the end of the id or before `-`,
  `_` or `.`. The match is written to the state key `issue`. A pattern awk cannot read files the
  task without an issue and a warning; it never refuses the work.
- **The id is the only place it is written.** `task set` refuses `issue`: a value set by hand could
  disagree with the id it is read from. A task filed before the key keeps none.
- **Shown where the task is listed**: `task show` (the state), `task list` and `jig status`
  (`issue=<issue>` after `status=`). The status page shows the id, which already carries it.
- **`task ship` names it once.** The reference is the issue as it is, or `#<n>` for one of digits
  only, the form GitHub, GitLab and Redmine link. When the commit's first line does not hold the
  reference as a whole word, the message is copied with it added — `SRD-2455 <subject>` before,
  `<subject> (#123)` after, because a first line starting with `#` is a comment to git under
  `commit.cleanup=strip` — and the copy is committed; the task's commit-message file is not
  changed. The pull request title gets the same rule, whether it came from the message or from
  `--title`. The body is untouched.

## Alternatives

- **A `--issue` flag on `task new`**, or an id built from it (`{issue}-{slug}`): refused by the
  owner. The id already says it, and a second place to write it is a second place to get it wrong.
- **Reading any `[A-Z]+-[0-9]+` prefix without configuration**: `release-0-25-1` or a slug like
  `v2-3-notes` would become issues no tracker has. Opt-in costs one line to a tracker user and
  nothing to anyone else.
- **Named presets (`jira`, `github`) instead of a pattern**: fewer mistakes, but every tracker with
  another key shape — or a project prefix rule — would need a new release of Jig.
- **A trailer (`Refs: SRD-2455`) instead of the subject**: not every integration reads trailers,
  and a pull request title has none; the subject and the title are what all of them read.
- **`#123` as a prefix for a numeric issue**: lost entirely to `commit.cleanup=strip`.
- **Tracker commands in the commit (`#fixed`)**: they change another system from a commit; out of
  scope.

## Consequences

- A tracker user adds one line to `.ai/config.yaml`; the order "create the issue, then
  `jig task new`" stays a rule the project writes into its own AGENTS.md, not code.
- `issue` joins the fields `_status_task_rows` copies, before `_ST_APFACTS`, which must stay last.
- A pattern too broad for the project's ids (`[0-9]+` against `2026-10-notes`) reads an issue that is
  not one; the documentation says to choose one only issues match. Such a match costs a wrong label
  in a subject and a title, never a refused task or a lost commit.
- Branch names are unchanged (`task/{id}`).
