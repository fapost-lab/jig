# Roadmap — Git flows

Destination: a project picks its git flow from a short catalogue; in the `staging` flow a task
goes from the base branch to the staging branch through a pull request, warned when nobody approved it, is
parked there without blocking other work, and reaches a pull request into the base branch on one "prepare
for prod" — said by a person or run by CI — while a project on the default `direct` flow works
exactly as before.

Epic: epic/staging-branch
Release: minor

## Phase 1 — Ship to staging

Goal: Jig does the staging step the team does by hand today, and everyone sees which tasks are on
staging. Done when: in a test project with `git.flow: staging` and `git.staging_branch: staging`, `jig task ship` opens a pull
request into staging, the pull request lands on staging — merged on the forge, or merged directly when
it conflicts — and `jig status` shows the task on staging, with no pull request into the base branch.

- [x] `choose-git-flow` — Choose a flow — `git.flow: direct | staging` in the shared config with the bricks'
  defaults and overrides (`staging_branch`, `staging_land`, `staging_review`, `promote_merge`); `jig init`
  and `jig-setup` describe both flows in plain words and offer `staging` when origin has a
  `stage`/`staging` branch; `direct` stays the default.
- [x] `ship-to-staging` — Ship a task to staging — `jig task ship` in a staging project opens the task's pull request
  into staging for review; no pull request into the base branch. (after: Choose a flow — it reads the key)
- [x] `land-on-staging` — Land a task on staging — merge the pull request on the forge; when it conflicts, merge the
  task branch into a fresh temporary worktree of staging, resolve, push (retried from a fresh fetch
  on rejection, never forced); without an approval, warn and ask: merge without review or wait
  (unattended: wait), by `staging_review` — `ask` as here, `require` always waits, `none` lands
  without asking; below `agent.git: merge`, stop at the open pull request. (after: Ship
  a task to staging — it lands that pull request)
- [x] `staging-state` — See a task's staging state — on staging / behind staging (own commits only, merges of the base branch
  excluded) derived from git by branch name, in
  `jig task list --json`, `jig status` and housekeeping; a pull request merged into staging is no
  longer `wrong-base`. (after: Choose a flow — it reads the key)

## Phase 2 — Prepare for prod

Goal: one command takes a tested task to a pull request into the base branch, from a person's checkout or
from a CI job. Done when: run on a runner with no Jig workspace and given a tested staging commit,
it opens the pull request into the base branch and prints its link, and it refuses a task whose tip is not
in that commit; a task waiting on staging is listed as parked and holds no slot.

- [ ] `park-at-staging` — Park at the staging branch — one state, *parked*, with its reason derived from git and the forge
  (`review` while the staging pull request is open, `signal` once the task is on the staging branch; the owner's checkout adds `landing`);
  it frees the current-task slot and the queue; `jig task resume` brings the task back; autopilot
  stops there, never approves and never promotes. (after: Land a task on staging — parking starts
  and ends at its steps)
- [x] `prepare-for-prod` — Prepare a task for prod — refuses unless the task tip is in the tested staging commit;
  merges the base branch into the task branch on conflict; opens the pull request into the base branch; prints the
  link — run again on a task already promoted, it merges the base branch in afresh and prints the same
  link instead of opening a second one; needs only git and the forge, and where the checkout has a queue it warns — in the output
  and the pull request body — of a dependency on the staging branch but not in the base branch. (after: See a task's
  staging state — the refusal is that check)
- [ ] `merge-promotion` — Merge the promotion by the flow — `promote_merge: human` stops at the link, `auto` switches
  on the forge's auto-merge so the pull request merges on green CI — in a checkout only at
  `agent.git: merge`, on a CI runner by the flow alone, and never for a promotion that raises the
  version, which stays a person's merge (a `major` one a draft). (after: Prepare a task for prod — it merges the pull request that item opens)

## Phase 3 — Staging over time

Goal: staging stays explainable as tasks come and go, and a fully automated team can drive it.
Done when: `jig status` names tasks on staging nobody promoted for long and staging work no task
branch owns.

- [ ] Staging drift report — tasks on staging long unpromoted, staging commits that are not in
  the base branch and come from no live `task/*` branch, and the checkout's open promotion pull requests
  the forge reports as conflicting with the base branch, with "run prepare for prod again". (after: See a task's staging state — the report is built on it; after: Prepare a task for prod —
  it reports the pull requests that item opens)
- [x] `staging-land-external` — Staging landed by CI — `staging_land: external`: Jig opens no pull request into the staging branch and
  merges nothing there, and reads from git which tasks CI merged in. (after: See a task's staging
  state — it is the only thing Jig does on the staging branch then). The key exists from Choose a flow;
  `external` works only from here, harmless in an epic released once.
- [ ] `promote-from-ci` — Promote from CI — "prepare for prod" given the tested staging commit promotes the task ids it
  names, or with `--all` every `task/*` branch contained in that commit and not yet in the base branch.
  (after: Prepare a task for prod — it runs that item's command once per task)

## Waves

1. Choose a flow
2. Ship a task to staging; See a task's staging state
3. Land a task on staging; Prepare a task for prod; Staging landed by CI
4. Park at the staging branch; Merge the promotion by the flow; Promote from CI; Staging drift report

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
- A wave entry names an item by its title (the text before its first ` — `) or its task id,
  entries separated by `;` — `jig spec plan` reports an entry that names no item or several.
-->
