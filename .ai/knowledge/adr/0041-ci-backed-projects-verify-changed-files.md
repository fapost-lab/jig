---
id: adr-0041-ci-backed-projects-verify-changed-files
type: adr
status: accepted
date: 2026-09-16
domains:
  - verify
  - profiles
paths:
  - scripts/lib/verify.sh
  - "profiles/**"
  - schemas/verify-map.md
  - ".ai/verify/**"
  - "skills/jig-verify/**"
  - tests/run.sh
summary: Why a project that declares CI runs the full set gets a flag-less jig verify narrowed to changes since the merge base, and why the files-to-checks map is the project's file, parsed by jig verify.
reviewed_at: 2026-09-18
---
# ADR-0041: A project whose CI runs the full set verifies by changed files, through a project-owned map

## Context

ADR-0013 made narrowing opt-in and ended with "the evidence that a task is done is an unscoped
run". In a project whose CI runs every check on each pull request, that local full run repeats
CI and adds no signal from checks the change cannot affect; on this repository it takes minutes,
and people interrupted it.

Discovery found four facts that shaped the answer:

- `--changed` without `--base` diffs against `HEAD`. Once a task's work is committed its list is
  empty and a supporting profile reports `skip`: "make `--changed` the default" would verify
  nothing after the first commit.
- Only the shell profile could narrow. php, laravel, node and go declare no `scope`, so a mode
  that relies on narrowing gives them nothing until they learn it (task
  `profiles-scope-and-languages`). The contract has to serve profiles written later.
- The shell profile's files-to-tests table was this repository's layout (`adapters/*`,
  `profiles/*`, the session hook), copied into every project that uses the profile. There it
  either ran everything or matched by accident.
- `tests/run.sh` reports `0 passed` and exits 0 for a filter that selects nothing. A narrowed
  run could pass without running a test — in any project with a `profiles/` directory, before
  this decision.

A committed config key is read by CI as well, so a project whose CI calls `jig verify` would
narrow the one run the key relies on.

## Decision

- **`verify.full_run: local | ci`** in `.ai/config.yaml`, default `local`, a project key (not in
  the local layer, ADR-0038). `ci` is the project's claim that CI runs the full set; no script
  checks it. Any other value is an error.
- **With `ci`, a flag-less `jig verify` narrows to what changed since the merge base with
  `git.base_branch`** — committed on the branch, staged, unstaged and untracked — through the
  ADR-0013 protocol unchanged. The merge base is resolved once and named in a header line
  (`verify: scope changed since origin/main@<sha> (verify.full_run: ci, full set runs in CI)`).
  With no merge base the working tree alone is used and the header says so. The base is the
  configured one, not the current task's: `verify` must work in projects without tasks, and for a
  branch cut from an epic the list is a superset — more checks, never fewer. `--base <ref>` works
  without `--changed` in this mode.
- **A full run is always reachable**: `--full`, or a non-empty `CI` environment variable, both
  named in the header. Explicit `--changed`/`--base` win over `CI`; `--full` with either is an
  error. `--changed` without `--base` keeps its meaning (against `HEAD`, for iteration). With
  `local` the output is unchanged.
- **A project map, `.ai/verify/<profile>.map`**: project-owned and committed, never created or
  touched by `init` or `upgrade`. Lines are `<glob> <decision>`; the first match wins; a decision
  is `-` (no check affected), `ALL`, or profile-specific filters; `-` and `ALL` stand alone; globs
  follow `detect`. Format: `schemas/verify-map.md`.
- **`jig verify` parses the map, never a profile.** A profile declaring the new capability
  `scope: [changed, map]` receives `JIG_VERIFY_MAPPED`, one `<path><TAB><decision>` line per
  changed file, `?` where no line matched. Every other profile has the variable unset (the
  ADR-0013 rule). A broken line fails that profile without running it, naming file and line. The
  core carries filter tokens without knowing what they mean.
- **A shipped profile holds only rules true for any project of its stack.** The shell profile
  keeps: documentation and knowledge affect no test; `tests/<x>.t.sh` → `<x>::`; `<x>.sh` →
  `<x>::` when `tests/<x>.t.sh` exists; a changed `.shellcheckrc` lints the whole tree; anything
  else runs everything. This repository's rows moved to its own `.ai/verify/shell.map`.
- **A narrowing that selects nothing is not a pass.** A profile that narrows tests confirms each
  filter selects at least one test before running it; one that selects none runs the full set and
  says why.
- **Evidence** (`jig-verify`): `jig verify` as the project configured it. With `ci` the narrowed
  report is sufficient when it names the mode; CI on the pull request proves the full set, and a
  red CI sends the task back to verify.

This narrows ADR-0013's last sentence for projects that declare `ci`; the rest of ADR-0013 stands.

## Alternatives

- **`verify.scope: full | changed`.** Names the mechanism, not why narrowing is safe, and
  `changed` already means "against `HEAD`" on the flag.
- **Check that CI exists** (look for workflow files). A workflow file does not say it runs the
  full set; the script would vouch for what it cannot know.
- **An unrecognised path is left to CI instead of `ALL`.** Fastest, but a change to a shared
  library would run no local test, and every regression would cost a CI round trip.
- **The map in `.ai/config.yaml`.** The config is flat `key: value`; a map is an ordered list with
  first match, and every command reads that parser.
- **The map beside the installed profile.** In link mode `.ai/profiles/<name>` is a symlink into
  the source, so the file would ship; in copy mode it mixes owners in a framework-owned directory.
- **The map inside the project's `verify.sh`** (kept by `upgrade` as keep-modified). Every later
  profile update then passes the project by.
- **A profile finds and parses the map itself** (`JIG_VERIFY_MAP`). The parser would be repeated
  in every profile and they would drift on what one map means. Rejected by the maintainer at the
  gate.
- **No `CI` detection, `--full` only.** A project whose CI calls `jig verify` would have to
  remember to add the flag.

## Consequences

- In a project that keeps `local`, nothing changes. A project that declares `ci` saves the time
  its profiles can narrow; today that is the shell profile only, and the others report
  `scope ignored` until `profiles-scope-and-languages` teaches them.
- `map` is now part of the distributed profile contract, like `scope` in ADR-0013: removing it
  later means an upgrade across profiles, and user-modified ones stay behind as keep-modified.
- A project with an unmodified shell profile runs everything where a jig-specific row used to
  narrow — more checks, never fewer.
- `tests/run.sh` clears `JIG_VERIFY_SCOPE`, `JIG_VERIFY_FILES`, `JIG_VERIFY_MAPPED` and `CI` for
  every test. The first narrowed run on this repository failed because a test that runs a profile
  directly inherited the scope of the run that started the suite; the leak predated this decision
  and became constant with it.
- The shell profile reads test names from the text of `tests/*.t.sh` rather than sourcing them,
  so it never executes a project's tests to decide which to run. A form it does not recognise can
  only make a filter look empty, which runs the full set.
- This repository's CI does not run shellcheck over the source; narrowed lint covers every changed
  file, but linter-version drift on untouched files is visible only in a full local run.

> **Amendment (2026-09-18).** This repository's CI reads the same map. A `scope` job runs
> `.github/scripts/ci-scope.sh` on the change (the pull request's base, or the push's previous tip):
> when every changed path is decided `-` by the map, or is documentation the map names no line for
> (`*.md`, `docs/`, `.ai/knowledge/`, `.ai/specs/`), the run is `light` — the knowledge check only;
> anything else, a path under `.github/`, a map that does not parse, or a change that cannot be
> measured is `full`. There is no partial run: a change to code gets every platform. Skipped jobs,
> not `paths-ignore`, so a required check reads them as passed. A nightly full run on `main` catches a
> map line that let a change skip the tests it needed. It was a pull request deleting two spec files
> that ran the whole suite on three platforms.
