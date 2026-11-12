---
id: adr-20261110-a-follow-up-answers-its-own-threads
type: adr
status: accepted
date: 2026-11-10
domains: []
paths:
  - scripts/lib/pr.sh
  - "skills/jig-pr-review/**"
  - tests/pr.t.sh
  - scripts/lib/prgitlab.sh
summary: Why jig pr followup reads the earlier review's head and open threads back from the forge's markers, keeps or reports the reviewed commit after a force-push, takes new comments only from lines added since it, and replies fixed/open in each thread on GitHub and GitLab.
reviewed_at: 2026-11-12
---
# A follow-up reads its earlier review back from the forge and answers each of its own threads

## Context

Phase 2 of `.ai/specs/pr-review/` asks for a second review after the author pushed fixes. It must
reply "fixed" or "still open" in each thread the first review opened, and take new findings only
from what changed. The first review leaves no state the follow-up can rely on:

- Without Jig in the reviewed repository, the state lives in `<git-common-dir>/jig/pr/<n>/`.
  `jig pr cleanup` deletes it, and the follow-up may run in another clone.
- `jig pr fetch` moves `refs/jig/pr/<n>/head` to the new head. The commit reviewed then hangs on
  nothing in the clone. After a force-push it hangs on nothing on the forge either.

What survives is on the forge. Every part jig posted carries
`<!-- jig-pr-review id=<hash> head=<sha> part=<k> -->`
(adr-20261109-a-review-is-posted-as-it-was-shown). That marker names the head it reviewed.

## Decision

`jig pr followup <n> [--login <login>]` runs after `jig pr fetch` of the new head. It reads the
earlier review back from the forge.

- **Whose review.** The login is the one the fetch proposed, or `--login` when it asked. It is
  confirmed as `check` confirms it: gh's own token for that login, or glab's account, and
  `GET user` must name it. Only that login's markers count.
- **What it reads.**
  - On GitHub: the reviews and review comments of the pull request, each with `in_reply_to_id`,
    `original_line`, `side`, `original_start_line` and the lines of its body, through gh's
    `--jq`.
  - On GitLab: every note of every discussion, not only the first.
  - A marker's `head=` must be 40 (or 64) lowercase hex. The function that reads it checks this
    before the value reaches git. A marker that fails is not ours.
- **The head to follow** is the head of the latest marker (by creation time) whose head is not the
  one fetched now.
- **Threads.**
  - A thread is a top-level comment of jig's on an earlier head: on GitHub one without
    `in_reply_to_id`; on GitLab a discussion whose first note carries a marker with `part ≥ 1`.
  - A thread is closed by a reply of the same login, on an earlier head, whose marker says
    `verdict=fixed`. Every thread not closed is listed, so a third round picks up what the second
    called still open.
  - Replies posted on the current head never close a thread. A follow-up that was half posted
    therefore lists the same threads again.
- **The commit reviewed is kept or said to be gone.**
  - When the clone still holds it, it is pinned at `refs/jig/pr/<n>/reviewed`.
  - Otherwise jig fetches it by its id from the record's remote, with the fetch's own flags.
  - Otherwise it is `unreachable`. The output says so: each thread is judged against the new head,
    and new findings come from the whole diff.
  - Unreachable never stops the follow-up. Losing the interdiff costs precision, not the review.
- **What it prints.**
  - `interdiff:` (`git diff <follows> <head>`).
  - `range-diff:`, when the old head's merge base with the base branch differs from the
    review's: a rebase. Both are measured from the same commit — on GitHub the pull request's
    own base commit the fetch recorded (`pr_base_sha`), so a base that moved alone is no rebase.
  - Each thread, `=== thread <k> <pos> <path>`, with its URL and the earlier comment's text.
  - The earlier summary. Findings the first review moved there have no thread, and the
    follow-up's own summary answers them.
  - The author's replies are not printed: they are data, read on the forge.
- **The `followup` file** in the pull request's state directory records the login, the head it
  was read for, `follows`, `reviewed` (available or unreachable), the old merge base, and
  `thread: <k> <id> <pos> <path>` per thread.
- **The draft follows up** with the header `follows: <sha>`, which must be the `followup` file's,
  read for the reviewed head. It answers with blocks `=== reply <k> fixed|open`.
  - Every thread gets exactly one reply.
  - `reply` without `follows` is refused.
  - The body is the person's text; the script writes no verdict prose. The marker carries the
    verdict.
- **New findings only from the interdiff.** A `comment` of a follow-up is an `R` comment, and its
  range must take in a line that was added both since `follows` and since the merge base (`git
  diff -U0`, no renames). The second condition removes lines that a rebase brought in from the
  base. With the commit reviewed unreachable, no such check is possible, and none is made.
- **Replies are parts of the version shown.**
  - They follow the comments as parts `NC+1…`, each marked `part=<j> verdict=<v>`.
  - `check` shows each one as `=== reply <k> <verdict> <pos> <path>, thread <id>` and adds
    `follows:` to the header. The thread's id is in the text and so in the hash.
  - `post` posts the review as before (one COMMENT review on GitHub, one discussion a part on
    GitLab), then each reply as a call of its own: `pulls/<n>/comments/<id>/replies` on GitHub,
    `merge_requests/<n>/discussions/<id>/notes` on GitLab, through `--input`.
  - The first refusal stops the replies on both forges. A rerun posts only what is missing.
  - A reply counts as landed only in the thread it was shown for. A reply in another thread is
    `misplaced`: it is reported and never posted again. `posted` records the replies' ids too.
- **Cleanup** also deletes `refs/jig/pr/<n>/reviewed` at the commit it holds, and the file
  `followup`.

## Alternatives

- Keeping the old head in the local record — rejected: cleanup removes the record, a reboot
  removes nothing but the follow-up may run in another clone, and the forge already holds it in
  the marker.
- Following only the latest review's comments — rejected: a finding called still open in round
  two would drop out of round three.
- A fixed English "Fixed." / "Still open." line written by the script — rejected: the review is in
  the person's language (ADR-0023 keeps language out of configuration). The verdict is
  machine-readable in the marker, and the skill puts it in words on the reply's first line.
- An interdiff of `follows..head` alone — rejected: after a rebase it holds the base's changes to
  the same files, and a "new finding" there would be about code the author did not write.
- Refusing a follow-up when the old head is unreachable — rejected: a force-push is the common
  case the spec names; the threads can still be judged against the new code.
- Replies inside the GitHub review (`comments[].in_reply_to`) — rejected: GitHub's review API takes
  positions, not replies, and a reply endpoint per thread keeps each answer where it was shown.

## Consequences

- RULES.md's deletion paragraph names the third ref and the `followup` file.
- `references/draft.md` gains `follows:` and `=== reply`. Version 1 stays: a draft without
  them means what it did.
- Tests stand in for gh and glab. The force-push test removes the commit from the clone (reflog
  expiry and `gc --prune=now`) and serves it from a bare origin with `uploadpack.allowAnySHA1InWant`.
  It then removes it there too.
- Not checked live yet (an unattended run touches no forge):
  - that GitHub and GitLab keep the marker in a reply and return it;
  - the two reply endpoints on a real pull and merge request;
  - `in_reply_to_id`, `original_line` and `original_start_line` on comments a push made
    outdated;
  - whether GitHub and GitLab serve `git fetch <sha>` of a commit a force-push left unreachable;
  - `range-diff` and the `+<sha>:refs/…` refspec under Git Bash.
