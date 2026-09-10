# Agent instructions

This project uses Jig, a vendor-neutral agent SDLC framework. Project knowledge lives in
`.ai/knowledge/`; the development process is provided by `jig-*` skills backed by
deterministic scripts in `.ai/scripts/`.

## Read first

- `.ai/knowledge/GLOSSARY.md` — canonical terms; use them in code and docs.
- `.ai/knowledge/RULES.md` — rules and invariants; never violate them.
- `.ai/knowledge/ARCHITECTURE.md` — domains, boundaries, dependency directions.
- `.ai/knowledge/adr/` — accepted decisions; propose a new ADR instead of silently
  contradicting one.

Do not read all of `.ai/knowledge/` up front. Ask the scripts for what is relevant:

```
.ai/scripts/jig context --files <changed files>
```

## Workflow

Start work with the `jig-task` skill; it classifies the task by risk and names the route.
Stage skills can also be used directly: `jig-analyze`, `jig-implement`, `jig-review`,
`jig-verify`, `jig-consolidate`, `jig-architecture-review`.

Two skills sit outside the task routes because they populate knowledge rather than change
code: `jig-map` proposes per-domain knowledge, and `jig-accept` decides what is proposed.
A proposed document is invisible to `jig context` until a human accepts it, so knowledge
someone wrote but nobody agreed to reaches no agent — `jig status` reports the count on
its `proposals:` line, and `jig knowledge proposed` lists it.

| Class | Route |
|---|---|
| T0 trivial | implement, verify |
| T1 local | analyze, implement, verify |
| T2 structural | analyze, plan, implement, review, verify |
| T3 architectural | discover, design, human gate, implement, architecture review, verify, consolidate |
| T4 critical | discover, specify, alternatives, design, human gate, implement, independent review, verify, consolidate |

Risk sets the floor: a one-line change to authentication is not trivial. When a task
turns out bigger, re-classify with `jig task set <id> class Tn` and run the stages the
new class requires.

## Working rules

- Code explains what; knowledge explains why. Put intent, constraints, trade-offs and
  rejected alternatives into `.ai/knowledge/`, not into task notes.
- Task-specific notes belong in `.ai/workspace/tasks/<id>/` (gitignored). They never
  become repository documentation by themselves.
- Completion is proven by evidence: run `.ai/scripts/jig verify` before declaring done.
- Before finishing a task, decide what should survive it. Update `.ai/knowledge/`, or
  state `NO_DURABLE_KNOWLEDGE`. Frontmatter is maintained by `jig knowledge new`,
  `jig knowledge paths add|remove` and `jig knowledge reviewed`, never by hand.
- Knowledge authority, highest first: human instruction, accepted ADR, architecture,
  rules and invariants, conventions, glossary, feature knowledge, task context.
  Escalate real conflicts to a human.
