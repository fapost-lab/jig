# Windows release checklist

Run before tagging a release that changes how Jig is installed or run on Windows
(`install.ps1`, `install.sh`, `scripts/jig.cmd`, directory links, `jig doctor`).

CI runs on `windows-latest`, which is an administrator with Git already installed. It
cannot show what a first-time user sees, so this list is walked by a person on a clean
machine. Record the result in the release pull request: date, Windows version, and every
item that did not pass.

## Machine

- A clean Windows 11 virtual machine, restored from a snapshot for each run.
- Claude Code installed from its official installer. Git for Windows **not** installed.
- Two accounts: a standard user without administrator rights, and an administrator.
  Run the list once for each.

## Install

1. Open Windows PowerShell 5.1 (not PowerShell 7) and paste the one line from README.
2. Git for Windows gets installed. As the standard user, note whether Windows asked for
   an administrator password, and whether the installer then continued without rights.
3. The installer asks at most four questions: project folder, make it a git repository,
   name and e-mail for git, set up jig. Note the time from paste to the last answer,
   download time excluded.
4. `jig doctor` output ends with `0 fail`. Note every `warn`.
5. The closing line tells you what to say to the agent.

## First session

6. Open the project folder in Claude Code. Say the phrase from step 5. The agent runs
   `jig task …` commands and they succeed.
7. After the session starts, `.ai/runtime/last-housekeeping` exists: the session hook ran.
8. In the project, `git log --stat` shows one first commit; `git ls-files -s .ai/scripts/jig`
   shows mode `100755`.

## Codex

9. In native Codex (PowerShell), ask the agent to run `.ai/scripts/jig status`. It
   succeeds through `jig.cmd`.

## Parallel work

10. `jig task new demo` and `jig task start demo --worktree` succeed; `jig doctor` reports
    directory links as `junction`.
11. Commit something on the task branch, merge it into `main`, close the task
    (`jig task set demo knowledge_consolidated true`, then `status consolidated`), run
    `jig housekeeping`. The worktree directory is gone, and the project's
    `.ai/workspace/` still holds every other task.

## Repeat and remove

12. Paste the install line again: nothing is reinstalled, no second PATH entry, no new commit.
13. `install.ps1 -Uninstall`: the jig PATH entry and `%USERPROFILE%\.local\share\jig` are
    gone; Git for Windows is still installed.
