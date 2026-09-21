---
id: adr-20260921-routing-evals-score-descriptions-lexically
type: adr
status: accepted
date: 2026-09-21
domains:
  - skills
  - verify
paths:
  - tests/routing.sh
  - tests/routing.t.sh
  - "tests/routing/**"
  - "skills/*/SKILL.md"
summary: Why skill descriptions are checked by prompt cases scored on weighted word overlap in the test suite, not by a model, and how a changed description reaches those tests locally and in CI.
reviewed_at: 2026-09-21
---
# Routing evals score prompt cases against skill descriptions by word overlap, in the test suite

## Context

A runtime picks a Jig skill by reading the skill descriptions. Nothing checked that two
descriptions do not claim the same requests, or that a reworded description still says enough to
be picked, and a description is prose that reads as documentation: `*.md` reaches no test in
`jig verify` and puts CI in its light scope, so the one change that can break routing ran nothing.
The autopilot spec (Phase 5) asked for prompt cases per skill scored by a shell script in `tests/`
and run in CI, with the test that a deliberately vague description fails. Its open question — a
live model run, worth a key and a cost? — stays open.

## Decision

- **Cases are data under `tests/routing/<skill>.cases`**, one prompt per line: `+ <prompt>` the
  skill must win, `- <prompt>` it must not (usually a neighbour's request). Every skill needs a case
  file with at least one of each, and every case file needs a skill; either gap fails the check.
- **`tests/routing.sh` scores lexically and deterministically**: lowercased words, stop words
  dropped, crude stemming; a prompt scores against a description the weight of each distinct shared
  word, N/df over the descriptions (a word every description uses decides nothing), plus the words
  of every phrase the description quotes that appears in the prompt once more. Weights are integers
  (`N*1000/df`), so equal sums are equal on every awk. Only the description is scored, never the
  skill's name.
- **Winning is strict**: `+` holds when the skill alone scores highest, above zero; `-` fails when
  the skill scores above zero and highest, including a tie for the lead. A tie is an overlap, and an
  overlap is what the check exists to find.
- **It runs as `tests/routing.t.sh`**, part of `tests/run.sh` and therefore of every full CI run.
  This repository's verify map sends `skills/*/SKILL.md` and `tests/routing/**` to `routing::`, so
  a changed description runs the evals under `jig verify` and makes CI's scope full.
- It checks the framework's own skills. `tests/` is not installed into projects, so a project's
  own skills are not evaluated.

## Alternatives

- **A live model run** — rejected for now: needs a key and network, costs money per run and is not
  deterministic, against ADR-0001 and ADR-0002 for anything in the suite. It says more about what a
  model picks; if it is ever wanted it is a second, opt-in half, not a replacement.
- **Plain word overlap without weights** — rejected: "task", "jig", "use", "change" appear in most
  descriptions and decide ties at random.
- **Cases inside each skill directory** — rejected: `skills/` is installed into every project, and
  the cases are a development test of the framework, not part of a skill.
- **A new CI job for the evals** — rejected: `tests/run.sh` already runs on every full CI run on
  three platforms; the gap was the scope decision, which the map line closes.

## Consequences

- A description reworded into vagueness or into a neighbour's territory fails CI with the case, the
  winner and the scores named.
- The check is a floor, not a prediction: a model can still pick differently, and paraphrases with
  no shared words are out of its reach. Prompts in another language than the descriptions cannot be
  scored.
- A new skill is not finished until it has a case file; a lost case is fixed in the description
  first and in the case only when the prompt was ambiguous.
