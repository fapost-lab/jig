# Jig

Jig is a project-owned framework for agent-driven software development. It gives
Claude Code and Codex shared project knowledge, workflows proportional to risk,
and deterministic shell commands for the mechanics. The agent makes engineering
decisions; scripts never call an LLM.

## Install first

### 1. Make `jig` available from any directory

Jig runs on macOS and Linux with Bash 3.2 or newer, Git, and standard Unix tools.
It needs no Node.js, Python, package manager, or build step. Using its skills also
requires a supported coding runtime. Project verification needs the tools used by
the selected technology profiles.

Clone the framework into a permanent directory, then put its executable on `PATH`:

```sh
mkdir -p "$HOME/.local/share" "$HOME/.local/bin"
git clone https://github.com/fapost-lab/jig.git "$HOME/.local/share/jig"
ln -s "$HOME/.local/share/jig/scripts/jig" "$HOME/.local/bin/jig"
export PATH="$HOME/.local/bin:$PATH"
jig version
```

Repository access may require authentication. If you already have a clone, use its
absolute path as the symlink target instead of cloning again:

```sh
mkdir -p "$HOME/.local/bin"
ln -s /absolute/path/to/jig/scripts/jig "$HOME/.local/bin/jig"
```

Keep the whole checkout: the executable loads adjacent libraries, skills, adapters
and templates. If `~/.local/bin/jig` already exists, inspect it before replacing it.

For future terminals, add this line once to `~/.zshrc` (zsh, the macOS default) or
`~/.bashrc` (interactive bash). A bash login shell must also load that file:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Open a new terminal and check `command -v jig`. This is a per-user global command;
it needs no `sudo`. `jig version` and `jig help` work anywhere. Project commands
operate on the Git repository containing your current directory, including when
you are in one of its subdirectories. They do not operate on every project at once.

### 2. Install Jig into a project

```sh
cd /path/to/your/project
# For a new directory that is not a Git repository yet:
git init
jig init
```

Default installation activates the `generic` profile and both `claude` and `codex`
adapters. Select a runtime and stack explicitly when needed:

```sh
jig init --adapters codex --profiles php
# Or, for a Laravel project using both runtimes:
jig init --adapters claude,codex --profiles laravel
```

`generic` stays active; Laravel also requires PHP. Detected profiles are suggested,
not silently enabled. `init` is non-interactive. Re-running it preserves existing
knowledge and modified files; explicit profile/adapter flags update those selections
in `.ai/config.yaml`. Read any conflict report and inspect the resulting diff.
Existing `AGENTS.md` or `CLAUDE.md` may need the Jig instructions merged by hand.

Without a global command, use an absolute path to the source executable:

```sh
/path/to/jig/scripts/jig init
```

### 3. Populate project knowledge

`jig init` installs files and starter documents. The **`jig-init` skill** asks the
agent to study the project and populate its glossary, architecture and rules.
Invoke skills in your coding runtime's conversation, not in the terminal:

| Runtime | Example message |
|---|---|
| Claude Code | `/jig-init` |
| Codex | `$jig-init` |

Then inspect the knowledge and validate it:

```sh
.ai/scripts/jig knowledge check
git status --short
```

Review and commit the installed framework files and project knowledge so teammates
get the same environment when they clone. Task workspaces and runtime reports are
gitignored. A teammate can run `.ai/scripts/jig` without a global installation.

For a larger project, invoke `jig-map` next to propose domain knowledge, then
`jig-accept` to decide the proposals with a human.

## Contents

- [What Jig provides](#what-jig-provides)
- [How Jig differs from adjacent frameworks](#how-jig-differs-from-adjacent-frameworks)
- [Skills and responsibilities](#skills-and-responsibilities)
- [Task workflows](#task-workflows)
- [Knowledge workflows](#knowledge-workflows)
- [Verify with profiles](#verify-with-profiles)
- [Upgrade the framework and a project](#upgrade-the-framework-and-a-project)
- [Phase 5: lifecycle automation](#phase-5-lifecycle-automation)
- [Project layout and configuration](#project-layout-and-configuration)
- [Roadmap and Phase 6](#roadmap-and-phase-6)
- [Troubleshooting and framework development](#troubleshooting-and-framework-development)

## What Jig provides

- **Durable knowledge:** shared terms, architecture, rules, features and decisions
  under `.ai/knowledge/`, tracked with the code.
- **Adaptive SDLC:** a small edit gets a short route; architectural or critical work
  gets design, a human gate and stronger review.
- **Task workspaces:** temporary plans, specifications and evidence stay local under
  `.ai/workspace/tasks/<id>/`.
- **Context selection:** commands resolve relevant knowledge by files, domains,
  topics and stage; a catalog makes additional documents discoverable.
- **Verification and consolidation:** checks provide evidence, and the agent decides
  what engineering intent should survive the task.
- **Lifecycle automation:** reconcile workspaces with remote merge state and clean up
  eligible workspaces without an LLM.
- **Measurement:** `jig measure` derives knowledge quality, the spread of task classes
  and the size of the change each class produced — on demand, from evidence that
  already exists, with no stored series and no telemetry.

Jig is not a coding runtime, issue tracker or agent orchestrator. Skills guide an
agent; the command line records state and performs deterministic operations. Running
`jig task new` does not start implementation or launch another agent.

## How Jig differs from adjacent frameworks

Jig's primary unit is the project's engineering lifecycle, not a specification,
prompt collection or agent team. It covers the path from project knowledge and task
classification through implementation, evidence, consolidation and eventual local
workspace cleanup. The framework makes five connected design choices:

1. **Semantic work and mechanics are separate.** The agent analyzes, designs, reviews
   and consolidates through skills. Bash scripts create state, resolve context, run
   checks, upgrade installed files and perform housekeeping without calling an LLM.
   Mechanical operations are testable and have no inference cost.
2. **Process follows risk.** T0 and T1 can finish without a task workspace. T3 and T4
   require an approved design, stronger review and consolidation. A change that is
   small to type but dangerous to undo still takes the higher-risk route.
3. **Knowledge has authority and lifecycle.** Durable knowledge is selected by path,
   domain, topic and stage. Agent-inferred domain knowledge remains `proposed` and
   cannot enter another agent's resolved context until a human accepts it.
4. **Task artifacts are transient.** Plans and investigation notes stay in a local,
   ignored workspace. Consolidation keeps only intent that should outlive the task;
   lifecycle automation can remove the workspace after remote merge evidence.
5. **The process is installed like project code.** Skills, scripts and profiles are
   committed per project. A manifest detects drift and upgrades framework-owned files
   while preserving project knowledge and locally modified files.

### Position among representative tools

These projects overlap with Jig, but optimize for different centers of gravity. This
comparison reflects their public documentation checked on 2026-09-10 and is not a
feature-completeness benchmark.

| Approach | Its documented center of gravity | Practical difference from Jig |
|---|---|---|
| [GitHub Spec Kit](https://github.github.com/spec-kit/) | An extensible, intent-driven process harness whose default is Spec → Plan → Tasks → Implement, with a large integration and extension ecosystem. | Spec Kit is the stronger fit when broad runtime coverage, reusable process extensions or spec-driven artifacts are the priority. Jig currently supports fewer runtimes and concentrates on one opinionated project-local lifecycle: risk classes, knowledge authority, deterministic state and cleanup. |
| [OpenSpec](https://openspec.dev/docs/schemas/spec-driven) | Proposal, behavior delta specs, design and tasks; [archive](https://openspec.dev/docs/quickstart) merges deltas into canonical specs and retains the completed change history. | OpenSpec is the stronger fit when behavioral specifications are the primary source of truth. Jig keeps a broader set of durable engineering knowledge and intentionally lets transient task artifacts disappear after selected intent is consolidated. |
| [BMad Method](https://docs.bmad-method.org/) | An agile AI-driven method with thinking, planning, build and review skills, project context and agent-oriented workflows. | BMad is the stronger fit when rich role-based planning and agent workflows are desired. Jig deliberately does not orchestrate agents; it focuses on runtime-independent skills plus a deterministic, repository-owned control layer. |

Jig is a good fit when a team wants the same process committed with the repository,
cheap handling for routine changes, explicit human gates for costly mistakes,
reviewable knowledge acceptance and shell-level mechanics that can be tested without
an LLM. Its narrower scope is deliberate, but its maturity is also narrower: Claude Code and
Codex are the only supported runtimes in the current MVP, and its measurement stops
where telemetry would begin — the framework can say how much process a change asked
for, never what the agent's work cost.

## Skills and responsibilities

Use `/jig-<name>` in Claude Code or `$jig-<name>` in Codex. You can also describe the
work in plain language and ask the agent to follow Jig. Skills are vendor-neutral;
adapters install them for each runtime.

| Skill | When to use it | Responsibility / result |
|---|---|---|
| [`jig-init`](skills/jig-init/SKILL.md) | First adoption or stale global knowledge | Analyze the project and populate glossary, architecture and rules. |
| [`jig-map`](skills/jig-map/SKILL.md) | Global documents no longer describe the domains adequately | Propose domain boundaries and knowledge packs with evidence; wait for human acceptance. |
| [`jig-accept`](skills/jig-accept/SKILL.md) | Knowledge proposals are waiting | Present proposals, collect human decisions and record acceptance or rejection. |
| [`jig-task`](skills/jig-task/SKILL.md) | Start or resume work | Find the relevant task, classify risk T0–T4 and choose the route. |
| [`jig-analyze`](skills/jig-analyze/SKILL.md) | Before a local or structural change; investigate a problem | Establish cause, affected components, constraints and options. |
| [`jig-implement`](skills/jig-implement/SKILL.md) | After analysis or approved design | Load binding knowledge, make the change and collect evidence. |
| [`jig-review`](skills/jig-review/SKILL.md) | Review a change, especially T2+ | Check requirements, correctness, rules, contracts and evidence against the actual diff. |
| [`jig-architecture-review`](skills/jig-architecture-review/SKILL.md) | T3 or an explicit architecture review | Check boundaries, dependency direction, invariants and accepted ADRs. |
| [`jig-verify`](skills/jig-verify/SKILL.md) | Before declaring completion | Run applicable checks and confirm the requested outcome, not just a green test suite. |
| [`jig-consolidate`](skills/jig-consolidate/SKILL.md) | After required implementation/review/verification, before commit or PR | Update durable knowledge or record `NO_DURABLE_KNOWLEDGE`; complete consolidation. |

Discovery, specification, alternatives, design and planning are workflow stages,
not additional standalone skills. The agent produces only artifacts the route
actually needs. A CLI artifact inventory does not prove completion or approval.

## Task workflows

### Choose a route

Start with `jig-task`. Risk sets the minimum class: a one-line authentication change
can still be T4. T0/T1 work that fits in one session need not create a workspace.

| Class | Typical scope | Route |
|---|---|---|
| T0 — trivial | Wording, formatting, obvious documentation edit | implement → verify |
| T1 — local | A contained change with an obvious solution | analyze → implement → verify |
| T2 — structural | Several components or an internal contract | analyze → plan → implement → review → verify |
| T3 — architectural | Boundaries, dependencies or lifecycle semantics | discover → design → **human gate** → implement → architecture review → verify → consolidate |
| T4 — critical | Security, secrets, destructive operations or money | discover → specify → alternatives → design → **human gate** → implement → independent review → verify → consolidate |

At a human gate, the agent presents a concrete design and waits for approval before
implementing. If scope grows, reclassify and complete the newly required stages.
Consolidate whenever a task produces lasting intent, including smaller tasks.

### Start and inspect a task

For example, ask the agent: “Use jig-task to add CSV export.” The following are
manual mechanics, not a substitute for the agent's classification and analysis:

```sh
.ai/scripts/jig task list
.ai/scripts/jig task current
.ai/scripts/jig task new csv-export --class T2 --domains reporting
.ai/scripts/jig task start csv-export
.ai/scripts/jig task show csv-export
.ai/scripts/jig task artifacts csv-export
```

**Filing a task and starting it are two steps.** `task new` records the intent and
nothing else: no branch, no checkout change, so filing something for next month costs
nothing and does not compete with the work in progress. A task with no branch is listed
as `not-started` and is never picked as `task current`.

`task start` begins it: it cuts the task's branch from the base branch, switches to it,
and records the commit it forked from. That fork point is recorded *then*, not at filing
time, because a base recorded weeks before work begins is already wrong by the time
anything needs it.

Start from a clean checkout — `task start` refuses a dirty tree, so one task's work
cannot become another's first commit. Workspaces belong to the checkout where they were
created.

Projects that work on one branch by choice set `git.branch_per_task: false`; `task start`
then records the current branch instead of cutting a new one.

### Several agents at once

One checkout holds one piece of uncommitted work. When another agent is already working
here, start the next task in a worktree of its own instead of pausing the first:

```sh
.ai/scripts/jig task start csv-import --worktree
# prints ../<project>.worktrees/csv-import — open a new agent session there
```

The dirty-tree refusal suggests exactly this. The new worktree is cut from the freshest
base branch and leaves this checkout, and the work in it, untouched. The command prints the
path and stops. An agent cannot move its own session, so opening a session in the new
worktree is your step.

The task's workspace stays where the task was filed, and the worktree gets a link to it.
From the original checkout, `task list` and `jig status` still show every task, and a task
running in a worktree carries where it is and how much there is uncommitted:

```text
csv-import class=T2 status=active branch=task/csv-import worktree=/work/app.worktrees/csv-import uncommitted=4
```

Agents do not commit, so that count is what waits for your review. Review and commit in
the worktree as you would anywhere. Once the task is merged and consolidated, housekeeping
removes the worktree with `git worktree remove` when it purges the workspace. It never
passes `--force`, so a worktree with uncommitted files stays, and `jig status` reports it
as `worktrees kept`. The branch is not deleted. `git.worktree_root` moves the worktrees
somewhere other than `../<project>.worktrees`.

### Pause and resume

```sh
.ai/scripts/jig task pause csv-export --reason "Waiting for the export format"
.ai/scripts/jig task list
.ai/scripts/jig task resume csv-export
```

Pause records a resumable task. Add `--stash` to stash tracked and untracked changes
with `git stash push -u`; ignored workspace files stay local. Resume on the
task's recorded branch and review the reported changes since the pause. A stash
conflict needs resolution before continuing implementation.

`task current` selects only a single eligible task on the current branch. If several
qualify, it exits 2 and lists candidates: name the intended task explicitly. Paused
tasks are excluded from automatic selection. To stop work permanently:

```sh
.ai/scripts/jig task abandon csv-export
```

### Review, verify and finish

Use the actual review base for your change, replacing `main` below if necessary:

```sh
.ai/scripts/jig task changes csv-export --base main
.ai/scripts/jig verify
.ai/scripts/jig knowledge check
```

The review inventory includes committed, staged, unstaged and untracked changes.
The agent must separate this task's changes from unrelated work. After required
checks and acceptance criteria pass, `jig-verify` records `ready`. After knowledge
has been reconciled, `jig-consolidate` records consolidation:

```sh
# Record these only after the corresponding work is complete.
.ai/scripts/jig task set csv-export status ready
.ai/scripts/jig task set csv-export knowledge_consolidated true
.ai/scripts/jig task set csv-export status consolidated
```

`NO_DURABLE_KNOWLEDGE` means the agent evaluated the outcome and found no new lasting
intent to record; it is a valid consolidation result. Then review and commit the
code and knowledge together, open a PR, and merge through your normal Git workflow.
Jig does not make `ready` or `consolidated` mean “merged”: remote state is derived
separately. Phase 5 handles eligible local workspaces after that.

## Knowledge workflows

### Load relevant context

```sh
.ai/scripts/jig context resolve --task csv-export --stage analyze --catalog
.ai/scripts/jig context resolve --task csv-export --stage implement --files src/export.php --catalog
```

Global documents and required knowledge must be read. Catalog entries are metadata,
not loaded bodies; use `--ids <document-id>` to request a document explicitly. As the
affected files or domains grow, resolve again. The agent records only documents it
actually read with `context acknowledge`, then runs `context guard`. The ledger
records a reading claim, not comprehension.

Standalone investigation can avoid selecting or creating a task:

```sh
.ai/scripts/jig context resolve --no-task --files src/export.php --stage analyze --catalog
```

Replace example paths with your repository's real files. Use `--files -` to read a
newline-separated list from stdin.

### Propose and accept domain knowledge

```text
jig-init → global glossary, architecture and rules
    → jig-map → proposed domain documents → human decision via jig-accept
        → accepted knowledge becomes available to context resolution
```

A domain pack can contain an overview, glossary and rules. Proposed documents live
at their real paths and are validated, but do not reach an agent's resolved context
until accepted. Rejection is recorded rather than erasing the proposal.

```sh
.ai/scripts/jig knowledge proposed
.ai/scripts/jig knowledge check
.ai/scripts/jig knowledge stale
.ai/scripts/jig knowledge paths
```

`jig-accept` presents numbered choices; users need not memorize document IDs. Agents
use `knowledge new`, `paths`, `summary` and `reviewed` to maintain metadata instead
of hand-editing frontmatter. Durable knowledge contains intent and constraints,
not copied task logs or entire plans. See [the frontmatter schema](schemas/frontmatter.md).

## Verify with profiles

Profiles supply deterministic checks for a stack. Jig does not install their tools
or project dependencies. Missing tools/checks are reported as skips; a skip is not a
pass or evidence that the application works.

| Profile | Checks when available |
|---|---|
| `generic` | Confirms the directory is a Git repository; always active. |
| `shell` | ShellCheck and executable `tests/run.sh`; supports changed-file scope. |
| `php` | PHPUnit (or Pest fallback), PHPStan, Pint and `composer validate`. |
| `laravel` | PHP checks plus `php artisan test`. |
| `node` | `npm test` and `npm run lint` when scripts exist. |
| `go` | `go vet ./...` and `go test ./...`. |

```sh
.ai/scripts/jig verify --list
.ai/scripts/jig verify --changed
.ai/scripts/jig verify --changed --base main
.ai/scripts/jig verify
```

Use scoped runs while iterating. Profiles that cannot narrow their checks run in
full and say so. Finish behavioral work with the required full checks; documentation
changes need relevant document checks. Jig refuses verification while it can detect
framework files pending installation: run `jig upgrade`, review the result, then retry.

Activate another profile or adapter by editing the inline lists in `.ai/config.yaml`
and running `jig upgrade`, or re-run `jig init` with explicit selections. Custom
checks belong in the project's installed profiles; upgrades preserve modified files.

## Upgrade the framework and a project

There are two separate operations. First update the shared source checkout:

```sh
git -C "$HOME/.local/share/jig" pull --ff-only
jig version
```

Use the actual clone path if you installed elsewhere. The global symlink immediately
uses that checkout's version. Then update a selected project's installed copy:

```sh
cd /path/to/your/project
jig upgrade --dry-run
jig upgrade
git diff
.ai/scripts/jig status
.ai/scripts/jig verify
```

These commands also work from subdirectories of that project. `jig upgrade` does
not fetch a new framework release, update unrelated repositories, or upgrade its
own source checkout. Repeat project upgrades where needed and commit the resulting
framework diff after review.

To choose an explicit source, including on a teammate's machine:

```sh
.ai/scripts/jig upgrade --from /path/to/jig --dry-run
.ai/scripts/jig upgrade --from /path/to/jig
```

Copy-mode upgrades compare source files with the recorded manifest and local hashes:

- Unmodified framework files are updated; missing/new files are installed.
- Locally modified files and conflicting existing files are kept and reported.
- Removed upstream files are deleted only when unchanged locally; modified orphans
  are kept and reported.
- Project knowledge, configuration and project-owned instructions are preserved.

The global command always runs code from the shared source checkout. It does **not**
automatically dispatch to the project's installed executable. Use `.ai/scripts/jig`
for daily task operations and verification when you want the version committed with
that project. The global command is convenient for installation and upgrades.

## Phase 5: lifecycle automation

**Status: implemented.** Housekeeping, the session helper and scheduler templates
exist and are covered by tests. Two limits are permanent rather than pending: only a
forge can distinguish an open pull request from a closed one, and a task whose branch
was deleted after merging resolves to `unknown` — which keeps its workspace.

```text
implementation → review → verification → consolidation → commit / PR → remote merge
                                                                      ↓
                                                           housekeeping (no LLM)
                                                                      ↓
                                                        eligible workspace → trash
                                                                      ↓
                                                           retention expires → purge
```

The safety rule is to keep workspaces when remote state is unknown. A confirmed
merge without consolidation requires attention. Stale work is reported; age alone
does not justify deleting an active workspace. Eligible workspaces first move to
`.ai/runtime/trash/`; permanent deletion happens after the retention period.

The command surface is:

```sh
jig housekeeping --dry-run
# After reviewing the report:
jig housekeeping
```

Forge detection can use optional authenticated `gh` or `glab`; Git provides a
fallback when merge evidence is available. A dry run can still query the remote;
`housekeeping.fetch` controls fetching. Neither a missing tool nor a failed lookup
should be interpreted as permission to delete.

Triggers are optional: the current design offers a Claude session helper and
external cron, macOS launchd or Linux systemd examples. The Codex adapter currently
offers scheduler guidance. `init` does not activate a scheduler or edit runtime
hook settings. See the [scheduler instructions](templates/scheduler/README.md) in
this checkout, or `.ai/templates/scheduler/README.md` after installation. Use an
absolute project path in a scheduler; do not rely on interactive shell `PATH`.

## Project layout and configuration

```text
your-project/
├── AGENTS.md                   shared agent instructions
├── CLAUDE.md                   Claude adapter instructions, when selected
├── .claude/skills/jig-*/        Claude skills, when selected
├── .codex/skills/jig-*/         Codex skills, when selected
└── .ai/
    ├── config.yaml            project-owned configuration
    ├── manifest               installed version, source and framework file hashes
    ├── scripts/               installed deterministic commands
    ├── profiles/              installed technology checks
    ├── templates/             framework-owned document / scheduler templates
    ├── knowledge/             durable, committed project knowledge
    ├── workspace/tasks/       local task artifacts and state; gitignored
    └── runtime/               local reports, timestamps and trash; gitignored
```

Configuration uses a flat YAML subset: dotted keys and inline lists, not nested
YAML. The knowledge/workspace/runtime paths are fixed. For example:

```yaml
profiles: [generic, php]
adapters: [claude, codex]
git.base_branch: main
forge: auto
housekeeping.cadence: 1d
housekeeping.fetch: true
housekeeping.trash_ttl: 7d
housekeeping.abandoned_ttl: 14d
housekeeping.stale_after: 60d
knowledge.require_frontmatter: true
```

Housekeeping keys apply to Phase 5. See the [configuration template](templates/config.yaml)
for defaults and comments. `jig status` summarizes tasks, knowledge proposals,
housekeeping information and framework drift; `jig help` lists command families.

## Roadmap and Phase 6

The [accepted decisions](.ai/knowledge/adr/) define the design. The roadmap is
broader than the currently completed implementation.

| Phase | Focus | Status for this README |
|---|---|---|
| 1 — Knowledge Harness | Installation, upgrades, manifest, knowledge and runtime adapters | Implemented foundation |
| 2 — Workspace & Context | Local task state, context selection, profiles and verification | Implemented foundation |
| 3 — Adaptive SDLC | Risk classification, stage skills and human gates | Implemented foundation |
| 4 — Consolidation | Durable intent, ADRs, coverage and stale knowledge | Implemented foundation |
| 5 — Lifecycle Automation | Remote merge evidence, housekeeping, trash and triggers | Implemented foundation |
| 6 — Measurement & Evolution | Process weight, change size and knowledge quality | Implemented foundation |

Phase 6 evaluates how well the framework works, through one read-only command:

```sh
jig measure
```

It reports knowledge quality, the distribution of task classes and their outcomes,
and the size of the change each class produced. Every number is derived when you ask
for it — from knowledge frontmatter, task state, git history and the purge lines of
`.ai/runtime/housekeeping.log`. Nothing is stored, nothing is committed, and there is
still no telemetry of any kind.

Two limits are part of the design rather than gaps to be closed later. The report
cannot price the work: tokens, turns and wall-clock effort are not recorded and cannot
be, so Phase 6 delivers *process weight against change size* instead of the "cost
measurement" the roadmap originally promised. And stage timing, session count and
whether a human gate was passed are visible only to the agent, so they are recorded
nowhere; `jig measure` prints that limitation in its own output rather than leaving a
reader to assume the numbers are complete.

## Troubleshooting and framework development

| Symptom | Action |
|---|---|
| `jig: command not found` | Check `PATH`, open a new shell, and verify the symlink target still exists. |
| `not inside a git repository` | Change into the target repository or initialize Git for a new project. |
| `project is not initialised` | Run the globally installed `jig init` inside that repository. |
| Cannot determine framework source | Pass `--from /absolute/path/to/jig`; an installed copy is not the full source checkout. |
| Skills are missing | Check configured adapters and `jig status`; run `jig upgrade`, then reopen the runtime session if needed. |
| Verification reports pending framework files | Preview and apply `jig upgrade`; verify again. |
| Verification reports skips | Install/configure the project's expected tools and rerun the applicable checks. |
| Several tasks match the branch | Inspect `task list` and explicitly name the task to continue. |
| Changes were kept during upgrade | Review `keep-modified` / `keep-conflict` reports and reconcile deliberately. |

Normal projects use copy mode so the team shares a committed version. For framework
development, `jig init --link` links scripts, profiles, templates and skills to the
source checkout. Changes then take effect immediately; links depend on that local
checkout remaining available. This repository uses link mode to develop Jig itself.

After adding framework-owned skills, profiles or templates, run `jig upgrade` to
place the new links before verification. Framework checks include:

```sh
bash tests/run.sh
.ai/scripts/jig knowledge check
```

The shell profile also runs ShellCheck. Follow [AGENTS.md](AGENTS.md), the
[rules and invariants](.ai/knowledge/RULES.md), and [accepted
decisions](.ai/knowledge/adr/) before changing framework behavior. Task notes belong in the ignored workspace; lasting
engineering intent belongs in `.ai/knowledge/`.
