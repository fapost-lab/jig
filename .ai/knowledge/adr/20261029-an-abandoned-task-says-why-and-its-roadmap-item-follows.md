---
id: adr-20261029-an-abandoned-task-says-why-and-its-roadmap-item-follows
type: adr
status: accepted
date: 2026-10-29
domains:
  - task
  - spec
paths:
  - scripts/lib/task.sh
  - scripts/lib/spec.sh
  - schemas/spec.md
  - schemas/state.md
summary: Why jig task abandon takes --reason and --moved-to, how jig spec drop closes the roadmap item that names an abandoned task, how it counts, and why a phase run leaves it to the coordinator.
---
# ADR: An abandoned or moved task says why, and the roadmap item that names it is closed with the reason

## Context

On 2026-10-28 the owner of fapost-core decided that Sentry lives in the monitoring package. The task
`sentry-error-reporting` in `packages/fapost-saas` was set to `abandoned` and got a `## Moved` note in
its `task.md`; the code went to fapost-monitoring and the pull request was closed. But the
`saas-production` spec's roadmap in SaaS still said Sentry was that task, in that repository. The next
agent read the spec and started editing SaaS. The decision existed only in a gitignored file on one
machine; the committed plan every agent reads kept saying the opposite.

`jig task abandon <id>` took only an id: no reason, no target, no look at the roadmap. `jig task set
<id> status abandoned` did the same. Nothing tied the end of a task to the plan that named it, while
the other end of a task — `jig spec done` at the knowledge decision — has checked the item since
ADR-0035.

Two neighbouring decisions shape the answer. A neighbouring repository's task or spec is named
`<repo>#<task-id>` or `<repo>#spec/<spec-id>`, parsed once by `jig_task_ref`, and Jig only reads the
neighbour (adr-20261029-a-task-reads-a-neighbouring-repository-through-a-link). In a phase run the spec
has one writer, the coordinator, and `spec done` refuses in a task's branch
(adr-20260922-a-phase-run-is-coordinated).

## Decision

**`jig task abandon <id> [--reason <text>] [--moved-to <ref>]` records why in the task's `state`,
and for a task linked to a spec runs `jig spec drop <id>`, which closes the roadmap item that names
the task with the reason in its text.**

- **A move is an abandon with a target, not a status.** `state` gets `abandoned_at`, `abandoned_reason`
  and `moved_to`, all script-owned. `--moved-to` is parsed by `jig_task_ref`; it need not be
  reachable. When the target is not there, the command that files it there is printed; the other
  repository is never written. A second abandon refines the record; an abandon without `--moved-to`
  removes an old target. Leaving `abandoned` for `active` or `ready` removes the three keys.
- **A task with a `Spec:` line must give a reason**, and `jig task set <id> status abandoned` refuses
  it, naming `jig task abandon`: the bypass is how the roadmap went stale. A task with no link may
  still be abandoned bare, so the actions table's `jig task abandon <id>` and every existing caller
  keep working; the table offers `jig task abandon <id> --reason <text>` for a linked task, and
  `spec remove --abandon-unstarted` passes `--reason "spec <id> removed"`. A `task.md` linking two
  specs counts as linked.
- **`jig spec drop <task-id>`** — beside `spec done`, by its pattern — reads the reason, day and target
  from `state` (read only), and turns each unchecked item that names the task into `[x]` with
  ` — moved to <ref> (<day>): <reason>` or ` — dropped (<day>): <reason>` after the item's last line.
  The suffix opens with a dash between spaces, where a wave entry's title ends, so a wave still names
  the item. It refuses a live task, and refuses with exit 3 in a phase run's task branch through the
  same function as `spec done`; there `task abandon` still succeeds and says the coordinator closes the
  item, with `jig spec drop` in the epic checkout after the merge. No item naming the task, one
  already closed, or a spec with no roadmap here, is not an error.
- **A closed item is an `[x]`**: done in `spec_phase_counts`, `spec list` and the status page,
  `merged=roadmap` in `spec plan`, closed for `roadmap complete`, the leftovers, `spec close`,
  `spec epic --finish` and the final ship. The why is in the item's text, which `spec list --json`
  carries as written. No count, TSV column or JSON field changes.
- **Until it is closed, an abandoned task's item is not done.** `spec_merged_task_ids` does not learn
  `abandoned`: the item stays `filed`, `spec plan` shows it `abandoned` and holds its wave, and the
  lifecycle refuses to close the spec over it. The lie cannot outlive the spec.
- **The edit is made where jig edits a spec, and never on the default branch.** This is the rule of
  adr-20260930-a-spec-lives-on-its-own-branch-from-the-first-minute applied to one more edit, not an
  exception to it:
  - *A spec with an open epic* is edited on the epic, whose copy of the roadmap is the current one,
    whatever base the task recorded. `spec drop` runs only in a checkout of it and asks for a commit
    there, the way a phase run's coordinator commits its checkmarks
    (adr-20260922-a-phase-run-is-coordinated).
  - *A spec without one*, whose task belongs on the default branch, is edited on `spec/<sid>`. On
    `spec/<sid>` the edit is made in place. On the default branch `spec drop` does what
    `jig spec resume` does — refuses a dirty tree by `task start`'s rule, then switches to the existing
    `spec/<sid>` (here or on origin) or cuts it — after first checking that an item is left to close, so
    a no-op never moves HEAD. HEAD stays on `spec/<sid>`, as after `spec resume`. A `spec/<sid>` from
    an earlier session that does not name the task, while the default branch does, closes nothing:
    `spec drop` switches back and exits 3, naming the merge of the default branch to make first.
  - On `spec/<sid>` the edit is committed there, locally, as a commit of `roadmap.md` alone (hooks run),
    so that neither the default branch nor the tree holds it and the next `task start` is not refused.
    Not at git level `none` (`agent.git`, or the run's level in an unattended clone, as `spec ship`
    reads it), where committing is the person's, and not when `roadmap.md` already held uncommitted
    changes, which belong to a `jig-idea` session on that branch and leave with its `spec ship`. Push
    and the pull request stay with `jig spec ship <sid>`, which `spec drop` names.
  - Anywhere else — the task's own branch, which never ships, a task worktree, any other branch —
    `spec drop` exits 3 and names where to run it; `task abandon` still succeeds and the item waits,
    unclosed and visible (above).
  - `spec remove --abandon-unstarted` rewrites nothing and switches nothing: the roadmap leaves with
    the spec, and a branch switch in the middle of that command would split it in two. It tells
    `spec drop` so through `JIG_INTERNAL_SPEC_REMOVING=<sid>`.

## Alternatives

- **A `moved` status.** Every reader of `status` — housekeeping, `queue next`, `spec plan`, the actions
  table, `task list --json` — would have to learn it, for a difference one key already carries.
  Rejected; `moved_to` can become a status later if a reader needs to tell the two apart.
- **Leave the item unchecked and teach the counts a "dropped" mark.** The lifecycle would need the same
  mark in five places, and `spec_phase_counts`' TSV and the JSON shape would change. Rejected for the
  same reason the progress rule kept the lifecycle on checkboxes.
- **Delete the item.** A wave naming it would turn into a `problem` and hold the phase, and the plan
  would lose the record of where the work went — the very thing the next agent needs.
- **Refuse the abandon until the roadmap is rewritten.** In a phase run's task branch the roadmap may
  not be touched at all, so the task could never be abandoned there; the unclosed item already blocks
  the spec's end and is visible in the plan.
- **File the task in the receiving repository.** Jig only reads a neighbour; writing there would be a
  second repository's lifecycle driven from this one.
- **Push and open the pull request for the roadmap edit from `task abandon` itself.** It would make one
  command push and open a pull request at whatever `agent.git` allows, for a step `spec ship` already
  owns. The local commit on `spec/<sid>` is the part that keeps the default branch and the tree clean;
  the rest stays `spec ship`'s.
- **Leave the edit uncommitted on the default branch for `spec ship` to pick up**, as the first version
  of this decision did. It contradicted adr-20260930-a-spec-lives-on-its-own-branch-from-the-first-minute:
  `task start` refused the next task over it, `spec ship` refused it once a `spec/<sid>` existed, and a
  task worktree left it behind for good. The owner chose, on 2026-10-29, that `spec drop` works on
  `spec/<sid>` as `spec resume` does, and that ADR stands unchanged.

## Consequences

- A spec-linked task can no longer be abandoned without a reason, by `task abandon` or by `task set`.
- The roadmap says where a dropped item's work went, in the committed file every agent reads; the
  task's `state` says it too, for `task show`.
- Reopening an abandoned task does not reopen its roadmap item: the person is told to reopen it by hand.
- Abandoning a spec-linked task of a spec without an epic, on the default branch, moves HEAD to
  `spec/<sid>` and, above `agent.git: none`, leaves a local commit there; `jig spec ship <sid>` from
  that branch takes it the rest of the way. At `none` the edit waits uncommitted on `spec/<sid>`, never
  on the default branch, and `task start` names `jig spec ship <sid>` until the person commits it.
- Progress counts a dropped item as done. A count of dropped items, if anyone needs one, can be read
  from the suffix later without changing the grammar.
- Rolling this back removes `spec drop`, two flags and three keys; closed items stay ordinary `[x]`
  lines with text. Nothing migrates.
