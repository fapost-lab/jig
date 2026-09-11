---
name: jig-task
description: Start or resume a task with Jig — classify it by risk, create its workspace and choose the workflow. Use when the user describes work to do ("add …", "fix …", "refactor …"), asks to start or continue a task, or says "jig task", "classify this", "what process does this need".
---

# jig-task — classify and route

You decide the class; scripts record it. Keep this step short: it exists to avoid
running an expensive process on cheap work, and a cheap process on risky work.

## 0. Exploration is a valid entry

For standalone research/comparison, use `jig context resolve --no-task --catalog` with
explicit files/domains/topics; do not select an unrelated task, classify implementation,
or create a workspace. Use `--files -` with empty stdin for a deliberately empty frontier.
An explicit analysis of a named task stays there. Save research only when useful/requested;
implementation intent returns to the route below.

## 1. Resume before starting

```
.ai/scripts/jig task current
.ai/scripts/jig task list
```

If a task for this work already exists, read its `task.md` and `plan.md`, say where it
stands, and continue from there instead of creating a second workspace.

`task current` exiting 2 means several tasks are live on this branch. It prints them;
ask the user which one, and never pick for them. Suggest pausing the other:

```
.ai/scripts/jig task pause <other-id> --reason "<why>" [--stash]
```

Resuming a task that was paused: `jig task resume <id>` prints what changed while it was
dormant. Treat a long pause or an overlap line as a reason to re-check the premises of
`design.md` before building on it; the stage skills can be re-run, and re-running
`jig-analyze` is how research is restarted.

## 2. Classify

Read `references/classification.md` and pick T0–T4 from the signals. State the class and
the one signal that decided it, in a single sentence. Do not narrate the rubric.

If the description is too vague to classify, ask one question. One, not a list.

## 3. Create the workspace, then start it

T0 and T1 that fit in one session need no workspace. Otherwise:

```
.ai/scripts/jig task new <id> --class T2 --domains <a,b>
.ai/scripts/jig task start <id>
```

The id is short and kebab-case, derived from the work (`fix-trigger-idempotency`), not a
ticket number unless the project uses one. Fill in `task.md`: goal, scope, notes.

**Two commands, because filing and beginning are different acts.** `task new` records the
intent: no branch, no checkout change. `task start` cuts the branch and records the commit
it forked from, which is why it belongs at the moment work actually begins — a fork point
recorded weeks earlier is wrong by the time anything reads it.

**File without starting when the work is for later.** A task with no branch is listed as
`not-started` and never becomes an ambiguous `task current` candidate, so parking an idea
costs nothing and does not need a pause to stay out of the way. Pause means "was being
worked on, set aside" — do not use it to mean "not begun".

**When `task start` refuses a dirty tree**, the changes belong to other work — never work
around it. Ask the user which road: pause the task that owns them
(`jig task pause <owner> --stash`), or start this one in a worktree of its own:

```
.ai/scripts/jig task start <id> --worktree
```

It prints a path and leaves this checkout alone. Your session cannot move there: tell the
user to open a new agent session in that path, and do not continue the task from here.

When the user already wrote the task as a document, take it from disk instead of
retyping it, and split it as §"When the task arrives written" says:

```
.ai/scripts/jig task new <id> --class T3 --from <path>
```

## 4. Load context

Use the first stage selected by the class so stage-aware knowledge arrives before that
stage begins (for example, `analyze` for T1/T2 and `discover` for T3/T4):

```
.ai/scripts/jig context resolve --task <id> --stage <first-stage> --catalog
```

Read exactly what it lists and nothing else. It returns global knowledge, documents
matching the affected files or domains, and the workspace artifacts.

## 5. Run the route

Announce the route, then start the first stage. Each stage is its own skill:

| Class | Route |
|---|---|
| T0 | jig-implement → jig-verify |
| T1 | jig-analyze → jig-implement → jig-verify |
| T2 | jig-analyze → plan → jig-implement → jig-review → jig-verify |
| T3 | discover → design → **human gate** → jig-implement → jig-architecture-review → jig-verify → jig-consolidate |
| T4 | discover → specify → alternatives → design → **human gate** → jig-implement → independent jig-review → jig-verify → jig-consolidate |

A stage whose output the user already supplied is not re-run; see the next section.

## When the task arrives written

A task handed over as a written document has usually been through discovery and design
already. Run the stage that is missing, not the ones the author has done.

- **Split it.** Goal, problem and scope go to `task.md`; the proposed solution goes to
  `design.md`. A gate cannot approve a document where the problem and the answer are
  mixed together.
- **Argue with the design before the gate.** Say what you would do differently and why,
  which questions it leaves open, and which of its claims you could not confirm. A design
  that draws no objection was not reviewed.
- **Verify its premises.** The document may assert things about this codebase that are no
  longer true. Check the ones the design rests on and report what you found. This is the
  part of discovery that is still owed.
- The gate is then the moment you and the author settle on the final shape, and
  implementation starts from that, not from the original text.

## Human gate (T3, T4)

Stop. Present the design in a few lines: what changes, which alternatives lost and why,
what it costs to undo. Wait for the human to approve, change or reject it. Do not start
implementing while waiting, and do not treat silence or a general "ok, go on" from an
earlier message as approval.

For T2+, follow [requirements and planning](references/requirements-and-planning.md).
Design UI changes with [applicable states](references/ui-states.md). At pause/resume or
this gate use the [handoff](references/handoff.md); continuous work needs no extra stop.
`jig task artifacts <id>` reports input facts, not approval or the next stage. If an input
lives in conversation, locate/read it before using `--provided <kind>`; never invent a
provided claim to silence a missing input.

## Artifacts

Create an artifact only when it does work: a plan someone follows, a design someone
approves, a spec someone checks against. Everything else stays in the conversation. Task
artifacts live in `.ai/workspace/tasks/<id>/` and never move into the repository; only
`jig-consolidate` writes to `.ai/knowledge/`.
