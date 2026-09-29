# Terminal output people can read

Depth: normal — one question per real decision. The forks are few, but two of
them are expensive to get wrong: what the machine contract is, and where colour
is decided.

## Idea

> нам нужно как то изменить вывод скриптов. Очень красиво сделано у ларавел
> промпт, все должно быть в цвете и форматировано с блоками разных типов и т.п.
> это я так понимаю большая задача, но мы должны идти в ногу со временем а не
> быть как линукс консоль 20 лет назад

Asked for first: the installer and `jig-setup`. Then `jig status` and
`jig doctor`; `jig upgrade` is the run that prompted this.

## Goal and problem

- **Who is worse off without this, and how:** the person Jig is built for — a
  non-developer, usually on Windows — meets the product through an installer
  that asks questions in plain grey text, and through runs whose sixty lines of
  output give a success, a hint and an error the same weight. The maintainer
  hit it directly on 2026-09-25: `jig upgrade` printed 55 replacements, two
  hints and a red error in one undifferentiated stream, and whether the install
  was sound could not be told by looking.
- **What is true when the work is done:** a person understands what happened
  **without reading the output twice**. Where a run succeeded, where it refused,
  what needs them and what is only for the record are told apart at a glance —
  not by tone, but by form.

## Measured starting point (2026-09-25)

- No ANSI escape anywhere in `scripts/` or the installers. No `tput`.
- `[ -t 1 ]` — the test for "is this a terminal" — appears zero times.
- `NO_COLOR` is read nowhere.
- ~1200 output sites across `scripts/lib/*.sh`.
- **2489 `assert_contains` calls in `tests/`.** This is the size of the machine
  contract, and the reason presentation must decorate rather than replace.

## Scope and non-goals

- In scope: the installer, `jig-setup`, `jig status`, `jig doctor`, and the
  shared output layer they need.
- Not doing: a full TUI. ADR-0002 allows POSIX sh / bash 3.2 and no mandatory
  dependency beyond git, so live redrawing components are out of reach by
  construction. Colour, weight, indentation, grouping, symbols and alignment
  are not.

## Stress test

- **The weakest point, and it reshaped the idea:** the run that prompted this
  was unreadable because of **volume**, not colour. Fifty-five `replace …`
  lines are noise; colouring them yields fifty-five coloured lines of noise.
  Colour only works once there is little enough left for it to mark.
- **The main trade-off:** decorating only on a terminal keeps the machine
  contract free, but a person who pipes into a pager loses the formatting. That
  is accepted: the pager reader is a developer, the terminal reader is who this
  is for.
- **Hidden assumption, named:** that ANSI reaches the target audience. Windows
  Git Bash and Windows Terminal do render it, older conhost needs VT enabled.
  `install.ps1` is PowerShell and cannot share the bash layer at all — the
  installer therefore pays for two implementations.
- **Colour must never be the only carrier.** Monochrome terminals, colour-blind
  readers, and a copy-paste into a chat all strip it. Form and words carry the
  meaning; colour reinforces it.

## Decisions

- **Volume and grouping first, colour second.** Reduce what is said before
  deciding how it looks — rejected: colouring the current output as it stands,
  because the stated success ("understood without reading twice") is not
  reachable that way.
- **Decorate only when stdout is a terminal** (`[ -t 1 ]`), and honour
  `NO_COLOR`. A pipe, CI and an agent receive today's bytes unchanged —
  rejected: colour always with a `--no-color` flag, because it breaks logs,
  agents and 2489 existing assertions.
- **Proof of concept first**, not a sweep of ~1200 output sites.

## Open questions

- Which command carries the proof of concept.

## Assumptions left untested

- That ANSI renders acceptably for a non-developer on Windows — taken at
  normal depth; a run of the chosen command on windows-latest CI, and one
  person's screenshot, would test it.
