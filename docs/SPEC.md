# Agent SDLC Framework

Status: Draft
Version: 0.4
Type: Vendor-neutral framework for AI-assisted software development

## Changelog 0.3 → 0.4

Decisions made while refining the spec (each recorded as a separate ADR in `.ai/knowledge/adr/`):

- **The executor is an agent, via skills. Scripts never call an LLM** (ADR-0001). Removed `task run` and `task classify` as commands; classification is performed by a skill, the script only records the result.
- **Implementation in shell with no mandatory dependencies** (ADR-0002). The term "CLI" replaced with "scripts".
- **The framework is copied into the project and committed**, rather than installed as a plugin at the user level (ADR-0003). A single environment for the whole team.
- **Knowledge documents get frontmatter** for deterministic context resolution (ADR-0004).
- **`status` in task state describes only the local lifecycle**; merge state is computed by housekeeping and is not the source of truth in the state file (ADR-0005). Added the `ABANDONED` state and handling of PRs closed without merge.
- **Two-phase purge**: workspace is first moved to trash, then erased once the retention period expires (ADR-0006).
- Housekeeping gets a cheap trigger from a session hook (timestamp check), the external scheduler becomes optional.
- `CLAUDE.md` is a one-line import of `AGENTS.md`, to avoid duplicating instructions.
- `RULES.md` is a single file of invariants; the `rules/` directory from the earlier spec is removed (until a real need appears).
- Added install versioning and `upgrade`.
- Metrics from §40 moved to Phase 6, without telemetry in the MVP.
- Open questions moved to §33.

## 1. Purpose

Agent SDLC Framework is a vendor-neutral framework for organizing the work of coding agents on software projects.

The framework is not a coding agent and does not replace Claude Code, Codex, or other AI runtimes. Its job is to provide a single layer on top of coding agents:

- project knowledge;
- engineering rules;
- canonical terminology;
- task context;
- adaptive SDLC workflows;
- quality gates;
- reusable skills;
- project bootstrap;
- knowledge consolidation;
- transient workspace lifecycle;
- integration adapters for different AI runtimes.

Core principle:

> Project knowledge and development process belong to the project, not to the AI vendor.

## 2. Core Problem

Coding agents use different mechanisms for instructions, rules, memory, and skills. This leads to:

- vendor lock-in;
- duplication of instructions;
- fragmented project context;
- context pollution;
- excessive SDLC ceremony;
- accumulation of obsolete task documentation.

The framework provides a vendor-neutral knowledge and process layer on top of specific AI runtimes.

## 3. Core Principles

### 3.1 Vendor Neutrality

The core framework does not depend on Claude, Codex, or any other AI runtime. Vendor-specific integration is implemented through adapters.

### 3.2 Project-Owned Knowledge

Architecture, terminology, decisions, engineering rules, **and the process itself** belong to the repository. A colleague cloning the repository gets both the knowledge and the process.

### 3.3 Adaptive SDLC

The framework uses the minimally sufficient process based on complexity, risk, scope, uncertainty, and architectural impact.

> Use the least expensive process that provides sufficient confidence.

### 3.4 Context Is a Resource

The framework minimizes repeated repository analysis, repeated mental-model reconstruction, unnecessary artifacts, and duplicated instructions.

Design consequence: **skills must be short**. Mechanics (finding files, reading state, assembling context, running tests) are moved into deterministic scripts, so a skill does not spend context describing them.

### 3.5 Artifact by Value

An artifact is created only if it is needed for handoff, context compression, approval, verification, or preservation of engineering knowledge.

### 3.6 Code Explains What, Knowledge Explains Why

Code is the primary source of truth about the system's current behavior. Durable documentation explains: why a decision exists, why it was implemented this way, what alternatives were considered, and what constraints and invariants exist.

### 3.7 Evidence over Claims

Completion is confirmed by evidence: tests, static analysis, linters, architecture checks, acceptance criteria, build results.

### 3.8 Human Discipline Is Not Infrastructure

Routine maintenance must not depend on whether a developer remembered to run cleanup or sync. Repeatable mechanical operations are automated.

### 3.9 Agent Executes, Scripts Are Deterministic

All semantic operations (analysis, classification, planning, review, consolidation) are performed by the agent following a skill's instructions. All mechanical operations (creating a workspace, writing state, assembling context, running verify, housekeeping) are performed by scripts. **Scripts never call an LLM.** This gives testability, zero inference cost for mechanics, and independence from the runtime.

## 4. Architecture

```
┌──────────────────────────────────────────────┐
│               Agent Runtime                  │
│          Claude Code / Codex / …             │
└──────────────────────┬───────────────────────┘
                       │ reads AGENTS.md, invokes skills
┌──────────────────────▼───────────────────────┐
│          Skills  (installed by adapter)      │
│   task · analyze · implement · review ·      │
│   verify · consolidate · architecture-review │
└──────────────────────┬───────────────────────┘
                       │ calls
┌──────────────────────▼───────────────────────┐
│          Scripts  (deterministic, no LLM)    │
│   init · upgrade · task · context · verify · │
│   knowledge check · housekeeping             │
└──────────────────────┬───────────────────────┘
                       │ reads / writes
┌──────────────────────▼───────────────────────┐
│                   Project                    │
│   .ai/knowledge (durable, tracked)           │
│   .ai/workspace (transient, ignored)         │
│   .ai/runtime   (state, ignored)             │
└──────────────────────────────────────────────┘
```

Housekeeping is the only component that runs **without an agent**: by a scheduler or by a session hook.

## 5. Framework Repository

```
agent-sdlc/
├── skills/            # vendor-neutral SKILL.md + references
├── scripts/           # sh, POSIX / bash 3.2 compatible
├── adapters/
│   ├── claude/        # install rules, transformers, hooks
│   └── codex/
├── profiles/
│   ├── generic/
│   ├── php/
│   ├── laravel/
│   └── go/
├── templates/         # knowledge templates, AGENTS.md, state
├── schemas/           # frontmatter and state field definitions
├── tests/             # sh test runner + fixtures
└── docs/
```

## 6. Project Structure

After `init` the framework creates:

```
project/
├── AGENTS.md                 # runtime-neutral instructions
├── CLAUDE.md                 # contains only: @AGENTS.md
│
├── .ai/
│   ├── config.yaml           # profiles, forge, housekeeping cadence, ttl
│   ├── manifest              # installed version + file hashes
│   ├── scripts/              # copy of framework scripts (tracked)
│   ├── profiles/             # active profiles (tracked)
│   │
│   ├── knowledge/            # tracked
│   │   ├── GLOSSARY.md
│   │   ├── ARCHITECTURE.md
│   │   ├── RULES.md
│   │   ├── features/
│   │   ├── conventions/
│   │   └── adr/
│   │
│   ├── workspace/            # gitignored
│   │   └── tasks/
│   │
│   └── runtime/              # gitignored
│       ├── last-housekeeping
│       └── trash/
│
├── .claude/skills/sdlc-*/    # installed by claude adapter (tracked)
└── .codex/skills/sdlc-*/     # installed by codex adapter (tracked)
```

Tracked by Git: `AGENTS.md`, `CLAUDE.md`, `.ai/config.yaml`, `.ai/manifest`, `.ai/scripts/`, `.ai/profiles/`, `.ai/knowledge/`, installed skills.

Gitignored: `.ai/workspace/`, `.ai/runtime/`.

## 7. Durable Knowledge

Durable knowledge is information that must survive a specific task.

Criterion:

> Would future developers or agents lose meaningful engineering intent if this information disappeared?

If not, the artifact should not become permanent documentation.

## 8. Knowledge Document Frontmatter

Every document in `.ai/knowledge/` (except `GLOSSARY.md`, `ARCHITECTURE.md`, `RULES.md`, which are considered global) starts with YAML frontmatter:

```yaml
---
id: feature-trigger-resolution
type: feature            # feature | adr | convention
status: active           # active | deprecated | superseded (adr: accepted | superseded | deprecated | rejected)
domains: [flow, triggers]
paths:
  - "src/Flow/**"
  - "app/Services/Trigger*"
---
```

Required fields: `id`, `type`, `status`. `domains` and `paths` drive context resolution (§25): a document is considered relevant to a task if at least one of the affected files matches `paths`, or the task is explicitly tagged with one of the `domains`.

Frontmatter is limited to flat scalars and single-level lists, so it can be parsed without a YAML parser. Keeping `paths` up to date is the responsibility of the consolidate skill.

## 9. Glossary

`.ai/knowledge/GLOSSARY.md` contains the canonical ubiquitous language:

```
Assistant

Canonical system term.

Informal synonyms: bot, chatbot.

Use "Assistant" in: source code, database schema, API, technical documentation.
```

## 10. Architecture

`.ai/knowledge/ARCHITECTURE.md` contains a high-level architecture map: domains, boundaries, dependency directions, runtime flows, system-wide constraints, invariants.

Architecture documentation does not retell the implementation without additional engineering intent.

## 11. Feature Knowledge

`.ai/knowledge/features/` is for complex or long-lived features. A feature document answers **WHAT / WHY / CONSTRAINTS** and describes the current state of the feature, not the history of a specific task. Multiple tasks sequentially modify one feature document.

## 12. ADR

`.ai/knowledge/adr/NNNN-<slug>.md` records significant architecture decisions: Context, Decision, Alternatives, Consequences. Historical ADRs are preserved with status `accepted | superseded | deprecated | rejected`.

## 13. Rules, Invariants and Conventions

- `.ai/knowledge/RULES.md` is normative requirements and invariants. A single file; area-specific rules are added as sections. A separate `rules/` directory is not introduced until a real need arises.
- `.ai/knowledge/conventions/` is stable engineering practices, one document per area.

Invariants are a special class of rules:

```
- Published definitions are immutable.
- Node handlers do not persist domain effects directly.
- Domain boundaries cannot be bypassed for convenience.
```

## 14. Transient Task Workspace

`.ai/workspace/tasks/<task-id>/` may contain:

```
task.md  discovery.md  spec.md  design.md  plan.md  review.md  verification.md  state
```

Task artifacts exist locally, under `.gitignore`, never automatically become part of the repository, live as long as the task lives, are used for context preservation between sessions, and are deleted by housekeeping after the lifecycle ends.

## 15. Task State

`.ai/workspace/tasks/<task-id>/state` is a flat `key: value` file, readable without a parser:

```
task_id: TASK-123
branch: feature/TASK-123
class: T2
status: active
knowledge_consolidated: false
created_at: 2026-09-08
updated_at: 2026-09-10
```

Fields:

| Field | Who writes it | Values |
|---|---|---|
| `task_id` | script `task new` | arbitrary id without spaces or `/` |
| `branch` | script `task new` | current branch |
| `class` | skill `task` via `task set` | `T0`–`T4` |
| `status` | skills via `task set` | `active` → `ready` → `consolidated`; `abandoned` |
| `knowledge_consolidated` | skill `consolidate` | `true` / `false` |
| `created_at`, `updated_at` | scripts | ISO date |

**`status` describes only the local lifecycle.** Merge state (`merged / open / closed / unknown`) is a derived fact about the remote, which housekeeping computes on every run and never writes into `state` as truth (a cache in `.ai/runtime/` is allowed).

## 16. SDLC Stages

```
DISCOVER  SPECIFY  DESIGN  PLAN  IMPLEMENT  REVIEW  VERIFY  CONSOLIDATE  DONE
```

Stages are composable and do not form a mandatory fixed pipeline.

## 17. Adaptive Task Classification

Classification is performed by the **agent** following the rubric from the `task` skill; the result is recorded by a script into `state`. The script does not classify.

| Class | Name | Workflow |
|---|---|---|
| T0 | Trivial | Implement → Verify |
| T1 | Local | Analyze → Implement → Verify |
| T2 | Structural | Analyze → Plan → Implement → Review → Verify |
| T3 | Architectural | Discover → Design → Human Gate → Implement → Architecture Review → Verify → Consolidate |
| T4 | Critical | Discover → Specify → Alternatives → Design → Human Gate → Implement → Independent Review → Regression/Security Verification → Consolidate |

Not every stage requires a persistent artifact. T0–T1 usually do not create a workspace at all.

## 18. Consolidation

`CONSOLIDATE` answers the question:

> What knowledge discovered or created during this task should survive the task?

Outcomes: `discard | feature knowledge | architecture | ADR | glossary | rule | convention | invariant`.

`NO_DURABLE_KNOWLEDGE` is a valid outcome, not an error. In both cases the skill sets `knowledge_consolidated: true`.

## 19. Consolidation Principles

Do not keep permanent copies of `discovery.md`, `spec.md`, `plan.md`, `review.md`, `verification.md` just because they existed.

Preserve: why, constraints, trade-offs, rejected alternatives, invariants, canonical terminology, architectural decisions.

After consolidation, durable knowledge is changed directly in `.ai/knowledge/` (including `paths` in the frontmatter of affected documents) and committed together with the implementation.

## 20. Consolidation Timing

```
Implementation → Review → Verification → Consolidation → Commit / PR → Merge
```

> Code change and the durable knowledge describing its engineering intent should normally enter the repository together.

## 21. Changes After Consolidation

If, after consolidation, the implementation changes within the same task (PR review), the durable document is updated in place. A new task document is not created; `knowledge_consolidated` stays `true` if the knowledge impact has not changed.

## 22. Post-Merge Changes

If a regression is discovered after merge, or a further change is required, a new task workspace is created on the current codebase and current durable knowledge. The previous transient workspace is not restored.

## 23. Lifecycle and Cleanup Policy

Local `status` × derived remote state:

| `status` | Remote | Housekeeping action |
|---|---|---|
| `consolidated` | `merged` | **purge** (to trash, see §24) |
| `active` / `ready` | `merged` | preserve, **flag: needs consolidation** |
| any | `open` | preserve |
| any | `closed` (PR closed without merge) | preserve, **flag: abandoned?** — skill `task abandon` moves it to `abandoned` |
| `abandoned` | any | purge after `abandoned_ttl` (default 14d) |
| any | `unknown` | preserve |

> When uncertain, preserve transient data.

TTL is a secondary safety mechanism. `age > stale_after` (default 60d) does not trigger destructive cleanup; the workspace is marked `STALE_CANDIDATE` and appears in the housekeeping report.

> Semantic lifecycle has priority over TTL.

## 24. Housekeeping

`.ai/scripts/sdlc housekeeping` is a deterministic process with no LLM:

1. `git fetch` (if network is available; otherwise it works on local state and marks the result as `stale-remote`);
2. walks `.ai/workspace/tasks/*/state`;
3. for each task determines remote state:
   - forge API via `gh` / `glab`, if available and authenticated;
   - otherwise Git ancestry (`merge-base --is-ancestor` relative to the base branch), accounting for squash/rebase via patch-id comparison;
   - otherwise `unknown`;
4. applies the policy from §23;
5. **purge is two-phase**: the workspace is moved to `.ai/runtime/trash/<date>/<task-id>/`; contents of trash older than `trash_ttl` (default 7d) are deleted permanently. Before any deletion the path is validated: it is inside `.ai/`, it is a directory, and `task-id` matches the pattern;
6. writes a report to `.ai/runtime/housekeeping.log` and updates `.ai/runtime/last-housekeeping`;
7. returns a non-zero exit code if there are tasks flagged `needs consolidation` — this is the only situation that requires an agent.

Merge commits, squash merges, rebase merges, and deleted remote branches are all accounted for.

## 25. Scheduling

Two triggers, both optional:

1. **Session hook** (installed by the adapter): at the start of an agent session, the age of `.ai/runtime/last-housekeeping` is checked; if older than `cadence` (default 1d), housekeeping runs in the background. The cost of the check is a single `stat`; the network is not touched.
2. **External scheduler** — cron, launchd, systemd timer, Claude scheduled routine, CI runner. `init` offers to configure this, but does not require it.

The framework does not implement its own scheduler.

## 26. Context Resolution

`.ai/scripts/sdlc context [--task <id>] [--files <list>] [--domains <list>]` deterministically returns a list of relevant documents:

```
global:   GLOSSARY.md  ARCHITECTURE.md  RULES.md
matched:  features/trigger-resolution.md   (paths: src/Flow/**)
          adr/0007-trigger-idempotency.md  (domains: triggers)
workspace: .ai/workspace/tasks/TASK-123/{task.md,plan.md}
```

Files for matching are taken from the argument, from `git diff --name-only` relative to the base branch, or from `task.md`. The agent reads only the returned list. If nothing matched, only global + workspace are returned.

## 27. Knowledge Authority

```
Human Task Instruction
  ↓ Accepted ADR
  ↓ Architecture
  ↓ Project Rules / Invariants
  ↓ Conventions
  ↓ Glossary
  ↓ Feature Knowledge
  ↓ Transient Task Context
```

Significant conflicts are escalated to a human.

## 28. Skills

```
skills/
├── sdlc-init/                 # initial knowledge population (analyze repo)
├── sdlc-task/                 # create/open a task, classify, choose workflow
├── sdlc-analyze/
├── sdlc-implement/
├── sdlc-review/
├── sdlc-verify/
├── sdlc-consolidate/
└── sdlc-architecture-review/
```

Requirements for a skill:

- vendor-neutral markdown; runtime specifics only in frontmatter, which the adapter rewrites;
- **short**: describes judgment and the order of actions, delegates mechanics to `.ai/scripts/sdlc …`;
- starts with `sdlc context`, not with its own repository traversal;
- does not contain generic best practices — those belong to profiles and `.ai/knowledge/`.

## 29. Scripts

`.ai/scripts/sdlc <command>` is the single entry point:

```
init                      idempotent project bootstrap
upgrade                   update scripts/skills/profiles from the framework, without touching files changed by the user
status                    summary: active tasks, housekeeping flags, version
task new <id>             create workspace + state
task set <id> <k> <v>     write a state field
task abandon <id>
context [...]             §26
verify                    run checks from active profiles, return a combined exit code
knowledge check           frontmatter validation, broken links, duplicate ids, documents without an owning path
housekeeping [--dry-run]  §24
```

Constraints: POSIX sh / bash 3.2; no mandatory external dependencies; `git` is required; `gh` / `glab` are optional; every command is covered by tests in `tests/`.

## 30. Profiles

A profile is a directory:

```
profiles/laravel/
├── profile.yaml      # detect: files/globs from which applicability is derived
├── verify.sh         # how to run tests / lint / static analysis for this stack
├── rules.md          # stack-specific rules, included into RULES.md as a section
└── conventions/      # optional
```

A project activates several profiles (`.ai/config.yaml: profiles: [php, laravel]`). `sdlc verify` sequentially calls `verify.sh` for each active profile. `generic` is always active.

## 31. Runtime Adapters

MVP: Claude Code, Codex.

An adapter is responsible only for integration:

- where to copy skills (`.claude/skills/`, `.codex/skills/`) and how to transform them (frontmatter, call syntax `/sdlc-task` ↔ `$sdlc-task`);
- installing the session hook for housekeeping (where the runtime supports it);
- generating runtime instructions (`CLAUDE.md` = `@AGENTS.md`; for Codex, `AGENTS.md` is read directly).

SDLC logic stays in skills and scripts. Installed files are committed — the whole team works in a single environment.

## 32. Init and Upgrade

`sdlc init`:

1. determine the repository root;
2. determine the technology stack, suggest profiles;
3. create `.ai/` and missing knowledge templates;
4. copy scripts, profiles, skills for the chosen adapters;
5. create `AGENTS.md`, `CLAUDE.md`;
6. configure `.gitignore`;
7. write `.ai/manifest` (framework version + hashes of installed files);
8. offer to configure scheduled housekeeping;
9. **do not overwrite existing knowledge**.

`sdlc upgrade`: compares hashes from the manifest with the current ones; files not modified by the user are updated; modified ones are preserved with a warning. Both are idempotent.

## 33. Open Questions

Unresolved; do not block Phase 1–2.

- **Git worktrees.** `.ai/workspace/` lives inside the checkout — each worktree gets its own. Alternative: workspace always in the main checkout, keyed by `task_id`. Decide in Phase 2.
- **Concurrency.** Two sessions on the same task write to the same `state`. For now, last-write-wins; a lock file if needed.
- **Metrics §40 (0.3).** Require telemetry that does not exist. Deferred to Phase 6; MVP has only qualitative assessment.
- **External artifact storage** for regulated environments — optional backend, not in MVP.

## 34. Non-Goals

The framework does not implement: its own LLM; its own coding agent; agent orchestration from scripts; an IDE; an issue tracker; mandatory multi-agent orchestration; permanent storage of the entire SDLC history; a mandatory external artifact repository; mandatory CI consolidation; LLM-based housekeeping; cleanup that requires manual discipline; support for more than two runtimes in the MVP.

## 35. MVP

The MVP must prove:

- **Knowledge Harness** — Claude Code and Codex understand project knowledge the same way.
- **Adaptive SDLC** — simple tasks do not get unnecessary ceremony.
- **Transient Workspace** — task-specific artifacts do not pollute the repository.
- **Consolidation** — engineering intent outlives the task only in durable knowledge.
- **Automatic Housekeeping** — merged and consolidated workspaces are deleted without developer action and without an LLM.
- **Vendor Independence** — the scheduler and coding agent are replaceable without changing lifecycle semantics.

## 36. Development Phases

| Phase | Content |
|---|---|
| 1 — Knowledge Harness | `init`, `upgrade`, manifest, knowledge templates + frontmatter, `knowledge check`, `AGENTS.md`, Claude + Codex adapters, `sdlc-init` skill |
| 2 — Workspace & Context | `task new/set/abandon`, state, `context`, profiles, `verify` |
| 3 — Adaptive SDLC | `sdlc-task` with classification, stage skills, human gates |
| 4 — Consolidation | `sdlc-consolidate`, feature knowledge, ADR candidates, `paths` maintenance, stale knowledge detection |
| 5 — Lifecycle Automation | forge detection, ancestry fallback, housekeeping, trash, session hook, scheduler templates |
| 6 — Measurement & Evolution | benchmarking, cost measurement, knowledge quality |

## 37. Final Lifecycle

```
                    TASK
                      │
                      ▼
          sdlc-task: classify → workflow
                      │
                      ▼
             Local Task Workspace
                      │
             ┌────────┴────────┐
        Spec / Plan       Implementation
             └────────┬────────┘
                      ▼
                   Review
                      ▼
                 Verification
                      ▼
                Consolidation
                 /          \
     Durable Knowledge    NO_DURABLE_KNOWLEDGE
                 \          /
                      ▼
                 Commit / PR
                      ▼
                Remote Merge
                      │
          local workspace remains
                      ▼
          Housekeeping (scheduled, no LLM)
                      │
           consolidated + merged?
                      │ yes
                      ▼
               trash → purge
```

> Code preserves behavior, durable knowledge preserves intent, and transient process artifacts disappear automatically when their lifecycle ends.
