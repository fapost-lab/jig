# Roadmap — knowledge sources that are sections of a file

Destination: a stub can link one section of a tracked file, and an agent reads only that section.

## Phase 1 — section sources

Goal: a README's rule section can be adopted without the rest of the file. Done when: a stub with
`section:` resolves to the section's line range, an edit outside it is not `changed`, and a renamed
heading is reported with the section that still has the approved text.

- [ ] section sources — the `section:` field through `new`, `check`, `context`, `sources`,
  `changed`, `inventory` and acknowledgement, plus `jig knowledge section` to relink
- [ ] skills adopt sections — `jig-map` links rule sections of READMEs, `jig-accept` and
  `jig-consolidate` work on the section (after: section sources — they call its commands)

## Waves

1. section sources
2. skills adopt sections
