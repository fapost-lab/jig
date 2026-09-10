---
id: adr-0023-agent-language-is-prose-not-configuration
type: adr
status: accepted
date: 2026-09-10
domains:
  - config
  - skills
paths:
  - templates/AGENTS.md
  - .ai/config.yaml
summary: Why the agent's language is stated in AGENTS.md rather than configured, and why interaction language is personal, not project-level.
---
# ADR-0023: Agent language is prose in AGENTS.md, not configuration

## Context

A project may want its agent to speak one language and write its documents in another —
Russian in the session, English in the repository. Task `agent-language-config` proposed
two keys in `.ai/config.yaml`: `language.interaction` and `language.documentation`.

Discovery established that the framework has no language concept at all today, and that
the skills already draw exactly the split the two settings would need: 17 destinations
where a skill writes a durable artifact, 16 where it reports to the user. The distinction
is real. The question the design had to answer was narrower: does a configuration key buy
anything that prose in an instruction file does not.

## Decision

**No language configuration. The project states its documentation language in
`AGENTS.md`, and `templates/AGENTS.md` prompts it to.**

The argument that decided it: a script cannot act on a language value. Checking what
language a document is written in requires an LLM, and ADR-0001 forbids scripts from
invoking one. So the consumer of `language.documentation` would not be a script — it
would be an LLM reading text. And an LLM reading `language: documentation=en` from
`jig context` output is not meaningfully different from the same LLM reading "write
documents in English" from `AGENTS.md`, which it already loads.

`AGENTS.md` is also the better-shaped home on every ownership test. It is committed, so
the answer is the same for every contributor — which is what makes documentation language
a project property in the first place. It is project-owned, so nobody is overruled by the
framework. And every runtime reads it, unlike `CLAUDE.local.md`, which is a Claude Code
convention that the `codex` adapter would not see.

**Interaction language is out of scope, because it is not a project property.** Two people
on one repository may want different session languages and neither is wrong. It belongs in
the individual's own runtime-local instruction file, where it already works.

## Alternatives

- **Two keys in `.ai/config.yaml`, delivered through `jig context`.** Rejected: the keys
  have no mechanical consumer, and `jig context` only reaches turns that a skill drives —
  never a plain conversational turn, which is exactly where an interaction language would
  have to apply.
- **A marker-delimited managed block in `AGENTS.md`, rewritten by `jig upgrade`.** The only
  always-on channel. Rejected: `AGENTS.md` is project-owned and `upgrade` never rewrites it
  (ADR-0003, RULES.md invariant), so this needs a new ownership mode to carry a value that
  earns nothing.
- **A gitignored user settings file (`.ai/config.local.yaml`) as a new per-user
  configuration tier.** Rejected here, though it is the right shape for the problem it
  solves: it dissolves the ADR-0003 conflict, because a gitignored generated file is not
  project-owned. It fails for a different reason — it still cannot reach a plain
  conversational turn, so it would buy the same nothing at the cost of a new configuration
  tier. Worth revisiting if a per-user setting appears that a script can actually act on.
  Note also that `.gitignore` is created once from `templates/gitignore` and then owned by
  the project, so a new ignored path would not reach projects that installed Jig earlier —
  their user settings would be committed, which is the leak such a file exists to prevent.
- **A separate value for code comments.** Rejected: `jig-implement` already says "write
  like the codebase, not like yourself", so a Russian-commented codebase keeps its Russian
  comments with no setting. A third value would only add a way to contradict the
  surrounding code.

## Consequences

- `templates/AGENTS.md` gains one working rule telling a new project to state its
  documentation language, and saying that session language is personal, not project-level.
  That is the whole change; no script, schema or skill is touched.
- Nothing validates the stated language. That is accepted: the alternative is an LLM in a
  script, which ADR-0001 rules out.
- If a project wants per-user settings later, this ADR does not block it. It records that
  language alone does not justify the tier.
- `agent-language-config` closes without shipping a feature. The gate rejecting a design is
  the gate working; the reasoning is kept here so the next attempt starts from it instead
  of re-deriving it.
