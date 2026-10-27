---
id: adr-20261027-main-is-not-retested-when-a-pull-request-tested-its-tree
type: adr
status: accepted
date: 2026-10-27
domains: []
paths:
  - .github/workflows/ci.yml
  - .github/scripts/ci-reuse.sh
  - .github/scripts/ci-ok.sh
summary: Why a push to main skips the suite and goes straight to the release tag when a full green pull-request run already tested its tree, how that tree is proved without the merge ref, and the risk left.
---
# A push to main is not tested again when a full pull-request run already tested its tree

## Context

A release used to cost four runs of the whole suite, about 25 minutes each: the last task's pull
request, its merge into `main`, a separate release pull request, and that one's merge. Two of the
four tested a tree that had just been tested. The release tag waits for `main`'s run (ADR-0034),
so the person releasing waited for all four.

Since `release-pr-runs-full-ci`, a pull request that changes `JIG_VERSION` always runs every
platform, Windows Git Bash shares included, and is refused while `main` is red. Its run is
therefore already the full test of the release — of the merge GitHub would make, not of the
branch alone, since a pull request's run checks out `refs/pull/N/merge`.

Two facts about GitHub decide how that tree can be known afterwards. A pull-request run's
`head_sha` (and `head_commit.tree_id`) is the head of the branch, not the merge it tested. And
`refs/pull/N/merge` is gone once the pull request merges. Neither the API nor the repository says,
after the fact, which tree a pull-request run tested.

## Decision

- **A push to `main` whose scope is full skips the suite when a pull request's run already tested
  its tree on every platform.** The `scope` job publishes `reuse`; `test`, `test-windows` and
  `smoke-windows` skip when it is true, and `release` runs as before — a skipped job is neither a
  failure nor a cancellation — and tags. The rules are `.github/scripts/ci-reuse.sh`, which has
  tests (`tests/ci-reuse.t.sh`, with a stub `gh`).
- **The tree is proved by ancestry, not read from the merge ref.** The run of a pull request with
  head `P` tested GitHub's merge of `P` into `main`'s tip at the time, `B`. `main` only moves
  forward (its branch rule refuses a non-fast-forward push) and the run came before the push, so
  `B` is the push's `before` commit or an ancestor of it. When `before` is an ancestor of `P`, so
  is `B`, the merge GitHub tested has `P`'s own tree, and when that is the tree of the pushed
  `HEAD`, the run tested exactly what `main` now holds. In plain words: the pull request was up to
  date with `main` when it merged.
- **"Full" is read from the run's jobs**: `knowledge` skipped (the scope was full), every other
  job but `release` and `epic-pr` succeeded, and at least one `windows-latest (Git Bash)` share
  passed. A narrow run, or one that skipped Windows, tested less than `main` releases.
  The run is one of the pull request GitHub records as having made the push — base `main`,
  merge commit equal to the pushed `HEAD` (`commits/<HEAD>/pulls`) — found by that pull request's
  head commit; the first successful one that qualifies wins. A direct push never reuses.
- **"Full" counts every job a pull request into `main` runs.** The jobs it always skips — `release`,
  `epic-pr`, `red-main` — are listed in `ci-reuse.sh` (`CR_PR_SKIPS`), and `tests/ci-reuse.t.sh`
  requires every job of `ci.yml` to be in that list or in the list of jobs a full pull-request run
  runs: an unlisted job would make every run look partial and switch reuse off silently, which is
  what `red-main` did to the first version of this script.
- **Anything else tests everything**: a push no pull request made, `main` moved on after the
  branch last merged it, no run
  qualifies, `before` is missing or unknown, or GitHub does not answer. The nightly run, a manual
  run and a push to an epic branch never reuse.
- **`ci-ok` keeps its second copy.** `ci-ok.sh` reads `reuse` and expects the three suite jobs to
  skip when it is true, and refuses a `reuse` on anything but a full push: a `true` there would
  skip a suite nobody tested.
- **The version is raised in the pull request of a release's last task.** A separate release pull
  request is the exception (a release with nothing left to change but the version). That pull
  request is full by rule, and when its branch is up to date with `main`, the release costs one run
  of the suite.

## Alternatives

- **GitHub's merge queue.** It tests the exact commit that lands, so `main` would need no run of
  its own at all, and it also keeps two merges from testing stale trees. Rejected for now: it
  changes how every pull request merges, `jig task ship` merges with `gh pr merge` and would have to
  enqueue instead and wait for a second, queue-side run, and the queue needs a `merge_group`
  trigger and a branch-rule change outside the repository's review. It adds a run per merge to
  save one; here the pull request's run is already the merge's test whenever the branch is current.
- **Test everything on `main`, as before.** Safe and simple, and it is what a stale branch still
  gets. Rejected as the default because it doubles the wait for every release whose tree has just
  been tested, and the wait is the reason releases were batched and delayed.
- **Record the tested tree in the pull request's run** — a job name built from a `scope` output,
  or an artifact — and compare it on `main`. It would also cover a pull request that was not up to
  date but merged cleanly. Rejected: it couples the decision to job naming or artifact retention,
  and nothing in the repository can test that GitHub renders such a name; the ancestry argument
  needs only git and the runs list.
- **Require branches to be up to date before merging** (strict status checks). It would make every
  merge reusable, and costs every other pull request a re-run after each merge into `main`. Not
  chosen; a stale branch simply gets the full run on `main`.

## Consequences

- A release merged from an up-to-date pull request is tagged minutes after the merge instead of
  about 25 minutes later. The `jig-release` finish merges the default branch into the epic before
  its final pull request; a task's branch is current when nothing merged into `main` since it was
  cut or since it last merged `main` in. `jig task ship` does not update a branch, so a release
  pull request whose base moved gets the full run on `main` unless its author merges `main` in
  (and lets that run finish) before merging.
- **Residual risk.** `main`'s tag rests on the pull request's run, not on a run of `main` itself:
  - a fault that only shows on the push event — a step that runs only on `main`, a secret or token
    scope a pull request does not have — is not exercised before the tag. Today no test step
    differs between the two events; a change that adds one must reckon with this ADR;
  - a flaky test that passed in the pull request is not given a second chance to fail before the
    tag; the nightly run still tests the whole suite on `main` every day;
  - the runner images may have changed between the two runs; the nightly run catches that too;
  - a run does not say which pull request it served once that pull request merged
    (`pull_requests` is empty), so runs are matched by the head commit. A green full run of the
    same commit for a second pull request into an epic — one branch proposed into `main` and into
    an epic at once — would count although it tested a merge onto the epic. Nothing in Jig's
    workflow opens such a pair;
  - the argument assumes `main` never moves backwards. A force push to `main` (refused by the
    branch rule today) would break it; so would a GitHub test merge that differs from the merge
    button's result, which for the same inputs it does not.
- `red-main.sh` treats a reusing run as full: it closes the `red-main` issue when green, since the
  tree it names passed every platform.
- `ci-scope.sh` measures the next push from the last successful run on `main`; a reusing run is
  one, and its tree was fully tested, so nothing falls between two runs.
- The name prefix of the Windows shares is copied into `ci-reuse.sh`; `tests/ci-reuse.t.sh` holds
  it to `ci.yml`. A rename that slipped past would only make `main` test everything.
