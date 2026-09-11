---
name: jig-consolidate
description: Decide what a finished Jig task should leave behind in durable knowledge, and write it. Use before committing or opening a PR, or when the user says "consolidate", "what should we document", "update the knowledge".
---

# jig-consolidate — what survives the task

One question:

> What discovered or created during this task would future developers and agents lose if
> it disappeared?

Code already records behaviour. Knowledge records intent. Answering
`NO_DURABLE_KNOWLEDGE` is a correct outcome, not a failure.

Run this completion stage only after implementation and required review/verification are
complete. Finishing analysis, a backlog, or a design does not complete its implementation
task: keep it active or explicitly paused. Resolve/read context with `--stage consolidate`.

## 1. Review what happened

Read the task's workspace artifacts and the diff. Look for: a decision with alternatives,
a constraint discovered the hard way, a term used inconsistently, an assumption that
turned out wrong, a rule the codebase now depends on.

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

## 5. Verify and record

```
.ai/scripts/jig knowledge check
.ai/scripts/jig task set <id> knowledge_consolidated true
.ai/scripts/jig task set <id> status consolidated
```

Consolidation happens before the commit, so code and the intent behind it enter the
repository together. If review later changes the implementation, update the same
documents; do not start a new task document for it.

## 6. Report

Ask the repository what changed, rather than reporting from memory:

```
.ai/scripts/jig knowledge changed --task <id>
```

It lists the documents created, modified and deleted since the task forked, untracked ones
included — a document written minutes ago is usually not committed yet. Pass `--base <ref>`
instead when the task has no fork point.

The command supplies the facts; you supply the meaning. Say what was written and where and
**why it earned a place**, or say `NO_DURABLE_KNOWLEDGE` and why the task left nothing
behind. A list of paths is not a report.
