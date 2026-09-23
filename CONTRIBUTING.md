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

### Which `jig` you are running

There are two, and they are never the same files:

- **`.ai/scripts/jig`** — this checkout's own. The link is committed (Git stores it as a symlink,
  not a copy) and it is relative, `.ai/scripts -> ../scripts`, so every `git worktree` resolves it
  inside itself. A worktree therefore runs **its own branch's** scripts, which is what makes it safe
  to develop a command and test it in the same working copy.
- **`jig` on `PATH`** — the release. `install.sh` clones it into `~/.local/share/jig` and links
  `~/.local/bin/jig` to it, so `which jig` answers with the link. Either way it resolves its own
  location and loads the libraries sitting next to it, and it never redirects a call into a
  project's `.ai/scripts`. Run it in this repository and you are testing the release against your
  branch's files — occasionally what you want, and never what you meant while debugging a change.

So in this repository, call `.ai/scripts/jig`. That is why the skills spell the path out wherever
they hand over a command to run, rather than the shorter `jig`. Prose that merely names a command —
in `AGENTS.md`, or in a skill's explanation — says `jig task set …` and means the same executable.

If typing the path grates, a wrapper in `~/.zshrc` (or `~/.bashrc`) picks the project's copy when
there is one and the release otherwise. It is a personal convenience, not something Jig installs or
expects:

```bash
jig() {
  local dir=$PWD
  while [ -n "$dir" ]; do
    if [ -x "$dir/.ai/scripts/jig" ]; then
      "$dir/.ai/scripts/jig" "$@"
      return
    fi
    dir=${dir%/*}
  done
  command jig "$@"
}
```

`command jig` then still reaches the release, which is how you ask for it deliberately.

### `jig upgrade` and which source it copies from

`jig upgrade` needs a framework checkout to install from, and the two executables find one
differently. The release on `PATH` brings its own: `~/.local/bin/jig` is a symlink and gets resolved,
so it lands in `~/.local/share/jig`. A project's `.ai/scripts/jig` cannot do that — the path it
resolves to stays `<project>/.ai/scripts`, whose parent is not a framework checkout — so it falls
back to the source recorded in `.ai/manifest`.

- **Here, your own `.ai/scripts/jig upgrade`.** This repository's manifest records `jig.source: .`,
  itself, so the upgrade refreshes the links from the checkout you are working in. That is what you
  want, and the release on `PATH` would not do it.
- **In an ordinary project, either, with one catch.** The manifest names the checkout whoever
  installed it used. When that path still exists, `jig self-update` moves it to the new release and
  the project's own `.ai/scripts/jig upgrade` picks it up from there. When it does not — a
  teammate's clone, a checkout since moved — the local one stops with `cannot determine the
  framework source root`. `command jig upgrade` gets you out of that, because it brings its own
  source and records it on the way.

Calling the wrong one is not destructive. In link mode every framework path is a symlink the release
did not create, so it meets `keep-conflict` on all of them, places nothing, leaves `.ai/manifest`
untouched — and ends by saying exactly that:

```text
jig upgrade: 0 placed, 0 kept, 27 conflict(s); manifest unchanged
nothing was placed from /home/you/.local/share/jig, so this project stays installed from /home/you/src/jig
hint: to install it from that checkout instead, run `jig init --link --from /home/you/.local/share/jig`
```

That hint is the real way to move a project to another checkout: choosing where a project's framework
comes from is an install decision, and `upgrade` only carries an existing install forward. An upgrade
that places files from a new source records it; one that placed nothing changes nothing — not the
files and not the manifest. So a project whose recorded checkout has gone keeps pointing at it
whenever there was nothing to place: because its files already match the new source, or because they
are symlinks the upgrade did not create. Then `jig init --from <dir>` (with `--link`, in link mode)
is the way out, and the command prints that line itself.

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
