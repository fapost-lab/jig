# Task classification rubric

Pick the class from the signals below, then run the route. Signals are read in order:
the first class whose signals fit is the answer. When two classes fit, apply the
tie-break rule at the bottom.

## T0 — Trivial

One obvious change with no design choice and no new behaviour.

Signals: typo, wording, comment, formatting, a rename confined to one file, a version
bump, a doc fix. Reverting it is trivial and nothing depends on the change.

Route: **implement → verify**. No workspace, no artifacts.

## T1 — Local

Behaviour changes inside one component, and the shape of the change is obvious.

Signals: a bug fix with a known cause, a small feature inside an existing module, a test
added for existing code. No new dependency, no change to a contract another component
relies on, no data shape change.

Route: **analyze → implement → verify**. Workspace only if the task spans sessions.

## T2 — Structural

Several components move together, or an internal contract changes.

Signals: a new module inside existing boundaries, a signature or interface used by other
components, a refactor across files, a new command or endpoint following an existing
pattern, a change whose blast radius you cannot state without looking.

Route: **analyze → plan → implement → review → verify**. Workspace with `plan.md`.

## T3 — Architectural

The shape of the system changes.

Signals: a new domain or boundary, a change in dependency direction, a new external
dependency or service, a persistence or data-shape change, a change that touches an
invariant in `RULES.md`, or a decision with real alternatives worth recording.

Route: **discover → design → HUMAN GATE → implement → architecture review → verify →
consolidate**. Workspace with `design.md`; the gate is a full stop (see SKILL.md).

## T4 — Critical

A mistake is expensive and hard to undo.

Signals: authentication, authorization, secrets; destructive or irreversible data
operations; migrations on live data; money, billing, compliance; anything with no
rollback path; a security fix with a known exploit.

Route: **discover → specify → alternatives → design → HUMAN GATE → implement →
independent review → regression and security verification → consolidate**. Workspace
with `spec.md` and `design.md`; review runs in a fresh context.

## Tie-break

- Unsure about **scope** (how much code it touches): choose the lower class and
  re-classify when it grows. Cheap process first.
- Unsure about **risk** (what a mistake costs): choose the higher class. A wasted review
  is cheaper than an unreviewed migration.
- A task that is trivial to write but hard to undo is not T0. Risk sets the floor.

## Re-classification

Classification is a first estimate, not a verdict. When a task turns out bigger:

```
.ai/scripts/jig task set <id> class T3
```

Then run the stages the new class requires that were skipped: at minimum design and its
gate for T3, specify and alternatives for T4. Say plainly that the class changed and why.
Never keep a T1 route on work that turned out to be T3.
