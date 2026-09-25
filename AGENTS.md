# Jig (Agent SDLC Framework) — agent instructions

This repository *is* the framework and also uses it (dogfooding). Follow the process
described in the durable knowledge under `.ai/knowledge/`.

## Jig first

Each row is a moment where a runtime offers its own way of doing the same thing. The middle
column is the way; the right-hand one is what it replaces.

| When you need to | Use | Instead of |
|---|---|---|
| Take on work someone described | the `jig-task` skill | starting to edit code straight away |
| Decide how much process the work needs | the risk test in the `jig-task` skill | reading a class off one word in the route table |
| File the work as a unit | `jig task new <id>` | the runtime's own background tasks (`spawn_task` in Claude Code): they open another session, not a task with a route, a workspace and consolidation |
| Get a branch for the task, or a tree of its own | `jig task start <id>`, or `jig task start <id> --worktree` | `git checkout -b`, `git worktree add` |
| Find what to read for the files you touch | `jig context --files <files>` | grepping `.ai/knowledge/`, or reading all of it |
| Write one of the task's documents | `jig task artifact write <id> <kind> --from <file>` | your editing tools on a path under `.ai/workspace/` |
| Show the work is done | `jig verify` | running the test commands yourself |
| Reach a commit and a pull request | `jig task ship <id> --message-file <file>` | `git commit`, `gh pr create` |

Keep this table short: eight rows get read; twenty stop being read, exactly as prose does. A
session to-do list (`TodoWrite` and the like) is deliberately absent — it is a draft for one
session, not a unit of work, and nothing here replaces it.

## Read first

- `.ai/knowledge/GLOSSARY.md` — use canonical terms.
- `.ai/knowledge/RULES.md` — invariants; do not violate.
- `.ai/knowledge/adr/` — accepted decisions; propose a new ADR instead of silently
  contradicting one.
- `README.md` — what Jig is, in short; `docs/` — the user documentation site
  (https://jig.fapost.in), where how Jig is used is described; `CONTRIBUTING.md` — how Jig is
  developed.

## Workflow

Start work with the `jig-task` skill; it classifies the task by risk and names the route.
Stage skills can also be used directly: `jig-analyze`, `jig-implement`, `jig-review`,
`jig-verify`, `jig-consolidate`, `jig-architecture-review`.

Three skills sit outside the task routes. Two populate knowledge rather than change
code: `jig-map` proposes per-domain knowledge, and `jig-accept` decides what is proposed.
A proposed document is invisible to `jig context` until a human accepts it, so knowledge
someone wrote but nobody agreed to reaches no agent — `jig status` reports the count on
its `proposals:` line, and `jig knowledge proposed` lists it. The third, `jig-idea`, works
before a route: it stress-tests an idea and keeps the result as a specification with a
roadmap under `.ai/specs/<id>/`. A specification is a plan, not knowledge, so `jig context`
never resolves it — `jig status` counts specs on its `specs:` line, and `jig spec list`
lists them with their roadmap progress. A spec released once, at the end, is built on an epic branch
(`jig spec epic`): its tasks are cut from the epic and their pull requests go into it.

`jig-autopilot` runs one task's route without waiting between stages and stops only where a
human is needed; the route, the gates and `agent.git` stay what they are.

`jig-setup` asks a person, one question at a time, how far their agent may go on its own and
writes the answers to their gitignored `.ai/config.local.yaml` through
`jig config set --local`; it never writes `.ai/config.yaml`.

**Three questions decide the class**, asked about this change being wrong after it shipped:
what takes it back; how far the mistake reaches — this repository, or users, money, somebody
else's system; and who finds it — a test and the next run, or the person it hurt. The class is
the **highest** one whose answers fit; the full test, with examples, is in the `jig-task` skill.

| Class | Route |
|---|---|
| T0 trivial | implement, verify, consolidate |
| T1 local | analyze, implement, verify, consolidate |
| T2 structural | analyze, plan, implement, review, verify, consolidate |
| T3 architectural | discover, design, human gate, implement, architecture review, verify, consolidate |
| T4 critical | discover, specify, alternatives, design, human gate, implement, independent review, verify, consolidate |

Every route ends in consolidation, and a task with a workspace ends it in two records
(ADR-0030). Before the commit, the knowledge decision — `NO_DURABLE_KNOWLEDGE` included —
is recorded with `jig task set <id> knowledge_consolidated true`. After the change has
landed, when `jig status` counts it under `needs consolidation`, the task is closed with
`jig task set <id> status consolidated`. A merge alone never closes a task.

Risk sets the floor: a one-line change to authentication is not trivial. When a task
turns out bigger, re-classify with `jig task set <id> class Tn` and run the stages the
new class requires.

## Working rules

- Durable artifacts are written in English: `.ai/knowledge/`, `README.md`, `docs/`, this file,
  skills, scripts, code comments and commit messages — everything that leaves the machine.
- Task artifacts under `.ai/workspace/tasks/` are written in the language their reader
  thinks in. They are gitignored and read by the person at the human gate, so English buys
  nothing there and costs them time.
- Any decision that changes architecture, distribution, lifecycle semantics or safety
  of destructive operations gets an ADR (`adr/YYYYMMDD-<slug>.md`, frontmatter per ADR-0004).
- Scripts: POSIX sh / bash 3.2, no mandatory dependencies besides `git` (ADR-0002).
  Every script command has a test under `tests/`.
- Skills are short; mechanics go to scripts (ADR-0001).
- Adding or renaming anything framework-owned — a skill under `skills/`, a profile, a
  template — is not finished until `jig upgrade` has placed it. This repository installs
  itself in link mode, so a new skill exists in `skills/` but not in `.claude/skills/` or
  `.codex/skills/` until then, and no runtime can see it. `jig verify` refuses to run
  while anything is pending, and `jig status` reports the count.
- A release is written down as it is made: the pull request that raises `JIG_VERSION` adds that
  version's section to `docs/changelog.mdx` — a line or two per user-visible change. CI's
  `changelog` job refuses a pull request that declares an unreleased version the page does not
  describe.
- Task-specific notes live in `.ai/workspace/tasks/<id>/` (gitignored), never in the repo.
- Before finishing a task, ask: what here should survive the task? Update
  `.ai/knowledge/` accordingly, or state `NO_DURABLE_KNOWLEDGE` — and record the decision
  in task state (`jig-consolidate`), not only in `plan.md`. Knowledge frontmatter is
  maintained by `jig knowledge new|paths|reviewed`, never by hand.
