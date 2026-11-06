# Staging branch — a task is tested on a shared stage before it reaches main

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

## Goal and problem

- Who is worse off without this, and how: a team that tests on a shared stage environment before
  production. Jig knows only one place a task lands — `main` or an epic — so the stage step is
  done by hand outside it: nothing records that a task is on stage, nothing stops its pull request
  into `main` from being merged before QA, autopilot and `agent.git: merge` would take it straight
  to `main`, and a pull request merged into stage reads as `wrong-base` (ADR-0039).
- What is true when the work is done: in a project that names a stage branch, a task is cut from
  `main`, shipped to stage, fixed there as often as QA needs, and promoted to `main` on one
  command — "prepare for prod", said by a person or run by CI — which opens the pull request,
  brings `main` in when it conflicts, and returns the link. A project without a stage branch works exactly as today.

## Stress test

- Hidden assumptions — "this holds only if …":
  - … stage is never rebuilt, squashed or reverted: "on stage" is ancestry, and a task reverted
    on stage after QA rejected it still reads as on stage.
  - … tasks on stage are independent: stage is never merged into `main`, so a task tested with
    another one present can reach production without it.
  - … the stage branch accepts a direct push: a team that protects stage gets no stage step.
- The main trade-off: the task branch stays clean (only its own work reaches `main`) at the price
  of shipping a combination nobody tested — stage's conflict resolutions stay on stage, and the
  pull request into `main` is a second merge.
- The weakest point: what QA tested is not what reaches production. It is the stage model
  itself, not Jig's, and Jig can only narrow it: the promotion pull request's CI against `main`
  is the one check of the shipped combination.
- Failure modes — cause, what breaks, the signal that shows it (independent failure hunt, ranked
  by likelihood times cost):
  1. Tested ≠ shipped — conflicts resolved on stage never reach the task branch, and the merge
     of `main` at promotion is a new, untested resolution. "Worked on stage" bugs in production;
     the stage merge's diff differs from the pull request's.
  2. An agent resolves conflicts on stage against code it does not own, pushed with no review
     and no CI. Regressions in other developers' tasks on stage; blame leads to a stage merge
     commit from someone else's task.
  3. Task state is per checkout: the drift report and a card move run by the merger or QA see
     only their own tasks. Colleagues' work reads as orphaned; "unknown task" on the card action.
  4. Dependent tasks promoted one at a time — B was tested with A present, reaches production
     without A. A production failure stage cannot reproduce (a missing migration or API).
  5. The stage merge in the developer's own checkout: dirty tree, stage checked out in another
     worktree, a merge left mid-conflict, HEAD left on stage. Later commits land on stage;
     `MERGE_HEAD` left behind.
  6. Races on the shared branch: several developers and autopilots push stale stage copies;
     protected stage refuses outright; interleaved deploys. Non-fast-forward rejections on ship.
  7. Ancestry lies: a reset of stage makes every task vanish; a revert keeps a rejected task
     "on stage"; the merge of `main` at promotion makes a task read "behind stage". Promotion
     refused right after it succeeded; reverted features shown ready.
  8. `agent.git: push` covers a push to a shared branch as if it were the task's own. Surprise
     pushes to stage; at `commit`, tasks wait for QA that were never deployed.
  9. Promotion pull requests go stale while the merger works through them one by one. Links
     already handed out lead to pull requests that now conflict.
  10. Tasks stay open for weeks waiting for QA: the queue, concurrency limits and `jig status`
      fill up; abandoned tasks stay on stage for ever and stage drifts from `main` for good.
- Other shapes considered, and why this one: a pull request into stage (abandoned by the team
  for its conflicts), merging stage into the task branch (carries untested work into `main`),
  a release from stage (two meanings for one command). This one keeps the team's own practice
  and puts Jig where the practice has no guard today.

## Scope and non-goals

- In scope:
  - `git.stage_branch` and its offer in `jig init` / `jig-setup`.
  - `jig task ship` in a stage project: commit, push the task branch, merge it into stage and push
    stage, as far as `agent.git` allows; no pull request into `main` yet.
  - "Prepare for prod" for one task: refuse unless the task is on stage and not behind it, bring
    `main` in on conflict, open the pull request into `main`, print its link.
  - Stage state in `jig task list --json`, `jig status` and housekeeping: on stage, behind
    stage, promoted; a pull request merged into stage is no longer `wrong-base`.
  - Autopilot stops after the stage step with "waiting for QA", never promotes.
  - Drift report: tasks on stage that nobody promoted for long, and stage work no live task owns.
- Not doing:
  - Jig UI's card move (another developer's project). It is feasible: "prepare for prod" is a
    script command the UI can run itself, and an agent is needed only when `main` conflicts.
    Jig delivers the command, its exit codes and the stage state the UI reads.
  - Resetting or rebuilding the stage branch from `main`.
  - A batch release from stage (see Decisions).

## Decisions

- Stage is an option of a project, not the default flow: a project without it is unchanged.
- "Tested on stage" is a signal from outside Jig — a QA person's word, or a stage pipeline
  that went green — given as the "prepare for prod" command; Jig never promotes a task to `main`
  on its own judgement. Both kinds of team are served by one mechanism: a team where people
  decide, and a team where CI/CD tests stage and promotes by itself.
- "Prepare for prod" runs from git alone, so a CI job can run it: the task branch, the stage
  branch, `main` and the forge — never the developer's gitignored workspace, which a CI runner
  does not have. Local task state (consolidation, the queue) catches up on the developer's next
  `jig status` / housekeeping, as it does for any merge today.
- The signal names the stage commit that was tested. The command refuses when the task branch
  tip is not contained in that commit: a fix pushed after the test run must not reach `main`
  untested. A person who says "prepare for prod" by hand means the stage tip as they see it.
- The stage merge runs in a temporary worktree of the stage branch, fetched fresh from origin,
  never in the developer's checkout (failure mode 5); a rejected push is retried from a fresh
  fetch, never forced (failure mode 6).
- The agent resolves any conflict in the stage merge, its task's files or not, and pushes —
  what the team's people do by hand today; stage is a draft, and QA is its check. The
  resolution is named in the ship report. Rejected: stopping on conflicts in code the task does
  not own (failure mode 2) — the team accepts that risk on stage already.
- A task on stage waiting for QA has a state of its own: it is not the current task, does not
  hold `jig queue next` or a concurrency slot, and `jig status` lists it on its own line; a fix
  QA asks for makes it current again (failure mode 10). Rejected: a plain pause — the UI and
  `jig status` could not tell "waiting for QA" from any other pause.
- A task QA rejects is fixed in the same task and shipped to stage again; Jig takes nothing off
  stage and has no "unstage" command. Failure mode 7 (a revert leaves a task "on stage") is
  accepted: the team does not revert on stage.
- The work is built on an epic, `epic/staging-branch`, and released once as a `minor` version:
  the mode is off until `git.stage_branch` is set, so nothing changes for existing projects, and
  the human wants the stage flow to arrive whole rather than a stage step without its promotion.
- Everything shared — on stage, behind stage, the drift report, the state a UI reads — is read
  from git and the forge by branch name (`task/<id>`), never from one checkout's workspace
  (failure mode 3). The workspace adds what only its owner knows; it is never required.
- A task reaches stage by a direct merge, the way the team does it by hand today: check out the
  stage branch, merge the task branch into it, resolve any conflict there, push stage. The
  resolution is a commit on stage; the task branch is never touched, so it reaches `main` with
  its own work only. Rejected: a pull request into stage — the team already abandons it for the
  conflicts; merging stage into the task branch — it would carry other tasks' untested work into
  `main`; a throwaway `stage/<id>` branch with a pull request — the same pull request the team
  abandons, with one more branch to clean up.
- The stage branch is named in the shared `.ai/config.yaml` as `git.stage_branch`; empty means
  off. `jig init` and `jig-setup` look for a `stage`/`staging` branch on origin and offer to turn
  it on; the agent writes the key after a yes. Rejected: turning it on whenever such a branch
  exists — some projects keep a branch by that name for something else.
- "Prepare for prod" works on one task: it opens that task's pull request into `main`, merging
  `main` into the task branch first when they conflict (`main` holds only released work, so
  nothing untested comes with it), and returns the link. Batching is the merger's choice, not
  Jig's: QA may signal several developers at once, each prepares their own pull request, and the
  person who deploys merges all of them or one at a time. Rejected: making it `jig-release` —
  a release today plans tasks not yet started and cuts them from an epic, while a staged task is
  started and cut from `main`; the command would mean two different things by project setting,
  and the team does not version a batch anyway. `jig-release` stays as it is.
- Whether a task is on stage is derived from git, not stored (ADR-0005): its branch tip is
  contained in origin's stage branch. A task with commits after that — a fix QA asked for — is
  "behind stage", and shipping it again merges the new commits in the same way.

## Open questions

- Who merges into `main` in a stage project. Two real teams: in the human's, one person merges
  and runs the deploy, so "prepare for prod" stops at the pull request link; in a fully automated
  team the pull request merges itself on green CI and CD deploys. Today the merge follows each
  person's `agent.git` (a local setting), which cannot express "only the deployer merges" and
  does not exist on a CI runner. Open: a shared project setting for the promote merge (`human` |
  `auto` on green CI), and how it relates to `agent.git` and `release.merge`.
- How a CI job knows which tasks to promote: every task branch contained in the tested stage
  commit and not yet in `main`, or the ones the pipeline names. Decides whether one green stage
  run promotes everything on stage at once.
- In an automated team the stage step may itself be CI's (a pipeline merges task branches into
  stage): whether Jig's stage step must then stand aside and only read what CI did.
- Pushing to stage is a push to a shared branch: which `agent.git` level allows it (`push`
  already, or a level of its own) — decides what an agent at level `commit` does at the stage step.
- Dependent tasks on stage (failure mode 4): whether "prepare for prod" should refuse, or warn,
  when the task's queue dependencies are on stage but not yet in `main`.
- Promotion pull requests that go stale while the merger works through them (failure mode 9):
  whether Jig re-checks them against `main` and says which now conflict.

## Assumptions left untested

- The team's stage branch accepts direct pushes — taken from the human's account of their
  practice; tested by the first phase-1 run against a real project.
- Agents resolving stage conflicts in others' code cause no more harm than people doing it by
  hand today — taken at normal depth; tested by the regressions QA reports in the first weeks.
- A CI runner can run Jig's promote command (bash, git, `gh`/`glab`, forge token) — not checked
  against any real pipeline.
