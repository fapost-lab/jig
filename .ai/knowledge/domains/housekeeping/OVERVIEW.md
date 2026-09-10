---
id: domain-housekeeping
type: domain
status: active
summary: "Unattended, LLM-free end of a task's life: remote state, the SPEC §23 policy, two-stage purge, and the triggers."
domains:
  - housekeeping
topics: []
load: domain
paths:
  - scripts/lib/housekeeping.sh
  - scripts/jig-session-hook
  - "templates/scheduler/**"
---
# Housekeeping

Ending a task's life without a developer and without an LLM. The domain is small, and
almost all of its difficulty is in one property: it deletes things, unattended, on
evidence it inferred itself.

## Responsibility

- Deriving **Remote State** per task, in tiers: forge (`gh`/`glab`) → git ancestry →
  `unknown`. Derived every run, never written into a task's `state` (ADR-0005).
- Applying the lifecycle policy of SPEC §23 — a pure function of `status`, remote state,
  `paused` and age, which is why the whole table is testable without a repository.
- The two-stage **Purge**: move to **Trash**, delete only after `trash_ttl` (ADR-0006).
- The audit trail: `.ai/runtime/housekeeping.log`, one line per decision including
  `via=` (the deciding tier), and the `.ai/runtime/last-housekeeping` stamp.
- The **Session Hook** and the scheduler examples — triggers, both optional, neither
  installed automatically (ADR-0024).

## What governs it

Read these before changing anything here; each is a rule someone paid for.

- **Nothing is destroyed on `unknown`** (RULES.md, SPEC §23). Every uncertainty in this
  domain must resolve *towards* `unknown`, never away from it.
- **No path is deleted or moved without validation** (RULES.md, ADR-0006). Use
  `task_dir`/`_task_valid_id` — the single choke point — and never transcribe a regex.
  ADR-0006's own text carried a wrong pattern for two phases; the code was right.
- **Ancestry answers "landed", not "open"** (ADR-0025), and a task whose branch *is* the
  base branch is `unknown`, because `--is-ancestor main main` is trivially true.
- **Exit 3 means "a human must consolidate"**; 1 is a real error, 2 belongs to
  `task current`. A trigger has to be able to tell those apart.

## Boundaries

Outside: what a `status` value *means* and who may write it — that is the `task` domain
(ADR-0005, ADR-0012). Housekeeping only reads `state`, and writes nothing into it.

Outside: which config file a runtime keeps its hooks in and what shape it has — that
belongs to the adapter (ADR-0024). This domain owns the hook *script*, not the runtime's
configuration.

Outside: installing `templates/scheduler/` — the `install` domain places it like any
other framework-owned tree. This domain only writes what goes in it.

The framework does not implement a scheduler (SPEC §34), and no script here ever calls
an LLM (ADR-0001).

## Entry points

- `scripts/lib/housekeeping.sh` — `cmd_housekeeping`, `housekeeping_decide` (the policy),
  `_hk_remote_state` and its tiers, `_hk_purge`, `_hk_trash_expire`.
- `scripts/jig-session-hook` — the trigger; always exits 0, by design.
- `tests/housekeeping.t.sh`; `fixture_merge_repo` in `tests/lib/assert.sh` builds the six
  merge topologies (fast-forward, merge commit, squash, rebase, open, deleted branch).

## Known gap

The GitLab tier has no test: `glab` was not available when it was written, and its
output is parsed with `sed` rather than a JSON reader (ADR-0002). Its failure direction
is safe — it falls through to ancestry and never fabricates `merged` — but it is
unverified against a real `glab`.
