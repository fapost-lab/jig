# Task state file

`.ai/workspace/tasks/<task-id>/state`, flat `key: value` lines, one per key, no nesting.
Reference: SPEC §15, ADR-0005, ADR-0008. Written only through `jig task`, atomically
(temp file then `mv`), last-write-wins.

| Key | Writer | Values |
|---|---|---|
| `task_id` | `jig task new` | `^[A-Za-z0-9][A-Za-z0-9._-]*$` (no leading dot, so `.`, `..` and hidden names are impossible); every `jig task` subcommand validates the id before touching the filesystem |
| `branch` | `jig task new` | branch name at creation |
| `class` | skill via `jig task set` | `T0` … `T4` |
| `status` | skills via `jig task set` | `active`, `ready`, `consolidated`, `abandoned` |
| `knowledge_consolidated` | `jig-consolidate` skill via `jig task set` | `true`, `false` |
| `domains` | skill via `jig task set` | comma-separated tags `^[a-z0-9-]+(,[a-z0-9-]+)*$`; used by `jig context` |
| `paused` | `jig task pause` / `resume` | `true`; the line is removed on resume, so an absent key means false |
| `paused_at` | `jig task pause` | `YYYY-MM-DD` |
| `paused_reason` | `jig task pause --reason` | one line of free text, optional |
| `paused_stash` | `jig task pause --stash` | stash commit SHA; the SHA, never the `stash@{n}` index, which shifts |
| `created_at` | `jig task new` | `YYYY-MM-DD` |
| `updated_at` | every `jig task set` | `YYYY-MM-DD` |

`jig task set` accepts only `class`, `status`, `knowledge_consolidated`, `domains` and
validates the value; every other key is refused, the four `paused*` keys included:
they are written only by `jig task pause` and `jig task resume` (ADR-0012).

Pause is orthogonal to `status`: a task paused while `ready` resumes as `ready`. A task
is a candidate for `jig task current` when its `branch` matches the checkout, its status
is `active` or `ready`, and `paused` is absent.

Remote merge state (`merged`, `open`, `closed`, `unknown`) is never written here; it is
derived by housekeeping on each run.

`jig task list` shows only live tasks (`active`, `ready`, paused included) unless
`--all` or `--status <s>` is given; `consolidated` and `abandoned` accumulate on a
long-lived branch and would otherwise crowd out the work in flight.

## Workspace files

| File | Created by | Purpose |
|---|---|---|
| `state` | `jig task new` | this file |
| `task.md` | `jig task new`, from `templates/task.md` or from `--from <file>` | goal, scope, notes; context also lists existing known artifacts |
| `discovery.md`, `spec.md`, `alternatives.md`, `design.md`, `plan.md`, `review.md`, `verification.md`, `handoff.md` | skills, when the task class calls for them | stage artifacts (SPEC §14) |

## Artifact input report (ADR-0020)

`jig task artifacts <id> [--provided discovery,design,...]` reads the class and reports
fixed-route documentary dependencies. `present` means a readable nonempty regular file
inside this workspace. An external linked file, empty file or unavailable input has a
reason. `provided-claim` names output the caller actually located in conversation or another
artifact; it is not persisted or validated. Known optional kinds are discovery, spec,
alternatives, design, plan, review, verification and handoff; task.md itself is inspected.

T1 implementation consumes discovery; T2 planning consumes discovery and implementation/
review/verify consume plan. T3 design consumes discovery and gate/implementation/
architecture-review/verify consume design. T4 specification consumes discovery, alternatives
consumes spec, design consumes spec+alternatives, and gate/implementation/review/verify
consume spec+design. T3/T4 consolidation consumes verification. All stages also consume
task.md; T0 has no additional documentary prerequisite.

Stage rows report inputs-available/needs-input, with semantic prerequisites separately
unassessed. Missing optional artifacts do not block unrelated stages. Exit 0 means the
report succeeded, even with missing inputs; invalid invocation/inspection exits 1.
Neither presence nor a provided claim proves approval, content quality or completion.
No state fields or transitions are added. Workspace-free T0/T1 need not call the command.

## Review scope (ADR-0022)

`jig task changes <id> --base <ref> [--files <a,b|->] [--format report|paths]` requires an
explicit commit base and inventories committed, staged, unstaged and untracked layers
separately. The report includes resolved base/HEAD, path layers and excluded candidate
count; paths format prints their sorted union only. Paths are literal repository-relative
file names; stdin permits spaces/commas, explicit empty scope stays empty, and dot segments,
absolute names and tab/newline names fail. Git failures do not become empty success.

The base and ownership evidence live in task artifacts, not state. Mixed files still need
hunk ownership evidence and actual patch inspection; inventory is not a review verdict.
