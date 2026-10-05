---
id: adr-20261005-jig-names-the-roles-not-the-models
type: adr
status: accepted
date: 2026-10-05
domains:
  - config
  - skills
  - task
paths:
  - scripts/lib/config.sh
  - scripts/lib/task.sh
  - skills/jig-task/references/delegation.md
  - skills/jig-setup/SKILL.md
  - skills/jig-autopilot/SKILL.md
summary: Why the model a stage is handed to lives in two local-only, runtime-named keys (claude.implement_model, claude.review_model) carried as opaque strings, why roles are route stages, why empty means no delegation, and why jig task route names it while no gate reads it.
---
# Jig names the roles a stage can be handed to; the model in a role is the person's, carried as an opaque string

## Context

The route already names who does what: a review "in a fresh context" by a subagent that has not
seen the implementation (`jig-review` for T4, `jig-autopilot` for every review). It never named on
which model, so the subagent ran on the session's. The maintainer of this repository runs a
further practice by hand, in a personal instruction file: the session plans and decides, and
hands implementation and review to subagents on a cheaper model. The people Jig is for will not
write that instruction file or `.claude/agents/*.md`; the guard rails that make a cheaper executor
safe — findings that block (adr-20260921-review-findings-block-completion), a receipt that goes
stale, verify that asks for evidence — the framework already has. What was missing is a place to
say which model, and a way for the stage skills to read it.

The answer differs between people: it depends on their plan, runtime and budget, and there is no
right answer for a project. That is the test `agent.git` and `route.depth` failed for the project
file (ADR-0038, adr-20260921-agent-git-rights-are-a-local-setting,
adr-20261002-route-depth-is-a-personal-choice). ADR-0023 kept the agent's language out of
configuration because its only consumer is a model reading text; the same is true here, but the
other homes are closed: the value is personal, so `AGENTS.md` is wrong, and a runtime's own files
(`CLAUDE.local.md`, `.claude/agents/`) are files Jig does not write (ADR-0024), so `jig-setup` could
ask the question and have nowhere to put the answer.

## Decision

- **Two local-only keys, `claude.implement_model` and `claude.review_model`,** in
  `JIG_CFG_LOCAL_KEYS` and `JIG_CFG_LOCAL_ONLY_KEYS`. A value in `.ai/config.yaml` is ignored and
  reported, as for every local-only key.
- **Roles are stages, not difficulty.** Jig has no "simple" or "medium"; it has a route. `implement`
  is the implement stage; `review` is every review stage of a route — review, a T4's independent
  review and a T3/T4's architecture review — because they are one role: a reader who has not seen
  the implementation, who enters findings and writes the receipt. Discovery, design, the gate,
  verify, consolidation and ship are judgement or sign-off and are never handed over.
- **The key names its runtime.** `sonnet`, `opus`, `haiku` and full model ids are Claude Code's
  vocabulary, so the keys carry the adapter's name, `claude.`; another runtime ignores them and does
  the stage itself. No `codex.*` keys until a runtime has something to read them. The scripts hold the
  key's name and nothing else about the runtime — no list of models, no call to it — so this is not
  vendor knowledge outside an adapter (ARCHITECTURE.md, adapter contract): what a value means is
  said only in skill prose, which the runtime reads.
- **The value is opaque.** Jig never compares it with a vendor's list — it cannot, and the list
  would go stale. `jig config set` applies only what the file format needs (not empty, no line
  break, no `#`, no surrounding blanks). A flat scalar is what ADR-0002 lets the shell carry.
- **Empty is off.** No default model: unset, `cfg` answers nothing and nothing is printed, so a clone
  that never heard of the keys runs exactly as before. The project-file inventory shows the
  empty default as `-`.
- **A script names, a skill acts.** `jig task route <id>` prints one
  `delegate: <stage> -> <model> (<key>)` line per set key whose stage is in the task's route — no
  review line for T0 and T1. `_task_route_delegates` is the one reader; no gate reads it.
- **One reference for every stage.** `skills/jig-task/references/delegation.md` says what a
  `delegate:` line means — a subagent with that value as its `model`, the stage's skill run whole by
  the subagent, the implementer and the reviewer never the same — and what happens without one; the
  stage skills point to it in a line each. `jig-setup` asks one question for both keys.
- **No actor record.** Which model did a stage is not written anywhere: a field the actor writes
  about itself is self-certification (adr-20261004-a-route-stage-is-proven-by-its-record), and the
  records that hold the route — the ledger, the receipt, verify's sign-off — do not depend on who
  wrote the code.

## Alternatives

- **Agent definitions in `.claude/agents/` installed by the adapter as framework-owned files.** They
  would carry the model and could restrict a reviewer's tools. Rejected: their content would depend
  on the local setting, so the manifest hash would differ in every clone and `upgrade` could no
  longer tell a person's edit from Jig's own. The Agent tool takes a model per call, which removes
  the need for a file. Tool restriction stays a later, separate change.
- **Prose in `CLAUDE.local.md` or `AGENTS.md`.** The first is a runtime file Jig does not write
  (ADR-0024), so no skill could ask for the value and store it; the second is committed and would
  pick one person's model for everyone.
- **Roles by difficulty (`simple`, `medium`).** A second classification beside the class, with no
  test to apply it by; the route already names the roles.
- **A key name that claims to be portable (`delegate.review`).** Its values are one runtime's names;
  a Codex session reading `sonnet` could do nothing with it.
- **Validating the name against known models.** Jig cannot know them all, and a list in a shell
  script would refuse tomorrow's model.
- **A project key.** A committed model spends every contributor's budget on one person's choice.
- **A third key for architecture review.** One role, one key; a key can be added later without
  breaking either.

## Consequences

- A person who answers one `jig-setup` question gets the practice of delegating by model with no
  instruction file of their own; one who answers nothing sees no change.
- A name Claude Code does not know reaches the Agent call and is refused there; the skill says so
  and does the stage without the model. That is the cost of an opaque value, and it lands on the
  person who wrote it, at the first stage that reads it.
- Undoing it: remove the two keys from the lists and the inventory, `_task_route_delegates`, the
  reference and the skill lines. A leftover key in someone's local file is reported as `ignored:`
  and removed with `jig config unset`.
