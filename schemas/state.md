# Task state file

`.ai/workspace/tasks/<task-id>/state`, flat `key: value` lines, one per key, no nesting.
Reference: ADR-0005, ADR-0008. Written only through `jig task`, atomically
(temp file then `mv`), last-write-wins.

| Key | Writer | Values |
|---|---|---|
| `task_id` | `jig task new` | `^[A-Za-z0-9][A-Za-z0-9._-]*$` (no leading dot, so `.`, `..` and hidden names are impossible); every `jig task` subcommand validates the id before touching the filesystem |
| `branch` | `jig task start` | the branch the task was started on. **Absent means the task has not been started** — it is listed as `not-started` and never becomes a `task current` candidate. Present *without* `base_commit` means an older `task new` recorded the checkout's branch at filing; `task start` treats such a task as unstarted and rewrites both keys |
| `base_commit` | `jig task start` | 40-hex commit the task's branch forked from, resolved when work began rather than when the task was filed. Absent while the task is unstarted, and in workspaces predating the field. Housekeeping treats an absent fork point as "ask the old question", so such a task is also without the protection the field provides |
| `base_branch` | `jig task start` | the branch the task was cut from and has to land on: `git.base_branch`, or the open epic of the spec the task links to (ADR-0039, ADR-0040). Checked with `git check-ref-format --branch` before it is written. Absent while the task is unstarted and in workspaces predating the field; every reader then uses `git.base_branch` (`jig_task_base`) |
| `class` | skill via `jig task set` | `T0` … `T4` |
| `status` | skills via `jig task set` | `active`, `ready`, `consolidated`, `abandoned`. `consolidated` means the task is **closed**: written by `jig-consolidate` after the task's change has landed, or at the end of the route for a task whose landing cannot be observed — no `branch`, or `branch` equal to the base branch (ADR-0030) |
| `knowledge_consolidated` | `jig-consolidate` skill via `jig task set` | `true`, `false`. `true` means the knowledge decision is recorded — `NO_DURABLE_KNOWLEDGE` included — at the end of every route, before the commit (ADR-0030) |
| `autopilot` | `jig task autopilot` | `on`, `stopped`, `done`; absent when the task never ran on autopilot. `task set` refuses it (adr-20260921-autopilot-runs-a-task-to-its-stops) |
| `autopilot_repairs` | `jig task autopilot` | repairs used in the current run, `0`–`2`; `repair` refuses a third with exit 3 and sets `autopilot: stopped`; `resume` resets it to `0`. `task set` refuses it |
| `autopilot_mode` | `jig task autopilot <id> start` | `attended` or `unattended`, read once from `autopilot.unattended` when the run starts and kept through `resume`, so changing the key mid-run changes nothing; `approve`, `decide` and `task gate --by agent` require `unattended`. Absent for a run started before modes existed, read as `attended`. `task set` refuses it (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci) |
| `autopilot_phase` | `jig task autopilot <id> start --phase` | `<spec-id>/<n>`: this run is one task of that roadmap phase's run, started by a coordinator who owns the spec and ships the task itself. `jig spec done` refuses in the task's own branch, and the status page sends the person to the coordinator's session instead of this task's. Absent for every other run, and never cleared — it is what the run was. `task set` refuses it (adr-20260922-a-phase-run-is-coordinated) |
| `gate` | `jig task gate <id> approved` | `approved`; absent until a human approved the T3/T4 design at its gate. The decision in words stays in `task.md` (ADR-0031); this key is what the scripts and the status page can read. `task set` refuses it (adr-20260922-the-status-page-stays-current-without-a-server) |
| `gate_design` | `jig task gate` | the hash of the approved design — the same value a review receipt's `design` pins (`design.md`, and for T4 `spec.md` and `alternatives.md`). A different current hash means the design changed after its approval. `task set` refuses it |
| `gate_by` | `jig task gate` | `human`, or `agent` for the self-approval of an unattended run (`--by agent`, refused unless the task's autopilot run is `on` and `unattended`). Absent on an approval recorded before it existed, read as `human`. `task set` refuses it (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci) |
| `pr_url` | `jig task ship` | the `https://` address of the pull request `ship` opened or found open. A fact about what `ship` did, not a merge state: whether it was merged is still derived by housekeeping every run (ADR-0005). `task set` refuses it |
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
Two values are refused on top of validation, to keep the order of ADR-0030: `status
consolidated` while `knowledge_consolidated` is not `true`, and `knowledge_consolidated
false` on a task whose status is `consolidated`.

Pause is orthogonal to `status`: a task paused while `ready` resumes as `ready`. A task
is a candidate for `jig task current` when its `branch` matches the checkout, its status
is `active` or `ready`, and `paused` is absent.

Remote merge state (`merged`, `open`, `closed`, `unknown`) is never written here; it is
derived by housekeeping on each run.

Every write through `jig task` — this file, the autopilot journal, the findings ledger, the
receipt — redraws the status page at the end of the command, once the page exists
(`jig_status_page_touch`, adr-20260922-the-status-page-stays-current-without-a-server).

`jig task list` shows only live tasks (`active`, `ready`, paused included) unless
`--all` or `--status <s>` is given; `consolidated` and `abandoned` accumulate on a
long-lived branch and would otherwise crowd out the work in flight.

## Workspace files

| File | Created by | Purpose |
|---|---|---|
| `state` | `jig task new` | this file |
| `task.md` | `jig task new`, from `templates/task.md` or from `--from <file>` | goal, scope, notes; context also lists existing known artifacts |
| `findings` | `jig task finding add` | the review findings ledger: one tab-separated line per finding — `F<n>`, severity `P0`–`P3`, status `open`/`fixed`/`closed`/`dismissed`, where (`path[:line]` or `-`), summary, date of the last change, dismissal reason (empty otherwise). Changed only by `jig task finding add\|set`, written atomically. A P0 or P1 in `open` or `fixed` refuses `status ready`, `knowledge_consolidated true` and `task ship` (adr-20260921-review-findings-block-completion) |
| `receipt` | `jig task receipt <id> --stage review\|architecture-review` | what the last review saw, flat `key: value`: `stage`, `reviewed_at`, `tree` (git tree id of the working tree without `.ai/knowledge/` and `.ai/specs/`, built in a temporary index), `base_commit`, `head`, `design` (hash of `design.md`; for T4 also `spec.md`, `alternatives.md`), `findings` (hash of the ledger); `-` for an absent file. Rewritten by each re-review. When `tree`, `design` or `findings` no longer match, or a T4 task has none, `status ready`, `knowledge_consolidated true` and `task ship` refuse (adr-20260921-review-receipt-pins-what-was-reviewed) |
| `autopilot` | `jig task autopilot <id> start` | the run's journal: one tab-separated line per event — UTC time, `start`/`stage`/`repair`/`stop`/`resume`/`approve`/`decide`/`end`, a one-line text (`start` carries the mode; `approve` and `decide` are what an unattended run did instead of stopping, printed by `report` as the "Approved by the agent, not a human" and "Decided without you" blocks). Read back by `jig task autopilot <id> report` and, as data, by `_task_autopilot_facts` for the status page |
| `discovery.md`, `spec.md`, `alternatives.md`, `design.md`, `plan.md`, `review.md`, `verification.md`, `handoff.md` | skills, when the task class calls for them, through `jig task artifact write\|append` | stage artifacts (domains/task) |

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
consume spec+design. Every class ends with consolidation (ADR-0030): T3/T4 consolidation
consumes verification, T2 consolidation consumes plan, and T0/T1 consolidation has no
additional input. All stages also consume task.md; T0 has no additional documentary
prerequisite.

Stage rows report inputs-available/needs-input, with semantic prerequisites separately
unassessed. Missing optional artifacts do not block unrelated stages. Exit 0 means the
report succeeded, even with missing inputs; invalid invocation/inspection exits 1.
Neither presence nor a provided claim proves approval, content quality or completion.
No state fields or transitions are added. Workspace-free T0/T1 need not call the command.

## Artifact writes

`jig task artifact write|append <id> <kind> [--from <file>|-]` writes `<kind>.md` in the
task's workspace: `write` replaces the document, `append` adds to it and creates it when
absent, inserting a newline first when the existing document does not end in one. Content
comes from `--from <file>`, or from stdin when `--from` is `-` or absent.

`<kind>` is one of nine — `task`, `discovery`, `spec`, `alternatives`, `design`, `plan`,
`review`, `verification`, `handoff` — one wider than the `--provided` vocabulary above,
which has no use for `task`. An unknown kind is refused rather than written, so a misspelt
name cannot become a file the report above never looks at.

The write is atomic (temporary file, then `mv`), it refreshes `updated_at` and redraws the
status page, and empty input is refused with the document left as it was: a `write` fed the
output of a command that failed would otherwise blank it.

The workspace is resolved the same way `jig task artifacts` resolves it, so the command is
how an agent in a Task Worktree writes an artifact without knowing that its workspace is
reached through a link (ADR-0029). It prints the path written — absolute when the workspace
is borrowed, since it is then in another worktree. No `{{TASK_ID}}` substitution happens:
that belongs to `jig task new --from`, which seeds a template rather than storing a
finished document.

## Review scope (ADR-0022)

`jig task changes <id> --base <ref> [--files <a,b|->] [--format report|paths]` requires an
explicit commit base and inventories committed, staged, unstaged and untracked layers
separately. The report includes resolved base/HEAD, path layers and excluded candidate
count; paths format prints their sorted union only. Paths are literal repository-relative
file names; stdin permits spaces/commas, explicit empty scope stays empty, and dot segments,
absolute names and tab/newline names fail. Git failures do not become empty success.

The base and ownership evidence live in task artifacts, not state. Mixed files still need
hunk ownership evidence and actual patch inspection; inventory is not a review verdict.

## Where a task is checked out

No key records it. A task started with `jig task start --worktree` has its `branch`
checked out in a Task Worktree, and `git worktree list` says where; `task list` and
`jig status` derive `worktree=<path> uncommitted=<n>` from that on every call (ADR-0029).
The worktree reaches this file through a link to the workspace, so the state file itself
exists once, in the checkout where the task was filed.

## Key order

`jig task new` writes `task_id`, `class`, `status`, `knowledge_consolidated`, `domains`,
`created_at`, `updated_at` — the keys it knows at filing time. `jig task start` inserts
`branch`, `base_commit` and `base_branch` before `created_at`, the same place `jig task set` inserts a
key it is adding for the first time. The order is stable, not canonical: nothing reads
this file positionally.
