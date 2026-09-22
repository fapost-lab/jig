---
id: domain-task
type: domain
status: active
summary: "The two seams the task ADRs do not describe: the ledger belongs to knowledge, and class is a field not a judgement."
domains:
  - task
topics: []
load: domain
paths:
  - scripts/lib/task.sh
  - scripts/lib/status.sh
  - schemas/state.md
  - templates/task.md
reviewed_at: 2026-09-22
---
# Task

The local lifecycle of a unit of work. What the lifecycle *is* — the workspace, the state
file, pause and resume — is settled by ADR-0005, ADR-0008 and ADR-0012 and is not restated
here. This document exists for the two seams those ADRs do not describe, because neither
of them is visible from inside this domain's own code.

## Boundaries

**The context ledger lives here and belongs to `knowledge`.** The file sits in the task
workspace, and this domain supplies the task id and the directory it goes in — but it does
not interpret a single line of it. A change to what an acknowledgement means is a
`knowledge` change that happens to touch `.ai/workspace/`.

**`class` is a field here, not a judgement.** Storing and validating `T0`–`T4` is this
domain's job; deciding which one a piece of work deserves belongs to the `jig-task` skill
and its rubric (ADR-0009). Nothing in `task.sh` may start inferring a class, and no rule
about *how* to classify belongs in this domain's documents.

**Artifact inputs and review inventory are facts, not lifecycle.** `task artifacts`
reports fixed-route information dependencies without assessing approval or completion
(ADR-0020). `task changes` requires an explicit base and inventories all Git layers;
the agent establishes task/hunk ownership and reads patches (ADR-0022). Neither command
changes task state or decides the next stage.

## Where this domain ends

`jig housekeeping` reads this domain's `state` files and never writes them (ADR-0005).
It now also copies `class`, `created_at` and `knowledge_consolidated` onto its purge line,
so `jig measure` can count a task whose workspace no longer exists (ADR-0027). Renaming a
field here therefore empties a column in a report two domains away, silently — the
copy is by key, and an absent key is read as unknown rather than as an error.
It has its own domain — see `domains/housekeeping/` — and the split is worth stating,
because the two are easy to confuse: **`status` is local progress, owned here; remote
merge state is derived there, every run, and stored nowhere.**

`jig spec remove` is a third reader: it reads `status`, `branch` and `base_commit` to decide which
linked tasks it may abandon, and abandons them through `jig task abandon`, never by writing `state`
(ADR-0035). A renamed `branch` or `base_commit` would make every task look not started, so
`--abandon-unstarted` would abandon started work; a renamed `status` would let it touch closed
tasks. Rename a field here and `spec.sh` changes with it.

**The two consolidation fields are two moments, and `task set` keeps their order**
(ADR-0030). `knowledge_consolidated: true` is written at the end of every route, before the
commit; `status: consolidated` closes the task after its change has landed, prompted by
housekeeping's `needs-consolidation`. `task set` refuses the status while the flag is not
`true`, and refuses `false` on a closed task. Apart from the findings gates below, this is the
only cross-key rule in `task_set`: every other key is validated on its own value alone.

One consequence lands squarely on this domain, and ADR-0026 is the answer to it.
Housekeeping can only establish that work landed when the task had a branch of its own: a
task whose `branch` is the base branch resolves to `unknown` forever (ADR-0025). So a task
gets a branch of its own — but at `jig task start`, not at `jig task new`.

**Filing and beginning are different acts**, and the distinction is carried by an absence:

- A filed task has **no `branch` and no `base_commit`**. That absence is what keeps it out
  of `_task_candidates_for_branch`, so it is never an ambiguous `task current` candidate
  and needs no pause to stay out of the way. `task list` shows it as `not-started`.
- `jig task start` writes both. It is the only command that may write `branch` after
  creation; `task set` still refuses every script-owned key, so ADR-0008's invariant is
  intact.
- `base_commit` is resolved when work begins rather than when the task is filed, because a
  fork point recorded weeks earlier is false by the time anything reads it. A task without
  one — legacy or unstarted — is one housekeeping must judge the old, weaker way.
- `paused` means "was being worked on, set aside". It is not the way to say "not begun";
  that is what the missing `branch` says.

**Where a task is cut from is recorded too** (ADR-0039, ADR-0040). `task start` writes
`base_branch`: the default branch, or the open epic of the spec its `task.md` links to. It fetches
first and refuses, rather than falling back to the default branch, when the spec is not in this
checkout, the epic exists nowhere, or the epic is finished. Every judgement against a base —
housekeeping, `task resume`, touched files for `context` and `knowledge paths` — reads it through
`jig_task_base`; renaming it sends every epic task back to `main` in all of them at once.

**Where a started task runs is a second, independent choice** (ADR-0029). `task start`
checks the branch out here. `task start --worktree` checks it out in a Task Worktree beside
the repository, for when this checkout is busy with other uncommitted work — the case the
dirty-tree refusal now names as its other road. Three things about it are easy to get
wrong from inside this domain's code:

- The workspace never moves. The worktree gets a link to it, so everything that reads a
  workspace works there unchanged, and the filing checkout keeps listing every task.
  Nothing may delete or move a workspace through that link. `task artifacts`, which
  refuses links, accepts exactly this one.
- Which worktree a task is in is *derived* from `git worktree list` on every call, never
  stored. `task list` and `jig status` print it with the count of uncommitted files there:
  at `agent.git: none` that count is the human's review queue; at a higher level it is still a
  fact worth showing, and the queue is what `jig status`'s `agent.git:` line names.
- A task in a worktree is not `task current` in the filing checkout: its branch is checked
  out elsewhere, and ADR-0008's branch match is what decides.

**`task ship` is the one command here that commits, pushes or opens a pull request**
(adr-20260921-agent-git-rights-are-a-local-setting). It reads three things other parts of this
domain own — `knowledge_consolidated`, `branch` and the task base through `jig_task_base` — and
refuses on each before it touches git, so a renamed field turns into a refusal, not a commit on
the wrong branch. How far it goes is `agent.git`, a local-only key of the config layer; the
forge it opens the pull request on is resolved by `jig_forge_kind` in `common.sh`, the same answer
housekeeping reads PR state from.

**The findings ledger is this domain's, and it adds two cross-key rules to `task set`**
(adr-20260921-review-findings-block-completion). `status ready` and `knowledge_consolidated true`
refuse while `_task_blocking_findings` answers — a P0 or P1 in `open` or `fixed` — and `task ship`
asks the same function again, since a fix after consolidation can add a finding. That function is
the single definition of "blocking": `jig status` prints its count as `blocking=<n>` by calling it,
never by reading the file. The ledger records claims (ADR-0020): the script cannot tell a reviewer
from the author, so who may close or dismiss a finding is a rule of the skills
(`skills/jig-review/references/findings.md`), not of this code.

**The status page shows this domain's answers verbatim, and this domain keeps it current**
(adr-20260922-the-status-page-stays-current-without-a-server). The page lists each live task with the
lines `_task_blocking_findings` prints, the line `task_receipt_check` prints (`current`, `stale (…)`,
`none`, `none (required for T4)`), `_task_worktree_note` and the task base; an autopilot run as
`_task_autopilot_facts` gives it (state, repairs, last stage and its time, last stop and its time —
the same producer `autopilot report` summarises); and a T3/T4 design as `_task_gate_state` answers
(`waiting`, `changed`, `approved`). Those strings are read by a person on the page as well as by the
gates: change one and the page and its tests change with it. `status.sh` reads every `state` in one
awk pass (`_status_task_rows`), so a renamed key empties a column there too.

Every writer here — `_task_rewrite_state`, `_task_rewrite_state_remove`, `task new`'s state, the
autopilot journal, the findings ledger, the receipt — calls `jig_status_page_dirty`, and `cmd_task`
redraws the page once at its end. An exit that skips that end after a write must flush first:
`jig_die` does, and so does the third repair's `return 3`. A new writer that does not mark, or a new
early exit that does not flush, leaves the page a command behind.

Two keys record facts only this domain's commands know, both refused by `task set`: `gate` and
`gate_design`, written by `jig task gate <id> approved` — the human's approval of a T3/T4 design as
data, pinned by the same hash a review receipt uses, so a design changed after approval is visible —
and `pr_url`, written by `task ship` when it opened or found a pull request. `pr_url` is what ship
did, not a merge state: ADR-0005 still holds, and housekeeping still derives whether it merged.

**The review receipt stands on the same three gates** (adr-20260921-review-receipt-pins-what-was-reviewed).
After the findings check, each gate asks one staleness function whether the working tree, the
approved design or the ledger moved since the receipt, and a T4 task must have one. The tree is
content, built in a temporary index, never the real one, and it leaves out `.ai/knowledge/` and
`.ai/specs/` because consolidation writes them after review. A new path that consolidation starts
writing must join that exclusion, or every task will read as unreviewed at its last step.

**An autopilot run is recorded here, but driven by a skill** (adr-20260921-autopilot-runs-a-task-to-its-stops).
`jig task autopilot` owns two state keys, `autopilot` and `autopilot_repairs`, which `task set`
refuses like every other script-owned key, and a journal file in the workspace. The only rule it
enforces is the repair limit — two per run, a third refused with exit 3 and the run `stopped`; every
other stop is `jig-autopilot`'s to take. A run changes none of the completion gates: a task on
autopilot meets the same findings and receipt checks as any other.

