# Handing a stage to a helper

Jig names the roles; the person names the model. `jig task route <id>` prints a line for each
stage they chose to hand over:

```
delegate: implement -> sonnet (claude.implement_model)
delegate: review -> sonnet (claude.review_model)
```

`review` covers every review of the route: review, a T4's independent review and a T3/T4's
architecture review. The value is the person's, written for their runtime; Jig never reads it.

## With a `delegate:` line, in Claude Code

Start a subagent for that stage with the value as the `model` of the call, exactly as printed —
never a name you prefer, never a corrected spelling. Give it the task id, the worktree, the base,
the stage's skill to follow, and the design or plan it implements against. It runs the skill
whole: it acknowledges what it read, enters findings and writes the receipt itself. You read its
report, check the ledger with `jig task findings <id>`, and carry the route on.

- The implementer and the reviewer are never the same subagent, and the reviewer never sees the
  implementer's conversation.
- A fix after review goes back to an implementer; the re-review is a new reviewer.
- If the runtime refuses the model, say so in one line and do the stage without it. Choosing
  another model is the person's decision, not yours.

## Without one

No line, another runtime, or no way to start a subagent (you are one): do the stage yourself, as
before. Where a skill asks for a review in a fresh context, that still holds — a subagent on the
session's own model, or, where none can start, the same session saying so in the pull request.

## What is never handed over

Classification, discovery and design, the human gate, decisions nobody made, `jig verify` and
the task's sign-off, consolidation and `jig task ship` stay with you. A helper changes who does a
stage, never the route: findings still block, a receipt still goes stale, verify still asks for
evidence. That is what makes a cheaper model safe to hand a stage to.
