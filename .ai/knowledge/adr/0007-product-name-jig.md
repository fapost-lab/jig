---
id: adr-0007-product-name-jig
type: adr
status: accepted
date: 2026-09-08
domains: [naming, adapters, skills, scripts]
paths:
  - "skills/**"
  - "scripts/**"
  - "adapters/**"
summary: Why the product is called Jig, and what the name commits it to.
---
# ADR-0007: The product is named "Jig"

## Context

The working name `agent-sdlc` is descriptive but long and generic. The name appears in
three user-facing places: the plugin/skill namespace (`/agent-sdlc:plan`), the script
entry point (`agent-sdlc task new`), and adapter directories. All three need something
short, pronounceable, and ideally self-explaining. A DNS domain is not a requirement:
the framework is installed from git and copied into projects.

## Decision

- The product is **Jig**. A jig is a machining fixture that guides the tool and holds
  the work steady but does no cutting itself. The agent is the tool; Jig guides it
  (see ADR-0001).
- Script entry point: `.ai/scripts/jig <command>`.
- Skills: `jig-<stage>` when copied into a project; `/jig:<stage>` when packaged as a
  plugin.
- The project-side directory stays `.ai/`: knowledge and process belong to the project,
  not to the tool, so the tool's name does not go on that directory.
- "Agent SDLC Framework" remains the descriptive subtitle.

## Alternatives

- **`bpai`** (bpartner AI) — rejected for the product: an owner brand, not a product
  name, and less adoptable outside the organisation. Kept as the repository /
  organisation name.
- **`keelson`** — the beam that ties a ship's frames over the keel; unique and
  pronounceable but seven letters and needs explaining.
- **`cairn`** — durable markers left for those who follow; fits consolidation, but an
  existing `cairn-dev/cairn` project and a weaker link to the core mechanism.
- **`keel`, `trellis`, `tack`** — rejected: established projects with the same name.

## Consequences

- Rename is mechanical: `agent-sdlc` → `jig`, `sdlc-*` → `jig-*`, `sdlc <cmd>` →
  `jig <cmd>` in spec, glossary, rules and earlier ADRs (historical quotes of v0.3 are
  left as written).
- `jig` is a common word; GitHub search is noisy. Uniqueness comes from the
  `bpai/jig` repository path, not from the word.
