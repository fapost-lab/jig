---
id: adr-20260918-profiles-narrow-per-check-with-project-tools
type: adr
status: accepted
date: 2026-09-18
domains:
  - verify
  - profiles
paths:
  - scripts/lib/profile.sh
  - "profiles/**"
  - schemas/verify-map.md
summary: Why profiles for eleven stacks narrow check by check, run only the project's own development tools, and share one library sourced by relative path.
---
# Every profile narrows check by check, with the project's own tools, through one shared library

## Context

ADR-0041 let a project whose CI runs the full set verify by changed files, but only the shell
profile could narrow: php, laravel, node and go ran everything and said `scope ignored`, and
Python, Rust, .NET, Java/Kotlin, Ruby, Dart/Flutter and Swift had no profile at all — a project
on those stacks got `generic`, which checks nothing and passes. The people Jig is for mostly
write TypeScript and Python, often on Windows, often without CI.

Three facts shaped the answer. Stacks narrow differently: a linter takes files almost
everywhere, while tests can be tied to changed files only where the stack has a convention or
a dependency graph (a Go package and its importers, a Rust crate, `foo.py` → `test_foo.py`).
The same development tool exists in several copies — a global pytest and the project's own —
with different versions and plugins. And the scope logic the shell profile carried was about
150 lines; twelve copies of it would drift.

## Decision

- **Thirteen profiles.** New: `python`, `rust`, `dotnet`, `jvm` (Gradle or Maven, so Kotlin
  too), `ruby`, `dart` (Dart or Flutter), `swift`. php, laravel, node and go are rewritten.
  Every profile but `generic` declares `scope: [changed, map]`.
- **Where a tool comes from.** A stack's own toolchain (`go`, `cargo`, `dotnet`, `swift`,
  `dart`/`flutter`, `php`, `composer`, `bundle`, the node package manager, Gradle/Maven — a
  project wrapper first) comes from `PATH`. A project's development tools (pytest, ruff, mypy,
  eslint, vitest, jest, PHPUnit, Pest, PHPStan, Pint, RuboCop, RSpec) come only from the
  project's environment: `vendor/bin`, `node_modules/.bin`, `bundle exec` when `Gemfile.lock`
  lists the gem, `$VIRTUAL_ENV`/`.venv`/`venv`/the poetry environment. Never a global copy: its
  verdict is about another version with other plugins. A missing tool is a skip that says where
  it looked. Windows layouts (`Scripts/`, `.exe`, `.cmd`) are probed by what exists.
- **Narrowing is per check.** A linter gets the changed files; tests are narrowed only where
  the stack ties a source file to its tests, and otherwise run in full with the reason; a
  change to a manifest, lock file or tool configuration sends the checks it affects to the full
  set; documentation and `.ai/` reach no check. Whole-program analysis whose file mode misses
  errors in unchanged callers — mypy, a `typecheck` script — always runs in full. Swift is not
  narrowed. What each profile does is in its own header comment; what a map filter means per
  profile is in `schemas/verify-map.md`.
- **A narrowing that selects nothing is not a pass** (ADR-0041), checked before the runner:
  a missing test file, a package without `.go` files, an undeclared crate, a jest
  `--listTests` that lists nothing — each runs the full set. pytest's exit 5 (nothing
  collected) is a skip. Where related tests cannot be counted without running them (vitest), a
  profile narrows only to changed test files themselves.
- **One library, `scripts/lib/profile.sh`**, sourced by a profile as
  `$(dirname "$0")/../../scripts/lib/profile.sh` — the same relative path in the framework
  source and in a copy- or link-mode install, so no capability is needed. Its `jp_*` functions
  are a distributed interface: a user-modified profile kept by `upgrade` meets whatever library
  the upgrade installed, so a function is never renamed or given a new meaning. The shell
  profile keeps its own code.

## Alternatives

- **A global development tool as a fallback.** Would turn many vibe-coder skips into runs, and
  every such run checks the project with the wrong version and without its plugins. Rejected at
  the gate.
- **Self-contained profiles** (the state before). Twelve copies of scope handling, map
  decisions, verdict lines and exit codes.
- **Passing the library through a capability** (`JIG_VERIFY_LIB`). A contract for what a
  relative path already answers in every install mode.
- **Deciding "no related tests" by the runner's exit code.** jest and vitest exit 1 for an
  empty selection; that is indistinguishable from failing tests.
- **Narrowing analysers by file** everywhere. Right for linters and for PHPStan in a CI-backed
  project, wrong for a type checker whose verdict on one file depends on its callers.
- **A spec in phases, one stack at a time.** Declined by the maintainer: one task.

## Consequences

- A project on any of eleven stacks gets checks that run its own tools, and in a CI-backed
  project each of them saves what its stack can narrow.
- Two defects were found in review and fixed in the library, both easy to reintroduce: a glob
  list split with `for g in $list` expands `config/*` against the disk (`jp_path_matches`
  splits with `set -f`), and restoring IFS to a newline after passing a file list breaks every
  later space-separated split (profiles restore `$' \t\n'`; the library sets its own IFS).
  conventions/shell.md records both.
- Every profile is tested with stub tools only: this repository's CI has none of the stacks.
  Real tool flags (`cargo fmt -p`, `jest --listTests`, `dotnet format --include`) are taken
  from the tools' documentation, not from a run.
- The library is now part of what `upgrade` must keep compatible, like the scope protocol.
