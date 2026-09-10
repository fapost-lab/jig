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

## Boundaries

Outside: what a skill or profile *says*. Adapters contain no SDLC logic; the only
transform today is Codex's invocation syntax (`/jig-x` → `$jig-x`).

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
