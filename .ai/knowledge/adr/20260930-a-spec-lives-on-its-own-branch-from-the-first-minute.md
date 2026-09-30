---
id: adr-20260930-a-spec-lives-on-its-own-branch-from-the-first-minute
type: adr
status: accepted
date: 2026-09-30
domains:
  - spec
paths:
  - scripts/lib/spec.sh
  - scripts/lib/task.sh
  - "skills/jig-idea/**"
summary: Why jig spec new and the new jig spec resume cut a spec's own branch (spec/<id>) instead of leaving it uncommitted on the default branch until spec ship.
reviewed_at: 2026-09-30
---
# A spec lives on its own branch from the first minute

## Context

`_task_refuse_dirty_tree` (`task start`) refuses tracked, uncommitted changes so that
one task's work-in-progress never rides onto another task's branch as its first commit
(ADR-0026 as amended, the 2026-09-11 incident RULES.md's deletion paragraph also cites).
Until this change, `jig spec new` created `spec.md`/`roadmap.md` as untracked files and
left the checkout on whatever branch it was already on — no branch of the spec's own, no
dirty-tree check. Untracked files never block that refusal, so a brand new spec never
tripped it; the trap was a *second* session over an already-merged, tracked spec:

- Discussion continues after a spec's first declaration is merged (`spec.md`/`roadmap.md`
  are now tracked); `jig-idea` edits them, uncommitted, on the default branch.
- §10 of `jig-idea` ("file a phase's tasks") rewrites `roadmap.md` with the filed task
  ids, the same way — an edit `jig spec new` had already run and gone by the time it
  happens.

Either way, by the time the person tries `jig task start` for something else, the tree is
dirty with no branch to send it to, and the refusal's own advice — "commit them" — has no
door on `main`, which this project accepts pull requests into only. A live user hit exactly
this with the `terminal-output` spec, sitting uncommitted on `main` since 2026-09-26.

## Decision

A spec is cut from the default branch onto its own, `spec/<id>`, at the point it starts
being written — `jig spec new` for a brand new one, a new `jig spec resume <id>` for an
existing one a session returns to — mirroring what `task start` already does for a task's
`task/<id>` (ADR-0029). Both refuse a dirty tree first, by the same rule `task start` uses
(`jig_tracked_changes`, `common.sh`, shared so the two cannot drift on what "dirty" means).

The branch-cutting mechanic itself is one function, `_spec_cut_own_branch`, extracted out
of `spec_ship_declare`'s existing "switch to `spec/<id>` when here is the default branch"
code (which used to be the only place a spec ever got its own branch, at ship time) and now
shared by `spec_new`, `spec_resume`'s fallback, and `spec_ship_declare` itself — kept for a
spec still authored by hand, directly on the default branch, an older jig or a hand-made
one. `spec_resume` additionally reuses a branch still here (locally or fetched from origin)
through `_spec_switch_to_existing_branch`, since — unlike a brand new spec — an existing
one's branch may already exist from an earlier session.

`spec resume` refuses when the spec's roadmap already declares an open epic: that spec is
edited on the epic branch instead (an existing rule, `jig-idea` §10), and cutting a
`spec/<id>` nobody would ever ship would just be a second, unused branch.

As insurance for a spec already sitting dirty this way (the `terminal-output` case), `task
start`'s own refusal now recognises when every tracked change lies under one spec's
directory and names `jig spec ship <id>` instead of "commit them" — `_task_dirty_only_spec`
in `task.sh`, reading `git status --porcelain` the same way `jig_tracked_changes` does.

## Alternatives

- **Only fix the refusal's text**, leaving specs branchless until `spec ship`. Rejected: it
  narrows the original bug (the *second-session* trap) but the owner's later instruction
  generalises the fix to `spec new` too, so a spec never sits dirty on the default branch
  in the first place — the same reasoning ADR-0029 gave a task its own branch for.
- **A bare `git switch`/`git checkout -b` described in `jig-idea`'s prose**, as the skill
  already does for switching to an *existing* epic branch. Rejected for *creating* a
  branch: validating a ref name and refusing one that already exists is exactly the
  mechanics `jig <command>`s exist to own instead of skills (RULES.md, "Skills reference
  `jig <command>` for mechanics").
- **Fold "resume" into `spec new` itself**, made idempotent on an existing id. Rejected:
  `spec new` dying "already exists" is a real signal (a taken id, a typo) that an idempotent
  `spec new` would swallow silently.

## Consequences

- `jig spec new`'s and `jig spec resume`'s output and exit code change: both can now refuse
  a dirty tree, require being on the default branch first, and print `switched to
  spec/<id>` (or `already on spec/<id>`) on success. A script or skill written against the
  old `spec new` (create only, no branch) sees a different current branch afterwards.
- `jig-idea` §1 opens every session — new or existing spec — with the branch already
  switched, before a single file is read or written; §9 ships what changed as its last
  step, rather than leaving it for the next `jig spec ship` to discover; §10's roadmap
  rewrite therefore always happens on `spec/<id>` (or the epic), never straight on the
  default branch, closing the second path into the original trap.
- Existing fixtures in `tests/spec.t.sh`, `tests/status.t.sh` and `tests/task.t.sh` that
  called `jig spec new` and then committed assuming they stayed on the default branch
  needed a `git checkout` (or a merge, where an intermediate commit already existed) back
  to it; two (`sship_declared`, `sship_cut`) instead build the spec directory by hand,
  deliberately bypassing `spec new`, to keep `spec_ship_declare`'s own hand-authored-on-main
  fallback covered.
