---
id: adr-20261002-a-worktree-shares-a-directory-by-mirroring-it
type: adr
status: accepted
date: 2026-10-02
domains:
  - task
  - install
  - config
paths:
  - scripts/lib/bootstrap.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/config.sh
summary: Why a directory of separate repositories under edit is given to a task worktree as a mirror of links rather than a copy or a link to the directory, how the mirror proves with git that it cannot strand the worktree, and why removing the worktree cannot take the shared work.
---
# ADR: A task worktree shares a directory by mirroring it, one link per entry

## Context

Some projects keep, beside their own code, a directory of separate git repositories under edit —
`packages/`, wired in as Composer path repositories. Each package has **one source of truth**: an
edit made from any tree must land in the same checkout of that package. Without the directory a
worktree of such a project does not run at all, so until now the only way to work on two tasks at
once in it was not to: one task at a time, in the main checkout.

`worktree.carry` (adr-20260924-a-worktree-carries-what-git-does-not) is the wrong tool and was
kept out of this case on purpose. A copy gives the worktree a second clone of each package; work
done there is invisible to the owning checkout, and — measured on 2026-09-24 — `git worktree
remove` without `--force` deletes the ignored clone without a word, commit and all. Housekeeping
now holds such a worktree (adr-20260925-a-worktree-goes-only-when-every-git-in-it-agrees), but a
held tree is not a working arrangement, and a removal by hand is still git's contract.

The design approved before this one said `share` links the directory itself. That cannot work,
and the reason is git's, not taste. Projects keep the directory out of git with a slashed pattern,
`packages/`, and **git does not apply a slashed pattern to a symlink**: the slash means "a
directory", and a symlink is not one to git. Measured on a live project:

| variant | `git status --porcelain` in the worktree | `git worktree remove` without `--force` |
|---|---|---|
| a link to the directory | `?? packages` | refused: `contains modified or untracked files` |
| a mirror (a real directory, entries are links) | empty | removed, directory gone |

After the mirror was removed the owner's `packages/` was intact: removing a link never touches its
target.

## Decision

**`worktree.share` names directories a task worktree shares with the checkout that owns it. Each
is given to the worktree as a mirror: a real directory whose every entry is a link to the owner's
entry of the same name.** The link is a symlink, or an NTFS junction where symlinks cannot be made
(`jig_link_dir`, ADR-0037). A file entry is linked only by a symlink; where only junctions work it
is named and skipped, because a copy of it would diverge. Link targets are absolute.

It is a team key in `.ai/config.yaml`, beside `worktree.carry`, and **never a profile key**: what
is shared rather than copied is always one project's layout, never a property of a stack.

**The mirror is placed the way a carried path is, and proves itself the same way.** It is built
in the worktree's `.ai/runtime/bootstrap`, renamed into place, and then git is asked what it now
sees; anything it made appear is taken back out, with `.gitignore` named as the remedy. The
placement step — re-test the destination, rename, catch a nested rename, ask git, take back — is
one helper both actions call. So the conditions a mirror needs are not predicted from spellings or
patterns but answered by git: a directory the project does not ignore, a case variant of a tracked
directory, anything else that makes the mirror visible all end in the same refusal (the F10 and F11
findings of the first attempt were both predictions that missed).

**Refused before anything is made**, besides everything `carry` refuses: an owner path that is not
a directory, and an owner path that holds `.git` itself — that is one repository, not a directory
of them, and mirroring it would link its `.git`. An entry whose name holds a newline is skipped and
named: the record of what was made is newline-separated. That gap was the reproducer of F13; the
take-back is proved by git regardless, so the skip is a courtesy and not the guard.

**A path declared both ways is shared, not carried**, and so is a path that lies inside or around a
shared one: the copy is the case that loses work, so of the two mistakes the safe one is made, and
the skipped carry is named.

**A destination already present is left alone unless it is a mirror.** A link, or a directory in
which git tracks anything, is what git brought, and is never touched — asked as `git -C <dst>
ls-files`, from inside the directory, so the filesystem decides the case and not the spelling. Any
other directory at the destination is a mirror and is **topped up**: each owner entry it lacks is
linked in, git is asked once, and everything added is taken back if git saw it. This is what
`jig task bootstrap <id>` does for a package the owner gained after the worktree was cut. One line
reports the outcome per path, so a partial top-up never reads as two contradictory messages (F15).

**Removal needs nothing new, and that is the point of mirroring.** The work lives once, in the
owner. Housekeeping's walk for nested repositories runs `find` without `-L`, so it does not enter
the links and finds no repository to hold the worktree for; `git worktree remove` deletes the links
and not their targets; on Windows, where git leaves links behind, `_hk_worktree_leftover` removes
only links. `tests/bootstrap.t.sh` and `tests/housekeeping.t.sh` hold this with the measured scenario — a commit with no remote
and an uncommitted file made in `<worktree>/packages/<pkg>` — through a bare `git worktree remove`
and through housekeeping, and the same scenario under `carry` is what loses the commit.

## Alternatives

- **A link to the directory.** Rejected: measured above, it strands every worktree.
- **The worktree's `info/exclude`.** Rejected: git reads it from the common directory, so one
  worktree cannot have its own, and writing the shared one changes git's behaviour for every tree.
- **Asking the project to add an unslashed pattern to `.gitignore`.** Rejected: a key a person must
  fill in for the basic case (zero configuration beyond the declaration itself).
- **Copying (`carry`).** Rejected: the second clone is the defect, and it loses work on removal.
- **Reading the paths from `composer.json` (`repositories` of type `path`).** Deferred, not
  rejected: it needs JSON parsing in POSIX sh without `jq`, and live projects point at three
  different shapes (`./nova`, `./packages/*`, `./nova-components/*`).

## Consequences

- **The mirror is a snapshot of the directory's entries.** A package added to the owner after the
  worktree was cut does not appear in it by itself; `jig task bootstrap <id>` adds it. A link to the
  directory would have shown it at once, and that is the price of a worktree that can be removed.
  The documentation names it.
- **An entry made inside the mirror is the worktree's own.** A real directory created in
  `<worktree>/packages/` is not shared and goes with the worktree; if it is a repository holding
  work that is nowhere else, housekeeping's nested-repository guard is what keeps it, as for any
  ignored path.
- **No new deletion.** A refused mirror is taken back by moving it into the staging directory and
  deleting it there, exactly as a refused carry is; what is deleted is a directory of links, and
  deleting a link — a symlink, or a junction under Git Bash (ADR-0037) — never touches its target.
  A test takes back a refused mirror and asserts the owner's entries are intact, which on Windows
  CI runs with junctions.
- Composer's relative symlinks (`vendor/<vendor>/<pkg> -> ../../packages/<pkg>/`) resolve inside
  the worktree, into the mirror, and from there into the owner's checkout: the carried `vendor/`
  and the shared `packages/` meet without either knowing about the other.
- `jig_config_keys`, `schemas/config.md` and `templates/config.yaml` gain `worktree.share`.
