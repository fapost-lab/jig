---
id: adr-20261106-copy-mode-projects-take-released-code-only
type: adr
status: accepted
date: 2026-11-06
domains:
  - install
paths:
  - scripts/lib/common.sh
  - scripts/lib/upgrade.sh
  - scripts/lib/init.sh
  - scripts/lib/self-update.sh
  - scripts/lib/status.sh
  - install.sh
  - scripts/jig
  - scripts/lib/doctor.sh
  - tests/run.sh
summary: Why a copy-mode project takes framework code only from a checkout at its release tag, how unreleased code is named X.Y.Z+<sha>, and why --unreleased is the one way to take it.
---
# A copy-mode project takes released code only; unreleased code is named `X.Y.Z+<sha>` and taken only with `--unreleased`

## Context

ADR-0033 made release tags the update channel and `main` the development channel, reached by asking
for it. It did not say what a copy-mode project may take from a global framework on that channel,
and every link of the chain did what it was designed to do:

- a global checkout on a branch — `install.sh --ref main`, a clone made by hand, an install from
  before the first tag, a `git checkout main` — stays on it, because a repeat install and
  `jig self-update` pull a branch rather than move it to a tag;
- `main` keeps the last release's `JIG_VERSION` until the next release raises it, so that checkout
  declares a released number while holding code no release contains;
- the pending check behind `jig verify` (ADR-0017) measures the project against the global framework
  whenever it is not older (adr-20261029-the-manifest-names-the-global-framework-not-its-path), and
  "the same number" is not older;
- `jig upgrade` copied what that checkout held and recorded the released number in `.ai/manifest`.

On 2026-11-06 this reached a real project. A colleague's global jig was on `main` past v0.40.0;
`verify` refused for 15 pending framework files, `jig status` said `project=0.40.0 global=0.40.0`,
an agent ran `jig upgrade` and opened a pull request carrying unreleased framework code labelled
0.40.0. Nothing along the way said the source was not a release.

## Decision

- **A released source is a framework checkout whose HEAD carries the tag `v<JIG_VERSION>` of the
  version it declares** (`jig_source_release`, common.sh). A branch at that commit is released — the
  bytes are the release's. Anything else is unreleased: a branch or detached HEAD past the tag, a
  version raised but not yet tagged, a directory that is not the top of a git checkout of its own.
- **Unreleased code has its own version name, `X.Y.Z+<short sha>`** (`X.Y.Z+unknown` without git;
  `jig_source_version`). `scripts/lib/version.sh` is unchanged and always plain: CI, the release job
  and every ordering helper read it as before. Comparisons and orderings use the release number
  (`jig_version_core`); `jig_release_version` stays strict.
- **`jig init` and `jig upgrade` in copy mode refuse an unreleased source**, dry run included, as
  `unreleased-source`, naming where the checkout stands and the two ways out: back to a release, or
  `--unreleased`. A dry run refuses too, because a plan the real run would refuse is no plan. Link
  mode is not affected: there the project runs the checkout itself, which is what developing Jig is.
- **`--unreleased` takes the code on purpose, and the project says so**: the manifest records
  `jig.version: X.Y.Z+<sha>`. The next upgrade from a released source replaces the files by hash and
  records the plain number again. Whatever re-runs an upgrade carries the flag: the handoff to newer
  code and the self-check after the install.
- **An unreleased source is not measured against.** `upgrade_pending` answers 4 — unknown, for this
  reason — so `verify` runs (ADR-0017's unknown), `jig doctor` warns instead of failing, and the
  drift count is omitted. This narrows ADR-0017 and adr-20261029: the global framework stands in for
  a missing source only when it is a release.
- **Unreleased code is said wherever a version is shown.** `jig --version` run from a framework
  checkout prints `X.Y.Z+<sha>` off a tag and the plain number at one (the installer and
  `self-update` check exactly that); `jig status` compares the global framework by that name, says
  "development channel" for an unreleased global and "carries unreleased Jig" for a project that
  took some, and offers no upgrade to unreleased code; `self-update` on a branch and `install.sh`
  installing anything but a release tag say that copy-mode projects will not take files from it.
- **Developing Jig is a separate clone in link mode**, and the global framework stays on a release
  tag; `CONTRIBUTING.md` says how.

## Alternatives

- **Only an instruction.** It protects the people who read `CONTRIBUTING.md`, and the colleague in
  question was not developing Jig at all.
- **A pre-release suffix in `version.sh` on `main`** (`0.41.0-dev` after each release). It adds a step
  to the release process, breaks the strict checks in CI (`release-tag.sh`, `epic-pr-check.sh`), and
  still calls every commit of `main` by one name.
- **Forbid `--ref main`.** It removes the development channel ADR-0033 keeps, and does not cover a
  clone made by hand.
- **Warn instead of refusing.** The upgrade in the incident was run by an agent; a warning is read by
  nobody there.
- **An environment variable to bypass the check** (for tests, for tools). A switch an agent can set
  silently is what this decision exists to prevent; the tests install from a released copy instead.
- **Treat local changes on a release tag as unreleased.** Not now: `self-update` already refuses a
  dirty global checkout, the incident was a branch, and a `git status` of the global checkout on every
  `jig status` costs real time on Windows. When it is wanted, reuse `self-update`'s cleanliness check,
  which pins `--untracked-files=all`.

## Consequences

- A copy-mode project gets framework code from a release, or from code someone named with
  `--unreleased`, and its manifest says which.
- A framework developer whose global jig is their working clone is refused in other projects; their
  ways out are a released global install beside the clone, or `--unreleased`.
- `install.ps1` set up with `-Ref main` cannot prepare a first project without `--unreleased`: its
  `jig init` is refused and it reports the failure. Known and accepted.
- The test runner installs from a released copy of the checkout (`tests/run.sh`, `JIG_HOME`), so the
  suite exercises the released path by default and the unreleased one where a test asks for it.
- `jig status` reads the global checkout's git (tag and HEAD) besides its `version.sh`; it still
  never runs the global executable (ADR-0033).
