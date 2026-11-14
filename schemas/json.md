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
touches the network: no forge CLI, no fetch — with two exceptions, `jig pr reviewers --json` and
`jig task pr-status --json`, whose subject is the forge itself (below): each is called when a person
asks, never on a timer.

Strings escape `"`, `\` and every control byte (`\n`, `\t`, `\r`, the rest as `\u00XX`); other
bytes pass through as they are, so a value is UTF-8 when what Jig read was. A value Jig has no
fact for is `null`, never an empty string or a missing key.

## Failure codes

`error.code` says why a read was refused, in a word a program can act on; `error.message` says it to
a person and may be reworded. The codes are part of the contract: one is never renamed or given
another meaning without raising `schema`. A new code may be added without raising it — a refusal
that has none yet reads `failed` until it gains one — so a program treats a code it does not know as
`failed`. For the same reason one case of a broad code may move to a new code of its own when callers
need to tell it apart (`already-filed`, out of `already-exists`); the release notes say so. The exit status keeps its meaning whatever the code: non-zero for every refusal.

| `code` | The read was refused because |
|---|---|
| `usage` | the command was given an argument it does not take, an option without its value, or a value outside the ones it accepts (`--status bogus`); `--json` beside an option it cannot be combined with too |
| `not-a-repository` | it ran outside a git repository |
| `not-initialised` | the repository has no Jig: no `.ai/config.yaml`; `jig init` installs it |
| `stale-revision` | a write was sent with a revision that is no longer the clone's: Jig wrote something after the caller read it (`jig queue … --revision <n>`, `jig task resume … --revision <n>`, `jig task pause … --revision <n>`, `jig task set … status consolidated --revision <n>`, `jig task gate … --revision <n>`, `jig task abandon … --revision <n>`, `jig task archive … --revision <n>`, `jig task unarchive … --revision <n>`, `jig spec item … --revision <n>`, `jig spec drop … --revision <n>`, `jig knowledge accept … --revision <n>`). Read again and decide again; nothing was written |
| `not-found` | a reference names no task or epic of this clone, an item, dependency or request that is not in the queue where the command needs it, a task document the task does not have (`jig task artifact read`), a knowledge document that does not exist (`jig knowledge read`) or links no source (`jig knowledge sources --diff`), or a spec, phase or item a roadmap write names that the roadmap on the write branch does not have, or a task it would file. Also `jig writes ship` with nothing waiting, and the task a `jig task gate`, `abandon`, `archive`, `unarchive` or `jig spec drop` names; for `jig spec drop` also a task linked to no spec, a spec with no roadmap on the write branch, and a roadmap with no item that names the task |
| `not-paused` | `jig task resume` was asked for a task that is neither paused nor parked at the staging branch: somebody resumed it first. Nothing was written |
| `already-paused` | `jig task pause` was asked for a task that is paused already: somebody paused it first. Nothing was written |
| `wrong-checkout` | `jig task resume` has a stash to apply, or `jig task pause --stash` has one to make, and this checkout is not on the task's branch; `message` names the worktree that has it checked out, or says to switch to it. Nothing was written |
| `stash-conflict` | `jig task resume` could not apply the task's stash: `git stash apply` refused and applied nothing, it merged the stash with conflicts or stopped part way, or a stash it merged earlier still has unresolved conflicts, or the checkout has unresolved conflicts of its own. The task stays paused and the stash entry is kept |
| `not-closable` | `jig task set <id> status consolidated` was asked for a task Jig does not offer to close: its knowledge decision is not recorded, or its pull request is not merged (the forge says so, or cannot be asked). `message` is the reason word for word, the one the task's `close` action carries. Nothing was written |
| `already-exists` | a write would create what the clone already has: `jig task new` with an id another task holds, `jig queue request` for a request already pending, `jig spec item add` with the text of an item the roadmap has, `jig spec item file` with a `--new` id another task holds. Another id is the remedy. Nothing was written |
| `already-filed` | `jig spec item file` was asked to file an item that already names a task, filed earlier here or in another clone; `message` names that task. Another id does not help: read the roadmap again. Checked before the task id, so an item that names a task is `already-filed` even when the id is taken too. Nothing was written |
| `git-not-allowed` | a write in Jig's own tree was asked for at `agent.git: none`, where Jig commits nothing. `message` names the setting. Nothing was written |
| `write-busy` | another write in Jig's own tree is running in this clone. Nothing was written; try again in a moment |
| `branch-checked-out` | the write's branch is checked out somewhere, and Jig never moves a checkout; `message` names the path. Nothing was written |
| `branch-diverged` | the write's branch and origin's have diverged. Nothing was written, and nothing is forced |
| `branch-has-other-commits` | the write's branch has commits here that no write of Jig's made and origin does not have: a person's, which a write does not publish. `message` names the branch. Nothing was written |
| `base-not-on-origin` | the write's base is not on origin, at `agent.git: push` or above: a branch cut from it would carry out whatever is on it, and no pull request could open into it. `message` names the base to push. Nothing was written |
| `write-still-waits` | an earlier write of the same target still waits where this one cannot follow: for another base than this edit's (an epic opened or finished since), or as edits that never reached origin above a write whose pull request was closed unmerged or whose branch origin deleted. `message` names the branch, and what to do. Nothing was written |
| `tree-in-the-way` | an unfinished write left something at Jig's tree that git will not remove. `message` names the path for a person to delete; a retry does not clear it. Nothing was written |
| `commit-refused` | git refused the commit in Jig's own tree, usually a project's hook; `message` holds what it said. This edit was not committed; an earlier one that already waits on the branch still waits |
| `epic-missing` | a roadmap write found its spec on an open epic that is neither here nor on origin. Nothing was written |
| `not-linkable` | `jig spec item file` cannot link this task or file this item: the task is finished, started or linked to another spec, or the item is checked. Nothing was written |
| `not-proposed` | `jig knowledge accept` or `reject` named a document that is not a proposal — for `reject`, nor an accepted stub whose source is `changed`, `unrecorded` or `missing`: decided already, on the branch if that decision still waits. Nothing was written |
| `not-on-base` | `jig knowledge accept`, `reject` or `reviewed` with `--json` or `--revision` named a document this checkout has and the base the decision is judged on does not — for `reject` of a stub, also a change to its source the base does not carry: not committed, or not on origin's base. Nothing was written |
| `not-on-branch` | the same, for what the base has and `knowledge/decisions`, cut before it got there and still waiting, does not. Nothing was written; decide it once that branch has landed |
| `source-missing` | `jig knowledge accept` or `reviewed` named a stub whose source is missing, invalid or not tracked. Nothing was written |
| `upgrade-blocked` | `jig upgrade` would not start here and changed nothing: uncommitted changes, a started task's branch checked out, `jig verify` running in this checkout, or line endings Jig's files are not pinned against. For `jig upgrade --land`: uncommitted changes, a checkout on another branch than the base or the upgrade's, the base checked out in another worktree, or a base that cannot be fast-forwarded to origin's. `message` lists every reason, one per line, each with what to do |
| `unreleased-source` | `jig init` or `jig upgrade` in copy mode (dry run too) found the framework source checkout not at the release tag of its version, or at it with uncommitted changes, and `--unreleased` was not given. `message` names where the checkout stands and the two ways out. Nothing was changed |
| `unknown-key` | `jig config set --json` was given a name no reader of Jig reads. Nothing was written |
| `not-local` | `jig config set --json` was given a key Jig reads but only the team's `.ai/config.yaml` answers for. Nothing was written |
| `invalid-value` | `jig config set --json` was given a value its key does not accept: outside the fixed set, not a number, not a duration. Nothing was written |
| `secret-key` | `jig config set --json` was asked to put a secret (`notify.telegram.token`) on a command line, which Jig never does. Nothing was written |
| `not-merged` | `jig upgrade --land` found the upgrade's pull request still open on the forge; or `jig upgrade` found the upgrade to this version already on an unmerged `jig/upgrade-<version>` branch whose pull request the forge reports open — the upgrade is done and waits for its merge, and `message` names the pull request's URL. Nothing was changed; merge it and run `jig upgrade --land` |
| `not-on-staging` | `jig task promote` found none of the task's own commits in the tested staging commit. Nothing was pushed and no pull request opened |
| `behind-staging` | `jig task promote` found own commits of the task the tested staging commit does not have, pushed or not: a fix made after the test. Nothing was pushed and no pull request opened |
| `carries-staging` | `jig task promote` found the staging branch merged into the task's branch: its pull request would take untested work of others into the base. Nothing was pushed and no pull request opened |
| `base-conflict` | `jig task promote` found the task's branch in conflict with the base branch; without `--json` the command exits 3, with it this refusal carries the paths in `message`. Whoever merges the base into the task branch resolves it. Nothing was pushed |
| `shallow-clone` | `jig task promote` ran in a shallow clone, where what a commit contains cannot be told. Nothing was pushed |
| `forge-unavailable` | the command could not ask the forge: no forge for this clone, its CLI missing or not signed in, or the call failed (`jig pr reviewers`, `jig task land --by human`, `jig task promote --json`, `jig task request-review`, `jig task merge-pr`, `jig task pr-status`). `message` holds why |
| `ci-red` | a person's merge (`jig task land --by human`, `jig task merge-pr`) found a check of the pull request failed. Looked at once, never waited for. Nothing was merged |
| `ci-pending` | the same, with a check still running (CI is looked at once, never waited for). Nothing was merged |
| `ci-none` | the same, with no check run on the pull request. Nothing was merged |
| `not-approved` | `jig task merge-pr`: the pull request has changes requested or still waits for a reviewer (`message` says whom). `jig task land --by human`: the pull request is not approved (`message` says changes requested, whom it waits for, or no review) and `git.staging_review` does not let it land without one, or `--without-review` was not given. Nothing was merged |
| `review-required` | `jig task land --by human --without-review` under `git.staging_review: require`: only an approval lands it. Nothing was merged |
| `conflict` | `jig task land --by human`: the pull request conflicts with the staging branch. A person's landing never merges directly; the agent lands it (`jig task land <id>`). No temporary tree was made. `jig task merge-pr`: the pull request conflicts with its base. Nothing was merged |
| `draft` | the pull request is a draft, which is never landed |
| `mergeable-unknown` | the forge could not say whether the pull request merges cleanly; ask again |
| `forge-refused` | the forge refused the merge, or the repository allows no merge method the landing needs, or the pull request's head is not the commit that was shipped: branch protection, a required review, rights. `message` holds the forge's first line. Nothing was forced |
| `no-pull-request` | the task has no pull request to act on |
| `pull-request-closed` | the task's pull request is closed unmerged (`jig task request-review`: or merged, where nobody is asked to review any more) |
| `wrong-flow` | the command does not apply to the task in this project: not on a sound `staging` flow, cut from a base other than `git.base_branch`, or `git.staging_land: external`; `jig task land` on a pull request that goes into another branch than the staging branch (`pr_into`, or the forge's base when `pr_into` is not recorded; into the base branch `message` names `jig task merge-pr <id> --by human`); `jig task merge-pr` on a pull request that goes into the staging branch (the local guard for a task whose `pr_into` is empty or the staging branch, the forge's base after it; `message` names `jig task land <id> --by human`) |
| `not-ready` | `jig task land --by human`: the ship's gates do not pass (the knowledge decision, a blocking finding, the review receipt, the route's records); `message` is their text |
| `not-shipped` | the task's branch is not on origin as shipped: it has commits origin does not, or origin has no such branch |
| `notes-stale` | a release's notes no longer reach the base's tip, found right before the merge (`jig task merge-pr` on a pull request that raises the version) |
| `reviewer-unknown` | `jig task request-review`: a `--reviewer` names nobody the repository may ask, several people (`message` lists them), or a team. Only people are asked. Nobody was asked |
| `autopilot-running` | the task's autopilot run is `on`: the agent is on it. For `jig task gate`, a human approval of a task whose unattended run is `on`: the approval there is the agent's. Nothing was written |
| `autopilot-stopped` | `jig task gate` without `--by agent` for a task whose unattended run is `stopped`, at its repair limit or before it: nobody answers there, and `message` names the way on (an answer to the stop, or a handover). Nothing was written |
| `no-gate` | `jig task gate` was asked for a task that has no human gate: its class is not T3 or T4, or it has no `design.md` to approve. Nothing was written |
| `already-archived` | `jig task archive` was asked for a task that is archived already: somebody archived it first. Nothing was written |
| `not-archived` | `jig task unarchive` was asked for a task that is not archived: somebody unarchived it first. Nothing was written |
| `wrong-status` | the task's status does not let the command run: `jig task archive` of a `consolidated` task (its work is in git and its workspace is purged, not kept), `jig task abandon` of an `archived` one (`jig task unarchive` first), `jig spec drop` of a task that is neither `abandoned` nor archived from `abandoned`. Nothing was written |
| `already-closed` | `jig spec drop` found every item that names the task checked already: somebody closed it first. Nothing was written |
| `ship-running` | a `jig task ship` of the task is waiting for CI and lands the pull request itself (`shipping` in `jig task list --json`). Nothing was written |
| `git-level` | a command without `--by human` at an `agent.git` (`agent.git_staging` for a task whose pull request goes into the staging branch) below what it needs: `jig task promote --json` and `jig task request-review` below `pr`, `jig task merge-pr` below `merge`. The action is the person's |
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
checkout record, the status page, the verify run), an idea draft (`jig spec draft write|rename|drop`,
and the draft `jig spec ship` moves to trash — no read reports one; the status page is redrawn), and — the accepted risk — **a file changed by
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
| `staging` | string or null | only in a project on the staging flow (`git.flow: staging` with a `git.staging_branch` `jig doctor` accepts); absent on any other flow. `on`: some commit of the task's own (reached by its branch, not by its base) is in `origin/<git.staging_branch>`, and every own commit outside it is a merge that brings the base in; `behind`: another own commit is not in it yet — a fix after the task landed there, pushed or not. `null`: none of its own work is there, or it has no branch. Derived from git by the branch's name on every read (`jig_staging_states`, common.sh), never stored, never from the forge: a squash merge into staging reads `null` |
| `parked` | object or null | only in a project on the staging flow, beside `staging`; absent on any other flow. `{"reason", "hint", "review"}` when the task waits at the staging branch: `reason` `review` (a pull request from its branch into the staging branch is open — the forge cache's newest, or the one `jig task ship` just opened, until the cache has it) or `signal` (its own work is on the staging branch, `staging: on`, and it waits for "prepare for prod"); `hint` `landing` when the reason is `review`, `git.staging_land` is `pr`, this clone's `agent.git` (`agent.git_staging` when set) is below `merge` — the person lands it — and the review is over: the pull request is approved as the forge cache holds it (`review.state` `approved`), or `git.staging_review` is `none` — else `null`; a review nobody has read yet (`review` `null`) is not an approval. `review` is the review object `{"state", "waiting_for"}` for a task parked for `review`, `null` for `signal` and when the cache cannot say (below): `state` `approved`, `changes` (somebody asked for changes), `waiting` (a requested reviewer has not answered) or `none` (nobody approved), `waiting_for` the logins still requested (an empty array when nobody). The same shape `jig task pr-status --json` prints as `review`. The pull request is the task's own: the one its `pr_url` names while the cache has it going into the staging branch, else the cache's newest from its branch into the staging branch. `null` when it is not parked: it is not `ready`, a person took it back for a fix (`park_resumed_at`, until its next `jig task ship`, at any `agent.git` level), its base is not `git.base_branch`, it has a pull request into its base that is open or merged (or `promote_url`), or neither holds. Derived on every read from git and the forge cache (`jig_parked_states`, common.sh), never stored (adr-20261112-a-task-waiting-at-staging-is-parked-and-resuming-it-is-its-status) |
| `worktree` | object or null | `{"path", "uncommitted"}`: the worktree, other than the checkout the command ran in, that has the task's branch checked out, and how many files there differ from its HEAD |
| `gate` | object or null | a T3/T4 design's gate: `{"state", "by"}`, `state` `waiting`, `changed` (the design moved after approval) or `approved`; `by` `human` or `agent`, `null` while waiting. `null` for any other class, or before `design.md` exists |
| `autopilot` | object or null | the task's autopilot run: `state` (`on`, `stopped`, `done`), `mode` (`attended`, `unattended`), `repairs` (integer), `stage` and `stage_at` (the last stage the current run entered), `stop_reason` and `stop_at` (the journal's last stop), `phase` (`<spec-id>/<n>` for a task of a phase run), `handover_at` (when a person took the stopped run over, `jig task autopilot <id> handover`); each `null` when there is none. `null` when the task never ran on autopilot |
| `pull_request` | object or null | the task's own pull request: `{"url", "state", "ci", "fetched_at", "base", "mergeable", "review"}`. It is the one `jig task ship` opened (`pr_url`), found in the forge cache by its address; when the cache does not have that address, or no `pr_url` is recorded (the pull request was opened by hand), the cache's newest from the task's branch into where its pull request goes: the staging branch on the staging flow for a task cut from `git.base_branch`, otherwise the task's base. `null` when `pr_url` is empty and the cache has none. `url` is `pr_url`, else the cache's address (`null` when it has none). `state` (`open`, `merged`, `closed`) and `ci` (`green`, `red`, `pending`, `none` — no check ran) are what the last `jig housekeeping` heard from the forge, at `fetched_at` (UTC), read from the forge cache below; each `null` when the cache does not say — no cache, no entry, or, for `ci`, a pull request that is not open or a forge whose list carries no checks (GitLab). `base` is the branch the pull request goes into (the cache's line, else where it should go), `mergeable` `mergeable` or `conflicting` for an open one (`null` otherwise), and `review` the review object `{"state", "waiting_for"}` as in `parked`, `null` when the cache holds none: the pull request is not open, an older cache line, a line `jig task ship` recorded before housekeeping ran, a forge that was not asked (GitLab asks only for merge requests into the staging branch, on the staging flow) or one that could not say |
| `promotion` | object or null | only in a project on the staging flow, right after `pull_request`; absent on any other flow. The pull request that carries the task's work from the staging branch into the base branch: `{"url", "state", "ci", "mergeable", "fetched_at"}`, read from the cache's newest line from the task's branch into its base, `url` from it or else from the address `jig task promote` recorded (`promote_url`); each `null` when the cache does not say. `null` when the cache has no such line and no `promote_url` is recorded, and for a task whose base is not `git.base_branch`: an epic's task is never promoted |
| `shipping` | object or null | `{"since"}` while a `jig task ship` of this task waits for CI and merges the pull request itself (`agent.git: merge`): `since` is when it began waiting (UTC). `null` when none does: no ship, or its process is gone. Read from `<clone root>/.ai/runtime/shipping/<id>`, which the ship writes and removes; a read deletes nothing |
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
| `start` | `jig task start <id>`, or `jig task start <id> --out-of-order --reason <text>` when `jig queue next` advises another queued task the one to start outranks this one (the command would refuse the plain form: the reason says which task first in the queue and what to do) | the task has not been started |
| `pause` | `jig task pause <id>` | it is not paused |
| `resume` | `jig task resume <id>` | it is paused, or parked at the staging branch (`parked` is not `null`) |
| `request-pause` | `jig queue request task:<id> pause` | it is not paused, no pause of it is requested, and it has been started: a task nobody started enters no stage, so no stage would take the request, and the reason sends the person to `pause` (the command still takes it) |
| `cancel-pause-request` | `jig queue cancel task:<id> pause` | a pause of it is requested |
| `approve-gate` | `jig task gate <id> approved` | a T3/T4 design waits at its gate (`waiting` or `changed`), and the gate is a person's: not in a clone or a run where nobody answers (`autopilot.unattended`) |
| `answer-stop` | `jig task autopilot <id> resume --answer <text>`, with ` --by human` for an unattended run | its autopilot run is `stopped`, and an unattended one has repairs left |
| `handover` | `jig task autopilot <id> handover --by human --answer <text>` | its autopilot run is `stopped`, in either mode, at the repair limit or before it (adr-20261108-a-person-takes-over-a-stopped-run) |
| `set-class` | `jig task set <id> class <Tn>` | the task is live |
| `ship` | `jig task ship <id> --message-file <file>` | the git level (`agent.git`, `agent.git_staging` for a task whose pull request goes into the staging branch, or `autopilot.git` for a run) is not `none`, the knowledge decision is recorded, no P0/P1 finding blocks, the review receipt is current, the route has its records, the task is started on a branch other than its base, and its pull request is not merged |
| `land` | `jig task land <id> --by human` | the project is on a sound `staging` flow with `git.staging_land: pr`, the task is cut from the base branch, it opened a pull request that does not go into another branch than the staging branch (`pr_into`) and the forge cache does not call merged or closed, the ship's gates pass (the knowledge decision, no blocking finding, a current receipt, the route's records), its autopilot run is not `on` and no `jig task ship` of it is waiting for CI. The git level is not read: the button is a person's decision. Whether the pull request is approved, conflicts, or the branch carries the staging branch is the command's, asked when it runs |
| `request-review` | `jig task request-review <id> --reviewer <login> --by human` | the task is live, it opened a pull request the forge cache does not call merged or closed, and its autopilot run is not `on`. The login is a placeholder the person fills in (`jig pr reviewers --json` lists whom to offer). The git level is not read |
| `merge` | `jig task merge-pr <id> --by human` | the task is live, on a staging flow, a task cut from the base branch qualifies when its pull request went into the base (`pr_into` is another branch than the staging branch: a task that changes the flow itself), or when no ship recorded where it went (an older Jig's: the command asks the forge and refuses one into the staging branch); otherwise its pull request goes into its own base (not the staging branch: that one is `land`), the forge cache does not call it merged or closed, its autopilot run is not `on` and no `jig task ship` of it is waiting for CI. Withheld too while the forge cache says its checks are red or pending, or that it conflicts: the table may withhold more than the command refuses, which looks at the forge itself, now. The git level is not read |
| `promote` | `jig task promote <id> --by human` | the project is on a sound `staging` flow, the task is cut from the base branch, it waits at the staging branch for the test (`parked.reason` is `signal`) and its autopilot run is not `on`. The git level is not read |
| `pr-status` | `jig task pr-status <id> --json` | the task opened a pull request. It asks the forge when run |
| `close` | `jig task set <id> status consolidated` | the knowledge decision is recorded, and the task opened no pull request or the forge cache says it merged |
| `abandon` | `jig task abandon <id>`, with ` --reason <text>` for a task whose `task.md` has a `Spec:` line | the task is live |
| `archive` | `jig task archive <id>` | the task is `active`, `ready` or `abandoned` |
| `unarchive` | `jig task unarchive <id>` | the task is `archived` |
| `reopen` | `jig task set <id> status active` | the task is `abandoned` |
| `drop-item` | `jig spec drop <id> --json` | the command's own guard finds nothing to refuse in this clone's local refs: the task is `abandoned`, or archived from `abandoned`; it is linked to one spec; `agent.git` is above `none`; an item that names it is unchecked in the roadmap on the base the write goes into (the default branch, or the open epic the roadmap declares) and on the spec's own branch `spec/<sid>` whenever this clone has it; and that branch holds no commits no write of Jig's made, is not checked out in a worktree, and holds no earlier write that still waits to go into another base (`write-still-waits`, judged from the write's record). `reason` is the command's own refusal, word for word. Read from local refs, never fetched, so a roadmap this clone has not got yet withholds the row. The command closes the item in Jig's own tree |

A `consolidated` task offers nothing, an `abandoned` one only `reopen`, `archive` and `drop-item`, an `archived` one only `unarchive` and, when it was archived from `abandoned`, `drop-item` — except, for both,
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
--state all` (or `glab mr list --all`, 100 at most) for states, and on GitHub a second `gh pr list
--state open` for the checks, the mergeable word and the review of the open pull requests — two
calls a run, whatever the number of tasks. GitLab's list carries no approvals: on the staging flow
housekeeping asks for each open merge request into the staging branch, and for no other, one
approvals call each. `jig upgrade` that leaves its pull request open adds that one line itself, `open`, with
`<ci>` and `<mergeable>` `-`, in place of an older line for the same branch and base; the next
housekeeping run replaces the whole file. One line per pull request, newest
first as the forge lists them, written atomically, `#` lines are comments:

```
<head>	<base>	<state>	<ci>	<fetched_at>	<head_commit>	<url>	<mergeable>	<review>	<waiting_for>
```

`<ci>` is `-` when it was not asked; `<head_commit>` and `<url>`, the pull request's head and its
address, are `-` when the forge did not say. `<mergeable>` is `conflicting` or `mergeable` for an
open pull request the forge has judged against its base (GitHub's `mergeable`, asked in the same
second call; GitLab's `detailed_merge_status`, in its one list), `-` otherwise. `<review>` is
`approved`, `changes`, `waiting` or `none` for an open pull request whose review was asked (the
words of `jig task pr-status`; GitHub's decision and reviews are read once, in the open list's call),
`-` otherwise and when the forge could not say; `<waiting_for>` is who is still requested as a
reviewer, logins comma-separated, `-` for nobody or not known. An open pull request the second
call lists but the first (the newest 200) does not gets its own line, after the others. A line written
before a column existed ends before it and reads as if each missing one were `-`. A task's entry is the first line for its branch and base, the
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
| `waiting` | object or null | an edit of this roadmap committed in Jig's own tree that has not landed: a [write](#jig-writes---json) with `progress` and `phases` beside it, the roadmap as it is on that branch. `null` when none waits |
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
| `id` | string | the item's handle: `i-` and 12 hex digits, a digest of its text without a leading task id or `fog:` and with whitespace collapsed; `-2`, `-3` for a repeat of the same text, in roadmap order. It holds through a move, a check and a filing. Rewording the item changes it, and a write naming the old one is refused. Compare it, do not parse it |
| `text` | string | the line after its checkbox, indented continuation lines joined with a space; tabs become spaces and trailing whitespace is dropped |
| `checked` | boolean | `[x]` or `[X]` |
| `done` | boolean | what the item counted as: `checked`, or its `task` is known in this checkout to have merged — `consolidated`, or logged `remote=merged` by the newest housekeeping run (schemas/spec.md) |
| `task` | string or null | the backticked task id the text starts with, followed by a dash — the pattern `filed` counts; `null` otherwise. Read from checked items too |
| `fog` | boolean | the text starts with `fog:` |

`done` counts the items whose `done` is `true`, `filed` the other unchecked ones with a `task`,
`fog` the unchecked ones with `fog`. The roadmap is read where `jig status` reads it: an open epic's from its ref with no
fetch, every other one from this checkout.

## `jig spec item` writes

`jig spec item add|move|file <spec> … --json` change a roadmap on a branch of its own, in Jig's own
tree (adr-20261104-a-write-goes-in-jigs-own-tree): nobody's checkout moves. `--revision <n>` as the
queue writes take it, and the same `stale-revision`. Without it the write checks against the revision
it reads once its tree stands, before it reads the roadmap there, so a Jig write landing while it
fetches is not a reason to refuse it. An item is named by its `id`, resolved in the
roadmap on the write branch, so `waiting.phases` holds the handles of the edits still on their way.

```
jig spec item add  <spec> --phase <n> --text <t> [--after <item> | --top | --bottom]
jig spec item move <spec> <item> [--phase <n>] [--after <item> | --top | --bottom]
jig spec item file <spec> <item> --task <task-id>
jig spec item file <spec> <item> --new <task-id> [--goal <text>]
```

`add` goes to the bottom of its phase unless told otherwise. `move` needs `--phase` or a place.
`file` names a task filed earlier (`jig task new`): the item gets `` `<task-id>` — `` in front, `fog:`
gone, and the task its `Spec:` line, so `jig spec link` afterwards answers "already linked".
`--new <task-id>` files the task too, as `jig task new <task-id> [--goal <text>]` does, in the same
write: the task id, the item, the level, the branch and the revision are all checked before anything is
written, and a refusal files nothing, so a program carries the revision of the read the person saw
(`jig task new` raises the revision; filed first, it would make the write `stale-revision`). The task is filed
once the commit stands, as the `Spec:` line is: a failure then is a `note`, with the commands to run, not a
refusal. `--task` and `--new` are exclusive, and `--goal` goes with `--new`.

```json
{"spec": "idea-x", "item": {"id": "i-7d2bc8dc7707", "text": "Export a page", "checked": false, "task": null, "fog": false, "phase": 2}, "write": <write>}
```

| Field | Type | Value |
|---|---|---|
| `spec` | string | the spec |
| `item` | object | the item as the roadmap on the branch now has it: `id`, `text`, `checked`, `task`, `fog` as in `jig spec list --json`, and `phase`, `null` for a section that is not a phase |
| `write` | object | where the edit went, [below](#jig-writes---json) |

Refusals: `usage`; `not-found` for a spec neither on its branch nor on the base, an item or phase the
roadmap on the branch does not have, or a task that does not exist; `already-exists` for an item with
this text, or a `--new` task id another task holds; `already-filed` for an item that names a task
already, whichever id was given; `not-linkable` for a task `file` cannot link: finished,
started, linked to another spec, or an item already checked, or a checkout that does not keep the clone's task workspaces for `--new`; `epic-missing` for an open epic neither
here nor on origin; and the refusals of every write, below.

## `jig knowledge decide|accept|reject|reviewed` writes

With `--json` or `--revision <n>`, a decision is committed on `knowledge/decisions`, in Jig's own tree
(adr-20261104-a-write-goes-in-jigs-own-tree). Without either, the text form changes the working tree,
as it always did. With `--json` alone the write checks against the revision it reads once its tree
stands, before it reads the knowledge there, as the spec item writes do. `reviewed` also takes `--date`. Several ids are one decision: a refusal refuses them
all.

`jig knowledge decide [--accept <id>]... [--reject <id>]... [--reviewed <id>]... [--date <d>] [--revision <n>] [--json]`
decides several documents several ways in one write — one fetch, one claim, one commit, one push — so a
page can send what a person decided at the revision they read. It is always a write in the tree; it has no
working-tree form. `decisions` lists them in the order of the flags. An id given twice, no decision at all,
or `--date` with no `--reviewed` is `usage`; any other refusal refuses the whole call, as above. A call of one
kind commits under that kind's subject (`Accept knowledge: …`); one of several kinds under
`Decide knowledge: <n> decisions`, a line per kind in the body.

```json
{"decisions": [{"id": "feature-alpha", "decision": "accepted", "path": ".ai/knowledge/features/alpha.md"}], "write": <write>}
```

`decision` is `accepted`, `rejected` or `reviewed`. `reject` takes a proposal, and also an accepted stub
whose source is `changed`, `unrecorded` or `missing` (as `jig knowledge sources` names it): that drops
its link, and the stub is `rejected` (adr-20261106-a-changed-link-is-dropped-by-reject). A document is
judged as it is on the branch, so one already decided and waiting is `not-proposed`. Refusals: `usage`;
`not-found` for an id no document has, here or on the branch; `not-on-base` and `not-on-branch` for a
document, or a change to a stub's source, this checkout has and the branch does not; `not-proposed` for
an `accept` of a document that is not a proposal, or a `reject` of one that is neither a proposal nor
such a stub; `source-missing` for a stub whose source is missing (`accept`, `reviewed`); and the
refusals of every write, below.

## `jig writes --json`

A write made in Jig's own tree, as the answer of each command above calls it `write`, and as
`jig writes [list] --json` lists what waits. `jig writes ship <target> --json` carries one as far as
`agent.git` now allows, and answers `{"write": <write>}`: a push that failed, a pull request after the
level was raised, and at `merge` the merge, once CI passed. A write itself never merges.

```json
{"target": "spec:idea-x", "branch": "spec/idea-x", "base": "main", "commit": "4354faecc647079ac9e77cc352e8d007374c250e", "commits": 1, "pushed": true, "pr": null, "merged": false, "committed": true, "level": "push", "note": "agent.git is push: the pull request is yours"}
```

| Field | Type | Value |
|---|---|---|
| `target` | string | what it is for: `spec:<id>` or `knowledge`, what `jig writes ship` takes |
| `branch` | string | the write branch: `spec/<id>` or `knowledge/decisions`; with `-2`, `-3` when the name is taken by a branch that landed by squash, whose pull request was closed, or that origin dropped |
| `base` | string | where its pull request goes: the default branch, or the spec's open epic |
| `commit` | string or null | the branch's tip; `null` when a write changed nothing on a branch that carries nothing |
| `commits` | integer | how many commits the base does not have |
| `pushed` | boolean | origin's ref, as of the last fetch or push, holds the tip |
| `pr` | string or null | the pull request's URL; `null` when there is none yet |
| `merged` | boolean | `true` only from `jig writes ship` that merged it, for this answer; nothing that merged waits |
| `committed` | boolean | answers only: this write made a commit. `false` when it changed nothing |
| `level` | string | answers only: the `agent.git` it went by |
| `note` | string or null | answers only: for a person, why it went no further: whose step is next, or what failed. A push or pull request that failed is said here and is not a refusal: the commit stands |

The list is `{"writes": [<write>, ...]}`, each without the three answer-only fields; a write leaves it
once its tip is an ancestor of its base as of the last fetch, the paths it touched read the same on the
base, or it was merged, or `jig writes ship` found it over. Like every read it asks no forge and fetches nothing, so a merge shows after
the next fetch. Refusals of every write: `git-not-allowed` at `agent.git: none`; `stale-revision`;
`write-busy`; `branch-checked-out`; `branch-diverged`; `branch-has-other-commits`; `base-not-on-origin`; `write-still-waits`; `tree-in-the-way`; `commit-refused`. `jig writes ship` adds `not-found`, also when the record's pull request was closed unmerged or merged with the tip, or origin deleted a branch it held: it sends nothing, the record says so, so that the list stops counting the write, and the next edit takes a new name. What origin holds is what it answers it has, never a tracking ref of a branch it deleted.

## `jig refresh --json`

`jig refresh` brings this clone up to origin, the one command a program runs to make what it
shows current (adr-20261112-refresh-brings-the-clone-up-to-origin): it fetches origin, as the
clone's own account and without a prompt, then fast-forwards the base branch (`git.base_branch`)
to `origin/<base>`. It never moves the person's checkout, never stashes, resets or forces, and never
touches their changes. A base that cannot move is an answer, not a failure: `outcome` says why and
the command exits 0. After a fetch that reached origin it also closes the writes in Jig's own tree
that are over, as `jig writes ship` would find them: their pull request merged (by squash too, with
the base changed again since), was closed unmerged, or origin dropped their branch. It raises the
revision when it closes a write, when the fetch moved an `origin/` ref, and when it moved the base; a
fetch that brought nothing new raises nothing, since only `fetched_at` moved.

```json
{"fetch": {"outcome": "done", "message": null, "fetched_at": "2026-11-12T15:24:39Z"},
 "base": {"name": "main", "outcome": "fast-forwarded", "from": "<sha>", "to": "<sha>", "checked_out_in": null, "message": null},
 "writes": [{"target": "knowledge", "branch": "knowledge/decisions", "reason": "merged"}]}
```

| Field | Type | Value |
|---|---|---|
| `fetch.outcome` | string | `done`; `failed` (origin did not answer, or git refused: the base step then works on what the last fetch left); `skipped` (the clone has no `origin`) |
| `fetch.message` | string or null | why it failed or was skipped, git's own last lines for a failure; `null` when `done` |
| `fetch.fetched_at` | string or null | as `origin.fetched_at` in [`jig status --json`](#jig-status---json), read after the fetch |
| `base.name` | string | `git.base_branch` |
| `base.outcome` | string | `fast-forwarded`; `up-to-date`; `blocked-by-changes` (the base is checked out here and git refused the fast-forward, since it would overwrite changes in the checkout — staged, unstaged, or an untracked file it would create; changes it does not touch do not stop it); `checked-out-elsewhere` (the base is checked out, rebased or bisected in another worktree, named in `checked_out_in` when known; run it there — or git could not list the worktrees); `diverged` (the base here has commits `origin/<base>` does not, or it moved while being fast-forwarded); `missing` (no `origin/<base>`, or no base branch here) |
| `base.from`, `base.to` | string or null | the base's commit before and after; equal unless `fast-forwarded`. `from` is what takes it back |
| `base.checked_out_in` | string or null | the worktree the base is checked out in, for `checked-out-elsewhere` |
| `base.message` | string or null | for a person, why the base did not move (for `blocked-by-changes`, git's message, which names the files); `null` otherwise |
| `writes` | array | the writes this run closed, each `{"target", "branch", "reason"}`: `target` as `jig writes` names it, `branch` the write's branch, `reason` `merged`, `landed` (the base holds its work), `closed` (its pull request closed unmerged) or `dropped` (origin deleted the branch it held). Empty when none was over, when the fetch did not reach origin, or when another write held the lock: one that still waits is `jig writes`'s to show |

Where the base is checked out here, it moves by `git merge --ff-only` (`merge.autoStash` off);
where it is checked out nowhere — the person is on another branch — by `git branch -f`, so their
checkout's branch and files stay as they are. Refusals: `usage` for any argument but `--json`;
`not-initialised` and `not-a-repository` as everywhere.

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
  "knowledge_counts_at": "2026-10-15T08:00:00Z",
  "origin": {"base": "main", "fetched_at": "2026-10-15T08:55:00Z", "behind": 0, "ahead": 0}
}
```

| Field | Value |
|---|---|
| `attention` | the items, most urgent first; `[]` when nothing needs the reader |
| `housekeeping` | the last `jig housekeeping` run the pull request and flag items come from: `ran_at` (UTC), `forge` (as in `jig task list --json`) and `stale` — `true` when the forge did not answer or the run is older than `housekeeping.cadence`, so a pull request waiting for the reader may be missing. `null` when housekeeping never ran in this checkout |
| `origin` | how this clone stands against origin, as of the last fetch, read offline: `base` (`git.base_branch`); `fetched_at`, when the clone last fetched (UTC) — the newest of every worktree's non-empty `FETCH_HEAD`, Jig's own trees included, so a fetch from any of them counts, of any branch: it says when the clone last reached out, not that `origin/<base>` came back with it; a fetch that failed empties its file and is passed over, which also loses the fetch before it there; `null` when none shows; `behind` and `ahead`, the commits `origin/<base>` has that the base here does not and the other way, `null` each when either branch is missing. `jig refresh` brings it up |
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
| `pull_request` | object | on the two `upgrade-pull-request-*` kinds: `{"branch", "base", "state", "fetched_at"}` — the upgrade's branch (`jig/upgrade-<to>` or `jig/upgrade-<to>-<n>`), the base it goes into (`git.base_branch`), `open` or `merged`, and when housekeeping heard it from the forge. On `promotion-conflicting` the same four: the task's branch, its base, `open`, and when the forge called it conflicting  On `pull-request-waiting` and `pull-request-was-open`: `{"branch", "base", "state", "fetched_at", "url", "ci", "mergeable", "review"}` from the forge cache, never the forge: the task's branch and base, `open`/`merged`/`closed`, when housekeeping heard it, the pull request's address, `ci` (`green`, `red`, `pending`, `none`), `mergeable` (`mergeable`, `conflicting`) and `review` (the review object `{"state", "waiting_for"}` as in `jig task list --json`); each `null` when the cache has no entry or does not say |
| `actions` | array of objects | on `pull-request-waiting` and `pull-request-was-open`: the task's own rows of the actions table, the same objects `jig task list --json` prints (`{"id", "command", "offered", "reason"}`) — `land` and `pr-status` for a task parked at the staging branch for review and landing, `merge` and `pr-status` otherwise. `offered` is the table's answer from the cache's state, `ci` and `mergeable`; `reason` says why a row is withheld |
| `versions` | object | on `upgrade-available`, `{"from", "to"}`; on the two `upgrade-pull-request-*` kinds, `{"to"}`, the version the branch is named for (`null` when the name holds none) |
| `staging` | object | on `staging-unpromoted`, `{"branch", "days"}` — the task's branch and the whole days since its work last landed on the staging branch; on `staging-unowned`, `{"commits", "list", "ack"}` — `commits`, how many of the reader's own commits the item is about (exact); `list`, those commits newest first, at most 20 of them (so it can be shorter than `commits`), each `{"sha", "subject", "date"}` — the full sha, the subject line, the author date in ISO 8601 with its offset; `ack`, the command that marks all of them as known, `jig staging ack --expect <commits>` (run it in the project as it is: it refuses, exit 1 and nothing written, when the count has moved since this read, so a commit the reader was not shown is never marked; read again then. `jig staging ack --dry-run` lists every one of them) |

The kinds, in the order they are listed:

| `kind` | `subject` | Needs a person because |
|---|---|---|
| `release-available` | project | a newer jig is out (`.ai/runtime/latest-release`, written by housekeeping) |
| `upgrade-pull-request-waiting` | project | an upgrade's pull request is open: the forge cache's newest line for a `jig/upgrade-*` branch into `git.base_branch` says `open`, and the base branch here does not already record its version (as it does right after `jig upgrade --land`, before housekeeping hears the merge). Merge it, then `jig upgrade --land`. One item per such branch |
| `upgrade-pull-request-merged` | project | an upgrade's pull request was merged, and the base branch here (`refs/heads/<git.base_branch>`) still records an older Jig than the version its branch is named for; `todo` is `jig upgrade --land`. A merged upgrade the base here already carries makes no item |
| `upgrade-available` | project | this project's installed Jig (the manifest's `jig.version`) is an older release than the one on this machine (a machine on unreleased code, `X.Y.Z+<sha>`, offers none); `todo` is `jig upgrade`, and the item carries `versions: {from, to}` — the project's and the machine's. Not listed while an `upgrade-pull-request-*` item is for the machine's version or a newer one (or for a branch whose name holds no version): `jig upgrade` again would cut a second branch for the same upgrade. One for an older version, such as an abandoned pull request left open, does not hold it back |
| `phase-stopped` | phase | tasks of a phase run stopped; answered once, in the coordinator's session |
| `autopilot-stopped` | task | an autopilot run stopped with a question |
| `gate-waiting` | task | a T3/T4 design waits at its human gate |
| `gate-changed` | task | a design changed after it was approved |
| `git-step` | task | finished and consolidated; the next git step is the person's (the level `jig task ship` would use: `agent.git`, `agent.git_staging`, or `autopilot.git` in a run) |
| `pull-request-waiting` | task | `jig task ship` opened a pull request that waits for review or merge, or a task parked at the staging branch waits on its review (the same kind, its `title` says which): `review, landing` — approved, or no review asked — "waiting for review and for you to land it"; a review that is `waiting`, `none` or unknown, "waiting for review" (`detail` begins with `waiting for review from <logins>` when the cache names them); `changes`, "Changes were requested on a pull request" (`todo`: take it back with `jig task resume <id>`). `detail` says the cache's word (CI green and merges cleanly, red, running, conflicts, or open) and as of when; `todo` names the move (`jig task merge-pr <id> --by human` or `jig task land <id> --by human`) and `jig task pr-status <id> --json` |
| `pull-request-was-open` | task | the last housekeeping run saw a pull request open (it may have merged since); same `detail`, `pull_request` and `actions` as `pull-request-waiting`, the `todo` in the past tense, a refresh first |
| `pull-request-of-abandoned-task` | task | the task was abandoned, and its pull request was open at the last housekeeping run |
| `promotion-conflicting` | task | on the staging flow, a promotion this checkout opened (`promote_url`) is open and the forge cache calls it conflicting with the base branch; `todo` says to run `jig task promote <id>` again, `url` is the promotion |
| `staging-unpromoted` | task | on the staging flow, the task's work has been on origin's staging branch for `git.staging_stale_after` or longer and no promotion is open or merged for it; for a task with no workspace here, `todo` says it is promoted from any checkout, or by its owner. Read from git by branch name: the task may be a colleague's, with no workspace here |
| `staging-unowned` | project | on the staging flow, the reader's own commits on origin's staging branch, merges left out, that the base branch does not have, that no task branch here or on origin holds, and that the reader has not acknowledged with `jig staging ack`. Own: the author's email or name is this clone's git author's (`git var GIT_AUTHOR_IDENT`). Nobody else's commits appear in the item, in any field; once every own one is acknowledged there is no item, until a new one lands (adr-20261113-staging-work-is-reported-to-its-own-author-until-acknowledged) |
| `needs-consolidation` | task | merged; the task can be closed |
| `wrong-base` | task | the work landed on another branch than planned |
| `closed-unmerged` | task | the pull request was closed without merging (housekeeping's `abandoned?`) |
| `worktree-kept` | task | a worktree was kept because it still holds work |
| `started-out-of-order` | task | a live (`active` or `ready`) task was started against the queue's answer with `jig task start <id> --out-of-order --reason <text>`; `detail` is `ahead of task:<other>: <reason>`, the task the queue advised and the reason given. It stands while the task is live; `todo` is to check the reason and, if it does not hold, pause the task and take the other (adr-20261022-the-next-task-is-advised-from-the-queue) |
| `base-behind-origin` | project | the base branch here is behind `origin/<base>` (`origin.behind` > 0), as of the last fetch: what landed there — a merged task, a knowledge decision — is not in this checkout yet; `todo` is `jig refresh` |
| `knowledge-proposed` | project | knowledge documents wait for a decision |
| `sources-changed` | project | adopted source files changed since they were approved |

The two `upgrade-pull-request-*` kinds come from the forge cache (above), never from the forge
itself, so they are as fresh as the last `jig housekeeping` — or the `jig upgrade` that opened the
pull request, which records it there; `jig upgrade --land` asks the forge
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
`jig spec list --json` by `id`. A finished task leaves the queue (`jig queue prune` below), but one
finished since the last prune may still be listed with no match in the default listing (`--all`
lists the finished ones). The envelope's `revision` is the
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

## `jig queue prune --json`

`jig queue prune [--dry-run] [--revision <n>] --json` takes every finished task out of the queue in
one write (adr-20261107-a-finished-task-leaves-the-queue): a task `consolidated`, `abandoned` or
`archived`, or whose workspace is gone, goes with what it waited for and its pause requests; a wait
on a task `jig queue next` reads as `finished` goes too, being met. The commands that finish a task
and every housekeeping run call it. With nothing to take out, nothing is written and the revision
is not checked; `--dry-run` answers the same and writes nothing. Otherwise `--revision` and
`stale-revision` are as for the writes above.

```json
{"dry_run": false, "removed": [{"ref": "task:old", "status": "consolidated"}], "met": [{"ref": "task:next", "on": "task:old"}]}
```

| Field | Type | Value |
|---|---|---|
| `dry_run` | boolean | `true` for `--dry-run`: nothing was written |
| `removed` | array | each item taken out, in the queue's order: `ref` (`task:<id>`) and `status` — `consolidated`, `abandoned`, `archived`, or `gone` when no workspace holds it |
| `met` | array | each wait dropped as met, held by an item that stays: `ref` the item, `on` the finished task |

Refusals: `usage` for an argument the command does not take; `stale-revision`; `failed` for a queue
of another format version. Epic items are never taken out.

## `jig queue next --json`

Which queued task to take next, and what holds the others back. It reads the queue, the tasks'
state files and what the last `jig housekeeping` run recorded, never the network, and writes
nothing: the queue file and the revision stay as they were. The producer's rules are the Jig
documentation's ("Order the work"); this is the shape.

```json
{"next": {"ref": "task:booking-form", "kind": "task", "id": "booking-form", "level": null, "position": 100, "priority": 1, "started": false}, "reason": null, "waiting": [{"ref": "task:booking-message", "on": "task:booking-form", "state": "unknown", "reason": "The message quotes the form"}], "taken": [{"ref": "task:booking-report", "checkout": "/home/me/shop", "since": "2026-10-30T15:09:12Z", "idle_seconds": 960, "command": "task artifact write booking-report discovery --from notes.md"}], "in_progress": [{"ref": "task:booking-export", "id": "booking-export", "priority": 2}], "not_queued": 1}
```

| Field | Type | Value |
|---|---|---|
| `next` | object or null | the task advised; `null` when there is none |
| `next.ref`, `next.kind`, `next.id` | string | `task:<id>`, `task` and the task id |
| `next.level` | string or null | as `item.level` of a write: `epic:<spec-id>`, or `null` on the top level |
| `next.position` | integer | its place within its level, as stored |
| `next.priority` | integer or null | `0` to `5`; `null` when not set |
| `next.started` | boolean | always `false`: kept for readers. A started task is never advised (it is listed in `in_progress`), so the task advised has no branch yet |
| `reason` | string or null | `null` when `next` is set; otherwise why there is none: `waiting` (a candidate waits for a dependency), `taken` (the candidates left are taken by another session), `in_progress` (the candidates left are all started already), `paused` (the queued tasks left are paused or have a pause request) or `empty` (nothing queued is a task to take), the first that holds in that order |
| `waiting` | array | every dependency not finished that holds back a candidate not taken by another session, each `{"ref", "on", "state", "reason"}`; `ref` is the one that waits as the queue stores it (a task, or the epic its tasks inherit the dependency from), `on` what it waits for, `reason` the reason given, `[]` for none |
| `waiting[].state` | string | `open` (not done yet), `broken` (the target was abandoned, is archived or is gone, so the wait never ends: drop it with `jig queue undepend`) or `unknown` (nothing says; `jig housekeeping` may) |
| `taken` | array | every candidate another session is working on, which is therefore not advised, each `{"ref", "checkout", "since", "idle_seconds", "command"}`; `[]` for none |
| `taken[].checkout` | string or null | the checkout that session ran its last command in |
| `taken[].since` | string or null | when that session took the task, UTC; kept while its record is live |
| `taken[].idle_seconds` | integer | seconds since that session last worked on the task |
| `taken[].command` | string or null | the jig command it last ran on the task, without `jig` |
| `in_progress` | array | every queued task that is `active`, not paused and not taken by another session and already has its branch and base commit, in queue order, each `{"ref", "id", "priority"}` (`priority` `0` to `5`, or `null`); never advised, since the advice is what to start. `[]` for none |
| `not_queued` | integer | how many active, unpaused tasks have no item in the queue |

A candidate is a queued task whose state is `active`, not paused, with no pause request and not started yet. Tasks
that are ready, closed, abandoned or gone, and epics, are never advised and never listed.
`waiting` holds the dependencies of candidates only. A candidate is taken when the newest live record
under `.ai/runtime/taken/<id>/` in the clone's main checkout belongs to a session other than the
caller's (adr-20261030-a-task-another-session-works-on-is-not-advised): a record is live for
`checkout.busy_ttl`, it is written only by a session the runtime names, and a caller with no name
of its own holds no task. The failures are the producer's alone and add
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

## `jig task pause --json`

`jig task pause <id> [--reason <text>] [--stash] [--revision <n>] --json` pauses a task at once and
answers with the task. It is what a board calls for a task whose `request-pause` action is withheld
because nobody started it: a request would wait for a stage that never begins. The write is checked
against a revision as `jig task resume`'s is: with `--revision <n>`, the `revision` of the read the
caller decided on; without it, the revision the command reads as it starts. When anything was
written in the clone since, the pause is refused with `stale-revision` and changes nothing. A landed
pause raises the revision by two (the claim and the write), and by two more when it took a pending
pause request out of the queue with it (`jig queue cancel`). `--json` may stand anywhere among the
arguments; without it the command prints its report, as it always has.
`jig task pause <id> --if-requested --stage <name>`, the stage's form, takes neither.

```json
{"task": <task>, "pause": {"stash": null, "request": {"requested_at": "2026-11-12T09:30:00Z", "reason": "standup"}}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it, read after the write: `paused` is `true`, `pause_request` is `null` |
| `pause.stash` | string or null | the stash `--stash` made of this checkout's changes; `null` without `--stash`, or when there was nothing to stash |
| `pause.request` | object or null | the pause request that was pending and went with the pause, `{"requested_at", "reason"}` as `pause_request` carried it; `null` when none was pending |

Refusals: `usage` for an argument the command does not take, a `--revision` without a value or that
is not a revision, a `--reason` with a line break, `--if-requested` beside `--json` or `--revision`,
and an id outside the grammar; `not-found` for no such task; `already-paused`, `wrong-checkout` and
`stale-revision` as in the table above; `not-initialised` and `not-a-repository` as everywhere. Each
of them happens before anything is written. A failure after the claim reads `failed` and leaves the task not
paused: a pending request that could not be taken out of the queue stays, and the revision is raised
by one; a `git stash push` that fails comes after the request went, and puts it back in the queue
with its reason and the time it went back (a warning says when it could not).

## `jig task resume --json`

`jig task resume <id> [--revision <n>] --json` ends a task's pause, or takes a task parked at the
staging branch back for a fix (its `status` goes from `ready` to `active` and `park_resumed_at` is
recorded, so it is not parked again until its next `jig task ship` — schemas/state.md), and answers with the
task and what the resume found. The write is checked against a revision as a `jig queue` write is: with
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
{"task": <task>, "resume": {"paused_days": 3, "stash": {"sha": "9f2c…", "applied": true}, "uncommitted": 2, "overlap": ["scripts/lib/task.sh"], "parked": null}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it — the same object, every field and its `actions` — read after the write: `paused` is `false` |
| `resume.paused_days` | integer | whole days since the task was paused; `0` when the pause has no date |
| `resume.stash` | object or null | the stash the pause recorded, `{"sha", "applied"}`; `applied` is always `true` in an answer, since a stash that does not apply is a refusal. `null` when the pause recorded none |
| `resume.uncommitted` | integer or null | files that differ from HEAD in the checkout the task's branch is checked out in — this one, or its worktree; `null` when the branch is checked out nowhere, or for a task never started, this checkout's count |
| `resume.overlap` | array of strings or null | files the task changed that also changed on its base since they parted, sorted; `[]` when none; `null` when no base or merge base was found. Read in the task's checkout, its uncommitted changes counted; from the branch's commits alone when it is checked out nowhere |
| `resume.parked` | string or null | the reason the task was parked for, `review` or `signal`, when this resume took it back from the staging branch: a task that was not paused. Then `paused_days` is `0` and `stash`, `uncommitted` and `overlap` are `null`, and `task.status` is `active`. `null` for a resume that ended a pause, which leaves the status as it was (a task paused while parked is parked again, and a second resume takes it back) |

Refusals: `usage` for an argument the command does not take, a `--revision` without a value or that
is not a revision (digits without a leading zero), and an id outside the grammar; `not-found` for no
such task; `not-paused` (neither paused nor parked), `wrong-checkout`, `stash-conflict` and `stale-revision` as in the table
above; `not-initialised` and `not-a-repository` as everywhere. Every refusal but `stash-conflict`
happens before anything is written. `stash-conflict` for unresolved conflicts already in the checkout
happens before anything is written too; for an apply that fails it happens after the revision was
claimed (it is raised by one). An apply that refused leaves the state as it was; one that merged the
stash with conflicts, or wrote part of it, records `paused_stash_applied` (schemas/state.md), so the resume after the
person resolved them ends the pause without applying the stash again.

## `jig task set <id> status consolidated --json`

`jig task set <id> status consolidated [--revision <n>] --json` closes a task — the person's yes that
the `close` action waits for — and answers with the task. The write is checked against a revision as
a `jig queue` write is: with `--revision <n>`, the `revision` of the read the caller decided on;
without it, the revision the command reads as it starts. When anything was written in the clone
since, the close is refused with `stale-revision` and changes nothing. A landed close raises the
revision by two (the claim and the write). `--json` may stand anywhere among the arguments; without
it the command prints nothing, as it always has, and `--revision` alone checks the write the same
way.

The two flags are the close's alone. On any other key or value (`jig task set <id> class T2
--revision 7`) they are refused with `usage` and nothing is written, so a program never believes a
write it sent with a revision was checked when it was not.

```json
{"task": <task>}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it — the same object, every field and its `actions` — read after the write: `status` is `consolidated` |

Refusals: `usage` for an argument the command does not take, a key other than `status` or a value
other than `consolidated` beside `--revision` or `--json`, a `--revision` without a value or that is
not a revision (digits without a leading zero), and an id outside the grammar; `not-found` for no
such task; `not-closable` when the close is not offered, as above; `stale-revision` as in the table
above; `not-initialised` and `not-a-repository` as everywhere. Any other refusal — an archived task,
a finding or a missing stage of the route that blocks a bare triage task's close — reads `failed`.
Every refusal happens before anything is written. Unlike the `close` action, which is judged by the
forge cache housekeeping wrote, the command asks the forge now: a cache behind the forge withholds
the action while the command would allow it. A pull request that is not merged, or a forge that
cannot be reached, is `not-closable`. Closing a task that is already `consolidated` lands again and
raises the revision.

A bare triage task (one `jig task ship` filed for open findings) is closed in the same write, its
knowledge decision recorded with it.

## `jig task gate --json`

`jig task gate <id> approved [--by human|agent] [--revision <n>] --json` records the approval of a
T3/T4 design as it is now and answers with the task: what a board's approve button calls, without
`--by`, so the approval is a human's (`gate_by: human`). The write is checked against a revision as
a `jig queue` write is: with `--revision <n>`, the `revision` of the read the caller decided on;
without it, the revision the command reads as it starts. A design rewritten since that read
(`jig task artifact write` raises the revision) is refused with `stale-revision` and nothing is
approved, so the design a person approved is the one they saw. The three keys the approval writes
(`gate`, `gate_design`, `gate_by`) land as one write: a landed approval raises the revision by two
(the claim and the write). `--json` may stand anywhere among the arguments; without it the command
prints its report, as it always has, and `--revision` alone checks the write the same way.

`--by agent` is the self-approval of an unattended run (`autopilot` journals it) and is refused
anywhere else with the plain `failed`: outside such a run the gate is a person's, and no program
acts on that.

```json
{"task": <task>, "gate": {"state": "approved", "by": "human", "design": "069789757ba120c7030986efcf80aeee2b2e7c26"}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it — the same object, every field and its `actions` — read after the write: `gate` is `approved` |
| `gate.state` | string | `approved` |
| `gate.by` | string | who the approval is recorded as: `human` or `agent` |
| `gate.design` | string | the hash of the design documents that were approved, the value `gate_design` holds and a review receipt pins |

Refusals: `usage` for an argument the command does not take, a decision other than `approved`, a
`--by` other than `human` or `agent`, a `--revision` without a value or that is not a revision, and
an id outside the grammar; `not-found` for no such task; `no-gate` for a class without a gate or a
task with no `design.md`; `autopilot-running` and `autopilot-stopped` for a human approval inside the
task's unattended run, as in the table above; `stale-revision` as above; `not-initialised` and
`not-a-repository` as everywhere. Each of them happens before anything is written. The refusal
the command makes is the one the `approve-gate` action carries as its `reason`.

## `jig task abandon --json`

`jig task abandon <id> [--reason <text>] [--moved-to <ref>] [--revision <n>] --json` gives a task up
and answers with the task. The new state — `status`, `abandoned_at`, `abandoned_reason` and
`moved_to`, each set or removed — lands as one write checked against a revision as `jig task pause`'s
is (`--revision <n>`, else the revision the command reads as it starts), and raises it by two, plus
one more when the task left the queue with it (`jig queue prune`). A task abandoned already is
abandoned again, its reason and move replaced, and has nothing to leave the queue. `--json` may stand
anywhere among the arguments.

The command writes the task's state and nothing else: no checkout is touched and the roadmap is not
edited. A task linked to a spec, whose roadmap item the text form closes by running `jig spec drop`,
leaves that item open here: it waits, unchecked and visible, and the table's `drop-item` action
closes it in Jig's own tree (`jig spec drop <id> --json`, below). The text form is as it was.

```json
{"task": <task>, "abandon": {"reason": "lives in monitoring", "moved_to": "../monitoring#sentry-errors", "note": null, "spec": "idea-x"}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it, read after the write: `status` is `abandoned` |
| `abandon.reason` | string or null | the reason recorded; `null` for none |
| `abandon.moved_to` | string or null | the move's target recorded (`<repo>#<task-id>` or `<repo>#spec/<spec-id>`); `null` for none |
| `abandon.note` | string or null | what the text form prints about a target that is not there: the command that files the task there, or the word that nothing is written to a spec there; `null` when there is nothing to say. Nothing is ever written to the other repository |
| `abandon.spec` | string or null | the spec the task is linked to, whose roadmap item is still open; `null` for a task linked to none (or to two) |

Refusals: `usage` for an argument the command does not take, a `--reason` that is empty, has a line
break or a tab, or is missing for a task linked to a spec, a `--moved-to` that is not a reference
(an absolute path, no `#`), a `--revision` without a value or that is not a revision, and an id
outside the grammar; `not-found` for no such task; `wrong-status` for an archived task
(`jig task unarchive` first); `stale-revision` as above; `not-initialised` and `not-a-repository` as
everywhere. Each of them happens before anything is written.

## `jig task archive --json`, `jig task unarchive --json`

`jig task archive <id> [--revision <n>] --json` puts an unfinished task (`active`, `ready` or
`abandoned`) away and `jig task unarchive <id> [--revision <n>] --json` returns it to the status it
had. Both answer with the task, and each lands the new state as one write checked against a revision
as `jig task pause`'s is: `--revision <n>`, else the revision the command reads as it starts. A landed
write raises the revision by two (the claim and the write); an archive raises it by one more when the
task left the queue with it (`jig queue prune`: its entry goes, as for a close, and a warning on
stderr says so). The queue is pruned after the state is moved, so a task never sits archived and
queued for a refused prune. `--json` may stand anywhere among the arguments.

An archive records `archived_from`, `archived_reason` (`manual`) and `archived_at`; an unarchive takes
them away with `absorbed_into`, so a task absorbed into another is its own task again. A reminder that
the task is not queued goes to stderr when it comes back to live work.

```json
{"task": <task>}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it, read after the write: `status` is `archived`, or the status it had |

Refusals: `usage` for an argument the command does not take, a `--revision` without a value or that
is not a revision, and an id outside the grammar; `not-found` for no such task; for `archive`,
`already-archived` and `wrong-status` (a `consolidated` task); for `unarchive`, `not-archived`;
`stale-revision` as above; `not-initialised` and `not-a-repository` as everywhere. Each of them
happens before anything is written. Housekeeping archives a stale task through the same state, once
per run and not checked against a revision, and prints no JSON.

## `jig spec drop --json`

`jig spec drop <task-id> [--revision <n>] --json` closes the roadmap item that names an abandoned task,
the one `jig task abandon --json` left open, and answers with the item. It is the same edit the text
form makes — the item is checked and ends with ` — dropped (<day>)` or ` — moved to <ref> (<day>)` and
the task's reason — but made in Jig's own tree on the spec's own branch, `spec/<sid>`, reaching the
base (the default branch, or an open epic) through a pull request, like `jig spec item`
(adr-20261104-a-write-goes-in-jigs-own-tree): nobody's checkout moves, so none of the text form's
refusals about the checkout (the task's own branch, a phase run, the base not being checked out)
apply. `--revision <n>` as the queue writes take it, and the same `stale-revision`; without it the
write checks against the revision it reads once its tree stands. `--revision` alone, without `--json`,
checks the same write and answers in text. The text form without either flag is unchanged: it edits the
roadmap in this checkout.

The task must be `abandoned` or archived from `abandoned`, and linked to one spec. When several items
name the task, every unchecked one is closed in the one commit, and the answer holds the first.

```json
{"spec": "idea-x", "task": "export-page", "item": {"id": "i-62ba30755b17", "text": "`export-page` — Export a page — dropped (2026-11-14): superseded", "checked": true, "task": "export-page", "fog": false, "phase": 2}, "write": <write>}
```

| Field | Type | Value |
|---|---|---|
| `spec` | string | the spec the task is linked to |
| `task` | string | the task |
| `item` | object | the item as the roadmap on the branch now has it, as in `jig spec item`: `id` (its handle after the edit, which changes with the text), `text`, `checked`, `task`, `fog` and `phase` |
| `write` | object | where the edit went, [below](#jig-writes---json) |

Refusals: `usage`; `not-found` for no such task, a task linked to no spec, a spec with no roadmap on the
branch or the base, and a roadmap with no item that names the task; `wrong-status` for a task that is
not abandoned; `already-closed` for a roadmap whose every item that names the task is checked;
`epic-missing` for an open epic neither here nor on origin; and the refusals of every write, below
(`git-not-allowed` at `agent.git: none`, `write-busy`, `stale-revision`, …). A task linked to two
specs is the plain `failed`. The table's `drop-item` offers the command only when it would find an
open item.

## `jig task land --by human --json`

`jig task land <id> --by human [--without-review] [--revision <n>] [--json]` lands the task's pull
request on the staging branch as a person's decision (adr-20261114-a-persons-pull-request-action-does-not-read-agent-git).
It is the agent's landing (`jig task land <id>`, unchanged) with these differences: the git level
(`agent.git`) is not read; an unattended run's silence is not applied; CI is looked at once and never
waited for; a conflict is never merged directly (no temporary tree: refused `conflict`, the agent lands it);
under `git.staging_review: ask` an unapproved pull request is refused `not-approved` and lands with
`--without-review`, which comments on the pull request that it landed at the person's word. `--json`
may stand anywhere; `--resolved` and `--note-file` are refused `usage`, `--abort` has no JSON form.
The write is checked against a revision as in `jig task resume`: `--revision <n>`, or the revision read as
the command starts; it is claimed right before the first thing is sent to the forge, so `stale-revision`
means nothing was sent. A text landing without `--revision` does not check.

```json
{"task": <task>, "land": {"outcome": "landed", "pull_request": "<url>", "staging": "staging", "without_review": null}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it, read after the landing |
| `land.outcome` | string | `landed`, or `already-landed` when the forge already had the pull request merged |
| `land.pull_request` | string or null | the task's pull request |
| `land.staging` | string or null | the staging branch it landed on |
| `land.without_review` | string or null | `null` for an approved landing; `"person"` for `--without-review`; `"git.staging_review is none"` where the project asks for no approval |

Refusals: `usage`, `not-found`, `wrong-flow`, `no-pull-request`, `pull-request-closed`, `not-ready`,
`not-shipped`, `carries-staging`, `not-approved`, `review-required`, `conflict`, `mergeable-unknown`,
`draft`, `ci-red`, `ci-pending`, `ci-none`, `forge-refused`, `forge-unavailable`, `autopilot-running`,
`ship-running` and `stale-revision`, as in the table above. All but `stale-revision` and the
forge's own answers are given before anything is sent.

## `jig task promote --json`

`jig task promote <id> [--by human] [--commit <sha>] [--title <t>] [--body-file <file>] [--revision <n>] --json`
opens the promotion's pull request for one task tested on the staging branch, as `jig task promote`
does. `--by human` does not read the git level and lets `git.promote_merge: auto` switch auto-merge
on; without it the level stays what it was, and below `pr` the refusal is `git-level`. Several ids or
`--all` are `usage`. The lines a person reads go to stderr; stdout carries the envelope. The revision is
claimed right before the first push or pull request, as for `jig task land`.

```json
{"task": <task or null>, "promote": {"pull_request": "<url>", "already_open": false, "pushed": true, "tested_commit": "<sha>", "in_base": false, "merge": {"outcome": "person", "reason": "git.promote_merge: human"}}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object or null | the task as `jig task list --json` lists it; `null` when the project has no workspace for it (a CI runner) |
| `promote.pull_request` | string or null | the promotion's pull request; `null` when the work is in the base already |
| `promote.already_open` | boolean | the pull request was open before this run |
| `promote.pushed` | boolean | this run pushed the task's branch |
| `promote.tested_commit` | string or null | the staging commit the promotion was judged against |
| `promote.in_base` | boolean | the branch is in the base already: nothing to promote |
| `promote.merge` | object or null | who merges: `outcome` `person` (the person merges), `auto-merge-on`, `auto-merge-already-on`, `merged` (the forge merged it at once) or `not-switched-on`, with `reason` in the words of the report line. `null` when `in_base` |

Refusals: `usage`, `autopilot-running`, `git-level`, `base-conflict` (paths in `message`),
`forge-unavailable`, `stale-revision`, and the promotion's own — `not-on-staging`, `behind-staging`,
`carries-staging`, `shallow-clone`, `not-found` — as in the table above; `failed` for the rest.

## `jig task request-review --json`

`jig task request-review <id> --reviewer <login|name>... [--by human] [--revision <n>] [--json]` asks
the forge to add people as reviewers of the task's open pull request, and takes none off. Names resolve
as `jig task ship --reviewer` resolves them (adr-20261113-reviewers-are-read-from-the-forge): a login
as it is, a part of a login or name that fits exactly one person the repository may ask; a team is
refused. The author of the pull request, the clone's own account, is left out, and said. GitHub:
`gh pr edit <url> --add-reviewer a,b`; GitLab: `glab mr update <iid> --reviewer +a --reviewer +b` (the
`+` adds; without it glab replaces the list). The pull request is read live first: merged or closed is
refused. `--by human` does not read the git level; without it the level must be `pr` or `merge`. The
revision is claimed right before the forge is written: `--revision <n>`, or the one read as the command
starts. The text form prints one line per login asked.

```json
{"task": <task>, "review_request": {"pull_request": "<url>", "requested": ["alice"], "author_left_out": false}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it |
| `review_request.pull_request` | string | the pull request |
| `review_request.requested` | array of strings | the logins asked, in the order given, once each |
| `review_request.author_left_out` | boolean | a `--reviewer` named the author, who was not asked |

Refusals: `usage` (no `--reviewer`; every name was the author), `not-found`, `no-pull-request`,
`pull-request-closed`, `reviewer-unknown`, `forge-unavailable`, `forge-refused`, `autopilot-running`,
`git-level` and `stale-revision`. All but `forge-refused` and `stale-revision` are given before anything
is sent.

## `jig task merge-pr --json`

`jig task merge-pr <id> [--by human] [--revision <n>] [--json]` merges the task's pull request into its
own base on the forge: the direct flow's, or an epic task's, where `jig task land` is the staging
flow's. (`jig task merge` is another command, which merges task branches.) On a staging flow a task whose pull request went
into the base is accepted; a pull request that goes into the staging branch (as `pr_into` says, or as the
forge says once it is read) is refused `wrong-flow`, naming `jig task land <id> --by human`. The forge is
read now, once, in this order, each a refusal that names its reason: merged (the outcome is
`already-merged`, and the close below follows), closed, draft, conflict, mergeability unknown, review
(`not-approved`: changes requested, or the reviewers it still waits for; no review at all goes on, and
branch protection decides), CI looked at once and never waited for, a release's notes. Then the
revision is claimed, and the forge merges the pull request at the head it was read at, by any method the
repository allows, never with `--admin` and never to merge later; a refusal is `forge-refused`. The
checkout is not touched: no branch is left or deleted. After the merge a task whose knowledge decision
is recorded is closed (`status consolidated`) in one write under the same claim; otherwise it stays
open and `close_blocked` says why. `--by human` does not read the git level; without it the level must
be `merge`.

```json
{"task": <task>, "merge": {"pull_request": "<url>", "outcome": "merged", "closed": true, "close_blocked": null}}
```

| Field | Type | Value |
|---|---|---|
| `task` | object | the task as `jig task list --json` lists it, read after the command |
| `merge.pull_request` | string | the pull request |
| `merge.outcome` | string | `merged`, or `already-merged` when the forge already had it merged |
| `merge.closed` | boolean | the task is `consolidated` now |
| `merge.close_blocked` | string or null | `knowledge-not-recorded`: the pull request is merged and the task waits for its knowledge decision (`jig task set <id> knowledge_consolidated true`); `null` otherwise |

Refusals: `usage`, `not-found`, `wrong-flow`, `no-pull-request`, `pull-request-closed`, `draft`,
`conflict`, `mergeable-unknown`, `not-approved`, `ci-red`, `ci-pending`, `ci-none`, `notes-stale`,
`forge-refused`, `forge-unavailable`, `autopilot-running`, `ship-running`, `git-level` and
`stale-revision`. All but `forge-refused` and `stale-revision` are given before anything is sent.

## `jig task pr-status --json`

`jig task pr-status <id> --json` reads where the task's pull request stands on the forge now, for the
person about to decide: the second read that asks the forge (after `jig pr reviewers --json`), so call
it when a person presses a button, never on a timer. It writes nothing and does not raise the
revision. `--json` is required (the text form is `usage`).

```json
{"task_id": "x", "pull_request": {"url": "<url>", "state": "open", "draft": false, "base": "main", "head": "<sha>", "mergeable": "clean",
  "checks": {"state": "pending", "list": [{"name": "test (ubuntu)", "state": "pending", "url": "<job url>", "started_at": "2026-11-13T10:00:00Z", "completed_at": null, "duration_s": 420}]},
  "review": {"state": "waiting", "waiting_for": ["alice"]},
  "protection": {"merge_state": "blocked", "required_approvals": 1, "required_checks": ["test"]},
  "blockers": ["ci-pending", "not-approved"]}}
```

| Field | Type | Value |
|---|---|---|
| `task_id` | string | the task |
| `pull_request.url`, `.head`, `.base` | string | the pull request, the commit at its head, the branch it goes into |
| `pull_request.state` | string | `open`, `merged`, `closed` |
| `pull_request.draft` | boolean | |
| `pull_request.mergeable` | string | `clean`, `conflict`, `unknown` (the forge has not worked it out yet) |
| `checks.state` | string | `red` (a check failed or was cancelled), `pending` (one is running), `green` (every one passed or was skipped), `none` (no check ran) |
| `checks.list[].name`, `.url` | string, string or null | GitHub's checks (`gh pr checks`), GitLab's jobs of the head pipeline; `url` the check's page |
| `checks.list[].state` | string | `pass`, `fail`, `pending`, `skipped`, `cancel` |
| `checks.list[].started_at`, `.completed_at` | string or null | UTC; `null` when the forge does not say |
| `checks.list[].duration_s` | integer or null | seconds from start to completion, or to now for a check still running; `null` without a start |
| `review.state` | string | `approved`, `changes`, `waiting`, `none`, `unknown`, as the landing reads it (`jig_pr_approval_v`) |
| `review.waiting_for` | array of strings | the reviewers still waited for; `[]` when none, or when the forge names nobody |
| `protection.merge_state` | string or null | GitHub's `mergeStateStatus` in lower case (`clean`, `blocked`, `behind`, `dirty`, `draft`, `has_hooks`, `unknown`, `unstable`); GitLab's `detailed_merge_status` as it says it |
| `protection.required_approvals` | integer or null | what the base branch's rules ask (GitHub's `rules/branches`, GitLab's `approvals_required`); `null` when the forge would not say |
| `protection.required_checks` | array of strings or null | the checks the base branch's rules require; `null` when the forge would not say, and always on GitLab |
| `blockers` | array of strings | what holds the merge back now, among `draft`, `conflict`, `mergeable-unknown`, `ci-red`, `ci-pending`, `ci-none`, `not-approved` (changes requested or a reviewer awaited), as `jig task merge-pr` refuses them; `[]` for a pull request ready to merge, and for one that is not open |

Refusals: `usage` (no `--json`, a task id missing), `not-found`, `no-pull-request`,
`forge-unavailable` (no forge for this clone, its CLI missing or not signed in, or the call failed:
`message` holds why).

## `jig task artifacts --json`

`jig task artifacts <id> --json` lists the documents in a task's workspace — the one
`_task_workspace_root` resolves, so a task in its own worktree is read where Jig keeps it, from that
worktree or from the main checkout. `--json` may stand anywhere among the arguments. It is a listing,
not the route report the text form prints: it asks nothing of the task's class, and `--provided` (a
caller's claim) cannot be combined with it.

```json
{"task": "<id>", "artifacts": [<artifact>, ...]}
```

`artifacts` holds every kind `jig task artifact` writes, always all twelve, in this order: `task`,
`discovery`, `spec`, `alternatives`, `design`, `plan`, `review`, `verification`, `handoff`,
`knowledge-map`, `commit-message`, `pr-body`. A kind not written yet is listed as `missing`, never
left out; a kind added later is added to the list, which is compatible.

| Field | Type | Value |
|---|---|---|
| `kind` | string | one of the kinds above |
| `state` | string | `present` (a readable, non-empty regular file in the workspace), `empty` (a regular file with nothing in it), `missing` (no file), `unavailable` (something Jig will not read: a link out of the workspace or one it cannot follow, a directory, a file it may not read) |
| `reason` | string or null | for `unavailable`, why, in the words the text form prints in parentheses (`outside workspace`, `symlink loop`, `unreadable link`, `missing parent`, `missing or not a regular file`, `unreadable`); `null` otherwise |
| `updated_at` | string or null | the file's modification time, UTC `YYYY-MM-DDTHH:MM:SSZ`, for `present` and `empty`; `null` otherwise |
| `bytes` | integer or null | the file's size in bytes, for `present` and `empty`; `null` otherwise |

`present` is the fact the text form reports as `present`: presence proves nothing about approval
or quality (ADR-0020). The read writes nothing and does not raise the revision.

Refusals: `not-found` for no such task; `usage` for a missing id, an id outside the grammar, an
unknown argument and `--provided` beside `--json`; `not-initialised` and `not-a-repository` as
everywhere. A workspace link Jig does not accept (one leading anywhere but this task's workspace in
another worktree of this repository) reads `failed`.

## `jig task artifact read --json`

`jig task artifact read <id> <kind> --json` answers with one document of a task's workspace,
resolved as `jig task artifacts --json` resolves it. `<kind>` is one of the twelve kinds above.
`--json` may stand anywhere among the arguments; without it the command prints the document's bytes
as they are.

```json
{"task": "<id>", "kind": "plan", "updated_at": "2026-10-29T09:12:40Z", "bytes": 2221, "content": "# Plan\n..."}
```

| Field | Type | Value |
|---|---|---|
| `task` | string | the task id |
| `kind` | string | the kind asked for |
| `updated_at` | string or null | the file's modification time, UTC; `null` when it cannot be read |
| `bytes` | integer or null | the file's size in bytes; `null` when it cannot be read |
| `content` | string | the whole file as a string, trailing newlines included; `""` for an `empty` document |

The envelope's `revision` is the one `jig task artifacts --json` reports while nothing is written,
so a consumer reads the list and a document under one revision. The read writes nothing.

Refusals: `not-found` for no such task, and for a kind the task has no document of (`missing`);
`usage` for an unknown kind, a missing or extra argument, an id outside the grammar, and `--json`
with `write` or `append` (it goes with `read` only); `not-initialised` and `not-a-repository` as
everywhere. A document Jig will not read (`unavailable` in the list) reads `failed`, its reason in
the message.

## `jig knowledge proposed --json`, `jig knowledge sources --json`

The knowledge waiting for a person, and the files its stubs link. Both read the documents under
`.ai/knowledge/` and git, write nothing and raise no revision. `--json` follows the subcommand
(`jig knowledge proposed --json`); the text forms print what they always did.

```json
{"proposals": [<proposal>, ...], "waiting": <write or null>}
```

| Field | Type | Value |
|---|---|---|
| `proposals` | array | every document whose status is `proposed`, in the order the text form lists them; `[]` when none |
| `proposals[].id`, `.type` | string | the document's `id` and `type` |
| `proposals[].domains`, `.paths` | array of strings | its `domains` and `paths` as written; `[]` for none |
| `proposals[].path` | string | the document's file, relative to the repository |
| `proposals[].summary` | string or null | its `summary`; `null` when it has none |
| `proposals[].source` | string or null | for a stub, the file it links, relative to the repository; `null` for any other document |
| `proposals[].waiting` | object or null | a decision on this document committed in Jig's own tree that has not landed: `decision` (`accepted`, `rejected`), `branch` and `pr` (string or null). The document here still says `proposed`, and it is until that lands. `null` when none waits |
| `proposals[].decidable` | boolean | a decision sent now (`accept` or `reject` with `--json`) would be judged on this document: its file is on the tip of the decisions waiting, or, when none waits, on the base as `origin/<base>` has it (the local base without origin), as of the last fetch. The write asks the same question of the commit its tree stands on. Whether it was decided already is `waiting`'s to say, and an id that differs there is still `not-found` |
| `proposals[].reason` | string or null | `null` when `decidable`; otherwise the code the decision would be refused with: `not-on-base` (only in this checkout or in commits the base does not have: commit and push it), `not-on-branch` (on the base, but not on the decisions waiting, cut before it got there), or `landed` (`origin/<base>` decided it already — the proposal is no longer `proposed` there — and this checkout is only behind: no decision is owed, `jig refresh` brings it here; a decision sent anyway is refused by the checks the write makes where it is judged) |
| `proposals[].lossy` | boolean | `true` when a string of this proposal held bytes that are not UTF-8 and they were dropped: a `path` or `source` read without them may name another file. `false` otherwise |
| `waiting` | object or null | the [write](#jig-writes---json) those decisions are on; `null` when none waits |

```json
{"sources": [<source>, ...], "counts": {"linked": 2, "changed": 1, "unrecorded": 0, "missing": 0, "landed": 0}, "waiting": <write or null>}
```

| Field | Type | Value |
|---|---|---|
| `sources` | array | every stub that links a source, in the text form's order; `[]` when none |
| `sources[].id` | string | the stub's `id` |
| `sources[].state` | string | `ok` (the source is the text that was approved), `changed` (it is not), `unrecorded` (no `source_hash` was ever recorded, so nothing approved the current text), `missing` (the source is not a readable file inside the repository), or, for a stub that is not accepted, its own status (`proposed`, `rejected`, ...) |
| `sources[].status` | string or null | the stub's `status` |
| `sources[].path` | string | the stub's file, relative to the repository |
| `sources[].source` | string | the linked file, relative to the repository |
| `sources[].bytes` | integer or null | the linked file's size in bytes; `null` when it is `missing` or not a file |
| `sources[].waiting` | object or null | a decision on this stub waiting on a branch, as on a proposal; `decision` is also `reviewed` here, and `rejected` for a dropped link. `state` stays what it is here until that lands. `null` when none waits |
| `sources[].decidable`, `.reason` | boolean, string or null | as on a proposal. For a `changed` or `missing` source the change is judged too: the stub has to be there with its source there not the approved text, or a `reject` there would find nothing to drop. `landed` when `origin/<base>` has the stub rejected (its link dropped), or approved at the text its source has there and here. Never for a document this checkout changed since it forked from the base |
| `sources[].lossy` | boolean | as on a proposal: `true` when a string of this record lost bytes that are not UTF-8, so its `path` or `source` may name another file |
| `waiting` | object or null | the [write](#jig-writes---json) those decisions are on; `null` when none waits |
| `counts` | object | `linked` (the length of `sources`), `changed`, `unrecorded` and `missing`: the figures the text form's last line prints, the states in this checkout; `landed`, how many of the `changed` and `unrecorded` ones have `reason` `landed`. What `jig status` counts as changed is `changed` plus `unrecorded`, less the `landed` ones |

`jig knowledge sources --diff <id> --json` answers for one stub:

```json
{"id": "convention-coding-style", "source": "docs/coding-style.md", "state": "changed", "approved_hash": "d9dc8059e3a61983d9e3ab6d32dfabc8aa7feb2d", "diff": "--- docs/coding-style.md (approved)\n+++ docs/coding-style.md\n@@ ...", "lossy": false}
```

| Field | Type | Value |
|---|---|---|
| `id`, `source` | string | the stub and the file it links |
| `state` | string | as `sources[].state` above, the same word for the same stub: `ok`, `changed`, `unrecorded` or `missing`, or for a stub that is not accepted its own status; the text form refuses a missing source, this answers it |
| `approved_hash` | string or null | the git blob hash of the approved text (`source_hash`); `null` when none was recorded or the source is `missing` |
| `diff` | string or null | the unified diff from the approved text to the file now, as `diff -u` prints it with the labels `<source> (approved)` and `<source>`; `null` unless the file changed since a recorded approval (`state` is `changed`, or a status for a stub that is no longer accepted) and git still has the approved text. A `changed` state with a `null` diff, like `unrecorded`, means the file is to be reviewed whole |
| `lossy` | boolean | `true` when `diff` or `source` held bytes that are not UTF-8 and they were dropped: a `source` read without them may name another file. Not set for the carriage return Git Bash drops from a CRLF line, or for a lone one a platform's `diff` turns into a line break |

Every string escapes as the envelope says. A source file is whatever a person committed, so a
diff may hold quotes, backslashes, tabs, control bytes or bytes that are not UTF-8: the first
three kinds come out escaped and read back unchanged; bytes that are not valid UTF-8 are dropped
from the answer, so the line is always valid JSON in UTF-8. The object they were dropped from says
so with its `lossy`: a proposal, a source, the `--diff` answer; a string outside those (the
`branch` of a write waiting) carries no flag. A character from U+100000 to U+10FFFF is valid and
kept; a lead byte above that range is dropped with the bytes that follow it. Without `iconv` on the
machine, every byte outside ASCII is replaced by `?` instead, one `?` per byte (a Cyrillic letter is
two), and `lossy` is set wherever one was.

Refusals: `not-found` for an id no document has, and for a document that links no source;
`usage` for an argument these commands do not take (`jig knowledge proposed x --json`, `sources
--diff` without an id, a second id); `not-initialised` and `not-a-repository` as everywhere.

## `jig knowledge read --json`

`jig knowledge read <id> --json` answers with the text of one knowledge document, whatever its
status, so a person can be shown what they are asked to decide: a proposed document as written, or
the file a stub links as it is now. It reads the checkout, writes nothing and raises no revision.
`--json` may stand anywhere among the arguments; the command has no text form (without it, it is
refused as `usage`).

```json
{"id": "feature-alpha", "status": "proposed", "path": ".ai/knowledge/features/alpha.md", "bytes": 1234, "content": "---\nid: feature-alpha\n...", "lossy": false, "source": null}
```

For a stub, `source` is the linked file:

```json
{"id": "convention-coding-style", "status": "proposed", "path": ".ai/knowledge/sources/coding-style.md", "bytes": 261, "content": "---\nid: convention-coding-style\n...", "lossy": false,
 "source": {"path": "docs/coding-style.md", "bytes": 900, "content": "# Style\n...", "lossy": false}}
```

| Field | Type | Value |
|---|---|---|
| `id` | string | the document's `id` |
| `status` | string or null | its `status`; `null` when it has none |
| `path` | string | the document's file, relative to the repository |
| `bytes` | integer | the file's size in bytes, as it is on disk (the dropped bytes of a `lossy` text included) |
| `content` | string | the whole file, frontmatter included, trailing newlines included; `""` for an empty file |
| `lossy` | boolean | `true` when `content` or `path` held bytes that are not UTF-8 and they were dropped. A NUL byte is dropped without it |
| `source` | object or null | for a stub, the file it links as it is now; `null` for any other document, and for a stub whose source is not a readable file inside the repository (missing, unreadable, a link, outside the repository: the states `jig knowledge sources` calls `missing`) |
| `source.path` | string | the linked file, relative to the repository |
| `source.bytes` | integer | its size in bytes, as it is on disk |
| `source.content`, `source.lossy` | string, boolean | its text and whether bytes were dropped from it or from `source.path`, as `content` and `lossy` |

Strings escape as the envelope says, and bytes that are not valid UTF-8 are dropped as in
`sources --diff` (or, without `iconv`, every byte outside ASCII becomes `?`, one per byte), so the line is always
valid JSON in UTF-8. A source is read whatever its state: `jig knowledge sources --json` says
whether it changed since it was approved. The text is the checkout's: a decision waiting on
`knowledge/decisions` is not applied to it (see `waiting` in `proposed --json`).

Refusals: `not-found` for an id no document has; `usage` for a missing id, a second argument, an
argument that starts with `-`, and for the command without `--json`; `not-initialised` and
`not-a-repository` as everywhere.

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
| `from`, `to` | the project's Jig before the run (the manifest's `jig.version`) and the version it upgrades to; `null` when unknown. Either carries `+<short sha>` (`0.40.0+278958c`) for unreleased code, taken with `--unreleased` |
| `outcome` | `planned` (a dry run), `linked` (link mode, every link in place), `nothing-to-do`, `incomplete` (the self-check failed, so nothing was committed; run again), `staged` (changed and left for the person to commit: `agent.git` is `none`, or the repository has no commit yet), `upgraded` (committed) |
| `files` | how many framework files the run placed, kept as they were, removed and left in conflict; `null` in link mode |
| `git` | how far git went, by `agent.git` (`level`): the upgrade's `branch` (`null` when the project works on one branch), the `commit` (`null` when staged), `pushed`, the `pull_request` URL or `null`, and `merged`. `null` when nothing was staged or committed |
| `manual_steps` | the steps this release asks for by hand, as the upgrade commit lists them; empty when there are none |
| `would_stop` | for a dry run, every reason a real run would refuse, as `upgrade-blocked` would name it; empty otherwise |

Refusals: `upgrade-blocked` before anything is touched; `not-merged` when the upgrade to this version
is already on an unmerged `jig/upgrade-<version>` branch whose pull request the forge reports open
(the forge is asked once, only then; without its answer, or for a merged or closed pull request, the
refusal reads `failed`); `usage` for an argument the command does
not take or `--from` without its value; `not-initialised` and `not-a-repository` as everywhere. Any
other refusal — a source that is not a Jig checkout, a project in link mode where links cannot be
made — reads `failed`. A failure after the commit (the push, the pull request or the merge) also
reads `failed` and carries no data: the commit and the branch are already there, and the push or
the pull request is left to the person — a second run stages nothing and ends `nothing-to-do`.

## `jig upgrade --land --json`

`jig upgrade --land` brings an upgrade that ended in a pull request here once the forge has merged
it: it asks the forge for the pull requests of `jig/upgrade-*` branches into `git.base_branch`,
fetches the base, checks the base branch out (from the base or from the upgrade's own branch),
fast-forwards it to `origin/<base>` — from any other branch or a detached HEAD it moves only the
base's ref, never the checkout — and lets the upgrade's branch go the way a merge Jig made itself
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
 "land": {"base": "main", "checkout_on_base": true, "branch_deleted": true, "origin_branch_deleted": true},
 "manual_steps": [], "would_stop": []}
```

| Field | Meaning |
|---|---|
| `mode`, `dry_run`, `files`, `manual_steps`, `would_stop` | as in `jig upgrade --json`; `dry_run` is `false`, `files` `null`, the two lists empty |
| `from`, `to` | the Jig the base branch here recorded before (`jig.version` in its manifest) and after the fast-forward; on `nothing-to-do` both are the base's. A value may carry `+<short sha>` for unreleased code |
| `outcome` | `landed`, or `nothing-to-do` when no merged upgrade waits to be brought here (and none is open) |
| `git` | on `landed`: `level` (`agent.git`), the upgrade's `branch`, the `commit` the base branch is at now, `pushed` and `merged` (both `true`), and the `pull_request` URL or `null`. `null` on `nothing-to-do` |
| `land` | on `landed`: the `base` fast-forwarded; `checkout_on_base`, `true` when this checkout is on it now, `false` when it stayed on another branch or a detached HEAD and only the base's ref moved (that branch takes the upgrade when it merges the base); and whether the upgrade's branch was deleted here (`branch_deleted`) and on origin (`origin_branch_deleted`). A branch kept says why in the text on stderr. `null` on `nothing-to-do` |

Refusals: `not-merged` when the pull request is still open; `upgrade-blocked` with every reason at
once; `usage` for any other argument. Both change nothing. No origin, no signed-in forge CLI, or a
forge that did not answer read `failed` and change nothing either.

## `jig config keys --json`

Every key Jig reads, in the order of its registry (`jig_config_key_rows`, `scripts/lib/config.sh`),
with what the clone answers for it. Reads `.ai/config.yaml` and `.ai/config.local.yaml` and
nothing else; changes nothing. Takes no argument but `--json`.

```json
{"keys": [{"key": "agent.git", "value": "none", "set": false, "source": "default", "scope": "local only", "kind": "choice", "allowed": ["none", "commit", "push", "pr", "merge"], "default": "none", "description": "How far your agent takes a finished task with git.", "secret": false}]}
```

| Field | Type | Value |
|---|---|---|
| `key` | string | the key as it is written in the file |
| `value` | string or null | what a reader of Jig gets (for `git.worktree_root`, whose reader builds its own default, the registry's placeholder): the first non-empty answer of the local file (for a key it may answer), then `.ai/config.yaml` (never for a local-only key), then the default; always a string, as the file writes it (`"true"`, `"30"`, `"[claude, codex]"`). `null` when nothing answers and there is no default. Always `null` for a secret |
| `set` | boolean | a file answers for the key (`source` is not `default`). For a secret this is all a reader learns |
| `source` | string | `local`, `project` or `default`: the layer `value` came from |
| `scope` | string | who may answer the key, as `jig config keys` prints it: `project` (only `.ai/config.yaml`), `local` (the local file wins, the project's answers when it is silent) or `local only` (the local file alone) |
| `kind` | string | `boolean` (`true` or `false`), `choice` (one of `allowed`), `duration` (`<n>d`, `<n>h`, `<n>m` or `<n>s`), `number`, `text` (anything the file can hold) or `list` (an inline list such as `[a, b]`). A kind a reader does not know is `text` |
| `allowed` | array or null | the values of a `boolean` or a `choice`, in the order a page offers them; `null` for the other kinds. Every value of a local key is one `jig config set` accepts |
| `default` | string or null | the value used when no file answers; `null` for a key that is off until set |
| `description` | string | one line, for a person |
| `secret` | boolean | `true` for `notify.telegram.token`: its value is never printed by any `--json` read or write, only whether it is `set` |

A key written in the local file that no reader answers from (a misspelling, a project key) is not
listed. Refusals: `usage` for an argument; `not-initialised` and `not-a-repository` as everywhere.

## `jig config` writes

`jig config set <key> <value> [<key> <value>...] --local --json` and `jig config unset <key>
[<key>...] --local --json` change the clone's own `.ai/config.local.yaml` and answer in the
envelope; `.ai/config.yaml` is the team's, and neither writes it. Both take `--revision <n>`, the
`revision` of the read the caller decided on: when anything was written in the clone since, the
write is refused with `stale-revision` and nothing is changed. Without it the command checks
against the revision it reads itself as it starts. A landed write raises the revision (by two: the
claim and the write), so read again for the new one. `--dry-run` cannot be combined with `--json`
(`usage`). The same flags work without `--json`; there, a write without `--revision` is not checked.

```json
{"keys": [<key>, ...]}
```

`set` answers with the object of each key it wrote (as `jig config keys --json` lists it, in the
order given), as the clone now reads it. A value `set` accepts is exactly what the key's `kind` and
`allowed` describe.

```json
{"keys": [<key>, ...], "removed": ["agent.git"]}
```

`unset` answers with the object of each key given that Jig reads, as it now stands (so back on its
default, or on the project's value), and `removed` lists the keys it took out of the file,
including a key no reader answers from, which has no object. A key the file did not hold costs
nothing: nothing is written and the revision does not move. `unset` accepts any key the file may hold,
as the text form does.

Refusals, all before anything is written: `unknown-key` and `not-local` for a key `set` may not
write, `invalid-value` for a value its key does not accept, `secret-key` for the token, which is
never set on a command line; `usage` for a missing key or value, an unknown flag, a missing `--local`,
a name a file cannot hold, a malformed `--revision` or `--dry-run`; `stale-revision` as above. One
bad pair refuses the whole call.

## `jig pr reviewers --json`

Who may be asked to review a pull request into a branch (adr-20261113-reviewers-are-read-from-the-forge):
the people a UI offers before `jig task ship <id> --reviewer <login>`. The one read that asks the
forge, since what it answers lives only there: call it when a person is about to choose, never on a
timer. It writes nothing.

```json
{"base": "staging", "source": "history", "author": "me", "candidates": [{"login": "alice", "name": "Alice Smith", "reviews": 2}, {"login": "bob", "name": null, "reviews": 1}]}
```

| Field | Type | Value |
|---|---|---|
| `base` | string | the branch the pull request goes into: `--base`, else the staging branch on a sound staging flow, else `git.base_branch` |
| `source` | string | `history`: the people who reviewed the last 30 merged pull requests into `base`, most frequent first; `assignable`: nobody the repository may still ask did, so everyone it may ask, in the forge's order |
| `author` | string | the login this clone asks the forge as — the author of a pull request `jig task ship` opens, never among the candidates |
| `candidates` | array | `[]` when there is nobody to ask |
| `candidates[].login` | string | what `--reviewer` takes |
| `candidates[].name` | string or null | the person's name on the forge; `null` when it has none |
| `candidates[].reviews` | integer or null | under `history`, how many of those pull requests the person reviewed (once per pull request, never its author); `null` under `assignable` |

Only people: no team, no bot. GitHub: the reviews submitted and the repository's assignable users.
GitLab: the reviewers each merge request named and the project's active members. Refusals: `usage`
for an unknown argument or `--base` without a value, `not-a-repository`, `forge-unavailable`.
