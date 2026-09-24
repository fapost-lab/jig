---
id: adr-20260924-a-worktree-carries-what-git-does-not
type: adr
status: accepted
date: 2026-09-24
domains:
  - task
  - install
  - config
paths:
  - scripts/lib/bootstrap.sh
  - scripts/lib/task.sh
  - scripts/lib/profiles.sh
  - scripts/lib/common.sh
  - scripts/lib/config.sh
  - "profiles/*/profile.yaml"
summary: Why a task worktree is given vendor, node_modules and .env from the checkout beside it rather than an install, what is copied and what is shared by link, and the measurements that chose the method.
reviewed_at: 2026-09-24
---
# ADR: A task worktree carries the state git does not track, from the checkout beside it

## Context

`jig task start <id> --worktree` gives a task a git checkout and nothing else. That is
enough for jig itself, which is shell with no dependencies, and it is wrong for almost every
project jig serves: `vendor/`, `node_modules/` and `.env` are gitignored, so a fresh worktree
is a tree in which the project's own checks cannot run.

ADR-0029 says "Worktrees need no install step here". The sentence is true of this repository
and was generalised from it — a dogfooding accident. It is amended by this decision.

The consequence is worse than inconvenience. While the supported road gives a broken tree and
the manual one gives a working tree, an agent will go around jig by hand, and no instruction
outweighs that.

## Decision

**A worktree is given a known-good state carried from the checkout that owns it, never an
install from the network.** Four reasons, in the order that decides the matter:

1. **Copying works on a host with no toolchain.** In the project this was written for, `php`
   lives in a devilbox container: `composer install` on the host is impossible, `cp vendor/`
   is not. This case alone rules out installing.
2. **No network is needed**, so the command keeps working offline and inside a sandbox that
   has no network at all.
3. **The result is exactly what already works next door**, rather than whatever resolving the
   manifest today produces.
4. **It is faster** — but only by the modest factor measured below, not by an order of
   magnitude. Speed is the weakest of the four reasons and nothing here rests on it.

**What is carried is declared, never guessed.**

- A profile declares its stack in `profile.yaml`: `carry:` (derived state to copy), `lock:`
  (files whose difference means what was carried is stale), `install:` (a command printed for
  a person, never run). Shipped: `php` → `vendor`, `node` → `node_modules`,
  `laravel` → `.env`. The reader already ignores keys nobody asks for, so no profile needed
  migrating.
- A project declares its own layout in `.ai/config.yaml`: `worktree.carry` and
  `worktree.share`. Both optional. The common case needs neither line, because profiles are
  detected.

**`share` is not a profile key and must not become one.** What is shared rather than copied is
always a project's layout, never a property of a stack; a profile that guessed it would guess
wrong.

**Two actions, told apart by the nature of the state, not by the kind of file.**

- **copy** — derived state, each tree's own: `vendor`, `node_modules`, `.env`.
- **share** — a source of truth under edit, which must stay single: `packages/`, separate git
  repositories wired in through composer path repositories. A copy would be a second clone of
  each package; an edit made in the worktree would sit in a clone the owning checkout cannot
  see, and the two would diverge in silence until a push.

**Only what the worktree does not already have is carried.** A path git brings itself is left
alone, which needs no list of exceptions: in two of the three live projects examined,
`packages/` is tracked by the parent repository, so the declaration is a no-op there.

**A shared directory is mirrored, not linked whole** — the directory is created in the
worktree and each of its entries is linked. This is forced by git, not chosen for taste: a
project keeps such a directory out of git with a trailing-slash pattern (`packages/`), and git
does not apply that pattern to a symlink. A linked directory therefore reads as an untracked
path, and `git worktree remove` without `--force` refuses the worktree for the rest of its
life — housekeeping would hold the task under `worktree-kept` forever and the tree would have
to go by hand, which is the cleanup by manual discipline ADR-0029 exists to avoid. A real
directory matches the pattern the project already has, so nothing is asked of the person.
Measured, both ways, on 2026-09-24. A per-worktree `info/exclude` was tried first and does not
work: git reads that file from the common directory, so it cannot describe one worktree.

**Nothing is ever installed.** When there is nothing to carry, the profile's `install` command
is named for a person to run. Running it was rejected: `task start` is not a build command,
the agent's sandbox may have no network, and — decisively — nothing to carry means the owning
checkout has no `vendor/` either, so the project is not installed there and the host may have
no toolchain at all, which is the very case this mechanism exists for.

**`.ai/` is refused, always and by name.** A worktree borrows exactly one workspace by link
(ADR-0029); a copy would give the task two `state` files diverging from the first write. So is
an absolute path, a path with dot segments, a path holding a space, tab or newline, a path that
is a link in the owning checkout, and a path resolving outside that checkout — the last checked
physically, because a symlinked parent leads out without a single `..`.

**The carry is the last step and is never fatal.** It runs after the branch, the workspace link
and the state writes, so a failure leaves a fully started task in a tree short of a dependency —
not a broken task, and not a tree holding half of one: each path is staged beside its destination
and renamed in, so the destination appears only once the carry is complete. Nothing is rolled back, because the tree and the branch are exactly what a
retry needs. `jig task bootstrap <id>` is that retry: idempotent by construction, working from
the owning checkout or from inside the worktree. Without it the only repair is by hand, and a
second `task start` refuses on the path that now exists.

**`--no-bootstrap`** skips the carry for one run. There is deliberately no project-level switch:
a key nobody fills is better not introduced.

**How to copy is a capability, never a platform** (ADR-0037). A probe on a temporary file asks
the only question that has an answer — does this `cp` accept the flag: `-c` (clonefile) on
macOS and the BSDs, else `--reflink=auto` on GNU coreutils, else a plain `cp -a`. Correctness
never depends on the probe, because both fast flags fall back to a full copy in silence when
the filesystem cannot clone. That silence is also why "did it clone?" cannot be asked.

## Measurements

Measured 2026-09-24 on live dependency trees, macOS 15.6, APFS, one volume. Disk use is the
difference in free blocks (`df -k`), not `du`, which counts a clone at full size.

| tree | method | time | disk |
|---|---|---|---|
| `vendor/`, 26,861 files, 201MB | `cp -a` | 12.27s | ~210MB |
| | `cp -c` (clonefile) | **5.35s** | **~11MB** |
| | `cp -R -l` (hard links) | 11.64s | ~15MB |
| `node_modules/`, 67,819 files, 839MB | `cp -a` | 34.82s | — |
| | `cp -c` (clonefile) | **12.70s** | — |
| | `cp -R -l` (hard links) | 30.20s | — |

**Hard links are rejected by these numbers, not by caution.** Their only argument was speed,
and it measures 5–13% against an honest copy — not an order of magnitude — while saving no more
disk than a clone. Where clonefile exists they lose on every axis; where it does not they buy a
tenth of the time in exchange for a package manager that edits a file in place corrupting the
neighbouring tree. Inode kinship was confirmed: `cp -R -l` gives `st_nlink=2` and the source's
inode, `cp -c` its own.

Installing, for comparison, with a toolchain on the host, a warm cache and a fast network:
`composer install` 19.7s (26,782 files), `npm ci` 26.9s (72,504 files). So installing is 1.5–3.7
times slower than a clone copy, not the order of magnitude first assumed. The claim "seconds
instead of minutes" did not reproduce and is not what this decision rests on; on a cold cache or
a slow link the gap widens, but the argument that decides is reason 1, not reason 4.

Relocatability was measured rather than assumed. `vendor/composer/*.php` computes `$vendorDir`
at runtime and holds no absolute host path; `node_modules/.bin/*` entries are relative symlinks.
Composer path repositories appear in `vendor/` as **relative** symlinks
(`vendor/bpartner/sso-server -> ../../packages/sso-server/`), with no absolute one found, so
after a copy they resolve inside the worktree and land in the shared directory — the tree stays
self-contained. All three copy methods preserve symlinks as symlinks.

**`python` deliberately declares nothing.** A virtualenv is not relocatable: copied elsewhere,
`.venv/bin/python` works and reports the new prefix, but every console script — `pip`, `pytest`,
`ruff`, `mypy` — keeps an absolute shebang into the original `.venv`, so `pip --version` from the
copy reports the *owner's* site-packages. `pytest` in a worktree would run against the
neighbouring tree's environment while appearing to work: the same silent divergence that makes
`packages/` shared rather than copied. Rewriting shebangs was rejected — editing another tool's
files during `task start` is not the framework's business. A wheel cache is the right carrier for
python, and is a separate decision.

## Alternatives

- **Install from the network in the worktree.** Rejected as the primary mechanism: it needs a
  toolchain on the host, which the motivating project does not have, and a network, which a
  sandbox may not have. Kept only as a sentence naming the command.
- **Hard links (`cp -R -l`).** Rejected on the measurements above.
- **Copy `packages/` like everything else.** Rejected: a second clone of each package's
  repository, diverging silently from the first.
- **Link a shared directory whole.** Rejected: git does not match a trailing-slash ignore
  pattern against a symlink, so the worktree is permanently un-removable by housekeeping.
- **A per-worktree `info/exclude`.** Tried and rejected: git reads it from the common directory.
- **Declare `share` in `profile.yaml`.** Rejected: sharing is a project's layout; a stack cannot
  know it.
- **Derive the shared paths from `composer.json`'s `path` repositories.** Attractive — it would
  remove the declaration for composer projects — but it needs JSON parsing in POSIX sh without
  `jq`, and the live projects examined point at three different directories (`./nova`,
  `./packages/*`, `./nova-components/*`), so the parse is not the easy case it looks like.
  Deferred, not refused.
- **A `worktree.bootstrap: false` project switch.** Rejected: nobody would fill it; `--no-bootstrap`
  covers the one run that wants it.
- **Roll the worktree back when the carry fails.** Rejected: the tree and the branch are what a
  retry needs.
- **Carry `.ai/workspace/`.** Rejected, and refused in code: two `state` files (ADR-0029).

## Consequences

- `jig task start --worktree` now writes into the new worktree, and on a large `node_modules`
  takes seconds rather than being instant. It says what it carried, with what and how long it
  took, and names every skip and refusal.
- **An edit to a shared package made from a worktree is not isolated in the task's branch.**
  This is an accepted trade, not a defect: the package lives in its own history, so the edit is
  not isolated today either, with or without jig. Sharing preserves exactly what happens without
  jig — one checkout of the package, edited from wherever.
- A new command, `jig task bootstrap`, and a new flag, `--no-bootstrap`.
- Three new `profile.yaml` keys (`carry`, `lock`, `install`) and two new config keys
  (`worktree.carry`, `worktree.share`). Config keys are team keys in `.ai/config.yaml`;
  `jig config set` does not accept them, by the existing rule that it writes only local keys.
- `cfg_list_lines` exists beside `cfg_list`, because `cfg_list` returns one space-separated line
  that every caller consumes with a bareword `for`, which would let a glob-shaped path expand
  against the real tree. Anything reading paths from config must use the new one.
- A worktree can now be stale rather than absent: a lock file differing between the owning
  checkout and the worktree is reported as a warning, never a refusal. The tree works; it is of
  the wrong vintage.
- **Each path is built beside its destination and renamed into place**, so the destination
  exists only when a carry finished. The loop reads an existing destination as already carried,
  and cleaning up after a failure cannot be relied on to restore that: a copy keeps the source's
  modes, so a single read-only directory inside a carried tree defeats `rm -rf` while leaving the
  remains exactly where the next run — `jig task bootstrap` included, the repair this decision
  rests on — would take them for finished work. The rename is atomic and within one directory, so
  no window exists in which the destination is partial. It is conventions/shell.md's rule for the
  manifest, applied to a tree.
- **The staging directory is `.ai/runtime/bootstrap` inside the worktree**, and that location is
  load-bearing rather than tidy. Staging beside the destination was tried first and reintroduced
  the failure this whole design exists to avoid: a project ignores `vendor/`, and
  `vendor.jig-partial.60347` is not `vendor/`, so an interrupted carry left an untracked path and
  `git worktree remove` without `--force` — the only removal jig performs — refused that worktree
  permanently. Under `.ai/runtime/` git ignores the remains (jig's own gitignore lists it without
  a trailing slash, so a directory and a link both match), and a `kill -9` that defeats every trap
  still cannot strand a worktree. The rename stays within one filesystem, so it stays atomic.
- **The run clears its staging directory on the way in and sweeps it on the way out**, by a trap,
  so remains do not accumulate across repeated `jig task bootstrap` runs. The directory is jig's
  own, so nothing in it is anyone else's to keep.
- **This adds no deletion outside `.ai/`.** What a failed carry built is removed, and it is always
  inside `.ai/runtime/bootstrap`; RULES.md therefore gains a shape, not a fifth exception. A
  carried path at its destination is never deleted, because a rename is what puts it there. A
  removal that does not succeed is reported rather than assumed: `rm -rf` exits 0 having deleted
  nothing when a directory inside the tree is not writable, and a copy keeps the source's modes,
  so the only answer worth having is whether the path is gone.
- **The destination is validated physically before anything is created.** `mkdir -p` and `cp`
  follow a symlink that is already in the worktree, so a link at an intermediate component of a
  declared path would let the carry write outside the tree. The owning checkout's side had this
  check from the start; the worktree's side needed it too.
- **The `.ai/` refusal is lexical *and* physical.** The lexical test is lowercased and applied to
  every segment, not the first: macOS and NTFS are case-insensitive by default, so `.AI/runtime`
  opens the real `.ai/runtime` and a case-sensitive test refuses nothing there — the same reason
  `km_source_problem` lowercases `.git`. Spelling is not the only way in, so the physical check
  above refuses a destination resolving into the worktree's `.ai/` however it got there.
- A package added to the owning checkout after a worktree exists does not appear in that
  worktree by itself, where a whole-directory link would have shown it. That costs close to
  nothing, and not because new packages are rare — a worktree exists for one task, so the
  contents of the shared directory at the moment it was created are what that task needs. A
  package installed later in another session belongs to *that* session's task, and reaches this
  tree the ordinary way: through the base, once that work lands on the default branch.
  `jig task bootstrap <id>` brings one in when it really is wanted here and now — an operation
  in its own right, not a workaround for the mirror. It does so by topping the mirror up with
  entries added since, which is why a destination that already exists is not simply skipped for a
  shared directory: git-tracked content is still left alone, but a mirror an earlier carry made is
  jig's to complete. Without that the trade above would have been accepted on a promise the code
  did not keep.
