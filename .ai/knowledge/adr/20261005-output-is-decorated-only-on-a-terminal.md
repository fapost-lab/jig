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
  - scripts/lib/upgrade.sh
  - scripts/lib/status.sh
summary: A report is grouped and coloured only when stdout is a terminal, decided once in scripts/lib/output.sh; a pipe, CI and an agent get the bytes printed before the layer existed.
reviewed_at: 2026-10-06
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
  in a command. A report too long for one list is drawn by section (amended below):
  `out_heading <text> <level> <verdict>`, `out_section <title> [<counts>]`,
  `out_row <style> <width> <text>...` and `out_join <item>...`; after `out_init` a command may
  read `OUT_WIDTH`, `OUT_SEP`, `OUT_MARK` and `OUT_MORE`, the width and marks those blocks use,
  as variables, so a row costs no process.
- **Words carry the meaning; colour reinforces it.** The level word is always printed. ASCII,
  except the marks a section is drawn with (amended below), and no `tput`: plain SGR codes,
  which mintty, Windows Terminal and the Git Bash console all render (ADR-0037), with no
  terminfo dependency (ADR-0002).
- **`jig doctor` is the first command on it.** In a pipe its report is byte-identical to the
  one before. At a terminal it prints failures, then warnings, each with its fix, then every
  passing check in one line (`ok    13 passed: git, git identity, …`), then the tally. The
  exit code does not depend on the form.

- **`jig upgrade` is the second.** In a pipe its report is byte-identical to the one before.
  At a terminal the replacements (and an interrupted run's reconciliations) are said once,
  grouped by their first two directories (`ok    replace 50 file(s): .ai/scripts (14),
  .claude/skills (17), …`), just before the summary — so a run that dies midway names none it
  had replaced, and its repeat reports them as `already-placed`; installs, deletions and links stay one
  `ok` line each, every file kept (`keep-modified`, `keep-conflict`, …) one `warn` line, and
  each hint a detail under its note. An upgrade of 58 files went from 66 lines to 17.
- **`jig status` is the third.** In a pipe its report is byte-identical to the one before. At a
  terminal the plain report is written first and read back (`_status_terminal`), so the two forms
  cannot disagree, and it is read by section (amended below): a heading with the verdict, then
  what needs the person — failures before warnings: a refusal, a task that is paused, blocked,
  stale, stopped or lowered (judged by the words the task line builder writes, never by a
  worktree path or a pause reason), drift, an epic whose branch is missing, knowledge awaiting a
  decision, a flag housekeeping left (`see:` its log), a hint (the newer-release hint is a `warn`
  with the command as its `hint:`) — and then the rest, each in its section. The form is decided
  in `cmd_status` alone, above every reader of the report: the status page and each of its
  redraws (`jig status --html|--refresh`, `jig_status_page_touch`, the hand-off from a worktree)
  call `_status_report` itself and so always embed the plain lines, and `jig doctor` reads
  `_status_framework_versions`, which only ever prints plain. In its first, grouped form (a few
  `ok` lines closed by `jig X: nothing needs you`) 31 lines in this repository became 12.
- **A reader inside Jig asks for the plain form.** Code that captures a Jig report to filter
  its lines — `upgrade_pending`, the upgrade's self-check — sets `JIG_TERMINAL=0` for that
  run, because the person's `JIG_TERMINAL=1` reaches it through the environment and would
  hand it lines its filter does not know.

## Alternatives

- **Colour always, with a `--no-color` flag.** Breaks logs, agents and the suite's assertions;
  the specification rejected it.
- **Group in both forms.** Shorter output everywhere, but a pipe would get new bytes, which is
  the one thing the plain form promises not to do.
- **The layer inside `common.sh`.** `common.sh` holds answers two commands must not disagree
  about; how a report looks is a subject with its own tests, like `section.sh`.
- **`tput` for capabilities.** An external program with a terminfo database that Git Bash does
  not always ship, for the five codes used here.
- **Unicode marks (✓, ✗).** Left out: a Windows console code page may not have them, and the
  level word already says the same. The section marks of the amendment below are not a meaning
  of their own, and fall back to ASCII.

## Amendment — a long report is read by section (2026-10-05)

`jig status` at a terminal grew to about 75 lines on a real project (11 `config.local:` lines,
24 `working here:` lines), and its grouped `ok` lines ran to several screen rows each. The
owner asked for it to be read by section, with a rule between sections and one row per item.

- **Sections.** A sectioned report opens with `out_heading`: what it is about on the left
  (`jig 0.21.0 · fapost-core · copy mode · up to date`) and the verdict on the right edge
  (`nothing needs you`, or `N items need you`, coloured as the worst level among them). Each
  section is a blank line and `out_section`: its title on a rule drawn to 80 columns, with its
  counts after it (`── Tasks  (10 active · 12 finished) ───…`). Its items are `out_row`s, two
  spaces in, in aligned columns. The width is a fixed 80 columns, not measured: `COLUMNS` is not
  exported to a child, and `tput` is not a dependency.
- **`jig status` sections.** Needs you (only when something does; nothing in it is repeated in
  the section it belongs to), Install, Settings, Tasks, Knowledge & specs, Recent activity here.
  Related settings sharing a first segment (`housekeeping.*`, `claude.*`) are one row. The
  activity is folded: the latest record on its own row, then one row per command and hour,
  counted; a row is the age, the command, then what it ran on, so a group has the rest of the
  line for the first ids that fit. Its last row says who holds HEAD here, by
  `jig_checkout_occupants` — the rule every refusal uses — and is the one fact, with the
  project's name in the heading, that the terminal form asks for beyond the plain report.
- **UTF-8 marks, only where the locale says UTF-8.** The rule `─` (U+2500), the separator and
  remark mark `·` (U+00B7) and the ellipsis `…` (U+2026) are drawn only in the terminal form and
  only when the first of `LC_ALL`, `LC_CTYPE` and `LANG` that is set names UTF-8, as the C
  library reads it, and the shell could take that locale (a locale that is not installed leaves
  `${#var}` counting bytes, and every column after a mark off); otherwise `-`, ` | `, `.` and
  `...`. The plain form stays ASCII whatever the
  locale. `NO_COLOR` and `TERM=dumb` remove colour, not sections.
- **Colour.** A section title is bold cyan and its rule dim; counts are plain. Level words keep
  their colours; a task id is bold; class `T3`/`T4` is yellow, `T2` plain, `T0`/`T1` dim; a
  task's notes (its own worktree, uncommitted files, a base of its own, a lean route, a running
  autopilot, `ready`) are yellow; an
  activity row's age is dim.
- **Measured.** On a fixture shaped like the owner's project (10 active tasks, 24 activity
  records, 11 `config.local` keys) the plain report is 59 lines; the grouped terminal form of
  #195 was 18 lines that wrapped to 31 rows at 80 columns; the sectioned form is 41 lines, none
  wider than 80 columns (a settings row too long for one goes on under itself).

## Amendment — tasks are grouped by epic and spec (2026-10-06)

The owner asked for the tasks of one epic to be read together, on the status page and at a
terminal.

- **Grouping.** The Tasks section groups its rows when any of them belongs to a spec: a line per
  epic (a spec whose roadmap has an `Epic:` line), then per spec without an epic, each as the
  spec's title in bold and `(epic · 3/5 done)` dim; its tasks under it on the branches of a tree;
  `Other tasks` last. With no task of a spec, the rows stay flat. The page's "Running now" groups
  the same way, a heading and a table per group.
- **One more fact asked beyond the plain report.** Which spec a task belongs to, by
  `jig_spec_link` and `jig_spec_epic` — the reading `task start` and the spec commands use — and
  the spec's progress, `spec_phase_rows` summed, read from the epic's branch when progress is
  made there (ADR-0040). With who holds HEAD and the project's name, these are what the terminal
  form asks for beyond the plain report; the plain report's `task …` lines do not change.
- **Two more marks.** `├─` (U+251C U+2500) and `└─` (U+2514 U+2500), the branch to a row of a
  group and to its last row, drawn under the same rule as the other marks; `|-` and `` `- `` in
  ASCII. A branch is dim.

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
- `install.ps1` is PowerShell and `install.sh` runs before any checkout exists, so neither can
  source this layer: what "the same form" means across the two shells is
  adr-20261005-the-installer-speaks-one-form-in-two-shells — the same vocabulary and layout,
  a test-pinned copy in `install.sh`, console colours in `install.ps1`.
- That ANSI renders for a person on Windows is proven by nothing in CI: CI proves only that the
  terminal form runs in Git Bash and produces the expected bytes.
