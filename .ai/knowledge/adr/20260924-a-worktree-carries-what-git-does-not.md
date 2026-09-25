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
summary: Why a task worktree is given vendor, node_modules and .env by copying them from the checkout beside it rather than installing, how the carry proves with git that what it placed cannot strand the worktree, and the measurements that chose the copy method.
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
- A project declares its own layout in `.ai/config.yaml`, with `worktree.carry`. It is
  optional; the common case needs no line at all, because profiles are detected.

**One nature of state is carried: derived state, each tree's own** — `vendor`, `node_modules`,
`.env`. It is copied, because a copy is what such state wants: each tree needs its own, and
nothing is lost when a tree goes.

**State that must stay single is deliberately out of scope**, not forgotten. A directory of
separate git repositories wired in as composer path repositories — `packages/` — is a source of
truth under edit, and copying it is not a lesser version of serving it but a different and worse
thing: see the risk named under Consequences, and the `worktree-share` task, which holds that
analysis whole.

**Only what the worktree does not already have is carried.** A path git brings itself is left
alone, which needs no list of exceptions.

**Nothing is ever installed.** When there is nothing to carry, the profile's `install` command
is named for a person to run. Running it was rejected: `task start` is not a build command,
the agent's sandbox may have no network, and — decisively — nothing to carry means the owning
checkout has no `vendor/` either, so the project is not installed there and the host may have
no toolchain at all, which is the very case this mechanism exists for.

**The carry proves its own safety instead of predicting it.** Everything it puts in a worktree
must be invisible to git, because `git worktree remove` without `--force` — the only removal jig
performs — refuses a worktree with anything untracked in it, and housekeeping can then never clean
that tree up (ADR-0029). So the carry records what git reports before it starts, places a path,
asks git again, and takes straight back out anything it made appear, reporting it and naming the
remedy (`.gitignore`).

This replaced four separate guards that each predicted the same answer and each got it wrong in
its own way: a path's spelling compared case-sensitively, a staging name the project's ignore rule
did not cover, `git ls-files` asked in one case while `-e` and `-d` answered in another, and a
a declared directory nobody had ignored at all. Every one of them was a proxy for "will git see this",
and every proxy has another door — case folding, unicode normalisation on HFS+, `core.ignorecase`,
a symlinked component. Four review rounds found four doors. Asking git has none, because it is the
same question, put to the same program, that housekeeping will put to it later.

The precondition this makes explicit, rather than assuming: **a path is carried only if the project
keeps it out of git.** That is what every project with an install step already does, and where it
does not, the carry says so and does nothing.

**A declared path that is untracked and not ignored is refused, and the price of refusing it is
accepted.** The price is not small and is named here rather than discovered later: such a project
gets a worktree in which its checks do not run — precisely the harm this decision exists to end.
The trade is "the tree is useless" in place of "the tree can never be deleted", and it was taken
for three reasons. A useless tree is visible immediately and is fixed by one line in `.gitignore`,
which the refusal itself names; an undeletable tree is discovered weeks later and is fixed by hand,
which RULES.md forbids as cleanup by manual discipline. The case is narrow: a `vendor/` that is
untracked and unignored means the owning checkout is itself sitting under thousands of `??` lines.
And the refusal is not silent — it says what to do. A path that is *tracked* and ignored is a
different case and is kept: git reports nothing either way, so nothing is stranded.

**The undo is proved the same way the placement is.** Taking a refused placement back out acts on
a recorded list of what was made, and that list is not what says it worked — git is asked again
afterwards, and an undo that did not restore the worktree is reported as one the person has to
look at. A list is accounting, and accounting has gaps. The gap that proved it was reached through
a mechanism no longer here: the list is newline-separated, and a mirror built its lines from entry
names found inside a shared directory, so an entry whose own name held a newline arrived as two
lines naming nothing — nothing was removed, and a clean refusal was reported over a worktree
`git worktree remove` refuses for good. What carries now records one validated path per placement,
so that particular gap is closed by construction. The principle is kept anyway, because it is
cheap and because the next gap will not announce itself: for as long as the accounting is also the
proof, any gap in it is a silent stranding.

**A rename that landed is told from one that nested by identity, not by name.** Placing a path is a
rename onto a destination re-tested immediately before, and a backstop catches what slips through
that window: `mv` moves *into* a directory that appeared meanwhile, burying the carried tree a level
down. The backstop compares the inode the staged tree had against the destination's afterwards,
because the name test it replaced — is there a `<dst>/<staged basename>` — cannot tell a nested
rename from a carried tree that legitimately holds a top-level entry of its own name, which
`carry: [data]` over a `data/data/` does on the first try. Where a filesystem reports no usable
inodes both reads come back equal and the backstop stands down; the re-test is what closes the
window that matters.

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
after a copy they resolve inside the worktree — where they find whatever the project put there,
which for a path-repository layout is the open question the `worktree-share` task inherits.
All three copy methods preserve symlinks as symlinks.

**`python` deliberately declares nothing.** A virtualenv is not relocatable: copied elsewhere,
`.venv/bin/python` works and reports the new prefix, but every console script — `pip`, `pytest`,
`ruff`, `mypy` — keeps an absolute shebang into the original `.venv`, so `pip --version` from the
copy reports the *owner's* site-packages. `pytest` in a worktree would run against the
neighbouring tree's environment while appearing to work: the same silent divergence that makes
`packages/` a case this decision does not serve by copying. Rewriting shebangs was rejected — editing another tool's
files during `task start` is not the framework's business. A wheel cache is the right carrier for
python, and is a separate decision.

## Alternatives

- **Install from the network in the worktree.** Rejected as the primary mechanism: it needs a
  toolchain on the host, which the motivating project does not have, and a network, which a
  sandbox may not have. Kept only as a sentence naming the command.
- **Hard links (`cp -R -l`).** Rejected on the measurements above.
- **A per-worktree `info/exclude`.** Tried and rejected: git reads it from the common directory.
- **A `worktree.bootstrap: false` project switch.** Rejected: nobody would fill it; `--no-bootstrap`
  covers the one run that wants it.
- **Roll the worktree back when the carry fails.** Rejected: the tree and the branch are what a
  retry needs.
- **Carry `.ai/workspace/`.** Rejected, and refused in code: two `state` files (ADR-0029).

## Consequences

- `jig task start --worktree` now writes into the new worktree, and on a large `node_modules`
  takes seconds rather than being instant. It says what it carried, with what and how long it
  took, and names every skip and refusal.
- A new command, `jig task bootstrap`, and a new flag, `--no-bootstrap`.
- Three new `profile.yaml` keys (`carry`, `lock`, `install`) and one new config key
  (`worktree.carry`). It is a team key in `.ai/config.yaml`;
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
- **A carry can now decline.** A declared path the project neither tracks nor ignores is placed,
  seen, and taken back, with a message naming `.gitignore` as the fix. That is a visible refusal
  where the alternative was a worktree nobody could remove and no warning at all. The tree it
  hands back is then one whose checks do not run, and that price is accepted above rather than
  worked around.
- **`git status` runs after every path placed, not once for the run.** It has to: asked once at
  the end it says the worktree is dirty without saying which path dirtied it, and there would be
  nothing to take back precisely. Where the project ignores what it declares — the ordinary case —
  the cost is nothing, because git walks only what it can see. Where it does not, **the refusal is
  slow**: each status walks every untracked file in the tree before the placement is taken back
  out, and there is one such walk per declared path. That is the case a project sees once, on the
  run that tells it to edit `.gitignore`.
- **Taking back is a move, not a new deletion.** What was placed is moved into the staging
  directory and deleted there, so every deletion still happens inside `.ai/runtime/`. Only what
  this run created is ever moved, and a move that fails leaves the path and says so: a worktree a
  person must look at is the honest outcome, where silence would leave one nobody can remove.
- **Containment judges a link by where it lies, not by where it points.** `cd -P` through a
  symlink answers about its target, so a link lying in the worktree looked as if it were outside
  it and was skipped by the take-back. Moving or removing a link never touches its target, so the
  location is the only thing that matters.
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
- **A carried path that contains a separate git repository can take a person's work away with
  the worktree, silently.** Measured on 2026-09-24, not reasoned about: a project with
  `packages/` in `.gitignore`, holding a real repository with its own `.git`, declared as
  `worktree.carry`. The carry copies the repository wholesale, so the worktree gets a *second
  clone*. Work done there — a commit in that clone, and an uncommitted file beside it — is
  invisible to the parent: `git status --porcelain` in the worktree is empty, because the path
  is ignored. `git worktree remove` without `--force` refuses on tracked changes and untracked
  files but **deletes ignored files silently** (ADR-0029 measured that too), so it returns 0 and
  takes the clone with it. The commit was in no other clone and the owning checkout never saw
  it; it is simply gone, with no message at any point.

  Jig's own cleanup no longer walks into this: before removing a worktree it asks git what it
  would delete silently, finds the repositories among those paths and asks each one's own git,
  and holds the worktree when the work is nowhere else
  (adr-20260925-a-worktree-goes-only-when-every-git-in-it-agrees). What that cannot reach is
  `git worktree remove` run by hand, which is git's contract and unchanged. So the measurement
  above still describes the bare command exactly, and the address of the danger is what moved.

  It is why a directory of separate repositories under edit **must not** be declared as
  `worktree.carry`, and why that is not offered anywhere as a stand-in for sharing: the second
  clone is the defect, and a worktree the cleanup declines to remove is a held tree, not a
  working arrangement. The carry is for derived state, which by definition can be thrown away —
  and derived state is also what the new guard deliberately does *not* hold, `.env` and a local
  database among it. Whether the carry should refuse a declared path that contains a `.git`
  outright is a decision, not a fix, and is open.
