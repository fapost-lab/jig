---
id: adr-20261113-staging-work-is-reported-to-its-own-author-until-acknowledged
type: adr
status: accepted
date: 2026-11-13
domains:
  - task
  - housekeeping
paths:
  - scripts/lib/common.sh
  - scripts/lib/status.sh
  - scripts/lib/staging.sh
summary: Why the staging drift report counts only the person's own commits (author email or name against the clone's git author) and stops naming them once jig staging ack records them by patch-id in .ai/runtime/staging-acked; the staging-unowned item carries commits, list and ack.
---
# Staging work no task holds is reported to its own author until acknowledged

## Context

The staging drift report (adr-20261112-the-staging-drift-report-is-read-from-git-by-branch-name) counted
every commit on origin's staging branch that the base lacks and no live task branch holds, whoever wrote
it, and named a `git log` that lists them. On a real project on the staging flow (2026-11-13) that was
94 commits going back seventeen months, by six authors: work still under test on feature branches, fixes
made on the staging branch alone, conflict resolutions. The line could not be acted on and stayed up
forever, so it said nothing, and it named colleagues' work to a person who can do nothing about it. The
person decided (2026-11-13): other people's commits are shown nowhere; their own old ones are marked as
known once, and only new ones are reported after that.

## Decision

- **Only the person's own commits are counted.** A commit is the person's when its author's email or
  name (mailmap applied, case ignored) is the email or name of this clone's git author,
  `git var GIT_AUTHOR_IDENT`. Email or name, because one person commits under several addresses (three,
  in that project); Jig commits a task as that author, so a task of this clone is covered. No identity,
  as on a CI runner, owns nothing. Nobody else's commits are counted, named or listed: not in the text,
  the page, `jig status --json`, housekeeping or `jig staging ack --dry-run`.
- **`jig staging ack` acknowledges them.** It records the person's commits the report counts now in
  `.ai/runtime/staging-acked` — gitignored, this clone's, in the runtime of the checkout that owns the
  task workspaces, so a task worktree and the main checkout share it (as the forge cache). One
  `<patch-id> <sha>` line per commit (`git patch-id --stable`), and a `- <sha>` line besides: a commit is
  acknowledged when its patch-id or its sha is in the file. By content, so a rebase or a cherry-pick on
  the staging branch does not bring acknowledged work back; by sha, for a commit with no diff, which has
  no patch-id. `--dry-run` lists them and writes nothing; `--expect <n>` refuses unless they are `<n>`,
  so a program marks only what its reader was shown, not a commit fetched since; off a sound staging
  flow it refuses. A write, so it raises the clone's revision (`jig_record_changed`).
- **The line names the command instead of a `git log`.** `staging: <n> commit(s) of yours on <staging>
  that the base does not have and no live task branch holds (list them: jig staging ack --dry-run; mark
  them as known: jig staging ack)`. No `git log` can leave acknowledged commits out; the dry run lists
  exactly what was counted, so the count and the listing still agree.
- **The item for a program** keeps its kind, `staging-unowned`, and `staging.commits`, now the count of
  own unacknowledged commits, and adds `staging.list` — at most 20, newest first, each
  `{"sha", "subject", "date"}` — and `staging.ack`, the command a program runs to acknowledge them,
  `jig staging ack --expect <commits>` (schemas/json.md). No own unacknowledged commit, no item.
- **The producer stays one.** `jig_staging_drift` prints `unowned<TAB><count><TAB>jig staging ack` and
  then `unowned-commit` records; `jig_staging_own` (common.sh) is the one judgement of "own, not
  acknowledged", used by the report and by the command. Its processes do not grow with the commits: one
  `git var`, one `git log`, and, only once something is acknowledged, one `git log -p | git patch-id`.

## Alternatives

- **A team view: everyone's work, grouped by author.** The person asked for none; the page is one
  person's, local, with nothing shared with the team. A team view is a task of its own if one is needed.
- **Acknowledge by sha.** Simple, and wrong on a branch that is rebased or has commits cherry-picked
  onto it: every acknowledged commit would come back.
- **Acknowledge a point in time, or the staging tip.** A colleague's merge of an old branch of the
  person's would bring commits from before that point, never acknowledged, and they would stay silent.
- **Email only.** In the real case 39 of the person's 52 commits carry another address. The price of
  the name: a colleague with exactly the same author name is taken for the person.
- **Acknowledge by sha list from the program.** The list is capped; a count the reader saw does the
  same job for any size.
- **Keep naming a `git log`, filtered by author.** It cannot leave acknowledged commits out, so it would
  list more than the count.

## Consequences

- A person sees their own forgotten work once, decides, and then hears only of what is new.
- A colleague's commit on the staging branch is invisible to everyone but its author, in that author's
  clone; work nobody owns because its author left is seen by no one.
- A promotion merged by a squash still leaves the person's own commits in the count, until acknowledged
  (docs/known-issues.mdx): the report does not tell a squash promotion from drift.
- `staging-unpromoted` is unchanged: a colleague's task waiting on staging is still named, by its branch.
- A branch template with nothing before `{id}` names no branch by itself, so a colleague's feature
  branch on origin does not hold its commits; only authorship keeps them out of the person's count.
