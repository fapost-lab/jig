# Knowledge document frontmatter

Applies to every file under `.ai/knowledge/` except the three global documents.
`.ai/knowledge/GLOSSARY.md`, `.ai/knowledge/ARCHITECTURE.md` and
`.ai/knowledge/RULES.md` are global and carry no frontmatter — recognised by their
repository-relative path, so `domains/payments/RULES.md` is an ordinary document that
must carry frontmatter like any other.
Reference: SPEC §8, ADR-0004. Parsed by `scripts/lib/frontmatter.sh` without a YAML
library, so the subset below is the whole grammar.

## Grammar

```
---
key: scalar
key: [item, item]
key:
  - item
  - "quoted item"
---
```

- The block starts on line 1 with `---` and ends at the next line that is exactly `---`.
- Keys are `[a-z_]+`. Scalars run to end of line; a trailing `# comment` is stripped.
- Lists are either inline `[a, b]` or block `  - item` (two-space indent, one level).
  Items may be double-quoted; quotes are stripped.
- No nesting, no multi-line scalars, no anchors.
- A value may not contain `#`: the reader strips a trailing comment before it
  strips quotes, and the grammar has no escape. The writers refuse such an item
  rather than write one that reads back corrupted.
- `--domains` and `--paths` on `jig knowledge new` are comma-separated, so a single
  glob cannot itself contain a comma. Add such a glob with
  `jig knowledge paths add <id> <glob>`, which takes one value.

## Fields

| Field | Required | Values |
|---|---|---|
| `id` | yes | `^[a-z0-9-]+$`, unique across `.ai/knowledge/`; prefix with the type: `feature-`, `adr-NNNN-`, `convention-`, `domain-`, `glossary-`, `rule-` |
| `type` | yes | `feature`, `adr`, `convention`, `domain`, `glossary`, `rule` |
| `status` | yes | everything except adr: `active`, `deprecated`, `superseded`; adr: `accepted`, `superseded`, `deprecated`, `rejected` |
| `date` | adr only | `YYYY-MM-DD` |
| `summary` | no | one-line scalar shown in the `jig context resolve --catalog` listing |
| `domains` | no | list of `^[a-z0-9-]+$` tags used by `jig context --domains` |
| `topics` | no | list of `^[a-z0-9-]+$` tags describing conceptual applicability, matched by `jig context --topics`; how a document reaches a task that touches no file it claims |
| `load` | no | `always`, `domain` or `matched` (default `matched`) — see below |
| `requires` | no | list of document ids that must be loaded whenever this document is; transitive and acyclic |
| `paths` | no | list of globs relative to the repository root, matched by `jig context --files`; `**` matches any depth |
| `supersedes` | no | id of the document this one replaces |
| `reviewed_at` | no | `YYYY-MM-DD`, when the document was last reconciled with the code it describes; read by `jig knowledge stale` (ADR-0010) |

## Load policy

`load` decides when `jig context resolve` requires a document's full body:

| Value | Required when |
|---|---|
| `always` | every resolution |
| `domain` | one of its `domains` is among the entered domains |
| `matched` (default) | one of its `paths` matches an affected file, or one of its `topics` matches a requested topic |

A `matched` document whose *domain* matches but whose paths and topics do not is **not**
required: it appears in the catalog (`--catalog`), where an agent can see its id and
summary and pull it in explicitly with `--ids`. Domain membership is a discovery signal,
not proof that the body is relevant — loading every document of an entered domain would
defeat the purpose of resolving context at all.

The stateless `jig context` form is unchanged and still promotes a domain match to
`matched:`. That difference is deliberate and is the one seam between the two forms.

## Domain packs

A domain may keep a pack under `.ai/knowledge/domains/<domain>/`:

| File | Type | Purpose |
|---|---|---|
| `OVERVIEW.md` | `domain` | orientation on entering the domain |
| `GLOSSARY.md` | `glossary` | terms specific to the domain |
| `RULES.md` | `rule` | constraints a change in the domain must not violate |

The directory is for human navigation and never implies applicability (ADR-0004): a
document filed under `domains/<d>/` must declare `<d>` in its own `domains`, and
`jig knowledge check` fails it when it does not. A document elsewhere may belong to the
domain just as well.

## Checks performed by `jig knowledge check`

| Finding | Severity |
|---|---|
| missing frontmatter on a non-global document | fail when `knowledge.require_frontmatter: true`, else warn |
| missing or invalid `id`, `type`, `status` | fail |
| invalid `load` value | fail |
| invalid `topics` item | fail |
| document under `domains/<d>/` that does not declare domain `<d>` | fail |
| `requires` naming an unknown id | fail |
| `requires` naming a document that is not active | fail |
| a cycle in the `requires` graph | fail |
| duplicate `id` | fail |
| ADR file name not `NNNN-<slug>.md` or duplicate number | fail |
| relative markdown link to a missing file | fail |
| `supersedes` pointing to an unknown id | fail |
| invalid `reviewed_at` (not `YYYY-MM-DD`) | fail |
| `paths` glob that matches no file in the repository | warn |
| document without `domains` and without `paths` | warn |

## Maintenance

Frontmatter is written by scripts, not by hand — `paths` items are globs full of
characters that a careless `sed` would eat (ADR-0001, convention-shell):

| Command | Effect |
|---|---|
| `jig knowledge new <feature\|adr\|convention> <slug>` | instantiate `.ai/templates/knowledge/<type>.md`, allocating the next ADR number |
| `jig knowledge new <domain\|glossary\|rule> <domain>` | instantiate the pack file under `.ai/knowledge/domains/<domain>/` from `.ai/templates/knowledge/domain/` |
| `jig knowledge paths add\|remove <id> <glob>` | maintain one document's `paths` |
| `jig knowledge reviewed <id>` | stamp `reviewed_at` |
| `jig knowledge stale` | `stale` / `unreviewed` / `orphaned` (stamped, code gone) / `planned` (never stamped, code not written yet) |

`jig knowledge paths` with no subcommand reports the gap in both directions: files the
task touched that no document claims, and globs that claim nothing.
