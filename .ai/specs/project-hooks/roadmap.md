# Roadmap — project hooks

Destination: a project rule reaches the agent at exactly the stage it belongs to, and a project
script can refuse a task's completion gate until the rule is met or a human waives it with a reason.

## Phase 1 — stage-only knowledge

Goal: a document can be required at named stages of every task, with no domain and no
`load: always`. Done when: a document with `load: stage` and `stages: [consolidate]` is required
by `jig context resolve --stage consolidate` for a task with no matching domain, is absent from
`--stage implement`, and `jig knowledge check` fails `load: stage` without `stages`.

- [ ] stage-only loading — `load: stage` through the resolver, pending/guard, `knowledge check`,
  `schemas/frontmatter.md`, the docs site and an ADR amending ADR-0014/0021

## Phase 2 — command hooks at completion gates

Goal: a project's own script can refuse `ready`, consolidation or ship. Done when: a hook that
exits non-zero makes the gate refuse with the hook's name and output, a hook that exits 0 with
output passes and shows it as a warning, a missing hook path refuses and is reported by
`jig status`, and a waiver with a reason lets that one task through and appears in `jig status`.

- [ ] gate hooks — `hooks.ready|consolidate|ship` read from `.ai/config.yaml` only, run in
  `task set` and `task ship` after the findings and receipt checks, exit-code contract,
  environment, misconfiguration reporting, docs and an ADR
- [ ] hook waivers — a per-task waiver with a reason, shown by `jig status` and in the pull
  request body; autopilot treats a hook refusal as a stop and never waives (after: gate hooks —
  there is nothing to waive before a hook can refuse)
- [ ] fog: hook timeout — whether a gate bounds a hook's run time depends on what bash 3.2 can
  do portably and on autopilot's stop rules; see the open questions

## Waves

1. stage-only loading, gate hooks
2. hook waivers
