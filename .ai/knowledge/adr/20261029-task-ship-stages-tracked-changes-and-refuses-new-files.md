---
id: adr-20261029-task-ship-stages-tracked-changes-and-refuses-new-files
type: adr
status: accepted
date: 2026-10-29
domains:
  - task
paths:
  - scripts/lib/common.sh
  - scripts/lib/task.sh
summary: Why jig task ship stages tracked changes itself when nothing is staged, refuses new untracked files, and names what a staged index leaves out.
---
# Task ship stages tracked changes itself and refuses new files

## Context

`jig task ship` is how an agent reaches a commit and a pull request (`AGENTS.md`: instead of
`git commit` and `gh pr create`), so agents and people read it as "commit the task's change".
Until now it committed only what was already staged
([adr-20260925-a-ship-refuses-before-it-sends](20260925-a-ship-refuses-before-it-sends.md)):
an empty index with changed tracked files was a refusal, and untracked files were a warning.

On 2026-10-29 that refusal fired twice in a day — in jig-ui (task `upgrade-buttons`) and here
(task `upgrade-land`). Each time the agent had not run `git add`, ship sent nothing, and the agent
staged by hand and ran it again. Nothing was lost, but the refusal answered a question nobody had
meant to ask: an empty index at ship time is an agent that forgot to stage, not a decision to ship
nothing.

Two holes were left open as well. A ship whose branch already carried a commit, with only new
files in the tree, warned and then pushed the earlier commit while the new files stayed behind.
And a partly staged index was committed as it was, with whatever it left out never named.

Staging on the agent's behalf has its own price, and it is not the same for every file. New content
in a file the repository already tracks adds no new path to history. A new file can be anything: a
secret nobody added to `.gitignore`, a scratch file, a build artefact. Once pushed to the forge it is
not taken back.

## Decision

Three rules for `jig task ship`, applied before the commit:

- **Nothing staged: the tracked changes are staged for you.** `jig_ship_stage_tracked`
  (`scripts/lib/common.sh`) runs `git add -u` over the project, `.ai/workspace/` and `.ai/runtime/`
  excluded. It prints every path it staged, so the reader sees what the commit holds, as with
  `git commit -a`.
- **Nothing staged and a new file in the tree: a refusal.** Any file git neither tracks nor ignores
  refuses the ship before anything is staged, and the refusal names each file. The files passed as
  `--message-file` and `--body-file` do not count, wherever they were written: they are the ship's
  inputs, not part of the change. The agent stages the new files that belong to the change, and
  ignores or removes the rest.
- **Something staged: that index is the commit.** A partly staged index (`git add -p`, one file
  out of several) is the caller's choice and is committed as it is. After the commit, a warning names
  every tracked change and new file the commit left out.

So a ship either commits the task's change or refuses with a reason and a non-zero exit. It never
succeeds while leaving the change in the working tree without saying so.

`jig spec ship` and the upgrade's commit keep the contract of the earlier ADR: their callers stage
a known set of paths, and staging everything tracked there would pick up unrelated work. They share
the warning about what a non-empty index leaves out.

## Alternatives

**Stage everything, new files included (`git add -A`, honouring `.gitignore`).** One step fewer
when the change adds files. Rejected because the cost falls on the one irreversible step: an
unignored `.env`, a credentials file or a stray dump goes to the forge, and on a public repository it
is out before anyone reads the pull request.

**Keep refusing an empty index.** This is the behaviour that cost two extra rounds in one day. It is
safe, but it gives a ship that is meant to replace `git commit` a step that `git commit -a` does not
need.

**Refuse a partly staged index.** It would catch a file the agent forgot to stage. It would also
take away deliberate partial staging and refuse whenever another session's edit sits in the same
checkout. Naming what was left out makes it visible without blocking.

## Consequences

- An agent no longer needs `git add` for a change made only to tracked files. It still needs it for
  new files, and the refusal tells it which ones.
- A new file that is neither tracked nor ignored now stops `task ship` when nothing is staged, where
  before it was a warning. A project that leaves build output or scratch files unignored will meet
  this refusal and should ignore them.
- Every tracked change in the checkout goes into the commit when nothing is staged, including an
  edit another session left there. The printed list is how a reader notices that.
- This decision narrows
  [adr-20260925-a-ship-refuses-before-it-sends](20260925-a-ship-refuses-before-it-sends.md) for
  `task ship` only. Its order rule, that nothing leaves the machine before the ship has said what it
  sends, is unchanged.
