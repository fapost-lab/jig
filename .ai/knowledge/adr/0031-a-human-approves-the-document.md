---
id: adr-0031-a-human-approves-the-document
type: adr
status: accepted
date: 2026-09-13
domains:
  - skills
  - sdlc
paths:
  - "skills/**"
summary: Why whatever a human is asked to agree to is shown verbatim, and why no script can check it.
reviewed_at: 2026-09-13
---
# ADR-0031: A human approves the document, not a retelling of it

## Context

Skills told the agent to summarise at exactly the points where a human decides: the T3/T4
gate "in a few lines", `jig-init` "summarise what was written", `jig-map` "present the
map", `jig-accept` "its body, or the part of it that carries the judgement".

The work follows the document, not the summary. A summary drops what the agent judged
unimportant — which is what the human is there to judge — and the approval recorded
afterwards names a document the human may never have seen. ADR-0009 made gates full stops
and required approval "for this design"; it said nothing about how the design reaches the
human.

## Decision

- **Whatever a skill asks a human to agree to is shown verbatim**: the document itself,
  rendered as Markdown, with a link to its file. The agent's commentary follows it,
  separately — what it would do differently, what it is least sure of, what undoing costs.
- **The same holds when a step writes something others will rely on without rereading
  it**: analysis notes in `task.md`, `plan.md`, knowledge written by `jig-init` and
  `jig-consolidate`. This adds no stop to any route.
- The task's other artifacts are listed with a link and one line each.
- **No length threshold.** A long document is shown whole.
- **A repeated gate shows every changed section whole** and names the unchanged ones.
- **The gate records** in `task.md` which documents were shown in full and the human's
  decision. An approval covers the document as it was shown; if it changes afterwards,
  `jig-implement` sends the task back to the gate.
- One reference, `skills/jig-task/references/show-the-document.md`, owns the rule; every
  skill that asks for a decision or reports written knowledge links to it.

This refines the gate of ADR-0009; it does not replace it.

## Alternatives

- **A link to the file only.** The human has to go and find the document, and the
  retelling beside the link stays the thing actually read.
- **A script, `jig task show --docs`.** Its output reaches the agent, not the human:
  runtimes collapse tool output. Useful only when the human runs it themselves.
- **Runtime rendering** (artifact pages, file previews). Exists in one supported runtime
  and not the other.
- **A length threshold above which a summary is allowed.** The way back to the summary.
- **A line diff on a repeated gate.** Lines out of context do not read.
- **A mechanical check comparing `design.md` mtime with the approval date.** The recorded
  date has no time and any save moves mtime; false alarms would teach agents to ignore it.
- **A new stop for the T2 plan.** Changes the routes ADR-0009 fixed, which is not the goal.

## Consequences

- **The rule is carried by skills alone.** No script sees what a human was shown; the
  record in `task.md` is a claim, not proof (ADR-0020). If agents keep summarising,
  nothing mechanical catches it.
- Messages at gates get longer. A long document's length becomes visible as its cost,
  which pushes toward shorter documents rather than shorter presentations.
- `jig-accept` shows one domain pack per message, so a large map takes several rounds.
- A new skill that asks a human to decide links the reference instead of describing its
  own way of presenting.
