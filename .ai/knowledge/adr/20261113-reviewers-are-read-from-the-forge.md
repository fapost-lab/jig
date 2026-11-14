---
id: adr-20261113-reviewers-are-read-from-the-forge
type: adr
status: accepted
date: 2026-11-13
domains:
  - task
paths:
  - scripts/lib/reviewers.sh
  - scripts/lib/pr.sh
  - scripts/lib/task.sh
  - scripts/lib/land.sh
  - scripts/lib/common.sh
summary: Why an approval waits for every reviewer the forge records as requested, why jig task ship --reviewer resolves people (never teams) against the forge before the push, and why reviewer candidates are read from the forge's recent reviews, never a setting, by the one --json read that asks the forge.
reviewed_at: 2026-11-13
---
# Reviewers are read from the forge, requested by the ship, and an approval waits for each of them

## Context

On the staging flow a task's pull request lands once it is approved
(adr-20261111-a-task-lands-on-staging-through-its-pull-request). In a team project two reviewers were
requested, one approved, and Jig read the pull request as approved and offered to merge it: without
branch protection GitHub's `reviewDecision` is empty, and one `APPROVED` in `latestReviews` decided;
on GitLab one entry in `approved_by` did. The reviewers a person asked for were never consulted.
Nor could Jig ask for them: the person added reviewers by hand after `jig task ship` opened the pull
request. The owner rejected a setting listing the people who review: a big team is too many names
to keep, and who reviews changes from one landing to the next.

## Decision

- **An approval waits for every requested reviewer.** `jig_pr_approval_v` (common.sh) answers
  `changes` when anybody's latest review asks for changes, whatever else holds; `waiting` with the
  names when a reviewer the forge records as requested has not answered — GitHub's `reviewRequests`,
  people and teams, even under an `APPROVED` decision; GitLab's `reviewers` of the merge request not
  in `approved_by` — or, on GitLab, when somebody approved and `approvals_left` is above zero;
  `approved` only then; `none` when nobody approved. Who was requested is the forge's record, however
  they got there. GitHub drops a request once its reviewer submits any review, a comment included:
  that is what "answered" means there, and Jig does not read the timeline to second-guess it.
  `_land_approval_gate` names whom it waits for.
- **The ship requests reviewers it is given.** `jig task ship <id> --reviewer <login|name>`,
  repeatable, requests them on the pull request the ship opens (`gh pr create --reviewer`,
  `glab mr create --reviewer`). A value is resolved before the push against everyone the repository
  may ask (GitHub `assignableUsers`, GitLab `members/all`, read page by page and matched here, since
  free text on gh's command line does not survive Git Bash): a login as it is, any case; otherwise a
  part of a login or name must fit exactly one person; several are refused naming each, none is
  refused, a value with `/` (a team) is refused — a team is satisfied by one member's review, which
  is not what a person who named reviewers asked for. The account that opens the pull request is its
  author and is left out, said. Nothing is requested on a pull request that was already open, below
  `pr`, under `git.staging_land: external` or without a forge, and the ship says so. The promotion's
  pull request (`jig task promote`) requests nobody.
- **Candidates are read from the forge, never kept.** `jig pr reviewers [--base <branch>] [--json]`
  (lib/reviewers.sh, shared by pr.sh and task.sh) lists who reviewed the last 30 merged pull requests
  into the branch — the staging branch on that flow, else the base — most frequent first, each counted
  once per pull request, never its author, a bot or someone the repository may no longer ask; with no
  such history, everyone it may ask. The agent offers the first three or four as the options of one
  question before an attended ship onto staging; an unattended run asks nothing and requests nobody.
- **The one read that asks the forge.** `jig pr reviewers --json` is a `--json` read whose subject is
  the forge, so it asks it, unlike every other read
  (adr-20261015-a-read-is-one-json-envelope). It is refused as `forge-unavailable` when the forge
  cannot be asked. A program calls it when a person is about to choose, never on a timer.

## Alternatives

- **A setting with the team's reviewers.** Rejected by the owner: too many names in a big team, a
  list that goes stale, and the choice belongs to each landing.
- **Teams as reviewers.** One member's review clears a team's request, so a team would read answered
  while the people the person meant had not looked.
- **Candidates in the forge cache, written by housekeeping.** Keeps every read offline, but costs
  every housekeeping run forge calls for a list asked for only at a ship, and is as old as the last
  run when someone was just added.
- **`waiting` read as `none`.** Loses whom the gate waits for, which is what the person needs to hear.

## Consequences

- An approval on a pull request with an unanswered request no longer lands: under `ask` the person
  is asked, under `require` and unattended it waits.
- `jig pr reviewers --json` is the exception to "a read never touches the network"; schemas/json.md
  names it, with its failure code.
- Adding reviewers to a pull request already open, and offering it from a UI, are left to the task
  that builds those actions on `jig_pr_approval_v` and lib/reviewers.sh.

> **Amendment (2026-11-14).** Adding reviewers to an open pull request is `jig task request-review <id> --reviewer <login|name>...`, resolved by the same functions as the ship; on GitLab each login is added with `+` (adr-20261114-a-persons-pull-request-action-does-not-read-agent-git).
