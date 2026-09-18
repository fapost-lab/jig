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

Three skills sit outside the task routes. Two populate knowledge rather than change
code: `jig-map` proposes per-domain knowledge, and `jig-accept` decides what is proposed.
A proposed document is invisible to `jig context` until a human accepts it, so knowledge
someone wrote but nobody agreed to reaches no agent — `jig status` reports the count on
its `proposals:` line, and `jig knowledge proposed` lists it. The third, `jig-idea`, works
before a route: it stress-tests an idea and keeps the result as a specification with a
roadmap under `.ai/specs/<id>/`. A specification is a plan, not knowledge, so `jig context`
never resolves it — `jig status` counts specs on its `specs:` line, and `jig spec list`
lists them with their roadmap progress.

| Class | Route |
|---|---|
| T0 trivial | implement, verify, consolidate |
| T1 local | analyze, implement, verify, consolidate |
| T2 structural | analyze, plan, implement, review, verify, consolidate |
| T3 architectural | discover, design, human gate, implement, architecture review, verify, consolidate |
| T4 critical | discover, specify, alternatives, design, human gate, implement, independent review, verify, consolidate |

Every route ends in consolidation, and a task with a workspace ends it in two records.
Before the commit, the knowledge decision — `NO_DURABLE_KNOWLEDGE` included — is recorded
with `jig task set <id> knowledge_consolidated true`. After the change has landed, when
`jig status` counts it under `needs consolidation`, the task is closed with
`jig task set <id> status consolidated`. A merge alone never closes a task.

Risk sets the floor: a one-line change to authentication is not trivial. When a task
turns out bigger, re-classify with `jig task set <id> class Tn` and run the stages the
new class requires.
