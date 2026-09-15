# Specification files

`.ai/specs/<spec-id>/`, committed. Reference: ADR-0035. Created by `jig spec new <id>`,
developed by the `jig-idea` skill; everything `jig spec list` and `jig status` report is read
from these files.

## Directory

| Path | Required | Content |
|---|---|---|
| `spec.md` | yes | idea, goal and problem, stress test, scope and non-goals, decisions, open questions, untested assumptions, depth |
| `roadmap.md` | yes | destination, phases, items, waves |
| anything else | no | `architecture.md`, `stack.md`, `research.md`, … |

`<spec-id>` follows the task id grammar (`jig_valid_id`): letters, digits, `.`, `_`, `-`, no
leading dot or dash. A directory with any other name is skipped by every listing. A spec
missing a required file is listed as `incomplete (no spec.md)`, `incomplete (no roadmap.md)`
or `incomplete (no spec.md, roadmap.md)` — not an error.

## `spec.md`

The first line starting with `# ` is the spec's title in `jig spec list`; `-` when there is
none. The sections are the template's (`templates/spec/spec.md`); no script reads them.

## `roadmap.md`

Only checkbox lines — `-` or `*`, then `[ ]`, `[x]` or `[X]` — are counted. Everything else
is prose to the script, including the numbered `## Waves` list.

| Line | Counted as |
|---|---|
| `- [x] …` | done |
| ``- [ ] `task-id` — goal`` | filed: a backticked id of the task id grammar, then whitespace, a dash (`—`, `-` or `--`) and whitespace |
| `- [ ] fog: area — why` | fog |
| `- [ ] anything else` | a planned item, not filed |

A line that opens with a backticked command rather than a task id, like
``- [ ] `jig spec remove` with flags``, is a planned item: the id grammar has no spaces, and
``- [ ] `jig-consolidate` checks the item`` has no dash after the backticks.

`jig spec list` prints `roadmap <done>/<total> done, <filed> filed, fog <fog>`.

## Conventions the script does not check

- One destination sentence before the first phase.
- An item is a finished slice, never a layer; a dependency carries a one-line reason:
  `(after: `<id>` — <reason>)`.
- No dates and no point estimates.
- A `task-id` is added when the item's task is filed; `[x]` when that task is closed.
