# Roadmap — Adopting a project's existing knowledge

Destination: a project that adopts Jig gets its existing rule documents to agents through
`jig context` — tracked ones linked in place, untracked ones copied — with no rule lost, duplicated
or changed without anyone seeing it, and can later migrate them into Jig's structure when the user
chooses.

## Phase 1 — Inventory and proposals

Goal: adopting Jig shows what the project already has and proposes links for it. Done when:
`jig-map` on a repository with documentation lists the rule-like documents, their duplicates and
contradictions, and leaves stub proposals a human can review and reject — acceptance opens in
phase 2, so nothing resolves yet: proposed documents never do (ADR-0016).

- [x] `adoption-inventory` — stubs with `source:` exist and validate: `jig knowledge new …
  --source <path>` writes a proposed stub; `knowledge check` fails a missing source, a source not
  in the git index with exact case, and two stubs on one source; inventory lists candidate files
  with size and tracked state, from `git ls-files -z`, never `CLAUDE.local.md`
- [x] `adoption-inventory` — `jig-map` adoption step: sort rule-like documents from guides for
  people, compare them and the runtime instruction files for duplicates and contradictions,
  propose stubs (team ADRs keep their numbers, catalog-only), show sizes (after: stubs with
  `source:` — it creates them)

## Phase 2 — Linked sources reach agents

Goal: an accepted stub puts its source in front of the agent and keeps that honest. Done when: a
task touching a linked source's `paths` is required to read the source, a changed source is owed a
new reading and is counted in `jig status`, and a missing one stops only the tasks that need it.

- [ ] `jig context` resolves an accepted stub to its source, catalog-only ADR stubs, "missing
  source" in the catalog and a failure only when selected; acknowledgements hash the source; lifts
  the phase-1 accept refusal, check and the `jig context` skip of stubs — amendments to ADR-0014 and ADR-0015 (after: phase 1 —
  needs stubs to resolve)
- [ ] `source_hash` at acceptance and review: `jig status` counts changed sources, `jig-accept`
  shows the diff for re-approval, `jig knowledge stale` reports them (after: stubs with `source:` —
  the hash lives in their frontmatter)

## Phase 3 — Keeping adopted rules current

Goal: work after adoption edits the rules where they live, and untracked rules join safely. Done
when: consolidation edits a source and reports it, never rewrites a team's accepted decision, and
an untracked rule file is copied only after a secret check and a human's look.

- [ ] Consolidation into sources: `jig-consolidate` edits the source, follows the project's own ADR
  convention for new decisions, `jig knowledge changed` reports source edits (after: `jig context`
  resolves stubs — consolidation must find the owner the agent was given)
- [ ] Copying untracked rule files: secret check that refuses until confirmed, the file shown
  whole, another tool's frontmatter replaced, a reminder that the original remains (after: stubs
  with `source:` — shares the inventory)

## Later

- [ ] fog: full migration into Jig's structure, started only by the user — what it produces and how
  it splits a mixed document are not known yet
- [ ] fog: rules inside sections of a file (README development sections) — no reference survives a
  renamed heading yet

## Waves

1. Stubs with `source:`
2. `jig-map` adoption step; `source_hash` and change reporting; copying untracked rule files
3. `jig context` resolves stubs (resolution and acknowledgements share `scripts/lib/context.sh`)
4. Consolidation into sources

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set by `jig spec done`.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
-->
