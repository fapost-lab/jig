# Jig (Agent SDLC Framework) — agent instructions

This repository *is* the framework and also uses it (dogfooding). Follow the process
described in the durable knowledge under `.ai/knowledge/`.

## Read first

- `.ai/knowledge/GLOSSARY.md` — use canonical terms.
- `.ai/knowledge/RULES.md` — invariants; do not violate.
- `.ai/knowledge/adr/` — accepted decisions; propose a new ADR instead of silently
  contradicting one.
- `README.md` — what Jig is and how it is used (human-facing).

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

- All documents, skills, scripts and comments are written in English (`CLAUDE.local.md`).
- Any decision that changes architecture, distribution, lifecycle semantics or safety
  of destructive operations gets an ADR (`adr/NNNN-<slug>.md`, frontmatter per ADR-0004).
- Scripts: POSIX sh / bash 3.2, no mandatory dependencies besides `git` (ADR-0002).
  Every script command has a test under `tests/`.
- Skills are short; mechanics go to scripts (ADR-0001).
- Adding or renaming anything framework-owned — a skill under `skills/`, a profile, a
  template — is not finished until `jig upgrade` has placed it. This repository installs
  itself in link mode, so a new skill exists in `skills/` but not in `.claude/skills/` or
  `.codex/skills/` until then, and no runtime can see it. `jig verify` refuses to run
  while anything is pending, and `jig status` reports the count.
- Task-specific notes live in `.ai/workspace/tasks/<id>/` (gitignored), never in the repo.
- Before finishing a task, ask: what here should survive the task? Update
  `.ai/knowledge/` accordingly, or state `NO_DURABLE_KNOWLEDGE`. Knowledge frontmatter is
  maintained by `jig knowledge new|paths|reviewed`, never by hand.
