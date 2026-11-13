---
id: adr-20261112-the-pr-review-skill-is-installed-per-user
type: adr
status: accepted
date: 2026-11-12
domains: []
paths:
  - scripts/lib/globalskill.sh
  - install.sh
  - install.ps1
  - scripts/lib/self-update.sh
  - "skills/jig-pr-review/**"
summary: Why jig-pr-review is linked (or copied with a marker) into ~/.claude/skills and ~/.agents/skills by the installer and self-update, never over the person's own, and finds its method through jig pr fetch.
reviewed_at: 2026-11-13
---
# jig-pr-review is installed for the person, beside every project's copy

## Context

Reviewing a colleague's pull request needs no project of one's own: `jig pr fetch` works in any
clone and drives the global `jig` on `PATH`, never the project's copy. The skill that drives it,
`jig-pr-review`, was only ever installed into a project (`jig init`, `jig upgrade`), so a person
reviewing a repository that has no Jig had to open a session in some Jig project and point it
elsewhere. It also reached two files outside itself by relative links (`../jig-review/SKILL.md`
for the review method, `../jig-task/references/show-the-document.md` for the showing rule), which
exist only beside a project's full set of skills.

Two accepted decisions stand in the way of anything outside the project. ADR-0024: the framework
never edits a runtime's configuration. ADR-0003: the framework is copied into the project, at the
project's version.

What the runtimes do, from their documentation: Claude Code reads personal skills from
`~/.claude/skills` and, when a personal and a project skill share a name, the personal one wins
(enterprise > personal > project). Codex reads user skills from `~/.agents/skills`; on a name
collision it does not merge the two, both may be offered, and which one is used is not documented.

## Decision

- **Where.** `jig-pr-review` alone goes to `~/.claude/skills/jig-pr-review` when `~/.claude`
  exists and to `~/.agents/skills/jig-pr-review` when `~/.codex` exists. A runtime the person does
  not have gets no directory made for it.
- **How.** A symbolic link to `<global checkout>/skills/jig-pr-review`, so `jig self-update` moves
  it along with nothing to copy. Where links cannot be made (Git Bash on Windows copies instead),
  a copy carrying a `.jig-global` marker file with its source and version.
- **Who.** `install.sh` (and so `install.ps1`, which runs it) places it last, after everything that
  can fail, and only for the default checkout that the `jig` link selects — a checkout installed
  elsewhere is not the one `jig self-update` keeps current; `jig self-update` places it after every run, with the code of the release it just
  checked out (`scripts/lib/globalskill.sh`). Only a path that is free, Jig's own link or Jig's
  marked copy is written. Anything else there — a directory without the marker, a link elsewhere —
  is the person's: one line says it was left alone, and nothing is changed. `install.ps1
  -Uninstall` removes Jig's link or marked copy and nothing else.
- **Removing it turns it off** (amended 2026-11-13, task pr-review-skill-opt-out). Each time
  Jig places or finds its own skill, it leaves a record beside it, `.jig-pr-review.placed` in the
  same skills directory. A free path with the record still there was emptied by the person: no
  later run puts the skill back, and one line says how to have it placed again — delete the record
  too. Each runtime's directory is its own choice. `install.ps1 -Uninstall` deletes the record of
  a path it left empty, so installing again places the skill.
- **No relative links.** `jig pr fetch` and `jig pr followup` print `method:` and `show:` with the
  paths of `jig-review/SKILL.md` and `show-the-document.md` in the framework that ran them; the
  skill reads those instead of `../…`. The method is then always the version of the mechanics.
- **Shadowing is accepted.** In Claude Code the personal copy runs in every project, including
  this repository while `skills/jig-pr-review/` is being changed. `jig status` prints
  `pr-review skill: personal <version> shadows this project's (<path>)` when Jig's personal copy
  differs from the project's.
- **ADR-0024.** A runtime's skills directory is not its configuration: nothing is parsed or
  edited, only a path of Jig's own name is created where none existed (the amendment of
  2026-09-10: creating a file that does not exist parses nothing).
- **ADR-0003.** This is the one framework file outside a project. Its version is the global Jig's,
  the same as the `jig` it drives; no project changes.

## Alternatives

- **Review from a Jig project as the hub**, as before: the problem this solves.
- **A separate install command** instead of the installer and `self-update`: a command one must
  know about in advance is one nobody runs.
- **An opt-out command** (`jig skills global off|on` with state under `~/.local/share/jig-state/`):
  deferred at first, then not taken when the opt-out was asked for (2026-11-13). Deleting the skill
  is what a person tries first; a record beside it makes that act the switch, with no command to
  learn and no new place for state.
- **Installing `jig-review` and `jig-task` globally too**, so the relative links resolve: they are
  project skills and would mislead outside one.
- **Copying the method into `jig-pr-review`**: two sources of one method drift apart.
- **Always a copy, Unix included**: a link costs nothing to keep current and leaves no stale copy.

## Consequences

- A person with Jig installed can review any repository's pull request from any directory.
- In Codex, an older project copy may win over a newer personal one. That is safe: it calls the
  global `jig pr`, whose draft format version 1 stays backward compatible, and it does not read
  `method:` or `show:`. Listed in `docs/known-issues.mdx`.
- On macOS and Linux there is no uninstaller; the link is removed by hand with the checkout.
- Every change to `jig-pr-review` must keep it self-contained: no link outside its own directory.
- RULES.md's deletion invariant names this as one more exception: only Jig's marked copy, after a
  fresh one replaced it, and temporary paths of its own; never a link.
- A skill removed by hand stays removed, and Jig never deletes its record in `self-update` or the
  installer; a person who wants the skill back deletes the record, as the line Jig prints says.
