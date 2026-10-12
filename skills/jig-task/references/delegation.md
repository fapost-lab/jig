# Handing a stage to a helper

Jig names the stages. The person chooses a model in their local settings. `jig task route <id>`
prints the choices for each configured runtime:

```
delegate: implement -> sonnet (claude.implement_model)
delegate: review -> gpt-6.1-sol (codex.review_model)
```

Use only lines whose key names the **current session's runtime**. A Claude Code session reads
`claude.*`; a Codex session reads `codex.*`. Lines for another runtime do not ask this session
to launch it. Cross-runtime handoff is a separate capability. `review` covers every review in
the route: T2 review, T4 independent review, and T3/T4 architecture review.

## With a matching line

Start a new subagent for the entire stage, with the value exactly as printed as its model.
Give it the task id, worktree path, base, stage skill, and approved design or plan. It runs
the skill itself, reads the relevant knowledge, records findings and the review receipt, and
returns a report. The coordinator checks `jig task findings <id>` and the receipt before
continuing. Never treat the subagent's final message alone as stage evidence.

The implementer and reviewer are different subagents. A reviewer starts with a fresh context
that does not include the implementation conversation. A fix after review goes to the
implementer; a re-review uses a new reviewer.

### In Codex

Request a Codex subagent explicitly with the printed model and a fresh context. Put the task
id, worktree, base, skill and necessary design or plan in its initial brief; do not rely on
inherited conversation. Wait for its result and check Jig's files. Do not silently choose a
replacement model. If subagent tools are disabled, the model is refused, or creation fails,
**stop this stage and report the reason**. The current session must not complete a stage for
which a Codex model was explicitly selected. In particular, it must not sign its own review
as if an independent reviewer ran.

### In Claude Code

Start a subagent with the printed model. If Claude Code refuses the model, say so in one line
and follow the existing Claude fallback: do the stage without that model. Choosing a different
model remains the person's decision.

## Without a matching line

The current session does the stage as before. Where the route asks for a review in a fresh
context, use a subagent on the session's model; if none can start, say so in the pull request.
No setting is required for a normal Jig route.

## What stays with the coordinator

Classification, discovery and design, the human gate, undecided choices, `jig verify` and
the task's sign-off, consolidation and `jig task ship` stay with the coordinator. A helper
changes who does a stage, not the route or its records.
