# Roadmap — Contract knowledge

Destination: an interface that others depend on has a contract that reaches every agent
touching its surface and that review holds a diff against, in the projects Jig is installed
into.

## Phase 1 — A written contract counts

Goal: a contract written by hand is a checked document, reaches the agent who edits its
surface, and review judges a diff against it. Done when: in a test fixture project with a
route file and its contract, `jig context --files <route file>` returns the contract, and
`jig-review` on a diff that removes a promised field names that contract with a "breaking"
verdict.

- [ ] The `contract` type — template with Guarantees, Obligations, Forbidden, Stability and
  Consumers; `.ai/knowledge/contracts/`; `knowledge new|check`; `accept` refuses an empty
  Consumers section and stamps `reviewed_at`; ADR; and the `jig-review` item beside
  "Contract drift"

## Phase 2 — Contracts get written

Goal: contracts appear without anyone remembering the type exists. Done when: a task that
changes a promise ends with a proposed contract, and `jig-map` on a project with routes
leaves drafts whose guarantees are questions, walked by `jig-accept`.

- [ ] `jig-consolidate` routes promises to a contract and proposes `deprecated` for an
  orphaned one (after: the `contract` type — it routes to that type)
- [ ] `jig-map` drafts contracts with guarantees as questions; `jig-accept` walks the
  questions and drops what is not confirmed (after: the `contract` type — it drafts that
  type, and `accept` enforces Consumers)

## Waves

1. The `contract` type
2. `jig-consolidate` routing; `jig-map` drafts and `jig-accept` questions

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
-->
