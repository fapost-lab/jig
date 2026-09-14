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
reviewed_at: 2026-09-14
---
# Install

Getting the framework into a project, keeping it current, and never destroying what the
project owns.

## Responsibility

- The framework-owned / project-owned split: `.ai/scripts/`, `.ai/profiles/`,
  `.ai/templates/knowledge/` and the installed skills are carried forward by upgrade;
  `.ai/knowledge/`, `.ai/config.yaml` and `AGENTS.md` are never touched (ADR-0003,
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

## Boundaries

Outside: what a skill or profile *says*. Adapters contain no SDLC logic; the only
transform today is Codex's invocation syntax (`/jig-x` → `$jig-x`).

Outside: how a release tag is made. The installer and `self-update` only read tags; the
release process creates them, and must keep each tag equal to its commit's `JIG_VERSION`.

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
- `scripts/lib/self-update.sh` — `cmd_self_update`.
- `scripts/lib/common.sh` — `jig_release_version`, `jig_version_newer`, `jig_newest_release`,
  `jig_global_executable`, `jig_declared_version`, `jig_version_of`.
