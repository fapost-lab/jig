---
id: adr-20260924-jig-owns-a-marked-section-of-the-instructions
type: adr
status: accepted
date: 2026-09-24
domains:
  - install
paths:
  - scripts/lib/init.sh
  - scripts/lib/upgrade.sh
  - scripts/lib/manifest.sh
  - scripts/lib/section.sh
  - templates/AGENTS.md
summary: Why jig upgrade may replace a marked section inside the project-owned AGENTS.md, and how that narrows ADR-0024.
---
# ADR-20260924: Jig owns a marked section of the project's instructions

## Context

`AGENTS.md` is placed once, by `_init_place_if_absent`, and is project-owned from that
moment: absent from the manifest, never overwritten, never restored (ADR-0003). It is also
absent from `_upgrade_build_staged` and therefore from the union of paths `jig upgrade`
walks. There is no path by which an upgrade could even see the file.

The consequence is that every improvement to what Jig *says to an agent* is frozen at the
version a project was set up on. Skills do get updated, but a runtime loads them on
request — after the agent has already decided whether to work Jig's way or its own. The
instructions are what it reads first, and they are the one thing that never moves.

The one existing route, the `jig-init` skill merging the section into an existing file,
runs only when a human thinks to ask for it. "Routine maintenance never depends on a
developer remembering to run it" is a scope invariant of this framework (`RULES.md`), and
this is a plain violation of it.

Three constraints bound any fix. There is no JSON or YAML parser and only `git` as a
dependency (ADR-0002). Nothing a human wrote may be overwritten, which is what ADR-0003
and ADR-0024 rest on. And the manifest's ownership model is whole-file: a body entry is
`<hash> <path>`, which ADR-0024 named as the reason it had no vocabulary for a framework
owning part of a project's file.

## Decision

The framework owns one **marked section** of the project's `AGENTS.md`, delimited by two
literal whole lines it writes itself:

    <!-- jig:begin -->
    ...the framework's text...
    <!-- jig:end -->

- The markers carry no version and no hash. The marker line is a literal that must stay
  matchable forever, so everything that changes between releases lives inside the section
  and travels with it — including the comment that tells a reader the section is managed.
- The region is `## Read first` and `## Workflow`. This is not a new boundary: it is the
  one `templates/AGENTS.md` already had, enforced until now by an awk range over heading
  text. Markers replace a heuristic with an explicit delimiter. `## Working rules` stays
  outside, because it is the project's.
- What jig last wrote there is recorded in the **manifest header**, one key:
  `instructions.section: <hash> <path>`, the hash being `git hash-object` of the section
  normalised to LF.
- `jig upgrade` applies the same decision table it applies to any framework-owned file —
  `replace` when the section is unchanged since jig wrote it, `keep-modified` when it is
  not, and the same words in the report. Two `keep-` outcomes are new: `keep-unmarked`
  when there is nothing of jig's to update, and `keep-malformed` when the marker pair
  cannot be read unambiguously.
- **`upgrade` never adopts a section.** With no record, every outcome is a `keep-`.
  The first time jig claims a region of a file a project already had, a human agrees to
  it: the `jig-init` skill shows the section verbatim (ADR-0031) and merges it with the
  markers, and `jig init` then records it. `init` writes nothing into `AGENTS.md` that was
  not already there, and it records a section under one condition only: **the region is
  byte for byte what jig itself would write**, the marked region of the source's own
  `templates/AGENTS.md`. Claiming an identical region destroys nothing, because the next
  upgrade would write exactly those bytes; text that merely sits between markers somebody
  typed is never adopted, and stays `keep-conflict` until a human goes through the skill.
- **`init` carries an existing record forward rather than re-deriving it.** `init` is
  re-run for unrelated reasons — adding an adapter, switching profiles — and re-deriving
  the hash from disk would silently re-baseline a section a human had edited, turning the
  next upgrade's `keep-modified` into a `replace` over their words. An edit inside the
  region stays switched off until a human agrees again; so does a section they removed.
- Anything ambiguous is a refusal. More than one marker of either kind, a missing half of
  the pair, or an end before its begin, and jig reports `keep-malformed` and writes
  nothing.
- The section is compared and hashed normalised to LF and written back in the file's own
  line endings, so a CRLF checkout (ADR-0037) neither reads as modified nor ends up with
  mixed endings.

`templates/AGENTS.md` becomes a framework-owned installed file, `.ai/templates/AGENTS.md`,
for the reason ADR-0011 gives: a consumer project has no framework checkout for the skill
to read the section from. `skills/jig-init/references/agents-section.md`, which was a
byte-for-byte copy of part of the template, is deleted.

## Why ADR-0024's reason does not reach this case

ADR-0024 refused to edit `.claude/settings.json` and closed with: "Any future integration
with a project-owned config file inherits this rule: offer the snippet, own the script,
detect by reading." This decision narrows that sentence, and owes an account of how.

**Its first reason was arbitrary JSON the framework does not control, with no parser.**
That does not reach here. The delimiters are two literal lines jig wrote, in a file jig
created from its own template or into which jig's own text was merged with consent. Jig
parses *nothing* of the project's document: it needs to understand no line outside its own
two markers. There is no partial understanding to get wrong — either the pair is present
exactly once and in order, or jig refuses. ADR-0024 also rejected "merge a tagged entry
with shell text processing" because a JSON editor in bash 3.2, correct against an
arbitrarily formatted file, is not a small job and every bug in it damages a file the
framework cannot rebuild. There is no editor here: a file is cut on two whole lines into
three parts and joined back.

**Its second reason was that the manifest has no vocabulary for "the framework owns four
lines inside a file the project owns."** This is the one that had to be answered rather
than avoided. The answer is that the manifest gains neither a second ownership model nor a
second decision table. It gains one named key in the header, beside `jig.version`,
`jig.source`, `jig.mode` and `adapters` — where facts about the install already live. The
outcomes stay the same three words, computed the same way: the hash of what jig wrote
against the hash of what is there now. Only the unit changes, from a file to a region jig
can identify by a delimiter it authored. In `settings.json` there was no delimiter, and
identifying the entry meant understanding JSON. ADR-0024's rejection of "extend the
manifest with a merged entry record type" — a second model and a second table for exactly
one file — still stands, and is precisely why the record here is a header fact.

**A third point should not go unsaid: "the framework never writes inside a project's file"
already does not describe the code.** `cmd_init` appends missing lines to the project's
`.gitignore` and `.gitattributes`. The rule as actually implemented is *only `init`, only
by appending, and never `upgrade`*. This decision moves that boundary: `upgrade` begins to
write, and to write by replacement. What does not move, and is the real invariant:

- the first time jig writes into a file a project already had, a human has agreed;
- any edit inside the region turns replacement off until a human agrees again;
- ambiguity is a refusal, never a guess;
- what a human removed is never restored — the same conclusion ADR-0024 reached about a
  deleted session-hook line.

**Finally, the `knowledge-sections` specification already rejected `<!-- jig:begin -->`**,
on the grounds that "Jig would edit documents it does not own (ADR-0036 refused team
frontmatter for the same reason)". That refusal is about *somebody else's documents* — a
team's README adopted as a knowledge source, whose text the team wrote. It stands for its
own case. The dividing line is not whose name is on the file but who wrote the region and
whether a human agreed to its being there; inside these markers, the author is Jig.

## Alternatives

- **An importable framework-owned file** — `AGENTS.md` stays the project's and pulls in an
  updated file with one line. Rejected: it would rest on whether a given runtime supports
  file imports (Claude Code does, Codex's support is unverified), and Jig is
  vendor-neutral — the mechanism has to work the same everywhere.
- **Only report staleness** — `jig status` says the section is old and leaves it there.
  Rejected as the answer: it depends on a human reading and acting, which is the behaviour
  this decision exists to remove. Kept as an addition: `status` and `doctor` report the
  section's state.
- **A body entry, `<hash> AGENTS.md#jig`.** Rejected: every reader splits an entry on its
  first space, so a pseudo-path enters `manifest_paths` and then gets hashed, walked and
  reported as a missing file by three readers with every right to assume a path is a path;
  an older jig on a newer manifest would report phantom drift; and `#` in a path was
  already rejected by the `knowledge-sections` specification.
- **No manifest record at all: compare against the installed `.ai/templates/AGENTS.md`.**
  Tempting, since "what jig wrote last time" would be a file the manifest already tracks.
  Rejected for two reasons: on `keep-modified` the record must *not* advance, while a
  framework-owned template does advance, so a project that reverted its text to an older
  version would afterwards be judged against a newer one; and it would make the decision
  depend on the order in which upgrade walks paths.
- **A line range instead of markers.** Rejected, following `knowledge-sections`: any edit
  above the range breaks it.
- **Recognising an untouched section by a ledger of every released section's hash**, so
  upgrade could add the markers itself. Rejected: the ledger must be kept forever and
  grows with every release, and a project that pasted the section from the documentation
  site by hand never matches it anyway — a permanent cost for partial coverage.
- **A non-interactive `jig upgrade --adopt-instructions`.** Rejected: the first write into
  a file a human owns stays consented, and the channel for that consent already exists.

## Consequences

- Improvements to what Jig tells an agent reach an installed project through the ordinary
  `jig upgrade` a person already runs, with no new habit to acquire.
- A project keeps every escape: edit the section and it is yours; remove the markers and
  nothing comes back; never adopt them and `upgrade` only ever prints one line about it.
- That line, `keep-unmarked AGENTS.md`, prints on every upgrade of a project that keeps its
  own instructions. It is deliberately outside `upgrade_pending`'s filter, so it never
  blocks `jig verify` — a project that chose its own instructions would otherwise be
  blocked forever by that choice.
- `replace AGENTS.md (Jig section)` *is* inside that filter, because a stale section is
  pending work like any other. This is why the report reuses the existing verbs instead of
  inventing new ones.
- The text of the section now has one source, `templates/AGENTS.md`. The documentation site
  keeps a copy because a website cannot read a file, and a test holds the two equal —
  markers included, since a section pasted without them is a section nothing updates.
- Anything that later wants to keep part of another project-owned file current inherits
  this rule, not ADR-0024's: jig may own a region it wrote, delimited by markers it wrote,
  recorded as one header fact, adopted only with consent. `.ai/config.yaml` is the obvious
  next candidate and is not decided here.
