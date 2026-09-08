# Rules and Invariants

## Invariants

- Scripts never invoke an LLM. (ADR-0001)
- Scripts never delete a path they have not validated to be inside `.ai/` and shaped
  like a workspace or trash entry. (ADR-0006)
- Housekeeping never destroys a workspace whose remote state is `unknown`. (spec §23)
- Nothing under `.ai/workspace/` or `.ai/runtime/` is ever committed.
- `init` and `upgrade` never overwrite existing knowledge or user-modified files. (ADR-0003)
- Remote merge state is never written into a task `state` file. (ADR-0005)

## Rules

- Shell code targets POSIX sh / bash 3.2; run `shellcheck` before committing. (ADR-0002)
- Knowledge documents under `features/`, `adr/`, `conventions/` carry frontmatter with
  `id`, `type`, `status`; `domains`/`paths` when applicable. (ADR-0004)
- ADR numbering is sequential, four digits, never reused.
- Skills reference `sdlc <command>` for mechanics instead of describing file operations.
