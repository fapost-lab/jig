---
id: rule-verify
type: rule
status: active
summary: "Constraints on running checks: exit codes decide results, the changed-file list is computed once, capabilities are named before they are granted."
domains:
  - verify
topics: []
load: domain
requires: []
paths:
  - scripts/lib/verify.sh
  - scripts/lib/profiles.sh
  - "profiles/**"
  - tests/run.sh
  - scripts/lib/profile.sh
reviewed_at: 2026-09-18
---
# Verify rules

The project-wide invariants on capability granting and on "a skip is not a pass" are in
the global `RULES.md` (ADR-0013). What follows binds changes inside this domain.

## Invariants

- A profile is run from the repository root, in a subshell, and its exit code is the only
  thing that decides its result. `cmd_verify` never inspects a profile's output to
  decide pass or fail — profiles are user-modifiable and their prose is not an API.
- Exit code 2 means skip and must stay distinguishable from 0. Collapsing skip into pass
  would let an unrunnable check report success.
- The changed-file list is computed once, in `_verify_changed_files`, and shared. Two
  profiles must never disagree about what changed in the same run.
- The changed-file list includes staged, unstaged and untracked files: a project is
  verified in the state it is in, not the state it was committed in.

## Rules

- A new capability gets a name in `profile.yaml`'s `scope` list and is passed only to
  profiles that name it. Adding a capability that older profiles could observe by default
  would break profiles written before it existed.
- **A narrowing that selects nothing is not a pass.** A profile that narrows its tests
  confirms every filter selects at least one test before running it; one that selects none
  runs the full set and says why. A runner reports an empty selection as `0 passed`, exit 0,
  and a pass nothing produced is the defect the scope protocol exists to prevent (ADR-0041).
- **A development tool comes from the project's environment, never from a global
  install.** pytest, eslint, PHPUnit and the like are read from `vendor/bin`,
  `node_modules/.bin`, `bundle exec` or the project's virtualenv; only the stack's own
  toolchain (`go`, `cargo`, `composer`, the package manager) is taken from `PATH`. A global
  copy checks the project with another version and without its plugins, and a green verdict
  from it says nothing (adr-20260918-profiles-narrow-per-check-with-project-tools). Missing,
  the check skips and says where it looked.
- **A profile narrows each check on its own terms.** Linters by file; tests only where the
  stack ties a source file to its tests; whole-program analysis (mypy, `typecheck`) never.
  Documentation and `.ai/` reach no check (`jp_is_doc`).
- **A shipped profile knows its stack, never a project.** A files-to-checks rule true for
  one project's layout belongs in that project's `.ai/verify/<profile>.map`. The map is
  parsed in `cmd_verify` alone; a profile reads decisions, never the map file.
- **A test suite run by a narrowed profile must not pass the scope on.** `tests/run.sh`
  unsets `JIG_VERIFY_SCOPE`, `JIG_VERIFY_FILES`, `JIG_VERIFY_MAPPED` and `CI` for every test:
  a test that runs a profile directly otherwise takes the scope of the run that started the
  suite.
- `detect` globs live in `profile.yaml` and nowhere else. No command re-derives the
  mapping from root manifest to stack.
- A profile's `verify.sh` prints one line per check it ran, because a profile runs
  several and a single profile-level result hides which of them fired.
- **A check that depends on an external tool names that tool's version in its verdict,
  and never refuses because of it.** Linters disagree with themselves across releases —
  shellcheck reports SC2015 in 0.10.0 and not in 0.11.0 — so the same tree honestly
  passes on one machine and fails on another. That is a fact to make legible, not a
  failure to suppress: without the version in the line, "green here, red there" has no
  visible cause. Refusing an unexpected version is the opposite mistake; it fails the
  gate for shipping an ordinary distribution rather than for anything about the code,
  and the tool is optional in the first place (ADR-0002).
- **A test decides its own environment; it never inherits one.** A check that needs a
  tool supplies it as a stub on `PATH`; a check that needs a tool *gone* builds a `PATH`
  from an explicit tool list. The suite gave three different verdicts for one commit —
  564/564 on the maintainer's Mac, 542/548 on a macOS runner, 545/548 on Linux — entirely
  because tests read the machine instead of stating what they needed.
- **A version probe must never be able to fail the thing it annotates.** Under `set -e`
  with `pipefail`, `x=$(tool --version | sed ...)` takes the pipeline's status, so a tool
  that is installed but cannot answer `--version` aborts the profile before it prints
  anything — for that check and every check after it. Guard the assignment and fall back
  to `unknown`.
