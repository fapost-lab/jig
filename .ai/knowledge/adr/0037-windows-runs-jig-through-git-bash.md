---
id: adr-0037-windows-runs-jig-through-git-bash
type: adr
status: accepted
date: 2026-09-16
domains:
  - install
  - task
  - housekeeping
paths:
  - install.ps1
  - scripts/jig.cmd
  - scripts/lib/doctor.sh
  - templates/gitattributes
  - .github/WINDOWS_RELEASE_CHECKLIST.md
summary: Why Windows support is Git Bash plus a PowerShell bootstrapper, with junctions where symlinks cannot be made, instead of a port.
reviewed_at: 2026-09-16
---
# ADR-0037: Windows runs jig through Git Bash, bootstrapped by install.ps1

## Context

Jig is meant for people who build with coding agents without being developers, and most of
them use Windows. Until now jig said "macOS and Linux": the installer is a `curl | bash` line,
the global `jig` is a symlink, a task worktree borrows its workspace through a symlink, and
every script is bash.

A `windows-latest` CI probe on 2026-09-14 ran the suite in Git Bash: 83 failures. Grouped, a
third came from the language — two spellings of one path (`git.exe` prints `C:/…`, bash
`/c/…`) and a lost executable bit — and the rest from the filesystem: `ln -s` in Git Bash
copies instead of linking unless Developer Mode is on, `chmod` does not make a directory
read-only, a tab cannot be part of a file name. One failure was a real bug on every Windows
machine: `upgrade` fed absolute paths to `git hash-object --stdin-paths`, which MSYS never
converts, so native git could not find them.

The audience also rules out any manual step: no "install Git first", no editing `PATH`, no
Developer Mode, and administrator rights only where nothing else works.

## Decision

- **Git Bash is the Windows platform, and jig's logic stays one bash implementation.** Git
  is mandatory anyway (ADR-0002), and on Windows git for people is Git for Windows, which
  carries bash. Code that differs by platform asks what the machine can do, never which OS it
  is.
- **`install.ps1` is the Windows entry point**, run as
  `irm https://raw.githubusercontent.com/fapost-lab/jig/main/install.ps1 | iex`. It finds Git
  for Windows (`PATH`, then the `GitForWindows` registry key) or installs it — winget, else the
  official installer with one UAC prompt, else a per-user install — takes bash from
  `git --exec-path` rather than `PATH` (where `bash.exe` can be WSL's launcher), runs
  `install.sh --no-path`, and adds the checkout's `scripts\` to the user `PATH`. With consent
  it prepares a first project: `git init`, a git identity only where none is set,
  `jig init --session-hook`, and a first commit only in a repository it created in that run,
  with the executable bit set in the index. It ends with `jig doctor` and one sentence to say
  to the agent. It runs on Windows PowerShell 5.1, and logs to `%LOCALAPPDATA%\jig\install.log`.
  `-Uninstall` removes the `PATH` entries, the `jig` link it can prove points into the
  checkout, and the checkout only when it is a jig source tree with a clean `git status`.
- **A directory link is a symlink where one can be made, else an NTFS junction, else
  nothing.** `jig_link_detect` probes once per run in a temporary directory; `jig_link_dir`
  makes the link. Bash sees a junction as a link (`-L`, `find -type l`, `cd -P`), and removing
  it never touches its target, so ADR-0029's checks hold unchanged. `task start --worktree`
  refuses before `git worktree add` when neither kind can be made. Link mode (`init --link`,
  its `upgrade`) needs real symlinks and refuses before its first write: a junction has no
  relative target and git does not store it.
- **Without symlinks the global `jig` is the checkout's `scripts/jig` on `PATH`**, not a link in
  `~/.local/bin`. `install.sh` puts `scripts/` on `PATH` (or, with `--no-path`, says to).
  `jig_global_executable` already accepts that path.
- **`jig.cmd` calls jig from PowerShell**, for a runtime such as native Codex that cannot run an
  extensionless shebang script. It sits next to `scripts/jig` and `.ai/scripts/jig`, finds bash
  through `git --exec-path`, passes arguments and the exit code through, and loses inner double
  quotes — cmd.exe's quoting. It is LF like every framework file: `upgrade` hashes a staged
  source file as raw bytes but the installed copy through the project's `.gitattributes`, so a
  CRLF source would read as changed forever and `jig verify` would refuse (ADR-0017).
- **Line endings and the executable bit do not depend on the machine.** `jig init` merges
  `templates/gitattributes` into the project's `.gitattributes` line by line, forcing LF on
  `.ai/scripts/**` and profile scripts. Framework scripts are run as `bash <file>` — profiles by
  `verify`, the dispatcher by the session hook — so a checkout that lost `+x` still works.
- **`jig doctor` answers "does jig work on this machine"**: git, identity, the global `jig`,
  the directory-link kind, versions, the pending upgrade, executable bits in the index,
  `jig.cmd`, the session hook — one line per check, a `fix:` line under each warning or
  failure, exit 1 on any failure. It is a reporting command: it calls other libraries and
  writes nothing. `status` does not grow these checks.
- **The worktree directory git leaves behind is cleared of links only.** On Windows
  `git worktree remove` can succeed and leave the directory with its `.ai/` links in it.
  Housekeeping then removes links and, deepest first, empty directories with `rmdir`, inside
  the path it already validated; anything else stays, and the task is reported
  `worktree-kept` with reason `leftover`.
- **CI proves it.** Pull requests run `smoke-windows`: `tests/install.t.ps1` against a local
  fixture remote, then the everyday commands in Git Bash — including a worktree started,
  merged, closed and removed through a junction — and `jig.cmd` from PowerShell. The full suite
  runs on Windows for `main` and manual runs, and `release` waits for both. Tests skip by
  capability (`skip_unless_symlinks`, `skip_unless_readonly_dirs`, …), with a reason, never
  by OS name. What CI cannot show — a clean machine without Git, a user without administrator
  rights, the Claude Code hook — is `.github/WINDOWS_RELEASE_CHECKLIST.md`, run by a maintainer
  before a release that changes installation on Windows.

## Alternatives

- **Port jig to PowerShell.** Rejected: ~9k lines of scripts and ~13k of tests rewritten,
  PowerShell 5.1 and 7 differ, and `pwsh` is absent on macOS and Linux — two implementations or
  none portable. A PowerShell copy beside bash was rejected for the same drift ADR-0002 avoids.
- **Node/TypeScript or a compiled binary.** Rejected: Node is not on a non-developer's Windows
  machine, a binary is opaque to the agents that read jig, and neither removes the symlink or
  NTFS failures, which were two thirds of the probe.
- **Ask the user to install Git first.** Rejected: it is exactly the manual step this audience
  cannot take.
- **PortableGit inside jig's directory.** No rights needed, but Claude Code would not find its
  bash without a setting in the user's runtime configuration, which jig does not edit (ADR-0024).
- **Turn on Developer Mode for symlinks.** Rejected: it needs administrator rights, and junctions
  cover the worktree link without any.
- **A pointer file, or a copy, instead of the workspace link.** A pointer rewrites everything that
  reads a workspace; a copy gives a task two `state` files (ADR-0029).
- **`jig.ps1` instead of `jig.cmd`.** Rejected: client Windows defaults to the `Restricted`
  execution policy, the script would not run, and PowerShell would not fall back to `.cmd`. For
  the same reason the installer is piped into `iex`, not downloaded and run as a file.
- **Environment checks inside `status`.** Rejected: `status` answers "what is happening with the
  tasks", runs at every session start, and would get slower for a question asked once.
- **Pester for `install.ps1` tests.** Rejected: a dependency for one file; the tests are plain
  PowerShell with an exit code.

## Consequences

- Windows is supported for copy-mode projects. Developing jig itself on Windows (link mode)
  still needs Developer Mode.
- PowerShell exists in the repository in exactly two files, `install.ps1` and
  `tests/install.t.ps1`, and one batch file, `jig.cmd` (ADR-0002 as amended). Every behaviour
  change stays one bash change.
- Anything that makes a directory link goes through `jig_link_dir`, and anything that hands a
  path to native git passes it as an argument or relative to a directory it `cd`s into
  (conventions/shell.md). A bare `ln -s` is silently a copy on Windows.
- Housekeeping has one more deletion outside `.ai/`: links and empty directories in a worktree
  directory git has just removed (RULES.md). `install.ps1 -Uninstall` is another, bounded the same
  way `install.sh` is (ADR-0033 as amended).
- A pull request costs a Windows smoke job (~2 minutes). The full Windows suite takes ~30 minutes
  against 1–5 on Linux and macOS, so it runs outside pull requests.
- 40 tests skip on `windows-latest`, each for a named missing capability — most because link
  mode needs symlinks. A skip is not a pass (ADR-0013): link mode on Windows is untested because
  it is unsupported there.
- A task worktree removed on Windows can report `leftover` if something other than links remains;
  it stays for a human, like every other `worktree-kept`.
- Installing Git without administrator rights (`/CURRENTUSER`) and the Claude Code hook on
  Windows are verified only by the release checklist.
