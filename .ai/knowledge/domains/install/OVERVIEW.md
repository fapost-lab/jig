---
id: domain-install
type: domain
status: active
summary: "Installing and upgrading the framework: the framework-owned split, copy and link modes, the adapter contract."
domains:
  - install
topics: []
load: domain
paths:
  - scripts/lib/init.sh
  - scripts/lib/upgrade.sh
  - scripts/lib/manifest.sh
  - "adapters/**"
  - install.sh
  - scripts/lib/self-update.sh
  - .github/scripts/release-tag.sh
  - install.ps1
  - scripts/lib/doctor.sh
  - scripts/jig.cmd
  - templates/gitattributes
  - scripts/lib/section.sh
reviewed_at: 2026-09-25
---
# Install

Getting the framework into a project, keeping it current, and never destroying what the
project owns.

## Responsibility

- The framework-owned / project-owned split: `.ai/scripts/`, `.ai/profiles/`,
  `.ai/templates/knowledge/`, `.ai/templates/scheduler/`, `.ai/templates/spec/`,
  `.ai/templates/AGENTS.md` and the
  installed skills are carried forward by upgrade; `.ai/knowledge/`, `.ai/specs/`,
  `.ai/verify/`, `.ai/config.yaml` and `AGENTS.md` are never touched (ADR-0003,
  ADR-0011, ADR-0041) — with the single exception of `AGENTS.md`'s marked section, below. `init` does not create `.ai/verify/` either: a project that wants a
  map writes it. A first `init` without `--profiles` and without `.ai/config.yaml` writes
  the detected profiles into the config it creates; with `--profiles`, or when the config
  exists, detection only suggests (adr-20260918-init-activates-detected-profiles). Neither is `.ai/config.local.yaml`, which is not the project's either: it
  belongs to the clone's owner and is never created by `init` — only by hand or by
  `jig config set --local` at the owner's request (ADR-0038). `init` does write
  its line into `.gitignore`, through the same append-missing-lines merge as every other
  `templates/gitignore` line; `upgrade` never touches `.gitignore`, so an older project
  gets the line only from a repeated `init`, and `status`/`doctor` warn until it has it.
- A project's own `AGENTS.md` or `CLAUDE.md` is kept by `init`, and then no agent there is
  told about Jig. `init` warns, `status` and `doctor` keep reporting it, from each adapter's
  `adapter_<name>_instructions_hint`; the text to merge is
  the marked region of `templates/AGENTS.md`, installed as the framework-owned
  `.ai/templates/AGENTS.md` so a project with no framework checkout has it. That template
  is the single source of the section; `docs/install.mdx` carries the only other copy, for
  pasting by hand, and a test holds the two equal — markers included, because a section
  pasted without them is a section nothing updates.
- **The marked section is the one part of a project-owned file that upgrade writes.**
  Between `<!-- jig:begin -->` and `<!-- jig:end -->` in `AGENTS.md`, `jig upgrade` applies
  the same table it applies to a file: `replace` when the region still hashes to what the
  manifest header records under `instructions.section: <hash> <path>`, `keep-modified` when
  it does not or when the markers were removed, `keep-malformed` when the pair cannot be
  read unambiguously, `keep-unmarked` when there is nothing of jig's there, and
  `keep-conflict` when markers exist that jig has no record of writing. Upgrade never
  adopts a section: only `jig init` records one, and only when the region is byte for
  byte the marked region of the source's own `templates/AGENTS.md` — claiming an identical
  region destroys nothing, while somebody's own words between markers are never taken. An
  existing record is carried forward, never re-derived, so a re-run of `init` cannot
  re-baseline a section a human edited. `replace AGENTS.md (Jig section)` is inside
  `upgrade_pending`'s filter, so a stale section is pending work like any other path;
  `keep-unmarked` is deliberately outside it, so a project that keeps its own instructions
  is never blocked from verifying by that choice. The parser is `scripts/lib/section.sh`
  (`jig_section_*`): it compares and hashes the region normalised to LF and writes it back
  in the file's own line endings, so a CRLF checkout neither reads as modified nor ends up
  with mixed endings (ADR-0037,
  adr-20260924-jig-owns-a-marked-section-of-the-instructions).
- Two install modes: `copy` (files copied and hashed in `.ai/manifest`) and `link`
  (relative symlinks into a source checkout, used when developing the framework itself).
- The upgrade decision table: install, replace, keep-modified, delete — decided per path
  from the manifest hash, the on-disk file and the staged source. A file is placed by
  copying it beside its destination and renaming over it, never by writing onto the
  destination: one of the files an upgrade replaces is `.ai/scripts/jig`, the script the
  shell is running at that moment, and a shell reads its script from an open descriptor as
  it goes — rewriting that file in place makes it read the new bytes at the offset it had
  reached. Every run ends in one summary line (`N placed, M kept, K conflict(s); manifest
  updated|unchanged`), and an upgrade that applied nothing leaves `.ai/manifest` untouched
  instead of repointing `jig.source`/`jig.version` at the checkout it was offered
  (adr-20260922-upgrade-records-the-source-it-installed-from). The source already recorded
  is the exception, written back whether or not anything was placed: in link mode the
  project runs that checkout's scripts, so its version moves with it.
- The adapter contract: where each runtime's skills live and how a skill is transformed
  on the way in.
- The global framework: `install.sh` bootstraps a per-user checkout at the newest release
  tag, `jig self-update` moves it forward, and `jig status` compares the version it declares
  with the project's installed one. Release tags are the update channel and `main` the
  development channel (ADR-0033). Moving the global framework never changes a project; only
  `upgrade` does.
- Windows (ADR-0037): `install.ps1` brings Git for Windows, runs `install.sh --no-path`, puts
  the checkout's `scripts\` on the user `PATH` and, with consent, prepares a first project.
  Where symlinks cannot be made, `install.sh` links nothing into `~/.local/bin` and `scripts/`
  goes on `PATH`; `init --link` and link-mode `upgrade` refuse before their first write.
  `scripts/jig.cmd` is framework-owned like `scripts/jig`, and `jig init` merges
  `templates/gitattributes` into the project's `.gitattributes`.
  Whatever the installer does on the user's behalf it says before doing it: that winget accepts
  its source and package agreements, that the Git identity it sets is global, and, before the
  "set up jig" question, that `init --session-hook` creates `.claude/settings.json` whose hook
  runs housekeeping (which moves and later deletes workspaces) at each session start;
  `-NoSessionHook` leaves the hook out. The Git installer the no-winget path downloads is not
  checked against a hash or signature — a known gap, not a guarantee.
- `jig doctor`: whether jig works on this machine and in this project, one line and a `fix:`
  per check. A reporting command — it calls `status`, `upgrade` and `common.sh` functions and
  writes nothing.
- Releases: a merge into `main` that raises `JIG_VERSION` is tagged `v<JIG_VERSION>` by the
  `release` job in CI once the tests pass; `.github/scripts/release-tag.sh` decides (ADR-0034).
  Raise the version in the pull request that should become the release, in
  `scripts/lib/version.sh` only, as `major.minor.patch` without leading zeros: patch for a fix,
  minor for a new capability, major for a change that breaks commands, the `.ai/` layout, the
  `init`/`upgrade` contract or the installer — minor instead while below `1.0.0`. A version never
  goes back.

### The project's config file is documentation, and jig never edits it

`.ai/config.yaml` is the team's: committed, reviewed like code, written by nobody but a person
(ADR-0024). An absent key takes its default, so a file a version behind still works — and that
is the trap, because the file is also the only place anyone ever sees *which* keys exist. After
`jig upgrade` it goes on describing the version it was written for, and a capability the new
version brought is one nobody was offered.

The answer is a report, never a write. `jig_config_keys` (`scripts/lib/config.sh`) is the one
list of `<key> <default>` this framework reads; `jig_config_unmentioned` and
`jig_config_unknown` compare a project's file against it, and where that is said was decided,
not defaulted:

- `jig upgrade` prints one line at the end of a real run. That is the moment the two part
  company, and it is said once.
- `jig doctor` repeats it on demand, and `jig config keys` prints the whole inventory. Doctor
  already reported the mirror case — a local-only key written into the project file, where
  nothing reads it — and both halves of one question belong in one command.
- `jig status` does not. An unmentioned key is something to look at, not something a task is
  waiting on, and a line printed at every session start stops being read.

Two rules keep the report from crying wolf. A commented line counts as a mention, because the
file documents as much as it configures and the template ships keys exactly that way — read
strictly, a project would be told on its first day that it is missing three of them. And
`JIG_CFG_LOCAL_ONLY_KEYS` is left out entirely: `cfg` never reads the project layer for those,
so naming one would ask a person to write a line that does nothing.

The inventory is written by hand, which is the part that would rot. `tests/config.t.sh` is what
stops it: it greps every `cfg`, `cfg_bool`, `cfg_list` and `cfg_list_lines` call out of
`scripts/` and refuses to pass unless the call sites, the inventory, `schemas/config.md`,
`templates/config.yaml` and `docs/configuration.mdx` agree on one set of keys and one set of
defaults. A key is added in all five places, or the suite names the one that was forgotten.

## Boundaries

Outside: what a skill or profile *says*. Adapters contain no SDLC logic; the only
transform today is Codex's invocation syntax (`/jig-x` → `$jig-x`).

The installer and `self-update` only read release tags. Only the CI `release` job creates them,
and it never tags a version its commit does not declare (ADR-0034). The release script lives under
`.github/` so that `init`, which copies `scripts/`, never installs it into a project.

Outside: running checks (domain `verify`). This domain installs `profiles/`; it does not
know what a profile does.

Adapters touch runtime layers only. An adapter that started making SDLC decisions would
put vendor-specific behaviour underneath vendor-neutral skills, which is the inversion
`ARCHITECTURE.md` forbids.

## Entry points

- `scripts/lib/init.sh` — `cmd_init`, `_init_place_symlink`, `_init_copy_framework_file`.
- `scripts/lib/upgrade.sh` — `cmd_upgrade`, `_upgrade_build_staged`,
  `_upgrade_process_path`, `_upgrade_section`, `_upgrade_link`.
- `scripts/lib/manifest.sh` — the manifest reader and writer;
  `manifest_instructions_section` reads the marked section's record.
- `scripts/lib/section.sh` — `jig_section_state|read|hash|report_state|write`.
- `adapters/<runtime>/adapter.sh` — the three functions each adapter must define.
- `install.sh` — the per-user bootstrap; cannot source libraries, so it carries copies of the
  release-ordering helpers.
- `install.ps1` — `Install-Jig`, `Initialize-JigProject`, `Uninstall-JigFramework`; tested by
  `tests/install.t.ps1`, which runs only on Windows CI.
- `scripts/lib/doctor.sh` — `cmd_doctor`, one `_doctor_check_*` per line of its report.
- `scripts/jig.cmd` — the PowerShell entry; `.github/WINDOWS_RELEASE_CHECKLIST.md` — what CI cannot
  check before a release that changes installation on Windows.
- `scripts/lib/self-update.sh` — `cmd_self_update`.
- `scripts/lib/common.sh` — `jig_release_version`, `jig_version_newer`, `jig_newest_release`,
  `jig_global_executable`, `jig_declared_version`, `jig_version_of`.
- `.github/scripts/release-tag.sh` — whether to tag a release; run by the `release` job of
  `.github/workflows/ci.yml`.
