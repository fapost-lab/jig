# Project hooks — a project binds its own rules to the route

Depth: normal — the command half runs project code and adds a new way to refuse completion;
both carry a cost of being wrong, but the design space is small.

## Idea

About hooks in Jig. The idea is good, and today's case shows well what is missing. Right now a
project has only one way to influence the process: document metadata (`paths`, `domains`,
`stages`, `load`). We have already hit two of its limits: `stages` does not work without a
domain, and `load: always` loads a rule at every stage.

I would make hooks of two kinds, declared in the project's `.ai/config.yaml`:

1. Knowledge hooks: a document to a stage, unconditionally.

   ```
   stages:
     consolidate:
       require: [convention-published-docs-updates]
   ```

   The document is handed out exactly at the needed stage of every task, without the
   `load: always` trick and without being tied to domains. It is a small extension of the
   existing stage mechanism.

2. Command hooks: a deterministic check at a stage. On the same principle as `jig verify`
   runs profile scripts:

   ```
   hooks:
     consolidate:
       - run: .ai/hooks/docs-site-check.sh
   ```

   The script can check, for example: files changed in `packages/fapost-foundation`,
   `database/migrations` or `.env.example`, while `docs/site` is untouched and `task.md` has no
   `Docs:` line — then warn. This is enforcement, not a reminder. And it fits Jig's principle
   "scripts never call the model".

Why this is convenient for different projects. Jig itself knows nothing about Mintlify or
docs.fapost.in. Each project declares its own rules in its own config, `jig upgrade` does not
touch them, and a project without public documentation simply does not declare such a hook.

It is usually better to start with the first kind: it is cheap and closes today's problem. The
second is a separate, larger feature: with it Jig starts executing project code, so one has to
think through when a hook blocks work and when it only warns.

*(Translated from the human's Russian, 2026-09-21.)*

## Goal and problem

- Who is worse off without this, and how: a project with a rule that belongs to one stage —
  "a change to the public API updates the published docs" belongs to consolidation. Today it
  either rides `load: always` and costs context at every stage, or needs a domain it has no
  natural claim to, because `stages` promotes only inside an entered domain (ADR-0021). And
  whether the agent followed the rule is invisible to every script: the rule is a request to a
  model.

  The case that started this, from a project that uses Jig — the rule rides `load: always`
  with no domains and no paths, so it is required at every stage of every task:

  ```
  ---
  id: convention-published-docs-updates
  type: convention
  status: active
  domains: []
  paths: []
  load: always
  summary: When a task must update docs.fapost.in, and what counts as too small to edit
  ---
  ```
- What is true when the work is done: a project document can say "I am required at stages X",
  and resolution hands it over at exactly those stages of every task, no domain needed. A
  project can declare its own scripts at the completion gates; a script's non-zero exit refuses
  the gate the way an open P0 finding does, and a human can waive it for one task with a reason
  that stays in the task.

## Stress test

- Hidden assumptions — "this holds only if …":
  - Config-side binding holds only if applicability may have two sources. ADR-0004/0014 say
    metadata is the only authority ("a document declares how it should be loaded"). The
    argument for the config — "Jig knows nothing about Mintlify, the project declares it" —
    holds equally for metadata: `.ai/knowledge/` is the project's and `jig upgrade` never
    touches it. So the knowledge hook moved into metadata.
  - "A hook at a stage" is enforcement only if a script can see the stage. It cannot: a stage
    is a skill, i.e. model behaviour. The deterministic points are commands —
    `jig context resolve --stage` and the completion gates (`task set status ready`,
    `task set knowledge_consolidated true`, `task ship`), where the findings and receipt checks
    already live. A hook fired on "entering a stage" runs only if the model ran the command:
    a reminder again. So command hooks bind to gates.
  - The nested YAML in the idea holds only with a nested parser. `.ai/config.yaml` is a flat
    subset — `section.key: value`, inline lists, no nesting. The flat form is
    `hooks.consolidate: [.ai/hooks/docs-site-check.sh]`.
- The main trade-off: enforcement against getting stuck. A blocking hook is a real stop — and a
  wrong or broken hook stops every task in the project. Answered by a per-task waiver with a
  recorded reason.
- The weakest point: gates run locally, in a workspace. CI has no workspace, so a hook never
  runs there; a contributor who never calls `knowledge_consolidated true` never meets the hook.
  The hook guards the Jig route, not the repository.
- Failure modes — cause, what breaks, the signal that shows it:
  - Hook script missing or not executable after a rename → every gate refuses. Signal: the
    refusal names the missing path, and `jig status` / `jig doctor` report it before the gate.
  - Hook hangs (waits on network, prompts for input) → the gate never returns, autopilot
    stalls. Signal: none today — see open questions (timeout).
  - Hook depends on the model-written `task.md` (a `Docs:` line) → the agent writes the line to
    pass. Signal: none mechanical; the waiver and the line are both visible at review. A hook
    should prefer facts from the diff over claims in prose.
  - `load: stage` document with no `stages` → never loaded. Signal: `jig knowledge check` fails
    it.
- Other shapes considered, and why this one:
  - Config `stages.<s>.require` — rejected, see Decisions.
  - Hooks fired by `jig context resolve --stage` — rejected: a reminder, not a stop.
  - A project check inside `jig verify` — rejected for now: it would run in CI too, but
    `jig verify` is task-agnostic (adr-20260921-review-findings-block-completion) and cannot
    see the task, and profiles are framework-owned. Kept as an open question.
  - Warnings only in the first version — rejected: it is the reminder the idea set out to
    replace.

## Scope and non-goals

- In scope:
  - `load: stage` in knowledge frontmatter, with resolver, `knowledge check` and docs.
  - `hooks.ready`, `hooks.consolidate`, `hooks.ship` in `.ai/config.yaml`; run at their gates;
    exit-code contract; per-task waiver with a reason; reporting of misconfigured hooks.
- Not doing:
  - Hooks on stage entry or on any command other than the three gates.
  - Hooks in CI or in `jig verify`.
  - A config-side document-to-stage binding.
  - Shipping any concrete hook (docs-site check and the like) as framework-owned: a hook is the
    project's. The docs may show one as an example.
  - Hooks that call a model. A hook is a script; ADR-0001 stands.

## Decisions

- **The knowledge hook is metadata: `load: stage`.** A document with `load: stage` and
  `stages: [consolidate]` is required at exactly those stages of every task, whatever domains
  are entered, and is otherwise neither required nor in the catalog. It does not contradict
  ADR-0021's "stages are additive, never intersect": that rule protects documents from being
  hidden by a stage filter; here the author opts the document into stage-only loading.
  — rejected: `stages.<stage>.require` in `.ai/config.yaml`, because it gives applicability a
  second source against ADR-0004/0014, and its one advantage — every binding in one place — is
  a listing `jig knowledge` can print.
- **Command hooks bind to the completion gates**, not to stages: `hooks.ready` runs in
  `task set <id> status ready`, `hooks.consolidate` in `task set <id> knowledge_consolidated
  true`, `hooks.ship` in `task ship`, after the findings and receipt checks. Keys are inline
  lists of project-relative script paths, in the flat config format.
  — rejected: firing on `jig context resolve --stage`, because it runs only if the model calls
  it; a `jig verify` check, because verify cannot see the task.
- **The exit code decides.** 0 passes the gate, and anything the script printed is shown as a
  warning. Non-zero refuses the gate; the refusal names the hook and shows its output. There
  is no warn/block mode in the config.
  — rejected: `warn`/`block` lists in the config, because the script already knows what is
  serious, and two lists per gate double the keys for no new power; warnings-only in v1,
  because it is a reminder again.
- **A refusal can be waived for one task, with a reason**, recorded in the task's workspace like
  a dismissed finding and shown by `jig status` and in the pull request body. Autopilot never
  waives: a hook refusal is one of its stops.
  — rejected: no waiver, because one broken hook would stop every task in the project; removing
  the hook from the config, because it leaves no trace in the task.
- **Hooks are a project key only.** `hooks.*` is read from `.ai/config.yaml`, never from
  `.ai/config.local.yaml` (ADR-0038): a hook is a team rule, and a clone must not switch it off
  silently. The waiver is the one visible way around it.
- **What a hook receives** (reversible, taken by the agent at normal depth): cwd is the task's
  checkout; environment `JIG_TASK_ID`, `JIG_TASK_DIR` (its workspace), `JIG_GATE`
  (`ready|consolidate|ship`), `JIG_BASE` (the task's base, ADR-0039). The changed-file list is
  the hook's to compute against `JIG_BASE`, so Jig passes no file protocol it would then have
  to version.
- **This needs ADRs**: one for `load: stage` (amends ADR-0014/0021), one for command hooks
  (Jig executes project code at a gate; lifecycle and safety semantics).

## Open questions

- Timeout: bash 3.2 has no portable `timeout`. Does a gate need one (a background process and
  a watchdog), or is a hung hook the project's problem? Autopilot's "never hangs" depends on it.
- How is a hook invoked on Windows (ADR-0037): by path with its shebang, or always through
  `sh <path>`? The second avoids the executable bit, which Git on Windows does not keep.
- Should a waiver go stale like a review receipt when the code changes after it?
- A project check in `jig verify` that runs in CI too — a separate feature, or a later phase of
  this one? It needs project-owned checks, which profiles do not allow today.

## Assumptions left untested

- `load: stage` is enough for today's case (published-docs rule at consolidation) — taken at
  normal; test: change `convention-published-docs-updates` from `load: always` to
  `load: stage` with `stages: [consolidate]` in the project that hit the problem, and resolve `--stage consolidate` and `--stage implement` for one task.
- Running project scripts at a gate adds no trust a project did not already give: the same
  project's tests run in `jig verify`, and nothing runs until a human or their agent calls the
  gate — taken at normal; test: the command-hook ADR's safety section.
- Three gates are the right points; nobody needs a hook at `review` or `verify` — taken at
  normal; test: ask again after the first project declares hooks.
