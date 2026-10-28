---
id: adr-20261029-a-task-reads-a-neighbouring-repository-through-a-link
type: adr
status: accepted
date: 2026-10-29
domains:
  - task
  - knowledge
paths:
  - scripts/lib/context.sh
  - scripts/lib/common.sh
summary: "Why a task names a neighbouring repository's task or spec with a Linked: line, how jig context lists those documents and tracks them in the ledger, and why Jig only reads the neighbour."
reviewed_at: 2026-10-29
---
# ADR: A task reads a neighbouring repository's task or spec through a link

## Context

A Jig project often lives next to other Jig projects: fapost-core keeps its package
repositories under `packages/<pkg>`, each a separate git repository with its own `.ai/`, ignored
by Core's `.gitignore`. On 2026-10-28 Core filed `tenant-decommission`, whose groundwork — the
contract Core implements and the list of what to delete — lay in fapost-saas's task
`tenant-suspend-delete` (`task.md`, `design.md`). `jig context` in Core reads only Core's own
`.ai/knowledge/`, and a task workspace is gitignored, so the agent started from nothing and asked
questions the neighbouring task had already answered, until a person pointed at it.

Nothing in Jig read another repository's state before. The case needs three things: a way to
write "this task continues that one" that a later command can reuse (moving a task to another
repository, `task-move-updates-roadmap`, names its target the same way); a place in the reading
an agent already does at every stage; and a way to see that the neighbour's document changed
after it was read.

## Decision

**A task links a neighbouring repository's task or spec with a `Linked: <ref>` line in its
`task.md`. `jig context resolve` for that task lists the linked documents, marked by source, and
the context ledger tracks them like required knowledge.**

- **The reference** is `<repo>#<task-id>` or `<repo>#spec/<spec-id>`, parsed in one place,
  `jig_task_ref` in `scripts/lib/common.sh`; `jig_task_ref_dir` finds what it names and
  `jig_task_links` lists a task's `Linked:` lines. `<repo>` is a path relative to the clone's
  main checkout (`jig_config_clone_root`), never to a worktree: a worktree lacks what the main
  checkout ignores, `packages/` among it. `..` is allowed — a neighbour may sit beside the
  clone — while an absolute path, `~`, a drive letter, a backslash, whitespace and a second
  `#` are not. The ids follow `jig_valid_id` before any path is built from them.
- **Resolve** prints, after the `workspace:` lines, one `linked:` line per document that exists:
  the absolute path and, in parentheses, the reference as written. A linked task gives its
  `task.md` and the artifacts `workspace:` lists for the task itself; a linked spec gives
  `spec.md` and `roadmap.md`. A link that reaches nothing — no directory there, no such task or
  spec, a line that does not parse — prints `linked: <ref>  unreachable: <why>`, and resolve
  still exits 0: another clone or another machine is the ordinary case, not an error.
  Only a task's resolve reads links; `--no-task` never does, so a spec or a workspace is still
  not knowledge (ADR-0035). The lines are not cached.
- **The ledger** (ADR-0015) tracks every linked document that exists. `jig context acknowledge`
  takes an absolute path only when it is one the task's links give at that moment; `pending`
  and `guard` owe a reading of a linked document as of a required one; resolve marks a linked
  document whose hash differs from the acknowledged one `changed since acknowledged`. A
  document that cannot be reached is not tracked — a reading of nothing cannot be owed — and
  resolve has already said why. A link back to the task itself gives nothing (`unreachable: this
  is the task itself`): its own artifacts are never tracked (ADR-0015). A linked document is hashed in its own directory: git on
  Windows cannot read an absolute path through stdin.
- **Jig only reads the neighbour.** Nothing is written there, there is no back-link, and the
  neighbour's version is not checked: what is read is whatever its checkout holds.

## Alternatives

- **Name the repository in configuration, or by its remote.** Rejected: a setting someone must
  fill in (zero-config), and a remote carries no workspace at all — it is gitignored and exists
  only on the machine that filed the task.
- **A path from the worktree, or an absolute path.** Rejected: a task worktree has no
  `packages/` unless it shares it, and an absolute path is true on one machine only.
- **One task spanning several repositories.** Rejected: a task's state, branch, review, ship and
  pull request belong to one repository; the change it would need is everywhere. A task in each
  repository with a link is a line to delete if it is wrong.
- **A second record of what was read from the neighbour.** Rejected: the ledger already records
  readings by hash and the guard already enforces them; a second record would be a second rule
  for the same question.
- **Make linked documents knowledge** (resolve them for every task, or copy them in). Rejected:
  a task's notes and a spec are plans, not descriptions of the system (ADR-0035); only the task
  that names them owes them a reading.
- **A `task new --link` flag.** Not now: `task new --from` takes the task's own document, and
  the `Linked:` line goes into it; the `jig-task` skill says to write it.

## Consequences

- A task with a link owes a reading of the neighbour's documents before implement and review,
  and again after the neighbour changes one.
- The ledger now holds absolute paths for linked documents. It is per clone and never committed,
  so a machine-specific path costs nothing; RULES.md names `_ctx_check_knowledge_path` as the
  one place such a path is accepted.
- The review receipt does not pin linked documents: it hashes the task's knowledge, not the
  neighbour's notes. A neighbour's document edited after review leaves the receipt current;
  the next `resolve` marks it `changed since acknowledged` and `guard` owes a new reading, but
  `task ship` does not refuse on it. Folding linked documents into the receipt is left for a
  later task, should a missed edit ever ship.
- On a clone without the neighbour, or with the neighbour's workspace absent, the agent is told
  plainly that the link reaches nothing; a spec, being committed, travels better than a task.
- `task-move-updates-roadmap` reuses `jig_task_ref` for its target; a new reader of a reference
  calls the same function, never its own pattern.
