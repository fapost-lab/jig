---
id: adr-0003-framework-copied-into-project
type: adr
status: accepted
date: 2026-09-08
domains: [adapters, distribution]
paths:
  - "adapters/**"
  - "scripts/init*"
  - "scripts/upgrade*"
---
# ADR-0003: Framework files are copied into the project and tracked by git

## Context

Two distribution models were considered: a Claude Code plugin installed at user level,
or copying skills/scripts into the project (as ai-factory does into `.claude/skills/`).
The team shares one environment, and the spec's core principle is that the process
belongs to the project.

## Decision

- `sdlc init` copies scripts to `.ai/scripts/`, profiles to `.ai/profiles/`, and
  skills to each selected adapter's directory (`.claude/skills/sdlc-*`,
  `.codex/skills/sdlc-*`). All of it is committed.
- `.ai/manifest` records the framework version and a hash of every installed file.
  `sdlc upgrade` replaces only files whose hash still matches the manifest; locally
  modified files are kept and reported.
- The same copy model is used for every adapter, keeping them symmetric.

## Alternatives

- **Claude Code plugin** — rejected for MVP: user-level install means a colleague
  cloning the repo does not get the process; Codex would need the copy model anyway;
  can be added later as a thin wrapper.
- **Git submodule / symlink to the framework checkout** — rejected: fragile across
  machines and CI.

## Consequences

- Cloning the repo yields a fully working agent environment.
- Framework upgrades are an explicit, reviewable commit.
- Installed skills may diverge per project; the manifest makes divergence visible.
