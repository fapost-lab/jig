# Epic branches: one release pull request per feature

Depth: deep — it changes what "landed" means for housekeeping, which decides when a workspace is
destroyed, and how every multi-phase feature reaches `main` and a release.

## Idea

Translated from Russian; the maintainer's words, 2026-09-15, in order.

- "If a spec closes a feature, what is the point of creating new branches and separate pull
  requests, when no phase gives a finished solution? Instead we do all phases in one branch as
  separate commits, and at the end one pull request and a version bump — that is logical."
- "We need to solve this fundamentally. If each task has to be separate so that housekeeping works
  correctly, then we need to come up with something so that there is one pull request into main,
  with the version bump. For example, as an idea: we create a branch from main for the idea (an
  epic branch), all tasks are pull requests into it, and after all phases it goes by pull request
  into main with the bump."

## Goal and problem

In one sentence: a feature planned as a spec lives on its own epic branch cut from `main`; each
phase's task branches from the epic and merges into it by pull request; when every phase is done,
the epic reaches `main` in one pull request that raises the version.

- Who is worse off without this, and how: whoever runs a feature of several phases. Today every
  task's base is `main` (`git.base_branch`, one value for the project), so there are two bad roads:
  a pull request and a release per phase, which ships half a feature (v0.5.0 shipped stubs nobody
  could accept); or one task for every phase, which loses per-phase tasks, gates and the tracking
  housekeeping does per task branch.
- What is true when the work is done: each phase has its own task, gate, review and pull request
  into the epic; housekeeping flags and cleans up a phase's task once its pull request is merged
  into the epic; `main` receives one pull request per feature and exactly one release, with the
  finished feature.

## Stress test

The failure modes come from an independent hunt in a clean context (2026-09-15), ranked by
likelihood times cost, against the decisions below as first taken.

- Hidden assumptions:
  - A task started for a spec with an epic ends up on the epic — holds only if the epic ref is
    present locally, the `Spec:` line exists before `task start`, and the pull request targets the
    epic. None of the three is guaranteed, and the fallback is `main`, silently.
  - "An epic exists exactly when its branch exists" — holds only while nobody keeps a merged epic:
    this repository never deletes merged branches.
  - Merging `main` into the epic is routine — holds only while nothing large runs in parallel;
    `windows-support` touches the same files (`task.sh`, `housekeeping.sh`, `common.sh`).
- The main trade-off: one release per finished feature, against a second long-lived line of history
  that has to be kept current, protected and eventually merged.
- The weakest point: every way a phase reaches the wrong branch looks, to housekeeping's forge tier
  (`headRefName` and `state` only), exactly like a correct merge.
- Failure modes — cause, what breaks, the signal that shows it:
  1. **Phase work lands on `main` silently.** No fetch before `task start`, a missing or late
     `Spec:` line, or a pull request created against the default branch sends a phase to `main`;
     the forge tier reads it `merged`, the task is closed and trashed, and the next release from
     `main` ships half a feature. Signal: none from Jig.
  2. **A leftover epic swallows work that never ships.** A merged `epic/<id>` is never deleted, so a
     follow-up task is cut from it, merged into it, closed and trashed; the code never reaches
     `main`. Signal: only the epic falling further behind `main`.
  3. **The `main`→epic merge drops parallel work unreviewed.** The conflict is resolved in a merge
     commit pushed straight to the epic: no pull request, no CI (`push` CI runs only for `main`), no
     Windows runner. Parallel ADRs collide on a number. Signal: bug reports after the release.
  4. **Bare base names resolve the wrong ref.** Helpers resolve the base by short name, local first:
     a teammate without a local epic gets an empty touched-files set, the creator a stale one;
     `task start` refuses when local and remote epics diverged. Signal: wrong `knowledge changed`.
  5. **Housekeeping takes unfinished work.** A stacked phase pull request merged into another phase
     branch reads `MERGED`; deleting the epic closes open phase pull requests, which reads as
     "abandon it"; a reflog cache still keyed to `main` counts every epic commit as the branch's own
     work (ADR-0032) and flags a paused task whose stash then goes with its workspace; a rebased epic
     loses commits of tasks already trashed.
  6. **The final merge tags nothing.** `main` released the same version meanwhile; the release job
     finds it and exits 0. Signal: no new tag.
  7. **Spec and roadmap split across two lines.** Filing a task edits the tracked roadmap and blocks
     `task start` on a dirty tree; ids and checkmarks conflict between `main` and the epic; `main`
     shows 0 done for the feature's whole life; knowledge written by phases is invisible on `main`.
  8. **Per-phase records are gone before the final review.** A closed phase's workspace is deleted
     after `trash_ttl`, weeks before the epic pull request is reviewed.
- Other shapes considered, and why this one:
  - Phase pull requests into `main` without a version bump, the last phase raising it — one release,
    no framework change; rejected: half a feature on `main` blocks a patch release from `main`, and
    any unrelated pull request that raises the version ships it.
  - One task for the whole feature — works today; rejected: one design, one knowledge decision and
    one `spec done` for every phase, and weeks of uncommitted work on one branch.
  - Maintenance lines (`release/<major>.x`) need the same foundation — a base per task — and are
    kept in view rather than built now.

## Scope and non-goals

- In scope: a recorded base per task and everything that judges a task against it; the `wrong-base`
  flag; the `Epic:` line and `jig spec epic` with `--finish` and `--reopen`; starting a linked task from
  its epic; keeping closed phase workspaces until the epic reaches `main`; how `spec list` and
  `jig status` show an epic; this repository's CI for epic pushes and the final pull request; the
  `jig-idea`, `jig-task` and `jig-consolidate` skills.
- Not doing: maintenance lines (a fog item below); a CI check for projects that adopt Jig; resolving
  knowledge written on an epic from `main`; detecting ADR number collisions between branches; a
  forge-side rule that stops a pull request into the wrong base.

## Decisions

- Epic branches are the shape for a multi-phase feature — rejected: phase pull requests into `main`
  without a version bump, because half a feature on `main` blocks a patch release from `main` and
  any unrelated pull request that raises the version ships it — decided by the maintainer on
  2026-09-15.
- The foundation is a base per task, recorded in its `state`, and it is the first thing built:
  epic branches stand on it, and so will maintenance lines.
- This spec is built as one task for both phases — one branch from `main`, a gate per phase, the
  phases as commits, one pull request raising the version — because the epic tooling it delivers
  does not exist yet and phase 1 alone gives no user anything. The spec reaches `main` with that
  pull request. `knowledge-adoption` phases 2 and 3 wait for it and become the first feature built
  on an epic — decided by the maintainer on 2026-09-15 — rejected: two pull requests into `main`
  with the version raised in the second, the shape this spec rejects for features.
- Implementation constraints from the failure hunt: a task's base is resolved as `origin/<base>`,
  never by bare name; the base reflog cache is built per base, never for `main` alone (ADR-0032).
- Maintenance lines — `release/<major>.x` as a task base, tags cut from them, `jig self-update`
  staying within a major version — belong to this spec as a later area, not to a separate one: they
  share the foundation. They become roadmap items when the first maintenance line is needed.
- An epic branch is used only for a spec that is released once, at the end. A spec of one task, or
  one whose phases are each useful on their own, keeps working against `main` as today — decided
  by the maintainer on 2026-09-15 — rejected: an epic branch for every spec, which adds a branch and
  a pull request where a phase already is the finished feature.
- A spec declares its epic with an `Epic: epic/<spec-id>` line in `roadmap.md`, written by
  `jig spec epic <id>`, which also creates the branch from the freshest `main`; pushing it is the
  human's step. `jig task start` fetches the epic and `main` first; refuses when the line is there
  and the branch is not, instead of falling back to `main`; and refuses to cut a task from an epic
  already merged into `main` — revised 2026-09-15 after the failure hunt (failure modes 1, 2) —
  rejected: the branch's existence alone as the signal, which cannot tell "no epic" from "the epic
  ref was never fetched" and keeps a merged epic alive for ever.
- Housekeeping's forge tier also reads a pull request's base (`baseRefName`): a pull request merged
  into anything but the task's recorded `base_branch` is flagged `wrong-base`, not `merged`, and its
  workspace stays. This also catches a phase stacked on another phase's branch.
- `jig task start` finds the epic of a task linked by its `Spec:` line and cuts the task's branch
  from it, recording the base in a new script-owned `state` field `base_branch`. Housekeeping,
  `task resume` and the touched-files helper read the base from `state`, falling back to
  `git.base_branch` when the field is absent — rejected: an explicit `--base` flag, which is easy
  to forget and sends a phase's pull request straight to `main`.
- A phase's task has landed when its pull request is merged into the epic: housekeeping flags it
  `needs-consolidation` and the human closes it. Its workspace is kept until the epic itself is
  merged into `main`, so each phase's design, review and verification survive to the final review —
  rejected: landing only when the epic reaches `main`, which would keep every phase's task open and
  reported for the whole feature; and purging a closed phase on the usual `trash_ttl`, weeks before
  anyone reviews the epic (failure mode 8).
- The epic is kept current by merging `main` into it directly, never by rebasing; `jig status`
  reports how far an epic is behind `main` — rejected: rebasing the epic, which rewrites history
  under the task branches cut from it and defeats the reflog check of a branch's own work
  (ADR-0032); and syncing only through a `main`→epic pull request with a branch rule on `epic/*`,
  which the maintainer found too heavy for the flow (2026-09-15). Accepted risk: a conflict in that
  merge is resolved without review (failure mode 3). CI runs the tests on every push to `epic/*`,
  so a bad resolution fails at once rather than at the final pull request.
- Before the final pull request, fresh `main` is merged into the epic and the version is raised
  there. A CI check on a pull request from `epic/*` into `main` fails when a release of that
  `JIG_VERSION` already exists, so the merge cannot silently tag nothing (failure mode 6).
- The spec and its `Epic:` line reach `main` first, and the epic is cut after them. From then on an
  epic spec is edited only on its epic — roadmap, task ids, checkmarks; filing a phase's tasks is an
  ordinary commit to the epic. On `main` nobody edits it, and `jig spec list` and `jig status` mark it
  with one line, `<id>  epic/<id> — progress is on the epic`, checking only that the branch exists.
  The current roadmap reaches `main` with the final pull request — decided 2026-09-15 after failure
  mode 7 — rejected: accumulating checkmarks on the epic while `main` shows the stale roadmap as if
  current, with conflicts at every sync; and reading the epic's roadmap from `main` through
  `git show`, which the maintainer found too complex. Accepted cost: `main` shows that a feature is in
  progress and where, not how far it got.

## Open questions

- Knowledge written by phases lives only on the epic until the final merge; sessions on `main` do
  not see it (failure mode 7).
- Parallel branches pick the same next ADR number; `knowledge check` catches it only at integration
  (failure mode 3).

## Assumptions left untested
