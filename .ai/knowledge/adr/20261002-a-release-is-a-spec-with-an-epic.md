---
id: adr-20261002-a-release-is-a-spec-with-an-epic
type: adr
status: accepted
date: 2026-10-02
domains:
  - spec
  - task
  - skills
paths:
  - "skills/jig-release/**"
  - scripts/lib/spec.sh
  - scripts/lib/task.sh
summary: Why a release is planned by the jig-release skill as a spec with an epic, how jig spec link joins a filed task to it, why a started task stays out, and why release notes are a reviewed task written against diffs.
---
# A release is planned by an agent as a spec with an epic, and a started task stays out of it

## Context

Releases 0.17.0 to 0.19.0 (#148, #149, #158, #165) were put together by a coordinating agent by
hand, in the same order each time: pick tasks and run them, each merged into `main` with no version
change; then a release task raised `JIG_VERSION` and wrote the changelog and upgrade pages from the
merged pull requests' diffs — not their titles: #148's review found a figure spliced from two
unrelated benchmarks — checked the known issues and roadmap pages against those diffs, chose minor
or patch with a reason, checked whether the installer changed and so whether the Windows checklist
applied, and opened the pull request for the owner to merge. After the merge someone watched CI on
`main`, because some Windows jobs run only there: #149 and #166 were follow-ups for a red `main`
that got no tag. The release of 0.16.1 added that upgrade claims hold or fail by which copy of Jig
runs the upgrade.

The owner asked for that to be the agent's job, on a release branch built like an epic. Specs with
epic branches (ADR-0040), shipping by `agent.git`
(adr-20260922-spec-work-ships-by-the-agent-git-level) and phase runs
(adr-20260922-a-phase-run-is-coordinated) already build a set of tasks on a branch and release it
once. Three things were missing: instructions for the agent, a way to link a task that was filed
before the spec existed, and a rule for a task that was already started.

## Decision

- **A release is a spec with an epic**, `release-<YYYY-MM-DD>` — named by the day it was planned so
  the id stays true when the level changes — with one phase whose items are the tasks going in, the
  release-notes task last, an `Epic:` line and a `Release:` line. No new object, state file or
  command family: `jig spec`, phase runs and `jig spec ship` carry it, and the existing `epic-pr` and
  `changelog` CI checks guard it.
- **The `jig-release` skill** decides what goes in and drives the rest. It lists live tasks with
  `jig task list --goals`, proposes the list in the order the project's knowledge gives — by
  default what breaks work, then what lies about state, then what slows work down, with "an agent
  could cheat" last — and a level with one sentence of reason by the project's own rule. The list
  and the level are a gate: a person approves the document before anything is created. In an
  unattended run nobody can answer, so the agent goes on and the declaration's pull request, which
  no agent merges, carries the document verbatim, marked as approved by the agent: its merge is
  where a person agrees.
- **`jig spec link <spec-id> <task-id>`** writes the `Spec:` line of a task filed earlier, with the
  phase read from the roadmap item that names the task. It refuses when no item names it or items in
  two phases do, a task linked to another spec, a closed task, and a borrowed task directory, as
  `spec remove` does.
- **A started task is not linked.** Its branch was cut from `main` when it started; moving it into
  the epic means rewriting that branch. It ships where it was cut from and reaches the release anyway
  when `main` is merged into the epic, which `spec epic --finish` already requires.
- **The release notes are a task, filed as T2**, so its claims are reviewed in a fresh context. It
  covers everything between the last release and the epic, from git, and checks each claim against
  the diff, numbers only as measured, stand-in versus real proof stated, known issues and roadmap
  entries the release closes, upgrade claims on every upgrade path, the project's own release
  checklists for parts that changed, and the planned level. Like any task of a phase run it never
  edits the spec (adr-20260922-a-phase-run-is-coordinated): a level the diffs disagree with is said
  in its pull request, and the `Release:` line is changed on the epic only with the person's yes —
  the level is theirs (adr-20260922-spec-work-ships-by-the-agent-git-level). Unattended, the higher
  of the two levels stands. The notes are written by the agent, not derived.
- **A fix that cannot wait** is an ordinary task from `main` and a patch release from `main`; the
  epic gets it when `main` is merged in. After a release merges, the agent watches CI on `main`
  until the release exists; red is a fix of that kind, not "done".
- Who merges a release does not change: a person, except an unattended run at `agent.git: merge`,
  and never a `major` release.

## Alternatives

- **A release object of its own** (`jig release`, its own state). Rejected: it would repeat the
  branch, the links, the phase run, the finish and the CI checks that specs with epics already have,
  and two ways of carrying work to `main` would drift apart.
- **Moving a started task into the epic** by rebasing its branch. Rejected: it rewrites a branch
  others may hold, a destructive step the run may not take.
- **Refusing started tasks a place in the release.** Rejected: they reach it through `main` whatever
  the rule says.
- **Deriving the changelog from the roadmap and pull request bodies.** Rejected: a body is a claim
  and the diff is what happened; 0.17.0's spliced figure came from exactly that kind of retelling.
  A machine "completeness" check over pull request titles would be the same check.
- **`--phase` on `spec link`.** Rejected: the roadmap already says which phase; a second source can
  disagree with it.
- **The selection order in an agent's memory** (where it was). Rejected: a rule only one agent
  remembers reaches no other; the skill ships it to every project, and a project's knowledge can
  override it.

## Consequences

- Each release costs one more pull request into `main` before work starts — the declaration — and a
  person merges it; without it `task start` in a checkout of `main` cannot find the spec.
- A phase run needs `agent.git` at `pr` or more; below that the release's tasks run one at a time on
  the same path.
- The release's final pull request carries every change at once, so CI's rules for which jobs run
  on a pull request see all of it before `main` moves.
- The mechanism is proven by tests of its commands; its acceptance is the next release, planned and
  made with it.
