---
id: adr-20260925-windows-runs-in-six-shares
type: adr
status: accepted
date: 2026-09-25
domains:
  - verify
paths:
  - .github/workflows/ci.yml
  - tests/ci-workflow.t.sh
summary: "Why the Windows suite runs in six shares rather than three or twelve, why the share count is the matrix's length instead of a number written next to it, and why the larger lever — the number of processes a test starts — was left alone."
---
# Windows runs in six shares, and the count is written once

## Context

The Windows suite ran in three shares and each took about half an hour, so a pull request
that touched platform behaviour waited thirty minutes for its slowest share
(adr-20260924-windows-runs-on-a-pull-request-that-touches-platform-behaviour put that
suite back on pull requests; this is what it costs). The same suite is under six minutes
on Linux. The difference is not a handful of pathological tests but every test alike:
each one builds a repository and calls `jig` — a bash script — tens of times, and a
process start on Windows costs an order of magnitude more.

Division is already a parameter: `JIG_TEST_SHARD=<i>/<n>` (`tests/run.sh`) takes every
n-th test in discovery order, so slow tests spread across shares whatever n is. The
repository is public, so its runners cost nothing but slots. The question was only how
many shares, and the honest answer had to be measured: every job has a constant part
that does not divide, and on Windows it was assumed to be large.

It is not. Measured on the runners, 2026-09-24 and 2026-09-25:

| shares | slowest share ran for | measured by |
|---|---|---|
| 3 | 29 min 38 s | the full matrix, on main |
| 4 | 23 min 13 s | one share, dispatched probe |
| 6 | 14 min 15 s | one share, dispatched probe |
| 8 | 12 min 45 s | one share, dispatched probe |
| 12 | 7 min 18 s | one share, dispatched probe |
| 16 | 6 min 36 s | one share, dispatched probe |

The constant part of a Windows job is **15 seconds** — 6 s of checkout, 4 s of pausing
Defender, the rest setup and teardown — and the wait for a runner was 3 to 4 seconds even
with seventeen jobs of this repository in flight at once. Neither is what flattens the
curve.

What flattens it is the spread between shares. Multiplying each measurement by its n
gives the whole suite's work: 5572, 5130, 6120, 5256 and 6336 seconds against the 5087 seconds
the full three-share run actually spent. The shares are not equal — a single share can
run 20% above the average — and the wall clock is the slowest of them, not the average.
As n grows, each share holds fewer tests (2028 of them in all) and that spread decides
more of the answer than n does. Between 6 and 8 shares the measured gain was 90 seconds.

## Decision

The Windows suite runs in **six** shares.

The count is written **once**, as the length of the `shard` matrix. The denominator of
`JIG_TEST_SHARD` and the share number in the job name are both
`${{ strategy.job-total }}`, which GitHub resolves to the number of jobs the matrix
created — confirmed on a Windows runner before it was relied on: the jobs reported
`JIG_TEST_SHARD=4/6` and were named `windows-latest (Git Bash) 4/6`.

Before this, the number appeared three times in the file, and the dangerous direction was
silent: a matrix raised to six with the denominator left at `/3` runs shares 1/3, 2/3 and
3/3 twice over and reports green on two thirds of the suite. `tests/ci-workflow.t.sh`
guards what is left — that the matrix list is 1..n with no hole and that no second copy of
the number reappears — because this is the one thing about the workflow that a run of the
workflow cannot check.

`timeout-minutes: 90` stays. A share now takes a sixth of what it did, so the limit is six
times the slack it used to be; lowering it would only buy a faster verdict on a hang, at
the price of a red run whenever a runner is slow.

## Alternatives

- **Keep three shares.** Rejected: thirty minutes is the wait this task exists to remove,
  and the measurement shows the constant part is 15 seconds, so nothing about the platform
  argues for three.
- **Twelve or sixteen shares.** Measured, and rejected. Twelve would reach about 8 minutes,
  but each doubling past six buys roughly three minutes while spending twice the runners,
  and a full run at twelve is fifteen jobs — against an account concurrency budget shared
  with every other pull request this repository has in flight, routinely three to five at
  once. Waiting saved on one pull request would be waiting added to the others. Six is
  where the curve stops paying for itself; raising it later is one token in the matrix.
- **Run fewer tests on Windows.** Refused outright. Exactly this trade let PR #93 onto
  `main` with its only platform-dependent property unverified. Narrowing *when* Windows
  runs is a different decision, already taken and bounded
  (adr-20260924-windows-runs-on-a-pull-request-that-touches-platform-behaviour); narrowing
  *what* runs is not.
- **Start fewer processes per test.** This is the real lever, and it is deliberately not
  pulled here. The cost is the number of times a test invokes `jig`; cutting it — fewer
  calls per scenario, one prepared repository shared by a group of tests — would beat any
  number of shares and would do it on every platform at once. It is also a rewrite of a
  suite of about 2000 tests, with its own risk of tests that no longer isolate each other.
  It deserves its own decision rather than being smuggled into a change to a matrix.

## Consequences

- A pull request that touches platform behaviour waits about fifteen minutes for Windows
  instead of thirty; a merge to `main`, which releases only after every share, is faster by
  the same amount.
- A full run occupies nine jobs instead of six. Three more Windows runners per run is the
  price, and it is paid out of a concurrency budget shared with the repository's other
  pull requests.
- Changing the number of shares is now a change to one list. It renames the matrix's jobs,
  which is why no branch rule may name them — `ci-ok` is the single required check
  (conventions/ci-gating.md), and that is what makes this change possible without touching
  branch protection.
- `.github/workflows/**` now reaches a check in `.ai/verify/shell.map`, where it used to
  reach none.
