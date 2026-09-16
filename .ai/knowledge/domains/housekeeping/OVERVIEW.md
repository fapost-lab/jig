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
reviewed_at: 2026-09-16
---
# Housekeeping

Ending a task's life without a developer and without an LLM. The domain is small, and
almost all of its difficulty is in one property: it deletes things, unattended, on
evidence it inferred itself.

## Responsibility

- Deriving **Remote State** per task, in tiers: forge (`gh`/`glab`) → git ancestry →
  `unknown`. Derived every run, never written into a task's `state` (ADR-0005).
- Applying the lifecycle policy — a pure function of `status`, remote state,
  `paused` and age, which is why the whole table is testable without a repository.
- The two-stage **Purge**: move to **Trash**, delete only after `trash_ttl` (ADR-0006).
- The audit trail: `.ai/runtime/housekeeping.log`, one line per decision including
  `via=` (the deciding tier), and the `.ai/runtime/last-housekeeping` stamp. A **purge**
  line additionally carries the task's own `class=`, `created=` and `consolidated=`
  (`_hk_task_facts`), read before the workspace moves: the purge is the last moment those
  facts exist anywhere (ADR-0027).
- The **Session Hook** and the scheduler examples — triggers, both optional, neither
  installed automatically (ADR-0024).
- Removing a **Task Worktree** when the task's workspace is purged (ADR-0029). This is the
  one deletion outside `.ai/`, and git performs it: `git worktree remove`, never with
  `--force`. A worktree that has to stay keeps the workspace with it, flagged
  `worktree-kept`, and `jig status` counts it. When git succeeds but the directory remains —
  Windows leaves the Directory Links in it — only links and empty directories are removed
  there; anything else is reason `leftover` (ADR-0037).

## What governs it

Read these before changing anything here; each is a rule someone paid for.

- **Nothing is destroyed on `unknown`** (RULES.md). Every uncertainty in this
  domain must resolve *towards* `unknown`, never away from it.
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
- **A worktree goes only with its workspace, and only through git** (RULES.md,
  ADR-0029). It must be listed with the task's branch, lie under `git.worktree_root`,
  hold nothing under `.ai/workspace/tasks/` but links, and be clean. `git worktree remove`
  deletes *ignored* files without asking, so the no-workspace-of-its-own check carries the
  whole weight for anything gitignored. Inside a worktree, housekeeping never sees the
  borrowed workspace: it finds workspaces with `find`, which does not follow links. Keep
  it that way.
- **A worktree jig did not create is never removed, and holds the workspace only while
  work waits there** (ADR-0029 as amended): uncommitted changes or a lock keep it;
  otherwise it is left in place and the workspace goes. The checkout housekeeping runs in
  gets the same uncommitted-changes guard when the task's branch is checked out there.
- **Exit 3 means "a human must consolidate"**; 1 is a real error, 2 belongs to
  `task current`. A trigger has to be able to tell those apart.
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

Outside: what a `status` value *means* and who may write it — that is the `task` domain
(ADR-0005, ADR-0012). Housekeeping only reads `state`, and writes nothing into it. That
still holds now that the purge line copies three of its fields: they are copied into this
domain's log, never back into the task's file.

**The report on stdout is for people and is not an interface.** It is printed once
every task is decided, grouped by outcome, and may change shape freely. What must not
change is that it can never pass for a log line: the session hook and the scheduler
templates append stdout to the same `housekeeping.log`, so no report line may carry a
`task=` field or begin with `--- run`. The per-task decision lines survive under
`--verbose`, and the tests of merge detection read those.

**The log is no longer only an audit trail.** `jig status` reads the newest `--- run`
block; `jig measure` reads the whole file as the history of tasks whose workspace is gone
(ADR-0027). Its line shape is an interface with two consumers now, and nothing rotates it.

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
  `_hk_worktree_retire` and `_hk_worktree_leftover`, `_hk_record` and `_hk_print_report` (the grouped report),
  `_hk_unknown_reason`.
- `scripts/jig-session-hook` — the trigger; always exits 0, by design.
- `tests/housekeeping.t.sh`; `fixture_merge_repo` in `tests/lib/assert.sh` builds the six
  merge topologies (fast-forward, merge commit, squash, rebase, open, deleted branch).

## Known gap

The GitLab tier has no test: `glab` was not available when it was written, and its
output is parsed with `sed` rather than a JSON reader (ADR-0002). Its failure direction
is safe — it falls through to ancestry and never fabricates `merged` — but it is
unverified against a real `glab`.
