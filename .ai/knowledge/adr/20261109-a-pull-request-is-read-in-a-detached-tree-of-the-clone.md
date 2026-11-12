---
id: adr-20261109-a-pull-request-is-read-in-a-detached-tree-of-the-clone
type: adr
status: accepted
date: 2026-11-09
domains: []
paths:
  - scripts/lib/pr.sh
  - "skills/jig-pr-review/**"
  - tests/pr.t.sh
  - scripts/lib/prgitlab.sh
summary: Why jig pr reads a pull request in refs/jig/pr/<n>/ and a detached .pr-<n> worktree of the person's clone with hooks off, where the review state lives, and what cleanup may delete.
reviewed_at: 2026-11-12
---
# A pull request is read in a detached tree of the person's clone, and nothing of its head runs

## Context

`.ai/specs/pr-review/` asks Jig to review a colleague's pull request — one that is not a Jig task,
in a repository that may not have Jig at all — and to show the review as it would be posted. The
manual run it grew from (SRD-2498, 2026-10-30) fetched the head by hand into a tree beside a dirty
checkout on another branch, found the real base, reviewed, and removed the trees and refs at the
end. Three forces shape the mechanics:

- The person's clone is theirs: its HEAD, index, branches, remote-tracking refs and `FETCH_HEAD`
  hold their work, and nothing about a review may move them.
- The head is written by somebody else. Its hooks, scripts and instructions reach a machine that
  holds the person's forge tokens, and a relative `core.hooksPath` (`.githooks`, `.husky`) makes
  `git worktree add` run the head's own `post-checkout`.
- Housekeeping removes worktrees and branches unattended, on evidence it infers itself; a tree it
  did not make must neither be taken for a task's nor be removed by it.

## Decision

`jig pr` (`scripts/lib/pr.sh`) does the mechanics; the `jig-pr-review` skill does the judgement.

- **The forge comes from the URL.** `https://<host>/<owner>/<repo>/pull/<n>`; owner and repository
  in GitHub's characters, `<n>` digits without a leading zero. Not `jig_forge_kind`, which answers
  for `origin` and fails as a whole when one `gh` account is broken. A GitLab merge request URL
  is taken since adr-20261110-a-merge-request-review-is-posted-as-discussions, which says how
  GitLab differs. One `gh api --hostname <host>` call, filtered by gh's own `--jq`, names the base
  branch and the head.
- **A local clone is required.** The remote is the first whose configured URL reaches the same
  host and `<owner>/<repo>` (https, ssh, scp form, `.git` or not, case aside, an SSH alias
  resolved).
- **Refs of Jig's own.** `git fetch --no-tags --no-recurse-submodules --no-write-fetch-head` with
  two explicit refspecs, `refs/pull/<n>/head` and the base branch, into `refs/jig/pr/<n>/head` and
  `refs/jig/pr/<n>/base`, with `--refmap=` so that git does not also move
  `refs/remotes/<remote>/<base>`. Nothing under `refs/heads/` or `refs/remotes/`, no `--prune`. A fetched
  head that is not the head GitHub named is refused: the pull request moved.
- **A detached worktree beside the repository**, at `<git.worktree_root>/.pr-<n>`. The leading dot
  is outside `jig_valid_id`'s grammar, so no task's worktree can ever be made at that path, and a
  path there that is not such a worktree is refused rather than reused.
- **Nothing of the head runs.** Every git call on the repository in `pr.sh` goes through `_pr_git`, which passes
  `-c core.hooksPath=/dev/null` (a file, under which no hook can exist) and
  `-c submodule.recurse=false`, with `GIT_LFS_SKIP_SMUDGE=1`. `jig pr` refuses to run in a review
  tree (a checkout named `.pr-<n>` that is not the clone's main one): there the hooks path,
  `.ai/config.yaml` and `.ai/scripts` are the author's. The skill reads; it runs no test, build or
  `jig` from the head and starts no session in its tree.
- **Rules from the base.** The fetch records the base branch's tip and the merge base apart; the
  skill reads `AGENTS.md`, `.ai/knowledge/` and the like at the base commit with `git show`.
- **GitHub's diff sets the merge base** (amended 2026-11-12, fapost-lab/jig#491). The merge base is
  measured from the pull request's own base commit (`.base.sha`, recorded as `pr_base_sha`), not
  from today's tip of the base branch: that is the diff GitHub shows and `comments check` asks the
  compare API for, and a base that took part of the pull request since (a branch cut from `main`
  into a `staging` that `main` is merged into) would otherwise move it, and every check would refuse
  until the author pushed. A commit the clone does not hold is fetched by its id into
  `refs/jig/pr/<n>/pr-base`, which cleanup takes back; a fetch that cannot get it refuses. When
  today's base gives a narrower diff, the fetch prints it beside, as `own change:`, for reading
  only: comments are placed on GitHub's diff. GitLab's merge base already came from its diff
  (adr-20261110-a-merge-request-review-is-posted-as-discussions).
- **State in the clone.** The record (what was fetched, the reviewed head, the candidate login)
  and the draft go to `.ai/workspace/pr/<n>/` when Jig is installed and git ignores that path, and
  otherwise to `<git-common-dir>/jig/pr/<n>/` — inside the clone, out of its working tree. Never
  into the PR's tree (ADR-0008).
- **The draft is one checked file**, kept with its CRs dropped and printed whole: what
  `jig pr draft` prints is what the person sees and what the posting item will post. Its format
  (version 1) is written in `skills/jig-pr-review/references/draft.md`, not under `schemas/` where
  the formats Jig's scripts read usually live (ADR-0028): the agent writes this file in projects,
  and `schemas/` is not installed there, while a skill's references are.
- **`gh` is needed for the whole command**, not only for merge detection as ADR-0002 describes
  it: `jig pr fetch` refuses without it — and without `glab` for a GitLab merge request. Jig as a
  whole still needs only git.
- **Cleanup takes back only what fetch made.** The worktree by `git worktree remove` without
  `--force`, at the one path built from a checked number, only while git lists it there detached
  and unlocked — git refuses one with changes, and then the refs and the record stay too; what
  git leaves behind on Windows goes through `jig_worktree_leftover`. The two refs by
  `update-ref -d` at the commit each holds when read. The record and the draft by name, then
  `rmdir`.
- **Housekeeping does not touch them.** It walks task workspaces, worktrees with a task's branch,
  `refs/heads/` and `refs/remotes/origin/`; a detached `.pr-<n>` and `refs/jig/pr/*` are none of
  these, and `fetch --prune` prunes only its own refspec. It does not report them either:
  `jig pr list` does. `_task_worktree_holds` still counts the PR's tree as a checkout of the
  repository, which is safe: the links it judges are ones Jig makes itself, in task worktrees,
  and Jig never runs inside the PR's tree.

## Alternatives

- A separate temporary clone per review — rejected in the spec: every review downloads the
  repository again.
- `refs/remotes/<remote>/pr/<n>` or a local branch — rejected: those namespaces are the person's
  and other tools', and a branch would be swept by housekeeping as soon as it looked like Jig's.
- `<worktree_root>/pr-<n>` — rejected: a task may be named `pr-7`.
- A temporary directory for the state without Jig, as the spec first said — rejected here: the
  next command (`draft`, `cleanup`, the posting item) must find it again, and a temporary directory
  is gone after a reboot. `<git-common-dir>/jig/` is where Jig's own tree already lives.
- Running nothing but trusting hooks to be absent — rejected: a relative `core.hooksPath` is a
  common setup, and the hook comes from the very commit being reviewed.

## Consequences

- RULES.md's deletion paragraph names `jig pr cleanup`.
- A forgotten review stays until `jig pr cleanup`: a detached tree and two refs, no data at risk.
- The posting item (`pr-review-github-post`) reads the record and the draft from the same place
  and adds its own checks — diff positions, the hash of what was shown, the head unchanged.
- A follow-up (adr-20261110-a-follow-up-answers-its-own-threads) adds a third ref,
  `refs/jig/pr/<n>/reviewed`, and a `followup` file; cleanup takes both back the same way.
