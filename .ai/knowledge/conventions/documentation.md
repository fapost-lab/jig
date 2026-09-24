---
id: convention-documentation
type: convention
status: active
domains: []
paths:
  - "docs/**"
  - README.md
  - CONTRIBUTING.md
  - .github/scripts/changelog-check.sh
  - AGENTS.md
  - templates/AGENTS.md
summary: How a behaviour claim earns its place in the docs — run it, paste the output, check it against the release branch — and how an instruction agents read is written so it beats the runtime's own default.
reviewed_at: 2026-09-24
---
# Documentation conventions

Practices for the user-facing site, the repository's own guides, and the instruction files
agents read. They exist because the rationale column names what each one cost.

## Practice

| Rule | Rationale |
|---|---|
| A statement about behaviour reaches documentation only after it was run. Command output shown in the text is pasted from a run, never reconstructed from the code that prints it. | One documentation pass made three false claims this way, each read out of the source rather than executed: that the release `jig upgrade` relinks a link-mode project (it reports `keep-conflict`, places nothing and leaves the manifest alone); that `jig upgrade` takes its source from the executable's location (only the global one does — a project's own `.ai/scripts/jig` resolves to `<project>/.ai`, which is no source root, and falls back to `.ai/manifest`); and a sample output line reading `stays installed from .`, which `manifest_source` can never print because it resolves `.` to the project path. Each read plausibly on the page, and each was caught only by a reviewer who ran the command. |
| While an epic is open, check a behaviour claim against the branch the release is cut from, not the branch under your feet. | An epic branch is behind `main`, which merges into it before the release. A pass documented the epic's `jig upgrade` behaviour although `main` had already fixed it, so the text would have shipped describing a bug that no longer existed. |
| A concept that both the site and a skill reference define is changed in both, in the same change. Where the full definition is too long for the site, the site carries the test the reader has to apply and the reference stays the complete one; what it may not carry is the superseded rule. | `docs/concepts.mdx` went on telling a human that the critical class is "Security, secrets, destructive operations, money" after `skills/jig-task/references/classification.md` had replaced that closed list with a risk test (ADR-0009, amendment of 2026-09-24). For as long as that lasted, the person at the human gate and the agent that classified the task meant different things by T4, and a disagreement of that kind surfaces as an argument about wording rather than about risk. Nothing catches it: the site is prose no test reads, and the rubric is a skill reference no test reads either. |
| A release is described as it is made: the pull request that raises `JIG_VERSION` adds that version's section to `docs/changelog.mdx`, a line or two per user-visible change. | The first fourteen releases shipped without a page, so the changelog had to be reconstructed from tags, commits and ADRs afterwards — at the one moment nobody remembers what a version contained, and at the cost of claims a reviewer then had to check against `git show`. Asking the author to remember is the maintenance this repository automates instead, so the `changelog` job refuses a pull request whose unreleased `JIG_VERSION` has no section (`.github/scripts/changelog-check.sh`). |
| An instruction that has to beat a runtime's own default is written as a table row indexed by the moment it is needed, whose third column names the path the agent would otherwise take. Eight rows is the ceiling. | `AGENTS.md` said in prose "start work with the `jig-task` skill" and never said "and not with your own background tasks". A reviewer reported following a table of exactly this shape for a whole session without a miss, while resolving the prose about Jig the other way. The third column is what does the work: it names the default the agent is already reaching for, at the moment of reaching for it. Length is the other half — a table of twenty rows stops being read for the same reason prose does. |
| A rule whose full form lives in a skill reference still carries its deciding question where the agent meets the rule first. | The class was described in `AGENTS.md` by one word — "local", "critical" — while the risk test that decides it lived in `skills/jig-task/references/classification.md`, which an agent opens only once it is already inside `jig-task`. An agent that took the short way classified from the word. Rewriting the rubric does not fix that: it improves a document the agent has to arrive at first. Copying the rubric up would break ADR-0001, so the deciding question moves up and the full test stays down. |
| `docs/known-issues.mdx` carries only faults still unfixed in `main`, each entry naming the task that closes it in a comment; the entry is deleted by that task's own pull request, the one that merges the fix. | The site is built from `main` and describes `main`, so the page states the project's current condition, not an installed version — `docs/changelog.mdx` is the page about releases. Two other removal rules were tried and are wrong here: removing an entry when a fix is merged *and released* leaves the page contradicting the branch it is built from, and removing it when somebody starts fixing empties the page while the fault is still there. What is left is ownership. This is the record `conventions/required-records.md` warns about — composed by a person, and refutable by nothing the machine sees, because task workspaces are gitignored and CI cannot read task state — so the entry is bound to the one diff where a reviewer is already looking at the fix. A page whose entries name no owner has no moment at which anyone is obliged to reread it. |

## Example

Reproduce the claim in a throwaway repository, then paste what it printed:

```bash
cd "$(mktemp -d)" && git init -q . && git commit -q --allow-empty -m init
/path/to/jig/scripts/jig init --link
/other/checkout/scripts/jig upgrade        # the claim under test
```

When the claim is about a fix that is on `main` but not on this branch, clone `origin/main`
and run it from there; the branch's own scripts answer for the old behaviour.

## Rationale

Documentation is the one artefact whose errors no test catches: every check in this
repository verifies scripts, never the prose about them. A reader who follows a false
sentence loses more than the time it took to write it, and a reviewer is the only gate,
so the cost of proving a claim belongs with the author who makes it.
