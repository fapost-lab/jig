---
id: adr-0036-existing-documents-are-linked-in-place
type: adr
status: accepted
date: 2026-09-15
domains:
  - knowledge
  - context
  - skills
paths:
  - scripts/lib/knowledge.sh
  - templates/knowledge/source.md
  - "skills/jig-map/**"
summary: Why a project's existing rule documents are adopted through proposed stubs that link them in place, and why no stub reaches an agent yet.
reviewed_at: 2026-09-16
---
# ADR-0036: A project's existing rule documents are linked in place by proposed stubs

## Context

A team that adopts Jig usually keeps its rules already: `docs/`, its own ADRs, `CONTRIBUTING.md`,
instruction files of other tools. `jig-map` proposed new documents under `.ai/knowledge/` and knew
nothing about those, so every rule risked two copies that drift apart, or never reached an agent
through `jig context`. The plan for adopting them is the specification
`.ai/specs/knowledge-adoption/`; this decision is its first phase.

Checking the plan against the code changed two of its premises. An accepted stub would be resolved
like any document, so an agent would receive its two-line body — a pointer — and acknowledge it by
the stub's hash, never opening the rules. And a team's ADR cannot live under `.ai/knowledge/adr/`:
that directory requires Jig's `NNNN-` numbering, which either renumbers the team's decision or
collides with the project's own. On a case-insensitive filesystem `[ -f docs/x.md ]` is true for
`Docs/x.md`, so a path valid on one machine would be missing on another, and `git ls-files` without
`-z` quotes every non-ASCII name.

## Decision

- **A stub links an existing tracked document with `source: <path>`** and holds only metadata. It
  lives in `.ai/knowledge/sources/<slug>.md`, a navigation directory like `domains/` (ADR-0004,
  ADR-0014). Its `type` is what the source is — `adr`, `convention` or `feature`, never a domain
  pack (ADR-0019) — its id is `<type>-<slug>` without Jig's ADR number, and an `adr` stub needs no
  `date`: the date lives in the source.
- **`jig knowledge new <type> <slug> --source <path> --proposed`** writes it from the framework-owned
  template `templates/knowledge/source.md`. The path is refused, before anything is written, when it
  is absolute, has dot segments, points inside `.ai/`, contains `#`, `"`, a backslash, brackets,
  parentheses, a tab or a newline, names `CLAUDE.local.md` in any case, is already linked, or is not
  a regular non-symlink file that git tracks with exactly this case. Tracking is decided by comparing
  the path as a string with one `git ls-files -z` listing — never a pathspec, never `[ -f ]` alone.
  `jig knowledge check` applies the same rules to every stub and fails two stubs on one source.
- **Until `jig context` can hand an agent the source, a stub reaches no agent.** `--source` requires
  `--proposed`; `jig knowledge accept` refuses a batch containing a stub; `knowledge check` fails a
  stub that is `active` or `accepted`; both forms of `jig context` skip any document with `source:`,
  so a hand-edited stub is not resolved either. Whether a document is a stub is answered once, by
  `jig_knowledge_source` in `common.sh`, because `knowledge` and `context` must agree on it. All four
  are lifted together when resolution of sources lands.
- **`jig knowledge inventory` lists the candidates**: `instructions:` lines for the instruction files
  of every tool it knows, with their git state and the stub linking them, and `doc:` lines for
  Markdown-like files with git state, size and `linked by <id>`. Listings are read with `-z`.
  Ignored directories are named on a `skipped:` line and not walked. `CLAUDE.local.md` never appears.
  Which candidates hold rules is the agent's judgement (ADR-0001).
- **`jig-map` adopts before it maps**: it links rule-like documents, skips guides for people, reads
  every instruction file for duplicates and contradictions and settles none of them silently, and
  lists untracked candidates to copy later.

## Alternatives

- **Accept stubs now and put a markdown link to the source in the body.** Rejected: nothing makes an
  agent follow a link in a body, and the acknowledgement would hash the stub.
- **Resolve sources in this change.** Rejected for size: resolution, acknowledgements and change
  tracking of sources are a phase of their own in the specification.
- **A `source` document type.** Rejected: it loses "this is an ADR", which decides how a stub is
  loaded later.
- **Stubs under `adr/` with Jig's numbers.** Rejected: a team's ADR-3 would be cited as another number,
  or collide with the project's ADR-0003.
- **Frontmatter written into the team's own files.** Rejected: Jig would edit documents it does not
  own, against tools (Docusaurus, MkDocs, Cursor) whose frontmatter its flat parser cannot read.
- **A separate `jig knowledge candidates` command.** Rejected: a second source of facts about the
  repository's shape beside `inventory`, which `jig-map` already reads.
- **Walking ignored directories.** Rejected: `node_modules/` alone is thousands of lines; the report
  names what it did not inspect instead.
- **A script that finds duplicates and contradictions.** Rejected: it is a judgement about meaning.

## Consequences

- Adoption can run today and leave a reviewable set of proposals, but none of them helps an agent
  until sources resolve. Proposals can be rejected meanwhile; they cannot be accepted.
- Four pieces of code exist only to hold stubs back — the `accept` refusal, the `knowledge check`
  failure for an active stub, and the `jig context` skip in both forms — and must be removed, not
  forgotten, when sources resolve.
- A stub's `paths` already count as coverage in `jig knowledge paths`, although nothing resolves it —
  as for every proposed document.
- A file name with a tab or a newline can never be a source, and a symlink never can: the target
  may lie outside the repository.
- Sizes in the inventory are matched to files by order, because `wc` in the C locale prints every
  non-ASCII byte of a name as `?`; when the counts disagree, no size is printed.

> **Amendment (2026-09-16).** Sources resolve, and the four holds are lifted together, as this decision
> required: `accept` takes a stub with a working link, `knowledge check` no longer fails an active one,
> and both forms of `jig context` resolve it to its source (ADR-0014, ADR-0015 as amended). The fifth
> — `--source` only with `--proposed` — stays. A stub records the text a human approved as
> `source_hash`, written by `accept` and `reviewed`. One definition, `km_source_states`, names each
> stub's source `ok`, `changed`, `unrecorded` (no hash — counted as changed, since nothing approved the
> current text) or `missing`; `jig status` counts changed and unrecorded on a `sources changed:` line,
> `knowledge stale` lists them, and `jig knowledge sources [--diff <id>]` shows every link with its size
> and the difference from the approved text when git still holds it. No copy of an approved text is
> stored: without it the source is reviewed whole. Resolution and acknowledgement re-check the source
> every time — a regular file, not a symlink, not under a symlinked directory leading outside the
> repository — because a source can be swapped after acceptance without the stub changing; such a source
> is `missing`. Re-approval is `jig knowledge reviewed`, dropping the
> link is `reject`; agents read the current text meanwhile.
