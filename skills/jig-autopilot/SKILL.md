---
name: jig-autopilot
description: Run one Jig task through its whole route without waiting between stages, stopping only where a human is needed, and hand back an open pull request or a stop that names what is needed. Use when the user says "autopilot", "take this on autopilot", "do it end to end", "finish it without me", or hands over a task to be done unattended.
---

# jig-autopilot — one task, start to finish

The route is the same as without autopilot. What changes: you go from stage to stage without
asking "shall I continue?", and you stop only where this skill says. Asking for autopilot is
the human's consent for this one task; how far you may go with git is `agent.git`, as always.

## 1. Start

Classify, file and start the task with `jig-task` (or resume one that is filed). Then:

```
.ai/scripts/jig task autopilot <id> start
```

Say in one line what will happen: the class, the route, and where the run will end —
an open pull request with `agent.git: pr`, or "ready for your commit" with `none`.

## 2. Run the route

Run each stage's skill in order, and mark it as you enter it:

```
.ai/scripts/jig task autopilot <id> stage <analyze|plan|implement|review|verify|consolidate|...>
```

- **Review in a fresh context.** Hand review (and architecture review) to a subagent that has
  not seen the implementation, with the task id, the base and the skill to follow. It records
  findings and signs the receipt; you fix, set `fixed`, and send it back to re-review.
- **Each repair costs one attempt.** A repair is one loop of fixing after a blocking finding or
  a red verification, then reviewing or verifying again. Before starting one:

  ```
  .ai/scripts/jig task autopilot <id> repair --reason "<what failed>"
  ```

  Exit 3 means the limit (2 per run) is used up and the run is stopped. Do not try again.
- **The gates are not obstacles.** When `status ready`, the knowledge decision or `task ship`
  refuses, the refusal is the process working: go back to the stage it names.

## 3. Stop only here

On a stop, record it, tell the human in plain words what you need from them, and wait:

```
.ai/scripts/jig task autopilot <id> stop --reason "<what is needed>"
```

| Stop | What you ask |
|---|---|
| The human gate of a T3/T4 task | Approve, change or reject the design — shown as [show the document](../jig-task/references/show-the-document.md) says |
| `repair` exited 3 | How to proceed: another approach, dismissing the finding (a P0/P1 only with them), or dropping the task |
| Re-classification to T3 or T4 | The gate for the new design. Up to T2, continue and say so in the report |
| A decision nobody made | The decision: a product choice not settled in `task.md`, the spec or knowledge. Never guess one |
| A destructive operation | Permission, or another way |

Destructive means: `push --force`, `reset --hard`, `clean`, deleting a branch or a stash,
rewriting published history, deleting files outside the task's own change, migrating or
deleting data, and anything the runtime asks permission for that the human has not given.
The scripts cannot see your commands — this stop is yours to keep.

After the human answers:

```
.ai/scripts/jig task autopilot <id> resume
```

It resets the repair count: the human gave the run a new direction. Continue from the stage
you stopped in.

## 4. End

Finish with `jig-consolidate`: it records the knowledge decision and ships the change as far
as `agent.git` allows. Then:

```
.ai/scripts/jig task autopilot <id> end
.ai/scripts/jig task autopilot <id> report
```

Hand back the pull request link (or "ready for your commit") and the report, and put the report
in the pull request body when you write it. Closing the task after the merge stays as
`jig-consolidate` §6 says.
