# Roadmap — Specifications and the jig-idea skill

Destination: an idea is tested with `jig-idea`, kept as a committed specification and turned into
tasks phase by phase whose completion the roadmap records; a spec can be removed cleanly, or copied
into a new project as its starting plan.

## Phase 1 — Storage, skill and listing

Goal: specifications can be created, tested and found. Done when: `jig-idea` is installed for
both runtimes, `jig spec list` and the `specs:` status line are tested, and this spec exists.

- [x] `idea-workflow` — `.ai/specs/` convention, `jig-idea` skill and templates,
  `jig spec list`, `specs:` status line, AGENTS/README/`jig-task` pointers, ADR

## Phase 2 — Tasks from the roadmap and removing a spec

Goal: a roadmap drives tasks and records their completion. Done when: phase tasks are filed with
a `Spec:` line, the knowledge decision checks their items, and `jig spec remove` unlinks and trashes.

- [x] `spec-task-links` — file a phase's tasks from the roadmap with the `Spec:` line; `jig-task`
  reads the linked spec as input (after: `idea-workflow` — needs the storage and the skill)
- [x] `spec-task-links` — `jig spec done` checks a task's items when its knowledge decision is
  recorded (after: filing — reads the `Spec:` line)
- [x] `spec-task-links` — `jig spec remove` with `--dry-run` and `--abandon-unstarted`, RULES
  amendment for trashing a spec (after: filing — unlinks by the `Spec:` line)

## Waves

1. `idea-workflow`
2. `spec-task-links` — filing, checkmarks and removal in one task
