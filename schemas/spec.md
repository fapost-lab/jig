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

### Waves

`jig spec plan <id> --phase <n>` reads the `## Waves` list: lines `<n>. <entry>; <entry>; …`,
one numbered list over the whole roadmap, an indented line continuing the one above it. An entry
names the item whose **title** it equals — the item's text without a leading
``` `task-id` — ``` or `fog:`, up to the first dash with a space on each side (`—`, `--`, `-`) or
` (after:` — ignoring case, backticks and runs of spaces; or the item whose **task id** it is,
backticked or not. `Findings ledger` and `` `findings-ledger` `` both name
``- [ ] `findings-ledger` — Findings ledger — review records…``.

An entry that names no item (`unmatched`) or several (`ambiguous`), and an item two entries name
(`repeated`, then placed in no wave), are reported and never guessed. A wave holding such an entry
never counts as merged, so every later wave waits until the list is fixed. Items in no wave are
listed under their phase and never start.

The rule is strict: wave N opens only when every item of every wave numbered below it has
merged — whichever phase that item is in. Merged is read offline: the item is checked, its task is
`consolidated`, or the newest housekeeping run logged it `remote=merged`.

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

Linked tasks are found through their own `Spec:` lines among this checkout's workspaces; a workspace
that is itself a link — one task borrowed on its own, the older shape — is skipped without a word.
When `.ai/workspace/tasks` itself is a link to another checkout's whole tasks directory, this
checkout owns none of the tasks under it, and says so once, to stderr, before any per-task line, in
place of them: `jig: warning: spec remove: this checkout borrows its task workspaces, so no task is
unlinked here; run it in the checkout that owns them`. `--dry-run` prints the same lines as
`would-abandon`, `would-unlink` and `would-move` and changes nothing. Git is not touched.

A copy of a spec directory in another project is a separate spec; nothing links the two.

## The `Epic:` line in `roadmap.md`

A spec released once, at the end, declares its epic branch (ADR-0040) with one whole line, written
after `Destination:`:

| Line | Meaning |
|---|---|
| none | tasks are cut from `git.base_branch` |
| `Epic: epic/<spec-id>` | open: `jig task start` cuts linked tasks from the branch |
| `Epic: epic/<spec-id> — finished` | written by earlier versions of jig (`—`, `-` or `--`); refused by `task start` and `spec epic` — a finished epic's spec is removed now |

Parsed by `jig_spec_epic` in `common.sh`. Two lines that disagree on the branch or its state are a
conflict: `task start` and `spec epic` refuse. Any branch name is read; a caller checks it with
`git check-ref-format --branch` before building a ref.

A `Release: patch|minor|major` line, written under the `Epic:` line by `jig spec epic <id> --release
<level>` when the epic is declared, records how far the epic's final pull request raises the version.
Every line starting with `Release:` is read: a value other than the three, or two lines that disagree,
is refused by `spec epic` and `spec ship`. No line means the level was not recorded; `--finish` prints
`release: <level>` or `release: not recorded`.

`jig spec list` shows, for an open epic: the usual progress and `(on <branch>)` when the checkout is
on the epic; `<branch> — progress is on the epic` elsewhere; `<branch> — branch missing` when neither
the local nor the origin ref exists. A legacy finished line shows the usual progress. `jig status` prints
`epic: <id> on <branch>, <n> commits behind <default>` or `epic: <id> on <branch>, branch missing`
for each open epic.

## Leftovers and closing a spec

A spec lives while it holds work not yet done (ADR-0035 as amended). Its leftovers are what removing it
would lose: every unchecked roadmap item, `fog:` included, and every entry of the "Open questions" and
"Assumptions left untested" sections of `spec.md`; the template's `<placeholder>` entries are not
leftovers. A human decides each one — moved to another spec or task, or dropped — before the spec goes.

When `jig spec done` leaves no planned item unchecked it prints `roadmap complete` and the command that
closes the spec. `jig spec close <spec-id> [--leftovers-handled]` closes a spec without an epic: it lists
the leftovers and refuses until `--leftovers-handled` confirms the decision, then moves the directory to
`.ai/runtime/trash/<date>/spec-<id>` without touching any task's `Spec:` line. The removal is committed
with the change that finished the spec. A spec with an `Epic:` line is refused: its epic closes it.

## `jig spec epic <spec-id> [--release patch|minor|major | --finish [--leftovers-handled] | --reopen]`

| Situation | Result |
|---|---|
| no `Epic:` line | the line is inserted after `Destination:` (error without one), with `Release: <level>` under it when `--release` is given; commit it and merge it into the default branch |
| `--release` with an `Epic:` line already there, or with `--finish`/`--reopen` | error |
| open line, branch exists locally or on origin (after a fetch) | `exists: <branch>`, exit 0 |
| open line, not yet on the freshest default branch's committed roadmap | error |
| open line, on the default branch | `created: <branch> at <sha>` — a local branch, no checkout; pushed by `jig spec ship` or by the human, by `agent.git` |
| legacy finished line | error |
| `--finish` | on the epic only, which must contain the freshest default branch; the leftover gate of `spec close`, then the spec directory is removed — committed with the version bump, carried to the default branch by the epic's final pull request |
| `--reopen` | spec absent, on the epic it declared: restores the directory from git — from `HEAD` while the removal is uncommitted, else from before the commit that deleted its roadmap — without touching the index |

The line printed after each step names the next one by `agent.git`: `jig spec ship <id>` where the
level lets the agent take it, the git command or pull request that is the human's where it does not.

## `jig spec ship <spec-id> [--message-file <file>] [--title <t>] [--body-file <file>]`

Carries spec work as far as `agent.git` allows (adr-20260922-spec-work-ships-by-the-agent-git-level),
through the git steps `jig task ship` uses. It never merges. At `none` it exits 3, changing nothing; an
invalid level, a detached `HEAD`, anything staged under `.ai/workspace/` or `.ai/runtime/`, and an
invalid `Release:` line are errors. The mode is read from the checkout and printed first:

| Mode | When | What it does |
|---|---|---|
| `declare` | the spec is here, and its open `Epic:` line is not on the freshest default branch (or it has none) | requires `--message-file`; everything staged must be under `.ai/specs/<id>/`; on the default branch it switches to a new `spec/<id>` first (error when that branch exists), on an `epic/*` branch it refuses; commits, pushes the branch, opens the pull request into the default branch |
| `epic` | the spec is here, its `Epic:` line is on the default branch or the checkout is on the epic, and the epic exists locally | refuses when anything is staged; pushes the epic (`push` and up), never forced |
| `final` | the spec is gone, and the checkout is on the epic its removed roadmap declared | requires `--message-file`, the freshest default branch in the epic, and the removal of `.ai/specs/<id>/` staged; commits, pushes the epic, opens the pull request into the default branch |

Each step prints what `task ship` prints — `committed <sha>` or `nothing staged; no commit`,
`pushed <branch>`, `pr <url>` or `pr <url> (already open)`, `no forge available; …` — and a level that
stops earlier ends in `stopped at …`. The title is the message's first line unless `--title`; the body
the rest of it unless `--body-file`.
