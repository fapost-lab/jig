# Contributing to Jig

This repository is the framework and also uses it: Jig is developed with Jig. Read
[AGENTS.md](AGENTS.md) — the instructions every agent here follows — and the durable knowledge it
points to before changing framework behaviour:

- [`.ai/knowledge/GLOSSARY.md`](.ai/knowledge/GLOSSARY.md) — canonical terms;
- [`.ai/knowledge/RULES.md`](.ai/knowledge/RULES.md) — invariants that must not be violated;
- [`.ai/knowledge/adr/`](.ai/knowledge/adr/) — accepted decisions; propose a new ADR rather than
  silently contradicting one.

User documentation is the [site](https://jig.fapost.in); its sources are in [`docs/`](docs/).

## Working rules

- `main` accepts changes only through pull requests.
- Work starts with the `jig-task` skill, which classifies it by risk and names the route. Task notes
  live in `.ai/workspace/tasks/<id>/`, which is ignored; lasting intent goes to `.ai/knowledge/`.
- A decision that changes architecture, distribution, lifecycle semantics or the safety of a
  destructive operation gets an ADR, named `YYYYMMDD-<slug>.md`, created with
  `jig knowledge new adr <slug>`.
- Scripts are POSIX sh / bash 3.2 with no dependency but Git (ADR-0002). Every script command has a
  test under `tests/`. Skills stay short; mechanics go to scripts (ADR-0001).
- Everything that leaves the machine — code, comments, knowledge, skills, documentation, commit
  messages — is written in English.

## Link mode

A normal project copies Jig in, so the whole team shares a committed version. This repository
installs itself in **link mode** (`jig init --link`): scripts, profiles, templates and skills are
symlinks into the checkout, so a change takes effect immediately. On Windows, link mode needs
Developer Mode for real symbolic links.

Adding or renaming anything framework-owned — a skill, a profile, a template — is not finished until
`jig upgrade` has placed it: until then a new skill exists in `skills/` but not in `.claude/skills/`
or `.codex/skills/`. `jig verify` refuses to run while anything is pending.

## Tests

```bash
bash tests/run.sh                  # everything, in parallel, one job per CPU
bash tests/run.sh knowledge::      # one file's tests
bash tests/run.sh knowledge::test_reject
.ai/scripts/jig knowledge check
```

`JIG_TEST_JOBS=1` runs the tests one at a time, or sets another width. `JIG_TEST_SHARD=2/3` runs every
third test starting with the second, so a slow platform can split the suite across machines.
`JIG_TEST_SKIP=file::test,...` reports the named tests as skipped.

Run `shellcheck` on every changed shell file, tests included; CI runs an older ShellCheck that can
flag what a newer local one lets through.

This repository sets `verify.full_run: ci`: a plain `jig verify` checks what changed, through
[`.ai/verify/shell.map`](.ai/verify/shell.map), and CI runs the full set on every pull request.
`tests/install.t.ps1` runs only on Windows CI.

Documentation changes: in `docs/`, run `npx mint broken-links` and `npx mint validate` (Node is a
maintainer tool here, not a dependency of Jig).

### Routing evals

A runtime picks a skill by its `description:`, so the descriptions have tests of their own.
`tests/routing/<skill>.cases` holds prompts the skill must win (`+ <prompt>`) and prompts it must not
(`- <prompt>`, usually a neighbour's); `tests/routing.sh` scores every prompt against every
description and prints one `ok`/`FAIL` line per case with the scores that decided it:

```bash
bash tests/routing.sh              # the report
bash tests/run.sh routing::        # as part of the suite, which is how CI runs it
```

A prompt is won by the one skill whose description shares the most words with it, each word
weighted by how few descriptions use it, with a phrase the description quotes (`"review"`) counting
once more. It is word overlap, not a model: no key, no network, the same answer everywhere.

- A new skill needs a case file with at least one `+` and one `-` line, or the check fails.
- A changed description runs these tests locally and in CI (`.ai/verify/shell.map` routes
  `skills/*/SKILL.md` to `routing::`). When it loses a case, reword the description before the case;
  change the case only when the prompt was ambiguous in the first place.
- Write most prompts as a user would ask them rather than copying the description's quoted phrases:
  a case that only repeats the description proves little.

## Releases

Raise `JIG_VERSION` in `scripts/lib/version.sh` in the pull request that should become the release:
`major.minor.patch` without leading zeros — patch for a fix, minor for a new capability, major for a
change that breaks commands, the `.ai/` layout, `init`/`upgrade` or the installer (before `1.0.0`,
such a change raises minor). After the merge, CI runs the tests and tags `v<JIG_VERSION>` itself; a
merge that leaves the version alone creates nothing, and a version lower than the latest release
fails the job. Nobody tags by hand (ADR-0034).

A release that changes installation on Windows also goes through
[`.github/WINDOWS_RELEASE_CHECKLIST.md`](.github/WINDOWS_RELEASE_CHECKLIST.md).
