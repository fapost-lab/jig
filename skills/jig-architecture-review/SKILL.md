---
name: jig-architecture-review
description: Review a Jig task against the system's architecture — boundaries, dependency directions, invariants and accepted ADRs. Use for T3 and T4 tasks after implementation, or when the user says "architecture review", "does this fit the architecture", "did we break a boundary".
---

# jig-architecture-review — does the system still hold its shape

Code review asks whether the change is correct. This asks whether the system is still the
system its documentation describes.

## 1. Load the shape

```
.ai/scripts/jig context --task <id> --all
git diff
```

`--all` includes superseded and deprecated documents: a change that revives a rejected
approach is exactly what this review must catch.

## 2. Check five things

- **Boundaries.** Does any component now know about something it must not? Domain code
  reaching into infrastructure, a module importing across a documented boundary.
- **Dependency direction.** Does every new dependency point the way `ARCHITECTURE.md`
  says it may?
- **Invariants.** Does the change preserve every invariant in `RULES.md`? Name the ones
  it touches and how they still hold.
- **Accepted decisions.** Does it contradict an accepted ADR? If the ADR is now wrong,
  the answer is a new ADR superseding it, never a silent departure.
- **New decisions.** Did the change make a choice that deserves recording? If so, it is
  an ADR candidate for consolidation.

## 3. Report

For each of the five, one line: holds, or violated with the evidence. Violations are
blocking; escalate a conflict between the change and an accepted decision to the human
rather than resolving it yourself.

Then hand the ADR candidates to `jig-consolidate`.
