---
id: adr-20260925-verify-explain-plans
type: adr
status: accepted
date: 2026-09-25
domains:
  - verify
paths:
  - scripts/lib/verify.sh
  - scripts/lib/profile.sh
  - "profiles/**"
  - schemas/profile.md
summary: Why jig verify --explain asks only capable profiles for a read-only plan, reports conditional scope honestly, and never treats the preview as verification.
reviewed_at: 2026-09-25
---
# ADR: A profile explains verification work without running it

## Context

The clone-wide busy record serializes verification runs, but a caller could not
see whether a supposedly narrowed run would expand to the full set before
joining that queue. Four tasks changed independent files and each started a
full shell suite: `scripts/lib/common.sh` has no project map entry, yet the
shell profile's built-in rule correctly widens it. The coordinator cannot
derive that rule from the map. Go and Jest also need tool queries to know a
final narrowed test set. A preview that executes those tools would cease to
be a cheap, side-effect-free answer.

## Decision

`jig verify --explain` uses the ordinary profile selection, scope choice,
changed paths and project map. It checks for pending framework files and
invalid maps, but does not take the busy record or run project checks.

A profile declares `explain` in its `scope` list before the coordinator grants
it `JIG_VERIFY_EXPLAIN=1`. An older profile without that declaration is not
invoked; the preview reports `unknown` and exits 2. The regular verify path
unsets the variable even when the caller exported it. Profiles use the same
selection functions for the preview and the run. They print one
`PLAN <profile>: <check>: <state> (<reason>)` line per check, with `full`,
`filtered`, `skip`, or `conditional`. Conditional answers state what query is
missing and whether a full run remains possible. A profile reporting no valid
plan or exiting nonzero makes the preview fail. Code 0 means every selected
profile explained its work, not that any check passed.

In explain mode a profile may read files and locate executables, but must not
invoke a project tool, probe its version, change project files, or run checks.
New planning helpers in `profile.sh` leave the existing `jp_*` execution and
verdict functions untouched for installed user profiles. The plan describes
the current tree and environment, not a promise about a later run after they
change.

## Alternatives

Computing from the project map in the coordinator misses built-in profile
rules. A separate planner per stack duplicates those rules and drifts.
Printing a plan just before a real run cannot help a caller decide whether to
start it. Running `go list` or `jest --listTests` during the preview adds tool
cost and can execute project configuration. Estimating minutes depends on the
machine and concurrent load. The plan therefore reports scope, not duration,
and marks unresolved tool-dependent branches conditional.

## Consequences

A caller can inspect likely work before occupying the verification queue.
Every shipped profile has a new explain branch to maintain alongside its
execution path. Tests cover all shipped profiles with project-tool stubs and
check the cases where a filter widens or a tool query leaves uncertainty. A
paired shell-profile test compares the plan with the real check names and
skip decisions on the same fixtures to expose drift between the branches.
Installed user-modified profiles keep working without migration; their
preview remains unknown until their owner adds the capability. The `PLAN`
format is a distributed contract and must evolve compatibly.
