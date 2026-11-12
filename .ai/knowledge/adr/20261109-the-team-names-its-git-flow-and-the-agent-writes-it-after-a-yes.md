---
id: adr-20261109-the-team-names-its-git-flow-and-the-agent-writes-it-after-a-yes
type: adr
status: accepted
date: 2026-11-09
domains:
  - config
  - install
paths:
  - skills/jig-setup/SKILL.md
  - scripts/lib/config.sh
  - scripts/lib/doctor.sh
  - scripts/lib/init.sh
  - templates/config.yaml
summary: Why a project's git flow is a shared setting, why the agent writes it into .ai/config.yaml after a person's yes and no script does, and how that narrows ADR-0038.
reviewed_at: 2026-11-12
---
# A project names its git flow in the shared config, and the agent writes it there after a yes

## Context

A team that tests on a shared staging branch did that step by hand, outside Jig. The staging-branch specification, removed once the epic that built it was released, made it the second of a small catalogue of named git flows, chosen per project; the flow model it chose, and what it rejected, are kept in the amendment below. The first thing that needs is a place to say which flow a project uses, and a way to turn it on.

The specification says `jig init` and `jig-setup` find a `stage` or `staging` branch on origin, offer the flow, and "the agent writes the key after a yes". ADR-0038 says the opposite of `.ai/config.yaml`: it is "the team's, changed by hand and reviewed like code", and `jig-setup` never wrote it. The person who owns both decided for the specification on 2026-11-09.

## Decision

- **A flow is a project setting.** `git.flow` (`direct`, the default, or `staging`) and its bricks `git.staging_branch`, `git.staging_land`, `git.staging_review`, `git.promote_merge` and `git.staging_stale_after` are project keys, outside `JIG_CFG_LOCAL_KEYS`. By ADR-0023's test the answer is the same for every contributor: two people on one project cannot have different roads to the base branch.
- **The agent writes the choice into `.ai/config.yaml`, after a yes, and only in `jig-setup` §4.** It shows the line or lines, and after a yes starts a task first, because `jig task start` refuses a tree with tracked changes, adds them in that task's tree and ships them to a pull request. What ADR-0038 protects holds: the file still changes as a diff a colleague reviews. This narrows ADR-0038 to this one case and is the named exception to the rule that skills reference `jig <command>` rather than describe a file operation.
- **No script writes it.** `jig config set` still refuses without `--local`, and no project-file counterpart exists. `jig init` advises and never prompts (ADR-0024). ADR-0024's amendment of 2026-10-10 is the precedent, though it covers only the person's own `settings.local.json`: a rule that a human pastes binds Jig's scripts, not the person's agent acting on their yes.
- **Scripts find and check.** `jig_staging_offer` reads refs only, never the network, and answers nothing once the file names a flow, `direct` included: answering `direct` writes `git.flow: direct` so the team is not asked again. `jig_git_flow_problems` names what cannot work, and `jig doctor` fails on it. A project on `direct` with no such branch sees no new output anywhere.

## Alternatives

- **The agent never writes; Jig prints the lines and the person pastes them.** Keeps ADR-0038 whole. Rejected by the person: the specification had already decided for the agent, and nothing is lost, since the change is reviewed in a pull request either way.
- **`jig config flow`, a command that writes the project file.** Validates the write in one place, and adds a project-file writer ADR-0038 said would not exist, for a two-line edit. `jig doctor` checks the result instead.
- **Turning the flow on whenever a `stage` or `staging` branch exists.** Rejected in the specification: a branch of that name may be for something else.
- **Describing the flows in every `jig init`.** A project with no such branch would read about a flow it has no use for.

## Consequences

- A project whose origin has a `stage` or `staging` branch gets a `jig doctor` warning, and a line from `jig init`, until someone names a flow. That is the offer; `git.flow: direct` ends it.
- `git.staging_land: external` and the `staging` flow are accepted now and do nothing until later items of the same epic. The epic is released once, so no release carries them unbuilt. The task staging-land-external built `external`: Jig reads what CI merged into the staging branch from git alone, with no pull request, and the ship files the triage task for open P2/P3 there.
- `jig status` prints a `flow:` line off the `direct` flow: the staging branch and how many live tasks are on it and behind it, or why the flow cannot be used (adr-20261112-the-staging-drift-report-is-read-from-git-by-branch-name follows it with its `staging:` lines). On `direct` it prints none.

## Amendment (2026-11-12): the flow model, and what it rejected

The staging-branch specification is removed when its epic is released (ADR-0035 asks for its
decisions to be knowledge first). Its flow model is this:

- **A small catalogue of named flows, built from bricks.** A flow is assembled from five bricks —
  `base_branch` (where a task is cut from and its work is final; today's `git.base_branch`),
  `staging_branch` (one intermediate branch, or none), `staging_land` (`pr` or `external`),
  `staging_review` (`ask`, `require` or `none`) and `promote_merge` (`human` or `auto`) — and the
  project names one of the flows that ship: `direct`, the default and Jig as it was, and `staging`.
  A person chooses a flow, not a combination; any brick may be overridden under `git.`.
  `git.staging_stale_after` is a setting of the staging flow's drift report, not a brick.
- **Jig's own mechanics belong to no flow**: the task branch and its recorded base, Jig's planning
  branches, landing read from ancestry and the forge, `agent.git` as the person's rights, closing a
  task once its work is in the final branch, release tags made by CI.

Rejected:

- **A flow engine** — branches and transitions declared in config and interpreted by Jig: a
  description language in bash 3.2 that every command reads, an order of magnitude more
  combinations to test, and flows designed for teams nobody has met.
- **Bricks as independent keys with no named flows**: most combinations mean nothing, and the person
  would assemble a flow instead of choosing one.
- **A `release-train` flow** for the whole project (every task cut from `release/next`): it needs a
  hotfix path, a back-merge into the train and a rule for cutting the next one, repeats what an epic
  already does (ADR-0040), and no team has asked for it. It can be added later as a third named flow
  on the epic mechanism; nothing here closes that door.
- **More than one staging branch** (`dev → stage → prod`): the brick would allow it; no team has
  asked for it.
- **`github` as the default flow's name**: it reads as wrong in a GitLab project, and Jig serves
  both forges.

The task that turns the flow on (or off), as the second bullet of the Decision describes, ships its
pull request into the base as on the direct flow, rather than being refused for differing from the
base
(adr-20261111-in-the-staging-flow-a-task-ships-into-the-staging-branch, amendment of 2026-11-12).
