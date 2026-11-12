---
id: adr-20261112-release-notes-name-the-commit-they-describe
type: adr
status: accepted
date: 2026-11-12
domains:
  - task
  - spec
paths:
  - scripts/lib/task.sh
  - scripts/lib/spec.sh
  - scripts/lib/common.sh
  - "skills/jig-release/**"
  - .github/scripts/changelog-check.sh
  - .github/scripts/epic-pr-check.sh
summary: Why feature work never raises the version, why a release is its own notes pull request from the fresh default branch, and how the Release-Notes-Through trailer keeps work merged after the notes out of an undescribed tag.
---
# A release is made apart from feature work, and its notes name the commit of the base they describe

## Context

Until 0.45.0 a feature epic released itself: `jig spec epic --finish` was followed by a version
raise by the roadmap's `Release:` level, and CI's `epic-pr` job refused an epic's final pull request
whose `JIG_VERSION` was already released (ADR-0040). The notes were written on the epic, over
`git log <last-tag>..HEAD`.

The review of fapost-lab/jig#489, the staging-branch epic, showed two faults of that shape. The
epic had written `0.45.0` into `version.sh`, the manifest and the changelog weeks before its merge;
meanwhile 0.44.0 was released from `main` (#488), and the three files conflicted, with the epic's
changelog jumping from 0.45.0 to 0.43.0. Nothing was lost that time because 0.44.0 described the
work merged into `main`. In general it would have been: `<last-tag>..HEAD` on an epic does not
contain what reached `main` after the epic was cut, and even after `main` is merged into the epic,
other pull requests keep reaching `main` until the release merges. Everything merged after the
notes were written goes out in the tag undescribed.

`main`'s branch rule in this repository requires `ci-ok` but not an up-to-date branch
(`strict_required_status_checks_policy: false`), so a green check is not re-run when `main` moves.

## Decision

- **Feature work never raises the version.** A task, and an epic's final pull request, merges into
  the default branch without a version change. An epic whose roadmap has no `Release:` line is a
  feature epic: `jig spec ship` in `final` mode refuses one that raises the version — committed on
  the epic or staged with the finish — before anything is sent, and `--finish` prints
  `release: none`. ADR-0040's reason against merging into `main` without a raise — half a feature
  on `main` — no longer applies: an epic merges finished.
- **A release is its notes task**, planned by `jig-release`: the last pull request, cut from the
  freshest default branch, raising the version by a level read over everything since the last tag.
  A release epic (`Release:` line, declared by `jig-release`) remains for tasks that must reach the
  default branch together; its final pull request is the release.
- **The notes name the commit of the base they describe.** The notes task records it,
  `jig task set <id> notes_through <sha>` (the full sha is kept; a value that is not a commit is
  refused), and `jig task ship` writes it into the commit as `Release-Notes-Through: <sha>`. Git is
  where every reader finds it, whichever task wrote it.
- **One question, asked in three places**, `jig_release_notes_gap <tip>` (common.sh, git only):
  the newest trailer among the branch's own commits must name a commit on the base, and the base
  must have no commits after it. `jig_release_notes_refusal` asks it against `origin/<base>`
  fetched now as the clone's account; a failed fetch is a refusal.
  - `jig task ship`, for a change that raises the version into the default branch, at `pr` and
    `merge`: refused before the push (`not sent: …`; the commit stays local), and at `merge` asked
    again after CI is green, right before the merge command (`not merged: …`). `push` is not
    checked: a person opens that pull request.
  - `jig spec ship` in `final` mode, for a release epic, the same way.
  - CI's `changelog` job in this repository, for a pull request into `main` declaring an
    unreleased version, with the full history checked out. A pull request into a release epic is
    not asked: its notes name a commit of `main` and the epic's own commits come after it; the
    epic's final pull request into `main` is.
  - A notes commit with no file change — the base moved by commits no user notices — is still
    made, empty but for its message, so the newer trailer reaches git.
- **The after-CI question is a hook**, `JIG_SHIP_LAST_CHECK` in `jig_ship_merge`: a function the
  caller names, asked after the CI wait and before the merge command on both forges. A check made
  before the wait would miss what merged during it.
- **CI's `epic-pr` job no longer requires an unreleased version**: it checks the epic is finished
  (its spec removed) and the version well-formed. It does not check that a feature epic leaves the
  version alone: the roadmap that says which kind it is was removed by the finish, `spec ship`
  refuses the raise before sending, and in this repository a raise without notes reaching `main`
  fails the `changelog` job anyway.
- **The `Release:` line tells the kinds apart.** An epic declared with one, as before, is a release
  epic; without one, a feature epic. A feature epic declared before this decision with a line is
  still a release, which is what it was declared as.

## Alternatives

- **A long-lived release branch (gitflow).** Rejected: it moves the race to keeping that branch in
  step with `main`, and adds a third branch to keep in agreement.
- **Containment only — the release branch contains `origin/main`.** Simpler, no new field. Rejected:
  merging `main` in is one command that need not look at the changelog; the marker makes revisiting
  the notes an explicit act.
- **The marker in the changelog** (`<!-- notes-through: <sha> -->`). Visible in the diff, but an
  installed project may keep no changelog or keep it anywhere, and `task ship` would have to know
  where. A trailer and a state key are project-neutral.
- **A stamp written by every ship.** Rejected: it would move with each ship and prove nothing about
  the notes.
- **The CI check alone.** Rejected: installed projects get the commands, not this CI (ADR-0034).
- **Strict status checks alone.** They make a branch update before the merge, not the notes: the
  branch is updated, CI is green, the changelog is unchanged.
- **Freezing `main` during a release.** Discipline, which Jig exists to remove.
- **Keeping the epic as the release and adding only the notes check.** Closes the race but not the
  collision of version numbers chosen weeks before the merge.

## Consequences

- A release made as these rules say cannot carry undescribed work into a tag when an agent merges
  it. A person merging from the forge's page is protected only by CI, and in this repository CI is
  not re-run when `main` moves unless strict status checks are switched on — the owner's setting,
  not changed by this decision.
- Each merge into the default branch while a release waits costs the notes task one more round:
  describe it, record the new tip, ship again.
- A release merged with squash keeps the trailer only if the squash message keeps it; the check
  reads the branch before the merge, so this matters only to someone reading `main`'s history.
- Between a feature epic's merge and the release, `main` holds unreleased work; a fix released
  then carries it, and its level is read over all of it.
- The trailer is read from the branch's own commits, so on a release epic the notes task's commit,
  merged into the epic, carries it to the final pull request. A squash merge into the epic whose
  message drops the trailer loses it, and the final pull request is refused until a commit carries
  it again; merge into a release epic with a merge commit.
- The trailer is an attestation by whoever wrote the notes, not a proof that they read every
  commit; it makes the moment of reading explicit and refuses a release once that moment is stale.
