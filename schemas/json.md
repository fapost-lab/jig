# JSON output

What a command prints with `--json`. Reference: adr-20261015-a-read-is-one-json-envelope.
Written by `scripts/lib/json.sh`, the one place Jig writes JSON, in shell and without `jq`
(ADR-0002). The contract tests are `tests/json.t.sh` (the envelope) and the `--json` tests of
each command's own test file (its `data`).

## The envelope

Every `--json` read prints exactly one line on stdout, whether it succeeded or was refused:

```json
{"schema":1,"revision":null,"generated_at":"2026-10-15T12:00:00Z","data":{...}}
{"schema":1,"revision":null,"generated_at":"2026-10-15T12:00:00Z","error":{"code":"failed","message":"task list: invalid status: bogus"}}
```

| Field | Value |
|---|---|
| `schema` | `1`. Raised only on an incompatible change: a field removed, renamed or given another type. Adding a field is compatible and does not raise it, so a consumer ignores fields it does not know |
| `revision` | the clone's revision, which a consumer compares between reads and sends back with a write. **`null` until the per-clone counter exists** (task `clone-revision`): unknown, never "unchanged" |
| `generated_at` | when the read started, UTC, `YYYY-MM-DDTHH:MM:SSZ` |
| `data` | the command's answer, its shape below. Present only on success |
| `error` | instead of `data` when the command refused or failed: `code` and `message`, both strings. `message` is what the command printed after `jig: error:` (possibly several lines, joined by `\n`), or `exited with status <n>` when it said nothing. `code` is `failed` for every refusal until stable failure codes exist (task `failure-codes`) |

The exit status is the command's: 0 with `data`, non-zero with `error`. What the command says to a
person — warnings, notices — goes to stderr unchanged and never into the envelope. Reading never
touches the network: no forge CLI, no fetch.

Strings escape `"`, `\` and every control byte (`\n`, `\t`, `\r`, the rest as `\u00XX`); other
bytes pass through as they are, so a value is UTF-8 when what Jig read was. A value Jig has no
fact for is `null`, never an empty string or a missing key.

## `jig task list --json`

The tasks `jig task list` would show with the same arguments: live ones by default, every task with
`--all`, one status with `--status <s>`. `--json` may stand anywhere among them; `--goals` changes
nothing, since the goal is always in the data.

```json
{
  "tasks": [ <task>, ... ],
  "hidden": 4,
  "housekeeping": {"ran_at": "2026-10-15T09:00:00Z", "forge": "github"}
}
```

| Field | Value |
|---|---|
| `tasks` | one object per task, sorted by id |
| `hidden` | how many finished tasks (`consolidated`, `abandoned`) the selection left out; `0` with `--all` or `--status` |
| `housekeeping` | the last `jig housekeeping` run the flags below come from: `ran_at` (UTC) and `forge` (`github`, `gitlab`, `none`, `failed`, or `null` for a log older than the field); `null` when housekeeping never ran in this checkout |

A task:

| Field | Type | Value |
|---|---|---|
| `id` | string | the task id |
| `class` | string or null | `T0`–`T4`; `null` while unclassified |
| `status` | string | `active`, `ready`, `consolidated`, `abandoned` (schemas/state.md) |
| `issue` | string or null | the tracker issue the id starts with |
| `goal` | string or null | the first paragraph under `## Goal` in `task.md`, joined into one line |
| `knowledge_consolidated` | boolean | the knowledge decision is recorded |
| `paused` | boolean | |
| `created_at`, `updated_at` | string or null | `YYYY-MM-DD` |
| `branch` | string or null | `null`: the task has not been started |
| `base_branch` | string | the branch the task is judged against and lands on (`jig_task_base`): its recorded base, else `git.base_branch` |
| `worktree` | object or null | `{"path", "uncommitted"}`: the worktree, other than the checkout the command ran in, that has the task's branch checked out, and how many files there differ from its HEAD |
| `gate` | object or null | a T3/T4 design's gate: `{"state", "by"}`, `state` `waiting`, `changed` (the design moved after approval) or `approved`; `by` `human` or `agent`, `null` while waiting. `null` for any other class, or before `design.md` exists |
| `autopilot` | object or null | the task's autopilot run: `state` (`on`, `stopped`, `done`), `mode` (`attended`, `unattended`), `repairs` (integer), `stage` and `stage_at` (the last stage the current run entered), `stop_reason` and `stop_at` (the journal's last stop), `phase` (`<spec-id>/<n>` for a task of a phase run); each `null` when there is none. `null` when the task never ran on autopilot |
| `pull_request` | object or null | the pull request `jig task ship` opened: `{"url", "state", "ci", "fetched_at"}`. `null` when none was opened. `state` (`open`, `merged`, `closed`) and `ci` (`green`, `red`, `pending`, `none` — no check ran) are what the last `jig housekeeping` heard from the forge, at `fetched_at` (UTC), read from the forge cache below; each `null` when the cache does not say — no cache, no entry for the task's branch and base, or, for `ci`, a pull request that is not open or a forge whose list carries no checks (GitLab) |
| `housekeeping_flags` | array of strings | the flags of the last housekeeping run that still stand for the task — `needs-consolidation`, `wrong-base`, `abandoned?`, `worktree-kept`, `base-unreleased`, `STALE_CANDIDATE` — after the same local recheck the status page makes (a closed task is no longer `needs-consolidation`); `[]` for none |

### The forge cache

A read never asks the forge, so pull request state comes from `.ai/runtime/forge-cache`, which
`jig housekeeping` writes from the lists it already fetches (not on `--dry-run`): `gh pr list
--state all` for states, and on GitHub a second `gh pr list --state open` for the checks of the open
pull requests — two calls a run, whatever the number of tasks. One line per pull request, newest
first as the forge lists them, written atomically, `#` lines are comments:

```
<head>	<base>	<state>	<ci>	<fetched_at>
```

`<ci>` is `-` when it was not asked. A task's entry is the first line for its branch and base, the
join housekeeping's own remote state uses. A run whose forge did not answer, or that has no forge,
leaves the last cache as it is: an old entry says how old it is through `fetched_at`, and is never
refreshed by a reader. The file lives in the checkout that owns the task workspaces; a worktree
borrowing them (ADR-0029) reads the owner's and its own housekeeping writes none.

## `jig spec list --json`

The specs `jig spec list` shows, in the same order, each with its roadmap as data. It takes no
argument but `--json`.

```json
{"specs": [ <spec>, ... ]}
```

A spec:

| Field | Type | Value |
|---|---|---|
| `id` | string | the spec id, its directory under `.ai/specs/` |
| `title` | string or null | the first `# ` heading of `spec.md`; `null` without one |
| `missing_files` | array of strings | which of `spec.md` and `roadmap.md` are missing — what the text form calls `incomplete`; `[]` for none |
| `release` | string or null | `patch`, `minor` or `major` from the roadmap's `Release:` line (schemas/spec.md); `null` when it has none, or one `spec epic` and `spec ship` would refuse |
| `epic` | object or null | the roadmap's `Epic:` line, below; `null` when it has none |
| `progress` | object or null | `{"done", "total", "filed", "fog"}`, integers: the sum of `phases`, the counts the text form prints as `roadmap D/T done, F filed, fog G` (off an open epic the text form prints `progress is on the epic` instead, and these are the epic's). `null` when the roadmap could not be read — no `roadmap.md`, a missing epic branch, or an epic ref without it |
| `phases` | array | one object per roadmap section the status page counts (`spec_phase_counts`), in roadmap order; `[]` when `progress` is `null` |

`epic`:

| Field | Type | Value |
|---|---|---|
| `branch` | string | the epic branch |
| `state` | string | `open`, or `finished` for a legacy `— finished` line |
| `checked_out` | boolean | the checkout the command ran in is on the open epic — the text form's `(on <branch>)` |
| `missing` | boolean | the epic is open, not checked out here, and has neither a local nor an origin ref, or a name git refuses as a branch — the text form's `branch missing`. `progress` is then `null` |
| `ref` | string or null | the ref `phases` were read from: an open epic not checked out here is read from it (`refs/remotes/origin/<branch>` as of the last fetch, else `refs/heads/<branch>`) — the text form's `progress is on the epic`. `null` when the roadmap was read from this checkout |

A phase:

| Field | Type | Value |
|---|---|---|
| `phase` | integer or null | `<n>` of a `## Phase <n> — <title>` heading; `null` for the items of any other section, or before the first heading |
| `title` | string or null | the heading's title; for a section that is not a phase, its whole heading; `null` when there is none |
| `done`, `total`, `filed`, `fog` | integer | the section's counts, by the rules of schemas/spec.md. A phase is listed even with no items; another section only when it has some |
| `items` | array | the section's checkbox lines, in order |

An item — the counts above are the sum of its fields, read in the same pass:

| Field | Type | Value |
|---|---|---|
| `text` | string | the line after its checkbox, indented continuation lines joined with a space; tabs become spaces and trailing whitespace is dropped |
| `checked` | boolean | `[x]` or `[X]` |
| `task` | string or null | the backticked task id the text starts with, followed by a dash — the pattern `filed` counts; `null` otherwise. Read from checked items too |
| `fog` | boolean | the text starts with `fog:` |

`done` counts the checked items, `filed` the unchecked ones with a `task`, `fog` the unchecked ones
with `fog`. The roadmap is read where `jig status` reads it: an open epic's from its ref with no
fetch, every other one from this checkout.
