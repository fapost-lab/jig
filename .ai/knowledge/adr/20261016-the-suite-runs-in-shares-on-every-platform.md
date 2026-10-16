---
id: adr-20261016-the-suite-runs-in-shares-on-every-platform
type: adr
status: accepted
date: 2026-10-16
domains:
  - verify
paths:
  - .github/workflows/ci.yml
  - tests/ci-workflow.t.sh
summary: "Why the suite runs in shares on Linux (two), macOS (three) and Windows (ten): CI measurements of where the time went, why more runners and not more workers, how the shares of one matrix over two platforms are held to 1/n..n/n, and why ci-ok needed no change."
---
# The suite runs in shares on every platform: Linux in two, macOS in three, Windows in ten

## Context

The required check `ci-ok` waits for the slowest job of a run. Measured over eleven full runs
of `ci.yml` on 2026-10-14 and 2026-10-15 (`gh run view --json jobs` and the job logs), it
answered 24 to 38 minutes after a push, and once 72:

| job | `Tests` step | share of the run |
|---|---|---|
| macOS, one job, 3 cores | 1386–2184 s | slowest on most pull requests |
| Linux, one job, 4 cores | 567–837 s | — |
| Windows, slowest of six shares | 1890–2153 s | slowest on main, epic pushes and platform pull requests |

- **The suite is CPU-bound.** One macOS host happened to have five cores instead of three
  and ran the same suite in 936 s against ~1950 s. The tests barely sleep
  (`tests/housekeeping.t.sh` moves a fictitious clock). More workers on the same runner would
  add no CPU; more runners add it almost linearly, as the Windows probes of
  adr-20260925-windows-runs-in-six-shares showed.
- **The cost is spread, not concentrated.** From the completion times in the logs, a test costs
  about 2 core-seconds on macOS and about 1 on Linux; four files (`task`, `status`, `upgrade`,
  `verify`) hold 30% of the tests and take about 55% of it, spread over hundreds of tests each;
  the slowest single test is 64 s. The prepared install is already copied rather than rebuilt per test
  (`fixture_cache_prepare`); what is left is the number of `jig` and `git` processes a test
  starts.
- **Windows work doubled.** Six shares summed to ~5100 s when they were chosen and to
  9695–11585 s now (2028 tests then, ~2930 now), so six no longer gives the fifteen minutes
  that ADR promised.
- **The spread between shares is the runners.** The same Windows share took 1177 s in one run
  and 2049 s in another; the slowest share is 1.08–1.29 times the mean. Round-robin by
  discovery order already spreads every file across every share.
- **Queueing.** In ten of the eleven runs every job started 10–21 s after the run was created.
  The exception was a macOS job that waited 37 minutes while nothing else in the organisation
  was running — GitHub's own macOS capacity, not this repository's limit. The organisation is
  on the Free plan: 20 jobs at once, 5 of them macOS.

## Decision

Every platform's suite runs in shares through `JIG_TEST_SHARD=<i>/<n>` (`tests/run.sh`):
**Linux in two, macOS in three, Windows in ten.** Every share runs every test that falls to
it; no platform runs fewer tests than before.

- `test` stays one job over both Unix platforms. Its matrix is an `include` list of
  `{ os, shard: '<i>/<n>' }`, it is named `${{ matrix.os }} ${{ matrix.shard }}`, and its
  `Tests` step sets `JIG_TEST_SHARD: ${{ matrix.shard }}`. `strategy.job-total` cannot be
  the denominator of a matrix whose platforms have different counts, so each entry carries
  its own; `tests/ci-workflow.t.sh` holds them together — per platform exactly `1/n .. n/n`
  with one `n`, both `ubuntu-latest` and `macos-latest` present, every entry in the one form
  the check reads, and the share passed to the runner from the matrix and nowhere else.
- `test-windows` keeps its form (adr-20260925-windows-runs-in-six-shares): the share count is
  the length of `shard: [1 … 10]` and the denominator is `${{ strategy.job-total }}`.
- The install check runs in every Linux and macOS share. It takes about 20 s, and running it
  in one share only would make it a step that can be skipped without any job saying so.
- `ci-ok`, `release`, `epic-pr` and `.github/scripts/ci-ok.sh` are unchanged. `needs` on a
  matrix job waits for every share, and the job's result is that of all of them: a share
  that failed, was cancelled or never started keeps `test` or `test-windows` from `success`,
  and `ci-ok` fails.

Expected, from the same measurements: macOS ~11–13 minutes, Linux ~6–8, Windows ~21–22. A
pull request that does not run Windows gets `ci-ok` in about 12–13 minutes instead of 24–38;
one that does, and main, in about 22 instead of 34–37.

## Alternatives

- **Shard macOS only.** Linux, at up to 14 minutes, would become the slowest job of most pull
  requests, and main would still wait 35 minutes for Windows.
- **More workers per runner (`JIG_TEST_JOBS` above the core count).** Rejected on the
  five-core measurement: the suite is CPU-bound, so oversubscribing adds no work done.
- **Rebalance shares by measured file time.** The spread between shares is runner noise, not
  unequal shares, and a table of times would go stale with every test added.
- **Cheaper fixtures.** The template install is already copied. Starting fewer processes per
  test is still the larger lever on every platform, and still a rewrite of ~2900 tests —
  left to its own decision, as adr-20260925-windows-runs-in-six-shares left it.
- **Windows in twelve shares.** About 18 minutes, but a full run would hold exactly the
  twenty jobs the organisation may run at once, and any other run would wait for all of it.
  Ten leaves room for the light runs of documentation pull requests.
- **Separate `test-linux` and `test-macos` jobs, each with `strategy.job-total`.** The count
  would be written once per platform, but `ci-ok`'s `needs`, its script, `release` and
  `epic-pr` would all change — more risk inside the gate itself to save a consistency check
  the test suite makes reliably.

## Consequences

- A full run holds 18 jobs instead of 11: 3 macOS instead of 1, 10 Windows instead of 6.
  Dividing adds no work — the same runner-minutes plus 15–55 s per new share — so when the
  queue is saturated the last run finishes about when it did, and when it is not each run
  finishes two to three times sooner. Two full runs at once queue, as they did before.
- A macOS shortage at GitHub now delays three jobs instead of one; it was one run in eleven.
- Changing a share count is a change to one list: for `test`, every entry of the platform
  (the test refuses a mix); for `test-windows`, the `shard` list. Job names change with it,
  which is why no branch rule may name them (conventions/ci-gating.md).
- adr-20260925-windows-runs-in-six-shares keeps its reasoning about counting shares once and
  about the process-count lever; its number six is replaced here.
