# Roadmap — Specifications and the jig-idea skill

Destination: an idea is tested with `jig-idea`, kept as a committed specification, turned into
linked tasks phase by phase, removed cleanly or carried into a new project.

## Phase 1 — Storage, skill and listing

Goal: specifications can be created, tested and found. Done when: `jig-idea` is installed for
both runtimes, `jig spec list` and the `specs:` status line are tested, and this spec exists.

- [ ] `idea-workflow` — `.ai/specs/` convention, `jig-idea` skill and templates,
  `jig spec list`, `specs:` status line, AGENTS/README/`jig-task` pointers, ADR

## Phase 2 — Tasks from the roadmap and removing a spec

Goal: a roadmap drives tasks and records their completion. Done when: phase tasks are filed with
a `Spec:` line, consolidation checks the item, and `jig spec remove` unlinks and trashes.

- [ ] File a phase's tasks from the roadmap with the `Spec:` line; `jig-task` reads the linked
  spec as input (after: `idea-workflow` — needs the storage and the skill)
- [ ] `jig-consolidate` checks the roadmap item when a linked task closes (after: filing — reads
  the `Spec:` line)
- [ ] `jig spec remove` with `--dry-run` and `--abandon-unstarted`, RULES amendment for trashing
  a spec (after: filing — unlinks by the `Spec:` line)

## Phase 3 — Carry a spec into a new project

Goal: an idea worked out in an idea-generation repository becomes a new project's starting
point. Done when: a spec is copied into a new project and its architecture and stack reach that
project's knowledge.

- [ ] fog: pointer left in the source project — form undecided without statuses
- [ ] fog: seam with `guided-project-init` — depends on that task's design

## Waves

1. `idea-workflow`
2. filing with the `Spec:` line
3. consolidation checkmarks, `jig spec remove` — separate files, can run in parallel
4. phase 3, after `guided-project-init`
