---
name: jig-init
description: Bootstrap or refresh a project's durable knowledge with Jig. Use when setting up Jig in a repository, when `.ai/knowledge/` is empty or stale, or when the user says "init jig", "set up project knowledge", "analyze the project".
---

# jig-init — populate project knowledge

Goal: after this skill, `.ai/knowledge/` states what the project is, which terms are
canonical, how it is structured and which rules hold. Write intent, not a code tour.

## 1. Bootstrap

Run `.ai/scripts/jig status`. If it reports the project is not initialised, run
`.ai/scripts/jig init` (or `<framework>/scripts/jig init` when the scripts are not yet
installed) and show the user what it created. Never overwrite existing knowledge.

## 2. Analyze the repository

Read only what is needed to answer the questions below. Prefer manifests, entry points,
directory names and existing docs over reading source files broadly.

- What does the system do, for whom?
- Which domains exist and where do they live in the tree?
- Which direction may dependencies point? Which layers exist?
- Which words are used for the core concepts, and are they used consistently?
- Which rules are already enforced (lint config, CI, tests) or clearly assumed?

## 3. Write knowledge

- `GLOSSARY.md`: one entry per core concept; pick the canonical term when the code
  uses several. Keep to terms a newcomer would get wrong.
- `ARCHITECTURE.md`: domains, boundaries, dependency direction, the two or three key
  runtime flows, system-wide invariants. Do not restate implementation.
- `RULES.md`: enforced or clearly intended rules and invariants, each with its source.
- If a decision is visible in the code and worth preserving, add an ADR from
  `templates/knowledge/adr.md` with status `accepted`.

Ask the user when a term or boundary is ambiguous; do not guess canonical names.

## 4. Verify

Run `.ai/scripts/jig knowledge check` and fix every failure. Warnings about `paths`
matching nothing are acceptable only for documents that intentionally have no owning
files.

## 5. Report

Summarise in a few lines what was written and which questions remain open for the user.
