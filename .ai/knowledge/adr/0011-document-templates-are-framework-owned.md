---
id: adr-0011-document-templates-are-framework-owned
type: adr
status: accepted
date: 2026-09-08
domains:
  - knowledge
  - distribution
paths:
  - scripts/lib/init.sh
  - scripts/lib/upgrade.sh
  - "templates/knowledge/**"
reviewed_at: 2026-09-09
summary: Why knowledge templates ship with the framework instead of living in a skill.
---
# ADR-0011: Knowledge document templates are installed as framework-owned files

## Context

`templates/knowledge/` holds five templates. `init` seeded only three of them —
`GLOSSARY.md`, `ARCHITECTURE.md`, `RULES.md` — into `.ai/knowledge/`, where they become
project-owned the moment they are written (ADR-0003). The other two, `feature.md`,
`adr.md` and `convention.md`, stayed in the framework checkout.

The consequence was invisible while the framework was only ever used from its own
checkout: a consumer project had no feature, ADR or convention template at all. Nothing
could instantiate one, so `jig knowledge new` had nothing to copy, and the shape of a
document existed only as prose inside a skill.

## Decision

`init` and `upgrade` install `templates/knowledge/` into `.ai/templates/knowledge/` as
**framework-owned** files, through the same conflict-aware placement and manifest
machinery that carries `.ai/scripts/` and `.ai/profiles/` (copy mode) or the same
relative symlink (link mode).

Framework-owned, not project-owned: a project does not edit these, `upgrade` carries
improvements forward, and a locally modified template is reported as a conflict rather
than silently replaced (domains/install).

The three global documents keep their existing treatment — seeded once, project-owned
forever. A project's `RULES.md` is its own; the template that started it is not.

## Alternatives

- **Heredocs inside `scripts/lib/knowledge.sh`.** Rejected: a template is content, and
  editing content should not mean editing a script. It also hides the template from
  `upgrade`'s conflict detection, so a project could never see that the shape of an ADR
  had changed.
- **The template inline in `skills/jig-consolidate/SKILL.md`.** Rejected: it duplicates
  the source of truth once per adapter, and ADR-0001 keeps skills short by moving exactly
  this kind of material out of them.
- **Fetch the template from the framework checkout on demand.** Rejected as the primary
  mechanism: a consumer project has no checkout to fetch from. It survives only as the
  fallback `jig knowledge new` uses for a project installed before this decision.

## Consequences

- `.ai/templates/` is a new tracked directory in every project. It is listed in
  `domains/install` among the framework-owned paths.
- `jig knowledge new` works in a consumer project with no framework checkout present.
- Changing a template is now a versioned, reviewable event: it reaches projects through
  `upgrade`, with a conflict reported if the project edited it.
- `jig_is_source_root` tests for `skills/` *and* `templates/` *and* `scripts/jig`. An
  installed project now has `.ai/templates/` and `.ai/scripts/jig` but never `.ai/skills/`,
  so it is still not mistaken for a source checkout — the `skills/` condition is what
  carries that distinction and must not be dropped.
