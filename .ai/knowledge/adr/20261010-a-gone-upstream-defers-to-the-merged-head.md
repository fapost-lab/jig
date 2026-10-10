---
id: adr-20261010-a-gone-upstream-defers-to-the-merged-head
type: adr
status: accepted
date: 2026-10-10
domains:
  - housekeeping
  - task
  - install
paths:
  - scripts/lib/common.sh
  - scripts/lib/housekeeping.sh
summary: Why a merged Jig branch whose upstream someone else pruned is deleted when its tip is in the head of the merged pull request, by a ref update guarded by that tip.
---
# A branch whose upstream is gone may go when its tip is in the merged pull request's head

## Context

adr-20261007-a-merged-branch-leaves-with-its-work deletes a merged Jig branch with `git branch -d`
and relies on `origin/<b>` still being there: `-d` checks a branch against its upstream, so a
squash-merged branch passes. Jig's own fetches say `--no-prune` to keep that ref. Somebody else's
need not: with the forge set to delete head branches on merge, an IDE's background
`git fetch --prune` (PhpStorm's, in the case that prompted this) drops `origin/<b>` minutes after
the merge. `-d` then compares the branch with HEAD, sees none of the squash's commits, and refuses.
On the owner's clone every `jig/upgrade-*` and almost every `task/*` branch stayed, each logged
`action=keep`, although the forge reported every one of their pull requests merged with the very
commit the branch was at. The earlier ADR rejected the fix below and left such branches to the
person; in practice nobody reads the log line, and the branches pile up again.

## Decision

`jig_branch_leave <who> <branch> <remote-sha> [<merged-head>]` (common.sh) keeps `git branch -d`
as the first and ordinary path. Only when `-d` refuses, and only with `<merged-head>` — the head of
a pull request the forge reported merged into the default branch, or into an epic already released
into it — the local branch goes anyway when its tip is that head or an ancestor of it
(`git merge-base --is-ancestor`): every commit on it is in the merged pull request. It is deleted
by `git update-ref -d refs/heads/<b> <tip>`, so only while it is still at the tip that was checked,
and its `branch.<b>` config section is removed with it. The outcome line is the ordinary
`deleted branch <b>`. A tip with any commit past the head, or a head that is not in this clone, is
kept, with the same `kept branch <b>: git does not see all of its commits merged` as before.

`<merged-head>` defaults to `<remote-sha>`. `_hk_branch_sweep` passes the forge's head separately,
because it empties `<remote-sha>` whenever origin's branch is gone or has moved — the very case in
which the local upstream is likely gone too. A branch housekeeping finds landed by ancestry alone
has no merged head and is unchanged: `-d` passes it anyway.

Everything else in the earlier ADR holds: which branches are Jig's, never one checked out or with
an open pull request, local before origin, origin only with a lease at the merged head, and
`git.delete_merged_branches: false` keeps every branch.

## Alternatives

- **Keep the branch and report it** (the earlier decision). Correct but useless in practice: Jig
  cannot control another program's fetch, and the only trace is one log line per run.
- **Tell the person to turn off prune in their IDE.** Works for one person on one machine, and
  only until the next tool that prunes.
- **`git branch -D` after the same check.** Deletes the same branches, but another process could
  move the branch between the check and the deletion; `update-ref` with the old value closes that
  window.
- **Fetch the merged head back into `origin/<b>` and retry `-d`.** Needs the network, invents a
  remote-tracking ref for a branch origin does not have, and still rests on the same check.

## Consequences

- A squash-merged branch whose upstream someone else pruned leaves like any other; one with
  unpushed work past the merged head stays and is reported.
- The safety of the local deletion past `-d` now rests on the forge's report: the head it names
  for a merged pull request from this branch. That is the same report the sweep already trusts to
  call a squash merge landed and to delete origin's branch.
- The commits of a deleted branch remain reachable from the forge (`refs/pull/<n>/head`, or the
  merged result) and from HEAD's reflog where they were checked out.
- RULES.md's deletion paragraph names this exception alongside `-d`.
