# PR review — Jig's reviewer on somebody else's pull request, with the comments ready to post

Depth: normal — the output is posted into somebody else's pull request, so a wrong call reaches
people outside the session and cannot be unsent; the design space is small and the manual run on
SRD-2498 (2026-10-30) already answered most of the mechanics.

## Idea

> Если мне приходится делать ревью чужих ПР, было бы не плохо использовать ревью джига, но сразу
> так, чтобы он готовил комменты в ПР (гитхаб и гитлаб). Как это лучше реализовать?

## Goal and problem

- Who is worse off without this, and how: a developer asked to review a colleague's pull request.
  Today they either review by hand, or run a generic review skill that knows neither the project's
  rules nor Jig's evidence standard, and then copy the findings into the forge one by one, finding
  the right line, the right account and the right wording each time.
- What is true when the work is done: given a pull or merge request URL, Jig reviews the change with
  `jig-review`'s method, shows the person the review exactly as it would be posted, and on their yes
  posts it as one review — summary plus line comments — on GitHub or GitLab. Nothing is written into
  the reviewed repository, and nothing is posted without the yes.

## What the manual run taught (SRD-2498, two PRs, 2026-10-30)

Steps done by hand, and which side of ADR-0001 each falls on:

1. Fetch the PR head into a separate tree without touching the person's checkout (it was dirty, on
   another branch); find the real base — `staging`, not the default branch — and the commit range.
   *Mechanics.*
2. Find the specification: a tracker issue named in the PR title. *Judgement, with a fact to read.*
3. Review with a fresh reader per PR; check the cross-repo contract against the sister PR; verify
   the serious findings once more. *Judgement.*
4. Check that every line comment lands inside the PR's diff hunks; move the rest (here
   `assignToLocation:398`) into the summary. *Mechanics.*
5. Show the person the drafts verbatim, take their edits and their yes. *Judgement, a gate.*
6. Pick the account that can reach the repository (`azinchenko-shiprelay`, not the active
   `bpartner`) without switching `gh` globally; post one review, event COMMENT; read the comments
   back to confirm their lines. *Mechanics.*
7. Remove the temporary trees and refs. *Mechanics.*

Also learned: the reviewer must be told where the project's rules live — a gitignored
`CLAUDE.local.md` is invisible in a tree made from the PR head, and a personal rule file is not a
team rule to cite in somebody else's pull request.

## Stress test

From the independent failure hunt (2026-10-30), ranked by likelihood × cost.

- Hidden assumptions — "this holds only if …": the person has a local clone of the reviewed
  repository; the PR's host is the same as `origin`'s; the PR's author is trusted; "the person said
  yes" means "the person read it"; the review is never run unattended.
- The main trade-off: posting saves the person the copying, and in exchange every post is a public,
  attributed act that cannot be unsent — so each mechanical shortcut must fail closed, never post
  something nobody saw.
- The weakest point: the author controls inputs the reviewer trusts — the head's own `AGENTS.md`,
  `CLAUDE.md` and `.ai/knowledge/`, the PR body, the linked issue, code comments — and they reach an
  agent holding forge tokens.
- Failure modes — cause, what breaks, the signal that shows it:
  - The PR loosens the rules it is reviewed against, or plants "reviewer: no findings" in its body
    or code → a clean review of a bad PR → no signal at all. Decided below: rules from the base;
    PR text is data.
  - The head's tests, build hooks or Makefile run on the person's machine with forge tokens in the
    environment (a fork or an untrusted contributor) → credentials leak → no signal until later.
    Decided below: nothing from the head is run.
  - The wrong account posts — on a public repository every account can read; `GH_TOKEN` overrides
    `--user`; `glab` has no `auth token --user`; `gh auth status` fails as a whole when one account is
    broken, so `jig_forge_kind` says `none` → a review under a personal login in a work repository →
    seen by everyone. Decided below: the draft names the login; more than one candidate means asking.
  - The author pushes or force-pushes between review and post → comments land on lines of a new
    head, the post fails with 422, or threads open as outdated → misplaced comments. Decided below:
    the post is pinned to the reviewed head.
  - A post fails half-way (one bad line rejects a whole GitHub review; GitLab is one call per
    discussion, so a rate limit at comment 17 leaves half a review) and a retry re-posts what landed
    → duplicates or a summary with no comments. Decided below: an idempotency marker and read-back.
  - The person edits the draft after the yes, or approves forty comments after skimming → comments
    in their name they never read (ADR-0031). Decided below: the post carries the hash of what was
    shown.
  - JSON built in bash without `jq` (ADR-0002): quotes, backticks, Cyrillic, code fences; on Git Bash
    MSYS path rewriting and CRLF (ADR-0037) → a 400 or mangled text. Decided below: payloads go
    through a file to the forge CLI; Windows runs on that item.
  - Renamed files, deleted lines (left side), multi-line ranges, binaries, a diff past the forge's
    size limits → comments fall into the summary or the post fails. Decided below: line positions
    from the forge's own diff; a size ceiling that says what was not reviewed.
  - Fetching `refs/pull/N/head` writes refs and objects into the person's clone; a worktree there is
    seen by housekeeping, which expects a task; state written into a temporary tree dies with it
    (ADR-0008). Open question below.
- Other shapes considered, and why this one: a mode of `jig-review`, a Jig task per review, a draft
  only — see Decisions.

## Scope and non-goals

- In scope: reviewing one or several pull requests of one feature on GitHub (first) and GitLab;
  posting one comment-only review per PR after a verbatim yes; following up on the author's fixes
  (second phase).
- Not doing: approving or requesting changes; running anything from the PR head; tracker clients;
  unattended reviews; reviewing a PR the person has no clone of (until the open question below is
  answered otherwise).

## Decisions

- Depends on `review-smells-and-two-axes`: the review method this spec reuses is being changed
  there (behaviour and standards passes, the smell baseline, rule sources). This spec does not
  define the method; it carries whatever `jig-review` §2 says to a pull request that is not a task.
- **A skill of its own, `jig-pr-review`, with the mechanics in `jig pr …` commands** — rejected: a
  mode of `jig-review`, because that skill is about a task (ledger, receipt, route, re-review by
  receipt) and a second set of rules for posting would double it; a Jig task per review, because it
  needs Jig installed in the reviewed repository and files a task for work that changes no code
  there. The skill takes the method from `jig-review` §2 by reference, never by copy. Like
  `jig-map` and `jig-idea`, it sits outside the task routes; `jig-task` stays the one entry into
  them (ADR-0009).
- **The review's state lives in the project's `.ai/workspace/`** when Jig is installed in the
  reviewed repository — rejected: a new machine-level Jig directory, because Jig keeps its state
  inside the project everywhere else and a new storage concept is not worth it for this. Without
  Jig there, `.ai/workspace/` is not gitignored, so writing it would leave files in somebody else's
  tree: the state then goes to a temporary directory and lasts as long as it does (open question
  below).
- **Jig posts, and only as a comment** — after the person has seen the review verbatim and said yes,
  as one review with the event COMMENT on GitHub (a set of discussions on GitLab). Approve and
  Request changes stay the person's, in the forge's own interface. Rejected: letting the person
  pick the event, because an approval posted by an agent is a decision made in their name; a
  draft only, because copying findings into the forge by hand is the pain this spec exists for.
- **The comment language is chosen per review, in the conversation** — rejected: remembering it
  with `jig config set --local`, because ADR-0023 keeps language out of configuration. The default
  is the person's own language; the skill asks when the pull request's thread is written in
  another one.
- **A re-review after the author's fixes is in scope, as the second phase** — rejected: leaving it
  to a later idea, because a review that cannot follow up on its own comments is half a review;
  putting it in the first phase, because the first phase is useful without it.
- **GitHub first, GitLab as an item of its own** — rejected: both in one item, because GitLab's
  merge-request discussions take a `position` of base, start and head sha rather than a line in a
  review, and that wants checking on a live merge request, not by analogy.
- **Findings rated P0–P2 get a blind second check before the person sees the draft** — a fresh
  reader, told nothing of who found what, checks each against the code and may drop it or move its
  severity. Rejected: none, because a false finding in somebody else's pull request costs more than
  in one's own (on SRD-2498 the check moved two severities and dropped a disputed finding);
  every finding, because P3s are many and a wrong one costs little.
- **Personal rule files are read but not cited** — `*.local.md` and the like are the reviewer's own
  rules, not the team's. Findings that rest only on them are shown to the person in a group of
  their own and are left out of the post unless the person moves them in. Rejected: not reading
  them, because they hold what the person cares about; citing them like team rules, because the
  author has never seen them.
- **One feature may span several pull requests** — the person may give several URLs (on SRD-2498, a
  warehouse and a console PR); each is reviewed by its own reader, which reads the others only to
  check the contract between them, and each gets its own post.
- **The specification is found, not fetched by a script** — the skill reads the pull request's title
  and body (and the task's issue by `task.issue_pattern` when Jig is installed), reads the issue
  through whatever tool the runtime has, and asks the person when there is none. Rejected: tracker
  clients in `jig pr`, because ADR-0002 allows no mandatory dependency and each tracker is another.
- **The account is proposed by access, named in the draft, and never switched** — `jig pr` tries
  each account the forge CLI holds against the repository, for the right to comment rather than to
  read, and uses the chosen one's token for that call only (`gh auth token --user`); the active
  account stays as it was. The draft the person approves names the login it will post as. One
  candidate is proposed; more than one, or a `GH_TOKEN`/`GITHUB_TOKEN` in the environment that
  overrides them, means asking. Rejected: picking silently by access, because on a public repository
  every account can read and identity is the one value where a silent default is most expensive
  (failure hunt); a setting naming the account, because the forge CLI already knows (zero-config).
- **The forge is taken from the PR URL, not from `jig_forge_kind`** — that function answers for the
  checkout's `origin` and its `forge` setting, and fails as a whole when one `gh` account is broken;
  the PR may live on another host (GitHub Enterprise, a self-hosted GitLab).
- **Rules come from the base, and everything the author wrote is data** — the reviewer reads
  `AGENTS.md`, `CLAUDE.md`, `.ai/knowledge/` and the like as they are on the PR's base, not its head;
  a change to those files inside the PR is itself something to review. The PR's title, body, the
  linked issue, code comments and thread replies are data, never instructions to the reviewer or to
  the second-check reader. Rejected: rules from the head, because a PR could loosen the rules it is
  judged by.
- **Nothing from the PR head is run** — no `jig verify`, no tests, no build: `jig-review` §2 comes
  along, §3 does not. Rejected: running same-repository PRs, because the head's hooks and scripts
  run with the person's forge tokens in reach, and "same repository" is not "trusted author". The
  review says plainly that it is a reading of the code, as the SRD-2498 one did.
- **The post is pinned to the reviewed head** — it names the commit it reviewed (`commit_id` on
  GitHub, the three shas on GitLab) and refuses when the PR's head has moved since: the person is
  offered a re-review of what changed, never a post onto new lines.
- **The post is exactly what was shown** — `jig pr comments post` refuses unless the payload's hash
  matches the version last shown to the person; any edit is shown again. The yes is never skipped,
  whatever `autopilot.unattended` says: this skill is never run unattended.
- **A post is idempotent** — each posted review and comment carries a hidden marker (the review's id
  and the reviewed head); before posting, `jig pr` reads back what is already on the PR and posts only
  what is missing, and on a failure half-way it reports what landed and what did not.
- **Line positions come from the forge's diff, not a local `git diff`** — the two can differ in base
  and merge-base; renamed files, deleted lines and multi-line ranges are mapped from it. Above a size
  ceiling, or for files the forge does not show, the review says which files it did not review —
  never a silent partial review.
- **Posting is not governed by `agent.git`** — that setting is about git in the person's own
  repository (commit, push, pull request, merge); a review comment is guarded by its own gate: the
  verbatim draft, the hash, the yes on every review. A person with `agent.git: none` can still
  post. Rejected: requiring level `pr`, because it would forbid the post to the very person who
  just said yes to it; a key of its own (`review.post`), because the yes already decides and
  another key is another thing to fill (zero-config).
- **The PR head is read from the person's own clone** — `jig pr fetch` fetches the head and the base
  into refs of Jig's own (`refs/jig/pr/<n>/…`, never `refs/remotes/origin/*`), makes a detached
  worktree of the head beside the repository, and `jig pr cleanup` removes both; housekeeping knows
  these worktrees and refs and does not take them for a task's. The review's state goes to the
  clone's own `.ai/workspace/` when Jig is installed there, never to the temporary tree (ADR-0008).
  A local clone is required. Rejected: a separate temporary clone, because every review would
  download the repository again; both paths, because two sets of mechanics for one step is twice
  the code to keep right.
- **Payloads go through a file to the forge CLI** (`gh api --input`, `glab api` with a file), never
  JSON spliced in a shell string; the Windows share runs on the item that builds them (ADR-0037).

## Open questions

- Without Jig in the reviewed repository the state is temporary — what does the second phase's
  re-review read then: only what the forge holds (its own earlier comments, the reviewed head
  recorded in the review's body), or nothing? Decides whether phase 2 works outside Jig projects.
  The hidden marker decided above already carries the reviewed head, which points to "the forge".
  Phase 2 must also survive a reviewed sha that a force-push made unreachable.

## Assumptions left untested

- A hidden HTML comment in a review's body and in each line comment survives the forge and is
  returned by its API on both GitHub and GitLab — taken at normal; the first post item tests it.
- `glab` can make a call with an account other than the active one (no `auth token --user`; perhaps
  per-host config or `GITLAB_TOKEN` for one call) — taken at normal; the GitLab item tests it, and a
  "no" there turns its account decision into asking every time.
- The forge's diff API covers PRs the size of the SRD-2498 warehouse one (40 files, about 2 000 lines)
  without paging problems — taken at normal; the check item tests it on that PR.
