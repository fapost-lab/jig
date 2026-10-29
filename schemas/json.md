# JSON output

What a command prints with `--json`. Reference: adr-20261015-a-read-is-one-json-envelope.
Written by `scripts/lib/json.sh`, the one place Jig writes JSON, in shell and without `jq`
(ADR-0002). The contract tests are `tests/json.t.sh` (the envelope) and the `--json` tests of
each command's own test file (its `data`).

## The envelope

Every `--json` read prints exactly one line on stdout, whether it succeeded or was refused:

```json
{"schema":1,"revision":1792079790,"generated_at":"2026-10-15T12:00:00Z","data":{...}}
{"schema":1,"revision":1792079790,"generated_at":"2026-10-15T12:00:00Z","error":{"code":"usage","message":"task list: invalid status: bogus"}}
```

| Field | Value |
|---|---|
| `schema` | `1`. Raised only on an incompatible change: a field removed, renamed or given another type. Adding a field is compatible and does not raise it, so a consumer ignores fields it does not know |
| `revision` | the clone's revision: an integer every Jig write raises, one for the clone and all its worktrees. A consumer compares it between reads (different means something changed; equal means Jig wrote nothing) and, from `contract-queue` on, sends it back with a write. Taken before the data is read, so the data is never older than it. `0` before Jig's first write in the clone. The first write starts it at the time in seconds, so its value says nothing but itself: compare it, do not count with it. See "The revision" below |
| `generated_at` | when the read started, UTC, `YYYY-MM-DDTHH:MM:SSZ` |
| `data` | the command's answer, its shape below. Present only on success |
| `error` | instead of `data` when the command refused or failed: `code` and `message`, both strings. `message` is what the command printed after `jig: error:` (possibly several lines, joined by `\n`), or `exited with status <n>` when it said nothing. `code` is one of the failure codes below |

The exit status is the command's: 0 with `data`, non-zero with `error`. What the command says to a
person — warnings, notices — goes to stderr unchanged and never into the envelope. Reading never
touches the network: no forge CLI, no fetch.

Strings escape `"`, `\` and every control byte (`\n`, `\t`, `\r`, the rest as `\u00XX`); other
bytes pass through as they are, so a value is UTF-8 when what Jig read was. A value Jig has no
fact for is `null`, never an empty string or a missing key.

## Failure codes

`error.code` says why a read was refused, in a word a program can act on; `error.message` says it to
a person and may be reworded. The codes are part of the contract: one is never renamed or given
another meaning without raising `schema`. A new code may be added without raising it — a refusal
that has none yet reads `failed` until it gains one — so a program treats a code it does not know as
`failed`. The exit status keeps its meaning whatever the code: non-zero for every refusal.

| `code` | The read was refused because |
|---|---|
| `usage` | the command was given an argument it does not take, an option without its value, or a value outside the ones it accepts (`--status bogus`); `--json` beside an option it cannot be combined with too |
| `not-a-repository` | it ran outside a git repository |
| `not-initialised` | the repository has no Jig: no `.ai/config.yaml`; `jig init` installs it |
| `stale-revision` | a write was sent with a revision that is no longer the clone's: Jig wrote something after the caller read it (`jig queue … --revision <n>`, `jig task resume … --revision <n>`). Read again and decide again; nothing was written |
| `not-found` | a reference names no task or epic of this clone, or an item, dependency or request that is not in the queue where the command needs it |
| `not-paused` | `jig task resume` was asked for a task that is not paused: somebody resumed it first. Nothing was written |
| `wrong-checkout` | `jig task resume` has a stash to apply and this checkout is not on the task's branch; `message` names the worktree that has it checked out, or says to switch to it. Nothing was written |
| `stash-conflict` | `jig task resume` could not apply the task's stash: `git stash apply` refused and applied nothing, it merged the stash with conflicts or stopped part way, or a stash it merged earlier still has unresolved conflicts, or the checkout has unresolved conflicts of its own. The task stays paused and the stash entry is kept |
| `already-exists` | a write would create what the clone already has: `jig task new` with an id another task holds, `jig queue request` for a request already pending. Nothing was written |
| `upgrade-blocked` | `jig upgrade` would not start here and changed nothing: uncommitted changes, a started task's branch checked out, `jig verify` running in this checkout, or line endings Jig's files are not pinned against. For `jig upgrade --land`: uncommitted changes, a checkout on another branch than the base or the upgrade's, the base checked out in another worktree, or a base that cannot be fast-forwarded to origin's. `message` lists every reason, one per line, each with what to do |
| `not-merged` | `jig upgrade --land` found the upgrade's pull request still open on the forge. Nothing was changed; merge it and run the command again |
| `failed` | any other refusal: one that names no code of its own, a fault of the environment (a checkout that cannot be read, a failed command), or a producer that printed nothing |

A refusal names its code with `jig_fail <code> <message>` (`scripts/lib/common.sh`); `jig_die
<message>` is `failed`. Both print the same `jig: error: <message>` to a person. Inside a `--json`
read `jig_fail` also prints its code on the line before the message, behind a unit separator
(`\037jig: code: <code>`), and `json_run` takes the code from the marker right before the message it
reports and removes every marker from the stderr a person sees. A refusal without such a marker
next to its message — `jig_die`, a message printed by hand, a child `jig` — is `failed`, and so is a
marker that is not a code (lowercase words joined by `-`). `tests/json.t.sh` pins the mechanism; the
`--json` tests of each command pin the code of each of its refusals.

## The revision

What raises it: every write Jig makes to a record a read can report — a task's state, its
artifacts and `task.md`, the autopilot journal, findings, the review receipt, a spec's files
(`new`, `epic`, `done`, `close`, `remove`, `link`, and the unlink `remove` does), knowledge
documents (`new` and every frontmatter change), settings (`jig config set|unset`), the pull
request and CI cache housekeeping writes, the knowledge counts a full `jig status` saves (when a
count changed), and a
housekeeping run (once, when it ends; not `--dry-run`). One write raises
it at least once; a command that writes several times raises it several times.

What does not: a read, Jig's caches and records of what it is doing (the context cache, the
checkout record, the status page, the verify run), and — the accepted risk — **a file changed by
anything but a Jig write**: edited by hand, or by git, whoever ran it — a person's `pull` or
`checkout`, and Jig's own git steps too (the base checked out and fast-forwarded after a ship
merges, a spec's branch switch, `upgrade` and `init` placing files). A consumer that must see those
watches the files as well.

Reference: adr-20261016-the-clone-revision-is-a-claimed-name.

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
| `hidden` | how many finished tasks (`consolidated`, `abandoned`, `archived`) the selection left out; `0` with `--all` or `--status` |
| `archived` | how many of the `hidden` tasks are `archived`, so a reader knows whether there is anything to ask for with `--status archived`; `0` with `--all` or `--status archived` (they are in `tasks`) |
| `housekeeping` | the last `jig housekeeping` run the flags below come from: `ran_at` (UTC) and `forge` (`github`, `gitlab`, `none`, `failed`, or `null` for a log older than the field); `null` when housekeeping never ran in this checkout |

A task:

| Field | Type | Value |
|---|---|---|
| `id` | string | the task id |
| `class` | string or null | `T0`–`T4`; `null` while unclassified |
| `status` | string | `active`, `ready`, `consolidated`, `abandoned`, `archived` (schemas/state.md). `archived` is compatible with schema 1 because an archived task appears only to a caller who asks for it (`--status archived` or `--all`); a reader that lists the default selection never meets the value |
| `archived_at` | string or null | `YYYY-MM-DD`; `null` unless `status` is `archived` |
| `archived_reason` | string or null | `abandoned`, `stale`, `manual` or `absorbed`; `null` unless archived |
| `archived_from` | string or null | the status before the archive, `active`, `ready` or `abandoned`; `null` unless archived |
| `absorbed_into` | string or null | the task that absorbed this one whole; `null` otherwise |
| `absorbs` | array of strings | ids of the tasks this one absorbed whole; `[]` when none |
| `absorbs_partly` | array of strings | ids of the tasks this one takes part of; `[]` when none |
| `partly_in` | array of strings | ids of the tasks that take part of this one; `[]` when none |
| `issue` | string or null | the tracker issue the id starts with |
| `goal` | string or null | the first paragraph under `## Goal` in `task.md`, joined into one line, HTML comments (`<!-- … -->`) left out; `null` when nothing is left |
| `knowledge_consolidated` | boolean | the knowledge decision is recorded |
| `paused` | boolean | |
| `pause_request` | object or null | a pause asked of the task and not yet honoured (`jig queue request`): `{"requested_at", "reason"}`, `requested_at` UTC, `reason` `null` when none was given; `null` when none is pending. It holds until the task's next autopilot stage boundary pauses the task, a `jig task pause`, or a `jig queue cancel` |
| `created_at`, `updated_at` | string or null | `YYYY-MM-DD` |
| `branch` | string or null | `null`: the task has not been started |
| `base_branch` | string | the branch the task is judged against and lands on (`jig_task_base`): its recorded base, else `git.base_branch` |
| `worktree` | object or null | `{"path", "uncommitted"}`: the worktree, other than the checkout the command ran in, that has the task's branch checked out, and how many files there differ from its HEAD |
| `gate` | object or null | a T3/T4 design's gate: `{"state", "by"}`, `state` `waiting`, `changed` (the design moved after approval) or `approved`; `by` `human` or `agent`, `null` while waiting. `null` for any other class, or before `design.md` exists |
| `autopilot` | object or null | the task's autopilot run: `state` (`on`, `stopped`, `done`), `mode` (`attended`, `unattended`), `repairs` (integer), `stage` and `stage_at` (the last stage the current run entered), `stop_reason` and `stop_at` (the journal's last stop), `phase` (`<spec-id>/<n>` for a task of a phase run); each `null` when there is none. `null` when the task never ran on autopilot |
| `pull_request` | object or null | the pull request `jig task ship` opened: `{"url", "state", "ci", "fetched_at"}`. `null` when none was opened. `state` (`open`, `merged`, `closed`) and `ci` (`green`, `red`, `pending`, `none` — no check ran) are what the last `jig housekeeping` heard from the forge, at `fetched_at` (UTC), read from the forge cache below; each `null` when the cache does not say — no cache, no entry for the task's branch and base, or, for `ci`, a pull request that is not open or a forge whose list carries no checks (GitLab) |
| `housekeeping_flags` | array of strings | the flags of the last housekeeping run that still stand for the task — `needs-consolidation`, `wrong-base`, `abandoned?`, `worktree-kept`, `base-unreleased`, `STALE_CANDIDATE` — after the same local recheck the status page makes (a closed task is no longer `needs-consolidation`); `[]` for none |
| `actions` | array of objects | what a person may do next with the task: every row of the actions table below, in its order |

### Actions

What a person may do next with a task, as Jig decides it from the task's state
(adr-20261015-one-table-of-what-a-person-may-do). One table in Jig (`_task_actions`,
`scripts/lib/task.sh`); a consumer shows it and keeps no copy. Every task carries every row:

```json
{"id": "pause", "command": "jig task pause booking-message", "offered": true, "reason": null}
```

| Field | Type | Value |
|---|---|---|
| `id` | string | the action, one of the ids below; stable |
| `command` | string | the Jig command that takes it, with the task's id; a word in `<…>` is a value the person supplies — `<text>`, `<Tn>`, `<file>` |
| `offered` | boolean | `true` when the command accepts the action on the task's state as it is |
| `reason` | string or null | why it is not offered: the command's own refusal, word for word, or the table's for a move that makes no sense in this state; `null` when offered |

| `id` | `command` | Offered when |
|---|---|---|
| `start` | `jig task start <id>` | the task has not been started |
| `pause` | `jig task pause <id>` | it is not paused |
| `resume` | `jig task resume <id>` | it is paused |
| `request-pause` | `jig queue request task:<id> pause` | it is not paused and no pause of it is requested |
| `cancel-pause-request` | `jig queue cancel task:<id> pause` | a pause of it is requested |
| `approve-gate` | `jig task gate <id> approved` | a T3/T4 design waits at its gate (`waiting` or `changed`), and the gate is a person's: not in a clone or a run where nobody answers (`autopilot.unattended`) |
| `answer-stop` | `jig task autopilot <id> resume --answer <text>`, with ` --by human` for an unattended run | its autopilot run is `stopped`, and an unattended one has repairs left |
| `set-class` | `jig task set <id> class <Tn>` | the task is live |
| `ship` | `jig task ship <id> --message-file <file>` | the git level (`agent.git`, or `autopilot.git` for a run) is not `none`, the knowledge decision is recorded, no P0/P1 finding blocks, the review receipt is current, the route has its records, the task is started on a branch other than its base, and its pull request is not merged |
| `close` | `jig task set <id> status consolidated` | the knowledge decision is recorded, and the task opened no pull request or the forge cache says it merged |
| `abandon` | `jig task abandon <id>`, with ` --reason <text>` for a task whose `task.md` has a `Spec:` line | the task is live |
| `archive` | `jig task archive <id>` | the task is `active`, `ready` or `abandoned` |
| `unarchive` | `jig task unarchive <id>` | the task is `archived` |
| `reopen` | `jig task set <id> status active` | the task is `abandoned` |

A `consolidated` task offers nothing, an `abandoned` one only `reopen` and `archive`, an `archived` one only `unarchive` — except, for both,
`cancel-pause-request` while a pause of it is still requested.

The rule is one-way. An action offered is one its command accepts on the task's state, because the
table asks the command's own guard; the table may withhold more than a command refuses (a finished
task, a design already approved, a merged pull request). What a command refuses for reasons that are
not the task's state is checked when it runs, never here: the checkout it runs in (`ship` runs where
the task's branch is checked out — its `worktree`, when it has one — and so does `resume` when the
pause recorded a stash, which it applies there; a `resume` without a stash runs in any checkout;
`start` wants a clean, unoccupied checkout), what is staged, the network, and the value a person types (`set-class`
lowering a class needs `--reason`, and is refused below T3 where nobody answers). `close` is judged
by the forge cache, never the forge: a cache that says `merged` is final, and one behind the forge
withholds a close until the next `jig housekeeping`.

New ids may appear without `schema` changing, so a consumer ignores ids it does not know.

### The forge cache

A read never asks the forge, so pull request state comes from `.ai/runtime/forge-cache`, which
`jig housekeeping` writes from the lists it already fetches (not on `--dry-run`): `gh pr list
--state all` for states, and on GitHub a second `gh pr list --state open` for the checks of the open
pull requests — two calls a run, whatever the number of tasks. One line per pull request, newest
first as the forge lists them, written atomically, `#` lines are comments:

```
<head>	<base>	<state>	<ci>	<fetched_at>	<head_commit>	<url>
```

`<ci>` is `-` when it was not asked; `<head_commit>` and `<url>`, the pull request's head and its
address, are `-` when the forge did not say. A line written before those two columns existed ends
at `<fetched_at>` and reads as if both were `-`. A task's entry is the first line for its branch and base, the
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
| `done` | boolean | what the item counted as: `checked`, or its `task` is known in this checkout to have merged — `consolidated`, or logged `remote=merged` by the newest housekeeping run (schemas/spec.md) |
| `task` | string or null | the backticked task id the text starts with, followed by a dash — the pattern `filed` counts; `null` otherwise. Read from checked items too |
| `fog` | boolean | the text starts with `fog:` |

`done` counts the items whose `done` is `true`, `filed` the other unchecked ones with a `task`,
`fog` the unchecked ones with `fog`. The roadmap is read where `jig status` reads it: an open epic's from its ref with no
fetch, every other one from this checkout.

## `jig status --json`

What needs a person in this clone, as data: the items the status page shows under "Needs you", in
the same order, built by the same code (`_status_attention`, `scripts/lib/status.sh`) — the page
renders each item as a card and this command prints it as an object, so the two cannot disagree.
`--json` takes no other argument: with `--html`, `--open` or `--refresh` beside it the read is
refused, and a read never writes a page or counts. Run in a task worktree it reads the main
checkout — its workspaces, housekeeping log and saved counts — as the page does (ADR-0029), answered
by the jig that was asked. An uninitialised project is a refusal.

```json
{
  "attention": [ <item>, ... ],
  "housekeeping": {"ran_at": "2026-10-15T09:00:00Z", "forge": "github", "stale": false},
  "knowledge_counts_at": "2026-10-15T08:00:00Z"
}
```

| Field | Value |
|---|---|
| `attention` | the items, most urgent first; `[]` when nothing needs the reader |
| `housekeeping` | the last `jig housekeeping` run the pull request and flag items come from: `ran_at` (UTC), `forge` (as in `jig task list --json`) and `stale` — `true` when the forge did not answer or the run is older than `housekeeping.cadence`, so a pull request waiting for the reader may be missing. `null` when housekeeping never ran in this checkout |
| `knowledge_counts_at` | when the knowledge counts behind `knowledge-proposed` and `sources-changed` were taken (UTC): the counts the last full `jig status` saved for the page, read as they are; when there are none, the two knowledge counts are taken now and saved nowhere |

An item:

| Field | Type | Value |
|---|---|---|
| `kind` | string | what is needed, one of the kinds below; a program acts on this |
| `subject` | object | what the item is about: `{"type", "id"}`, `type` `task`, `phase` (`id` is `<spec-id>/<n>`) or `project` (`id` is `null`) |
| `tasks` | array of strings | the task ids the item is about: one for a task, every stopped task of the phase for a phase, `[]` for the project |
| `title` | string | what happened, for a person — the card's heading |
| `detail` | string or null | why, for a person: the stop reason with its age, the housekeeping run a fact was borrowed from, a count |
| `todo` | string | what the person should do, in plain words |
| `url` | string or null | the pull request's address, for the pull request kinds when jig knows it |
| `pull_request` | object | only on the two `upgrade-pull-request-*` kinds: `{"branch", "base", "state", "fetched_at"}` — the upgrade's branch (`jig/upgrade-<to>` or `jig/upgrade-<to>-<n>`), the base it goes into (`git.base_branch`), `open` or `merged`, and when housekeeping heard it from the forge |
| `versions` | object | on `upgrade-available`, `{"from", "to"}`; on the two `upgrade-pull-request-*` kinds, `{"to"}`, the version the branch is named for (`null` when the name holds none) |

The kinds, in the order they are listed:

| `kind` | `subject` | Needs a person because |
|---|---|---|
| `release-available` | project | a newer jig is out (`.ai/runtime/latest-release`, written by housekeeping) |
| `upgrade-pull-request-waiting` | project | an upgrade's pull request is open: the forge cache's newest line for a `jig/upgrade-*` branch into `git.base_branch` says `open`, and the base branch here does not already record its version (as it does right after `jig upgrade --land`, before housekeeping hears the merge). Merge it, then `jig upgrade --land`. One item per such branch |
| `upgrade-pull-request-merged` | project | an upgrade's pull request was merged, and the base branch here (`refs/heads/<git.base_branch>`) still records an older Jig than the version its branch is named for; `todo` is `jig upgrade --land`. A merged upgrade the base here already carries makes no item |
| `upgrade-available` | project | this project's installed Jig (the manifest's `jig.version`) is an older release than the one on this machine; `todo` is `jig upgrade`, and the item carries `versions: {from, to}` — the project's and the machine's. Not listed while an `upgrade-pull-request-*` item is: `jig upgrade` again would cut a second branch for the same upgrade |
| `phase-stopped` | phase | tasks of a phase run stopped; answered once, in the coordinator's session |
| `autopilot-stopped` | task | an autopilot run stopped with a question |
| `gate-waiting` | task | a T3/T4 design waits at its human gate |
| `gate-changed` | task | a design changed after it was approved |
| `git-step` | task | finished and consolidated; the next git step is the person's (`agent.git`) |
| `pull-request-waiting` | task | `jig task ship` opened a pull request that waits for review or merge |
| `pull-request-was-open` | task | the last housekeeping run saw a pull request open (it may have merged since) |
| `pull-request-of-abandoned-task` | task | the task was abandoned, and its pull request was open at the last housekeeping run |
| `needs-consolidation` | task | merged; the task can be closed |
| `wrong-base` | task | the work landed on another branch than planned |
| `closed-unmerged` | task | the pull request was closed without merging (housekeeping's `abandoned?`) |
| `worktree-kept` | task | a worktree was kept because it still holds work |
| `knowledge-proposed` | project | knowledge documents wait for a decision |
| `sources-changed` | project | adopted source files changed since they were approved |

The two `upgrade-pull-request-*` kinds come from the forge cache (above), never from the forge
itself, so they are as fresh as the last `jig housekeeping`; `jig upgrade --land` asks the forge
before it changes anything. The plain `jig status` prints the same facts as `upgrade pull request:`
lines.

A new kind may be added without raising `schema`; a program shows an unknown kind by its `title`,
`detail` and `todo`. The person-facing strings are not a contract: read `kind`, `subject` and
`tasks`.

## `jig queue` writes

`jig queue set|move|depend|undepend|remove <ref> … --json` change one item of the clone's queue
(adr-20261019-the-queue-is-one-file-written-against-a-revision) and answer in the envelope. A write
takes `--revision <n>`, the `revision` of the read the caller decided on; when anything was
written in the clone since, the write is refused with `stale-revision` and changes nothing. Without
`--revision` the command checks against the revision it reads itself as it starts. The envelope's
`revision` is taken before the write: with `--revision` the write was checked against the value
sent, without it against one the command read a moment later, which a write landing in between
makes newer than the envelope's — send `--revision` when that matters. A landed
write raises the revision past it (by two: the claim and the write), so read again for the new one.

```json
{"ref": "task:queue-file", "item": {"ref": "task:queue-file", "kind": "task", "id": "queue-file", "level": "epic:contract-queue", "position": 150, "priority": 0, "depends_on": [{"on": "task:other", "reason": "needs the format"}]}}
```

| Field | Type | Value |
|---|---|---|
| `ref` | string | the item written: `task:<id>` or `epic:<spec-id>` |
| `item` | object or null | the item as the queue now holds it; `null` after `remove` |
| `item.kind` | string | `task` or `epic` |
| `item.id` | string | the task id, or the spec id of the epic |
| `item.level` | string or null | `epic:<spec-id>` for a task built on that open epic; `null` on the top level, where epics and tasks without an epic are ordered together |
| `item.position` | integer | its place within its level, sparse: compare positions, do not count with them. A move changes the moved item only, unless no integer was left between its neighbours — then that one write respaced the whole level |
| `item.priority` | integer or null | `0` (most urgent) to `5`; `null` when not set. A label: the order is the positions' |
| `item.depends_on` | array | what the item waits for, each `{"on": <ref>, "reason": <string>}`, ordered by `on` |

Refusals: `usage` for an argument the command does not take, a priority outside `0`–`5`, a move
against an item of another level, a reference to itself or a dependency that would close a cycle;
`not-found` and `stale-revision` as above.

## `jig queue list --json`

The whole queue of the clone, the same for every worktree; `jig queue --json` is the same read. It
writes nothing and raises no revision.

```json
{"items": [<item>, ...]}
```

| Field | Type | Value |
|---|---|---|
| `items` | array | every queued item, each the object `item` of a write's answer above, in the queue's canonical order: the top level (`level` `null`) by `position`, then each epic's level (ordered by its `level`) by `position`; `[]` when nothing is queued |

Request lines (`request`, [Pause requests](#pause-requests) below) are read but not listed: `jig
task list --json` shows a task's pending pause as its `pause_request`. Lines of a kind this version
does not read (record kinds a later Jig adds to the file) are left out, never an error. A queue file of another format version is refused with `failed`, as is any
argument after `list` with `usage`.

Read with `jig task list --json`: a `task` item joins a task by `id`, an `epic` item a spec of
`jig spec list --json` by `id`. A task finished or gone stays queued until removed, so it may have
no match in the default listing (`--all` lists the finished ones). The envelope's `revision` is the
one to send with the next write, as for every read.

### Pause requests

`jig queue request <ref> pause [--reason <text>] … --json` asks a task to pause, and `jig queue
cancel <ref> pause … --json` takes the request back
(adr-20261019-a-pause-request-is-honoured-at-the-stage-boundary). Both are queue writes: the same
`--revision`, the same claim, the same `stale-revision`. A request is sticky: it holds until the
task reaches its next stage boundary — `jig task autopilot <id> stage` in an autopilot run, or `jig
context resolve --task <id> --stage <stage>`, the first step of every stage skill, with or without
one, either of which then pauses the task instead of entering the stage — until `jig task pause`
pauses it by hand, or until it is cancelled — whatever stage the task reaches in between.

```json
{"ref": "task:booking-message", "request": {"kind": "pause", "requested_at": "2026-10-19T12:00:00Z", "reason": "need the laptop"}}
```

| Field | Type | Value |
|---|---|---|
| `ref` | string | the task asked: `task:<id>` |
| `request` | object or null | the request as the queue now holds it; `null` after `cancel` |
| `request.kind` | string | `pause` |
| `request.requested_at` | string | when it was made, UTC; not changed by anything until it goes |
| `request.reason` | string or null | the reason given, on one line; `null` for none |

Refusals: `usage` for a reference that is not a task, a kind other than `pause`, or an argument the
command does not take; `not-found` for a task this clone does not have, and for `cancel` when no
pause of it is requested (`cancel` takes any well-formed reference, so a task gone to trash can still
have its request taken out); `already-exists` when a pause of it is already requested — its time
stays; `failed` when the task is paused, `consolidated` or `abandoned`. The `request-pause` and
`cancel-pause-request` actions ask the same guards.

## `jig queue next --json`

Which queued task to take next, and what holds the others back. It reads the queue, the tasks'
state files and what the last `jig housekeeping` run recorded, never the network, and writes
nothing: the queue file and the revision stay as they were. The producer's rules are the Jig
documentation's ("Order the work"); this is the shape.

```json
{"next": {"ref": "task:booking-form", "kind": "task", "id": "booking-form", "level": null, "position": 100, "priority": 1, "started": true}, "reason": null, "waiting": [{"ref": "task:booking-message", "on": "task:booking-form", "state": "unknown", "reason": "The message quotes the form"}], "not_queued": 1}
```

| Field | Type | Value |
|---|---|---|
| `next` | object or null | the task advised; `null` when there is none |
| `next.ref`, `next.kind`, `next.id` | string | `task:<id>`, `task` and the task id |
| `next.level` | string or null | as `item.level` of a write: `epic:<spec-id>`, or `null` on the top level |
| `next.position` | integer | its place within its level, as stored |
| `next.priority` | integer or null | `0` to `5`; `null` when not set |
| `next.started` | boolean | `true` when the task has its branch and base commit |
| `reason` | string or null | `null` when `next` is set; otherwise why there is none: `waiting` (a candidate waits for a dependency), `paused` (the queued tasks left are paused or have a pause request) or `empty` (nothing queued is a task to take) |
| `waiting` | array | every dependency not finished that holds a candidate back, each `{"ref", "on", "state", "reason"}`; `ref` is the one that waits as the queue stores it (a task, or the epic its tasks inherit the dependency from), `on` what it waits for, `reason` the reason given, `[]` for none |
| `waiting[].state` | string | `open` (not done yet), `broken` (the target was abandoned, is archived or is gone, so the wait never ends: drop it with `jig queue undepend`) or `unknown` (nothing says; `jig housekeeping` may) |
| `not_queued` | integer | how many active, unpaused tasks have no item in the queue |

A candidate is a queued task whose state is `active`, not paused and with no pause request. Tasks
that are ready, closed, abandoned or gone, and epics, are never advised and never listed.
`waiting` holds the dependencies of candidates only. The failures are the producer's alone and add
no code: `usage` for an argument after `next`, `not-initialised` without Jig, `failed` for a queue
file of another format version. Without a queue the answer is `"next":null,"reason":"empty"`.

## `jig task new --json`

`jig task new <id> … --json` files a task and answers with it. `--goal <text>` gives the task's
goal on the command line, so a program files a task without writing a file for `--from` first: the
text, trimmed, becomes the paragraph under `## Goal` in the template's `task.md`, the one the task's `goal`
reads back. `--json` may stand anywhere among the arguments; without it the command prints
the workspace's path, as it always has.

```json
{"task": <task>}
```

`task` is the filed task as `jig task list --json` lists it — the same object, every field and its
`actions`. A task just filed has no branch, so `branch`, `worktree`, `autopilot` and `pull_request`
are `null` and `housekeeping_flags` is `[]`. Filed without `--goal`, the brief is the template's, whose
placeholder under `## Goal` is an HTML comment, so `goal` is `null`. The envelope's `revision` is
taken before the task is written; the write raises it, so read again for the new one.

Refusals: `already-exists` when a task — or a directory under `.ai/workspace/tasks/` — already holds
the id, including the second of two `task new` racing for one; `usage` for an id outside the grammar
(ASCII letters, digits, `.`, `_` and `-`, not starting with `.` or `-`; `jig_valid_id`,
`scripts/lib/common.sh`), an argument the command does not take, an option without its value, a class or
domains it does not accept, and a `--goal` that is empty, holds a line break, starts with `#`, or
stands beside `--from`; `not-initialised` and `not-a-repository` as everywhere. Any other refusal —
a worktree that keeps a task directory of its own, a `--from` file that cannot be read — reads
`failed`. Nothing is written on a refusal.

## `jig task resume --json`

`jig task resume <id> [--revision <n>] --json` ends a task's pause and answers with the task and
what the resume found. The write is checked against a revision as a `jig queue` write is: with
`--revision <n>`, the `revision` of the read the caller decided on; without it, the revision the
command reads as it starts. When anything was written in the clone since, the resume is refused with
`stale-revision` and changes nothing. A landed resume raises the revision by two (the claim and the
write). `--json` may stand anywhere among the arguments; without it the command prints its report,
as it always has.

Without a stash the resume writes only the task's state, so it runs in any checkout: a task in its
own worktree is resumed from the clone's main checkout. When the pause recorded a stash
(`jig task pause --stash`), the stash is applied in this checkout, which must then be on the task's
branch.

```json
{"task": <task>, "resume": {"paused_days": 3, "stash": {"sha": "9f2c…", "applied": true}, "uncommitted": 2, "overlap": ["scripts/lib/task.sh"]}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it — the same object, every field and its `actions` — read after the write: `paused` is `false` |
| `resume.paused_days` | integer | whole days since the task was paused; `0` when the pause has no date |
| `resume.stash` | object or null | the stash the pause recorded, `{"sha", "applied"}`; `applied` is always `true` in an answer, since a stash that does not apply is a refusal. `null` when the pause recorded none |
| `resume.uncommitted` | integer or null | files that differ from HEAD in the checkout the task's branch is checked out in — this one, or its worktree; `null` when the branch is checked out nowhere, or for a task never started, this checkout's count |
| `resume.overlap` | array of strings or null | files the task changed that also changed on its base since they parted, sorted; `[]` when none; `null` when no base or merge base was found. Read in the task's checkout, its uncommitted changes counted; from the branch's commits alone when it is checked out nowhere |

Refusals: `usage` for an argument the command does not take, a `--revision` without a value or that
is not a revision (digits without a leading zero), and an id outside the grammar; `not-found` for no
such task; `not-paused`, `wrong-checkout`, `stash-conflict` and `stale-revision` as in the table
above; `not-initialised` and `not-a-repository` as everywhere. Every refusal but `stash-conflict`
happens before anything is written. `stash-conflict` for unresolved conflicts already in the checkout
happens before anything is written too; for an apply that fails it happens after the revision was
claimed (it is raised by one). An apply that refused leaves the state as it was; one that merged the
stash with conflicts, or wrote part of it, records `paused_stash_applied` (schemas/state.md), so the resume after the
person resolved them ends the pause without applying the stash again.

## `jig upgrade --json`

`jig upgrade … --json` runs the upgrade as it always does and answers with what it did. `--json` may
stand anywhere among the arguments and goes with `--dry-run` and `--from`; the text the command
prints for a person goes to stderr, unchanged. When the run is handed to a newer jig (the project's
source holds a newer version than the jig that was called), that jig's data is this envelope's.

```json
{"mode": "copy", "dry_run": false, "from": "0.32.0", "to": "0.33.0", "outcome": "upgraded",
 "files": {"placed": 12, "kept": 100, "removed": 0, "conflicts": 0},
 "git": {"level": "pr", "branch": "jig/upgrade-0.33.0", "commit": "<sha>", "pushed": true,
         "pull_request": "<url>", "merged": false},
 "manual_steps": [], "would_stop": []}
```

| Field | Meaning |
|---|---|
| `mode` | `copy`, or `link` for a project installed with `jig init --link` |
| `dry_run` | `true` for `--dry-run`, which changes nothing |
| `from`, `to` | the project's Jig before the run (the manifest's `jig.version`) and the version it upgrades to; `null` when unknown |
| `outcome` | `planned` (a dry run), `linked` (link mode, every link in place), `nothing-to-do`, `incomplete` (the self-check failed, so nothing was committed; run again), `staged` (changed and left for the person to commit: `agent.git` is `none`, or the repository has no commit yet), `upgraded` (committed) |
| `files` | how many framework files the run placed, kept as they were, removed and left in conflict; `null` in link mode |
| `git` | how far git went, by `agent.git` (`level`): the upgrade's `branch` (`null` when the project works on one branch), the `commit` (`null` when staged), `pushed`, the `pull_request` URL or `null`, and `merged`. `null` when nothing was staged or committed |
| `manual_steps` | the steps this release asks for by hand, as the upgrade commit lists them; empty when there are none |
| `would_stop` | for a dry run, every reason a real run would refuse, as `upgrade-blocked` would name it; empty otherwise |

Refusals: `upgrade-blocked` before anything is touched; `usage` for an argument the command does
not take or `--from` without its value; `not-initialised` and `not-a-repository` as everywhere. Any
other refusal — a source that is not a Jig checkout, a project in link mode where links cannot be
made — reads `failed`. A failure after the commit (the push, the pull request or the merge) also
reads `failed` and carries no data: the commit and the branch are already there, and the push or
the pull request is left to the person — a second run stages nothing and ends `nothing-to-do`.

## `jig upgrade --land --json`

`jig upgrade --land` brings an upgrade that ended in a pull request here once the forge has merged
it: it asks the forge for the pull requests of `jig/upgrade-*` branches into `git.base_branch`,
fetches the base, checks the base branch out (from the base or from the upgrade's own branch),
fast-forwards it to `origin/<base>` and lets the upgrade's branch go the way a merge Jig made itself
does — here when git sees its work merged, and on origin, at the head the forge merged, only at
`agent.git` `push` or above. It never stashes and never forces. `--land` takes no other argument
but `--json`, and reads no framework source.

The upgrade it lands is the newest merged one with something left to do here: its version not yet
on the base branch here, or its branch still here. Standing on an upgrade branch, only that
branch's pull request counts.

```json
{"mode": "copy", "dry_run": false, "from": "0.38.1", "to": "0.39.0", "outcome": "landed",
 "files": null,
 "git": {"level": "pr", "branch": "jig/upgrade-0.39.0", "commit": "<sha>", "pushed": true,
         "pull_request": "<url>", "merged": true},
 "land": {"base": "main", "branch_deleted": true, "origin_branch_deleted": true},
 "manual_steps": [], "would_stop": []}
```

| Field | Meaning |
|---|---|
| `mode`, `dry_run`, `files`, `manual_steps`, `would_stop` | as in `jig upgrade --json`; `dry_run` is `false`, `files` `null`, the two lists empty |
| `from`, `to` | the Jig the base branch here recorded before (`jig.version` in its manifest) and after the fast-forward; on `nothing-to-do` both are the base's |
| `outcome` | `landed`, or `nothing-to-do` when no merged upgrade waits to be brought here (and none is open) |
| `git` | on `landed`: `level` (`agent.git`), the upgrade's `branch`, the `commit` the base is on now, `pushed` and `merged` (both `true`), and the `pull_request` URL or `null`. `null` on `nothing-to-do` |
| `land` | on `landed`: the `base` checked out, and whether the upgrade's branch was deleted here (`branch_deleted`) and on origin (`origin_branch_deleted`). A branch kept says why in the text on stderr. `null` on `nothing-to-do` |

Refusals: `not-merged` when the pull request is still open; `upgrade-blocked` with every reason at
once; `usage` for any other argument. Both change nothing. No origin, no signed-in forge CLI, or a
forge that did not answer read `failed` and change nothing either.
