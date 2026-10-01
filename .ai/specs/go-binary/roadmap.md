# Roadmap — Jig without bash: one implementation for every platform

Destination: `jig` is one implementation for macOS, Linux and Windows — TypeScript on Node
with zero dependencies unless the Phase 0 gate says otherwise — and bash is needed nowhere — not for a command, not for a verify profile, not for the session hook — and
every behaviour the sh suite proved is proved again against the binary.

## Phase 0 — Measure before committing

Goal: the go/no-go question has a number on each side, and the decisions the port cannot
start without are taken as a proposed ADR. Done when: the baseline and the prototype are
measured on Linux and on Windows with Defender on, the test triage names every test as
contract or implementation, and a superseding ADR is proposed — and a human has said go or
no-go on the spec.

- [ ] Baseline — `jig context` and `jig knowledge check` timed on Linux and on Windows with
  Defender on, after the one-walk knowledge cache has landed in bash (prerequisite: the
  `knowledge-costs-one-walk` task; it changes the number the port must beat)
- [ ] Test triage — every one of the 2,391 tests classified as contract (drives `jig` as a
  process) or implementation (sources `lib/*.sh`, runs a profile script directly), recorded
  in a file the parity run reads
- [ ] Spike — a standalone prototype, in the recommended form (TS on Node, zero
  dependencies; repeated in Go only if a runtime reason fails it), of `knowledge` + `context` and of the junction and
  deletion primitives, run against the contract subset of their tests and timed beside the
  baseline on both platforms (after: Baseline — a prototype without a baseline measures
  nothing; after: Test triage — the parity run needs to know which tests may be red for
  reasons other than behaviour)
- [ ] Superseding ADR, proposed — one document that supersedes ADR-0002 and amends ADR-0003,
  0033, 0037, RULES.md:151 and AGENTS.md, carrying the decisions in `spec.md`; proposed, not
  accepted, until the gate says go
- [ ] fog: the profile language — what a declarative profile must express for the 13
  profiles to port without loss; cannot be stated until the spike has shown how the binary
  shells out to project tools

## Phase 1 and after — fog

- [ ] fog: the port itself — a skeleton (dispatcher, config, common, manifest), then
  commands in waves, then distribution (installers on every platform; version switching,
  release artefacts and signing only for a binary form), then the deletion audit, then the knowledge and docs migration, then retiring
  bash. Not cut until Phase 0 says go; the epic branch and its `major` release are declared
  then, not now.

## Waves

1. Baseline; Test triage; Superseding ADR, proposed
2. Spike

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
- A wave entry names an item by its title (the text before its first ` — `) or its task id,
  entries separated by `;` — `jig spec plan` reports an entry that names no item or several.
-->
