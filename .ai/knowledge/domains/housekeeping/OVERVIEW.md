---
id: domain-housekeeping
type: domain
status: active
summary: "Unattended, LLM-free end of a task's life: remote state, the lifecycle policy, two-stage purge, and the triggers."
domains:
  - housekeeping
topics: []
load: domain
paths:
  - scripts/lib/housekeeping.sh
  - scripts/jig-session-hook
  - "templates/scheduler/**"
  - scripts/lib/hklog.sh
  - scripts/lib/forgecache.sh
reviewed_at: 2026-11-11
---
# Housekeeping

Ending a task's life without a developer and without an LLM. The domain is small, and
almost all of its difficulty is in one property: it deletes things, unattended, on
evidence it inferred itself.

## Responsibility

- Deriving **Remote State** per task, in tiers: forge (`gh`/`glab`) → git ancestry →
  `unknown`. Derived every run, never written into a task's `state` (ADR-0005).
- Applying the lifecycle policy — a pure function of `status`, remote state,
  `paused`, age and, for an archived task, `archived_from` and `archived_reason`,
  which is why the whole table is testable without a repository.
- The two-stage **Purge** of a closed task: move to **Trash**, delete only after `trash_ttl`
  (ADR-0006).
- The **Archive** of a task nobody finished: an abandoned task older than `abandoned_ttl`, or an
  `active`/`ready` one untouched for longer than `stale_after`, is archived through the task
  domain's `_task_archive`, not deleted, and kept without a time limit
  (adr-20261027-a-task-nobody-finished-is-archived-not-purged). Its log line is `action=archive
  reason=abandoned|stale`; a dry run prints `would-archive`. An archived task whose work merged is
  flagged `needs-consolidation` unless it was archived from `abandoned` or absorbed by another task
  (`archived_reason: absorbed`); those are left as they are, and one with neither key keeps the flag.
- The **Queue prune** at the start of every run, before this run's log marker and any purge:
  `jig queue prune` (a dry run: `--dry-run`) takes the queue entries of finished or vanished tasks
  out, and every wait the advice reads as met — on a closed task, or one the last run logged
  `remote=merged` — through `jig queue`, the queue's only writer
  (adr-20261107-a-finished-task-leaves-the-queue). Its lines are printed when it took anything out;
  a refusal is a warning, never the run's failure.
- The audit trail: `.ai/runtime/housekeeping.log`, one line per decision including
  `via=` (the deciding tier), and the `.ai/runtime/last-housekeeping` stamp. A **purge**
  line additionally carries the task's own `class=`, `created=` and `consolidated=`
  (`_hk_task_facts`), read before the workspace moves: the purge is the last moment those
  facts exist anywhere (ADR-0027).
- The **forge cache**, `.ai/runtime/forge-cache` (`lib/forgecache.sh`, schemas/json.md): what
  the run heard from the forge about each pull request —
  `<head> <base> <state> <ci> <fetched_at> <head_commit> <url>`, the last two `-` when unknown and
  absent from a line an older run wrote — kept for `jig task list --json` and `jig status` (its
  `upgrade-pull-request-*` items), which never ask the forge themselves. States come from the list
  the forge tier already fetches; on GitHub a second list call asks the checks of the open pull
  requests only (about 1 s, where the check rollup for all 200 in the first call cost 13 s instead
  of 2), so a run makes two calls whatever the number of tasks. Written atomically after a list the
  forge answered, never on a dry run, never by a worktree that borrows the owner's task directory;
  a run without an answer leaves the last cache, whose entries keep their `fetched_at`.
- **`jig refresh`**, outside housekeeping and on demand: the same fetch (`_hk_fetch`'s form), then
  a fast-forward of the base only, never moving the checkout or touching its changes; the button a
  program shows while `jig status --json` reports `base-behind-origin`
  (adr-20261112-refresh-brings-the-clone-up-to-origin).
- The **Session Hook** and the scheduler examples — triggers, both optional, neither
  installed automatically (ADR-0024).
- The daily **latest-release check**: right after its own fetch, when `housekeeping.fetch`
  is not false, one `git ls-remote --tags` against the *global framework's* origin (not the
  project's), asking the same question `jig doctor` asks on demand
  (`jig_check_newest_release`, common.sh — shared so the two never drift). The answer goes to
  `.ai/runtime/latest-release` (`latest=<version> checked_at=<date>`, or `failed
  checked_at=<date>` when the network did not answer), so `jig status` can show a newer
  release without a network call of its own, for the audience — the non-developer who never
  runs `jig doctor` — this was built for (task status-says-a-newer-jig-exists). Never fails
  the run.
- Removing a **Task Worktree** once the task is closed and its branch landed on its own
  base, or when its workspace is purged, whichever comes first (ADR-0029 as amended
  2026-09-22). This is one of the two deletions outside `.ai/`, and git performs it: `git
  worktree remove`, never with `--force`. A worktree that has to stay is flagged `worktree-kept`, and
  `jig status` counts it; at a purge it keeps the workspace with it, and beside
  `base-unreleased` the workspace is kept anyway. When git succeeds but the directory remains —
  Windows leaves the Directory Links in it — only links and empty directories are removed
  there; anything else is reason `leftover` (ADR-0037).
- Not a **Review Tree**'s: a detached `<git.worktree_root>/.pr-<n>` and `refs/jig/pr/<n>/*`, made
  by `jig pr fetch`, are neither a task's worktree nor a branch, so housekeeping neither removes
  nor reports them; `jig pr list` shows them and `jig pr cleanup` takes them back
  (adr-20261109-a-pull-request-is-read-in-a-detached-tree-of-the-clone).
- Deleting the **branches Jig made** once their work landed — the other deletion outside
  `.ai/`, and git performs it too (`_hk_branch_sweep`,
  adr-20261007-a-merged-branch-leaves-with-its-work). After the task loop, in the main checkout
  only: a local branch or `origin/` ref that `jig_branch_deletable` calls Jig's (`jig/upgrade-*`,
  `finish/<id>`, the task template's name; under a template with nothing before `{id}`, only a
  branch a task record in the workspace or trash names — read afresh in the sweep, after this
  run's purges moved records to trash), that no workspace left in place holds and no
  worktree has checked out, and that landed — a merged pull request, or ancestry into the
  default branch. `git branch -d` first, against the upstream still there, which is what lets a
  squash merge through (hence `fetch --no-prune`); when somebody else's prune took that upstream
  and `-d` refuses, the forge's merged head vouches for a tip that is it or its ancestor
  (`update-ref -d` at that tip, adr-20261010-a-gone-upstream-defers-to-the-merged-head); origin only at `agent.git` `push` or above,
  with a merged pull request whose head is where origin's branch still is, by a lease push — one
  for the whole sweep, after the local branches, so a run makes at most two network calls (its
  `ls-remote` and that push) however many branches it deletes: over HTTPS each call may cost the
  person a credential-helper dialog (issue #317). A purged task's branch goes in the run that purged it, as
  its worktree does. Lines `branch=<b> where=local|origin action=delete|keep`, without `task=`.
- Judging each task against **its own base** (`jig_task_base`, ADR-0039): ancestry, the
  "branch is the base" rule, the unknown reason and the reflog of own work all use it, bases
  resolved origin first. Work merged into another branch is flagged `wrong-base` beside
  `unknown` — kept, exit 3, counted by `jig status`. A closed task merged into a base that has
  not reached the default branch — a phase of an open epic — is kept with `base-unreleased`
  until it has (ADR-0040).
- On the staging flow, each task's **staging state** (`_hk_staging_init`, once per run after the
  fetch, through `jig_staging_states` in common.sh): `on` or `behind`, derived from git by branch
  name and written into no task's state (ADR-0005). It goes on the task's log and `--verbose` line
  as `staging=on|behind`, after `flags=` and before a purge's facts, and into the report's note
  (`on staging`, `behind staging`). A pull request merged into the staging branch is not
  `wrong-base`, and a task on staging is not archived as stale — it is kept with
  `STALE_CANDIDATE`, as work landed on the wrong base is (ADR-0039 as amended 2026-11-11). On any
  other flow the run, its log and its report are what they were.

## What governs it

Read these before changing anything here; each is a rule someone paid for.

- **Nothing is destroyed on `unknown`** (RULES.md). Every uncertainty in this
  domain must resolve *towards* `unknown`, never away from it. The one exception is a
  task a human abandoned: `housekeeping_decide` archives it after `abandoned_ttl` whatever
  its remote state (ADR-0005 as amended), keeping the workspace. Archiving deletes nothing, which
  is why a stale `active` or `ready` task may be archived too, and why one with a worktree (or its
  branch checked out with changes) stays flagged `STALE_CANDIDATE`: a person may be working there.
- **No path is deleted or moved without validation** (RULES.md, ADR-0006). Use
  `task_dir`/`_task_valid_id` — the single choke point — and never transcribe a regex.
  ADR-0006's own text carried a wrong pattern for two phases; the code was right.
- **Ancestry answers "landed", not "open"** (ADR-0025), and a task whose branch *is* the
  base branch is `unknown`, because `--is-ancestor main main` is trivially true.
- **Commits since the fork are not proof of the branch's own work** (ADR-0032). A branch
  fast-forwarded onto a newer base carries the base's commits and its tip is an ancestor of
  the base. `merged` needs a reflog position the base did not contain at that time
  (`_hk_own_work`); a tie in time goes to the base, and a missing reflog means `unknown`.
  Compare positions, never reflog messages.
- **The tree a killed write left goes** (`ot_sweep`, `lib/owntree.sh`): it is not a task worktree, it
  holds its branch against a person's `git switch`, and with no write holding the lock nothing in it
  is anybody's (adr-20261104-a-write-goes-in-jigs-own-tree).
- **A worktree goes when its task is closed and landed, or with its workspace, and only
  through git** (RULES.md, ADR-0029 as amended). A phase's workspace waits for its epic
  (ADR-0040); its worktree does not, because nothing reads the worktree once the task is
  closed. A merged task not yet closed keeps it: closing is the human's confirmation
  (ADR-0030). It must be listed with the task's branch, lie under `git.worktree_root`,
  hold nothing under `.ai/workspace/tasks/` but links, be clean and not be locked — the
  lock is checked before git is asked, for jig's own worktrees too, so the reason reads
  `locked`. `git worktree remove` deletes *ignored* files without asking, and git's own
  refusals therefore cover nothing gitignored, so one condition is jig's own: no repository
  inside those ignored paths may hold work that is nowhere else — asked of that repository's
  own git, since nothing outside it knows, and the reason reads `nested-repository`; when git will
  not say what it ignores at all, the reason reads `ignored-unknown` and the worktree is kept on
  the same principle as every other unanswered question here
  (adr-20260925-a-worktree-goes-only-when-every-git-in-it-agrees). The question names its
  untracked mode (`--untracked-files=normal`), because a person's `status.showUntrackedFiles`
  otherwise decides the answer: `no` leaves the ignored paths out entirely, which read as
  "nothing nested" and removed a repository's only copy, and `all` lists every file in
  `vendor/` and `node_modules/`, which on 2026-10-16 ran a find per file and exhausted the
  system's descriptors through bash 3.2's per-iteration process substitutions. Any git output
  a script parses is asked in a mode it names, never in the user's. Ignored files that are
  not a repository still go, and the removal's log line names them in its last field,
  `ignored=`; an orphaned task directory under `.ai/workspace/` is not a repository and is
  not covered by this. It is also no longer how a worktree normally looks: a worktree jig
  makes borrows the owner's whole task directory, and `task new` refuses in one that does
  not (ADR-0029 as amended). Inside a worktree, housekeeping still never sees the borrowed
  workspaces: it finds them with `find "$tasks_dir"` and **no trailing slash**, and find
  does not descend a symlink named as its starting point. Keep it that way — the slash is
  the whole difference between reporting nothing and purging another checkout's tasks into
  a trash directory that dies with this tree.
- **A worktree jig did not create is never removed, and holds the workspace only while
  work waits there** (ADR-0029 as amended): uncommitted changes or a lock keep it;
  otherwise it is left in place and the workspace goes. The checkout housekeeping runs in
  gets the same uncommitted-changes guard when the task's branch is checked out there.
- **Exit 3 means "a human must act"** — consolidate, or look at work flagged `wrong-base`;
  1 is a real error, 2 belongs to `task current`. `base-unreleased` needs nobody and does not
  set it. A trigger has to be able to tell those apart.
- **`needs-consolidation` is the expected signal to close a task, not an anomaly**
  (ADR-0030). Every task on a branch other than the base branch reaches `ready:merged` with its knowledge
  decision already recorded, and waits there for a human to close it. A merge never closes
  a task: do not relax the policy to purge `ready:merged`, with or without
  `knowledge_consolidated: true` — the maintainer rejected exactly that. The flag keeps its
  name although only the close may be missing, because `jig status` and `jig measure` read
  it from the log.
- **`--dry-run` has a reader at every session start.** `jig-task` runs it to find the tasks
  flagged `needs-consolidation` and asks the user about each (ADR-0030). That only works
  while the dry run stays free of side effects — no fetch, no log line, no stamp — and its
  per-task stdout line keeps the task id first and the `flags=` field.

## Boundaries

Outside: idea drafts. Housekeeping walks only `.ai/workspace/tasks/` and never touches
`.ai/workspace/ideas/`; a draft leaves only by its spec's ship or a person's drop
(adr-20261110-an-idea-draft-waits-outside-git). What lands in trash as `idea-<id>` is purged by
`trash_ttl` like any entry.

Outside: what a `status` value *means* and who may write it — that is the `task` domain
(ADR-0005, ADR-0012). Housekeeping reads `state` and writes nothing into it, with one exception:
it archives, by calling the task domain's writer (`_task_archive`), which sets `status` and the
three archive keys (adr-20261027-a-task-nobody-finished-is-archived-not-purged). It never writes
`state` itself. It writes the queue only through `jig queue prune`, the queue's own command
(adr-20261107-a-finished-task-leaves-the-queue), never the file. The purge line copies three of the task's fields: they are copied into this
domain's log, never back into the task's file.

**The report on stdout is for people and is not an interface.** It is printed once
every task is decided, grouped by outcome, and may change shape freely. What must not
change is that it can never pass for a log line: the session hook and the scheduler
templates append stdout to the same `housekeeping.log`, so no report line may carry a
`task=` field or begin with `--- run`. The per-task decision lines survive under
`--verbose`, and the tests of merge detection read those.

**The log is no longer only an audit trail.** `jig status` reads the newest `--- run`
block; `jig measure` reads the whole file as the history of tasks whose workspace is gone
(ADR-0027); `jig spec plan` and `jig spec list` read `remote=merged` from the newest block to
tell which tasks merged. Its line shape is an interface with three consumers now. A reader of
the newest block never reads the file: `hklog_last_run_lines` in `scripts/lib/hklog.sh` finds
the last marker's byte offset with `grep -b` and cuts there with `tail -c`. One run of a session
hook out of file descriptors once left 55 000 error lines in a log, 8.8 MB, and every reader that
read it whole paid a third of a second for it. So the log is also bounded: every non-dry run,
under its lock and before its own marker, trims it (`_hk_log_trim`) to the 10 runs before it, and
in each of them to every record (the marker, lines that start with a UTC time) plus at most
200 other lines — the report and whatever stderr the hook appended — then one `housekeeping: log
trimmed: <n> more lines …` note. From older runs only the `action=purge` lines stay, at the top
in their order, which is why `jig measure` may still read the whole file: the history it reads
is never trimmed; it alone still grows, by one line per purged task. A new reader of anything
older than the newest run, or of a line that is not a record, has to change this trim first.
The file is rewritten in place, never renamed over, because the hook and the schedulers hold
it open for appending. The one
free-form field is `ignored=` on a worktree removal, which lists paths: it comes last and
carries no space, so a `key=value` reader that stops at the first space never meets it.
The status page reads the newest block too — `remote=open` for pull requests waiting on a person,
the flags for its cards — and the marker's `forge=github|gitlab|none|failed` field to say whether
that data can be trusted: `failed` means the forge did not answer this run, so no `open` was seen
(adr-20260924-the-status-page-keeps-the-readers-place). A flag here is where one of its cards
starts, never where it ends: the page drops a flag a fact on its own disk disproves before any
card is built, so this run's `needs-consolidation`, `abandoned?` or `worktree-kept` reaches the
reader only while the task is still open and the worktree still there (`hklog_flagged_ids` in
`scripts/lib/hklog.sh`, domains/task). `jig task list --json` reports the same surviving flags per
task, with the marker's time and forge as `housekeeping` (schemas/json.md), so renaming a flag or
reshaping a line changes that contract too. Nothing in this domain changes for it — the decisions, the flag names and the
line shape are what they were; the flag is simply not carried past the fact that answered it.
A non-dry run ends by redrawing the
page in full when it exists (`jig_status_page_touch --full`), which also refreshes the counts the
page's cheaper redraws reuse; that never changes the run's output or exit code.

Outside: which config file a runtime keeps its hooks in and what shape it has — that
belongs to the adapter (ADR-0024). This domain owns the hook *script*, not the runtime's
configuration.

Outside: installing `templates/scheduler/` — the `install` domain places it like any
other framework-owned tree. This domain only writes what goes in it.

The framework does not implement a scheduler (RULES.md, Scope invariants), and no script here ever calls
an LLM (ADR-0001).

## Entry points

- `scripts/lib/housekeeping.sh` — `cmd_housekeeping`, `housekeeping_decide` (the policy),
  `_hk_remote_state` and its tiers, `_hk_purge`, `_hk_trash_expire`, `_hk_task_facts`,
  `_hk_worktree_retire` (with `jig_worktree_leftover` in common.sh), `_hk_branch_sweep` (with
  `jig_branch_leave` and `jig_branch_is_jigs` in common.sh), `_hk_record` and `_hk_print_report` (the grouped report),
  `_hk_unknown_reason`, `_hk_released`.
- `scripts/jig-session-hook` — the trigger; always exits 0, by design.
- `tests/housekeeping.t.sh`; `fixture_merge_repo` in `tests/lib/assert.sh` builds the six
  merge topologies (fast-forward, merge commit, squash, rebase, open, deleted branch).

## Known gap

The GitLab tier has no test: `glab` was not available when it was written, and its
output is parsed with `sed` and `awk` rather than a JSON reader (ADR-0002); each field is
taken at its first occurrence, because nested objects carry a `state` of their own. Its failure direction
is safe — it falls through to ancestry and never fabricates `merged` — but it is
unverified against a real `glab`.
