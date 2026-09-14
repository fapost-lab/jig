---
id: adr-0033-release-tags-are-the-update-channel
type: adr
status: accepted
date: 2026-09-14
domains:
  - install
paths:
  - install.sh
  - scripts/lib/self-update.sh
  - scripts/lib/status.sh
  - scripts/lib/common.sh
summary: Why release tags, not main, are what installs and updates the global framework, and why moving it never changes a project.
reviewed_at: 2026-09-14
---
# ADR-0033: Release tags are the update channel; the installer and `self-update` move the global framework, and only `upgrade` moves a project

## Context

Jig was installed by hand: clone, symlink, a `PATH` line, all copied from README. Nothing
updated the checkout afterwards except `git pull` typed by the user, and nothing told a
project that the framework on `PATH` had moved on. `jig status` printed the version of the
executable it ran, never both sides.

Two facts shaped the answer. `main` changes with every pull request while `JIG_VERSION` stays
the same — it was `0.1.0` from the first commit — so a checkout that follows `main` can be
any number of commits ahead and still report the same version. And a project's framework is
committed with the project (ADR-0003): whatever updates the global copy must not reach into
projects.

## Decision

- **A release is an annotated tag `v<major>.<minor>.<patch>`, digits only, on a commit whose
  `JIG_VERSION` is the same version.** The newest release is chosen by comparing the three
  fields as numbers (`0.10.0` is newer than `0.9.0`), in shell arithmetic, because `sort -V`
  is not available everywhere. Any other tag — a pre-release suffix, a stray name — is not a
  release and is ignored. How tags are made belongs to the release process, not to this
  decision.
- **Release tags are the update channel; `main` is the development channel**, reached only by
  asking for it (`--ref main`).
- **The global framework is the `jig` that `PATH` selects**, resolved to the `scripts/jig` of a
  source checkout. There is no configuration naming it.
- **`install.sh`, at the repository root, is the per-user bootstrap.** It installs the newest
  release tag into `~/.local/share/jig` and links `~/.local/bin/jig`, with no `sudo`, and never
  runs `jig init`. With no release tag it fails and names `--ref main`; it does not fall back to
  `main`, which would change what the default means the day the first tag appears. Its whole
  body is functions, and the file ends in an `if` block, so a download cut short anywhere
  before the last line runs nothing.
  - On a repeat run it moves a clean checkout forward by the rule `self-update` uses, returns to
    the previous commit if the new tag's `jig version` disagrees with its name, and refuses an
    explicit `--ref` that does not name what the checkout already has out; an explicit tag is a
    pin and is not moved forward. It never overwrites, stashes, resets or deletes what it did
    not create.
  - On a failed run it removes only what that run created: the install directory it made with a
    plain `mkdir` (so nothing that appeared there meanwhile can be taken for its own) and the
    `jig` link it made. RULES.md names this as the second deletion outside `.ai/`.
  - When `~/.local/bin` is not already on `PATH` and the shell's startup file (`.zshrc`,
    `.bashrc`, else `.profile`) does not already mention it, it appends one marked `export PATH`
    line; `--no-path` skips this. That is not the edit ADR-0024 refuses: the file belongs to the
    user, not to a project, and the installer appends without parsing it.
- **`jig self-update` moves the global checkout, and nothing else.** Run from a project's
  installed copy, it hands over to the global executable. It refuses a checkout with any change,
  untracked files included whatever `status.showUntrackedFiles` says. At a release tag it fetches
  tags and moves to the newest release, never backwards, and if that tag's `jig version`
  disagrees with its name it returns to the commit it was on and fails. On a branch with an
  upstream it runs exactly `git pull --ff-only`. Anywhere else it refuses.
- **`jig status` compares the project's installed version with the global one** on one line,
  `framework versions: project=<p> global=<g> current|mismatch`, with a hint naming the
  direction, or `global=unavailable` and no hint. The global version is read from its checkout's
  `scripts/lib/version.sh`; `status` never runs the global executable.
- **A project moves only by `jig upgrade`.** The sequence is `self-update`, then
  `upgrade --dry-run`, `upgrade`, and a reviewed commit.

## Alternatives

- **`main` as the update channel, with tags only pinning the bootstrap URL.** Rejected: `status`
  would call a checkout any number of commits ahead `current`, and every unreleased change would
  reach users on their next update.
- **`git pull` inside `jig upgrade`.** Rejected: one command would mutate both the source and the
  project, and `--dry-run` could no longer promise to change nothing.
- **Warn about a newer framework before every command.** Rejected: repeated stderr noise, and a
  global lookup added to commands whose output other tools read.
- **`status` runs the global `jig version`.** Rejected after review: a broken or hanging global
  checkout would hang the command someone reaches for right after a failed update, and there is
  no portable timeout. A read-only command should not execute whatever `PATH` selects.
- **Fall back to `main` when no release tag exists.** Rejected: the default would silently
  change meaning when the first tag appears.
- **Install under `/usr/local/bin`.** Rejected: it needs `sudo` for a per-user tool.
- **Run `jig init` after installing.** Rejected: the directory someone happened to run the
  installer from is not consent to modify it.
- **Upgrade every known project after `self-update`.** Rejected: there is no registry of
  projects, and a project's framework update is a commit someone reviews.
- **Name the command `jig update`.** Rejected: too close to `upgrade`, which changes the project.

## Consequences

- Until the first release tag exists, the default install fails by design; the development
  channel works with `--ref main`.
- Tag and `JIG_VERSION` must agree, or the installer and `self-update` refuse the release. The
  release process has to guarantee it.
- A framework developer's global `jig` usually points at their working checkout, on a task
  branch with no upstream or with uncommitted work; `self-update` refuses there, and that
  checkout is updated with Git.
- `install.sh` cannot source `scripts/lib/common.sh` — it runs before a checkout exists — so it
  carries copies of the release-ordering helpers. Tests run the same cases against both.
- `status` now reads one file outside the project, in the global checkout. Its tests build a
  `PATH` without any real `jig`, so neither a maintainer's install nor its absence on a CI
  runner decides an assertion.
- A new command library is framework-owned: copy-mode projects report it as pending until
  `jig upgrade` (ADR-0017).

> **Amendment (2026-09-14).** "How tags are made belongs to the release process" is settled by
> ADR-0034: the `release` job in CI tags `v<JIG_VERSION>` after the tests pass on a merge that
> raises the version, and a tag name is always canonical — no leading zeros.
