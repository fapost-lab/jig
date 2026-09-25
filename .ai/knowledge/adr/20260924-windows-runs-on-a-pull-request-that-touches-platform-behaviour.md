---
id: adr-20260924-windows-runs-on-a-pull-request-that-touches-platform-behaviour
type: adr
status: accepted
date: 2026-09-24
domains:
  - verify
paths:
  - .github/workflows/ci.yml
  - .github/scripts/ci-windows-scope.sh
  - tests/ci-windows-scope.t.sh
summary: "Why the full Windows suite runs on a pull request whose diff touches line endings, MSYS paths, directory links, a Windows-only file or a CI workflow, and passes over the rest: the signal, the numbers behind it, and why it matches no literal carriage return."
reviewed_at: 2026-09-25
---
# Windows runs on a pull request whose diff touches platform behaviour

## Context

ADR-0037 put the full Windows suite outside pull requests: three shards are about 25
minutes, the runners are slow, and every change would pay — including the prose changes
that are a fifth of this repository's pull requests. A `smoke-windows` job covered pull
requests instead, and the full suite ran on `main`, nightly, and by hand.

On 2026-09-24 that cost a red `main`. Pull request #93 taught `jig_section_write` to keep a
file's own line endings, and §9 of its design said so in as many words — a Windows checkout
has `core.autocrlf=true`. Nothing ran that on Windows. The pull request merged green, `main`
went red, and the fix (#96) found two defects, not one: under Git Bash `grep`, `sed` and
`awk` drop the CR before the regular expression sees it, so the code rewrote every
`AGENTS.md` from CRLF to LF and the test that was supposed to catch it asserted zero on any
file. Review could not have caught this. It read the code; the answer needed the code run on
Windows.

Running Windows on every pull request fixes it and costs the 25 minutes ADR-0037 declined to
spend. The question is whether a cheaper signal exists: one that catches a change like #93
and passes over a change that cannot behave differently on Windows.

It does. Measured over the 99 pull requests merged before this decision — every merged pull
request numbered below #101 — by rebuilding each one's diff the way CI sees it, from the
`main` tip the merge commit sat on to the merge commit, and running today's `ci-scope.sh`
and `ci-windows-scope.sh` over it: 77 run the full suite today, and the signal below selects
22 — 22% of all pull requests, 29% of the ones that would otherwise pay. #93 is among them.
Rebuilding the branch's own diff instead, from the merge base to the branch head, gives the
same 77 and the same 22, so the numbers do not rest on which of the two a reader picks.

The measurement also ruled things out. A signal built from the obvious candidates —
`mv`/`rm`/`cp` on paths, `symlink` anywhere, `chmod`, drive letters and path separators —
selects 47 of 99, half the history, which buys nothing. It was broad for reasons worth
recording: `s:/` inside a `sed` expression reads as a drive letter, `symlink` and `chmod`
appear throughout a repository whose own install mode is symlinks, and the Windows shards
already skip the tests those two guard by capability (`skip_unless_symlinks`,
`skip_unless_readonly_dirs`). There was a signal with no check standing behind it.

## Decision

- **A pull request runs the Windows shards when its diff touches platform behaviour**, and
  `smoke-windows` keeps running on every pull request as before. `main`, the nightly run and
  a manual dispatch are unchanged: they run Windows whatever changed.
- **The signal is the Windows failure classes ADR-0037 named**, not a guess at fragility.
  Content rules, matched case-insensitively against the added and removed lines of a diff:
  line endings (`\r`, `\015`, `crlf`, `autocrlf`, `eol=`, `text=auto`); MSYS path
  translation (`cygpath`, `MSYS`, `exec-path`); directory links (`junction`, `jig_link_`);
  and the platform named outright (`windows`, `git bash`, `powershell`, `ADR-0037`, `NTFS`).
  Path rules, matched against any changed path: `.github/workflows/**`, `*.ps1`, `jig.cmd`,
  `*gitattributes`. Only the workflows: a workflow decides which platforms run at all, while
  a script under `.github/` that CI executes on `ubuntu-latest` alone — the release tag, the
  epic gate, the changelog gate — is ordinary code and is read by the content rules like any
  other.
- **A change that names Windows runs on Windows.** It is the loosest rule and the one that
  matters most: #93's author was reasoning about this platform in writing, and nothing was
  running that reasoning. It is also nearly free — dropping it selects 20 instead of 22.
- **Prose is Markdown that is not a template.** A template is checked first and is never
  prose: `templates/AGENTS.md` is a shipped file whose line endings reach a user's project,
  and it happens to be Markdown — it is the file #93 was about. Everything else that is
  Markdown is prose wherever it sits, knowledge, specs, schemas, skills, the docs site and a
  checklist under `.github/` alike, because a person is its only reader. Four variants of
  this filter were measured; all four select the same 22, so the one that leaves no hole was
  taken.
- **The rules are plain ASCII, and a literal carriage return is deliberately not matched.**
  MSYS `grep`, `sed` and `awk` drop CR before the pattern sees it — half of what #96 had to
  undo — so a rule matching one would answer differently depending on where it ran. A
  decision about platform-dependence must not itself be platform-dependent. It costs
  nothing: matching a literal CR as well selects the same 22.
- **A miss costs a red `main`, not a released defect.** `main` and the nightly run still
  execute the full Windows suite, and `release` still waits for every shard. This is a
  narrowing of when the net is raised earlier, never a removal of the net that existed.
- **Unmeasurable is `windows`**, the way an unmeasurable scope is `full` (ADR-0041): no base,
  a base of zeros, a base absent from the history, a failing diff, an empty change.
- **The decision lives in `.github/scripts/ci-windows-scope.sh`, which has tests**
  (`tests/ci-windows-scope.t.sh`); the `scope` job runs it and publishes one output,
  `windows`, and `test-windows` reads `full` and `windows` and nothing else. The event check
  that used to sit on the job moves into `scope`, so there is one place that decides.

## Alternatives

- **Run the Windows shards on every pull request.** The honest fix, and the one ADR-0037
  already weighed and declined. It spends 25 minutes on the 77 of 99 pull requests the
  signal passes over.
- **Leave it as it was and rely on `main`.** This is what produced the red `main` — twice,
  because the next merge inherited the defect and its own run failed on it.
- **Decide by paths alone** (`scripts/lib/**`, `.github/`, `install.ps1`). Cheaper to read
  and impossible to fool, but `scripts/lib/**` alone appears in 60 of 99 pull requests. A
  path signal coarse enough to catch #93 catches most of the history with it.
- **Decide by the broad content candidates** — file moves, `symlink`, `chmod`, path
  separators. 47 of 99, and for the reasons in Context most of those matches stand in front
  of tests that skip on Windows anyway.
- **Extend `ci-scope.sh` with a second output.** One diff, one map parse, one classification.
  Rejected on two counts: the script's shape is a walk that exits at the first path forcing
  `full`, and a second dimension means removing the early exit and rewriting its tests; and
  the verify map answers "which tests does this path affect", which is not "is this prose" —
  a path a project maps `-` is still code that ships.
- **Match a literal carriage return in the diff.** Precise in principle, platform-dependent
  in practice, and worth nothing measured. See Decision.
- **Let the author opt in with a label or a commit trailer.** It is the discipline this
  framework exists to remove: #93's author documented the Windows behaviour in the design and
  still would have had to remember to add the label.

## Consequences

- A pull request that touches line endings, path translation, directory links, a
  Windows-only file or a CI workflow costs about 25 minutes more and answers before the merge
  rather than after it. Measured on history, that is 22 of 99.
- The Windows failure classes are now written down in two places that must agree: this ADR
  and the script's header. A new class found on Windows is a new rule in the script, a test
  beside it, and a line here.
- A change to a workflow always runs Windows, so what decides which platforms run is checked
  on them — including the pull request that introduced this decision. The rest of `.github/`
  buys nothing on its own, which is the point: on this history every pull request that
  touched a gate script touched `ci.yml` with it, so the narrowing changed no verdict, only
  the reason the script gives for one.
- ADR-0037's consequence "the full Windows suite ... runs outside pull requests" is narrowed
  by this decision. `smoke-windows` on every pull request, the nightly run and the release
  waiting for every shard all stand unchanged.
- The signal can be fooled by a change that behaves differently on Windows without saying so
  in any of these words. That is the accepted residual risk, and `main` is where it surfaces,
  exactly as before this decision.

> **Amendment (2026-09-25).** The measurement above, 22 of 99, read the diffs from the merge
> commits of `main`, which cannot see a pull request that landed through an epic branch — #60
> to #85 did. Remeasured over the 105 merged pull requests below #107, enumerated with
> `gh pr list --state merged` and each diff rebuilt as merge-base(base, head) to head: the
> signal as this ADR accepted it matches 24, and with the rules the amendments below add, 30.
> `ci.yml` runs the shards only where `ci-scope.sh` also says `full`, and all 30 are `full`,
> so the signal never makes a cheap pull request expensive. The cost per pull request is no
> longer the 25 minutes above: the suite moved to six shares and ~15 minutes
> (adr-20260925-windows-runs-in-six-shares).

> **Amendment (2026-09-25).** The residual risk above — a change that depends on the platform
> by idiom rather than by word — is narrowed, and the rule for when an idiom counts is that
> **the idiom's own reason must be platform-dependent**. `conventions/shell.md` is the
> discriminator, because its rationale column already says why each construct is there. Two
> classes follow from it. First, POSIX file semantics the author names — `inode`, `hard link`,
> and the `stat -c`/`stat -f` dialect split: this is the "names the platform" rule read from
> the other side, since an author writing `inode` is reasoning about file identity Windows
> does not give. It is what #88 turned on, which replaced `cp` onto a destination with a
> rename because `cp` keeps the inode of the script bash is executing. Second, `ln -s` in code
> that ships, outside `tests/`: the convention forbids it because in Git Bash it copies and
> still exits 0, so an install or a worktree silently gets a second copy. A symlink a *test*
> plants is not a signal — such a test leaves through `skip_unless_symlinks` and skips on
> Windows, which is the argument the Alternatives above already used. What the signal is for
> is a change whose **correctness** depends on POSIX semantics, not every use of `mv`.

> **Amendment (2026-09-25).** The price of that rule, named, because it is bought and not
> overlooked: seven pull requests stay uncaught. #10, #20, #21, #61, #62, #65 and #66 write a
> workspace or knowledge file through `file.tmp.$$` and a rename, and the signal passes over
> all seven. `conventions/shell.md` asks for that idiom so a crash mid-write cannot leave half
> a file — a reason that is not a platform — so the idiom is not a signal. Measured over the
> same 105: a rule on it would raise 9 pull requests these rules do not, and only #88 among
> them is platform-dependent, where the *destination* makes it so, a file bash is executing,
> which #88 states in the word `inode`. #88 and #17 are already caught for their own reason,
> so the rule would catch nothing new at all and spend seven false runs of ~15 minutes.
> Nothing for something is not a trade. A rule on a bare `mv` is worse: 53 of 105, the union
> the Alternatives above rejected. `test_ci_windows_scope_atomic_write_idiom_is_skipped`
> asserts the silence, so this stays a decision rather than drifting into a defect someone
> repairs. **Revisit it when `main` goes red on Windows because of a rename over a destination
> in code that named none of these words** — that is the evidence this decision lacks today.
> The fix then is a rule about the destination, an installed or executing file, not about the
> idiom: the idiom is what made the measurement come out at nothing for seven.

> **Amendment (2026-09-25).** One `skip` the script gave was not a residual risk but a
> fail-open: it answered about a file it had not managed to look at. With git's default
> `core.quotePath`, `git diff --name-only` prints a path holding a byte above 0x7F wrapped in
> double quotes with each such byte octal-escaped. No path rule matches that string and
> `git diff -- "$string"` selects nothing, so the file passed with its content never read. The
> file list is now read with `-c core.quotePath=false`, and a test plants a non-ASCII name.
> A path holding a double quote or a newline is still quoted whatever that setting says;
> closing that too means reading the list NUL-separated.
