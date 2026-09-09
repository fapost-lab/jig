---
name: jig-implement
description: Implement a Jig task — write the change against the project's rules and conventions, then prove it with evidence. Use after analysis or an approved design, or when the user says "implement", "write the code", "make the change", "continue implementation".
---

# jig-implement — make the change

## 1. Know what binds you

```
.ai/scripts/jig context --task <id>
```

Read the listed documents before writing code. Conventions and invariants are not
suggestions: a change that violates one is wrong even when it works.

For T3 and T4, check that the human approved the design. If no approval was given in this
conversation, go back to the gate.

## 2. Follow the plan, one step at a time

If `plan.md` exists, work through it in order and tick steps as they land. If the plan
turns out wrong, fix the plan first and say what changed. Do not silently diverge.

## 3. Write like the codebase, not like yourself

Match the surrounding style, the naming in `GLOSSARY.md`, and the patterns the
conventions describe. Prefer the boring solution that fits the existing shape over a
better one that does not. Where you must introduce a new pattern, say why.

Scope discipline: implement the task, not the improvements you notice on the way. Note
those separately and let the user decide.

## 4. Prove it as you go

Every change carries its evidence: a test for new behaviour, a failing-then-passing test
for a defect, a check that the build still runs. During implementation, run the smallest
relevant checks provided by the project.
Run the required full checks once against the final change in `jig-verify`; do not run
the whole suite after each edit or start another copy while a run is still active.

An unproven claim is not done. If a check cannot run, say so plainly instead of
declaring success.

## 5. Report

Say what changed, in which files, and what the evidence is. Then move to review for T2
and above, or straight to `jig-verify` for T0 and T1.
