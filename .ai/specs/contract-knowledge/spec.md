# Contract knowledge

Depth: deep — it changes the knowledge model (types, frontmatter, context resolution, review) that ships into every installed project; a wrong type is expensive to take back.

## Idea

Asked which knowledge documents Jig creates and what it is missing, the human wrote
(translated from Russian): "I mean which documents we create and what, properly speaking,
we lack. For example, a document about contracts and the like. Or maybe everything is
enough."

The proposal they chose to test: add a `contract` knowledge document type for public
interfaces — file formats, CLI surface, APIs, schemas — that other parties depend on;
resolvable by `jig context` through `paths`, linkable as a stub to an existing file
(OpenAPI, proto, a DB schema), and checked in review for breaking changes. The first trigger
was the five `schemas/*.md` in this repository; the human then separated them from this spec
(see Decisions).

## Goal and problem

A contract here is a promise to a party that is not part of the change being made: a
mobile app calling an HTTP API, a front end reading a JSON response, a service reading a
table, a module calling another module's public class. Two parties are worse off today, weighted equally:

- Who is worse off without this, and how:
  - **An agent in an installed project** edits code that implements an API, a schema or an
    event without seeing the contract that code honours (OpenAPI, proto, migrations),
    because nothing links that file to the code in `jig context`.
  - **The reviewer and the human at the gate** learn that a diff breaks a promise to a
    consumer only if they happen to know the consumer exists; `jig-review` does not name the
    contracts a diff touches.
- What is true when the work is done:
  - Editing a contract's producer or consumer brings the contract into context without the
    agent guessing it exists.
  - `jig-review` lists the contracts a diff touches and says, for each, whether the change
    is compatible or breaking for its consumers.

## Stress test

- Hidden assumptions — "this holds only if …":
  - "A new type makes contracts reach agents" holds only if context resolution looks at the
    type. It does not: `context.sh` selects by `load`, `paths`, `domains`, `topics` and
    `stages` only (`context.sh:378-420`). Any document with the right `paths` — a `feature`
    stub on `schemas/state.md` today — already reaches the agent. A type buys a label for
    skills (review, consolidate, map), nothing in resolution.
  - "Review can tell compatible from breaking" holds only if the contract names its
    consumers. Jig has no format versioning; compatibility is kept ad hoc by "an absent key
    means the old behaviour" (`schemas/state.md:10-12`, `schemas/config.md:5`), and who
    consumes a format — an older installed Jig, a skill, an external client — is written
    nowhere.
  - `jig-review`'s "Contract drift" item (`skills/jig-review/SKILL.md:37`) covers callers,
    tests and docs inside the repository, not consumers outside the change.
- The main trade-off: a checked structure and an explicit contract-versus-rule line, paid
  for with a seventh type that every knowledge skill must route to and every user must tell
  apart from the other six.
- The weakest point: authorship (failure 3). The type is only worth having if someone
  states promises that are not already in the code, and in the target audience the only
  candidate author is the agent, which can read what the code does but not what was
  promised.
- Failure modes — cause, what breaks, the signal that shows it:
  Found by an independent failure hunt (clean context), ranked by likelihood times cost:
  1. Staleness always on, real drift silent. `stale` fires on any commit to a contract's
     `paths`, and interface code changes for refactors that keep every guarantee; the
     behaviour a guarantee rests on often lives outside the globs (middleware, serializers).
     Contracts stay stale, get stamped in bulk, and the wrong ones are never flagged.
     Signal: the contract stale count never reaches zero; a consumer breaks while its
     contract reads fresh.
  2. Review trusts the provider's word. The review item compares a diff with prose the
     provider wrote; consumers are listed by hand. A change that keeps the written
     guarantees but breaks unwritten behaviour passes as "keeps guarantees", and the item
     displaces the existing "Contract drift" check of real callers. Signal: review says not
     breaking, consumer tests fail after.
  3. Nobody writes contracts in a vibe-coded project. Telling "what the code guarantees"
     from "what it happens to do" is a judgement those users cannot make; the work is
     preventive; every contract waits `proposed` for a human. Either the type is dead weight
     in every skill, or the agent invents guarantees from current code and the human accepts
     unread. Signal: contracts that read as a description of the code; no review ever cites
     one.
  4. Blurred line with `feature` / `adr` / `convention`. The guarantees of a public route
     fit "why a feature is shaped so; its constraints" as well. The same content lands in two
     documents and they drift. Signal: one path matched by a `feature-` and a `contract-`
     document that disagree.
  5. Global guarantees ("IDs are never reused") belong to no file; reaching agents through
     `paths` forces `**` globs or `load: always`. Signal: contracts with `**` globs.
  6. Dogfood only. `schemas/*.md` are not installed into projects, and many ADRs cite them
     by path; converting them proves the type on an unusual single-author case and gives
     installed projects no example. Signal: contracts here, none anywhere else. Removed by
     the decision that keeps `schemas/` out of this spec.
  7. Contracts outlive their interfaces. Retiring one needs a status change no skill
     triggers; `orphaned` fires only with `reviewed_at`. Signal: review cites a contract for
     deleted code.
  A stub on a large generated file (context flood, `sources changed` after every build) was
  also found; the no-stub decision removes it.
- Other shapes considered, and why this one:
  - **Chosen — a `contract` type:** its own template and directory, a structure
    `knowledge check` can hold, and a `jig-review` item keyed on the type.
  - A `feature` tagged `topics: [contract]` — rejected: the type would lie (`feature` says
    why a feature is shaped so), nothing checks a free-form tag or the sections, and the
    contract-versus-rule line stays implicit; it is the free-form template again.
  - `domains/<d>/CONTRACTS.md` in the domain pack — rejected: it loads on entering the
    domain, not on touching the interface, so it reaches the wrong agents and misses the
    right ones, and ADR-0019 gives a pack one slot per type.
  - A trial in this repository first (`feature` stubs on `schemas/*.md`, one review line) —
    rejected: installed projects get nothing from it, and they are who the type is for.

## Scope and non-goals

- In scope:
  - The `contract` type: template, directory, `knowledge new|check|accept` support, the
    rule that Consumers is filled before accept.
  - `jig-review`: the contract item beside "Contract drift".
  - `jig-consolidate` and `jig-map`: routing to contracts, draft guarantees as questions,
    proposing `deprecated` for an orphaned contract; `jig-accept` walking the questions.
- Not doing:
  - Contract stubs, or linking a machine-readable file other than through `paths`.
  - Jig's own `schemas/*.md`, their visibility in `jig context`, format versioning or
    migrations: they concern this repository, not the projects Jig is installed into.
  - Deriving consumers from code, or checking compatibility mechanically (OpenAPI diff and
    the like): a contract is prose and the verdict is review's judgement.
  - Global guarantees in contracts: they stay in `RULES.md`.

## Decisions

- A contract document is written prose about an interface in the code — what a consumer may
  and may not do through it — read by a human and resolved for an agent by the interface's
  `paths`. Rejected: linking an existing machine-readable contract file (OpenAPI, proto) as
  the primary form, because the target audience's interfaces live in code (routes, models,
  migrations, classes), with no contract file to link.
- A contract document holds only what the code cannot say: what the provider guarantees,
  what a consumer must do, the uses that are forbidden, what is stable and what may change
  without notice, and who the consumers are. Signatures and parameters stay in the code —
  rejected: a full description with signatures, because it is a copy of the code that
  drifts with every signature change, the way `docs/SPEC.md` did (ADR-0028).
- Contracts get their own knowledge type, `contract` — rejected: a tag on `feature`, a
  domain-pack file, a trial without a type (see "Other shapes").
- A contract is always written prose; there are no contract stubs. A machine-readable
  contract file (OpenAPI, proto) is listed in the contract's `paths`, so editing it brings
  the contract into context. This reverses "linkable as a stub" in the original proposal.
  Rejected: a stub without the contract's sections, because consumers and stability would be
  unknown and review could not judge compatibility; a stub that also carries a body, because
  it reopens ADR-0036 (a stub holds only metadata) and makes resolution choose between body
  and source. The file is the code's side of the contract, like a signature. ADR-0036 is
  unchanged: stubs stay `adr`, `convention` or `feature`.
- Contracts come from two places: `jig-map` proposes drafts for the interfaces it finds, and
  `jig-consolidate` proposes one when a task made or changed a promise to someone outside
  the change. Rejected: consolidation only, because a project adopting Jig would start with
  no contracts and wait for tasks to touch each interface; map only, because promises made
  later in tasks would never be recorded. Failure 3 (guarantees invented from current code,
  accepted unread) is closed by the next decision.
- A contract binds exactly one interface. A guarantee that belongs to no single interface
  ("IDs are never reused") is an invariant in `RULES.md`, global or domain — rejected: a
  contract with `load: always`, because it would load everywhere and duplicate the role of
  `RULES.md`.
- A `jig-map` draft states each guarantee as a question — "promised, or incidental?" —
  which `jig-accept` walks with the human; what is not confirmed is dropped. The Consumers
  section is filled by a human, and `jig knowledge accept` refuses a contract whose
  Consumers section is empty. Rejected: guarantees written as statements marked
  "inferred", because the human would accept the whole draft and failure 3 would stand.
- In `jig-review` the contract item adds to "Contract drift", never replaces it: real
  callers are still checked. A "breaking" verdict is a finding the human accepts
  explicitly, and a change that alters a promise updates the contract in the same task.
  Rejected: a list of touched contracts without a verdict, because the goal asks review to
  tell compatible from breaking.
- The line between types: `feature` says why the provider is built as it is, for whoever
  changes its inside; `contract` says what those outside may rely on, for whoever changes
  its surface or depends on it; `rule` says what no change in a domain may break. A
  guarantee is written once, in the contract; a feature that depends on it names it in
  `requires`.
- A contract's `paths` claim the interface's surface only: the route file, the interface
  class, the schema, the OpenAPI file — for a file format, the code that reads and writes
  it. The template and `jig-map` say so. Rejected: surface plus implementation, because
  `stale` would fire on every refactor (failure 1). A behaviour change inside the
  implementation is caught by review's "Contract drift" check of real callers, not by
  `stale`.
- Jig's own `schemas/*.md` are not contracts and stay out of this spec. They describe this
  repository's file formats; the type is for the projects Jig is installed into, and
  designing it around the framework's own files measures it by the wrong project. Whether
  the schemas should reach agents editing Jig's scripts is a question for this repository,
  settled separately. Rejected: moving the schemas into `contracts/`, and a contract beside
  each schema — both mix the framework's own documentation with a feature it ships.
- Retiring a contract uses what exists: `jig knowledge accept` stamps `reviewed_at` on a
  contract, so a contract whose `paths` match nothing is always `orphaned`, never
  `planned`; `jig-consolidate` proposes `deprecated` for an orphaned contract among the
  documents it touches. No new mechanism.

## Open questions

- None open at this depth.

## Assumptions left untested

- The work is preventive: no incident is known, here or in another project, of an agent
  breaking a promise because it did not see the contract — taken at deep, stated by the
  human; tested by the first installed project that writes contract documents and whether
  review ever flags a breaking change through one.
