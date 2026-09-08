# Agent SDLC Framework — agent instructions

This repository *is* the framework and also uses it (dogfooding). Follow the process
described in `docs/SPEC.md` and the durable knowledge in `.ai/knowledge/`.

## Read first

- `.ai/knowledge/GLOSSARY.md` — use canonical terms.
- `.ai/knowledge/RULES.md` — invariants; do not violate.
- `.ai/knowledge/adr/` — accepted decisions; propose a new ADR instead of silently
  contradicting one.
- `docs/SPEC.md` — the product specification (human-facing).

## Working rules

- All documents, skills, scripts and comments are written in English (`CLAUDE.local.md`).
- Any decision that changes architecture, distribution, lifecycle semantics or safety
  of destructive operations gets an ADR (`adr/NNNN-<slug>.md`, frontmatter per ADR-0004).
- Scripts: POSIX sh / bash 3.2, no mandatory dependencies besides `git` (ADR-0002).
  Every script command has a test under `tests/`.
- Skills are short; mechanics go to scripts (ADR-0001).
- Task-specific notes live in `.ai/workspace/tasks/<id>/` (gitignored), never in the repo.
- Before finishing a task, ask: what here should survive the task? Update
  `.ai/knowledge/` accordingly, or state `NO_DURABLE_KNOWLEDGE`.
