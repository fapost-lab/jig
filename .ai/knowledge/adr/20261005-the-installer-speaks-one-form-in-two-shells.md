---
id: adr-20261005-the-installer-speaks-one-form-in-two-shells
type: adr
status: accepted
date: 2026-10-05
domains:
  - install
  - scripts
paths:
  - install.sh
  - install.ps1
  - tests/install.t.ps1
summary: "The installer speaks the output blocks in bash and PowerShell: the same vocabulary and layout, a test-pinned copy in install.sh, console colours in install.ps1, plain bytes off a terminal."
reviewed_at: 2026-10-05
---
# The installer speaks the output blocks in both shells: one form, two implementations

## Context

adr-20261005-output-is-decorated-only-on-a-terminal gave Jig's reports one form — a level word
(`ok`, `warn`, `fail`) padded to six columns, details indented under the text, what needs a
person before what does not — decided in `scripts/lib/output.sh`, and only at a terminal. It left
one question to the installer: the first minute with Jig is `install.sh` (`curl … | bash`) on
macOS and Linux and `install.ps1` (`irm … | iex`) on Windows, and neither can use that layer.
`install.sh` runs before any checkout exists, and `install.ps1` downloads it alone into `%TEMP%`,
so there is nothing to source; `install.ps1` is PowerShell and cannot source bash at all.

The installer is also where the person Jig is written for — a non-developer, usually on Windows
— first meets its questions and refusals: four questions at most, and a refusal of the folder a
fresh PowerShell starts in (adr-20260926-the-installer-refuses-a-folder-it-must-not-own). And
its output is a machine contract twice over: `install.ps1` parses `install.sh`'s
`jig installed: …` line, and `tests/install.t.sh` and `tests/install.t.ps1` assert on both.

## Decision

- **"The same form" is the vocabulary and the layout, not the code.** A block is a level word
  padded to six columns, then the first line of text; every further line is indented six
  columns and keeps its own indentation, so a command the person types stays set off under the
  sentence that introduces it; an empty line stays empty. Level words: `ok`, `warn` (needs the
  person, or something they should know), `fail` (the run stopped), and `ask` for a question —
  the answer is typed after it on the same line. What needs the person comes before the closing
  line. The words are the plain form's words; at a terminal a level word replaces a prefix that
  said the same (`note:`, `install.sh: error:`).
- **The rule of when is the layer's rule, in both shells.** Only at a terminal; redirected
  output gets exactly the bytes printed before the blocks existed. `JIG_TERMINAL=1|0` overrides
  the measurement; a non-empty `NO_COLOR` or `TERM=dumb` removes colour and keeps the layout.
- **bash: a pinned copy.** `install.sh` carries the part of the layer it speaks
  (`_install_out_init`, `_install_block`), as it already carries the release-ordering helpers.
  `tests/install.t.sh` holds `_install_block`'s bytes equal to `out_status`'s for every level,
  with colour and without, and pins the plain output byte for byte. stdout and stderr are
  measured apart (`[ -t 1 ]`, `[ -t 2 ]`), so an error redirected into a file carries no escape
  code. The escape codes are made inside `_install_out_init`, so `sh install.sh` still reaches
  its "must be run with bash" refusal.
- **PowerShell: its own implementation, console colours.** `install.ps1` has `Test-JigTerminal`
  (`-not [Console]::IsOutputRedirected`, with `JIG_TERMINAL`), `Test-JigColor`,
  `Get-JigBlockLines` (the layout, pure, unit-tested) and `Write-JigBlock`. Colour goes through
  `Write-Host -ForegroundColor`, the console's own API, which an old conhost honours without
  virtual-terminal processing — never through escape codes, which it would print as text.
- **At a terminal, `install.ps1`:** keeps its `==> …` steps (the progress said before a long
  operation); turns each step's result into an `ok` or `warn` block; asks each question with
  `ask`, the words that explain a question indented above it; shows a refused folder as a
  `warn` block when the question is asked again and as the run's `fail` block when the run ends
  (`-Project`, `-Yes`, or the third refusal); shows `install.sh`'s own lines only when it
  failed, since the step's `ok    jig installed: …` says what they would; and runs `jig doctor`
  with `JIG_TERMINAL=1 NO_COLOR=1` — its grouped form, without escape codes.
- **A reader inside Jig asks for the plain form.** `install.ps1` runs `install.sh` with
  `JIG_TERMINAL=0` for that call, because it parses the summary line and a person's
  `JIG_TERMINAL=1` would reach it through the environment.
- **`ask` joins `scripts/lib/output.sh` with its first bash user.** No bash command asks a
  question yet; `jig-setup`'s item of the terminal-output specification adds it there, in this
  shape.

## Alternatives

- **One implementation, shared.** `install.ps1` could run a bash formatter through Git Bash, but
  it prints before Git exists (finding or installing Git is its first step), and `install.sh`
  has nothing to source. Two implementations of a five-line shape cost less than either
  workaround.
- **ANSI escape codes in PowerShell.** The same bytes as bash, but Windows PowerShell 5.1 on a
  console without virtual-terminal processing prints them as text — to exactly the audience
  this is for.
- **Colour in `jig doctor` under `install.ps1`.** Same reason: doctor's colour is escape codes.
  Its grouping is what shortens the report, and that survives `NO_COLOR`.
- **New words for the terminal form** (`fix:` labels inside the refusal). The refusal already
  reads as an instruction — what is wrong, that jig is installed, the three commands — and two
  wordings of one message would drift; the layout sets the commands off without new words.
- **Unicode marks.** As in the layer's ADR: a console code page may not have them.

## Consequences

- The plain form of both installers is unchanged byte for byte, so `Get-JigInstalledInfo`, the
  test suites and logs read what they read before; `tests/install.t.ps1` runs every scenario
  with `JIG_TERMINAL=0`, as `tests/run.sh` takes the overrides out of the bash suite.
- A change to a block's shape is now three edits — `output.sh`, `install.sh`, `install.ps1` —
  and only the bash copy is held to the source by a test. The PowerShell layout is pinned by its
  own unit test, against the same examples.
- What CI cannot show — the colours in a Windows PowerShell 5.1 console, the `ask` word and
  `Read-Host`'s prompt on one line, whether the refusal reads as an instruction — is on
  `.github/WINDOWS_RELEASE_CHECKLIST.md`, for the release that ships it.
