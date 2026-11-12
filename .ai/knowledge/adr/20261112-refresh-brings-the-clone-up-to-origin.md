---
id: adr-20261112-refresh-brings-the-clone-up-to-origin
type: adr
status: accepted
date: 2026-11-12
domains:
  - housekeeping
  - knowledge
paths:
  - scripts/lib/refresh.sh
  - scripts/lib/status.sh
  - scripts/lib/knowledge.sh
summary: Why jig refresh fetches and fast-forwards the base without moving the checkout or refusing a dirty one, why reads say how old the clone's view of origin is, and why a decision origin's base already holds reads as landed.
---
# ADR: `jig refresh` brings the clone up to origin, and reads say how far behind it is

## Context

Jig's `--json` reads never touch the network (adr-20261015-a-read-is-one-json-envelope), so whether
anything landed on origin is as of the last fetch, and a fetch happened only in housekeeping (once a
day by default) or in commands that need one. On 2026-11-12, in fapost-lab/core, a person merged the
pull request of `knowledge/decisions` (#346, by squash). Jig UI went on showing the four decisions as
"Kept, waiting; pushed, no pull request yet", since neither clone had fetched since. After a fetch
the waiting write was gone, but the base here was still five commits behind: the four stubs in the
checkout still held the old `source_hash`, read as `changed`, and were offered to be decided again,
`decidable: true`. Nothing in the reads said the view was old, and Jig UI may run no git of its own
(every change it makes is a jig command), so the only way out was a terminal — what the page exists
to spare a person.

## Decision

- `jig refresh [--json]` is the one command a program runs to make what it shows current. It fetches
  origin as housekeeping does (`_hk_fetch`: the clone's account, no prompt, `--no-prune`), bounded by
  `jig_net`, then fast-forwards `git.base_branch` to `origin/<base>`, and does nothing else.
- The base moves only forward, and never by moving the person's checkout. Checked out here, by
  `git merge --ff-only` with `merge.autoStash` off (a `post-merge` hook of theirs still runs, as on
  any merge); checked out nowhere, by `git branch -f`, which git itself refuses for a branch any
  worktree has checked out, rebases or bisects — so a person on a task branch keeps their branch and
  files; checked out in another worktree, or when git cannot list the worktrees, not at all
  (`checked-out-elsewhere`, naming it). Ahead or diverged, not at all. Never stash, reset or force.
- A dirty checkout is not refused. Git refuses a fast-forward that would overwrite a change —
  staged, unstaged, or an untracked file it would create — and that refusal is the answer
  (`blocked-by-changes`, git's message naming the files); changes it does not touch do not stop it.
  `jig upgrade --land` refuses any tracked change, because it may switch the checkout's branch;
  refresh never does.
- Refresh is not a git right of `agent.git`: it commits and pushes nothing, and fetches as
  housekeeping does at every level, so it runs at `none` too. adr-20261104's "a write never moves
  the person's checkout" is about Jig's own write branches; refresh moves the person's base, only
  forward, and never their checkout.
- A base that cannot move is an answer, not a failure: the command exits 0 and `base.outcome` says
  why, so a program shows it in words. A fetch that fails is an answer too (`fetch.outcome:
  failed`); the base step then works on what the last fetch left.
- `jig status --json` carries `origin`: `fetched_at` — the newest non-empty `FETCH_HEAD` of every
  worktree of the clone, Jig's own trees included, since each worktree keeps its own. Any fetch
  writes it, of any branch, so it says when the clone last reached origin, not that the base came
  back with it; a failed fetch empties its file, which loses the fetch before it there. Jig keeps no
  stamp of its own — and `behind` / `ahead` of the base against `origin/<base>`. While `behind` > 0 an
  attention item `base-behind-origin` names `jig refresh`. Still no network.
- The knowledge reads give a document that waits for a decision here, and that `origin/<base>`
  already decided, `decidable: false` with `reason: landed`: a proposal no longer `proposed` there,
  a stub rejected there, or a stub approved there at the text its source has there and here. The
  difference must be the base's: a document this checkout changed since its fork point (a branch
  that proposes it again) is never landed. Only documents that differ from the base are read. `jig status`'s `proposals:` and `sources changed:` leave them
  out. This is what keeps a person on a task branch from being asked again after a refresh that
  moved the base by `update-ref`, whose files in the checkout did not change.

## Alternatives

- **Jig UI runs `git fetch` / `git pull` itself**: its own rule is that every change it makes is a
  jig command, and every program would repeat the same refusals.
- **Reads fetch on their own**: every refresh of a page would reach the forge, and a read stops
  being something one runs as often as one likes.
- **`jig housekeeping` as the button**: it also sweeps branches and trash, refreshes the forge
  cache, checks for a release, and runs on a cadence; it does not fast-forward the base.
- **Refuse any dirty tree, as `jig upgrade --land` does**: a person nearly always has a change
  somewhere, so the button would nearly never work; git already protects every change the
  fast-forward would touch.
- **Check the base out when the person is on another branch**: it moves their checkout;
  `git branch -f` moves the branch alone.
- **`git update-ref` with the old value**: guards the race between the check and the move, but
  moves a branch a worktree is rebasing or bisecting, which `worktree list` shows as detached;
  `git branch -f` refuses those, and the old value is checked just before it.
- **Exit with a refusal code when the base cannot move**: a program would read an expected state
  (changes in the checkout) as a failure.
- **A stamp file Jig writes on each fetch**: misses every fetch Jig did not make (a person's `git
  pull`, an editor's background fetch); `FETCH_HEAD` sees them all.

## Consequences

- A program shows how old its view is (`origin.fetched_at`), offers `jig refresh` while
  `base-behind-origin` stands, and may run it when its page opens.
- `landed` is a third reason beside `not-on-base` and `not-on-branch`; a decision sent anyway is
  refused by the checks the write makes in its own tree, as a decision already made.
- A write that merged by squash and whose files the base changed again afterwards still reads as
  waiting after a refresh; closing it through the forge is task `refresh-closes-landed-writes`.
- The counts `jig status` saved for the page are as old as that run; `knowledge_counts_at` says so.
