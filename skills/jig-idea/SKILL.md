---
name: jig-idea
description: Stress-test an idea with the user and keep the result as a durable specification with phases and a roadmap under `.ai/specs/<id>/`. Use when an idea's shape is not settled yet, when work is too big for one task (tens of tasks, phases), when designing a future project's architecture and stack before any code exists, or when the user says "I have an idea", "poke holes in this", "write a spec", "build a roadmap", "continue the spec".
---

# jig-idea — test the idea, keep the plan

A **specification** is the plan for a large piece of work: the idea as the human said it,
what survived questioning, the decisions, and a roadmap of phases and items. Tasks are filed
from it later — the next day, months later, or in a different repository.

This skill talks and writes the specification. It never starts a task, never changes code,
and writes nothing outside `.ai/specs/<id>/`. `jig-task` stays the one entry into task routes
(ADR-0009); this skill works before it.

A specification is not knowledge. `.ai/specs/` sits outside `.ai/knowledge/`, so
`jig context` never resolves it and `jig knowledge check` never reads it: an agent working
on today's code must not read tomorrow's plan as a description of the system. A spec has no
status; progress is read from its roadmap.

## 1. Open the specification

```
.ai/scripts/jig spec list
```

- **Existing spec.** Read every file in its directory before saying anything. Start from its
  open questions and its fog items — that is where the last session stopped.
- **New spec.** Choose a short kebab-case id with the user, then create it:

  ```
  .ai/scripts/jig spec new <id>
  ```

  It refuses an invalid or taken id and writes `spec.md` and `roadmap.md` from the
  templates; fill them in, starting with the heading of `spec.md`, which names the spec in
  `jig spec list`. Write the idea in the human's own
  words, not a retelling. Other files (`architecture.md`, `stack.md`, `research.md`) are
  added when the conversation needs them.

A spec is written in the project's durable language (AGENTS.md): it is committed.

## 2. Learn what the project already knows

```
.ai/scripts/jig context resolve --no-task --catalog --files <paths> --domains <domains>
```

Name the files and domains the idea touches. In a repository with no code yet, the global
documents are what there is. Facts about the repository you find yourself; never ask the
human something the code can answer.

## 3. Propose a depth

One line: the level and why. The human may pick another.

- **easy** — you take the reversible decisions yourself and list each as an assumption; you
  ask only about the irreversible. Before writing, one question: accept or reject the
  assumptions.
- **normal** — one question per real decision.
- **deep** — every decision with its trade-off visible, every pressure lens that fits, and
  the independent failure hunt (§5).

The level is a budget, not a verdict. When more is open than it allows, say so and offer to
go deeper. Record the level in `spec.md`.

## 4. Three phases, in order

1. **Understand.** The idea in one sentence, who is worse off without it, what success
   looks like. Do not argue yet.
2. **Put weight on it.** Hidden assumptions ("this holds only if X — and if not?"),
   trade-offs, vague words, the cost of being wrong. Use the lenses in
   [pressure](references/pressure.md); pick the ones that fit, do not name them aloud.
3. **Offer other shapes.** Two or three alternatives — another audience, scale or form — or
   a twist (invert it, constrain it, cut it down), each with your recommendation.

Do not skip ahead: an alternative offered before the idea is understood answers a question
nobody asked.

## 5. Independent failure hunt

Always on deep, offered on normal. Give a fresh agent in a clean context — a subagent, if
your runtime has them — the idea and the leading options, with the brief in
[pressure](references/pressure.md). Without subagents, run the same pass yourself as a
separate, announced step. What it finds goes into "Stress test"; the sharpest findings
become decisions or open questions.

## 6. Ask well

- Every question carries your recommended answer and what follows from each option.
- Explain a term the first time it appears.
- One decision per question. Batch only questions that are truly independent.
- Two answers in a row of "I don't know" — ask one open question in the human's terms, then
  return to options (see the stuck protocol in [pressure](references/pressure.md)).

## 7. Write it down as you go

What is decided goes into the spec files immediately — not at the end, where half of it is
lost. Show every written or changed section verbatim, as
[show the document](../jig-task/references/show-the-document.md) says. A rejected option is
recorded with its reason: the next session must not reopen the argument. What is unresolved
goes to "Open questions".

## 8. Roadmap

When the idea has held up, or when asked. Format: the `roadmap.md` that `jig spec new` wrote; its closing
comment repeats these rules.

- A destination sentence first; without it there is nothing to check items against.
- Items are finished slices that make the product noticeably better, never layers
  ("backend", "tests").
- A dependency carries a one-line reason. No reason, no dependency: a false edge turns
  parallel work sequential.
- An area whose question cannot be stated precisely yet is a `fog:` item. Do not split or
  size it; it becomes real items once the fog lifts.
- Waves group items that can run at the same time, in separate worktrees (ADR-0029). Wave N
  depends only on earlier waves.
- No dates and no point estimates: order is the priority.

Look up the facts the cut depends on ("where does this live", "is this one part of the
code") yourself, in parallel subagents where possible, each with its source. Decide the cut
with the human: show the draft as prose and verbatim in the file, then let them merge, split
and move items between waves.

## 9. End of the session

The session ends when nothing is left open for the chosen depth, or when the human stops.
Close with three lines: the idea after testing in one sentence, its weakest point, the next
step. Leftovers stay in "Open questions"; the next session starts there.

Check the result:

```
.ai/scripts/jig spec list
```

When the human wants to begin an item, hand it to `jig-task` with the item's text and a link
to the spec. Do not start it here.
