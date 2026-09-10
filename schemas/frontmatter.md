# Knowledge document frontmatter

Applies to every file under `.ai/knowledge/` except the three global documents.
`.ai/knowledge/GLOSSARY.md`, `.ai/knowledge/ARCHITECTURE.md` and
`.ai/knowledge/RULES.md` are global and carry no frontmatter — recognised by their
repository-relative path, so `domains/payments/RULES.md` is an ordinary document that
must carry frontmatter like any other.
Reference: ADR-0004. Parsed by `scripts/lib/frontmatter.sh` without a YAML
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
- A value may not contain `#` or `"`: the reader strips a trailing comment before it
  strips quotes, and the grammar has no escape. The writers refuse such a value
  rather than write one that reads back corrupted.
- **A scalar containing `: ` must be double-quoted.** jig's own reader takes
  everything after the first `key: ` and so accepts `summary: Terms: a, b`, but a
  real YAML parser reads it as a nested mapping and rejects the whole document —
  which is how editors and any other tool see this file. `fm_set` (and therefore
  `jig knowledge summary`) quotes it for you; `jig knowledge check` fails a document
  where something else wrote it unquoted.
- `--domains` and `--paths` on `jig knowledge new` are comma-separated, so a single
  glob cannot itself contain a comma. Add such a glob with
  `jig knowledge paths add <id> <glob>`, which takes one value.

## Fields

| Field | Required | Values |
|---|---|---|
| `id` | yes | `^[a-z0-9-]+$`, unique across `.ai/knowledge/`; prefix with the type: `feature-`, `adr-NNNN-`, `convention-`, `domain-`, `glossary-`, `rule-` |
| `type` | yes | `feature`, `adr`, `convention`, `domain`, `glossary`, `rule` |
| `status` | yes | `proposed` for any type; then everything except adr: `active`, `deprecated`, `superseded`, `rejected`; adr: `accepted`, `superseded`, `deprecated`, `rejected` |
| `date` | adr only | `YYYY-MM-DD` |
| `summary` | no | one-line scalar shown in the `jig context resolve --catalog` listing |
| `domains` | no | list of `^[a-z0-9-]+$` tags used by `jig context --domains` |
| `topics` | no | list of `^[a-z0-9-]+$` tags describing conceptual applicability, matched by `jig context --topics`; how a document reaches a task that touches no file it claims |
| `load` | no | `always`, `domain` or `matched` (default `matched`) — see below |
| `stages` | no | list of route-stage names; additive promotion for matched catalog documents inside entered domains (ADR-0021) |
| `requires` | no | list of document ids that must be loaded whenever this document is; transitive and acyclic |
| `paths` | no | list of globs relative to the repository root, matched by `jig context --files`; `**` matches any depth |
| `supersedes` | no | id of the document this one replaces |
| `reviewed_at` | no | `YYYY-MM-DD`, when the document was last reconciled with the code it describes; read by `jig knowledge stale` (ADR-0010) |

## Proposed knowledge

`status: proposed` is knowledge that has been written but not agreed to. The document
sits at its real path, is validated by `jig knowledge check`, and shows up as an ordinary
git diff — but **`jig context` never resolves it**, so nothing inferred can reach an
agent's context before a human decides. A proposal ends one of two ways, and either way
the document stays at its path — nothing under `.ai/knowledge/` is deleted by these
commands:

```
jig knowledge proposed          # list documents awaiting a decision
jig knowledge accept <id>...    # proposed -> active (adr: accepted)
jig knowledge reject <id>...    # proposed -> rejected
```

Resolution uses an allowlist — only `active` and `accepted` are loaded, listed in the
catalog, or usable as a `requires` target. A denylist of retired values would resolve
anything it had not heard of, including `proposed` and including a typo. `rejected` is
absent from that allowlist like every other historical status, so a rejected document
stays at its path and never resolves — it reads exactly like a `deprecated` or
`superseded` one to `jig context`. `--all` still shows everything, which is how a
proposed or rejected document is reviewed.

`jig-map` is the skill that writes proposed documents; nothing stops a human writing one
by hand.

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
| invalid `stages` item | fail |
| document under `domains/<d>/` that does not declare domain `<d>` | fail |
| `requires` naming an unknown id | fail |
| `requires` naming a document that is not active | fail |
| a cycle in the `requires` graph | fail |
| duplicate `id` | fail |
| ADR file name not `NNNN-<slug>.md` or duplicate number | fail |
| relative markdown link to a missing file | fail |
| `supersedes` pointing to an unknown id | fail |
| invalid `reviewed_at` (not `YYYY-MM-DD`) | fail |
| unquoted scalar containing `: `, which YAML reads as a nested mapping | fail |
| `paths` glob that matches no file in the repository | warn |
| resolvable document (`active`/`accepted`) with no `summary` | warn |
| document without `domains` and without `paths` | warn |

## Maintenance

Frontmatter is written by scripts, not by hand — `paths` items are globs full of
characters that a careless `sed` would eat (ADR-0001, convention-shell):

| Command | Effect |
|---|---|
| `jig knowledge new <feature\|adr\|convention> <slug>` | instantiate `.ai/templates/knowledge/<type>.md`, allocating the next ADR number |
| `jig knowledge new <domain\|glossary\|rule> <domain>` | instantiate the pack file under `.ai/knowledge/domains/<domain>/` from `.ai/templates/knowledge/domain/` |
| `jig knowledge paths add\|remove <id> <glob>` | maintain one document's `paths` |
| `jig knowledge stages add\|remove <id> <stage>` | add/remove optional stage relevance idempotently |
| `jig knowledge summary <id> <text>` | set the one-line `summary`; refuses `#`, which the reader would strip as a comment |
| `jig knowledge proposed` | list every document with `status: proposed` |
| `jig knowledge accept <id>...` | promote one or more `proposed` documents to `active` (adr: `accepted`) |
| `jig knowledge reject <id>...` | mark one or more `proposed` documents `rejected`; never deletes or moves the file |
| `jig knowledge inventory [--scope <dir>]` | deterministic facts about the repository's shape: tracked root files named individually (where manifests live), runtime instruction files, and tracked file counts per directory. It carries no knowledge of what a manifest *means* — that mapping is declared once in each profile's `detect` globs, and recognising it is the agent's judgement (ADR-0001). Prints neither the catalog nor the coverage gaps either — those are `jig context resolve --catalog` and `jig knowledge paths` |
| `jig knowledge reviewed <id>` | stamp `reviewed_at` |
| `jig knowledge stale` | `stale` / `unreviewed` / `orphaned` (stamped, code gone) / `planned` (never stamped, code not written yet) |

`jig knowledge paths` with no subcommand reports the gap in both directions: files the
task touched that no document claims, and globs that claim nothing.

## Stage relevance (ADR-0021)

Progressive resolve/pending/guard accept --stage: analyze, discover, specify, alternatives,
design, plan, implement, review, architecture-review, verify, consolidate. Human gates
use design context. `stages: [implement, review]` promotes a load: matched catalog document
only when one of its domains is entered and its stage matches. Existing path/topic/ID,
load: always/domain and requires selection is preserved. Stage is never an intersecting
filter. No stage/domain match leaves existing selection unchanged; metadata is optional.
New dependencies receive the same lifecycle filtering and hash-ledger checks as any other
required document. Missing mandatory globals, requested IDs or dependencies fail.

Write stages through `jig knowledge stages add|remove <id> <stage>`; unknown names fail.
Legacy stateless context rejects --stage with guidance to use resolve. Both context forms
support --no-task, conflicting with --task, for research without implicit workspace/domain
selection. Explicit file/domain/topic selectors remain available in their respective forms.
