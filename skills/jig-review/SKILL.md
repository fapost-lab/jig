---
name: jig-review
description: Review a Jig task's diff against the project's knowledge, rules and conventions before it ships. Use after implementation for T2 and above, or when the user says "review", "check this change", "is this ready".
---

# jig-review — review against the project, not against taste

## 1. Load what the change must satisfy

```
.ai/scripts/jig task changes <id> --base <ref>
.ai/scripts/jig task changes <id> --base <ref> --format paths > <workspace>/review-files
.ai/scripts/jig context resolve --task <id> --stage review --files - < <workspace>/review-files
.ai/scripts/jig context guard --task <id> --stage review --files - < <workspace>/review-files
```

Establish ownership and inspect all patches/new contents using
[change scope](references/change-scope.md), adding an explicit allowlist for unrelated work.
The context lists the ADRs, invariants and feature knowledge that bind these files.
Review against those, plus correctness. Style opinions with no rule behind them are noise.

Resolve against the *actual* diff, not the task's original file list — the change reaches
files nobody planned. If the guard reports pending documents, read and acknowledge them
before reviewing: a review that has not read the rules it is reviewing against is a
formality.

For T4 the review is independent: run it in a fresh context, or delegate it to a
subagent that has not seen the implementation being defended.

## 2. Look for these, in order

- **Requirements.** Check every criterion in the [acceptance map](../jig-task/references/requirements-and-planning.md),
  including omitted functionality. For UI work inspect [applicable state evidence](../jig-task/references/ui-states.md).
- **Correctness.** Wrong results, unhandled failure paths, race conditions, boundary
  cases. State a concrete input that breaks it, or it is not a finding.
- **Rule and ADR violations.** Quote the rule. An accepted ADR contradicted silently is a
  blocking finding: either the change is wrong or the ADR is stale, and both need saying.
  A MUST NOT in a resolved [boundary document](../jig-task/references/component-boundaries.md)
  is a rule: an implementation that does it is a blocking finding.
- **Contract drift.** Callers, tests and docs that the change invalidated.
- **Evidence gaps.** Behaviour claimed but not covered by a check.
- **Scope creep.** Changes unrelated to the task.

## 3. What you run

A check belongs to a review when it tests a finding. Run `jig verify` once without flags —
the project's setting decides how wide it goes, so it needs none — and targeted filters on
the files a finding names. The run that earns its time is reverting the fix and watching the
new test go red: a test that passes either way proves nothing. Never `jig verify --full` and
never the raw runner over everything; the full set is CI's job, and a rerun of a suite that
already passed cannot see the two things that actually get through it
([what a reviewer runs](references/what-to-run.md)).

## 4. Report

Findings ordered by severity, each with file and line, one line of description, and a
concrete fix. Say plainly when there are none. Record each one in the task's ledger with a
severity, as [findings](references/findings.md) says: a finding only said here blocks nothing.
On a re-review, close each `fixed` finding that is fixed and reopen the rest. Last, write the
review's receipt (`jig task receipt <id> --stage review`), which pins what you reviewed.

Then either apply the fixes or hand them back, depending on what the user asked. A review
that ends without a decision on every finding is unfinished.
