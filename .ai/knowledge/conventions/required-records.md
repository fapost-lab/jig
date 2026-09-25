---
id: convention-required-records
type: convention
status: active
domains: []
paths:
  - "skills/**"
  - scripts/lib/task.sh
  - schemas/state.md
summary: "The test a new mandatory record has to pass before a stage may demand it: computed, written by someone other than whom it binds, or refutable by the machine — otherwise it decays into a form to fill."
reviewed_at: 2026-09-24
---
# Records the process requires

When a stage is about to demand a new record — a field in `state`, a line in `task.md`, a
section a document must carry — this is the test it has to pass first.

## Practice

> A required record resists ritual when it is **computed** by a machine rather than composed,
> or **written by someone other than the person it constrains**, or **refutable by something
> the machine can see on its own**. A record with none of the three is self-certification: its
> author, its subject and its only reader are the same agent, reasoning once. It decays into a
> form to fill, and the form is then matched rather than thought about.

| Rule | Rationale |
|---|---|
| A record written by the actor it constrains buys nothing it did not already have. Give it a second author, or compute it. | The review findings ledger works for this reason: the finding is entered by the reviewer and blocks the author, so a claim has to survive somebody who did not make it (adr-20260921-review-findings-block-completion). Asymmetry of authorship is what the ledger is, not a detail of it. |
| Prefer a record that is derived over one that is filled in. A derived record cannot be answered mechanically, because it is not answered at all. | The review receipt is a hash of the reviewed tree, the design and the findings — nobody fills it, `jig task receipt` computes it, and it goes stale on its own the moment the tree moves (adr-20260921-review-receipt-pins-what-was-reviewed). No discipline sustains it, so none can lapse. |
| A list an agent can match against will be matched instead of reasoned about. Do not create one, and do not let an illustration turn back into one. | The classification rubric listed concrete signals under each abstract class heading, and the agent matched the list because matching is cheaper than reasoning about the heading; work no list named fell to a lower class. ADR-0009's amendment of 2026-09-24 put the risk test in front and demoted the lists to open examples, with an explicit constraint against turning them back. A mandatory field whose answer has an obvious default is the same object one level down. |
| Where a class or a judgement can be contradicted by a fact in the diff, let the machine raise the contradiction at the completion gates, where the diff exists. Do not ask the author to attest to it at the start, where it does not. | A class is chosen in `jig task new`, before there is anything to check; by `status ready`, `knowledge_consolidated true` and `task ship` the change exists and `scripts/lib/task.sh` already refuses on facts it can read. Re-classification mid-route is normal and cheap — change the class, say so, continue on the new route — so a machine's only useful output here is "re-classify", not a record the author swore to earlier. |

## What measured this

The rule was not derived in the abstract. A proposal to make every task carry one written line
— "if we are wrong, this is what takes it back" — was tested against all 73 merged tasks of this
repository, each classified by reading its diff:

- **43 of 73** would have carried `revert`, and nothing more. Every prose-only task (28 of 92
  merged pull requests) would have, without exception.
- Of the 29 with a substantive answer, **15 were a single cause** — the change raised
  `JIG_VERSION`, which is a release, which `git revert` does not retract. That one cause is
  larger than every other irreversible cause combined.
- The decisive case: pull request #88, "Replace installed files by renaming, never by writing in
  place", raised `JIG_VERSION` 0.15.0 to 0.15.1 with a changelog entry. An agent told in so many
  words to flag "raises the shipped version" read that diff and answered "just revert". The
  reader primed to catch it missed it.

The proposal was rejected on its own evidence: the line would have been written by the same
agent, in the same moment, from the same reasoning that produced the class — so it inherits the
blind spot whole and then presents it as a checked fact. What the measurement left behind is the
test above, not the line.

## Example

Refusing a record is as much a result as adding one. When a stage wants a new obligation, name
which of the three properties it has. If it has none, say so and stop there — an obligation that
only produces a default answer costs every task and catches nothing.

The one property most often available is the third: a fact already in the repository that can
contradict the claim. `.github/scripts/changelog-check.sh` is the shape — it asks a stateless
question about the declared version, turns itself on when a branch raises it and off once the
version is released, and nobody fills anything in.

The rule has since refused a second proposal, and what the refusal measured is worth more than
the proposal was. A machine was to object at the completion gates wherever a class contradicts
the diff: a change that raises the shipped version is a release, and a release is neither T0 nor
T1. It passes the test above twice over — nobody fills anything in, and the objection is a fact
the machine reads for itself — and it was still not built. Two findings outlive it.

**A signal read from a diff is worth exactly what the file it reads is worth.** Anchored to one
path and one line, this one is exact: of 96 merged pull requests, 18 change `^JIG_VERSION=` in
`scripts/lib/version.sh`, and those same 18 are every pull request that touches that file at all
— not one false positive. Loosened to a substring search over the whole diff it takes on 8 false
positives at once, because `JIG_VERSION=` also lives in 15 other files, 9 of them tests that
write fake version files. Generalised to other ecosystems by a shell without `jq` it stops
working altogether: `^version = ` in `Cargo.toml` matches a dependency's version under
`[dependencies.*]` as readily as the package's own; `"version"` in `package.json` picks up a
nested one (`9.9.9` for a package whose version is `0.4.1`); a `pyproject.toml` with
`dynamic = ["version"]` holds no version at all; and in Go, Swift and most PHP libraries the
release is a git tag, so there is no version in any file to read. The exactness collapses at the
ecosystem boundary, not at the parser — which is where a better parser would have been spent.

**Before a proposal is judged by the test above, ask whether its mechanism reaches its
evidence.** The version check was to be generalised by the profiles, so that nobody configures
anything: `node` knows `package.json`, `rust` knows `Cargo.toml`. But this repository activates
`generic` and `shell`, and its own version lives in `scripts/lib/version.sh` — a file invented
here, belonging to no ecosystem's convention, which no profile can name. Not one of the 15 tasks
that justified the proposal would have been reached by the mechanism proposed to catch them. A
proposal can pass the ritual test and fail this one, and it fails it quietly, because the
evidence and the instrument are almost always argued in separate paragraphs.
