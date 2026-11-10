---
id: adr-20261109-an-autopilot-pull-request-carries-no-design
type: adr
status: accepted
date: 2026-11-09
domains:
  - task
  - skills
paths:
  - skills/jig-autopilot/SKILL.md
  - docs/autopilot.mdx
summary: Why an autopilot pull request body is a short English summary with the report's blocks, and the agent-approved design is named in one line rather than pasted in.
---
# An autopilot pull request carries a short English summary, never the design

## Context

An unattended run approves its own T3/T4 design, and the rule was to put `design.md` verbatim in
the pull request as approved by the agent, not a human
(adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci). The skill also put the run's
whole report in the body: every journal line, with its timestamp. Both made the body documentation.
`design.md` is a task artifact, written in the language its reader thinks in, so the body was not
even in English: pull request #432 carried about 180 lines of a Russian design. A pull request
leaves the machine, so it is written in English, and a reviewer reads its summary, not a design
they cannot answer.

## Decision

- The body an autopilot run writes is short and in English: what changed and why, the review
  result, the verify result, and the report's blocks as they are — **Decided without you**,
  **Approved by the agent, not a human**, **Resumed on an answer**, **Taken over by a person**,
  **Changed linked sources — need your review**. Not the journal's stage and repair lines.
- The design is not in the body. Its approval is the `approve --reason` line, one or two English
  sentences: what was approved and where the durable detail lives — the ADR or knowledge document
  the task wrote. No `## Design` section.
- `decide` and `approve` reasons are written in English, since they reach the body as they are;
  `stop` and `end` reasons reach only the person and stay in their language. A person's answer is
  still quoted as given (adr-20261013-human-answer-resumes-stopped-unattended-run), with an English
  gloss in the body when it is not in English.
- Showing the design whole stays a thing done for a person in the conversation
  (`skills/jig-task/references/show-the-document.md`). The gate still pins its hash (`gate_design`).

## Alternatives

- **Translate the design into English for the body** — rejected: still documentation in a pull
  request, and a second copy of a document that has one source.
- **Link to `design.md`** — rejected: `.ai/workspace/` is gitignored; the link leads nowhere.
- **A short `## Design` section beside the blocks** — rejected: it repeats the approve line.

## Consequences

- A reader of the pull request no longer sees the agent-approved design whole. What lasts of it
  is in the ADR or knowledge the task wrote, which the approve line names, and in the
  conversation where the design was shown.
- A design whose substance nobody wrote into durable knowledge leaves only the approve line
  behind; consolidation is what keeps it, as for any task.
- Narrows adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci, the 2026-09-22
  amendment of adr-0009-routing-rubric-and-explicit-gates and
  adr-20261004-a-route-stage-is-proven-by-its-record where they put the design verbatim in the
  pull request; the rest of each stands. No script changes: `report` already prints the blocks.
