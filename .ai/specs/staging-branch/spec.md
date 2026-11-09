# Git flows — a project picks how its tasks travel; `direct` and `staging` ship

Depth: normal — with the independent failure hunt: the idea changes a task's lifecycle and what
guards a merge into the default branch, so an outside read is worth its cost.

## Idea

The human's words (translated from Russian, meaning kept):

> We take a task from master; after implementation we merge it into the stage branch, and only
> after testing and fixes do we create a PR into master and merge it.
>
> A task goes to stage through a pull request, but frequent conflicts mean we often end up merging
> it directly by hand.
>
> When QA signals "prepare for prod", we can say the same to Jig — "prepare for prod" — and Jig
> opens the pull request, checks conflicts, merges master in if needed, and hands back the link.
> Ideally Jig UI does this when a card is moved from Staging to Ready: a script finds the right
> session and gives it the command — a separate project; for now, only whether it is feasible.
>
> We prepare a PR into stage and give it to colleagues for review. After approval the PR is
> merged; only if it conflicts do we merge into stage directly by hand, though the PR exists and
> stays in the history. It is an important step: we never just merge straight in.

## Goal and problem

- Who is worse off without this, and how: a team that tests on a shared staging environment before
  production. Jig knows only one place a task lands — the base branch or an epic — so the staging step is
  done by hand outside it: nothing records that a task is on staging, nothing stops its pull request
  into the base branch from being merged before QA, autopilot and `agent.git: merge` would take it straight
  to the base branch, and a pull request merged into staging reads as `wrong-base` (ADR-0039).
- What is true when the work is done: in a project that names a staging branch, a task is cut from
  the base branch, shipped to staging through a pull request (reviewed when the team wants it), fixed as often as QA
  needs, and promoted to the base branch on one
  command — "prepare for prod", said by a person or run by CI — which opens the pull request,
  brings the base branch in when it conflicts, and returns the link. A project without a staging branch works exactly as today.

## Stress test

- Hidden assumptions — "this holds only if …":
  - … staging is never rebuilt, squashed or reverted: "on staging" is ancestry, and a task reverted
    on staging after QA rejected it still reads as on staging.
  - … tasks on staging are independent: staging is never merged into the base branch, so a task tested with
    another one present can reach production without it.
  - … the staging branch accepts a direct push from the people who resolve conflicts: a team that
    protects staging against every push gets the pull request path only, with no conflict fallback.
- The main trade-off: the task branch stays clean (only its own work reaches the base branch) at the price
  of shipping a combination nobody tested — staging's conflict resolutions stay on staging, and the
  pull request into the base branch is a second merge.
- The weakest point: what QA tested is not what reaches production. It is the staging model
  itself, not Jig's, and Jig can only narrow it: the promotion pull request's CI against the base branch
  is the one check of the shipped combination.
- Failure modes — cause, what breaks, the signal that shows it (independent failure hunt, ranked
  by likelihood times cost):
  1. Tested ≠ shipped — conflicts resolved on staging never reach the task branch, and the merge
     of the base branch at promotion is a new, untested resolution. "Worked on staging" bugs in production;
     the staging merge's diff differs from the pull request's.
  2. An agent resolves conflicts on staging against code it does not own, pushed with no review
     and no CI. Regressions in other developers' tasks on staging; blame leads to a staging merge
     commit from someone else's task.
  3. Task state is per checkout: the drift report and a card move run by the merger or QA see
     only their own tasks. Colleagues' work reads as orphaned; "unknown task" on the card action.
  4. Dependent tasks promoted one at a time — B was tested with A present, reaches production
     without A. A production failure staging cannot reproduce (a missing migration or API).
  5. The staging merge in the developer's own checkout: dirty tree, staging checked out in another
     worktree, a merge left mid-conflict, HEAD left on staging. Later commits land on staging;
     `MERGE_HEAD` left behind.
  6. Races on the shared branch: several developers and autopilots push stale staging copies;
     protected staging refuses outright; interleaved deploys. Non-fast-forward rejections on ship.
  7. Ancestry lies: a reset of staging makes every task vanish; a revert keeps a rejected task
     "on staging"; the merge of the base branch at promotion makes a task read "behind staging". Promotion
     refused right after it succeeded; reverted features shown ready.
  8. `agent.git: push` covers a push to a shared branch as if it were the task's own. Surprise
     pushes to staging; at `commit`, tasks wait for QA that were never deployed.
  9. Promotion pull requests go stale while the merger works through them one by one. Links
     already handed out lead to pull requests that now conflict.
  10. Tasks stay open for weeks waiting for QA: the queue, concurrency limits and `jig status`
      fill up; abandoned tasks stay on staging for ever and staging drifts from the base branch for good.
- Other shapes considered, and why this one: a direct merge into staging on every ship (skips the
  colleagues' review the team holds to), merging staging into the task branch (carries untested work into the base branch),
  a release from staging (two meanings for one command). This one keeps the team's own practice
  and puts Jig where the practice has no guard today.

## Scope and non-goals

- In scope:
  - `git.flow` with the flows `direct` and `staging`, the bricks' keys (`git.staging_branch`,
    `git.staging_land`, `git.staging_review`, `git.promote_merge`), and the offer in `jig init` /
    `jig-setup`.
  - `jig task ship` in a staging project: commit, push the task branch, open a pull request into
    staging for colleagues' review; no pull request into the base branch yet.
  - Landing the pull request on staging: merged on the forge when it merges cleanly, a direct merge
    into staging only when it conflicts; without an approval, by `staging_review`: Jig warns and
    asks whether to merge without review or wait (`ask`), waits (`require`), or lands without
    asking (`none`). With `staging_land: external` CI lands the task and Jig only reads it.
  - "Prepare for prod" for one task, for several named with `--commit <sha> <id>…`, or for all
    with `--all`, each handled on its own: refuse unless the task is on staging and not behind it, bring
    the base branch in on conflict, open the pull request into the base branch, print its link. `promote_merge` decides who
    merges it.
  - Staging state in `jig task list --json`, `jig status` and housekeeping: on staging, behind
    staging, promoted; a pull request merged into staging is no longer `wrong-base`.
  - Autopilot asks at an unapproved staging pull request (unattended: stops, parked with
    reason `review`) and stops after it lands (parked with reason `signal`); it never approves and never promotes.
  - Drift report: tasks on staging that nobody promoted for long, and staging work no live task owns.
- Not doing:
  - Jig UI's card move (another developer's project). It is feasible: "prepare for prod" is a
    script command the UI can run itself, and an agent is needed only when the base branch conflicts.
    Jig delivers the command, its exit codes and the staging state the UI reads.
  - Resetting or rebuilding the staging branch from the base branch.
  - A batch release from staging (see Decisions).

## Decisions

### Flow model (2026-11-07)

The staging step is not built as a one-off mode but as the second of a small catalogue of named
git flows a project picks from.

Terms used throughout this spec: the **base branch** is the branch `git.base_branch` names —
`main` or `master`, whatever the project uses; the **staging branch** is the branch
`git.staging_branch` names — `stage`, `staging` or another; "staging" alone, as in "on staging" or
"merged into staging", is short for the staging branch. The flow is called `staging` whatever the
staging branch is called.

The decisions below this subsection were made before the catalogue and still hold for the `staging` flow; where one is changed here, it says so.

- **Jig's own mechanics are not part of any flow** and are the same in every one: the task
  branch `task/<id>` with its fork point and recorded base (ADR-0026, ADR-0039); Jig's planning
  branches `spec/<id>`, `epic/<id>`, `finish/<id>`, `close/<id>`; landing detected by ancestry
  and the forge, with `wrong-base`; deleting a branch once its work landed; `agent.git` as the
  person's rights (a flow says which steps exist, `agent.git` how far the agent takes them on its
  own); closing a task once its work is in the final branch; release tags made by CI (ADR-0034).
- **A flow is assembled from five bricks**:
  - `base_branch` — where a task is cut from and where its work is final. It is today's
    `git.base_branch`, which `jig init` already reads from the remote's default branch (else
    `main` or `master`); no flow adds a key for it;
  - `staging_branch` — one intermediate branch a task lands on before the base branch, or none;
  - `staging_land` — how a task lands on the staging branch: `pr` (a pull request, merged directly into the
    staging branch only when it conflicts) or `external` (CI merges into the staging branch; Jig only reads it);
  - `staging_review` — whether an approval is needed before landing on the staging branch: `ask` (warn and
    ask, the decision below), `require` (wait for an approval, as an unattended run does) or `none`
    (land without asking);
  - `promote_merge` — who merges the pull request into the base branch that "prepare for prod" opens:
    `human` (Jig stops at the link) or `auto` (the forge merges it on green CI).
- **Two named flows ship**: `direct` — a task goes straight to the base branch, today's Jig and
  the default; and
  `staging` — the base branch plus a staging branch, defaults `staging_land: pr`, `staging_review: ask`,
  `promote_merge: human`. The
  shared `.ai/config.yaml` names one with `git.flow`; `staging` needs `git.staging_branch` (the
  branch name is the team's — `staging` in the human's project), and any brick may be overridden
  under `git.`, the rest coming from the flow. `jig init` and `jig-setup` describe both in plain
  words and offer `staging` when origin has a `stage`/`staging` branch. This changes the decision
  below that named `git.staging_branch` alone as the switch: it is now the flow's parameter.
- **The flow knows nothing about QA.** Promotion waits for a signal from outside Jig — a person's
  word or a green CI run — whoever gives it. A task waiting at the staging branch has one state, *parked*, whose reason Jig derives from git and the
  forge (its staging pull request waits for review, or it is on the staging branch and waits for the signal).
  It is not the current task and holds no queue or concurrency slot, as decided below for both.
- **Parked is derived from the branch and its pull requests alone, never written**, the way
  remote merge state is today: a task is parked when its branch `task/<id>` has an open pull
  request into the staging branch or is contained in the staging branch, and it has no pull
  request into the base branch yet. Task status and `agent.git` are local to one checkout, so
  neither is part of it. The reason anyone can read is `review` (the staging pull request is still
  open) or `signal` (the task is on the staging branch and waits for "prepare for prod"). The
  owner's checkout adds what only it knows: the hint `landing` (the pull request may land, but
  the person's `agent.git` is below `merge`, so the person lands it), and that a task resumed for
  a fix is `active`, not parked. A colleague, a CI runner and a UI read that task as parked until
  the fix ships; that is accepted, since only the owner's workspace knows the work has resumed.
  Parking ends in one of two ways: `jig task resume <id>` makes the task `active` for a fix, which
  ships to the staging branch again and parks again; or "prepare for prod" opens the pull request
  into the base branch, and the task leaves the staging side of the flow and is judged as any task
  with an open pull request is today. Unlike a pause, which a person writes in one checkout,
  parking is read from git and the forge, so a colleague, a CI runner and a UI see the same state
  and the same shared reason.
- **`promote_merge: auto` is a merge, deferred.** Jig does not merge; it switches on the forge's
  auto-merge, and the pull request into the base branch merges itself on green CI. In a person's checkout
  switching it on needs `agent.git: merge`, the same rule as landing on the staging branch; below it Jig
  opens the pull request and says auto-merge was not switched on and why. On a CI runner, which
  has no `agent.git`, the flow's setting decides: the team put the token in the pipeline and chose
  `auto`. A promotion that raises the declared version is a release
  (`20261026-a-task-that-raises-the-version-is-a-release`), and `promote_merge: auto` never applies
  to it, in a checkout or on a CI runner: `release.merge` is local-only, so a runner never has it,
  and a guard that exists in one place only is none. Jig opens the pull request, switches nothing
  on and says the merge is a person's; a `major` release opens as a draft whose body starts with
  `Needs a human: major release?`, as that ADR requires. Rejected:
  `auto` from the shared config with no `agent.git` read — one shared key would hand every
  developer's agent the right to merge into the base branch, which `agent.git` keeps personal on purpose;
  `auto` on CI only — a team that promotes by hand but wants auto-merge would lose it.
- **A CI run promotes the tasks it names, or all of them only when told.** "Prepare for prod"
  takes the tested staging commit and task ids (`--commit <sha> <id>…`); each is refused unless its
  tip is contained in that commit, the id coming from the branch name `task/<id>`. `--all`
  promotes every `task/*` branch contained in the commit and not yet in the base branch — for a team whose
  green CI is the test, written into its pipeline once and on purpose. Rejected: all by default —
  one build that happened to go green would send everything on the staging branch to production; names
  only, with no `--all` — an automated team would have to build the list in its pipeline, and a
  bug in that script is no safer.
- **A dependency still on the staging branch is warned about, never refused** (failure mode 4). The queue
  that holds dependencies is `.ai/runtime/queue`, local to the checkout that filed them, so only
  that checkout can see one. There, "prepare for prod" for a task whose queue dependency is on the
  staging branch but not in the base branch still opens the pull request, prints which task it depends on and that
  it should go with it or after it, and puts the same line in the pull request body for the
  merger. On a CI runner there is nothing to check, and the documentation says so: a team that
  cares names the tasks together or uses `--all`. Rejected: refusing — it holds a task hostage
  to one that may be waiting on purpose or a dependency gone stale, and it would guard only one
  checkout; doing nothing — the risk is real and a warning costs little.
- **A stale promotion is refreshed by running it again** (failure mode 9). "Prepare for prod" on
  a task that already has an open pull request into the base branch opens no second one: it merges the base branch
  into the task branch again, pushes, and prints the same link. In the owner's checkout,
  `jig status` and housekeeping mark an open promotion pull request the forge reports as
  conflicting with the base branch and say to run "prepare for prod" again. Nothing watches in the
  background. Rejected: doing nothing — the forge shows the conflict, but the developer learns of
  it only when the merger tells them; re-checking every other open promotion after each one — the
  command would answer for other people's pull requests, and a checkout sees only its own tasks
  (failure mode 3), so the picture would be partial anyway.
- **A release stays a choice of the work, not of the project.** A spec whose parts are useless
  apart gets an epic (ADR-0040, `jig-release`) in either flow: its tasks are cut from and land on
  `epic/<id>`, and the epic reaches the base branch once. Small work keeps its own rhythm meanwhile, and a
  hotfix is an ordinary task from the base branch.
- Rejected:
  - a flow engine — branches and transitions declared in config and interpreted by Jig: a
    description language in bash 3.2 that every command reads, an order of magnitude more
    combinations to test, and flows designed for teams nobody has met;
  - bricks as independent keys with no named flows: many combinations mean nothing, and the
    person assembles a flow instead of choosing one;
  - documentation only, describing the flows: that is today, with the staging step done by hand;
  - a `release-train` flow for the whole project (every task cut from `release/next`): it needs
    a hotfix path, a back-merge into the train and a rule for cutting the next one, repeats what
    an epic already does, and no real team has asked for it. It can be added later as a third
    named flow on the epic mechanism; nothing here closes that door;
  - more than one staging branch (`dev → stage → prod`): the brick allows it, no team has asked for it;
  - the name `github` for the default flow: it would read as wrong in a GitLab project, and Jig
    serves both forges.

- Staging is an option of a project, not the default flow: a project without it is unchanged.
- "Tested on staging" is a signal from outside Jig — a QA person's word, or a staging pipeline
  that went green — given as the "prepare for prod" command; Jig never promotes a task to the base branch
  on its own judgement. Both kinds of team are served by one mechanism: a team where people
  decide, and a team where CI/CD tests staging and promotes by itself.
- "Prepare for prod" runs from git alone, so a CI job can run it: the task branch, the staging
  branch, the base branch and the forge — never the developer's gitignored workspace, which a CI runner
  does not have. Local task state (consolidation, the queue) catches up on the developer's next
  `jig status` / housekeeping, as it does for any merge today.
- The signal names the staging commit that was tested. The command refuses when the task branch
  tip is not contained in that commit: a fix pushed after the test run must not reach the base branch
  untested. A person who says "prepare for prod" by hand means the staging tip as they see it.
- In a team where people decide, the signal never reaches Jig directly: QA posts it where the
  team talks (a Slack message), and the developer tells their agent "prepare for prod". Those
  words are the signal; the agent runs the command. Jig reads no chat. A message the agent
  reads through a connector (a Slack MCP) is not a signal by itself — the person still says it,
  so a message nobody relayed never promotes a task. The person's word is taken against the
  staging tip with no further check: QA gives it only after the fixes and the talks with the
  developer and the product owner are done. Rejected: warning when the task landed on staging
  recently — it second-guesses a decision QA has already made.
- The direct merge, when a conflict calls for it, runs in a temporary worktree of the staging
  branch, fetched fresh from origin, never in the developer's checkout (failure mode 5); a rejected push is retried from a fresh
  fetch, never forced (failure mode 6).
- Colleagues' review is the team's usual step, not a rule: not every task goes through it. Before
  either merge into staging, Jig reads the pull request's approval from the forge. Approved — it
  merges. Not approved, or the forge cannot say (no `gh`/`glab`, no forge) — it warns and asks
  the person: merge without review, or wait for review. Waiting leaves the task parked with
  reason `review`. An unattended run, with nobody to ask, waits. Rejected: refusing an unapproved pull
  request — it blocks the tasks the team deliberately ships without review; merging without a
  word — the review the team relies on for most tasks would be skipped unseen. *Changed by the
  Flow model:* this is `staging_review: ask`, the default; the rejections are of those behaviours
  as the default, and a team that wants them sets `require` or `none` on purpose.
- The agent resolves any conflict with staging, its task's files or not, and pushes — what the
  team's people do by hand today; QA checks staging. The resolution is named in the ship report
  and in a comment on the pull request. Rejected: stopping on conflicts in code the task does
  not own (failure mode 2) — the team accepts that risk on staging already.
- A parked task (two states when first decided, one since the Flow model) has a state of its
  own: it is not the current task, does not
  hold `jig queue next` or a concurrency slot, and `jig status` lists it on its own line
  (failure mode 10). `jig task resume <id>` brings it back to work — for a fix QA asked for, or to
  answer a reviewer; a commit cannot be the trigger, since the work has to be resumed before
  anything is committed. Rejected: a plain pause — the UI and
  `jig status` could not tell a parked task from any other pause.
- A task QA rejects is fixed in the same task and shipped to staging again — as a new pull request
  into staging, reviewed like the first. The fix takes implement, a review of what changed since
  the last review (the re-review Jig already has), verify, ship — not the whole route again; Jig takes nothing off
  staging and has no "unstage" command. Failure mode 7 (a revert leaves a task "on staging") is
  accepted: the team does not revert on staging.
- The work is built on an epic, `epic/staging-branch`, and released once as a `minor` version:
  the mode is off until `git.flow` names `staging`, so nothing changes for existing projects, and
  the human wants the staging flow to arrive whole rather than a staging step without its promotion.
- Everything shared — on staging, behind staging, the drift report, the state a UI reads — is read
  from git and the forge by branch name (`task/<id>`), never from one checkout's workspace
  (failure mode 3). The workspace adds what only its owner knows; it is never required.
- A task reaches staging through a pull request into staging. `jig task ship` opens it from the task
  branch; it is merged on the forge. Only when the pull request conflicts with staging is the task
  merged into staging directly: the task branch merged
  into staging, the conflict resolved there, staging pushed. The forge then shows the pull request
  as merged, since its head is in staging, so it stays in the history with whatever review it had.
  The resolution is a commit on staging; the task branch is never touched, so it reaches the base branch with
  its own work only. Rejected: a direct merge on every ship — it skips the review the team holds
  to; merging staging into the task branch to clear the conflict — it would carry other tasks'
  untested work into the base branch; a throwaway `stage/<id>` branch with a second pull request — a
  second review of the same change, with one more branch to clean up.
- The staging branch is named in the shared `.ai/config.yaml` as `git.staging_branch`, the
  `staging` flow's parameter (Flow model); the flow is off unless `git.flow` names it. `jig init` and `jig-setup` look for a `stage`/`staging` branch on origin and offer to turn
  it on; the agent writes the key after a yes. Rejected: turning it on whenever such a branch
  exists — some projects keep a branch by that name for something else.
- "Prepare for prod" works on one task: it opens that task's pull request into the base branch, merging
  the base branch into the task branch first when they conflict (the base branch holds only released work, so
  nothing untested comes with it), and returns the link. Batching is the merger's choice, not
  Jig's: QA may signal several developers at once, each prepares their own pull request, and the
  person who deploys merges all of them or one at a time. Rejected: making it `jig-release` —
  a release today plans tasks not yet started and cuts them from an epic, while a staged task is
  started and cut from the base branch; the command would mean two different things by project setting,
  and the team does not version a batch anyway. `jig-release` stays as it is. *Changed by the Flow
  model:* a run may name several tasks or use `--all`; each is still handled on its own, with a
  pull request of its own, and merging them together or apart stays the merger's choice.
- Whether a task is on staging is derived from git, not stored (ADR-0005): its branch tip is
  contained in origin's staging branch. A task with commits of its own after that — a fix QA asked
  for — is "behind staging", and shipping it again merges the new commits in the same way. Merges
  of the base branch into the task branch — at promotion — are not the task's own commits and do not make
  it behind (failure mode 7): otherwise a task reads "behind" the moment it is promoted, and a
  second "prepare for prod" refuses it.
- Who may land a task on staging follows `agent.git`, with staging treated like any shared branch:
  merging the pull request on the forge and the direct merge pushed to staging both need level
  `merge`. Below it, `jig task ship` opens the pull request into staging and stops, saying the task
  is not on staging yet; the person lands it. The task is parked with reason `signal` only once git shows it
  on staging — never because the ship step ran. Rejected: letting `push` cover the direct merge —
  a push to a branch the team shares is a merge in effect, not the task's own push.
- The knowledge decision (ADR-0030) is recorded before the task's first ship to staging, since
  that is the first commit others build on; each later ship — a QA fix, the merge of the base branch at
  promotion — may revise it. The task closes, as today, once its work is in the base branch.
- The drift report counts only what staging has and the base branch does not: a promoted task's branch is
  deleted after it lands, and without that subtraction every promoted task would read as staging
  work no task owns.

## Open questions

- An epic in a `staging` project: whether each epic task goes through the staging branch, or the epic as a
  whole before its final pull request into the base branch. Left until a real epic meets a staging branch.

## Assumptions left untested

- Pushing a merge that contains a pull request's head into its base marks the pull request as
  merged — true of GitHub as far as known; not checked for GitLab, where it may stay open and
  need closing with a note.
- The team's staging branch accepts direct pushes — taken from the human's account of their
  practice; tested by the first phase-1 run against a real project.
- Agents resolving staging conflicts in others' code cause no more harm than people doing it by
  hand today — taken at normal depth; tested by the regressions QA reports in the first weeks.
- A CI runner can run Jig's promote command (bash, git, `gh`/`glab`, forge token) — not checked
  against any real pipeline.
- The forge has auto-merge enabled, a repository setting on GitHub, which `promote_merge: auto`
  relies on — not checked against any real project; without it Jig should say so and stop at the
  link.
