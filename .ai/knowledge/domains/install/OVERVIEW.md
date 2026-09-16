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
reviewed_at: 2026-09-16
---
# Install

Getting the framework into a project, keeping it current, and never destroying what the
project owns.

## Responsibility

- The framework-owned / project-owned split: `.ai/scripts/`, `.ai/profiles/`,
  `.ai/templates/knowledge/`, `.ai/templates/scheduler/`, `.ai/templates/spec/` and the
  installed skills are carried forward by upgrade; `.ai/knowledge/`, `.ai/specs/`,
  `.ai/config.yaml` and `AGENTS.md` are never touched (ADR-0003,
  ADR-0011).
- Two install modes: `copy` (files copied and hashed in `.ai/manifest`) and `link`
  (relative symlinks into a source checkout, used when developing the framework itself).
- The upgrade decision table: install, replace, keep-modified, delete — decided per path
  from the manifest hash, the on-disk file and the staged source.
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
  `_upgrade_process_path`, `_upgrade_link`.
- `scripts/lib/manifest.sh` — the manifest reader and writer.
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
