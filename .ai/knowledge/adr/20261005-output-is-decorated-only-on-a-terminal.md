---
id: adr-20261005-output-is-decorated-only-on-a-terminal
type: adr
status: accepted
date: 2026-10-05
domains:
  - install
  - scripts
paths:
  - scripts/lib/output.sh
  - scripts/lib/doctor.sh
summary: A report is grouped and coloured only when stdout is a terminal, decided once in scripts/lib/output.sh; a pipe, CI and an agent get the bytes printed before the layer existed.
reviewed_at: 2026-10-05
---
# A command's report is decorated only when stdout is a terminal, through one output layer

## Context

Jig's reports were one undifferentiated stream: a success, a hint and an error carried the same
weight, and `jig doctor` printed thirteen passing checks around the two lines that needed a
person. The terminal-output specification (`.ai/specs/terminal-output/`) asks for reports a
person understands without reading twice, by form rather than tone — and puts volume and
grouping before colour, because colouring sixty lines of noise leaves sixty lines of noise.

The same bytes are also a machine contract. Agents, CI logs and `install.ps1` read them, and the
test suite pins them with about 2500 `assert_contains` calls. Before this decision nothing in
`scripts/` measured whether stdout was a terminal, read `NO_COLOR`, or printed an ANSI escape.
Several commands are to adopt the new form (`upgrade`, `status`, the installer, `jig-setup`),
so where the form is decided and what blocks it is built from has to be decided once.

## Decision

- **`scripts/lib/output.sh` is the output layer.** A command that prints a report through it
  sources it and calls `out_init` once, as a plain command (it memoises into globals). It is
  the only place that decides the form; a command asks `out_terminal` and never tests
  `[ -t 1 ]` itself.
- **Two forms.** *Plain* when stdout is not a terminal: every block prints exactly the bytes
  the command printed before the layer existed, in the same order, as each line is known.
  *Terminal* when `[ -t 1 ]`: the command may group and reorder what it says, and the blocks
  add colour.
- **Overrides.** `JIG_TERMINAL=1` treats stdout as a terminal (tests, Windows CI, `less -R`);
  `JIG_TERMINAL=0` never does (an agent whose runtime gives commands a pseudo-terminal).
  Colour is on only in the terminal form, and off when `NO_COLOR` is non-empty or `TERM` is
  `dumb`. `NO_COLOR` removes colour, not grouping.
- **The block vocabulary.** `out_status <ok|warn|fail> <text>` (the level word padded to six
  columns), `out_detail <label> <text>` (indented under the status line above it, as
  `fix: …`), `out_group <level> <summary> <name>...` (many items of one level in one line),
  `out_gap` (a blank line between groups) and `out_summary <text>` (the closing line). A new
  shape is added here, with its plain bytes pinned in `tests/output.t.sh`, not printed by hand
  in a command.
- **Words carry the meaning; colour reinforces it.** The level word is always printed. ASCII
  only, and no `tput`: plain SGR codes, which mintty, Windows Terminal and the Git Bash console
  all render (ADR-0037), with no terminfo dependency (ADR-0002).
- **`jig doctor` is the first command on it.** In a pipe its report is byte-identical to the
  one before. At a terminal it prints failures, then warnings, each with its fix, then every
  passing check in one line (`ok    13 passed: git, git identity, …`), then the tally. The
  exit code does not depend on the form.

## Alternatives

- **Colour always, with a `--no-color` flag.** Breaks logs, agents and the suite's assertions;
  the specification rejected it.
- **Group in both forms.** Shorter output everywhere, but a pipe would get new bytes, which is
  the one thing the plain form promises not to do.
- **The layer inside `common.sh`.** `common.sh` holds answers two commands must not disagree
  about; how a report looks is a subject with its own tests, like `section.sh`.
- **`tput` for capabilities.** An external program with a terminfo database that Git Bash does
  not always ship, for the five codes used here.
- **Unicode marks (✓, ✗).** Left out until a command needs them: a Windows console code page
  may not have them, and the level word already says the same.

## Consequences

- A reader who pipes a report into a pager gets the plain form; the specification accepted that
  trade. `JIG_TERMINAL=1` brings the terminal form back on purpose.
- The terminal form of doctor waits until every check has run (the release check can take up
  to `_JIG_RELEASE_CHECK_TIMEOUT` seconds) before printing, because ordering by what needs a
  person cannot stream. The plain form still streams.
- The details of a passing check (for example which config keys sit on their default) are
  only in the plain form; at a terminal a passing check is its name in the group line.
- `tests/run.sh` unsets `JIG_TERMINAL` and `NO_COLOR`, so a developer's environment never
  changes the form a test reads.
- `install.ps1` is PowerShell and cannot source this layer; what "the same form" means across
  the two shells is decided by the installer's own item of the specification.
- That ANSI renders for a person on Windows is proven by nothing in CI: CI proves only that the
  terminal form runs in Git Bash and produces the expected bytes.
