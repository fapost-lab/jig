# Roadmap — Terminal output people can read

Destination: a person reads a Jig command's output once and knows what happened
and what, if anything, is theirs to do.

## Phase 1 — Prove the shape on one command

Goal: `jig doctor` can be read once, and the way it is built is reusable.
Done when: a run with warnings shows what needs a person before what does not,
a piped run is byte-identical to today's, and a Windows terminal renders it.

- [ ] doctor reads in one pass — group the passing checks into one line, keep
  what needs a person expanded with its fix; the shared output layer (terminal
  detection, `NO_COLOR`, the block vocabulary) arrives inside this item, since a
  layer on its own gives nobody anything
- [ ] fog: how the PowerShell side stays consistent with the bash side — the
  installer cannot share the layer, and what "consistent" means there is not a
  question we can state precisely before the vocabulary exists

## Phase 2 — The runs that made this necessary

Goal: the two commands a person reads after acting say what happened, not
everything that happened. Done when: an upgrade of 55 files fits on a screen
without losing what the reader must act on.

- [ ] upgrade says what changed, not every file it touched — group the
  replacements, keep installs, deletions, conflicts and hints expanded
  (after: doctor reads in one pass — the block vocabulary is defined there)
- [ ] status adopts the same blocks (after: doctor reads in one pass — same
  reason)

## Phase 3 — First contact

Goal: the first minute with Jig looks designed, on both shells. Done when: the
installer and `jig-setup` ask their questions in the same form as the rest.

- [ ] the installer asks and answers in the new form, in bash and in PowerShell
  (after: doctor reads in one pass — the vocabulary; and phase 1's fog item,
  which decides what "the same form" can mean across two shells)
- [ ] jig-setup asks its questions in the new form (after: the installer — the
  same prompt shapes, written once)

## Waves

1. doctor reads in one pass
2. upgrade says what changed; status adopts the same blocks
3. the installer asks and answers in the new form; jig-setup asks its questions in the new form
