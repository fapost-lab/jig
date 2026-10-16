---
id: adr-20261015-every-review-is-a-fresh-reader
type: adr
status: accepted
date: 2026-10-15
domains:
  - skills
  - task
paths:
  - skills/jig-review/SKILL.md
  - skills/jig-architecture-review/SKILL.md
  - skills/jig-autopilot/SKILL.md
  - skills/jig-task/references/delegation.md
summary: Why every review stage is done by a subagent or process that has not seen the implementation, attended or not, with a new reader per re-review; why T4 adds another model when the person set one, every criterion checked and fixed P0/P1 reverted until red; and why nothing records the reviewer's model.
---
# Every review in a route is done by a reader who has not seen the implementation; T4's is extended

## Context

adr-20261005-jig-names-the-roles-not-the-models made review one role — "a reader who has not seen
the implementation" — but the skills held that only in two places: `jig-review` asked for a fresh
context at T4, and `jig-autopilot` for every review it ran. An attended T2 review, and an attended T3
architecture review, were done by the session that wrote the change, with its reasoning still in
context. So the work a person sat beside was reviewed more weakly than the work nobody watched, and
T4's "independent review" differed from the others only by the receipt it must leave. The
maintainer asked why the attended route did not use a fresh reviewer, and found no reason for it.

## Decision

- **Every review stage is a fresh reader.** Review, architecture review and T4's independent review
  are done by a subagent or a fresh process that has not seen the implementation conversation —
  attended or on autopilot, at every class whose route has a review. Each re-review is a new reader.
- **The brief carries the task, not the author's account.** Task id, worktree, base, the skill,
  `task.md` and the design or plan; never the implementer's report. A subagent gathers the change
  and the knowledge with the scripts; an external read-only process gets the brief `delegation.md`
  names, because it cannot run them.
- **Who reviews is chosen as before:** `executor: review`, else `delegate: review` for the session's
  runtime, else a subagent on the session's model. A selected model or runtime that cannot start
  keeps the rules of adr-20261012-codex-subagents-use-runtime-models and
  adr-20261012-cross-runtime-stage-executors: the coordinator never signs its own review in its place.
  Only with no review line at all, where no subagent can start, may the session review, and the pull
  request says so.
- **T4 is reviewed further.** The reviewer runs on another model or runtime than the implementation
  when the person configured one: the effective implementer (`executor: implement`, else
  `delegate: implement`, else the session) is compared with the effective reviewer the same way, and
  they differ when their runtimes differ or one runtime names two models. The agent never picks a
  model itself. Without one, a same-model reviewer in a fresh context does the review and the pull
  request says so; the ship is not stopped. Every acceptance criterion is checked with evidence, and
  every P0 or P1 marked `fixed` is re-reviewed by reverting the fix and watching its test go red.
- **No script, gate or setting changes.** Jig cannot tell a fresh context from a reused one, so this
  is a norm of the skills. The pull request line about the model is prose for the person, not a route
  record: "No actor record" in adr-20261005 still holds for the ledger, the receipt and the gates.

## Alternatives

- **Keep the fresh reader at T4 and in autopilot only.** Rejected: the weakest review stays where a
  person is present, and the skills keep contradicting adr-20261005.
- **Record the reviewer's model in the receipt.** Rejected: a record the actor writes about itself is
  self-certification (adr-20261004-a-route-stage-is-proven-by-its-record); the receipt pins content.
- **Require another model for T4.** Rejected: a person without a second model or runtime would have
  every T4 task stopped by a setting they never had to write.
- **Let the agent choose another model for T4.** Rejected: the model is the person's choice and
  budget (adr-20261005), and the agent cannot know what they have.
- **Two reviewers for T4.** Rejected for now: double the cost, and a second reviewer on the same
  model mostly finds what the first did.

## Consequences

- An attended T2 or T3 review costs one more subagent, which re-reads the diff and the knowledge
  through the scripts.
- T4 gains a review on another model wherever the person set one up, and a visible line in the pull
  request where they did not.
- Nothing checks the norm; an agent that reviews its own change leaves a receipt that looks the same.
  Hardening that is later work.
- Undoing it: restore the skill text and mark this ADR superseded; no state or data is involved.
