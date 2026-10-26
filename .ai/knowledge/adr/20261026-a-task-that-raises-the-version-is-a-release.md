---
id: adr-20261026-a-task-that-raises-the-version-is-a-release
type: adr
status: accepted
date: 2026-10-26
domains:
  - task
  - spec
paths:
  - scripts/lib/task.sh
  - scripts/lib/common.sh
summary: Why jig task ship treats a change that raises the declared version into the default branch as a release, which files it reads the version from, and why its merge follows release.merge as an epic's final pull request does.
---
# A task whose change raises the version is a release, and `release.merge` decides its merge

## Context

`release.merge` (adr-0040, amendment of 2026-10-04) was read only by `jig spec ship`, for an epic's
final pull request; that amendment said "task pull requests stay under `agent.git`". Yet
adr-20261002-a-release-is-a-spec-with-an-epic lets a fix that cannot wait be "a patch release from
main" through an ordinary task, and states that who merges a release does not change: a person,
except an unattended run at `agent.git: merge`, and never a `major` one. Nothing enforced that for a
task. On 2026-10-24 release 0.33.0 was made as a plain task from `main` in a clone with
`release.merge: human`, and `jig task ship` merged it on green CI; CI tagged it (ADR-0034), and a
published tag cannot be taken back.

## Decision

- **A change is a release when it raises the version the project declares**, compared between the
  point the task's branch forked from its base (`git merge-base`, against `jig_base_ref`, the
  comparison the forge's pull request makes) and `HEAD`. `jig_release_raise` (common.sh) asks the
  files of `JIG_VERSION_FILES`, at the repository's root, in order: `scripts/lib/version.sh`
  (`JIG_VERSION="…"`, Jig's own source), `VERSION` (first non-empty line), `package.json` and
  `composer.json` (first `"version": "…"` line), `pyproject.toml` and `Cargo.toml` (first
  `version = "…"` line). The first one that declares a version at `HEAD` decides. A file that
  declared none at the fork point raises nothing; equal values raise nothing.
- **The level** is `major` when the first number grew, and also when either value is not a number
  there: a version nobody can read is never merged as a lesser release. Anything else is a minor or
  patch release. Anything git cannot answer is "not a release", which is the ship as it was.
- **Only into the default branch** (`git.base_branch`). A task into an epic is not the release; the
  epic's final pull request is, and `jig spec ship` keeps deciding it.
- **`jig task ship` then decides the merge as `spec_ship_final` does**, in the same order, at level
  `merge`: `release.merge` other than `agent` leaves the pull request open
  (`not merged: release.merge is human in this clone; the release's merge is the person's`); a ship
  where somebody answers (neither `autopilot.unattended` nor the task's own unattended run) leaves
  it to the human; a `major` release opens as a draft whose body starts with
  `Needs a human: major release?` and is not merged. Otherwise the task's usual gates and the merge
  on green CI follow. At every level from `pr` the ship says which file raised the version and from
  what to what.

## Alternatives

- **Read `JIG_VERSION` only.** Would have caught 0.33.0, and nothing in any project that installs
  Jig, where that file does not exist.
- **A committed key naming the version file.** One more setting a person must know to fill in; the
  built-in list covers the usual manifests, and a key can still be added later without breaking
  anything.
- **A `--release` flag on `jig task ship`.** 0.33.0 happened because the agent did not follow the
  release process; it would not have passed the flag either. Reading the diff does not depend on
  discipline.
- **Merge a task's release in an attended ship at `release.merge: agent`.** Contradicts
  adr-20261002-a-release-is-a-spec-with-an-epic and what `jig spec ship` does for the same release
  made the other way.

## Consequences

- A release is merged by the same rule whichever way it was made. A false positive (a manifest
  version raised without a release) costs one merge by hand; a miss is the behaviour before this
  decision.
- Monorepos whose versions live below the root (`packages/*/package.json`) are not recognised.
- The list is code: a new kind of manifest is a change to `JIG_VERSION_FILES` and `_jig_version_in`.

> **Amendment (2026-10-26, review findings of the first change).** The first file whose version
> *went up* decides, not the first that declares one: an unchanged `VERSION` no longer hides a raised
> `package.json`. Two `X.Y.Z` versions are compared as numbers (`jig_version_newer`), so an equal or
> lower one raises nothing; any other change of a version that is not `X.Y.Z` is still `major`.
> `pyproject.toml` is read only in `[project]` or `[tool.poetry]`, `Cargo.toml` only in `[package]`,
> a header up to its first `]` and a basic or literal string; a line opening with `[` inside a multi-line
> string or array still starts a table, so such a file can hide its version (a miss, never a false release).
> `VERSION` skips blank lines, CRLF ones included. The fork point is the later of the merge-bases
> with `origin/<base>` and the local `<base>`, so a stale remote-tracking ref does not take a raise
> merged in from a fresher base for the task's own. The checks run in `spec_ship_final`'s order:
> outside an unattended run first, then `release.merge`, then `major`.
