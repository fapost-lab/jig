# Knowledge document frontmatter

Applies to every file under `.ai/knowledge/features/`, `adr/`, `conventions/`.
`GLOSSARY.md`, `ARCHITECTURE.md`, `RULES.md` are global and carry no frontmatter.
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
| `id` | yes | `^[a-z0-9-]+$`, unique across `.ai/knowledge/`; prefix with the type: `feature-`, `adr-NNNN-`, `convention-` |
| `type` | yes | `feature`, `adr`, `convention` |
| `status` | yes | feature/convention: `active`, `deprecated`, `superseded`; adr: `accepted`, `superseded`, `deprecated`, `rejected` |
| `date` | adr only | `YYYY-MM-DD` |
| `domains` | no | list of `^[a-z0-9-]+$` tags used by `jig context --domains` |
| `paths` | no | list of globs relative to the repository root, matched by `jig context --files`; `**` matches any depth |
| `supersedes` | no | id of the document this one replaces |
| `reviewed_at` | no | `YYYY-MM-DD`, when the document was last reconciled with the code it describes; read by `jig knowledge stale` (ADR-0010) |

## Checks performed by `jig knowledge check`

| Finding | Severity |
|---|---|
| missing frontmatter on a non-global document | fail when `knowledge.require_frontmatter: true`, else warn |
| missing or invalid `id`, `type`, `status` | fail |
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
| `jig knowledge new <type> <slug>` | instantiate `.ai/templates/knowledge/<type>.md`, allocating the next ADR number |
| `jig knowledge paths add\|remove <id> <glob>` | maintain one document's `paths` |
| `jig knowledge reviewed <id>` | stamp `reviewed_at` |
| `jig knowledge stale` | `stale` / `unreviewed` / `orphaned` (stamped, code gone) / `planned` (never stamped, code not written yet) |

`jig knowledge paths` with no subcommand reports the gap in both directions: files the
task touched that no document claims, and globs that claim nothing.
