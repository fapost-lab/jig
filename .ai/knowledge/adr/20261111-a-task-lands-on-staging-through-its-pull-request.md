---
id: adr-20261111-a-task-lands-on-staging-through-its-pull-request
type: adr
status: accepted
date: 2026-11-11
domains:
  - task
paths:
  - scripts/lib/land.sh
  - scripts/lib/task.sh
  - scripts/lib/common.sh
summary: Why jig task land and ship at merge land a staging pull request on the forge when clean and directly only on conflict, in a temporary worktree with rerere and an unforced push retried from a fresh fetch, why review follows git.staging_review, and why a task branch stays clean of staging.
reviewed_at: 2026-11-12
---
# A task lands on staging through its pull request, and directly only when it conflicts

## Context

In the `staging` git flow (adr-20261109-the-team-names-its-git-flow-and-the-agent-writes-it-after-a-yes) `jig task ship` opened the task's pull request
into `git.staging_branch` and stopped there, even at `agent.git: merge`
(adr-20261111-in-the-staging-flow-a-task-ships-into-the-staging-branch). The team's own practice is
the next step: the pull request is reviewed and merged on the forge, and only when it conflicts with
the staging branch is the task merged into it directly, by hand. The staging-branch specification's decisions bind how Jig
does it: the direct merge only on conflict, in a temporary worktree of the staging branch fetched
fresh, never in the person's checkout, where a dirty tree, staging held by another worktree or a merge
left mid-conflict would follow the person's next commit onto staging; a rejected push retried from
a fresh fetch, never forced, since several people and autopilots push to the one shared branch; the agent resolves the conflict, any file, and names the resolution;
review by `git.staging_review`; landing needs `agent.git: merge`. At the gate the person added one
rule: a task branch is cut from the base and stays clean of the staging branch until it reaches the
base.

## Decision

- **`jig task land <id>`** lands the task's open pull request into the staging branch; `jig task ship`
  at `merge` calls the same code (`land_task`, `scripts/lib/land.sh`, sourced by `task.sh` alone)
  right after it opens the pull request, and its exit code is the ship's. Exit 0 is landed or an
  ordinary `not landed: <why>`; 3 a person decides (below `merge`, an unapproved pull request at
  `ask`, a push origin refused, staging moving under three pushes); **5 a conflict waits for the
  agent** in the temporary tree. `--resolved --note-file <file>` continues after 5; `--abort` gives a
  landing up and sends nothing. Below `merge` it refuses with exit 3 and the person lands it.
- **Before anything is sent** it refuses a task not on the staging flow, cut from another base, on
  `staging_land: external`, with no pull request, or with a closed one; it asks the ship's own gates
  (knowledge decision, blocking findings, review receipt, route), fetches the staging branch, the task
  branch and the base **strictly** — a failed fetch refuses (`jig_fetch_fresh`), where
  `jig_fetch_branches` only warns — and refuses a local branch ahead of origin: only what was
  shipped lands. A pull request already merged reads as landed.
- **The clean-branch rule.** A task branch is cut from the base and stays clean until it reaches the
  base: only the base and clean task branches may be merged into it. A clean task branch `task/<dep>`
  — itself carrying nothing else, judged by the same rule, recursively — may be merged in, and its
  commits are its work even when they are on the staging branch already (the person's decision at
  the gate, 2026-11-11). The staging branch merged in (GitHub's "Update branch" included), any other
  branch, or a task branch that itself carries one of those is refused by `task ship` at every level
  before the commit and by `task land`, naming what was merged. The ship judges the commit it is
  about to make, so a merge in progress (`MERGE_HEAD`) is judged with its heads as the concluding
  commit's parents. One function answers both, `jig_branch_carries_staging <tip> <base-ref>
  <staging-ref> [<merge-head>...]` in `common.sh`: it looks at every merge on the branch's
  first-parent line and prints `<sha><TAB><merge><TAB><what>` per commit a refused merge brings. A
  merge of the base never counts; the task's own commits already on staging stay its own. "Cut from
  the base" is checked by the first-parent line: a branch is not clean when a commit of its line, down
  to the first the base has, is on the staging branch's own first-parent line — Jig lands only by
  merge commits, so a task's commits are second parents there, while a branch cut from or rebased
  onto staging carries staging's landing merges on its own line. A merged dependency is judged at the
  commit that was merged, recursively and four deep, and is also not clean when its line holds the
  tip of an origin branch that is neither `task/*` nor the base. A merged commit counts as a
  dependency only when it is on a `task/*` branch's own first-parent line — that task's own work —
  never because a task branch merged it in too. The refusal names the reason: cut
  from a branch, carries what, or nested too deep. One rev-list per branch judged, never per commit.
- **Review by `git.staging_review`**, read from the forge before either merge (`jig_pr_approval`):
  approved when GitHub's `reviewDecision` is `APPROVED`, or is empty and the latest reviews hold an
  approval and no change request; on GitLab when `approved_by` is not empty. `none` lands without
  asking and says so; `require` waits; `ask` stops with exit 3 naming both answers — land without
  review (`--without-review`) or wait — and an unattended run waits. `--without-review` is refused
  under `require` and where nobody answers. A landing without an approval is said on the pull request. The person's
  word is for one landing attempt: kept in the workspace (`land-without-review`) only across the
  conflict stop and its `--resolved`, so the person is not asked twice, and forgotten however else the
  attempt ends — landed, not landed, refused — and with `--abort`.
- **Merged on the forge when it merges cleanly** (`jig_pr_mergeable`: GitHub `mergeable`, GitLab
  `has_conflicts`/`detailed_merge_status`, looked at again for up to a minute while the forge works
  it out): through `jig_ship_merge` with the policy `merge-commit`, since squash and rebase break the
  ancestry "on staging" is read from. Red CI, a refusal or no allowed method is `not landed`, and the
  direct merge is **never** the way around them. Unknown is `not landed`; a draft never lands.
- **The direct merge, only on conflict**, in `<git.worktree_root>/.land-<id>`: a detached worktree
  of `origin/<staging>` just fetched, outside `.git/` so the agent edits it with ordinary tools; the
  leading dot keeps it from being any task's worktree. The task's tip is merged with `--no-ff
  --no-commit` and git's rerere on (its cache is the clone's `rr-cache`), the conflicting paths are
  kept in the workspace (`land-conflicts`), and the agent resolves and runs `--resolved`, which
  refuses unmerged or unadded paths, leftover conflict markers, an empty note, and a task branch that
  moved since the merge started. The merge commit's message names the paths and carries the note
  (`land-note.md` in the workspace). The person's checkout, its HEAD and the task branch are never
  touched.
- **The push is never forced.** `git push origin HEAD:refs/heads/<staging>`: a non-fast-forward is
  answered by a fresh fetch, a new tree, the merge again with the resolution replayed by rerere, and
  another push — three pushes at most per run; new conflicts stop at 5 again. Any other refusal —
  branch protection, a hook, rights — stops with exit 3, no retry, and keeps the tree with the
  committed merge for the person. A push past protection a person's own rights allow (an admin's
  bypass) is not something Jig can see; it is accepted as the team's practice by hand is.
- **After the push** the tree goes, the pull request gets a comment naming the merge, the paths and
  the resolution, and a pull request the forge still reads open (GitLab may not mark it merged) is
  warned about, never closed. A failed comment only warns: the merge commit says the same.
- **Nothing is left behind the task**: the checkout stays on the task branch, the branch stays (it
  is promoted later), the task's status does not change. Parking is the next phase's, built by
  adr-20261112-a-task-waiting-at-staging-is-parked-and-resuming-it-is-its-status: a landed task is
  read as parked, and why it waits is never written.
- `jig task land` is the `land` row of the actions table (`_task_land_refusal`).
- **The temporary tree is the second `--force` removal in Jig** (RULES.md): `git worktree remove
  --force` of `<worktree root>/.land-<id>` only, by `_land_tree_remove`, whose path one function
  builds.

## Alternatives

- **Jig's own tree (`owntree.sh`).** One per clone, under a lock with a 900 s ttl, removed at every
  exit; the agent resolves between two runs, for as long as it takes. It would need the lock held
  across the agent's work or a different lifecycle for every writer.
- **A tree inside `.git/`.** Out of every indexer's way, but runtimes may refuse edits under `.git/`,
  and the agent has to edit there.
- **The merge in the person's checkout.** Failure mode 5 of the spec.
- **The direct merge as a fallback for any refusal of the forge.** It would bypass red CI and branch
  protection; the spec allows it only on conflict.
- **Deciding the conflict locally (`git merge-tree --write-tree`).** Needs git 2.38 and is a second
  answer beside the forge's, which is the one that merges.
- **Retrying the push by merging the new staging into the resolution.** One more merge commit on
  the shared branch per race; merging again with rerere leaves one.
- **Retrying forever, or not at all.** One holds a run on a busy branch; the other hands every race
  back to the agent.
- **`reviewDecision` alone.** It is empty when no rule requires reviews, so an approved pull request
  would read unapproved.
- **A question asked by the script.** Scripts ask nothing; the skill asks on exit 3.
- **Only `ship --continue`, no `task land`.** After waiting for a review there would be nothing to
  land with but a new ship.

## Consequences

- **Known limitations of the clean-branch walk.** It relies on Jig's landing by merge commits: a
  staging branch landed on by fast-forward — an external lander's plain `git merge` under
  `git.staging_land: external` — puts a task's own commits on staging's first-parent line, and the
  task then reads as cut from staging. Whoever lands outside Jig lands with `--no-ff`. A branch cut
  from a feature branch is caught only for a merged dependency, and only while that feature branch's
  tip on origin is still on the dependency's line: once the feature branch moved on, was deleted on
  origin or was never pushed, the dependency reads clean; the task branch itself is never checked for
  it.

- `jig task ship` at `merge` in the staging flow may now exit 3 or 5 where it used to print `not
  merged` and exit 0; the skills read both.
- A wrong landing is a merge commit on the shared staging branch; nothing is forced, so it is undone
  by a person's `git revert -m 1`; the task then still reads on staging, since "on staging" is
  ancestry and a revert keeps it.
- The agent's resolution of others' code reaches staging without CI (a conflicting pull request runs
  none); the skills ask for targeted tests in the tree before `--resolved`, and QA reads the comment.
- rerere writes its cache to the clone's `rr-cache`; git prunes it on its own schedule.
