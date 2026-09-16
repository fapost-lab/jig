---
id: adr-0034-releases-are-tagged-by-ci
type: adr
status: accepted
date: 2026-09-14
domains:
  - install
paths:
  - .github/scripts/release-tag.sh
  - .github/workflows/ci.yml
  - .github/scripts/release-lib.sh
summary: Why a release tag is created only by CI after the tests pass, from a tested script under .github, and how the version is raised.
reviewed_at: 2026-09-16
---
# ADR-0034: A release is tagged by CI after the tests pass, from a tested script, never by hand

## Context

ADR-0033 made release tags the update channel: the installer installs the newest `vX.Y.Z` and
`jig self-update` moves to it. It left open how a tag comes to exist. Three facts decided it.
`JIG_VERSION` had not changed since the first commit, so nothing reminded anyone to tag. `main`
accepts changes only through pull requests, and agents do not commit here, so a tag by hand is a
separate human step after every merge. And a published tag is practically irreversible: once an
installer or `self-update` has used it, deleting or moving it breaks those installations.

## Decision

- **A release is a merge into `main` that raises `JIG_VERSION`.** After the tests pass on every
  platform, the `release` job of `.github/workflows/ci.yml` tags `v<JIG_VERSION>`. It runs only on
  a push to `main`, after the `test` job (`needs: test`), and it alone gets `contents: write`; the
  rest of the workflow stays `contents: read`. Nobody tags by hand.
- **The decision lives in `.github/scripts/release-tag.sh`, which has tests; the job only runs
  it.** The script:
  - requires `JIG_VERSION` to be `major.minor.patch` written without leading zeros, so a tag name
    is canonical;
  - reads tags from the remote with `git ls-remote --tags origin`, not from the checkout;
  - does nothing when a release with a numerically equal version already exists, wherever it
    points — that is every merge that did not raise the version. Equality is by number, so a
    `v01.0.0` counts as `1.0.0` and a second tag for one release is never made;
  - fails when a newer release exists: a version never goes back;
  - otherwise creates the annotated tag `v<version>` (`Jig <version>`) on `HEAD` and pushes it
    without `--force`. A rejected push fails and removes only the local tag this run made. An
    existing remote tag is never moved or deleted.
- **The script sits under `.github/`, not `scripts/`**, because `jig init` copies `scripts/` into
  every project and releasing is this repository's business only. It sources the release helpers
  of `scripts/lib/common.sh`, so tags are judged by the same rules the installer and
  `self-update` use.
- **Version rule.** `JIG_VERSION` is raised in the pull request that should become the release,
  in `scripts/lib/version.sh` only: patch for a fix, minor for a new capability, major for a
  change that breaks commands, the `.ai/` layout, the `init`/`upgrade` contract or the installer.
  Before `1.0.0`, such a change raises minor.
- A tag is all a release is for now: no GitHub Release page. README keeps the bootstrap command on
  `main/install.sh`, which installs the newest release anyway.

## Alternatives

- **Tag by hand after the merge.** Rejected by the maintainer: it is the discipline the framework
  exists to remove, and a version and its tag could disagree.
- **Decide in the workflow YAML.** Rejected: it cannot be tested locally, and every script command
  in this repository has a test.
- **A `jig release` command under `scripts/`.** Rejected: it would be installed into every
  project, none of which releases Jig.
- **A separate `release.yml` triggered by `workflow_run` after `ci`.** Rejected: it runs from the
  default branch's copy, fires whatever the outcome, and needs `conclusion`, branch and event
  checks to give the guarantee `needs: test` gives in the same workflow.
- **Fail when the version's tag already points at another commit.** Rejected: every merge that does
  not raise the version would turn the job red.
- **Decide "already released" by the tag's name.** Rejected after review: the shared helpers read
  `01.0.0` as `1.0.0`, and a name comparison published `v01.0.0` beside an existing `v1.0.0` in a
  reproduction.
- **Check the tagged installer's raw URL inside the job.** Rejected: network and raw caching would
  make the job flaky; it is checked once after the first release instead.
- **Pin README's bootstrap URL to the tag.** Rejected: a README change per release for no gain.

## Consequences

- The merge that raises the version is the irreversible moment; the tag follows it within one CI
  run. The first release is `v0.2.0`, not `v0.1.0`: `JIG_VERSION` had been `0.1.0` since the first
  commit, so every project installed from any commit before the release records `0.1.0` in its
  manifest. Releasing under that number would make `jig status` report such a project as `current`
  while its files lag behind; `0.2.0` keeps the release distinguishable from every snapshot before
  it.
- With the workflow's `cancel-in-progress`, two quick merges cancel the first run, and the tag lands
  on the second commit, which contains the first and declares the same version.
- A malformed or lower version fails the `release` job on `main` after the merge; the repair is
  another pull request.
- Three GitHub behaviours the design relies on are not stated outright in GitHub's documentation:
  that `contents: write` lets the job push a tag with the checkout's token, that a failed matrix leg
  skips the jobs that need it, and that a raw URL serves a file at a tag. The first release run
  proves or refutes them.
- A tag pushed with `GITHUB_TOKEN` starts no workflow, and nothing depends on one starting.

> **Amendment (2026-09-16).** CI also runs the tests on every push to `epic/**`, and a pull request
> from `epic/*` into `main` runs the `epic-pr` job: it fails when `JIG_VERSION` is already released or
> the epic's roadmap line is not `— finished` (ADR-0040). The "already released" rule is shared with
> `release-tag.sh` through `.github/scripts/release-lib.sh`. The `release` job is unchanged.
