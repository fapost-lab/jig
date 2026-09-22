---
id: adr-20260922-spec-work-ships-by-the-agent-git-level
type: adr
status: accepted
date: 2026-09-22
domains:
  - spec
  - config
  - skills
paths:
  - scripts/lib/spec.sh
  - scripts/lib/common.sh
  - skills/jig-idea/SKILL.md
summary: Why jig spec ship carries a spec's declaration, epic branch and final pull request as far as agent.git allows, why the git steps are shared in common.sh, and why the release level is recorded when the epic is declared.
reviewed_at: 2026-09-22
---
# A spec's declaration, epic branch and final pull request ship by the same agent.git level as a task

## Context

adr-20260921-agent-git-rights-are-a-local-setting let an agent commit, push and open a pull request
for a task, as far as the clone's `agent.git` allows, and left spec work out on purpose: ADR-0040 still
said "pushing is the human's step" for a freshly cut epic and "the human opens the pull request" for
the epic's final one, and `jig spec epic` and `jig-idea` said so unconditionally. A user who set
`agent.git: pr` got open pull requests for every phase and then three git chores per spec: carry the
spec and its `Epic:` line to the default branch, push the cut epic, open the final pull request.

The final pull request is also the release (ADR-0034 in this repository), and nothing recorded how far
it should raise the version until the moment it was opened, when an unattended run has nobody to ask.

## Decision

- **Same key, same levels, no new setting.** `agent.git: none | commit | push | pr` covers spec work
  cumulatively, as it covers a task: the declaration is committed at `commit`, pushed at `push`, and
  opened as a pull request into the default branch at `pr`; a cut or re-synced epic is pushed at `push`
  and up; the finished epic is committed at `commit`, pushed at `push`, and opened as a pull request
  into the default branch at `pr`. No level merges — not a declaration, not the epic.
- **A separate command, `jig spec ship <id>`**, reads what to ship from the checkout and prints it as
  `mode: declare | epic | final`, never from a flag: the spec here with its `Epic:` line not yet on the
  freshest default branch is a declaration; the line there and the epic cut is an epic to push; the
  spec removed by `--finish` on the epic it declared is the final pull request. `jig spec epic` stays
  local and only names the next step by the level.
- **Each mode refuses what is not its own.** A declaration commits only paths under
  `.ai/specs/<id>/` and never on the default branch: from there it switches to a new `spec/<id>` (the
  human's answer at the gate, 2026-09-22), carrying the working tree and index; it refuses on an
  `epic/*` branch. Pushing an epic commits nothing and refuses a staged index; a push origin moved past
  is refused by git and never forced. The final mode requires the removal staged and rechecks that the
  epic holds the freshest default branch, as `--finish` did, because the default may have moved since.
  At `none` it exits 3, like `task ship`.
- **The git steps live in `common.sh`.** `jig_ship_check_staged`, `jig_ship_commit`,
  `jig_ship_push` and `jig_ship_pr` (GitHub and GitLab, an open pull request reported rather than
  duplicated) are shared by `task ship` and `spec ship`, which may not source each other. `task ship`
  keeps its gates — knowledge decision, findings, receipt, branch — and its behaviour unchanged; each
  command decides which steps to take.
- **The release level is recorded when the epic is declared.** A `Release: patch|minor|major` line
  under `Epic:`, written by `jig spec epic <id> --release <level>` after `jig-idea` asks the human,
  validated by `spec epic` and `spec ship`, and printed by `--finish` as `release: <level>` or
  `release: not recorded`. The version itself stays the project's knowledge: no script reads or
  checks it.
- **What stays the human's at every level:** saying every phase is in (the finish), the release level
  when none was recorded, each leftover of the spec, and merging the final pull request.

This refines ADR-0040 ("pushing is the human's step", "the human opens the pull request into `main`"
now hold at `none`) and closes the consequence adr-20260921-agent-git-rights-are-a-local-setting left
open. Merging the final pull request in an unattended run, and the default level used when no
`Release:` line was recorded, belong to the unattended-mode decision.

## Alternatives

- **Extend `jig spec epic`** with `--ship` or an automatic push when it cuts. Rejected: it mixes a
  spec's local state with the network and the level, and `--finish` is already the most involved
  mode.
- **The skill runs git itself.** Rejected for the same reason as for tasks: the level, the base and the
  checks would be a request to a model.
- **Ship the finish as a task** through `task ship`. Rejected: a task is cut from the epic and lands
  in it; a pull request from the epic into the default branch is not something the task model says.
- **`spec.sh` sources `task.sh`.** Rejected by the scripts layout rule; the shared steps moved to
  `common.sh` instead.
- **A mode flag** (`--declare`, `--final`). Rejected: the state already tells, and a flag that
  disagrees with it is one more way to push the wrong branch.
- **Refuse on the default branch instead of switching to `spec/<id>`.** Rejected by the human at the
  gate: the switch loses nothing and saves a round trip.
- **Decide the release level at the finish.** Kept for attended runs when nothing was recorded, but
  not as the rule: an unattended finish has nobody to ask.

## Consequences

- With `agent.git: pr` a spec with an epic needs a human for its decisions and merges only.
- `task ship` and `spec ship` cannot disagree on staging, pushing or finding an open pull request; a
  change to one is a change to both.
- `spec ship` touches the network (fetching the default branch) to tell a declaration from an epic.
- Reverting the command is cheap; the helpers in `common.sh` stay harmless. A merged epic is a
  release and is not reverted by reverting this.

> **Amendment (2026-09-22).** The two questions left to the unattended-mode decision are answered: at
> `agent.git: merge`, in an unattended run only, `spec ship` merges the epic's final pull request with a
> merge commit once CI passed and nothing is left of the epic; no `Release:` line reads as `minor`, and a
> `major` release opens as a draft that needs a human. A declaration is still never merged
> (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci).
