# Knowledge sources that are sections of a file

Depth: normal — the design is worked out against the code; it is parked because it does not
pay for itself yet, not because it is unclear.

## Idea

What the `knowledge-adoption` specification left open (removed when it finished; in git
history): rules that live in a section of a file, such as a README's "Development" section, are
lost today — a stub (ADR-0036) can only link a whole file — and a reference to a section should
survive a renamed heading. The maintainer decided on 2026-09-18 to keep this for later: do it
only when it proves needed.

## Goal and problem

- Who is worse off without this, and how: a brownfield team whose rules sit in a README section.
  `jig-map` skips READMEs, so the rules reach an agent only as a copy `jig-init` made into
  `RULES.md`, which drifts from the README; linking the whole README hands the agent the project's
  shop window for twenty lines of rules.
- What is true when the work is done: a stub can link one section of a tracked file; an agent is
  given only that section; an edit outside the section is not a change to what was approved; a
  renamed heading is reported, with the section that still has the approved text named.

## Stress test

- Hidden assumptions — "this holds only if …": teams keep rules in README sections often enough
  to matter; headings are unique within a file; a heading is renamed without its text changing
  often enough for the hash hint to help.
- The main trade-off: precise context (only the section) against ~40 places in `common.sh`,
  `knowledge.sh` and `context.sh` that handle a stub's source, and a change to the acknowledgement
  ledger's format.
- The weakest point: a heading renamed together with an edit of its text is not recognised; it
  stays `missing` and a human relinks it.
- Failure modes — cause, what breaks, the signal that shows it: a duplicate heading added later →
  the section becomes ambiguous → `knowledge check` fails the stub; a heading renamed → `missing`
  on `jig status`/`knowledge sources`; a fenced code block containing `#` lines → mistaken for a
  heading unless fences are skipped (a test).
- Other shapes considered, and why this one: see Decisions.

## Scope and non-goals

- In scope: a stub field `section: "<heading text>"`
  (`jig knowledge new <type> <slug> --source <file> --section "<heading>" --proposed`); the section
  runs from that ATX heading to the next heading of the same or a higher level, headings inside
  fenced code ignored, the heading text unique in the file; resolution rows name the file, the
  section and its line range; `source_hash`, `changed`, `sources --diff` and `context acknowledge`
  work on the section's text; uniqueness becomes the pair (file, section), and a whole-file stub
  beside a section stub of the same file is refused; `inventory` shows `linked by <id> § <heading>`;
  `jig knowledge sources` names a section that still has the approved text when the heading is
  gone; `jig knowledge section <id> "<heading>"` relinks after a human's yes; `jig-map` links rule
  sections of READMEs, `jig-accept` shows the section, `jig-consolidate` edits the section.
- Not doing: a full migration of existing documents into Jig's structure — nobody has asked what it
  would produce that a link in place does not; it returns through `jig-idea` when someone does.

## Decisions

- The heading's exact text identifies the section — rejected: case- and space-insensitive matching,
  because an exact match is predictable and checkable.
- A renamed heading is reported, never followed — rejected: relinking automatically by hash,
  because a script would silently change what an agent reads.
- Rejected: a line range (`lines: 40-72`), broken by any edit above it; markers in the team's file
  (`<!-- jig:begin -->`), because Jig would edit documents it does not own (ADR-0036 refused team
  frontmatter for the same reason); copying the section into `.ai/knowledge/`, two copies of every
  rule; an anchor in the path (`README.md#development`), since `#` is refused in a source path and a
  slug depends on the renderer.

## Open questions

- How the acknowledgement ledger records a section (`<hash>\t<path> § <heading>` or a separate
  column) — decides whether an existing ledger stays readable.

## Assumptions left untested

- That README sections are a common home for rules in the projects Jig targets — taken at normal
  depth; tested by the next brownfield adoption that meets one.
