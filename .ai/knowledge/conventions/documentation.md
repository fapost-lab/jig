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
summary: "How a behaviour claim earns its place in the docs: run it, paste the output, and check it against the branch the release is cut from."
reviewed_at: 2026-09-23
---
# Documentation conventions

Practices for the user-facing site and the repository's own guides. They exist because
the rationale column names what each one cost.

## Practice

| Rule | Rationale |
|---|---|
| A statement about behaviour reaches documentation only after it was run. Command output shown in the text is pasted from a run, never reconstructed from the code that prints it. | One documentation pass made three false claims this way, each read out of the source rather than executed: that the release `jig upgrade` relinks a link-mode project (it reports `keep-conflict`, places nothing and leaves the manifest alone); that `jig upgrade` takes its source from the executable's location (only the global one does — a project's own `.ai/scripts/jig` resolves to `<project>/.ai`, which is no source root, and falls back to `.ai/manifest`); and a sample output line reading `stays installed from .`, which `manifest_source` can never print because it resolves `.` to the project path. Each read plausibly on the page, and each was caught only by a reviewer who ran the command. |
| While an epic is open, check a behaviour claim against the branch the release is cut from, not the branch under your feet. | An epic branch is behind `main`, which merges into it before the release. A pass documented the epic's `jig upgrade` behaviour although `main` had already fixed it, so the text would have shipped describing a bug that no longer existed. |
| A release is described as it is made: the pull request that raises `JIG_VERSION` adds that version's section to `docs/changelog.mdx`, a line or two per user-visible change. | The first fourteen releases shipped without a page, so the changelog had to be reconstructed from tags, commits and ADRs afterwards — at the one moment nobody remembers what a version contained, and at the cost of claims a reviewer then had to check against `git show`. Asking the author to remember is the maintenance this repository automates instead, so the `changelog` job refuses a pull request whose unreleased `JIG_VERSION` has no section (`.github/scripts/changelog-check.sh`). |

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
