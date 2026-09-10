# Rules and Invariants

## Invariants

- Scripts never invoke an LLM. (ADR-0001)
- Scripts never delete a path they have not validated to be inside `.ai/` and shaped
  like a workspace or trash entry. (ADR-0006)
- Housekeeping never destroys a workspace whose remote state is `unknown`. (spec §23)
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
