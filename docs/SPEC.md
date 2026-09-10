# Jig

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
- Added install versioning and `upgrade`; defined `.ai/config.yaml` (flat YAML subset, fixed paths) and `.ai/manifest` (`git hash-object` hashes, framework-owned files only) with the `upgrade` decision table (§6.1, §6.2, §32).
- Metrics from §40 moved to Phase 6, without telemetry in the MVP.
- Open questions moved to §33.
- Product named **Jig** (ADR-0007); script entry point `jig`, skills `jig-<stage>`, plugin namespace `/jig:<stage>`. The `.ai/` directory keeps its name: knowledge belongs to the project, not to the tool.

## 1. Purpose

Jig (Agent SDLC Framework) is a vendor-neutral framework for organizing the work of coding agents on software projects.

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
jig/
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
│   ├── templates/knowledge/  # document templates for `knowledge new` (tracked)
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
├── .claude/skills/jig-*/    # installed by claude adapter (tracked)
└── .codex/skills/jig-*/     # installed by codex adapter (tracked)
```

Tracked by Git: `AGENTS.md`, `CLAUDE.md`, `.ai/config.yaml`, `.ai/manifest`, `.ai/scripts/`, `.ai/profiles/`, `.ai/templates/`, `.ai/knowledge/`, installed skills.

`.ai/templates/knowledge/` is framework-owned: `jig knowledge new` instantiates it, and `upgrade` carries improvements forward. `GLOSSARY.md`, `ARCHITECTURE.md` and `RULES.md` are seeded from the same templates into `.ai/knowledge/` on `init` and become project-owned the moment they are written (ADR-0003).

Gitignored: `.ai/workspace/`, `.ai/runtime/`.

### 6.1 Configuration: `.ai/config.yaml`

There is no YAML parser (ADR-0002), so the file is a flat YAML subset: `section.key: value`, inline lists only, no nesting. It stays valid YAML for editors and linters and is read in shell with one `sed` expression.

```yaml
# Jig project configuration.
# Flat YAML subset: `section.key: value`, inline lists only, no nesting.
# Paths are NOT configurable: .ai/knowledge, .ai/workspace, .ai/runtime are fixed.

profiles: [generic, php, laravel]     # generic is always active
adapters: [claude, codex]

git.base_branch: main                 # merge target for ancestry checks
forge: auto                           # auto | github | gitlab | none

housekeeping.cadence: 1d              # session hook runs housekeeping if last run is older
housekeeping.fetch: true              # allow `git fetch` during housekeeping
housekeeping.trash_ttl: 7d            # trash entries older than this are deleted
housekeeping.abandoned_ttl: 14d       # abandoned workspaces are purged after this
housekeeping.stale_after: 60d         # older active tasks are reported as STALE_CANDIDATE

knowledge.require_frontmatter: true   # `jig knowledge check` fails on missing frontmatter
```

Any key that is absent takes the default built into the script. Reading a value:

```sh
cfg() { sed -n "s/^$1:[[:space:]]*//p" .ai/config.yaml | sed 's/[[:space:]]*#.*//'; }
cfg housekeeping.trash_ttl              # → 7d
cfg profiles | tr -d '[]' | tr ',' ' '  # → generic php laravel
```

Paths are deliberately not configurable. Configurable paths force every skill to resolve them before doing anything (ai-factory carries ~20 `paths.*` keys for this reason), which is exactly the context cost §3.4 is meant to eliminate.

### 6.2 Manifest: `.ai/manifest`

The manifest records which installed files belong to the framework and what they looked like when installed. It is maintained only by `jig init` and `jig upgrade`.

```
# jig manifest. Do not edit by hand; maintained by `jig init` and `jig upgrade`.
jig.version: 0.1.0
jig.source: github.com/bpai/jig@a1b2c3d
installed_at: 2026-09-08
adapters: [claude, codex]
---
3f786850e387550fdab836ed7e6dc881de23001b .ai/scripts/jig
89e6c98d92887913cbf6d0d2d1e4e5c7a8b9c0d1 .ai/scripts/lib/state.sh
e2d3c4b5a6978877665544332211009988776655 .ai/profiles/php/verify.sh
1122334455667788990011223344556677889900 .claude/skills/jig-task/SKILL.md
1122334455667788990011223344556677889900 .codex/skills/jig-task/SKILL.md
```

- Header lines above `---` use the same flat `key: value` form as `config.yaml`; lines below are `<hash> <path>`.
- The hash is `git hash-object <file>`. `git` is the one mandatory dependency, so the hash exists on every machine, whereas `shasum` and `sha256sum` differ between macOS and Linux. It is SHA-1, which is adequate for drift detection; the manifest is not a security boundary.
- Tracked: `.ai/scripts/**`, `.ai/profiles/**`, `.claude/skills/jig-*/**`, `.codex/skills/jig-*/**`.
- Not tracked: `AGENTS.md`, `CLAUDE.md`, `.ai/config.yaml`, everything under `.ai/knowledge/`. These are created once and then owned by the project; `upgrade` never touches them.

## 7. Durable Knowledge

Durable knowledge is information that must survive a specific task.

Criterion:

> Would future developers or agents lose meaningful engineering intent if this information disappeared?

If not, the artifact should not become permanent documentation.

## 8. Knowledge Document Frontmatter

Every document in `.ai/knowledge/` (except the three global documents `.ai/knowledge/GLOSSARY.md`, `ARCHITECTURE.md` and `RULES.md`, recognised by path) starts with YAML frontmatter:

```yaml
---
id: rule-payments
type: rule               # feature | adr | convention | domain | glossary | rule
status: active           # active | deprecated | superseded (adr: accepted | superseded | deprecated | rejected)
summary: Mandatory constraints for changes to payment processing.
domains: [payments]
topics: [money, gateway, ledger]
load: domain             # always | domain | matched (default matched)
requires: [adr-0012-money-representation]
paths:
  - "src/Payments/**"
---
```

Required fields: `id`, `type`, `status`. `domains`, `topics` and `paths` drive context resolution (§26): a document is considered relevant to a task if at least one of the affected files matches `paths`, or the task is tagged with one of the `domains` or `topics`. `load` decides how strong that relevance is, and `requires` names documents that must come with it. The full schema, including the domain pack layout under `.ai/knowledge/domains/<domain>/`, is `schemas/frontmatter.md`.

Frontmatter is limited to flat scalars and single-level lists, so it can be parsed without a YAML parser. Keeping `paths` up to date is the responsibility of the consolidate skill.

## 8.1 Proposed Knowledge

`status: proposed` is knowledge written but not yet agreed to. The document lives at its real path, is validated by `jig knowledge check` and appears as an ordinary git diff, but `jig context` does not resolve it: resolution uses an allowlist of `active` and `accepted`, so a proposed document cannot enter any agent's context, be listed in the catalog, or satisfy a `requires`. `jig knowledge accept <id>` promotes it after a human has agreed; `--all` is how it is reviewed before that. `jig status` reports the count on the `proposals:` line, so knowledge left undecided is discoverable by someone arriving later rather than only by whoever was in the session that proposed it.

This is what makes `jig-map` (§28) safe to run on an unfamiliar codebase: everything it infers is written where a human can read it in context, and nothing it infers is authoritative until accepted. An allowlist rather than a denylist of retired values, because a denylist resolves every value it has not heard of — a typo included — as though it were active.

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

Pause is a separate field, not a `status` value: a task paused while `ready` resumes as
`ready` (ADR-0012). See `schemas/state.md` for the four `paused*` keys.

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

### 17.1 Requirements, inputs, and review

Standalone exploration can answer a question before task classification/creation. Explicit
analysis of a task stays attached to it. Once implementation intent is concrete, normal
routing and gates apply. `context --no-task` bypasses unrelated current-task selection.

For T2+, keep one acceptance-to-check/evidence map in plan.md or its existing design/spec
owner. Analysis resolves material ambiguity; low-impact defaults are stated, deferred
questions have owner/trigger and cannot cross dependent work. Describe relevant behavior
deltas and compatibility consequences. Each plan step names its completion check; evidence
can serve several steps/criteria. T0/T1 keep proportional prose. Omitted/unverified criteria
remain visible; green tests do not substitute for requirement coverage.

`task artifacts <id> [--provided <kinds>]` reports fixed-route inputs as present,
provided-claim or unavailable, and input dependencies as inputs-available/needs-input.
Conversation outputs need no separate file. The caller must substantiate provided claims;
semantic approval, implementation and review outcomes remain unassessed. This read-only
report never advances lifecycle. Exact relationships are in schemas/state.md (ADR-0020).

`task changes <id> --base <ref> [--files <list>|-] [--format report|paths]` inventories
committed/staged/unstaged/untracked layers with an explicit commit baseline. The file
allowlist is literal; explicit empty scope remains empty. No-base and Git errors fail.
Both review stages inspect all selected patches/new contents and every requirement;
record ownership evidence and disclose unresolved mixed-file boundaries (ADR-0022).

Use a compact persisted handoff at session/executor boundaries, pause or gate; same-session
transitions are brief. UI work maps applicable states to criteria and UI evidence; backend
work needs no UI artifact. Shared guidance is installed under existing skills/references.

## 18. Consolidation

`CONSOLIDATE` answers the question:

> What knowledge discovered or created during this task should survive the task?

Outcomes: `discard | feature knowledge | architecture | ADR | glossary | rule | convention | invariant`.

`NO_DURABLE_KNOWLEDGE` is a valid outcome, not an error. In both cases the skill sets `knowledge_consolidated: true`.

## 19. Consolidation Principles

Do not keep permanent copies of `discovery.md`, `spec.md`, `plan.md`, `review.md`, `verification.md` just because they existed.

Preserve: why, constraints, trade-offs, rejected alternatives, invariants, canonical terminology, architectural decisions.

After consolidation, durable knowledge is changed directly in `.ai/knowledge/` (including `paths` in the frontmatter of affected documents) and committed together with the implementation.

Frontmatter is never hand-edited during this: `jig knowledge new` creates the document, `jig knowledge paths add|remove` maintains its globs, and `jig knowledge reviewed` stamps it as reconciled with the code. The skill decides *what* survives; the script performs the edit (ADR-0001).

## 19.1 Stale Knowledge

A document rots when the code under its `paths` moves on and its prose does not. `jig knowledge stale` reports four verdicts — `stale` (a file matching its `paths` has a commit newer than `reviewed_at`), `unreviewed` (it claims paths but was never reconciled), `orphaned` (it was reconciled once and its globs now match nothing, so the code moved away), `planned` (it was never reconciled and its globs match nothing, so the code is not written yet). Only the first three are defects: deciding at the gate before implementing (§17) makes forward-looking documents normal, and `--strict` does not fail on them. Documents with status `superseded`, `deprecated` or `rejected` are skipped: they describe the past on purpose.

The report is not a gate. It exits 0 unless `--strict` is given, so `verify` stays a correctness check and does not begin failing on knowledge that is merely aging (ADR-0010).

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
| `paused`, not consolidated | `merged` | preserve, **flag: needs consolidation** |
| `paused` | `open` / `closed` / `unknown` | preserve |
| `paused`, age > `stale_after` | any | report as `STALE_CANDIDATE` |
| any | `unknown` | preserve |

Pause is a field, not a `status` value (ADR-0012), so it combines with the rows above: it
exempts a task from auto-resume, never from being reported.

> When uncertain, preserve transient data.

TTL is a secondary safety mechanism. `age > stale_after` (default 60d) does not trigger destructive cleanup; the workspace is marked `STALE_CANDIDATE` and appears in the housekeeping report.

> Semantic lifecycle has priority over TTL.

## 24. Housekeeping

`.ai/scripts/jig housekeeping` is a deterministic process with no LLM:

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

Two triggers, both optional, neither installed automatically:

1. **Session hook** — `.ai/scripts/jig-session-hook`, a framework-owned script. At the start of an agent session it checks the age of `.ai/runtime/last-housekeeping`; if older than `cadence` (default 1d), housekeeping runs detached in the background. The cost of the check is a single `stat`; the network is not touched. The hook always exits 0, including when the project is not initialised, so it can never break the session it is attached to.

   Wiring it up is the user's action: the adapter *offers* the entry, and jig never edits the runtime's own config file (ADR-0024). `jig init --session-hook` will create that file for you when it does not exist yet — creating is safe, editing is not — and declines silently when it does. For Claude Code that entry goes in `.claude/settings.json`; `jig status` reports whether it is there. **Codex has no SessionStart equivalent**, so Codex users get lifecycle parity but not this trigger, and must use a scheduler.
2. **External scheduler** — cron, launchd, systemd timer, Claude scheduled routine, CI runner. `init` prints where the examples live (`.ai/templates/scheduler/`); it never prompts and never installs one.

The framework does not implement its own scheduler.

## 26. Context Resolution

`.ai/scripts/jig context [--task <id>] [--files <list>|-] [--domains <list>] [--all] [--format list|paths]` deterministically returns a list of relevant documents, one per line:

```
global:    .ai/knowledge/GLOSSARY.md
global:    .ai/knowledge/ARCHITECTURE.md
global:    .ai/knowledge/RULES.md
matched:   .ai/knowledge/features/trigger-resolution.md   (paths: src/Flow/**)
matched:   .ai/knowledge/adr/0007-trigger-idempotency.md  (domains: triggers)
workspace: .ai/workspace/tasks/TASK-123/task.md
workspace: .ai/workspace/tasks/TASK-123/plan.md
```

Inputs:

- **Task**: `--task`, otherwise the one candidate for the current branch (`jig task current`).
  With several candidates the command warns, omits the workspace section and still exits 0:
  omitting is safer than picking, and a read-only command must not block (ADR-0012).
- **Files**: `--files` (comma list, or `-` for stdin), otherwise derived from git: files changed since the merge base with `git.base_branch`, plus unstaged and untracked files.
- **Domains**: `--domains`, otherwise the task's `domains` state key.

A document matches when any of its `paths` globs matches any file, or any of its `domains` equals a requested domain; the reason is printed. Resolution uses an allowlist of `active` and `accepted` (§8.1), so `proposed`, `superseded`, `deprecated`, `rejected` and any value the resolver has not heard of are skipped unless `--all`. `--format paths` prints bare paths for piping. The agent reads only the returned list. If nothing matched, only global + workspace are returned.

Enumeration walks `.ai/knowledge/` recursively, so a document is resolved wherever it is filed; applicability lives in frontmatter, never in the directory (ADR-0004).

## 26.1 Progressive Resolution

The stateless form answers "what matches this diff". A working agent has a second question — what must I have read before I change these files, and what have I not read yet — and four subcommands answer it:

```
jig context resolve [selectors] [--catalog]
jig context pending [selectors]
jig context guard   [selectors]
jig context acknowledge --task <id> --files <list>|-
```

Selectors are `--task` (or `--no-task`), `--stage`, `--files`, `--domains`, `--topics`, `--ids` and `--all`.

`resolve` prints two things. **Required** documents, whose full body the agent must read: the globals, `load: always` documents, `load: domain` documents of an entered domain, `load: matched` documents hit by a path or topic, ids named with `--ids`, and the transitive `requires` closure of all of those. And, with `--catalog`, **catalog** entries: id, path and `summary` of the remaining active documents of the entered domains. A catalog entry is metadata only; the agent decides whether it is relevant and pulls it in with `--ids`. A body is never loaded merely because it shares a domain.

A `requires` that resolves to no active document is fatal: returning a partial context that looks complete is the failure this exists to prevent.

`acknowledge` records that a document has been read, in a ledger at `.ai/workspace/tasks/<id>/context` — one `<git-hash><TAB><path>` line per document, in the gitignored workspace. `pending` prints tracked documents with no acknowledgement or whose content changed since one; a document that changes becomes pending again, which is why the ledger stores hashes rather than a list. `guard` prints the pending set and exits 1 while any remain. Workspace artifacts are returned by `resolve` but never tracked: they are the task's own output.

T0 and T1 have no workspace (§17), so they have no ledger. `guard` then prints `no task workspace; nothing tracked` and exits 0 — a skill can call it unconditionally, and the report never implies a check that did not happen.

What the ledger proves is deliberately narrow: the agent stated it read the document. It is not evidence of comprehension, and a passing guard is not evidence that the knowledge was applied.

### 26.2 Stage relevance and standalone exploration

`--stage` adds relevance in progressive resolve/pending/guard. A load: matched document
in an entered domain's catalog is promoted when its optional stages metadata matches.
Existing mandatory globals, load policies, path/topic matches, explicit IDs and transitive
requires remain binding. Stage never hides a constraint or selects unrelated domains.
Supported names and writer commands are in schemas/frontmatter.md (ADR-0021).

Use the same stage and other selectors for resolve/pending/guard. Newly required or changed
hashes become pending; unchanged acknowledged documents need no reread. Missing mandatory
globals, requested IDs or dependencies fail even without a task. Legacy context rejects
--stage and directs callers to resolve. Workspace artifacts are not stage-filtered.

Both forms accept --no-task, mutually exclusive with --task. It bypasses implicit task
selection, inherited task domains and workspace artifacts; explicit selectors still work.
No-task guard reports no ledger, not a successful read check. No task state is written.

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
├── jig-init/                 # initial knowledge population (analyze repo)
├── jig-map/                  # propose per-domain knowledge; human accepts it
├── jig-accept/               # decide pending proposals with a human
├── jig-task/                 # create/open a task, classify, choose workflow
├── jig-analyze/
├── jig-implement/
├── jig-review/
├── jig-verify/
├── jig-consolidate/
└── jig-architecture-review/
```

`jig-init`, `jig-map` and `jig-accept` sit outside the task routes: they populate knowledge rather than change code. `jig-init` writes the three global documents; `jig-map` proposes per-domain knowledge as `proposed` documents (§8.1) and stops at its own human gate. Neither runs as part of a task route, because a judgement about someone else's codebase deserves its own approval.

`jig-accept` is the other side of that gate, and a separate skill because the decision is deliberately allowed to outlive the session that proposed: `jig knowledge proposed` enumerates what is waiting, the skill presents each proposal with its body and its evidence, and `jig knowledge accept` / `jig knowledge reject` apply the answers in one all-or-nothing call each. Rejecting sets `status: rejected` and leaves the document at its path — it stops resolving, but the next map to propose the same domain can see the argument was already had (ADR-0018). The human is never asked for a document id; that is the skill's job to translate.

`jig-task` is the entry point and the only router: it classifies the work against the rubric in `skills/jig-task/references/classification.md` and names the route (§17). Every other skill performs one stage and can also be invoked directly when the user already knows which stage they want. Human gates for T3 and T4 are full stops inside `jig-task`; approval must be given for that design, in that conversation. Re-classification with `jig task set <id> class Tn` is a normal event, not a failure (ADR-0009).

Requirements for a skill:

- vendor-neutral markdown; runtime specifics only in frontmatter, which the adapter rewrites;
- **short**: describes judgment and the order of actions, delegates mechanics to `.ai/scripts/jig …`. The whole skill set is a few hundred lines; anything longer means mechanics leaked in;
- starts with `jig context`, not with its own repository traversal;
- does not contain generic best practices — those belong to profiles and `.ai/knowledge/`;
- substance that would bloat a skill goes to `references/` next to it, loaded only when that skill runs.

## 29. Scripts

`.ai/scripts/jig <command>` is the single entry point:

```
init                      idempotent project bootstrap
upgrade                   update scripts/skills/profiles from the framework, without touching files changed by the user
status                    summary: active tasks, housekeeping flags, version
task new <id> [--class T?] [--from <file>]  create workspace + state + task.md
task set <id> <k> <v>     write a state field (class, status, knowledge_consolidated, domains)
task abandon <id>         status → abandoned
task pause <id> [--reason <t>] [--stash]   dormant; --stash records the stash SHA
task resume <id>          clear the pause, apply the stash, report the gap
task list [--all] [--status <s>]   live tasks by default; finished ones are counted
task show <id>            print the state file
task current              the one candidate for this branch; exit 2 lists several
task changes <id> --base <ref> [...]   inventory committed/staged/unstaged/untracked layers
task artifacts <id> [--provided <kinds>]  report fixed-route documentary inputs
context [...]             §26
verify [--profile <p>]    run checks from active profiles, return a combined exit code
knowledge check           frontmatter validation, broken links, duplicate ids, documents without an owning path
knowledge new <type> <slug>  instantiate a feature/adr/convention template, allocating the next ADR number
knowledge paths [...]     report the gap between documents' `paths` and the files a task touched; `add`/`remove` a glob
knowledge stages add|remove <id> <stage>  maintain additive stage relevance
knowledge stale [--strict]  documents that drifted away from the code they describe (§19.1)
knowledge reviewed <id>   stamp `reviewed_at` on a document reconciled with the code
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

A project activates several profiles (`.ai/config.yaml: profiles: [php, laravel]`). `jig verify` sequentially calls `verify.sh` for each active profile. `generic` is always active.

### Scope (ADR-0013)

`jig verify --changed [--base <ref>]` narrows the run. The changed-file list — staged, unstaged and untracked — is computed once and passed to profiles through two environment variables:

| Variable | Meaning |
|---|---|
| `JIG_VERIFY_SCOPE` | `changed` when a scope is active; unset otherwise |
| `JIG_VERIFY_FILES` | path to a file listing the changed paths, one per line, repo-relative |

Mapping those files onto checks is the profile's job: filter syntax differs per stack, a file list does not. A profile opts in by declaring `scope: [changed]` in `profile.yaml`; one that does not declare it is run with both variables unset and reported as having ignored the scope. A profile that cannot narrow safely runs its full set and says so; a supporting profile with nothing to do reports `skip`, never `pass`.

`--changed` is for iteration. The evidence that a task is done is an unscoped run.

## 31. Runtime Adapters

MVP: Claude Code, Codex.

An adapter is responsible only for integration:

- where to copy skills (`.claude/skills/`, `.codex/skills/`) and how to transform them (frontmatter, call syntax `/jig-task` ↔ `$jig-task`);
- *offering* the session hook for housekeeping — printing the entry the user adds themselves, and reporting whether it is present. The adapter never writes the runtime's own config file (ADR-0024), and says so plainly when its runtime has no session hook at all;
- generating runtime instructions (`CLAUDE.md` = `@AGENTS.md`; for Codex, `AGENTS.md` is read directly).

SDLC logic stays in skills and scripts. Installed files are committed — the whole team works in a single environment.

## 32. Init and Upgrade

`jig init`:

1. determine the repository root;
2. determine the technology stack, suggest profiles;
3. create `.ai/` and missing knowledge templates;
4. copy scripts, profiles, skills for the chosen adapters;
5. create `AGENTS.md`, `CLAUDE.md`;
6. configure `.gitignore`;
7. write `.ai/manifest` (framework version + hashes of installed files);
8. print where the scheduling examples live — advisory only: `init` never prompts, so it stays usable in CI and in an agent session;
9. **do not overwrite existing knowledge**.

`jig upgrade` compares three things for every framework-owned path: whether the file exists in the new framework version, whether it is listed in `.ai/manifest`, and whether the local hash still equals the manifest hash.

| In new version | In manifest | Local hash | Action |
|---|---|---|---|
| yes | yes | = manifest | replace, update hash |
| yes | yes | ≠ manifest | **keep**, report `modified`, leave manifest hash unchanged |
| yes | no | file absent | install, add to manifest |
| yes | no | file present | **keep**, report `conflict` |
| no | yes | = manifest | delete, remove from manifest |
| no | yes | ≠ manifest | keep, report `orphaned-modified` |

The same principle as housekeeping applies: when in doubt, do not touch. `jig status` lists `modified` and `conflict` files so divergence from the framework is visible rather than silently accumulating. Both `init` and `upgrade` are idempotent.

`jig status`'s `drift: <m> modified, <x> missing, <p> pending` line reports two distinct kinds of gap. `modified`/`missing` walk paths already recorded in `.ai/manifest`; `pending` is the count of framework-owned items — a skill, profile or adapter file added to the source since the project's last `upgrade` — that `jig upgrade` would install or link right now. The two cannot be merged: a path is only ever in the manifest once `init` or `upgrade` has placed it, so a newly added skill is invisible to `modified`/`missing` even though it is exactly what `jig upgrade` exists to catch up on — and in link mode the manifest carries no path lines at all, leaving `modified`/`missing` at zero no matter how far behind the project has drifted. `pending` is computed the same way `jig upgrade --dry-run` reports its own pending actions, without mutating anything. When the framework source root cannot be resolved (e.g. a copy-mode install whose source checkout no longer exists on this machine), pending state is unknown rather than zero, and the field is omitted from the line entirely.

`jig verify` refuses to run any profile at all while framework files are pending: a pass computed against a stale install is not evidence of anything. It reports one line per pending path plus `FAIL framework: <n> framework files not installed (run jig upgrade)` and exits non-zero, before touching the profile loop (`--list` is unaffected — it only reports installed/not-installed, it runs nothing). As with `status`, an unresolvable source root degrades to "unknown" rather than a failure: verify proceeds to run the profiles normally.

Activating a profile or adapter later is a config edit followed by `jig upgrade`: on a re-run, `init` and `upgrade` take `profiles` and `adapters` from `.ai/config.yaml` unless flags are given, and flags that differ from the config rewrite those two lines. In link mode `upgrade` creates any missing symlinks instead of copying.

`init` also prints profiles it detected but did not install (`suggested profiles: ...`); it never changes the selection on its own, so a re-run stays predictable.

## 33. Open Questions

Unresolved; do not block Phase 1–2.

- **Git worktrees** and **concurrency**: resolved in Phase 2 by ADR-0008. A workspace belongs to the checkout it was created in; `state` is written atomically with last-write-wins semantics and no lock.
- **Metrics §40 (0.3).** Require telemetry that does not exist. Deferred to Phase 6; MVP has only qualitative assessment.
- **External artifact storage** for regulated environments — optional backend, not in MVP.
- **Session hook installation** — resolved in Phase 5 by ADR-0024, and not as this question proposed. Merging a tagged entry into `.claude/settings.json` would mean editing arbitrary project-owned JSON with no JSON parser available (ADR-0002 allows only `git`), risking a file jig cannot rebuild. Instead the hook logic lives in a framework-owned script, the adapter prints the one line that names it, and a human pastes it. `jig status` reports whether it is installed by a read-only substring test.

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
| 1 — Knowledge Harness | `init`, `upgrade`, manifest, knowledge templates + frontmatter, `knowledge check`, `AGENTS.md`, Claude + Codex adapters, `jig-init` skill |
| 2 — Workspace & Context | `task new/set/abandon`, state, `context`, profiles, `verify` |
| 3 — Adaptive SDLC | `jig-task` with classification, stage skills, human gates |
| 4 — Consolidation | `jig-consolidate`, feature knowledge, ADR candidates, `paths` maintenance, stale knowledge detection |
| 5 — Lifecycle Automation | forge detection, ancestry fallback, housekeeping, trash, session hook, scheduler templates |
| 6 — Measurement & Evolution | benchmarking, cost measurement, knowledge quality |

## 37. Final Lifecycle

```
                    TASK
                      │
                      ▼
          jig-task: classify → workflow
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
