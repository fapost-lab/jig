---
id: adr-20260930-an-upgrade-is-a-unit-of-work
type: adr
status: accepted
date: 2026-09-30
domains:
  - install
paths:
  - scripts/lib/upgrade.sh
  - docs/upgrading.mdx
  - scripts/lib/common.sh
summary: A real copy-mode upgrade hands itself to newer code, refuses a dirty tree, CRLF clone or busy checkout, works on its own branch cut from the base, and commits once after the self-check, shipping as far as agent.git allows.
reviewed_at: 2026-09-30
---
# A copy-mode `jig upgrade` is a unit of work: checked, run by the newest code, on its own branch, one commit

## Context

Until 0.16.1 `jig upgrade` wrote into whatever tree it was run in, on whatever branch was checked
out, with whatever code happened to run it, and left the result for someone to commit. Each of
those produced an incident in one week:

- **Old code upgrading to new.** `line 133: cmd: unbound variable`, the template 0.15.1 deleted
  because it did not stage it, and the project with a clean filter whose old copy replaced its
  entry point but not its libraries (`jig_clear_git_location_env: command not found`, rc=127) —
  all four were the version being replaced doing the replacing.
- **The current branch.** Run on a task's branch, an upgrade rode into that task's pull request.
- **A dirty tree.** An upgrade mixed with somebody's uncommitted work cannot be reviewed or undone
  as one change.
- **A run in progress.** Scripts replaced under a running `jig verify` turned one run into 34
  false failures on 2026-09-26.
- **Line endings.** In a clone with `core.autocrlf=true` and nothing pinning Jig's files to LF,
  every hash in the manifest is of other bytes, and `jig status` still reports `drift: 0`.

## Decision

In copy mode a real `jig upgrade` runs in this order, and nothing is touched before step 3:

1. **The newest code does the work.** When the running `JIG_VERSION` is older than the source's,
   the run is handed whole to `bash <source>/scripts/jig upgrade --from <source>`, with
   `JIG_UPGRADE_HANDED_OFF` in the environment. A handed-off run still older than its source
   refuses and names `jig self-update`. This protects only from the first version that has it.
2. **It may start.** Refused, all reasons at once, when: tracked files have uncommitted changes
   (untracked do not count — the rule of `task start`); `core.autocrlf` is true and
   `.ai/scripts/jig` has no `eol=lf`; a live session is recorded in this checkout
   (`jig_checkout_busy`, the task checked out here excepted); `jig verify` holds the clone's run
   record for this same checkout. A run in another worktree executes its own files and does not
   stop it. The exception is a known limit: the dispatcher records every command run on a task's
   branch under that task's name — this upgrade included — so a second session on the same task
   in the same checkout cannot be told from the one running the upgrade.
3. **Its own branch.** `jig/upgrade-<to-version>` (`-2`, `-3` when taken), cut from the fresh
   `git.base_branch` the way `task start` cuts, never from the current branch — a base that exists
   neither here nor on origin is a refusal, not a fallback to HEAD. An unmerged branch already
   holding the upgrade to this version is a refusal too, naming it: a second branch could only
   become a second pull request. A run already on a
   `jig/upgrade-*` branch stays there, and its uncommitted changes do not stop it: that is how an
   interrupted upgrade is repeated (adr-20260926-an-interrupted-upgrade-is-repeated-not-rolled-back).
   With `git.branch_per_task: false`, or no commit yet, there is no branch.
4. The upgrade itself, unchanged.
5. **The self-check decides the commit.** An install the newly placed dispatcher does not confirm
   complete is not committed.
6. **One commit** of what the run changed: every tracked change (the tree was clean) and the
   untracked paths the manifest owns, `.ai/manifest` and `AGENTS.md`. Its message carries the
   versions from and to, the run's summary line, a `Manual steps:` section and the Upgrading page.
   Nothing changed — the run goes back to where it started, deletes the branch it cut, and, when
   that was not the base, says to merge the base in: that is where a stale task branch gets it.
7. **As far as `agent.git` allows**, by `task ship`'s own `jig_ship_*` steps: `none` stages and
   prints the one `git commit -F` to run; then commit, push, pull request, merge on green CI.
   Nothing leaves the machine without a branch of the upgrade's own, or without an `origin`.

A dry run stays read-only (ADR-0017): no hand-off, no branch, no refusal — each reason is printed
as `note: a real upgrade would stop: …`. `upgrade_pending` skips the checks altogether.

**Link mode is out of scope.** There the scripts are the source checkout itself, so no old code
runs and no script is replaced under anything; and it is how the framework installs itself, where
`jig upgrade` is a development step on a tree that is dirty by design.

The installers do not upgrade projects — they install the global checkout — so none of this
applies to them.

## Alternatives

- **Refuse instead of handing off to newer code.** Rejected: the newer code is on the machine and
  the person asked for the upgrade; a refusal would only ask them to type another command.
- **Branch from the current branch.** Rejected: that is the leak into a task's pull request.
- **Stop at the pull request even at `agent.git: merge`.** Rejected: the level is the person's
  statement of how far the agent goes, and `task ship` honours it the same way; manual steps are
  carried in the pull request and the commit.
- **Refuse a dry run on a dirty tree.** Rejected by ADR-0017: `status`, `verify` and `doctor` run
  one each time.

## Consequences

- An upgrade is one reviewable, revertible commit, never mixed with other work.
- Branches in flight do not have the upgrade until the base is merged into them; the run says so.
- `_upgrade_manual_steps` is the one place the commit and the pull request take their manual steps
  from; `upgrade-carries-its-own-checklist` fills it.
- The read side of the verify run record moved to `common.sh` (`jig_verify_busy_*`), since one
  command library never sources another.
