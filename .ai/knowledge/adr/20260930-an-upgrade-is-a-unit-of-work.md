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
  - scripts/lib/checkout.sh
summary: A real copy-mode upgrade hands itself to newer code, refuses a dirty tree, CRLF clone, a started task on HEAD or a running verify, works on its own branch cut from the base, and commits once after the self-check, shipping as far as agent.git allows.
reviewed_at: 2026-10-05
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
   `.ai/manifest` has no `eol=lf`; a live session is recorded in this checkout
   (`jig_checkout_busy`, the task checked out here excepted); `jig verify` holds the clone's run
   record for this same checkout. A run in another worktree executes its own files and does not
   stop it. The exception is a known limit: the dispatcher records every command run on a task's
   branch under that task's name — this upgrade included — so a second session on the same task
   in the same checkout cannot be told from the one running the upgrade. *The session stop is
   replaced by the amendment of 2026-10-05 below: the one occupancy rule of `task start`, with no
   exception for the task on HEAD.*
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

## Amendment 2026-10-05: an upgrade refuses only an occupied HEAD

**What happened.** On 2026-10-05 an upgrade 0.17.1 → 0.20.0 in an installed project, run from
`main`, refused twice over: a session that had run `jig status` three hours earlier, and one that
had run `jig task show` on a task whose branch was not checked out there. The only way out was to
delete files the message did not name. Meanwhile `task start` had been narrowed
(adr-20260924-a-checkout-records-what-is-happening-in-it): a record named by a session id, a task
never started, closed, or whose branch left HEAD occupies nothing. The upgrade did the inverse —
it counted every one of those, and excepted the one task whose HEAD it moves.

**Decision.**

- **One rule, one function.** Who occupies a checkout is `jig_checkout_occupants`
  (`scripts/lib/checkout.sh`): a fresh record named by a task that has been started, is not
  `consolidated` or `abandoned`, and whose branch is the one checked out here. `task start` and
  `upgrade` both read it; neither keeps a filter of its own. `jig status` still reports the wider
  `jig_checkout_busy`: a report may say more than a refusal acts on.
- **No exception for the task on HEAD.** It is exactly the task the upgrade takes off this
  checkout when it switches to `jig/upgrade-*`. With the narrowed rule and that exception kept,
  the stop could never fire. The dispatcher records the upgrade's own run under that task's name,
  so for an upgrade the record is always fresh: in effect it refuses whenever a started, live task
  is on HEAD. That is the same rule, and the same known false refusal `task start` accepts — a
  record named by a task cannot say which session wrote it, so the person running the upgrade on
  their own task's branch is refused too. The exit costs one command and touches nothing.
- **The refusal names the task, its branch and the record, and the exit for a finished session**:
  `jig task start <id> --worktree`, which gives the task its own worktree and puts this checkout
  back on its base branch, then `jig upgrade` again; or waiting, while another session still works
  on it. In a linked worktree (ADR-0029) that exit does not exist — the task already has its
  worktree, and git keeps the base branch in the main checkout — so there the refusal says to run
  the upgrade in the main checkout. It quotes no age or command — they would describe this upgrade — and does not suggest
  deleting the record, which the next run would rewrite anyway.
- **Asked only where HEAD moves**, as in `task start`: not with `git.branch_per_task: false`, and a
  repeat on the upgrade's own branch holds no task.
- **A session that only oriented itself does not protect the scripts.** The upgrade also replaces
  the scripts, so the question was asked separately and answered no. A record says a command ran
  within `checkout.busy_ttl`, not that one is running, and cannot tell a live session from one
  that ended hours ago — that is the refusal above. Between commands, the swap is the upgrade
  doing its job: the session's next command runs the new version whole. The harm is confined to a
  command executing during the swap, and the long one that suffered it, `jig verify`, has its own
  stop whose record lives exactly as long as the run. Should another long command need the same,
  the answer is a record of *that command running*, not a wider reading of "someone was here".
  A coordinator on the base branch loses HEAD to the upgrade as it would to `task start`, and gets
  the moved-HEAD notice on its next orienting command; the upgrade also prints the way back.

**Consequences.** An upgrade from the base branch is no longer stopped by records at all; one run
from a started task's branch always is, with the way out named. `jig upgrade --dry-run` on such a
branch prints it as a note, as it prints every stop.
