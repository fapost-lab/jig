---
name: jig-consolidate
description: Decide what a finished Jig task should leave behind in durable knowledge, record that decision, and close the task once its change has landed. Use at the end of every task route, before committing or opening a PR; when `jig status` or housekeeping reports a task under needs-consolidation; or when the user says "consolidate", "what should we document", "update the knowledge", "close the task".
---

# jig-consolidate — what survives the task

One question:

> What discovered or created during this task would future developers and agents lose if
> it disappeared?

Code already records behaviour. Knowledge records intent. Answering
`NO_DURABLE_KNOWLEDGE` is a correct outcome, not a failure.

This is the last stage of **every** route, T0 included, and it has two entries (ADR-0030):

- **Record the decision** (§1–§5) — after implementation and required review/verification,
  before the commit, so code and the intent behind it enter the repository together.
- **Close the task** (§6) — after its change has landed. A merge is not the end of a task:
  fixes can follow it, and only the close says the task is done.

Finishing analysis, a backlog, or a design does not complete its implementation task: keep
it active or explicitly paused. Resolve/read context with `--stage consolidate`.

A T0/T1 task without a workspace has no state to record: state the decision in the report
and stop there.

## 1. Review what happened

Read the task's workspace artifacts and the diff. Look for: a decision with alternatives,
a constraint discovered the hard way, a term used inconsistently, an assumption that
turned out wrong, a rule the codebase now depends on.

Found nothing? That is `NO_DURABLE_KNOWLEDGE`: skip to §5.

## 2. Route each finding

| Finding | Destination |
|---|---|
| A decision with real alternatives and consequences | `jig knowledge new adr <slug>` |
| Why a feature is shaped this way; its constraints | `jig knowledge new feature <slug>`, or the document that already owns it |
| A boundary, dependency direction or system-wide rule | `ARCHITECTURE.md` |
| Something that must always hold | `RULES.md` invariants |
| A practice the project now follows | `jig knowledge new convention <slug>` |
| A term used for a core concept | `GLOSSARY.md` |
| Orientation, terms or rules that bind one domain only | `jig knowledge new domain\|glossary\|rule <domain>` |
| Process notes, task history, what you tried | nothing; it dies with the workspace |

Never copy `plan.md`, `review.md`, `verification.md`, acceptance maps, or behavior deltas
into knowledge because they exist. Retain only the accepted intent in its durable owner.

## 3. Write into existing documents

Update the document that owns the topic instead of adding a parallel one. Several tasks
over time shape one feature document. When a decision replaces an earlier one, mark the
old ADR `superseded` rather than editing history.

## 4. Keep the frontmatter true

`paths` and `domains` are how `jig context` finds a document later; a document nobody can
find is worse than no document. Ask what this task changed about coverage:

```
.ai/scripts/jig knowledge paths --task <id>
```

`uncovered` is code no document claims — either a document should claim it, or the code
genuinely carries no intent worth recording. `unmatched` is a glob that points at nothing
— the code moved or was deleted.

```
.ai/scripts/jig knowledge paths add <id> <glob>
.ai/scripts/jig knowledge paths remove <id> <glob>
```

Then stamp every document you edited as reconciled with the code:

```
.ai/scripts/jig knowledge reviewed <id>
```

That stamp is the whole basis of `jig knowledge stale`. Skipping it does not save time,
it degrades the document to "never reconciled".

A document you edited that has no `summary` gets one now — it is the single line another
agent reads in the context catalog before deciding whether to open the file, and
`knowledge check` warns until it is there. One sentence saying what the document is for,
not a restatement of its title.

Frontmatter is never hand-edited: the commands above own it (ADR-0001, ADR-0010).

## 5. Verify and record the decision

```
.ai/scripts/jig knowledge check
.ai/scripts/jig spec done <id>
.ai/scripts/jig task set <id> knowledge_consolidated true
```

`spec done` checks the roadmap items that name the task when its `task.md` carries a `Spec:`
line, so the checkmark reaches the base branch in the same change as the work; for a task with
no link it says so and changes nothing. If it reports that no roadmap item names the task, the
roadmap and the task disagree: ask the human, and do not edit the roadmap by hand.

The status stays `ready`: the task is still current, and fixes from review of the commit
or PR continue in it. If review changes the implementation, update the same documents; do
not start a new task document for it.

A task cut from an epic (`base_branch: epic/…`) lands when its pull request is merged into the
epic, and closes then like any other. Housekeeping keeps its workspace until the epic reaches the
default branch, so the final review can still read it.

A task whose landing cannot be observed closes now, in §6: `jig task list` shows no
`branch` for it, or the base branch. Housekeeping never sees such a task land (ADR-0025).

## 6. Close the task

Close when the change has landed: `jig-task` found the task flagged `needs-consolidation`
at session start and the user agreed, `jig status` counts it under `needs consolidation`,
or the human says the work is finished.

1. `knowledge_consolidated` must already be `true`. If it is not, run §1–§5 first; the
   knowledge then reaches the repository in a follow-up change.
2. If fixes after the commit changed the intent, update the documents they touched.
3. Ask the human whether a fix is still expected on this task. If one is, leave it open.

```
.ai/scripts/jig task set <id> status consolidated
```

The script refuses this while the knowledge decision is unrecorded. Once the task's branch
is confirmed merged, housekeeping moves the workspace to trash; a task whose landing
cannot be observed keeps its workspace, closed and unflagged, because housekeeping never
destroys on `unknown`. A problem found after the close is a new task.

## 7. Report

Ask the repository what changed, rather than reporting from memory:

```
.ai/scripts/jig knowledge changed --task <id>
```

It lists the documents created, modified and deleted since the task forked, untracked ones
included — a document written minutes ago is usually not committed yet. Pass `--base <ref>`
instead when the task has no fork point.

The command supplies the facts; you supply the meaning. Show what was written — each new
document, and each changed section of an existing one — verbatim, as
[show the document](../jig-task/references/show-the-document.md) says: it binds every agent
that resolves it. After it, say **why it earned a place**, or say `NO_DURABLE_KNOWLEDGE`
and why the task left nothing behind. A list of paths is not a report. Say too whether the
task is closed or waits for its change to land.
