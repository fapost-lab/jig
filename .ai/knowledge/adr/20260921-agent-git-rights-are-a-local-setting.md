---
id: adr-20260921-agent-git-rights-are-a-local-setting
type: adr
status: accepted
date: 2026-09-21
domains:
  - config
  - task
  - skills
paths:
  - scripts/lib/config.sh
  - scripts/lib/task.sh
  - skills/jig-consolidate/SKILL.md
  - scripts/lib/common.sh
summary: Why agent.git (none|commit|push|pr, later merge) is read only from the clone's local config, and why jig task ship does the git work up to that level.
reviewed_at: 2026-09-22
---
# Whether an agent commits, pushes or opens a pull request is a per-clone setting, and a script ships the change

## Context

"Agents do not commit" was never a rule a script checked. ADR-0029 wrote it down for this
repository — the human reads the diff and commits it, and agent-made commits reviewed as pull
requests were rejected by the human for this project — and `jig status`, `task list` and
housekeeping's comments came to treat uncommitted files as the human's review queue. The
documentation site already said the opposite in general: whether the agent may commit is the
project's rule, not Jig's. The only grant that existed was prose in a personal `CLAUDE.local.md`,
which no script and no Codex session can read.

The autopilot specification (2026-09-18) needs the other answer: a user who trusts the process
wants a finished task back as an open pull request, not as chores. Its stress test named the
failure to avoid: commit rights granted in one clone must not leak into the project, or every
contributor's agent starts committing.

## Decision

- **`agent.git: none | commit | push | pr`**, cumulative: `commit` commits to the task's branch,
  `push` also pushes it, `pr` also opens a pull request into the task's base. The default `none`
  is the behaviour before this decision. No level merges, and none will: merging, and closing the
  task after it lands (ADR-0030), stay with the human.
- **The key is local-only.** It is read from `.ai/config.local.yaml` (ADR-0038) and never from
  `.ai/config.yaml`: `JIG_CFG_LOCAL_ONLY_KEYS` names keys `cfg` answers from the local layer and
  the default alone. A value in the project file is ignored, and `jig status` and `jig doctor` say
  so. By ADR-0023's test the answer differs between contributors, and a committed one would be
  the leak the specification names.
- **A script ships, not the skill.** `jig task ship <id> --message-file <file>` commits what the
  agent staged, pushes the task's branch and opens the pull request into its recorded base, each
  step only as far as the level allows, and prints where it stopped. It refuses, changing nothing,
  when the knowledge decision is not recorded (ADR-0030 becomes a check), on a branch other than
  the task's or on its base, and when anything under `.ai/workspace/` or `.ai/runtime/` is staged.
  It never stages, never forces a push, never skips hooks; an existing pull request is reported,
  not duplicated; with no usable forge the pull request is the human's. At `none` it exits 3, which
  the skill reads as "hand the change to the human".
- **The agent chooses what is staged.** Which hunks belong to the task is a judgement
  (ADR-0022), so `ship` commits the index as it is and never runs `git add`.
- **`jig-consolidate` ships** after the knowledge decision is recorded. The human gates of T3 and
  T4 are unchanged; git rights do not waive them.
- **`jig status` names the review queue** the level implies: uncommitted files at `none`, unpushed
  commits at `commit`, pushed branches at `push`, open pull requests at `pr`. The per-worktree
  `uncommitted=<n>` stays; it is a fact at every level.

## Alternatives

- **Skills call git themselves, reading the level through a config command.** Fewer lines of
  script, but the level, the base and the ADR-0030 order would be a request to a model in every
  skill that ships. The autopilot specification requires stops that a script enforces.
- **The key in both layers, like the housekeeping keys.** Rejected: a committed value grants rights
  to every contributor.
- **A project ceiling (`config.yaml` limiting what a local value may grant).** Deferred, not
  rejected: nobody has asked for it yet, and the autopilot specification keeps the same question
  open for waiving the human gate; the two are decided together.
- **`ship` stages everything (`git add -A`).** Rejected: it would sweep in another task's work.
- **Prose in `CLAUDE.local.md`.** Rejected: scripts and Codex cannot read it, and `jig status` would
  keep calling uncommitted files the queue.

## Consequences

- A clone without the key sees no change. With `agent.git: pr` a finished task ends in an open pull
  request into its own base, an epic's task included.
- A worktree holding committed-and-pushed work is still kept by housekeeping only for uncommitted
  changes or a lock; nothing about retention changed.
- Pushing an epic and opening a specification's final pull request are not covered: `jig spec epic`
  and `jig-idea` still name those steps as the human's (task `agent-git-epics`).
- ADR-0029's "Agents here do not commit" is now the `none` level of this setting, not a rule.

> **Amendment (2026-09-22).** The consequence left open above is decided: spec work ships by the same
> level through `jig spec ship`, and the git steps both commands take live in `common.sh`
> (adr-20260922-spec-work-ships-by-the-agent-git-level).

> **Amendment (2026-09-22).** "No level merges, and none will" is superseded: `agent.git: merge` merges
> the pull request `task ship` opened, only on green CI with at least one check, at the shipped commit,
> never with `--admin` or `--auto` and never past branch protection; closing the task after it stays the
> human's except in an unattended autopilot run
> (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci). The key stays local-only, and so are
> `agent.ci_timeout` and `autopilot.unattended`.

> **Amendment (2026-09-22).** One more local-only key: `autopilot.parallel` (1–16, default 2), how
> many tasks of a roadmap phase a phase run has agents building at once. It is personal for the same
> reason `agent.git` is — how many agents may work unwatched on one machine is not the project's
> call — and `agent.git` below `pr` refuses a phase run outright
> (adr-20260922-a-phase-run-is-coordinated).
