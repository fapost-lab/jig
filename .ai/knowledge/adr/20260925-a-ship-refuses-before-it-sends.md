---
id: adr-20260925-a-ship-refuses-before-it-sends
type: adr
status: accepted
date: 2026-09-25
domains:
  - task
  - spec
paths:
  - scripts/lib/common.sh
  - scripts/lib/task.sh
  - scripts/lib/spec.sh
summary: Why jig task ship and jig spec ship refuse when there is nothing to commit, and why push, the pull request and the merge each refuse until the ship has said what it sends.
reviewed_at: 2026-09-25
---
# A ship refuses before it sends

## Context

`jig task ship` and `jig spec ship` share their git steps (`jig_ship_*`,
`scripts/lib/common.sh`): commit what is staged, push the branch, open the
pull request, and at `agent.git: merge` merge it once CI is green.

The commit step treated an empty index as information rather than as a
question. It printed `nothing staged; no commit` and returned 0, and the ship
carried on. Two failures came out of that, seen on live runs on 2026-09-24 and
2026-09-25:

- **The outcome.** Nothing to commit was never a reason to stop. When the
  branch already carried commits of its own, the ship pushed, opened a pull
  request and — at `agent.git: merge` — merged it, while the change sat
  unstaged in the working tree. Nothing downstream notices: a pull request
  that does not contain the change has nothing to make CI red, so it goes
  green and merges itself. The run reports success and the work is left
  behind.
- **The order.** When the branch had no commit of its own either, the ship
  still pushed the empty branch and asked GitHub for a pull request; the run
  stopped there, on `No commits between main and task/<id>` — a message from
  the forge, about pull requests, after the forge had already been asked. An
  empty pull request is not taken back by noticing it: it stays in the forge,
  people and bots see it, somebody closes it by hand, and on a public
  repository it has already happened.

The costs differ in kind. An unhelpful message costs one reader a minute. A
step that left this machine too early costs everyone who sees the result, and
a silent success costs whoever later looks for a change that was never
shipped.

## Decision

Two rules, in this order.

**Nothing to commit is an outcome, not a line in the log.** `jig_ship_commit`
refuses when the index is empty *and* tracked files hold unstaged changes:
shipping then would carry whatever the branch already holds and leave the
change behind. An empty index with a clean working tree still proceeds — the
change was committed by an earlier run, and that is the path a second ship
takes after a push that failed or a forge that was down. Untracked files are
warned about, never refused: a scratch file, the commit message itself or a
build artefact is nobody's shipped change, and a refusal on those is one every
caller would learn to work around. This is the test `jig task start` already
applies at the other end of a task — tracked changes stop it, untracked ones
do not (`_task_refuse_dirty_tree`, `scripts/lib/task.sh`) — so a task now
begins and ends by reading the working tree the same way.

**Nothing leaves this machine before the ship has said what it sends.** Push,
the pull request and the merge each open with `_jig_ship_outward`, which
refuses until one of two calls has answered:

- `jig_ship_require_commits <who> <head> <base>` — `<head>` carries at least
  one commit the base does not, judged through `jig_base_ref` so the
  comparison is the one the forge will make. Otherwise the ship refuses with
  nothing sent. This is what `task ship`, a spec's declaration and a spec's
  final pull request all use.
- `jig_ship_sends_no_commit <why>` — this ship carries no commit and means to.
  One caller does: `spec ship` in `epic` mode pushes an epic branch so that it
  exists on the forge for its tasks to target, and an epic just cut from the
  default branch has no commit of its own.

The guard is on the steps, not on the paths through them: a new outward step
inherits the rule by opening with `_jig_ship_outward`, and a new call site
inherits it by having to say which of the two applies.

## Alternatives

**Fix the message.** The first framing of the defect was that the useful line
(`nothing staged; no commit`) scrolled past while the error the reader was
left looking at came from `gh`. True, and not the fault: a perfectly worded
line still lets the push and the pull request happen.

**Check just before the push.** Push is the first outward step, so one check
there would cover today's callers. It would not survive the next one: the rule
would live at a call site instead of at the steps, and the second path to
reach `jig_ship_pr` would reopen the hole silently.

**Refuse on any empty index, unconditionally.** Simpler to state, and it
breaks the retry: a ship that committed and then failed to push could never be
run again without an empty commit to appease it. The working tree is what
separates the two cases, and it is already there to be read.

**Refuse on untracked files too.** It would catch a new file the agent never
added. It would also refuse on the commit message file, on build output and on
anything a person left lying about, in a command that runs at the end of every
task — the kind of refusal callers route around, which costs more than it
catches. A warning says it without blocking.

## Consequences

- `jig task ship` and `jig spec ship` can refuse where they used to carry on.
  Both refusals name what to do: stage the change, or commit it.
- The empty pull request cannot be produced by a ship any more, so
  `docs/known-issues.mdx` loses the entry this decision closes.
- Every future outward step of a ship must open with `_jig_ship_outward`, and
  every future call site must say which of the two answers applies. Nothing
  enforces that but review and the test that holds each of the three steps to
  it (`tests/task.t.sh`).
- The order is testable without a network: `origin` in the tests is a real
  bare repository, so a push that happened shows in its refs, and the `gh`
  stub records every call, so a forge that was asked anything shows in
  `gh-calls.log`.
