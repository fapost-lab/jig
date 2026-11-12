---
id: adr-20261110-an-idea-draft-waits-outside-git
type: adr
status: accepted
date: 2026-11-10
domains:
  - spec
paths:
  - scripts/lib/spec.sh
  - "skills/jig-idea/**"
summary: Why an idea's conversation is kept in a gitignored draft until its spec is committed, where it lives in the clone, and why only the spec's committing ship or a person's drop removes it.
reviewed_at: 2026-11-10
---
# An idea's conversation waits in a draft outside git until its spec is committed, and only that commit or a person removes it

## Context

`jig-idea` writes nothing until the human says the idea is ready to be written down
(adr-20260930-a-spec-lives-on-its-own-branch-from-the-first-minute, amended 2026-11-10). That
amendment left one gap open: a conversation cut short before the yes — a closed laptop, a crashed
session, the human stopping for the day — left nothing on disk, and the next session started from
nothing. The conversation is the expensive part of a spec: the decisions, the rejected options
and their reasons, the agent's proposals and what became of each.

The human set two constraints at the start (2026-11-10): the agent keeps the draft on its own,
without asking — "here a human is certainly not needed" — and a draft is never removed
automatically: "only a person can give the command to delete".

## Decision

- **Where.** `.ai/workspace/ideas/<id>/draft.md` in the clone's main checkout
  (`jig_config_clone_root`), so a session in a task worktree and one in the main checkout see the
  same drafts. Where a clone has no main checkout to find — its git common directory is not named
  `.git` — under `<git-common-dir>/jig/ideas/<id>/`, as the revision is kept
  (`jig_config_odd_common`, adr-20261016-the-clone-revision-is-a-claimed-name as amended): there
  every checkout is its own clone root, and a draft written in a task worktree would go with it.
  Ignored by git, outside `.ai/specs/`, with no branch: the tree stays clean and nothing waits to be
  shipped. Free-form, in the human's language — it is theirs to read, as a task's workspace is.
- **Who writes it.** The agent, after every answer to a round, the whole draft replaced, through
  `jig spec draft write <id>`; `jig spec draft rename` when the spec's id turns out different;
  `jig spec draft list` shows them, and `jig status` counts them on a `drafts:` line printed only
  when there is one.
- **How it leaves — two ways, no third.**
  1. `jig spec ship <id>` in `declare` mode moves the draft of the same id to trash right after its
     commit moved HEAD, and says `draft consumed`. Not at `spec new`: the files are still the
     templates then, and a session cut between `spec new` and filling them in would lose the
     conversation. Not after the push: a ship whose push or pull request fails is rerun, commits
     nothing the second time and would never come back for the draft. A ship that commits nothing,
     and the `epic`, `final` and `remove` modes, leave the draft where it is. A failure to move it
     warns and never fails the ship.
  2. `jig spec draft drop <id>`, run only when the human asks for it.

  Housekeeping never walks `.ai/workspace/ideas/` and removes no draft for its age.
- **No revision raise.** A draft write marks only the status page dirty, not the clone revision
  (schemas/json.md): no `--json` read reports a draft, and a write per round would make every
  concurrent `--revision` write stale for nothing.

## Alternatives

- **The draft in `.ai/specs/<id>/` on `spec/<id>`, uncommitted.** Rejected: a branch and a dirty
  tree from the first minute, which is what the amended adr-20260930 moved away from; and a spec is
  written in the project's durable language while the draft is read by the human.
- **Consumed by `spec new`.** Rejected: see above, the templates are still empty then.
- **The agent deletes the draft after writing the spec.** Rejected: a step that holds only as long
  as the agent remembers it; the ship does it instead.
- **Housekeeping clears drafts past an age.** Rejected by the human: only a person removes one.
- **A `jig idea …` command family.** Rejected: a draft is a spec before it is born; a second
  namespace for four subcommands buys nothing.
- **A draft per circle, with its summary.** Rejected at the gate: on deep, a session cut in the third
  round would lose two rounds of answers.
- **`spec draft show`.** Rejected at the gate: `list` prints the path, and the file is read as a file.

## Consequences

- A conversation cut short loses at most the round in progress; the next session opens with
  `jig spec draft list` and goes on from the draft.
- **Two cases leave a written spec's draft behind**: at `agent.git: none` the ship exits 3 before
  it commits, and a spec on an epic is shipped by the epic, whose mode commits nothing. The draft
  then stays until a person drops it; the skill says so and names `jig spec draft drop <id>`. This
  is not maintenance that depends on someone remembering (RULES.md, scope): nothing breaks or
  grows dangerous while a draft waits — `jig status` counts it and `draft list` says a spec of that
  id exists — and removing it is the human's by their own rule. If the count turns out to bother
  people, the way back is to consume a draft when a spec of its id is seen committed, not to age it
  out.
- **A ship of an existing spec consumes that spec's draft** whatever the commit carries — a roadmap
  rewrite at filing time, say — so a draft an earlier session left unwritten would go to trash with
  it. The skill makes the agent check `draft list` before filing and settle such a draft first; the
  script cannot tell the difference. Trash keeps it for `trash_ttl`.
- In a clone with no main checkout to find, a draft dropped or consumed inside a task worktree goes
  to that worktree's trash and leaves with the worktree before `trash_ttl` runs out. Accepted by the
  human (2026-11-10): the draft has already gone legitimately by then, only the window to take it
  back is shorter, and a trash under the git common directory would make housekeeping delete in a
  new place — a change to RULES.md's deletion invariant, out of proportion to a rare layout.
- Trash gains a third kind of entry, `idea-<id>` (ADR-0006 as amended).
- Reverting the change leaves existing drafts as harmless ignored files that nothing reads.
