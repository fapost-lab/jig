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
reviewed_at: 2026-09-26
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
- Exit code 3 means **no verdict was produced**: the check started and did not finish, or
  nothing was checked at all. It must stay distinguishable from both 0 and 1. A profile
  killed by a signal (128+N) means the first and needs no profile change to say so.
  `jig verify` exits 3 for either, and the line it prints says which.
- **A run where nothing passed and nothing failed is not a pass, and the two ways that happens
  are told apart.** `cmd_verify` ended in `[ "$failn" -eq 0 ]`, so a set of pure skips answered
  0 — success on a project not one line of which had been examined, read as success by
  `jig task ship` and the autopilot. What decides is **whether there was anything to check**: a
  profile covering the stack took part and its checks all skipped (the tools are missing —
  refuse, exit 3), or only fallback profiles took part, so nothing covers the project at all
  (nothing to install, nothing to wait for — do not refuse, and do not say `ok`: say that
  nothing here checks this project, and have `jig task ship` say it again where it has
  consequences). Collapsing the two either way is a defect, and a test that cannot tell them
  apart does not cover this rule. **The profile declares which it is** — `verifies: nothing`,
  read only by `profiles_is_fallback` — and it is never inferred, least of all from
  `detect: always`: `detect` says when a profile applies, not what it asserts, and a profile
  that applies everywhere and does check something (a secret scanner, a licence-header check)
  would otherwise ship unverified the day its tool went missing. Absence means the profile
  verifies something, which is the cautious default. It cannot be computed from a run — a
  profile with no checks and one whose checks could not run give identical skips and exit 2,
  and `jig task ship` must answer without running anything at all.
- **Incomplete outranks fail**, in `cmd_verify`, in `jp_end`, in `profiles/shell/verify.sh`
  and in `tests/run.sh` alike. A run something was killed in is not evidence, so the failures
  beside it are not evidence either.
- The changed-file list is computed once, in `_verify_changed_files`, and shared. Two
  profiles must never disagree about what changed in the same run.
- The changed-file list includes staged, unstaged and untracked files: a project is
  verified in the state it is in, not the state it was committed in.

## Rules

- A new capability gets a name in `profile.yaml`'s `scope` list and is passed only to
  profiles that name it. Adding a capability that older profiles could observe by default
  would break profiles written before it existed.
- `jig verify --explain` asks a profile for a plan only when it declares `scope: [..., explain]`.
  A profile in this mode MUST name every check as full, filtered, skipped or conditional;
  a conditional answer MUST name a possible full run. It MUST NOT run a project tool,
  probe its version or change the project. The coordinator MUST NOT take the clone's
  busy record, run an older profile lacking the capability, or read a plan as a check's
  verdict. A missing plan is an error, not a successful preview. The existing
  `jp_*` run and verdict functions retain their meanings for installed user profiles.
  Where a profile has separate plan and run branches, a test MUST compare their check
  names and skip decisions on the same inputs, so a changed run branch cannot leave
  a green but blind preview.
- **A run that dies without a failure is not a pass, so it is not claimed as one.** `Killed: 9`
  and `Terminated: 15` reach a waiting process as 128+N, and until they had an outcome of their
  own they were indistinguishable from a failing test. On one night that misreading cost four
  investigations — three attempts and two hours for one author, 24 phantom `verify::` failures
  for one reviewer — and not once was the cause in the code. Exit code 3 means "run it again",
  never "it is broken". What this catches is death **by a signal**; a test starved rather than
  killed still reads as an ordinary failure, and that limit is stated rather than papered over
  (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
- **One test run per clone, and the second one waits.** `jig verify` claims a record every
  worktree of the clone can see (`<clone root>/.ai/runtime/verify/busy/`, taken with `mkdir`
  because eight waiters must not wake together) and waits while another run holds it. A record
  is live only while `kill -0` on its pid succeeds *and* its mtime is within `verify.busy_ttl`;
  `0` switches the mechanism off, and `CI` switches it off by itself, because parallelism there
  is deliberate. Nothing in it may fail `jig verify`: a record that cannot be taken lets the run
  go ahead. The rule this replaces — "avoid simultaneous duplicate full runs" — was obeyed by
  every one of the eight agents that between them produced load average 364; it was written for
  one actor and said nothing about a population.
- **A profile answers `pass` only for a check that could have come out false on this
  project.** A test that is true wherever the profile can run at all is not a check — it is
  an entry in a tally, and a tally entry is indistinguishable from evidence to everything
  downstream. `generic` asserted "is this a git repository", which `jig_require_repo` has
  already refused by then; that one entry kept `pass > 0`, and `pass > 0` painted green every
  run in which each real check had skipped. Such a test is a guard: it may fail the run, and
  it may not pass it. `jp_end` already encodes the rule — exit 2 when no applicable check ran
  — and a profile that predates the library is not exempt from it.
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
- **What decides is whether a path could change a check's result, not what extension it has.**
  A stack with its own asset build has three kinds of front-end path, not one. The source is
  read by neither the test runner nor a browser, so it reaches no test. What *defines* the
  build — the package manifest, its lock file, the bundler's configuration — can alter every
  built asset, and a browser test loads the built assets under the same test command, so it
  runs the full set. And two kinds of path look like the first and behave like the second:
  the served directory, which holds what the browser actually loads, and the test suite's own
  files, where a front-end file may be a fixture or a snapshot a test asserts on. Until this
  was written, a Vue component ran a Laravel project's entire back-end suite; "anything that
  is not the stack's own extension needs no test" would have been the wrong cut the other
  way, and both halves have to be asserted for the rule to be covered at all.
- **A profile that falls back to the full set names the path that made it.** `not narrowable`
  was one wording for four situations — a file that defines the build, a file that can affect
  any test, a source no test is named after, and a path the profile cannot map at all — and
  the person reading it could act on none of them. The reason belongs to the profile, because
  only it knows its stack; the shared library only names the path (`jp_decide_cause`), and it
  names none for a path the project's own map widened, since attributing that line to a rule
  of the profile's would be a wrong explanation rather than a missing one.
- **A shipped profile knows its stack, never a project.** A files-to-checks rule true for
  one project's layout belongs in that project's `.ai/verify/<profile>.map`. The map is
  parsed in `cmd_verify` alone; a profile reads decisions, never the map file.
- **A test suite run by a narrowed profile must not pass the scope on.** `tests/run.sh`
  unsets `JIG_VERIFY_SCOPE`, `JIG_VERIFY_FILES`, `JIG_VERIFY_MAPPED`, `JIG_VERIFY_EXPLAIN`, `JIG_VERIFY_BUSY_HELD`
  and `CI` for every test:
  a test that runs a profile directly otherwise takes the scope of the run that started the
  suite.
- **This repository's `tests/run.sh` takes the clone's run record as well, and that is local
  to it.** The framework promises the record through `jig verify` only; a project's own runner
  is outside the contract. Here it is inside, because the review skills ask for targeted runs
  by test name and `jig verify` cannot express one — it narrows by changed file — so the raw
  runner is the ordinary way to run a targeted set rather than an edit-time convenience. It
  takes no record in a tree that is not a jig project, and none when it inherits
  `JIG_VERIFY_BUSY_HELD` from the `jig verify` that started it
  (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
- **The raw test runner is not the evidence path.** `tests/run.sh` reads no configuration:
  it does not know `verify.full_run`, never consults `.ai/verify/<profile>.map`, and prints
  no mode header — so its output cannot be the narrowed-mode evidence a task is closed on.
  It is the tool for running a named filter during an edit; the run that counts goes through
  `cmd_verify`.
- **A repeated full run is not additional evidence.** A suite that passed proves, run again,
  that it still passes. What has actually got through this suite was invisible to that: nine
  `worktree-bootstrap` tests passed against the wrong fixtures, and `section.sh` had no test
  at all on Windows, which turned `main` red. The first was caught by reading the fixtures,
  the second by writing the test that was missing — neither by a second run. This is why the
  full set is run where it is cheap and parallel, in CI, and why a local repeat of it is a
  cost with no yield: it competes for the machine with the CI pass holding the merge and
  returns a confidence it did not produce.
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
