---
id: adr-20261029-an-upgrade-pull-request-is-landed-by-jig
type: adr
status: accepted
date: 2026-10-29
domains:
  - housekeeping
paths:
  - scripts/lib/upgrade.sh
  - scripts/lib/status.sh
  - scripts/lib/forgecache.sh
summary: Why jig status follows an upgrade's pull request from the forge cache and jig upgrade --land brings a merged one here, and what it refuses.
reviewed_at: 2026-11-11
---
# ADR: An upgrade that ended in a pull request is followed by `jig status` and landed by `jig upgrade --land`

## Context

At `agent.git: pr` an upgrade ends with its pull request open on `jig/upgrade-<to>` and the main
checkout back on the base branch, still at the old Jig. Nothing in the project said so afterwards:
`jig status` kept offering `upgrade-available`, and a program that upgrades projects (Jig UI) knew
of the pull request only while it remembered the run. In fapost-core it forgot on a restart, offered
Upgrade again, and `jig upgrade` cut `jig/upgrade-<to>-2` — a duplicate pull request (#323) after
the real one (#322) had merged. Once merged, bringing the upgrade into the checkout was the
person's git work: switch to the base, pull, delete the branch. Jig UI may not run git itself
(every change it makes is a jig command), so that step had no owner.

## Decision

- The forge cache gains two columns, `<head_commit>` and `<url>`, after `<fetched_at>`, written by
  housekeeping from the list it already fetches. A line an older run wrote ends at `<fetched_at>`
  and reads as both unknown.
- `jig status` reads the upgrade's pull request from that cache and never from the forge: the newest
  line of each `jig/upgrade-*` branch into `git.base_branch` makes `upgrade-pull-request-waiting`
  while `open` and the base here does not record its version yet — a landed upgrade goes quiet
  at once, before housekeeping hears the merge — and `upgrade-pull-request-merged` while `merged` and the base branch here still
  records an older Jig than the version the branch is named for. While either stands,
  `upgrade-available` is not said. (Amended 2026-10-30: only while it stands for this machine's
  version or a newer one, or for a branch whose name holds no version. A pull request for an older
  version — one nobody merged or closed — no longer hides the newer upgrade: it would have held it
  back for good; task upgrade-land-followups.)
- `jig upgrade --land` is the step after the merge. It asks the forge, because only the forge knows
  whether the pull request merged; refuses `not-merged` while it is open and `upgrade-blocked` for a
  dirty tree, a checkout on another branch than the base or the upgrade's (amended 2026-11-13: no
  longer refused, see the last bullet), a linked worktree on the upgrade's
  branch (amended 2026-10-30: it is never switched to the base, as `jig_ship_leave` never switches
  one — run it in the main checkout), a base checked out in another worktree, or a base origin's
  cannot fast-forward — every reason at once, nothing changed.
  Otherwise it checks the base out, fast-forwards it to `origin/<base>` and lets the upgrade's branch
  go through `jig_ship_leave`, as after a merge Jig made itself; the merged head is passed for origin
  only at `agent.git` `push` or above, as housekeeping's sweep does. It never stashes and never
  forces. A forge CLI that fails is `the forge did not answer`, never an empty list: its exit status
  is read on its own, not through the pipeline that parses its answer.
- (Amended 2026-11-11, task upgrade-refusal-names-open-request.) `jig upgrade`, refusing a second
  branch for the upgrade to a version already on an unmerged `jig/upgrade-<to>` branch, asks the
  forge once, only on that refusal, through the same list `--land` reads: an open pull request from
  that branch is refused `not-merged` with its URL — the upgrade is done and waits for its merge,
  which a program shows as waiting, not as a failure; a merged or closed one is named with its
  state and reads `failed`. No forge, a bad `forge:` value or a forge that did not answer leave the
  refusal it always was: the lookup can add a pull request to the message, never another error.
- (Amended 2026-11-13, task gitlab-upgrade-mr-in-status.) `jig upgrade` that leaves its pull
  request open — opened, or found already open — writes it into the forge cache itself, as `open`,
  in place of any older line for the same branch and base, every other line kept
  (`forgecache_record`). Housekeeping is started by a session in the project, so an upgrade made
  from anywhere else went unmentioned by `jig status` until then: a GitLab project nobody opened a
  session in for weeks showed only `upgrade-available` while its merge request waited. The next
  housekeeping run still replaces the whole cache with what the forge says. Housekeeping's GitLab
  list asks for 100 merge requests, GitLab's largest page, not glab's default 30.
- (Amended 2026-11-13, task upgrade-land-without-checkout.) A checkout on a third branch — neither
  the base nor the upgrade's, a detached HEAD included, in the main checkout or a linked worktree —
  is no longer refused and never switched: other sessions may be working in it. `--land` moves only
  the base, by `git fetch . refs/remotes/origin/<base>:refs/heads/<base>` — a fast-forward only, so
  a commit that reached the base after the checks is never lost, and refused by git for a branch
  any worktree has checked out or is rebasing or bisecting, which `update-ref` would not refuse. A
  clone with no local base gets one from `origin/<base>`, tracking it. The upgrade's branch goes
  through `jig_branch_leave` with the merged head for the local branch at every level — `git branch
  -d` measures a branch without upstream against HEAD, which here is not the base — and for origin
  only at `agent.git` `push` or above. Since the tree is not touched, uncommitted changes are no
  reason to refuse there; a base checked out in any worktree, a base with commits origin's lacks and
  an `origin/<base>` without the upgrade still are. The checkout takes the upgrade when it next
  merges the base; a `next:` line says so while the checkout records another Jig than the base, and
  `--json` reports `land.checkout_on_base: false`. On the base or the upgrade's branch nothing
  changed: the tree is moved, so a dirty tree still refuses.

## Alternatives

- **Jig UI runs git itself** after the merge: rejected by its own rule that every change is a jig
  command, and every other program would have to repeat the same git steps and their refusals.
- **`jig upgrade` lands a merged upgrade before upgrading again**: one command doing two things a
  person decides apart, and a merge it did not see happen; it also would not tell a reader the pull
  request is still open.
- **`jig status` asks the forge**: breaks the rule that a read never touches the network
  (adr-20261015-a-read-is-one-json-envelope); the cache is as fresh as housekeeping, and `--land`
  asks the forge itself before it acts.
- **Read "merged" from `origin/<base>` alone** (its manifest carries the version): needs a fetch in
  `status`, and gives no head to delete origin's branch at.

## Consequences

- A program shows "waiting for merge" from the project, across restarts, and gates its buttons on
  the two kinds and on `jig upgrade --land --json` (schemas/json.md).
- The items are as old as the last `jig housekeeping`; `housekeeping.stale` says when that matters.
- `jig_ship_leave` has a third caller; RULES.md's deletion paragraph names it.
- The cache format is read by version: a mixed-version clone whose older jig reads a new line sees
  the new columns in `fetched_at`.
