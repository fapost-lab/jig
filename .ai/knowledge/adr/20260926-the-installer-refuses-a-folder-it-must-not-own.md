---
id: adr-20260926-the-installer-refuses-a-folder-it-must-not-own
type: adr
status: accepted
date: 2026-09-26
domains:
  - install
paths:
  - install.ps1
summary: Why install.ps1 refuses the home folder, a drive root and a folder inside someone else's repository as a project folder, why -Yes cannot turn that off, and why install.sh needs no such guard.
reviewed_at: 2026-09-26
---
# The installer refuses a project folder it must not own

## Context

`install.ps1` prepares a first project after it has installed the framework:
it asks which folder (Q1), whether to make that folder a git repository (Q2),
and then runs `jig init`, `git add -A` and one commit.

Both questions defaulted towards yes, and that is what made the default path
dangerous. `irm ... | iex` from a fresh PowerShell leaves the current
directory in the user's profile. Q1 offered the current directory as its
default; Q2 defaulted to yes on an empty answer; `-Yes` skipped both. So the
shortest, most likely run turned the whole of `C:\Users\<name>` into a git
repository and staged everything in it -- documents, keys, whatever else the
profile holds -- in the first minute of the product, for the user who by
definition cannot undo it. There was no check on the profile, on the root of a
drive, or on a repository above the folder.

Two things found while fixing it decide the shape of the guard rather than
merely supporting it:

- **`jig init` writes at the repository root, not in the folder it was run
  in** (`jig_require_repo`, `scripts/lib/common.sh`). A folder inside somebody
  else's repository therefore does not get `.ai\`, `AGENTS.md`, `CLAUDE.md`,
  `.claude\settings.json` and a `.gitignore` line -- *that repository's root*
  does, which is not the folder the person named. The installer's existing
  `--is-inside-work-tree` check hid this: it saw a repository, skipped
  `git init` and skipped the commit, and let `jig init` write anyway.
- **The danger does not need `git init` to happen.** When `$HOME` is itself a
  repository -- dotfiles, which is ordinary -- nothing runs `git init` or
  `git add`, and `jig init` still writes into the profile. A guard conditioned
  on "are we about to create a repository here" would miss that.

## Decision

One function, `Get-JigProjectDirRefusal`, decides about a candidate project
folder and returns the text of a refusal or nothing. `Initialize-JigProject`
puts every candidate through it -- from `-Project`, from the current directory
under `-Yes`, or typed at Q1 -- before the folder is created and before
`git init`, `jig init`, `git add -A` and the commit can reach it.

Refused: the home folder; any folder that contains it (`C:\Users`, the root of
the system drive); the root of a drive or UNC share; and a folder inside a
repository whose root is some other folder.

Allowed, because a guard is also what it stays silent about: an ordinary new
or empty folder, including one deep inside the profile -- that is the way out
of a refusal -- and a folder that *is* a repository root, which is the
everyday "add jig to the project I already have" case the installer has always
handled by never committing into a repository it did not create.

The two questions case 4 asks are answered without reading a word of git's
output, because the installer's own `Invoke-JigNative` merges stderr into it
and one `warning:` line would otherwise be taken for an answer -- failing open
in the direction of the harm. Whether the folder is in a work tree at all is
`rev-parse --show-toplevel`'s exit code; whether it is that work tree's root is
whether the folder holds `.git` itself. The probe runs with `GIT_DIR`,
`GIT_WORK_TREE` and their relatives cleared for its duration, mirroring
`jig_clear_git_location_env` (`scripts/lib/common.sh`): with `GIT_DIR` set and
no `GIT_WORK_TREE`, git calls the current directory the top of a work tree and
would answer for every folder on the disk, refusing all of them. Git's text is
read only to name the root in the message, so a reply that does not look like a
path costs a worse sentence and never a wrong decision. Comparing the folder
with that text instead would be a guess at one spelling of a path that git
writes `C:/Users/...`, PowerShell writes `C:\Users\...`, and Windows also has
an 8.3 form of.

`-Yes` does not reach this. It means "take every default answer", and a flag
that agrees with questions is not consent to a folder: the refusal reads no
flag, and no branch of it is skipped when one is present. `-Project` is refused
the same way -- a flag names a folder, it does not grant permission for it.

It is a refusal and not a warning: a warning printed into an `irm | iex`
one-liner is not read. Non-interactively it throws, which `Install-Jig` prints
red and exits 1 on. Interactively the refusal is printed and Q1 asked again, up
to three times, and a current directory that is itself refused is no longer
offered as Q1's default. Asking again is still a refusal, because no answer
makes the refused folder acceptable; what it avoids is ending the run over a
first-time user's first Enter.

There is no flag that turns the guard off. A flag-shaped exemption is the
guard's own bypass with documentation: a person told to add one adds it. The
refusal names the folder, says that jig itself is installed and only the last
step stopped, and prints the two commands that lead out.

`install.sh` is not changed, and the asymmetry is deliberate. It has no project
step at all -- no `git init`, no `git add`, no `git commit`, and no read of the
launch directory; every `git` call in it addresses the remote or its own
checkout under `$HOME/.local/share/jig`. On macOS and Linux a person runs
`jig init` in their own project, so there is nothing there to guard.

## Alternatives

- **Warn and continue.** Rejected: this is the one path where the output
  scrolls past in a piped one-liner, and the cost is not inconvenience but an
  index holding a whole profile.
- **Refuse only when the installer itself would run `git init`.** Rejected: it
  misses a profile that is already a repository, where `jig init` writes into
  the profile with no `git init` in sight.
- **A flag to allow it anyway** (`-AllowHomeAsProject` and the like).
  Rejected: see above.
- **Refuse any folder with a `.git` anywhere above it, including a repository
  root.** Rejected: it breaks "add jig to my existing project", which is the
  normal way Jig is adopted.
- **Also refuse `Desktop`, `Documents`, `Downloads`.** Rejected: the default
  path is the profile itself, since that is the current directory of a fresh
  PowerShell, while those have to be typed. A list of suspicious profile
  subfolders is guesswork and would drift with Windows.

## Consequences

- `install.ps1` grows its first guard of the form "where this installer must
  not write", beside the ones `RULES.md` already records of the form "what it
  may delete".
- Three tests in `tests/install.t.ps1`, which runs in the `smoke-windows` job on
  every pull request: the default scenario (`-Yes -Project <profile>` must exit
  non-zero, name the folder, and leave no `.git`, `.ai` or `AGENTS.md` behind);
  a table holding both halves of the decision as `conventions/detectors.md`
  requires -- each refused shape, and each shape it must stay silent about; and
  the interactive path, driven in-process with `Read-JigValue` overridden,
  because a child process started `-NonInteractive` cannot answer a prompt. The
  rest of the file is the silent half too: every other scenario installs into a
  folder deep inside the profile, and an over-wide rule turns them red.
- Two known limits, not guarantees. The comparison against the home folder is
  textual after normalisation, so another spelling of the same folder -- an 8.3
  short name, a `subst`'ed drive -- is not caught. And `.git` in the folder is
  read as "this folder is its own root": a copied worktree or submodule
  directory whose `.git` file still points at another gitdir, or a
  `core.worktree` pointing elsewhere, is therefore allowed, and `jig init` would
  write at that other root. Both guard the person who did not mean to, which is
  the whole population this exists for, rather than one trying to get past it.
  A bare repository is not a hole in the safe direction: `--show-toplevel` fails
  outside a work tree, so the folder is allowed and `jig init` then refuses
  through `jig_require_repo` with nothing written.
- `.github/WINDOWS_RELEASE_CHECKLIST.md`'s first-questions step now carries the
  one check CI cannot make: the line was pasted without changing directory, so
  the first question must refuse the profile rather than offer it. It stays one
  step, because a second paste would ask the person to reproduce what step 3
  already shows them.
