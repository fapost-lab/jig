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
| `task.md` | `jig task new`, from `templates/task.md` or from `--from <file>` | goal, scope, notes; the only file `jig context` lists by default |
| `discovery.md`, `spec.md`, `design.md`, `plan.md`, `review.md`, `verification.md` | skills, when the task class calls for them | stage artifacts (SPEC §14) |
