---
id: adr-20261110-a-pull-request-runs-the-tests-its-change-reaches
type: adr
status: accepted
date: 2026-11-10
domains:
  - verify
paths:
  - .github/workflows/ci.yml
  - .github/scripts/ci-scope.sh
  - .github/scripts/ci-matrix.sh
  - .github/scripts/ci-run-tests.sh
  - .github/scripts/ci-reuse.sh
  - .github/scripts/red-main.sh
  - tests/run.sh
summary: Why a pull request and a push run only the tests the shell profile says the change reaches, with the whole suite nightly and for a release; how shares are sized by estimated work and divided by measured durations from one plan; why a selected run never releases, is never reused and never closes red-main.
---
# <Decision in one sentence>
# A pull request runs the tests its change reaches; the whole suite runs nightly and for a release

## Context

CI answered a pull request in 20 to 35 minutes and ran the whole suite of ~3800 tests on three
platforms for any change to a script (ADR-0041, amendment of 2026-09-18: "There is no partial
run"). Measured on the nightly run of 2026-11-09:

| platform | shares | slowest share | CPU per test | runner-minutes |
|---|---|---|---|---|
| Linux | 2 | 11–13 min | ~1.6 s | ~24 |
| macOS | 3 | 17–19 min | ~2.5 s | ~54 |
| Windows | 10 | 29–31 min (fastest 17) | ~14 s | ~250 |

- The tests are end to end: each starts `jig` and `git` tens of times, and every process start
  costs about eight times as much under Git Bash. Sourcing a test file costs nothing (0.02 s for
  11 000 lines).
- The shares were dealt round-robin, so one Windows share ran 17 minutes and another 31.
- The slowest tests, `upgrade::*` at 80–185 s each on Windows, each ran a full `jig init` where a
  cached install would do.
- The local `jig verify` already narrows to the tests a change reaches, through
  `.ai/verify/shell.map` and the shell profile's rules (a script to its test file, a changed
  function to the scripts that call it). CI used the map only to tell documentation from
  everything else.
- Replaying the last 40 merged pull requests through the profile: 5 needed no test, 20 reached a
  few test files, 15 reached everything (the harness, `profile.sh`, some functions of `common.sh`).

## Decision

- **What a run tests.** `scope` publishes `suite`:
  - `selected` when the shell profile names the tests the change reaches;
  - `all` when it cannot, and always for the nightly run, a manual run, a change of `JIG_VERSION`,
    anything under `.github/`, and the test harness (`tests/run.sh`, `tests/lib/`).
  - `.github/scripts/ci-scope.sh` asks the profile through the explain protocol
    (adr-20260925-verify-explain-plans) with the inputs `jig verify` gives it, but without
    `verify.full_run: ci`: locally that setting defers an ALL to CI, and CI is where it was
    deferred to. Any ALL, and any plan the script cannot read, is `all`.
  - What decides the selection is `all` too: `.ai/verify/`, `profiles/shell/`,
    `scripts/lib/verify.sh` and `scripts/lib/profile.sh`. A map line would otherwise choose the
    tests of the pull request that adds it and of every one after it.
  - A selection always includes `knowledge::test_real_repository_knowledge_passes_with_no_failures`:
    the whole suite ran it, the `knowledge` job runs only on a light run, and a change to code can
    break a document's `paths`.
  - Pull requests, pushes to `main` and pushes to an epic run `selected` when they can. Windows
    still runs on a pull request only where `ci-windows-scope.sh` says the change touches
    platform behaviour, and then runs the same selection.
- **How it is divided.**
  - `.github/scripts/ci-matrix.sh` sets the number of shares from the estimated work of the
    selected tests on each platform, in shares of about six minutes. The ceilings are 4 Linux,
    4 macOS and 10 Windows: 19 of the organisation's 20 concurrent jobs with the Windows smoke
    job, and 4 of its 5 macOS jobs.
  - The tests are divided by measured duration (LPT, `tests/run.sh` `JIG_TEST_DURATIONS`) rather
    than round-robin.
  - The durations are the per-test reports (`JIG_TEST_REPORT`) of the last green nightly run.
    They are read once, by `scope`, and handed to every share in the run's `plan` artifact:
    two shares reading two tables would divide the suite two ways.
  - Without a table the runner falls back to round-robin.
- **What a selected run may not do.**
  - It never releases: `release` needs `suite == 'all'`, and a change of `JIG_VERSION` is always
    `all`.
  - `ci-reuse.sh` reuses only a pull request's run of the whole suite. The test jobs' names end
    in `(all)` or `(selected)`.
  - A green selected run never closes the `red-main` issue.
- **`red-main` names the failed tests.** It reads the shares' reports and lists the commits since
  the last green nightly run. On a red nightly run it points at the map: a test the nightly run
  finds first is one a change may have skipped.
- **Cheaper fixtures.** Tests that only need an installed project copy the cached install
  (`fixture_jig_repo`), and the v2 framework source of the upgrade tests is cached too
  (`fixture_caches_prepare`).

This replaces "There is no partial run" in ADR-0041's amendment of 2026-09-18 and the fixed share
counts of adr-20261016-the-suite-runs-in-shares-on-every-platform and
adr-20260925-windows-runs-in-six-shares. adr-20261027-main-is-not-retested-when-a-pull-request-tested-its-tree
now applies to a pull request's run of the whole suite only.

## Alternatives

- **Keep every pull request full and only even out the shares and fixtures.** Windows would fall
  to about 22 minutes, but every pull request would still wait for it. Those changes are part of
  this decision anyway.
- **Keep the push to `main` full.** After almost every code merge, reuse would find a selected
  pull-request run and test everything again for 30 minutes on 18 runners. Pull requests would
  wait less, the runner-minutes would hardly fall, and `main`'s runs would hold the concurrency
  limit. The maintainer chose to narrow it (2026-11-10).
- **Run Windows only nightly.** A pull request that breaks Windows would merge and turn `main`
  red until the morning. Narrowing gives the same speed and keeps Windows on the pull requests
  that touch it.
- **Larger or self-hosted runners.** These spend money or upkeep on the symptom; a test still
  costs 14 s under Git Bash. That cost is the task `fewer-processes-per-command`.
- **More Windows shares.** Twelve would hold all twenty concurrent jobs, and every other pull
  request would queue behind one run.
- **A committed durations table.** `main` takes pull requests only, so the table would go stale
  or need a bot.
- **Each share fetching durations itself.** A nightly run finishing between two shares' starts
  would divide the suite two ways, and a test could run in no share with the run still green.

## Consequences

- About 60% of pull requests (25 of 40 in the replay) wait minutes instead of half an hour. The
  rest still run everything, faster by the even shares and the fixtures.
- A gap in the map or the profile no longer shows on the pull request that opened it. It shows
  on the next nightly run, at most a day later, before any release: a release always runs the
  whole suite. The `red-main` issue then names the failed tests and the commits since the last
  green nightly run.
- `main` may be red for up to a day after such a merge, and `main-green-check.sh` holds a release
  pull request back meanwhile.
- CI now depends on the explain protocol's `PLAN shell: tests/run.sh: filtered (test filters: …)`
  line. A change to that line makes `ci-scope.sh` answer `all`: slower, never narrower.
- Undoing it is one line: have `ci-scope.sh` print `full` where it prints `selected`. The even
  shares stay, and without a `plan` the runner divides by round-robin as before.
