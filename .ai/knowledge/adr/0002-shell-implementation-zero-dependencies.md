---
id: adr-0002-shell-implementation-zero-dependencies
type: adr
status: accepted
date: 2026-09-08
domains: [core, scripts]
paths:
  - "scripts/**"
  - "tests/**"
summary: Why Jig is bash 3.2 with git as its only mandatory dependency.
---
# ADR-0002: Scripts are POSIX/bash-3.2 shell with no mandatory dependencies

## Context

The framework is installed into a project as files and read by agents. A compiled
binary would be opaque to both humans and agents and would add a deployment step.
Node or Python would add a runtime requirement to every developer machine and CI runner.
The executable surface is small (init, upgrade, task state, context, verify, housekeeping).

## Decision

- Scripts are written for POSIX sh / bash 3.2 (macOS default). No bash 4+ features
  (associative arrays, `${var,,}`, `mapfile`).
- Mandatory dependency: `git` only. Optional: `gh` / `glab` for forge merge detection.
- No YAML parser: `state` files and knowledge frontmatter are restricted to flat
  scalars and one-level lists so they can be read with `sed`/`grep`.
- Tests use a hand-rolled sh runner under `tests/` to preserve the zero-dependency
  property.

## Alternatives

- **Go binary** — rejected: opaque, needs a release pipeline, templates via embed.FS.
- **TypeScript/Node (as ai-factory)** — rejected: Node ≥18 requirement, slower start
  for a scheduled housekeeping job, and no gain for a file-and-git tool.
- **Python** — rejected: environment fragility; may be used ad hoc for a single
  hard case later, but not as the base.

## Consequences

- Anyone can read what a command does; agents can too.
- Destructive operations must be written defensively (see ADR-0006).
- A `shellcheck` pass and the test suite are the quality gates for scripts.
