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
- A `task-id` is added when the item's task is filed; `[x]` is set by `jig spec done` when that
  task's knowledge decision is recorded, never by hand.

## The `Spec:` line in a task

A task filed from a roadmap carries one line in its `.ai/workspace/tasks/<task-id>/task.md`:

```text
Spec: .ai/specs/<spec-id>/ — Phase <n>
```

The whole line must match: `Spec: .ai/specs/<spec-id>/`, then optionally whitespace, a dash (`—`,
`-` or `--`), whitespace and `Phase <n>`. A `<spec-id>` outside the id grammar links to nothing. Two
lines naming different specs are a conflict: `jig spec done` refuses, `jig spec remove` leaves the
task alone and names it. No field in `state` carries the link.

## `jig spec done <task-id>`

| Situation | Result |
|---|---|
| no `Spec:` line | `spec done: <id> is not linked to a spec`, exit 0 |
| unchecked items name the task | all of them become `[x]`, written atomically; the marked lines are printed |
| every item naming it is checked | `already done`, exit 0, file unchanged |
| no item names it | error: the roadmap and the task disagree |
| spec or its `roadmap.md` missing, two specs linked | error |

An item names the task when its text starts with the backticked id and a dash — the "filed"
grammar above — compared as a string. Run when the knowledge decision is recorded, before the
commit (ADR-0035).

## `jig spec remove <spec-id> [--dry-run] [--abandon-unstarted]`

Report lines, one per decision:

| Line | Meaning |
|---|---|
| `abandoned <id> (not started)` | with `--abandon-unstarted`: no `branch`, or `branch` without `base_commit`; done through `jig task abandon`, before unlinking |
| `unlinked <id>` | an open linked task lost its `Spec:` lines for this spec; the rest of `task.md` is unchanged |
| `kept <id> (consolidated\|abandoned)` | closed tasks keep their line |
| `kept <id> (links to more than one spec)` | conflict, untouched |
| `not-here <id> (…)` | the roadmap names the id; no workspace in this checkout |
| `moved .ai/specs/<id> -> .ai/runtime/trash/<date>/spec-<id>` | `-2`, `-3` when taken |

Linked tasks are found through their own `Spec:` lines among this checkout's workspaces; workspace
links are skipped. `--dry-run` prints the same lines as `would-abandon`, `would-unlink` and
`would-move` and changes nothing. Git is not touched.

A copy of a spec directory in another project is a separate spec; nothing links the two.
