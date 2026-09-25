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

It prints `autopilot: on (unattended)` when this clone set `autopilot.unattended: true`: then
the run asks nothing, and §5 replaces §3. Say in one line what will happen: the class, the
route, and where the run will end — merged with `agent.git: merge`, an open pull request with
`pr`, or "ready for your commit" with `none`. Offer to
open the status page with `.ai/scripts/jig status --open`, where the human can watch the run
and sees first what it needs from them.

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

In an unattended run there are no stops: §5. Otherwise, on a stop, record it, tell the human in plain words what you need from them, and wait:

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

A reason says **what you need from the human**, and nothing about the state of the task.
It is written once and never rechecked, while the task moves on: a reason that reported
"no pull request" or "verify has not been run" was still saying it hours after both had
happened. The state the page derives itself, fresh, in the cards around the stop.

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

## 5. Unattended: ask nothing

The person who set `autopilot.unattended` cannot answer a stop. Each one becomes the safe
default below, recorded so they read it in the pull request, in plain words, not in jargon:

| Stop | Instead |
|---|---|
| The gate of a T3/T4 task, or a re-classification into one | Write the design as usual, then `jig task gate <id> approved --by agent`, `jig task autopilot <id> approve --reason "<what was approved>"`, and in `task.md` (`jig task artifact append <id> task --from -`): "Human gate — approved by the agent (unattended)". Put `design.md` verbatim in the pull request under `## Design — approved by the agent, not a human` |
| A decision nobody made | The most cautious option that is easiest to undo. `jig task autopilot <id> decide --reason "<what you chose, and why>"` |
| A destructive operation | Never. Find another way or leave that part out, and say so with `decide --reason` |
| `repair` exited 3 | The run ends unfinished: stage what there is and run `jig task ship <id> --message-file <file> --draft`. The body starts with `Not finished: <why>`. A draft is never merged; the run stays `stopped`, and the status page shows it waiting |

What never changes: a P0/P1 is never dismissed, the gates are never worked around, and nothing
is merged but by `task ship`. Before shipping, put `jig task autopilot <id> report`'s
**Decided without you** and **Approved by the agent, not a human** blocks in the pull request
body as they are. At `agent.git: merge`, `task ship` merges once CI passed or prints
`not merged: <why>` — both are a finished run; say which. After `merged`, close the task
(`jig-consolidate` §6) without asking, then `end`.

## 6. A roadmap phase

"Run phase N of `<spec>` on autopilot" is a **phase run**: a whole wave of the roadmap at once,
each task built by its own agent in its own worktree, while you act as the **coordinator**. The
mechanics — the loop, the prompt each task agent gets, what to do when one fails — are in
[phase-run.md](references/phase-run.md). Three things hold whatever happens:

- **The coordinator writes no code.** You file the wave, start the agents, ship each task and
  keep the merge queue. The work itself is theirs.
- **A task agent touches neither the spec nor the forge.** It never edits `.ai/specs/`, never
  runs `jig spec done` (the script refuses in its branch) and never runs `jig task ship`. It
  ends at consolidation, with the change staged and its commit message written.
- **A stop holds the next wave, not this one.** The wave in flight finishes; the question goes
  to the person in one message, in your session, and the wave after it waits for the answer.

It needs `agent.git` at `pr` or better and a spec built on an epic. Without either, refuse the
phase run, say which is missing, and offer to run the phase's tasks one at a time instead.
