---
name: jig-map
description: Propose a domain-aware knowledge map for a project and route the accepted parts into `.ai/knowledge/`. Use after `jig-init` when a project has only the three global documents, when `.ai/knowledge/` does not describe the domains an agent keeps rediscovering, or when the user says "map the knowledge", "what are our domains", "propose knowledge structure".
---

# jig-map — propose the map, let a human accept it

The hard part is not collecting facts; scripts do that. It is deciding what a codebase's
domains actually are, which is a judgement, and judgements must not become project
knowledge until someone agrees with them.

## 1. Collect the facts

```
.ai/scripts/jig knowledge inventory [--scope <dir>]
.ai/scripts/jig context resolve --catalog --domains <domains so far>
.ai/scripts/jig knowledge paths
```

The first names the tracked files at the repository root — where manifests live, and
recognising what `composer.json` or `go.mod` implies is your judgement, not the
command's — plus the runtime instruction files and where the tracked code sits. The second
gives what knowledge already exists. The third gives where it is missing: `uncovered` is
code no document claims, `unmatched` is a document pointing at code that moved.

Read the code the inventory names. A map proposed from directory names alone is a guess
with a table of contents.

## 2. Separate what you saw from what you concluded

Every statement in the proposal is labelled:

- **observed** — it is in the repository; name the file or the command that shows it.
- **inferred** — you concluded it from evidence; give the evidence and say how sure.
- **proposed** — you are suggesting it should be true. This is where rules live.

A rule with no evidence is a proposal, not an observation, however obvious it looks.
Mislabelling here is the failure this skill exists to prevent: an inference that reads as
a fact becomes a rule nobody remembers agreeing to.

## 3. Write the proposal

`knowledge-map.md` in the task workspace: candidate domains, their boundaries, the
evidence for each, and — as its own section — **what you could not determine**. A map
that claims complete coverage of a codebase it read for twenty minutes is not credible.

Then create the documents at their real paths, proposed from the start:

```
.ai/scripts/jig knowledge new domain <domain> --proposed
.ai/scripts/jig knowledge new glossary <domain> --proposed
.ai/scripts/jig knowledge new rule <domain> --proposed
```

Then fill them in. A proposed document is validated by `knowledge check` and visible as a
normal diff, but `jig context` will not resolve it — so nothing you inferred can reach
another agent before a human has seen it. Never create one without `--proposed` and
demote it afterwards: until the status changes, the half-written document resolves as
project knowledge.

Give every document a `summary`. It is the one line an agent reads in the catalog when
deciding whether to open the document; without it the catalog says nothing.

Do not write to `GLOSSARY.md`, `ARCHITECTURE.md` or `RULES.md`. Those are the project's
own, and a map proposes domains, not project-wide law.

## 4. Human gate

Stop. Present the map and the diff together: which domains, what evidence, what you could
not determine, and what you would drop first if the human wants fewer. Wait.

Do not accept your own proposal. Silence is not approval.

## 5. Accept, then validate

```
.ai/scripts/jig knowledge accept <id> [<id>...]
.ai/scripts/jig knowledge reject <id> [<id>...]
.ai/scripts/jig knowledge check
```

Accept what was approved and reject what was not. Rejecting sets `status: rejected` and
leaves the document where it is: it stops resolving, and the next map to propose the same
domain can see that the argument was already had. Do not delete it.

Then report what entered `.ai/knowledge/` and what was turned down.

The gate does not have to close in this session. Anything left proposed can be decided
later with the `jig-accept` skill, which enumerates proposals so nobody has to remember
the ids.
