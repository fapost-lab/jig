---
id: adr-20261002-route-depth-is-a-personal-choice
type: adr
status: accepted
date: 2026-10-02
domains:
  - task
  - config
  - skills
paths:
  - scripts/lib/task.sh
  - scripts/lib/config.sh
  - scripts/lib/status.sh
  - skills/jig-task/SKILL.md
  - skills/jig-review/SKILL.md
  - skills/jig-autopilot/SKILL.md
summary: Why the depth of a task's route (full or lean) is a personal, local-only choice with a per-task override, why lean trims only analysis, plan and a second review round, and why nothing that gates reads the depth.
---
# How much of its class's route a task runs is a personal choice, and the class stays its floor

## Context

The routes of ADR-0009 were run end to end on autopilot for a release: a T2 took 40 to 70
minutes, a T3 about 75, of which 15 to 20 were CI. The owner asked how much faster the work would
be without the design, the plan and the review rounds. Switching process off wholesale was
rejected: a class is a risk assessment, and the stages that hold it — tests, CI, the gate, the
findings ledger, consolidation — are what makes a mistake cheap. What remained was a handle on the
stages that cost time without changing the assessment, for the person whose time it is.

ADR-0009 rejected letting the human pick the process mode per task, as ai-factory does, because it
puts the burden back on the person and picks by effort rather than by risk. This decision keeps
both halves of that reasoning: the class stays the rubric's answer and is never lowered, and the
default asks nothing of anybody. What a person may pick is only the part of a route that does not
hold the class's risk (ADR-0009, amendment of 2026-10-02).

## Decision

- **Two depths, `full` and `lean`, and `full` is the default.** Nothing has to be set: a project
  that never heard of the key runs every route exactly as before (zero-config).
- **The person's setting is `route.depth`, local-only.** It is in `JIG_CFG_LOCAL_KEYS` and
  `JIG_CFG_LOCAL_ONLY_KEYS`: a value in `.ai/config.yaml` is ignored and reported, because a
  committed value would trade every contributor's review depth for time on their behalf — the
  reason `agent.git` is local-only. `jig config set route.depth lean --local` accepts `full` or
  `lean`; `jig_route_depth` reads it.
- **A task may differ.** `jig task new <id> --lean` records `route_depth: lean` in the task's state;
  `jig task set <id> route_depth full|lean` changes it. A task's own key wins, the setting answers
  otherwise. Neither is pinned when a run starts: changing the depth changes the stages still ahead,
  and that is the person's choice to make.
- **One resolver, one table.** `_task_route_depth` (task.sh) answers the depth and where it came
  from (`task` or `route.depth`); `_task_route_stages` holds the only table of routes the scripts
  know, and `_task_artifact_route` (`jig task artifacts`) asks it for the depth too, so a lean T2
  is not told it waits on a plan. `jig task route <id>` prints the class, the depth, the route and what lean trims; the skills
  name what it prints rather than computing a route themselves (ADR-0001). `jig status` marks a
  lean task `depth=lean` and the status page badges it; `jig task autopilot <id> start` and
  `report` print `depth: <depth> (<source>)`. They consume the resolver; none recomputes it.
- **What lean trims.** T0: nothing. T1: the analysis is a few lines in `task.md`, not a document of
  its own. T2: the plan is part of the analysis. T2 to T4: one review round — P2 and P3 stay `open` in
  the ledger and go to the pull request instead of being fixed. T3/T4 otherwise keep every stage.
- **The floor is held by what already gates, and nothing that gates reads the depth.** `jig verify`
  on changed files, CI before a merge (`jig_ship_merge`), both consolidation records (ADR-0030), the
  T3/T4 gate, the architecture review, and the findings ledger are unchanged. In particular a P0 or
  P1 that was fixed still blocks until a re-review closes it
  (adr-20260921-review-findings-block-completion), so "no re-review" holds only when the round found
  nothing blocking — at T2 as at T3/T4. The class is never lowered by a depth.
- An invalid value — a hand-written `route.depth: light`, or a `route_depth` nobody validated —
  reads as `full`: a mistake costs process, never a stage.

## Alternatives

- **A project key.** One person's trade of review for time would apply to the whole team.
- **A process mode the person picks per task (ai-factory's `fast`/`full`/`ultra`).** Rejected by
  ADR-0009 and still rejected: a mode replaces the class, a depth only trims what the class leaves
  optional.
- **Lean as a lower class.** A class is the answer to what a mistake costs; a preference cannot
  change that answer, and every floor keyed by class would move with it.
- **Skills only.** Each skill would carry its own copy of the route table, and neither `jig status`
  nor the autopilot report could show the depth.
- **Always record the depth at `task new`.** Tasks filed before the feature would carry none, and a
  changed setting would not reach tasks already filed. An absent key that means "follow the setting"
  is simpler and needs nothing filled in.
- **Scripts refusing a skipped stage.** Scripts do not run stages (ARCHITECTURE.md); the floor is
  already enforced where a skipped stage would show — the ledger, the receipt, verify, ship.
  (Superseded on 2026-10-04: the floor was not held for the gate, which nothing read. The completion
  gates now refuse a route whose recorded stages are missing, reading the class's `full` route from
  `_task_route_stages`; see adr-20261004-a-route-stage-is-proven-by-its-record.)

## Consequences

- A person can buy time per task or for all their work without a way to buy it below the class.
- The skills must name the route from `jig task route`, not from the class table: a skill that reads
  the table alone runs the full route and is merely slower, never less safe.
- P2/P3 findings left open at lean accumulate in the pull request rather than in the code; their
  record is the ledger and the PR body.
- Undoing it is local: drop the key from the two lists, the subcommand, the status note and the
  skill lines. A leftover `route_depth` in a state file is harmless; a leftover `route.depth` in a
  local file is reported as `ignored:` and removed with `jig config unset`.
