# Jig as a single Go binary

Status of this session: **parked** on 2026-10-01 after the stress test — see the closing
note under Open questions. Depth: deep — the idea reverses an accepted decision (ADR-0002, reaffirmed by ADR-0037),
changes how Jig reaches a project and its CI, and rewrites ~21k lines of scripts and ~41k of
tests (2,391 tests in 47 files); almost nothing in it is cheap to take back.

## Idea

In the human's own words (Russian, verbatim; English gloss below):

> дурная идея на развитие.... если сделать джиг на базе ларавел-зеро и скомпилировать в апп
> при помощи нейтив пхп?
>
> давай через jig-idea именно используя голенг

Gloss: rewrite Jig as one Go binary, cross-compiled for macOS, Linux and Windows, instead
of the POSIX sh / bash 3.2 scripts — so that Windows runs Jig natively, without Git Bash,
and the non-developer audience gets a zero-config install. (Laravel Zero + NativePHP was
the first form of the idea; Go was chosen in the same conversation because it
cross-compiles to a 5–10 MB static binary without a runtime.)

## Goal and problem

- Who is worse off without this, and how — four pains, in the order the human ranked them:
  1. **Jig's own development on Windows is fragile.** The last two releases were Windows
     repairs (CRLF, MSYS paths, a doctor test). Every pull request risks a red `main` on a
     platform the author cannot see, and the Windows suite costs ~15 minutes in six shares
     because Defender scans every one of the tens of thousands of processes a shell suite
     starts (ADR-0037, adr-20260924-windows-runs-on-a-pull-request…, adr-20260925-…-six-shares).
  2. **Jig is slow where it matters.** `jig context` walks the tree once per path pattern:
     291 walks, ~8,500 processes, 30–39 s on a project with 83 documents; agents start
     skipping it (docs/known-issues.mdx). The cost is the shell model itself — a process per
     `sed`, `awk`, `grep` — not one algorithm.
  3. **Install for a non-developer on Windows is a 1,322-line PowerShell script** (winget,
     UAC, `PATH`, Git Bash as a foreign world next to the PowerShell the person sees).
  4. **A runtime without bash cannot call Jig directly.** Codex on Windows goes through
     `jig.cmd`, which loses inner double quotes — cmd.exe's quoting (ADR-0037).
- What is true when the work is done — the strongest form, chosen by the human:
  **`jig` is one static binary per platform (macOS, Linux, Windows); bash is needed nowhere
  — not for a command, not for a verify profile, not for the session hook.** In PowerShell
  it runs natively. `git` stays the only mandatory dependency (ADR-0002's zero-dependency
  property survives; its *shell* property does not). The command-line contract is kept 1:1,
  so skills, docs and knowledge that say `jig <command>` do not change.
- Not a goal: keeping the scripts readable to the agent. ADR-0002's "anyone can read what a
  command does" is given up deliberately; `--help`, `--explain` and the documentation carry
  that weight. Recorded under Decisions.

## Stress test

Independent failure hunt run 2026-10-01 in a clean context against the repository; the
numbers below are its, re-measured, not the conversation's.

- Hidden assumptions — "this holds only if …":
  - *"Windows runs Jig without Git Bash"* holds only if git is not mandatory. It is
    (ADR-0002), on Windows git is Git for Windows, and Git for Windows always carries bash.
    The port removes bash from **Jig's code**, not from the machine; the install step that
    hurts (installing Git, UAC, `PATH`) stays. Claude Code itself treats Git for Windows as
    optional and runs hooks in PowerShell without it — so the port does open the
    PowerShell-only machine, which is a scenario nothing tests today.
  - *"The port fixes Windows fragility"* holds only if the fragility is in the language.
    ADR-0037 measured the 83 probe failures: one third language (MSYS paths, `+x`), two
    thirds filesystem (symlinks, junctions, `chmod`, CRLF). The binary inherits the two
    thirds.
  - *"The port makes Jig fast"* holds only if the cost is process spawning. The 30–39 s is
    `jig knowledge check` doing 291 tree walks; `jig context` is ~10 s, and
    adr-20260930-resolve-guard-share-a-required-rows-cache already removed part of it in
    bash. The fix is algorithmic (one walk, cached rows) and reachable without a port. The
    port removes the *remaining* per-process cost, which is real on Windows (Defender scans
    every process start) but unmeasured in isolation.
  - *"The sh suite is the parity oracle"* holds only if the tests drive `jig` as a process.
    About a quarter do not: 17 places source `scripts/lib/*.sh` and call functions
    (`tests/bootstrap.t.sh`, `config.t.sh`, `housekeeping.t.sh`, `section.t.sh`,
    `manifest.t.sh`, `status.t.sh`, `verify.t.sh`), `dispatcher.t.sh` (60 tests) tests the
    bash dispatcher, `install.t.sh` (40) tests `install.sh`, and 352 profile tests run
    `bash profiles/<x>/verify.sh` directly. 2,663 assertions compare verbatim output text, so
    the port is byte-for-byte on messages or the tests are rewritten.
  - *"Skills and docs do not change"* holds only if the invocation path stays. 110 literal
    `.ai/scripts/jig …` references in 30 files (skills, `templates/scheduler/*`, the AGENTS.md
    marked section) and the hook line in `.claude/settings.json`, which Jig never edits
    (ADR-0024). With a global binary the verb contract holds; the **path** contract does not.
- The main trade-off: one typed implementation with a real YAML/JSON reader removes the
  whole class the Windows ADRs are workarounds for (CR stripped by `grep`/`sed`/`awk` before
  the regex sees it, MSYS path translation, `hash-object --stdin-paths`, `jig.cmd` losing
  quotes, `bash` resolving to the WSL launcher, six CI shares with Defender paused) — at the
  price of rebuilding distribution, release engineering, the deletion audit and the
  knowledge base, and of a feature freeze while it happens.
- The weakest point: **the port attacks the third of Windows failures that is in the
  language, and makes the other two thirds more dangerous around deletion.** Since Go 1.23
  `os.Lstat` on Windows reports a junction as `ModeIrregular`, not `ModeSymlink`. The
  deletion invariant (RULES.md; ADR-0006, 0029, 0037: "only links, never followed, and empty
  directories") was proven for bash's `-L` / `find -type l` / `cd -P`. A port that asks "is
  it a link?" the Go way either never cleans a Windows worktree (`worktree-kept: leftover`
  forever) or hands a junction to `os.RemoveAll`, which walks into the main checkout's
  `.ai/workspace`. Every enumerated deletion is re-audited, with reparse-point syscalls, not
  translated.
- Failure modes — cause, what breaks, the signal that shows it:
  1. *Two update mechanisms disagree.* The binary leaves the tree, but 13 skills, 31
     templates, the AGENTS.md section and `.gitattributes` lines are still placed and hashed
     in `.ai/manifest` (ADR-0003, ADR-0017, adr-20260926, adr-20260930). A binary pin and a
     manifest can name different versions → binary 0.19 with 0.17 skills describing flags
     that no longer exist. Signal: `jig status` says `drift: 0` while an agent reads a stale
     skill.
  2. *Embedded profiles delete a contract.* Profiles are copied into projects, a user may
     edit one, and `upgrade` keeps it as `keep-modified` (ADR-0013; adr-20260918 calls `jp_*`
     "a distributed interface"). In `embed.FS` nothing of that exists; the only customisation
     left is `.ai/verify/<profile>.map` (ADR-0041), which cannot add a check or change a tool
     lookup. Signal: a project that patched `.ai/profiles/php/verify.sh` loses the patch at the
     first binary upgrade and `verify` reports a *skip* that an autopilot run reads as green.
  3. *Unsigned binaries meet the audience.* Today a release is a CI tag with deliberately no
     GitHub Release page (ADR-0034); `install.sh` is `git clone`, `self-update` is
     `git fetch --tags` (ADR-0033). A binary needs six artefacts, checksums, HTTP
     self-update, both installers rewritten. `Invoke-WebRequest` sets Mark-of-the-Web →
     SmartScreen "Windows protected your PC" for a person ADR-0037 says cannot take a manual
     step; Go binaries are a known Defender false-positive class, and CI cannot show it
     because `ci.yml` pauses Defender to run the suite. Signing is a yearly cost and a
     secrets-in-CI story the repository has none of. Signal: the first Windows user report.
  4. *Network where the clone used to suffice.* ADR-0003: "cloning the repo yields a fully
     working agent environment". With a global binary, a fresh clone or a CI job has nothing
     until it downloads the pinned version (rate limits, proxies, air-gapped runners); the
     session hook must still "exit 0 in every circumstance" at the cost of one `stat`, so a
     missing binary means housekeeping silently stops for half a team. Signal: ADR-0024's
     "report no one reads".
  5. *The knowledge base points at the old tree.* 76 of 91 knowledge documents carry
     `paths:` into `scripts/`, `profiles/`, `install.*`; ADR-0002, 0003, 0033, 0037,
     RULES.md:151 ("POSIX sh / bash 3.2; run shellcheck") and AGENTS.md all state the shell
     decision. Without a superseding ADR *before* the first Go file, `jig context` hands
     bash-era knowledge to the agent porting Go, and `jig knowledge stale` lights 76
     documents at once. Signal: the framework's own process is what the port breaks first.
  6. *CI doubles and its Windows trigger goes blind.* Parity means 2 × (2 platforms + 6
     Windows shares) per pull request for the length of the port, on a budget already
     contended at three to five pull requests at once (adr-20260925).
     `ci-windows-scope.sh` selects Windows runs by bash failure classes (`cygpath`, `MSYS`,
     `exec-path`, `\r`) and will not fire for a Go path bug. The scenario the port targets
     — Claude Code hooks run by PowerShell with no Git Bash — has no CI lane, no checklist
     entry, and `templates/scheduler/` has no Task Scheduler template.
- Other shapes considered, and why this one:
  - *Fix the measured pains in bash.* One-walk knowledge resolution (already begun), a
    JSON-free hook detector, keep Git Bash. The smallest version worth having; it removes
    the slowness and none of the text-processing class. Rejected as the whole answer, kept
    as the baseline the port must beat (see Open questions).
  - *Hybrid — the bash dispatcher delegates ported commands to the binary.* Users get speed
    early; two runtimes in the wild and Git Bash on Windows until the end. Rejected (see
    Decisions).
  - *Port the hot core only* (`context`, `knowledge`, `status`, the manifest hashing) as an
    optional accelerator. It is the hybrid with a smaller surface and the same two-runtime
    cost. Rejected for the same reason.
  - *A spike before the commitment* — port `knowledge` + `context` + the junction/deletion
    primitives to a standalone Go prototype, run them on the Windows runner **with Defender
    on**, and measure against the bash baseline; decide go/no-go on numbers. This is the
    shape recommended for Phase 0: it is the only one that answers findings 2, 3 and 8 with
    evidence instead of argument, and it costs weeks, not the quarter.

## Scope and non-goals

- In scope:
- Not doing:

## Decisions

- **Readability of the scripts to the agent is given up.** ADR-0002's "anyone can read what a
  command does; agents can too" is no longer a requirement: `--help`, `--explain` and the
  documentation carry it. — rejected: Go sources placed in the project beside the binary,
  because it costs a toolchain or a build cache on every machine for a property the agents
  rarely used.
- **Features in bash are frozen for the length of the port; only bug fixes land**, and each
  one is ported in the same task. The three open specs and the task backlog wait for the Go
  implementation. — rejected: features in bash while the port catches up, because a port
  against a moving target is the premortem ("70 % parity, two implementations alive, nobody
  closes either"); rejected: backlog first and the port after, because that moves the idea
  by months and changes nothing about the fragility the backlog keeps paying for.
- **The sh test suite is the parity oracle during the port and is retired afterwards.**
  Tests call `jig` as a process through `$JIG_BIN` (`tests/lib/assert.sh:157`), so the same
  suite runs against the binary command by command. After the swap, new tests are written in
  Go; the sh suite is frozen and deleted once Go coverage reaches it. — rejected: keeping the
  sh suite forever as e2e, because then developing Jig still needs bash and the Windows suite
  stays a 15-minute, process-heavy job — pain 1 would leave the user and stay with the
  maintainer; rejected: Go tests first, port second, because it doubles the work before the
  first visible result.
- **Released once, at the end, as 1.0.0 on an epic branch** (ADR-0040). No phase gives a
  user anything on its own: "bash needed nowhere" is true only when the last command and the
  last profile are ported. The release level is `major`: the implementation and the way it
  reaches a project both change, even though the command-line contract does not. — rejected:
  a hybrid where the bash dispatcher delegates ported commands to the binary, because users
  would run two runtimes at once and Windows would still need Git Bash until the end.
- **Distribution: one global `jig` that switches to the version a project pins.** The
  binary is installed once per machine; versions live in a per-user cache
  (`~/.local/share/jig/versions/<v>/`, `%LOCALAPPDATA%\jig\versions\<v>\`). Run inside a
  project, `jig` reads the pinned version from `.ai/manifest` and re-executes that version —
  the `rustup` / Go-toolchain pattern. A version missing from the cache is fetched, or, when
  that is refused or impossible, reported with the one command that installs it, which the
  agent relays to the person. Old versions are removed when no known project pins them, or
  by age. Nothing of Jig's code is committed to a project. — rejected: a committed shim
  (`.ai/scripts/jig` sh + `jig.cmd`) with a cache, because the shim is bash on Unix and a
  cmd file on Windows, so "bash needed nowhere" is false by construction and the
  extensionless `.ai/scripts/jig` still cannot run from PowerShell; rejected: committing the
  binary, because a host then holds many copies with no way to control which one runs or how
  it is upgraded, and every upgrade stays in the history of every project. **Consequence
  accepted:** the invocation path changes from `.ai/scripts/jig` to `jig` in the 110 places
  that name it (skills, templates, scheduler files, the AGENTS.md section) — the verb
  contract is frozen, the path contract is not; and a fresh clone needs the binary before
  anything runs, so the project's own instructions say how to install it.

- **Profiles stay files the project can override; the binary interprets them.** A profile is
  declarative data (`profile.yaml`: detection, tools, checks, narrowing rules) in a real YAML
  subset the binary parses — the shell-era "flat scalars only" limit (ADR-0002) falls with the
  shell. `.ai/profiles/` stays in the project, `keep-modified` stays, ADR-0013's override
  contract survives. — rejected: profiles as Go code with `.ai/verify/<profile>.map` as the
  only customisation, because it withdraws a contract two ADRs call distributed for no gain
  the human wanted. **Cost accepted:** the profile format is a small language to design, and
  the two expressive profiles (`go`'s `go list .Deps` closure, `php`'s vendor paths) are the
  test of whether it is expressive enough — an open question below.
- **One record: the binary carries its skills and templates.** Skills, templates and the
  AGENTS.md marked section are embedded in the binary of the same version; `jig upgrade`
  raises the pin in `.ai/manifest` and re-places the files. The manifest keeps hashes only to
  recognise `keep-modified` placed files. A binary of one version with skills of another is
  impossible by construction. — rejected: a separate pin beside today's manifest with a
  precedence rule, because that divergence is the failure the hunt ranked first.

## Open questions

- **Parked, and why.** The human parked the spec at the end of the first session rather than
  commit to a roadmap: the hunt showed two of the four motivations weaker than stated
  (Git for Windows stays because git stays; the slowness is a tree-walk count, not the
  language) and the cost three times larger than assumed. **Prerequisite before this is
  reopened:** land the one-walk knowledge cache in bash (the `knowledge-costs-one-walk` task
  named in docs/known-issues.mdx) and measure `jig context` / `jig knowledge check` on Linux
  and on Windows with Defender on. Those numbers are the baseline the Phase 0 spike must
  beat; without them the next session cannot answer the go/no-go question.
- **The profile language.** What a declarative profile must express so that the 13 existing
  profiles port without loss — in particular `go`'s transitive-importer closure through
  `go list` and the per-check tool lookup of `php`/`laravel` — and where a profile is allowed
  to shell out to a project tool. Decides whether "profiles stay files" holds at all.

- **Go / no-go gate.** What number must the Phase 0 spike beat for the port to proceed —
  `jig context` and `jig knowledge check` wall time on Linux and on Windows with Defender
  on, against the bash baseline *after* the one-walk cache lands? The decision to spend the
  quarter depends on it; without a number the spike proves nothing.
- **Profiles: code or data?** Either profiles become declarative data a project can still
  override (a `profile.yaml` with checks, tools and narrowing rules the binary interprets;
  `.ai/profiles/` stays, `keep-modified` stays), or they are Go code with
  `.ai/verify/<profile>.map` as the only customisation and the override contract is
  withdrawn by ADR. Decides Phase sizing (13 profiles, 352 tests) and whether ADR-0013 and
  adr-20260918 survive.
- **One record or two?** Does the binary carry its own skills and templates and place them
  at run time, so the pinned version is the only record — or does `.ai/manifest` keep
  hashing placed files beside the pin, with a precedence rule? Decides what `jig upgrade`
  still does, how ADR-0017's `pending` is computed, and whether adr-20260930's "upgrade hands
  itself to newer code" has a meaning.
- **Signing.** Authenticode for Windows and notarisation for macOS, with the yearly cost and
  CI secrets they bring, or an unsigned binary and a documented SmartScreen click the
  audience ADR says they cannot make. Decides the installer design and a line in `doctor`.
- **The session hook on PowerShell-only Windows.** Claude Code runs hooks in PowerShell when
  Git Bash is absent; today the hook line is a bash script path and `status` detects it by
  substring. What is the hook command per shell, how does `status` detect it, and what does
  a project that already has the old line in `.claude/settings.json` (which Jig never edits,
  ADR-0024) see? Needs a PowerShell-only CI lane that does not exist.
- **Deletion audit.** Which syscall answers "is this a junction" on Windows in Go, and how is
  every enumerated deletion in RULES.md re-proven against it before any Go code deletes
  anything. A Phase 0 item, not a Phase N one.

## Assumptions left untested

- *A Go port of one command is a byte-for-byte message port.* Taken at deep; tested by the
  Phase 0 spike running the process-driving subset of the sh suite against the prototype.
- *The remaining per-process cost on Windows is large enough to matter once the one-walk
  cache lands.* Taken at deep; tested by the Phase 0 measurement with Defender on.
- *`git` through `os/exec` behaves the same as from bash for worktrees, `hash-object`,
  credential helpers and `gh`/`glab`.* Taken at deep; tested by the parity suite.
