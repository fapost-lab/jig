# Rules and Invariants

## Invariants

- Scripts never invoke an LLM. (ADR-0001)
- Scripts never delete a path they have not validated to be inside `.ai/` and shaped
  like a workspace or trash entry. (ADR-0006) The one exception is a task worktree, and
  git deletes it, not the script. It is removed only by `git worktree remove` without
  `--force`, only when git lists it with the task's branch, it lies under
  `git.worktree_root`, and it holds no workspace of its own. (ADR-0029)
- Housekeeping never destroys a workspace whose remote state is `unknown`.
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
  profile names, adapter names and knowledge domain names are checked at the single
  function that builds the path (`task_dir`, `profiles_dir`, `adapters_dir`,
  `km_domain_dir`), before any read, write or `sed` expression that embeds them. A path
  supplied by a caller rather than derived from a name is validated the same way at the
  point it is joined to the project root — `_ctx_check_knowledge_path` for an
  acknowledged document, the `--scope` check in `km_inventory` for a directory. Each
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
- ADR numbering is sequential, four digits, never reused.
- Knowledge frontmatter is written through `jig knowledge new|paths|reviewed`, never by
  hand: `paths` items are globs and hand-editing them is how they rot. (ADR-0001)
- Consolidation stamps `reviewed_at` on every knowledge document it edits, so
  `jig knowledge stale` keeps telling the truth. (ADR-0010)
- Skills reference `jig <command>` for mechanics instead of describing file operations.
