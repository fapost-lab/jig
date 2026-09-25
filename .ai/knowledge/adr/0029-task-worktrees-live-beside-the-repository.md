---
id: adr-0029-task-worktrees-live-beside-the-repository
type: adr
status: accepted
date: 2026-09-11
domains:
  - task
  - housekeeping
paths:
  - scripts/lib/task.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/status.sh
summary: Why parallel agent sessions get a worktree per task beside the repository, borrow the workspace by link, and are cleaned up by git.
reviewed_at: 2026-09-24
---
# ADR-0029: A task can start in a worktree of its own, beside the repository, removed by git

## Context

Several agent sessions working in one checkout overwrite each other. On 2026-09-11 three
tasks in a row recorded a branch that belonged to another session, because a parallel
session moved HEAD between two commands, and one session's uncommitted scripts sat in the
tree while another ran `jig verify` against them. The dirty-tree refusal on `task start`
prevented the worst of it, and was overridden with `--force` every time.

Agents here do not commit, and review happens before the commit: the human reads the diff
and commits it. Agent-made commits reviewed as pull requests were considered and rejected.
A pull request coordinates people who are not in the same conversation, and here they are.
So a task worktree holds uncommitted work as its normal state, not as debris.

Worktrees need no install step here. Every framework symlink is relative and committed,
so each one resolves inside the worktree it is checked out in, and `.ai/workspace/` and
`.ai/runtime/` are gitignored, so a worktree starts empty — ADR-0008's model exactly.

## Decision

- **`jig task start <id> --worktree`** cuts the task's branch from the freshest base, as
  plain `task start` does, but checks it out in a new worktree instead of this checkout. It
  records `branch` and `base_commit`, prints the worktree's path, and stops. An agent
  session cannot leave its working directory mid-session, so opening a session there is
  the human's step (the stance of ADR-0024). It needs `git.branch_per_task: true`, because
  git will not check one branch out in two worktrees. A start that fails takes back what
  it made. `git worktree add -b` creates the branch before the directory, and a leftover
  branch would refuse every retry. The branch is deleted with `update-ref -d <ref> <commit>`,
  which only succeeds while it still points at the commit it was cut at.
- **`task pause --stash` refuses when the task's branch is checked out elsewhere.** It
  stashes the checkout it runs in, and for a task in its own worktree that is not the
  task's work.
- **The dirty-tree refusal names the worktree as the other road** — pause the owner with
  `--stash`, or start this task in its own worktree. The worktree is created on request,
  not automatically: the human is needed at that moment anyway, to open the session.
- **The workspace does not move.** The worktree gets one link, `.ai/workspace/tasks/<id>`,
  to the workspace in the checkout where the task was filed. That checkout keeps seeing
  every task, and the workspace's lifecycle stays in one place. `task artifacts` accepts
  exactly this link — to the same task's workspace in another worktree of this repository —
  and still refuses any other.
- **Where a task's branch is checked out is read from git** (`git worktree list`), never
  from another checkout's `.ai/`. `task list` and `jig status` show a task started in a
  worktree with `worktree=<path> uncommitted=<n>`: the queue waiting for review.
- **Worktrees live beside the repository**: `git.worktree_root`, by default
  `../<project>.worktrees`, relative to the project root unless absolute.
- **Housekeeping in the owning checkout removes a task's worktree when it purges the
  task's workspace**, and only then, so no new policy row exists. The worktree must be
  listed by git with the task's branch, lie under `git.worktree_root`, hold nothing under
  `.ai/workspace/tasks/` but links, and have no uncommitted changes. It is removed by
  `git worktree remove` without `--force`. When it has to stay, the workspace stays too,
  flagged `worktree-kept`, and `jig status` counts it. The branch is never deleted.

## Alternatives

- **One shared checkout, coordinated by pausing.** Rejected: the failure is not a missing
  signal but HEAD moving under a running session, which no amount of state prevents.
- **Agents commit to their own branch; the human reviews a pull request.** Rejected by the
  human for this project: review before the commit is strictly shorter when author and
  reviewer share a conversation.
- **Create the worktree automatically on a dirty tree.** Rejected: it saves no step, since
  the human has to open the session, and a dirty tree the agent caused itself would leave
  a stray worktree behind.
- **Worktrees inside the repository (`.ai/worktrees/`).** Cheaper for an agent's sandbox,
  and covered by the existing deletion invariant. Rejected because the cost lands on every
  adopting project: a nested copy of the whole tree is found twice by test runners, type
  checkers and IDE indexers, and jig can prune its own profiles but not their
  configuration. A worktree inside this repository has also reached the index once
  (`858b156`, removed in `f3ea409`).
- **Move the workspace into the worktree.** Rejected: the filing checkout loses the task
  from view, and an overview then needs the cross-worktree lookup ADR-0008 rules out.
  Copying it gives two `state` files that diverge from the first write.
- **Only report a finished worktree and print the command to remove it.** Rejected: that
  is cleanup by manual discipline (RULES.md, Scope invariants).
- **Remove with `--force`.** Rejected: it discards uncommitted work, which in a task
  worktree is the work waiting for review.

## Consequences

- A deletion outside `.ai/` now exists, and RULES.md names it: a task worktree, removed
  only by git, only under the three checks above. Measured before deciding: `git worktree
  remove` without `--force` removes the worktree and the link and leaves the owner's
  workspace intact. It refuses on tracked changes and untracked files, but it deletes
  *ignored* files silently. That is why a worktree holding a real workspace is kept.
- Creating a worktree writes outside the project directory, so an agent's sandbox may ask
  for permission once per worktree. Paths in reports are absolute.
- ADR-0008 gains a named exception: a worktree borrows exactly one workspace, by a link it
  was given at creation. Ownership — housekeeping, trash — stays with the filing checkout.
  Housekeeping run inside the worktree does not see the link at all, because it finds
  workspaces with `find`, which does not follow links.
- The link is absolute, like git's own worktree paths. Moving the repository breaks both
  alike, and `git worktree repair` fixes git's side of it.
- `git.worktree_root` is read on every run, not recorded per task. Changing it strands every
  worktree made under the old root: housekeeping keeps them, flagged `worktree-kept` with
  reason `outside-worktree-root` in the log, until they are moved or removed by hand.

> **Amendment (2026-09-11).** "An agent session cannot leave its working directory
> mid-session" holds for some runtimes, not all: Claude Code can switch a running session
> into an existing worktree. The decision stands, because it rests on the narrower fact
> that the script cannot move the session that called it. What changes is the guidance
> built on the premise: `jig-task` tells an agent that can switch to do so, and to ask the
> user for a new session only when it cannot. The rejection of an automatic worktree still
> holds on its second ground, the stray worktree a self-inflicted dirty tree would leave.
> A switched session may be fenced to the worktree: Claude Code's editing tools refuse the
> workspace link, because it resolves into the filing checkout, so task artifacts are
> written there with plain shell commands.

> **Amendment (2026-09-13).** A worktree outside `git.worktree_root` is still never touched,
> but it no longer holds the workspace back unconditionally. Claude Code creates a worktree
> per session under `.claude/worktrees/`; a task started inside one checked its branch out
> there, and housekeeping kept the task under "needs you" on every run until a person removed
> a tree jig does not own. That is cleanup by manual discipline, which this decision rejected.
> Now such a worktree, when clean and not locked, is left in place and the workspace is purged
> (log `action=leave reason=outside-worktree-root`). Uncommitted changes keep it, as before,
> and so does a lock (`git worktree lock`, which Claude Code holds while an agent runs).
> The consequence above about a changed `git.worktree_root` changes with it: a clean worktree
> stranded under the old root no longer keeps its workspace.
>
> Removing runtime worktrees was considered and rejected: the runtime removes clean ones
> itself when a session ends, removal would pull the working directory from under a live
> session, and it would add a second deletion outside `.ai/`. Declaring the runtime's worktree
> directory in an adapter was rejected too: once foreign worktrees are left alone and the
> `shell` profile takes its file list from git, nothing consumes it, and the location is the
> runtime's to change (Claude Code's `WorktreeCreate` hook moves it).
>
> The checkout housekeeping runs in now gets the same guard as a task worktree: a task whose
> branch is checked out there, with uncommitted changes, keeps its workspace (ADR-0032).

> **Amendment (2026-09-16).** The workspace link is made by `jig_link_dir`: a symlink where one can be
> made, an NTFS junction where it cannot — Git Bash on Windows copies on `ln -s` — and `task start
> --worktree` refuses before `git worktree add` when neither can (ADR-0037). A junction passes every check
> above (`-L`, `find -type l`, `cd -P`), and removing it never touches the workspace. On Windows `git
> worktree remove` can succeed and leave the worktree's directory behind with those links in it;
> housekeeping then removes only links and empty directories there, with `rmdir`, and anything else keeps
> the task under `worktree-kept` with reason `leftover`. The claim above that "every framework symlink
> is relative and committed" holds for link mode only, which still needs real symlinks.

> **Amendment (2026-09-21).** "Agents here do not commit" is no longer a rule of the framework:
> it is the default level, `none`, of the per-clone setting `agent.git`
> (adr-20260921-agent-git-rights-are-a-local-setting). The alternative this decision rejected —
> agents commit to their own branch and the human reviews a pull request — was reopened by the
> maintainer on 2026-09-18 as an opt-in for one clone, never a project default. At `none`
> everything above holds unchanged. At a higher level uncommitted work in a worktree is still
> kept, and still not debris; it is just no longer the whole review queue.

> **Amendment (2026-09-22).** "Removes a task's worktree when it purges the task's workspace, and only
> then" is replaced: a task's worktree goes when the task is closed and its branch has landed on the
> task's own base — an epic included, judged as housekeeping already judges it (ADR-0039), with no new
> network call — or when its workspace is purged, whichever comes first. Three worktrees of closed
> phases merged into `epic/autopilot` sat on disk because a phase's workspace waits for its epic
> (ADR-0040) and the worktree waited with it; they were removed by hand, which is the cleanup by manual
> discipline this decision rejected, and a phase run creates worktrees by the wave. The records a phase
> keeps for the epic's review live in the workspace, in the filing checkout; the worktree only links to
> them, and nothing reads it once the task is closed.
>
> The safety conditions are unchanged: git lists the worktree with the task's branch, it lies under
> `git.worktree_root`, nothing under its `.ai/workspace/tasks/` is anything but a link, it has no
> uncommitted changes, `git worktree remove` runs without `--force`, and the branch is never deleted.
> One is sharpened: a lock now keeps a worktree of jig's own as well, checked before git is asked, with
> reason `locked` instead of `git-refused`. Git refused a locked worktree anyway; the reason now says
> what it most likely is in a phase run — a live agent — and a dry run no longer promises a removal git
> would refuse. A worktree that has to stay while its workspace is kept anyway (`base-unreleased`) is
> flagged `base-unreleased,worktree-kept` and counted like any other. A task that is merged but not yet
> closed keeps its worktree: closing is the human's confirmation (ADR-0030), and a `merged` that turns
> out wrong (ADR-0032) must not take the tree from beside the work.
>
> Removing the worktree in `jig task set <id> status consolidated`, or in `jig task ship`, was
> considered and rejected: the task is often closed from inside its worktree, "landed" is housekeeping's
> judgement, and ship runs before the merge. A live session in a clean, unlocked worktree can still lose
> its working directory to a housekeeping run once its task is closed; closing is an agent's last step,
> and a phase run's coordinator runs housekeeping only after a wave finishes. No automatic lock is taken
> at `task start --worktree`.

> **Amendment (2026-09-24).** "Task artifacts are written there with plain shell commands" — the
> 2026-09-11 amendment's last clause — is replaced by a verb: `jig task artifact write|append <id>
> <kind> [--from <file>|-]`. The observation behind it stands, and so does the link; what was wrong
> was leaving the consequence as advice. It was advice nobody gave: the fact lived in this amendment,
> which an agent writing `plan.md` is not reading, and no skill mentioned it, so each session
> rediscovered the refusal by hitting it and then guessed its way around.
>
> Prose could not have fixed it either. "Here, write task documents with shell redirection" is an
> instruction against the runtime's own default, and that is the class of rule agents break.
> So the mechanic moves into the script (ADR-0001), and the skills call it.
>
> The verb earns its place on four counts a redirection does not cover: it resolves the workspace
> through `_task_workspace_root` — the shared check that accepts this one borrowed link and refuses
> every other, now used for reading and writing alike; it writes atomically, tmp then `mv`; it takes a
> closed vocabulary of nine kinds, so a misspelt name cannot become a file `task artifacts` never looks
> at; and it refreshes `updated_at` and redraws the status page. The last one was the silent failure:
> a `plan.md` written around jig left the task looking untouched from outside, which in a worktree is
> the only view anyone else has.
>
> Two smaller refusals come with it, both protecting a document that already exists: empty input is
> never written, because a `write` fed the output of a command that failed would otherwise blank the
> document; and an artifact that is a link is refused rather than followed or replaced, consistent with
> `task artifacts`, which already reports an artifact pointing out of the workspace as unavailable.
>
> Nothing about the workspace's location changes. The alternatives this decision rejected — moving the
> workspace into the worktree, or copying it — stay rejected, for the reasons given above.

> **Amendment (2026-09-24, carrying).** "Worktrees need no install step here" is true of this
> repository and false of almost every project jig serves. It was generalised from the one case in
> front of it: jig is shell with no dependencies, so its own worktrees start complete. A project
> with an install step keeps `vendor/`, `node_modules/` and `.env` outside git, and a fresh
> worktree is therefore a tree its own checks cannot run in — which made the supported road worse
> than the manual one, and an agent that goes around jig by hand is not fixed by an instruction.
>
> `jig task start <id> --worktree` now carries that state in from the checkout beside it, and
> `jig task bootstrap <id>` carries it again when the first attempt failed
> (adr-20260924-a-worktree-carries-what-git-does-not). The rest of this decision is untouched:
> the workspace is still borrowed by exactly one link and never copied — the carry refuses any
> path inside `.ai/` by name — the worktree still lives under `git.worktree_root`, and git still
> removes it, without `--force`, under the same conditions.
>
> One of those conditions turned out to constrain *how* state may be carried, and the carry is
> built around it. Housekeeping can only remove a worktree git reports as clean, so the carry
> places a path, asks git what it now reports, and takes straight back out anything it made
> appear, naming `.gitignore` as the remedy. A declared path the project neither tracks nor
> ignores is refused rather than carried.
>
> A second consequence belongs here rather than there, because it is *this* decision that owns
> the removal: `git worktree remove` without `--force` deletes ignored files **silently**, as
> measured above. So a carried path that holds a separate git repository is a trap. The worktree
> gets a second clone; work done in it is invisible to the parent because the path is ignored;
> and removing the worktree takes that work with it — committed and uncommitted alike, the commit
> having existed in no other clone — without a single message. Measured end to end on 2026-09-25.
> Carrying such a directory is therefore not supported.
>
> Sharing one by link is a separate decision, held by the `worktree-share` task. Note for whoever
> takes it: linking a directory whole reads as untracked, because git does not match a
> trailing-slash ignore pattern such as `packages/` against a symlink, and that alone would make
> the worktree un-removable for the rest of its life. A mirror — a real directory whose entries
> are links — was built for this and then removed again; it is **a mechanism no longer here**, and
> its measurements and findings live with that task.
