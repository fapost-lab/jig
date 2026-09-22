---
id: adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci
type: adr
status: accepted
date: 2026-09-22
domains:
  - task
  - skills
  - config
  - spec
paths:
  - scripts/lib/common.sh
  - scripts/lib/task.sh
  - scripts/lib/spec.sh
  - scripts/lib/config.sh
  - skills/jig-autopilot/SKILL.md
  - skills/jig-consolidate/SKILL.md
summary: "Why an unattended autopilot run asks nothing and records its defaults in the pull request, and why agent.git: merge merges only on green CI at the shipped commit, never past branch protection."
reviewed_at: 2026-09-22
---
# An unattended run asks nothing, and a finished change merges itself once CI passed, never past the forge's rules

## Context

The users the autopilot specification targets build through an agent without being developers
(spec decision of 2026-09-21). They cannot answer the questions an autopilot run stops on — approve
this design, choose between these options, may I delete this — and they want the change they asked for
deployed by CI, not left as an open pull request they do not know how to review. ADR-0009 made human
gates full stops, and adr-20260921-agent-git-rights-are-a-local-setting said no `agent.git` level
merges, and none will. Both were right for a user who can answer; neither leaves anything for one who
cannot.

A merge bypasses the only human look at the change, so the question was never "merge or not" but
under which conditions a merge nobody watches is still safe, and what records what the agent decided
alone.

## Decision

- **Two local-only keys, each its own switch.** `agent.git: merge` is a level above `pr`: `task ship`
  merges the pull request it opened. `autopilot.unattended: true` makes an autopilot run ask nothing.
  "May it merge" concerns every ship; "may it ask" concerns only a run. Unattended without `merge`
  ends in an open pull request with the decisions written in it; `merge` without unattended is a run
  that asks at its stops and merges at the end. Both keys, and `agent.ci_timeout`, are in
  `JIG_CFG_LOCAL_ONLY_KEYS`: a committed value would make every contributor's agent merge or decide.
- **A script merges, only when everything holds** — `jig_ship_merge` in `common.sh`, shared by
  `task ship` and `spec ship`. The pull request is not a draft and its head is the commit that was
  shipped; the caller's gates still pass (a task's findings and receipt are checked again right before
  it); the repository allows a merge method (merge commit, else squash, else rebase); the checks are
  waited for up to `agent.ci_timeout` minutes (default 30), and at least one ran and every one passed
  — none, a red one, or the timeout leaves the pull request open; then `gh pr merge
  --match-head-commit <sha>` (GitLab: `glab mr merge --sha <sha> --auto-merge=false`). Never `--admin`,
  never `--auto`. A refusal from the forge — branch protection, a required human review — is not an
  error: `ship` prints `not merged: <why>` and exits 0. That refusal is the ceiling a team keeps over
  one contributor's local key.
- **Stops become recorded defaults, in an unattended run only.** `task autopilot start` records
  `autopilot_mode: attended|unattended`, so changing the key mid-run changes nothing. The gate of a
  T3/T4 task (and a re-classification into one) is approved by the agent — `jig task gate <id>
  approved --by agent`, refused outside an unattended run, recorded as `gate_by: agent` — and the
  design goes verbatim into the pull request as approved by the agent, not a human. A decision nobody
  made takes the most cautious, most reversible option; a destructive operation is never performed —
  another way or less work. Both are journaled with `task autopilot <id> approve|decide`, refused in an
  attended run, and `report` prints them as "Decided without you" and "Approved by the agent, not a
  human" blocks for the pull request body.
- **Exhausted repairs end in a draft, not a stop.** The third `repair` still stops the run with exit 3;
  the skill then ships with `task ship --draft`, which opens a draft saying what is unfinished. A draft
  completes nothing and is never merged, so it is the one ship the completion gates (knowledge
  decision, findings, receipt) do not refuse.
- **The epic's final merge is the release**, so `spec ship` in final mode merges it only at `merge` and
  only in an unattended run; attended, even at `merge`, it stays the human's. On top of the conditions
  above: only a merge commit (ADR-0040: squash and rebase break the ancestry its tasks are judged by);
  checked again right before the merge — the epic holds the freshest default branch, the spec is not
  on disk, no non-fog roadmap item is unchecked, and no task cut from the epic has a branch outside it;
  the release level from the roadmap's `Release:` line, `minor` when there is none, and a `major`
  release never without a human — the pull request opens as a draft that says "Needs a human: major
  release?". Fog, open questions and untested assumptions dropped at the finish are quoted in the pull
  request under "Dropped without you".
- **After `merged`, the task closes** (`jig-consolidate` §6) without asking — in an unattended run
  only. Anywhere else a merge still does not close a task without the human (ADR-0030).

This refines ADR-0009: in an unattended run the human gate is approved by the agent, with the record
above, instead of stopping. It supersedes the line "No level merges, and none will" of
adr-20260921-agent-git-rights-are-a-local-setting.

## Alternatives

- **One key for the non-developer** (`autopilot.unattended` implying the merge). Simpler to explain,
  but it mixes asking and merging; the documentation gives the two lines to paste instead.
- **`gh pr merge --auto`.** With no required checks it merges at once, and CI gates nothing.
- **Merging, or waiting for CI, in the skill.** The conditions would be a request to a model; the
  specification requires stops a script enforces.
- **A stop instead of a draft when repairs run out.** The user would not answer it; a draft shows where
  the run stopped and releases nothing.
- **`gh pr checks --watch` for the wait.** It has no timeout of its own and macOS has no `timeout`;
  the script polls instead, every 15 s, and waits two minutes for a first check to register before
  deciding CI checks nothing.
- **Only waiving the gate.** Every other stop would still ask a question the user cannot answer.

## Consequences

- A clone with both keys gets a change merged and deployed with no human between the request and CI.
  What the agent decided alone is in the pull request, which stays the place to read it afterwards.
- A repository that requires a human review keeps every such pull request open: the user learns that
  from `not merged: the forge refused …` and from the status page's queue line for `merge`.
- A repository without CI never gets a merge: "CI checked nothing" is a refusal, not a pass.
- A task squash-merged into its epic reads as not in the epic, so the epic's final merge waits for a
  human — the safe side of ADR-0040's ancestry rule.
- Reverting the mechanism is removing a level, two keys and two journal events; a change already
  merged is reverted like any other, not by this.
