# Rules and Invariants

## Invariants

- Scripts never invoke an LLM. (ADR-0001)
- Scripts never delete a path they have not validated to be inside `.ai/` and shaped
  like a workspace or trash entry. (ADR-0006) The one exception is a task worktree, and
  git deletes it, not the script. It is removed only by `git worktree remove` without
  `--force`, only when the task is closed and its branch landed on its own base, or its
  workspace is purged; and only when git lists it with the task's branch, it lies under
  `git.worktree_root`, it holds no workspace of its own, and it is not locked. (ADR-0029) When git removed
  it and its directory is still there — Windows leaves the links behind — housekeeping
  deletes only links (`find -type l`, never followed) and empty directories (`rmdir`) inside
  that path, and leaves anything else. (ADR-0037) The installer,
  `install.sh`, is the other: on a failed run it removes only the install directory it
  created with a plain `mkdir` in that same run and the `jig` link it created, never a path
  that existed before. (ADR-0033) Its Windows bootstrapper, `install.ps1`, removes only the
  Git installer it downloaded in that run; with `-Uninstall` it removes the `jig` link only
  when it points into the install directory, and that directory only when it is a jig source
  tree whose `git status` is clean. (ADR-0033, ADR-0037) `jig spec new` is the third: when a template copy fails it
  removes only the two temporary files it named in `.ai/specs/<id>/` and then `rmdir`s the
  directory it created with a plain `mkdir` in that run; `rmdir` refuses anything that is
  not empty. (ADR-0035) `jig upgrade` is the fourth: in copy mode it deletes a file only when the
  manifest records it with the hash jig installed, the file is unchanged, the new version no
  longer ships it, and the path — relative, without `..` — lies under `.ai/` or an adapter's
  skills directory (`.claude/skills/`, `.codex/skills/`); anything else is kept and reported
  `keep-outside`. (ADR-0024) The carry into a task worktree adds a third shape rather than a
  fifth exception: `jig task start --worktree` and `jig task bootstrap` delete only inside a
  worktree's `.ai/runtime/bootstrap`, the staging directory where they build a declared path
  before renaming it into place, and only a path that resolves physically inside that directory
  and is not the directory itself. A carried path at its destination is never deleted, because
  a rename is what puts it there and it therefore only ever appears complete. The staging
  directory sits under `.ai/runtime/` so that git ignores it: anything a carry leaves in a
  worktree that git does not ignore reads as untracked, and `git worktree remove` without
  `--force` — the only removal jig performs — then refuses that worktree for good.
  (adr-20260924-a-worktree-carries-what-git-does-not) Moving to trash is not deleting, and it has two users: housekeeping moves
  a workspace, and `jig spec` moves `.ai/specs/<id>/` — `remove`, `close` and `epic --finish`, and a
  partial restore of `epic --reopen` — only after checking that the id is valid and the directory
  resolves inside `.ai/specs/`. (ADR-0006, ADR-0035)
- Housekeeping never destroys a workspace whose remote state is `unknown`, with one exception
  decided in ADR-0005: a task a human ended with `jig task abandon` (directly, or through
  `jig spec remove --abandon-unstarted`) is moved to trash once it is older than
  `housekeeping.abandoned_ttl`, whatever its remote state — the abandonment answered the question
  `unknown` leaves open. It goes through trash like any purge (ADR-0006), a worktree only by
  `git worktree remove` without `--force`, and its branch and commits are never touched.
  (`domains/housekeeping`)
- Nothing under `.ai/workspace/` or `.ai/runtime/` is ever committed.
- `init` and `upgrade` never overwrite existing knowledge or user-modified files. (ADR-0003)
- Remote merge state is never written into a task `state` file. (ADR-0005)
- A capability is passed to a profile only when its `profile.yaml` declares it, and is
  explicitly unset for every profile that does not — never left to the ambient
  environment. A profile predating the capability must not be able to observe it.
  (ADR-0013)
- A narrowed check reports what it narrowed to, and an unhonoured scope is reported
  rather than silently dropped; a supporting profile given an empty file list reports
  `skip`, never `pass`. (ADR-0013; a skip is not a pass)
- No filesystem path is built from a name that has not been validated first: task ids,
  spec ids, profile names, adapter names and knowledge domain names are checked at the
  single function that builds the path (`task_dir`, `spec_new` and the `spec_ids` walk,
  `spec_task_dir` and `spec_remove`, `profiles_dir`, `adapters_dir`, `km_domain_dir`), before
  any read, write or `sed` expression that embeds them. A path supplied by a caller rather
  than derived from a name is validated the same way at the point it is joined to the
  project root — `_ctx_check_knowledge_path` for an
  acknowledged document, the `--scope` check in `km_inventory` for a directory, and
  `km_source_problem` plus `km_source_tracked` for a linked source, which also refuses a
  tracked symlink because it may point outside the repository (ADR-0036), and
  `jig_knowledge_read_path` each time a stub is resolved to its source — no symlink, no
  directory outside the repository, since a source can be swapped after it was accepted — and
  `km_copy_check` for the file `jig knowledge new --copy` copies, which is only ever read. Each
  validates for the shape it needs; none may skip the check because another command
  already ran one. (ADR-0008, convention-shell)

## Scope invariants

What the framework deliberately does **not** do. Moved here when the product
specification was retired: the list outlived the document because non-goals are what proposals
of the form "while we're at it, let's also…" break against.

- Does not implement: its own LLM; its own coding agent; agent orchestration from scripts;
  an IDE; an issue tracker; mandatory multi-agent orchestration; permanent storage of the
  entire SDLC history; a mandatory external artifact repository; mandatory CI
  consolidation; LLM-based housekeeping; cleanup that requires manual discipline; support
  for more than two runtimes in the MVP.
- Does not implement its own scheduler. It ships examples in `.ai/templates/scheduler/`;
  adopting one is the user's action.
- **Routine maintenance never depends on a developer remembering to run it.** Repeatable
  mechanical operations are automated (formerly §3.8). Housekeeping exists for this
  reason, and so does the requirement that a flag nobody will see counts as work not done.

## Rules

- Shell code targets POSIX sh / bash 3.2; run `shellcheck` before committing. (ADR-0002)
- Knowledge documents under `features/`, `adr/`, `conventions/` carry frontmatter with
  `id`, `type`, `status`; `domains`/`paths` when applicable. (ADR-0004)
- An ADR is named `YYYYMMDD-<slug>` by the day it was written, and cited by its id; legacy
  `NNNN-` names stay valid and their numbers are never reused. (adr-20260918-adr-names-are-dated)
- Knowledge frontmatter is written through `jig knowledge new|paths|reviewed`, never by
  hand: `paths` items are globs and hand-editing them is how they rot. (ADR-0001)
- Consolidation stamps `reviewed_at` on every knowledge document it edits, so
  `jig knowledge stale` keeps telling the truth. (ADR-0010)
- Skills reference `jig <command>` for mechanics instead of describing file operations.
- Whatever a skill asks a human to agree to is shown to them verbatim, with the agent's
  commentary after it; a summary is never what gets approved. (ADR-0031)
