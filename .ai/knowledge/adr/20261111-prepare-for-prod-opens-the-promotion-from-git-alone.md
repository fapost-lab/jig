---
id: adr-20261111-prepare-for-prod-opens-the-promotion-from-git-alone
type: adr
status: accepted
date: 2026-11-11
domains:
  - task
paths:
  - scripts/lib/promote.sh
  - scripts/lib/common.sh
summary: Why jig task promote runs from git and the forge alone, tells a CI runner by CI, refuses against the tested staging commit, finds its pull request by head and base, and hands a conflict with the base to a person.
---
# "Prepare for prod" opens the promotion from git alone, and hands a conflict with the base to a person

## Context

In the staging flow (`.ai/specs/staging-branch/`) a task lands on `git.staging_branch`, is tested
there, and reaches the base branch only when somebody says "prepare for prod" — a person, or a CI
job given the staging commit it tested. The spec asks for one command that refuses a task whose tip
is not in that tested commit, merges the base into the task branch when the two conflict, opens the
pull request into the base and prints its link, and runs on a CI runner, which has the repository
and a forge token but no workspace, no queue and no `agent.git`.

Three things the spec took for granted did not hold in the code. Merge conflicts are symmetric: a
task branch that conflicts with the base conflicts just as much when the base is merged into it, so
"merge the base in when they conflict" always needs a resolution, and a script resolves nothing
(ADR-0001). `jig_ship_pr` finds an open pull request by its head alone, so it would report a task's
open pull request into the staging branch as its promotion. And nothing told a CI runner from a
person's checkout.

## Decision

- **`jig task promote <id> [--commit <sha>] [--title <t>] [--body-file <file>]`**, a subcommand of
  `jig task` whose body lives in `scripts/lib/promote.sh`, sourced by `task.sh` for this command
  alone. Ids are collected into a list and `--all` is parsed; both forms refuse (`usage`) until
  "Promote from CI" builds them. Without `--commit` the tested commit is the tip of
  `origin/<staging>` after a fetch — what a person who says it by hand means.
- **It reads git and the forge, never requires a workspace.** The branch is the one the state
  records, else the name `git.branch_template` gives the id. Where a workspace exists it adds the
  epic check, the autopilot check, the dependency warning and `promote_url`; nowhere is one needed.
- **A CI runner is a process whose `CI` is set and not `false`/`0`** (`jig_on_ci_runner`). There
  `agent.git` is not read: the token in the pipeline is the team's decision. In a checkout the
  person's `agent.git` must be `pr` or `merge`; below it the command exits 3 and the pull request is
  the person's, as `task ship` hands over. A task whose autopilot run is `on` is refused, on a runner
  as in a checkout, wherever a workspace says so: autopilot never promotes.
- **Refused before anything is sent, exit 1, each with its code**: not the staging flow; a task of
  an epic; a shallow clone (`shallow-clone`); a base, staging or task branch that cannot be fetched
  from origin — unlike `task ship`'s fetch, which only warns, since a promotion judged on a stale
  `origin/<task-branch>` opens its pull request on the real branch, which may hold an untested fix; a `--commit` that names no commit (`not-found`) or is
  not on `origin/<staging>`; no branch (`not-found`); the local and origin branch diverged
  (`branch-diverged`); no own commit in the tested commit (`not-on-staging`); an own commit the
  tested commit lacks, pushed or not (`behind-staging`); a merge of staging into the task branch
  (`carries-staging`, naming what was merged) — the task branch stays clean of staging, without
  exception. The one merge it may carry is the clean branch of another task (`task/<dep>`, on that
  branch's own first-parent line and carrying nothing but other clean task branches, judged
  recursively): its commits reach the base with the task, so each must be in the tested commit, and
  the command warns in its output and the pull request body (decided by the person, 2026-11-11).
  Clean also means cut from the base: no commit of the branch's first-parent line may be on the
  staging branch's first-parent line (Jig lands a task by a merge commit, so its own commits are
  second parents there), and a merged dependency's line may not hold the tip of an origin branch
  that is not a task branch, the base or staging (`cut from feature/x`). One function answers all of
  it, `jig_staging_branch_problems` (common.sh), and it is asked before the tested commit is, so a
  staging newer than `--commit` merged in is named, not listed as the task's own commits. A
  dependency cut from another task's branch names that task too, so no task's work reaches the base
  unnamed. On the task's first-parent line every commit but a merge of the base is its own work and
  must be in the tested commit — a merge of a clean dependency included, since whatever that merge
  changed was tested only if the merge was. The judgement is
  `_jig_staging_walk` (common.sh), the walk `jig_staging_states` already used, given the tested
  commit instead of `origin/<staging>`, so a merge of the base does not make a promoted task behind.
- **A conflict with the base is found, not resolved — a change to the spec.** The merge is tried in
  a temporary detached worktree (`jig_merge_conflicts`), aborted, and the worktree removed by
  `git worktree remove` without `--force`. A conflict exits 3 (`base-conflict`) with the paths and
  the steps; the agent or person merges `origin/<base>` into the task branch in its checkout,
  resolves, runs `jig verify`, commits, and runs the command again, which pushes that merge — the
  only commits it ever pushes, since anything else would make the task behind — and opens the pull
  request. Without a conflict the base is not merged in at all. On a runner nobody can resolve, and
  the job fails with exit 3.
- **The pull request is found by head and base together** (`jig_ship_pr`'s new `<match-base>`). A
  second run prints the open one, `pr <url> (already open)`; a closed one does not count. Its title
  is the staging pull request's, else the newest own commit's subject; its body names the tested
  commit, the staging pull request, the dependency warnings and a version raise.
- **A dependency is warned about, never refused**: where the checkout's queue has a `task:`
  dependency whose work is on the tested commit and not in the base, a line in the output and in
  the pull request body. A runner has no queue and prints none.
- **A version raise is said, not acted on**: no merge happens here, so a person merges every
  promotion and no draft is opened; "Merge the promotion by the flow" decides the rest.
- **Output a UI reads**: `task promote: …` lines, `pushed <branch>`, `pr <url>` or
  `pr <url> (already open)` as `task ship` prints them, and a last line on who merges
  (`git.promote_merge`). Exit 0 open or already in the base, 1 refused, 3 a person is needed. No
  `--json` yet; its codes are registered in schemas/json.md.
- **`promote_url`**, a script-owned state key, keeps the promotion's link; `pr_url` stays the
  staging pull request's.

## Alternatives

- **`task ship --to-base`.** It needs a workspace, a message file, the findings and receipt gates
  and `agent.git`; a runner has none of them.
- **A top-level `jig promote`.** The verb is about a task, beside `ship`; the shared parts live in
  common.sh either way.
- **Merge the base in on every promotion.** A merge commit on every run changes what ships for no
  reason, and on a conflict it needs a resolution anyway.
- **Resolve with a strategy (`-X ours`/`theirs`), or merge in the developer's checkout.** The first
  silently ships wrong code; the second meets a dirty tree, a branch checked out elsewhere, and a
  `MERGE_HEAD` left behind.
- **`git merge-tree --write-tree`.** No checkout needed, but it asks for git 2.38; one path for every
  git is worth more. It can become a fast path later.
- **`agent.git` everywhere, or nowhere.** Everywhere, a runner never promotes; nowhere, an agent at
  `none` opens pull requests into the base on its own.
- **A runner is a clone with no workspace or local config.** A developer's fresh clone looks the
  same, and their agent would pass by `agent.git`.
- **Warn on a failed fetch and go on with the refs at hand**, as `task ship` and `task start` do.
  The pull request is opened on origin's branch as it is, not as it was last fetched: a fix pushed
  after the test from another clone would reach the base untested.
- **Unshallow the clone silently.** A hidden fetch of the whole history on a large repository is a
  surprise; the refusal says how to fetch it.
- **An escape flag for `carries-staging`.** The person who owns the flow decided the task branch is
  never merged with staging; `task ship` and `task land` check the same earlier, through
  `jig_branch_carries_staging`. Until the two walks are one (finding F15 of this task), they differ
  at the edges: land follows merged dependencies four deep and names task branches `task/<id>`,
  promote five deep and by `git.branch_template`. Land is the stricter in both, so promote never
  accepts a branch that could not have reached staging; F15 unifies depth and naming with the walk.

## Consequences

- A CI job can promote with `jig task promote <id> --commit <sha>` given full history, `gh` or
  `glab` and a token; in link mode it installs Jig itself, since `.ai/scripts` points nowhere there.
- A conflict with the base always needs an agent or a person; the spec's "merges the base in" is
  carried out by whoever resolves, and the command only pushes the result.
- The resolution of that conflict is a combination nobody tested on staging; the pull request's CI
  is its one check (the spec's failure mode 1, accepted).
- RULES.md gains one deletion: the trial merge's worktree, removed by git without `--force`.
- **Known limitation: "cut from the base" is judged by what can be seen, not by the cut point.** A
  top-level task cut from a feature branch, or a dependency cut from a branch whose tip moved on
  after the cut, was deleted on origin or was never pushed, passes as clean. Its content is still
  only what the tested commit holds, so nothing untested reaches the base; what is lost is the
  label — the work of that other branch reaches the base under this task's name, with no warning.
  Judging the cut point itself (the oldest commit of the first-parent line must have its first
  parent in the base, at every depth) would close it; left for a later change.
- `_jig_staging_walk` is shared: a change to what counts as own work changes `jig status`,
  housekeeping and promotion together, which is the point.

## Amendment (2026-11-12): a fix after the promotion was opened

The promotion's pull request and the staging pull request come from the same task branch. Once
`jig task promote` has opened the one into the base, a fix found by QA cannot reach staging without
reaching that pull request too: every push to the branch updates both, and `jig task ship` refuses
while a pull request into another branch than staging is open (adr-20261111-in-the-staging-flow-a-task-ships-into-the-staging-branch).
So `behind-staging`, when a promotion is open, says to close it first, ship the fix to staging, and
promote again after the test. The base-conflict refusal is told by exit 3 alone: promote has no
`--json` yet, and `base-conflict` in schemas/json.md is reserved for it.

## Amendment (2026-11-12): several tasks in one run ("Promote from CI")

`jig task promote [--commit <sha>] <id> <id>…` promotes each task named, and
`jig task promote --commit <sha> --all` every branch on origin that `git.branch_template` names a
task's branch (the id read from the name, so a runner with no workspace has it) whose tip the tested
commit contains and the base does not. `--all` needs `--commit` (`usage` without it): a build that
merely ran green is no decision to send everything on staging to the base. `--all` with ids, and
`--title` or `--body-file` with more than one task, are `usage` too; so is `--all` under a template
with nothing before `{id}`, which, as for `jig_branch_is_jigs`, would take every branch whose name is
a valid id — staging and the base included — for a task's.

What would refuse every task — the flow, a shallow clone, a base or staging branch that cannot be
fetched, a tested commit that names nothing or is not on staging — refuses the run once, before the
first task. The tested commit is then resolved once and given to every task, so all are judged
against the same commit even without `--commit`. Each task runs `_promote_one` unchanged, in a
subshell of its own (`_promote_task`): a refusal anywhere on its path exits, as it does for one task,
and ends that task alone; the subshell's explicit `exit` runs its own cleanup, the trial merge's
worktree included. Each task is announced (`task promote: promoting <id>`), prints its own output,
and ends in `task promote: <id>: promoted|refused|needs a person`; a summary line closes the run.

The exit code summarises: 1 when any task was refused, else 3 when any needs a person, else 0 —
every task open or in the base already, or `--all` found nothing to promote. A refusal outweighs a
person needed: it means something is wrong, not only that someone must act, and either fails a
pipeline. An interrupted task (130, 143) ends the run with its code. One task named alone keeps the
one-task output and codes. A later step that acts on each task's pull request ("Merge the promotion
by the flow") goes in that per-task step.

A branch `--all` leaves out because some of its own commits are in the tested commit and some are
not — tested, then fixed — is named (`task promote: skipped <id>: …`) and does not change the exit
code: a pipeline must not turn red on every untested fix. A branch with nothing in the tested commit
is not mentioned. "Not yet in the base" is ancestry alone, so a promotion merged by squash or rebase
is taken again; teams using `--all` merge promotions with a merge commit (known issue, closed by a
later task). `--all` must not run while an epic branch is on the staging branch: a runner has no
workspace to tell an epic's tasks from the others, and the spec leaves epic-meets-staging open. A
task reverted on staging still reads as tested (the spec's failure mode 7), and `--all` promotes it.

Rejected: turning `_promote_refuse` into a `return` — the steps also exit through functions of
common.sh and task.sh shared with `task ship` and `task land`; only a subshell isolates them all.
Exit 3 outweighing 1 — a pipeline would read a run with a refused task as one waiting on a person.

## Amendment (2026-11-12): the merge by the flow

The bullet "A version raise is said, not acted on" is superseded: `git.promote_merge: auto` now
switches the forge's auto-merge on where the person or the runner may and CI gates the base, a
release never, and a `major` one where auto-merge would otherwise apply opens as a draft whose body
starts with `Needs a human: major release?`. The last line says who merges. A refusal that means
origin's task branch is not the tested commit (`branch-diverged`, `carries-staging`,
`not-on-staging`, `behind-staging`) switches auto-merge off first on an open promotion that has it
on, and says so — the one thing a refusal sends (adr-20261112-a-promotion-merges-itself-only-where-ci-gates-it).
