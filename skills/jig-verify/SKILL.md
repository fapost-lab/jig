---
name: jig-verify
description: Verify a Jig task with evidence — run the project's checks and confirm the task's goal is actually met. Use before declaring work done, or when the user says "verify", "check it works", "run the tests", "are we done".
---

# jig-verify — evidence, not claims

## 1. Run the project's checks

Reuse completed checks when their code, test inputs, and relevant environment have not
changed. Run missing or invalidated checks; a stage transition alone is not a reason to
repeat them. Documentation-only work needs relevant document checks, not an unrelated
full code suite. Keep required regression coverage for behavioral changes.

```
.ai/scripts/jig verify
```

While iterating, `jig verify --changed` narrows the run to what the diff touches, and
each profile reports whether it honoured the scope or ran everything anyway. It is not
evidence that the task is done: the run above, unscoped, is.

Wait on the run's own handle and read that exit code: `.ai/scripts/jig verify >verify.log
2>&1 & wait $!` in plain shell, or the completion signal of the tracked background job if
the harness started one. Never poll with `pgrep -f <pattern>` — the polling command's own
command line contains the pattern, so it matches itself and waits forever.

This runs the active profiles: tests, linters, static analysis, whatever the stack
provides. A `skip` means the check did not run, which is not a pass. A missing tool is
worth reporting, not hiding.

For T4 add regression and security checks: the exact scenario that motivated the task,
plus the neighbouring paths a mistake would break.

## 2. Confirm the goal, not just the green

Read the goal in `task.md` and check the change actually delivers it. Tests passing and
the task being done are different claims. Where the goal is user-visible, exercise it the
way a user would.

## 3. Check the knowledge still holds

```
.ai/scripts/jig knowledge check
```

Failures are blocking. Warnings about `paths` matching nothing mean a document now points
at files that moved or never existed; fix them during consolidation.

## 4. Report

State what ran, what passed, what was skipped and why. If something failed, say so with
the output before anything else, and do not describe the work as done.

When everything holds:

```
.ai/scripts/jig task set <id> status ready
```

Then consolidate for T3 and T4, or whenever the task produced knowledge worth keeping.
