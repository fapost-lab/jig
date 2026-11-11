---
id: adr-20261110-a-merge-request-review-is-posted-as-discussions
type: adr
status: accepted
date: 2026-11-10
domains: []
paths:
  - scripts/lib/pr.sh
  - "skills/jig-pr-review/**"
  - tests/pr.t.sh
  - scripts/lib/prgitlab.sh
summary: Why jig pr posts a GitLab merge request review as one discussion per part with a base/start/head position from GitLab's diff, reads glab's JSON itself, keeps glab's own account, and counts a part landed only where it was shown.
reviewed_at: 2026-11-11
---
# A merge request review is posted as one discussion per part, read back by marker and position

## Context

`.ai/specs/pr-review/` posts a review on GitHub and GitLab. The GitHub half
(adr-20261109-a-review-is-posted-as-it-was-shown) posts one review with the event COMMENT. GitLab
has no review object of that kind in its API. A comment on a line of a merge request is a
discussion of its own, and its `position` names three commits of GitLab's diff: base, start and
head. So a post is one call per part, and it can stop half-way. `glab`, the CLI that holds the
person's GitLab account, differs from `gh` in three ways that matter here:

- `glab api` has no `--jq`, so its answers reach the shell as JSON.
- It keeps one account per host, and there is no `auth token --user`.
- A line in a position needs one number on each side the line exists on: an added line has only a
  new number, a deleted line only an old one, and a context line both. Hunk headers alone do not
  give that.

## Decision

`jig pr` takes a GitLab merge request URL, `https://<host>/<group>[/<sub>…]/<project>/-/merge_requests/<iid>`.
Everything adr-20261109-a-review-is-posted-as-it-was-shown decides holds for it: the review is
posted only as it was shown (by hash), only on the reviewed head, after the person's yes, through
a file, with a hidden marker, and never by a switched account. What differs:

- **The forge comes from the URL.** The record says `forge: gitlab` and keeps the project's
  numeric id, and every later call uses that id. A record without `forge:` is GitHub's. The head
  is fetched from `refs/merge-requests/<iid>/head`, and the target branch from the base.
- **GitLab's diff sets the merge base.** `fetch` takes the merge base from the merge request's
  `diff_refs.base_sha`, not from today's tip of the target branch. It refuses when that commit is
  not below the head in the clone, or when `diff_refs.head_sha` is not the head it fetched.
  `check` and `post` refuse when `sha` or `diff_refs.head_sha` has moved from the reviewed head,
  or when `base_sha` is no longer the recorded merge base. The text shown names `base` and
  `start` in its header, so a diff GitLab made again is a new version to show.
- **glab's JSON is read by jig.** Every call is `glab api --hostname <host> --output ndjson`, one
  value a line. `_pr_json_lines` reads it: a small awk reader under `env LC_ALL=C` that prints
  `<path><TAB><value>` per scalar. It decodes strings (`\uXXXX` into UTF-8; a newline starts a
  continuation line). A value it cannot read prints `!`, and every reader refuses on that. No
  `jq` (ADR-0002). A file name holding a newline is refused, as on GitHub. Markers are found by
  `jig-pr-review id=`, so an HTML-escaped `<!--` does not hide them.
- **Positions come from the hunk bodies.** `merge_requests/<iid>/diffs` (or `/changes` before
  GitLab 15.7) gives each file's `diff` text. A hunk header counts only at the start of a line,
  and `\ No newline` lines are skipped. Each line of a hunk is recorded as context, added or
  deleted. A position is `position_type: text` with the three shas, `old_path`/`new_path`, and
  `new_line`, `old_line` or both, by that line's kind. A comment must lie in one hunk, as on
  GitHub; one outside is moved into the summary with the fixed line
  `Not in GitLab's diff, so not commented on: …`. The files GitLab does not show are those it
  calls `too_large`, those with no hunk (unless only renamed), and, past its `changes_count`
  (`1000+` is its own ceiling), those the local diff has and its list does not.
- **A range is posted at its last line.** GitLab's `line_range` needs a `line_code`, a SHA-1 of
  the path. Jig has no SHA-1 of a string without a new dependency (`jig_hash` is git's object
  hash). `R17-20` is therefore posted on `R20`, and the text shown says so:
  `=== comment R17-20 <path>, at R20`. The hash covers that line.
- **The account is the one glab keeps for the host.** Each call runs in a subshell. In it the
  token variables (`GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`, `OAUTH_TOKEN`, `CI_JOB_TOKEN`) and the
  host variables (`GITLAB_HOST`, `GL_HOST`, `GITLAB_URI`, `GITLAB_URL`) are unset, and `GLAB_CHECK_UPDATE=false` and
  `NO_PROMPT=1` are set. Jig never reads, passes or writes a token: glab uses its own, and its
  configuration is never written. `fetch` proposes that account when it may comment as a member:
  - Reporter or above, by the project or its group, may comment.
  - Any membership of a project that is not public may comment.
  - Otherwise, or with a token variable set, the answer is `ask`.
  `check` and `post` confirm with `GET user` that the call answers as the draft's login. They try
  glab's account first, then the environment's token when that one answers as the login. A
  discussion that is locked refuses anybody who is not such a member.
- **One discussion a call, and the first refusal stops.** The summary goes first, as a
  discussion without a position. Then each comment goes with its position, through
  `--input part-<k>.json`. A rate limit would refuse the rest anyway, so the first refusal ends
  the run. Each id goes into `posted` as soon as GitLab gives it. A run again posts only what is
  missing.
- **Landed means where it was shown.** The read-back takes each discussion's first note by the
  same login. A part with this version's marker counts as landed only at its position: the
  posted path and the line on its side, and no position for the summary. A part that is there
  elsewhere, or without its line, is `misplaced`. It is reported, the run exits 1, and it is never
  posted again: the next run refuses before posting anything. So does a note whose id `posted`
  holds for this version and the read-back no longer finds with its marker (deleted or edited):
  the part it held may be the one missing. Which copy stays is the person's
  call.

## Alternatives

- Draft notes and `bulk_publish`, which publish at once as GitLab's own review does — rejected:
  draft notes are the person's pending state on the server. A half-done run would leave drafts
  they cannot see, which their next "Submit review" in GitLab publishes.
- `jq` for glab's answers — rejected by ADR-0002, and it is not on Git Bash.
- A SHA-1 written in awk for `line_code` — rejected: much code for a highlight. Posting at the
  last line is shown before the yes, and the live check may reopen it.
- Reading `glab auth token` or the config file and passing the token like gh's — rejected: glab
  keeps one account per host, so it adds nothing but a token in jig's hands.
- Retrying a misplaced comment — rejected: it would put a second copy beside the first, in the
  person's name.

## Consequences

- Every comment on GitLab is a notification of its own to the author, where GitHub sends one for
  the review.
- A follow-up's replies are later notes of a discussion, so the read-back reads every note since
  adr-20261110-a-follow-up-answers-its-own-threads.
- `jig pr fetch` needs `glab` for a GitLab URL, as it needs `gh` for a GitHub one, and a `glab`
  that has `--output ndjson`.
- The state directory holds the same files as on GitHub. `payload.json` is the list of
  discussions, kept for reading.
- Tests stand in for glab with GitLab's JSON. That runs the reader too, and needs no `jq`.
- Not checked live yet (the item asks for a live merge request; an unattended run touches no
  forge):
  - that GitLab keeps the hidden marker, and in which escaping it returns it;
  - positions on added, deleted and context lines, and on a renamed file;
  - the last-line range;
  - `diff_refs` after a force-push;
  - which account glab uses with a keyring-stored token, and an environment token overriding it;
  - the access levels (a public non-member, Guest, Reporter, a locked discussion);
  - `/diffs` paging, `too_large`, `changes_count: "1000+"`;
  - the error GitLab gives for a bad position;
  - nested-group encoding;
  - the oldest glab with `ndjson`;
  - Git Bash with `--input`.
