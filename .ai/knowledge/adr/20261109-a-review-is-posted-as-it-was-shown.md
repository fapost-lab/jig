---
id: adr-20261109-a-review-is-posted-as-it-was-shown
type: adr
status: accepted
date: 2026-11-09
domains: []
paths:
  - scripts/lib/pr.sh
  - "skills/jig-pr-review/**"
  - tests/pr.t.sh
  - scripts/lib/prgitlab.sh
summary: Why jig pr comments posts one COMMENT review only as shown (hash, reviewed head), as the one account that may comment, with a token for one call, through a file, idempotent by marker.
reviewed_at: 2026-11-11
---
# A review is posted only as it was shown, as the account that may comment, once

## Context

`.ai/specs/pr-review/` ends a review of a colleague's pull request with a post: one comment-only
review, in the person's name, into somebody else's repository. A post cannot be unsent and is read
by people outside the session, so every shortcut must fail closed. The failure hunt of the spec
named the ways it goes wrong: comments in the person's name they never read, or that were edited
after their yes; the wrong account (on a public repository every account can read; `GH_TOKEN`
overrides any choice); comments landing on the lines of a head the author pushed since; a retry
that posts a second copy; JSON built in shell and mangled by quotes, Cyrillic or Git Bash; lines
that are not in the forge's diff, which make GitHub refuse the whole review.

`jig pr fetch` and `jig pr draft`
(adr-20261109-a-pull-request-is-read-in-a-detached-tree-of-the-clone) already give the reviewed
head, the merge base and a checked draft. This decision covers what turns that draft into a post.

## Decision

`jig pr comments check` builds the review and shows it; `jig pr comments post` posts it.

- **Positions come from GitHub's diff**, never a local `git diff`: `pulls/<n>/files`, of which
  only the hunk headers cross from `gh` (its `--jq` filter), parsed by the shell. A comment's
  range must lie in one hunk on its side; an `L` comment on a renamed file is posted under the new
  name with `side: LEFT`. A comment outside the diff is moved into the summary, in the draft's own
  notation (`**R398 `path`**`), never dropped. Before that, GitHub's merge base
  (`compare/<base>...<head>`) must be the one the review read: otherwise old-side lines point
  elsewhere.
- **The ceiling is GitHub's.** Files it gives without a patch (binary — listed with no changes —
  or too large; a rename with no change has nothing to show and is not one of them) and files past
  its listing (`changed_files` above what it lists; named from the local diff) are listed in the
  summary by a fixed line, `Not in GitHub's diff, so not commented on: …` — never a silent partial
  review. The line is English whatever the review's language: the script writes no prose of its
  own beyond it, and a translated line would need a setting (ADR-0023 keeps language out of
  configuration).
- **What was shown is what is posted.** `check` prints the review as it will be posted — header
  (url, head, login, event), summary, each comment at its posted position, every hidden marker —
  and a `hash:` line: `git hash-object --stdin` of that text without the markers (stdin, so no
  filter of `core.autocrlf` changes it), the markers being made from it. It records the hash as
  the version shown. `post --shown <hash>` builds everything again from the draft and GitHub and
  refuses unless the hash it gets is the one named and the one shown last. An edit is a new
  version, shown again; the yes is never skipped, whatever `autopilot.unattended` says.
- **Pinned to the reviewed head.** Both commands refuse when GitHub's head is not the reviewed
  one, and the review names it in `commit_id`.
- **The account is proposed by the right to comment, not to read.** `fetch` tries every account
  `gh` holds for the host: with that account's own token (`gh auth token --user`, gh 2.40 and
  later, asked with every token variable unset) it reads `repos/<owner>/<repo>`. An account may
  comment as a member when it has push, triage, maintain or admin, or reads a private repository.
  Exactly one such account is proposed; none or several, or a token in the environment, means
  asking. A public repository where the person is not a member therefore always asks — on
  purpose: identity is the value where a silent default costs most. The draft names the login,
  and `check` and `post` confirm with `GET user` that the token in hand is that login's.
- **The token is for one call.** It reaches `gh` as `GH_TOKEN` (github.com and `*.ghe.com`) or
  `GH_ENTERPRISE_TOKEN` (a GitHub Enterprise Server) in a subshell where every other token variable is unset —
  never as an argument, never on disk. `gh auth switch` is never run and gh's configuration is
  never written.
- **Payloads go through a file.** JSON is built by `json_quote` (json.sh), written into the
  pull request's state directory and handed over with `gh api --method POST --input <file>`;
  no free text is ever an argument. Under Git Bash `gh` is a native program, so its arguments
  follow the shell convention: API paths without a leading `/`, no `Accept:` header, no `/` in a
  `--jq` filter, the `--input` path left for MSYS to convert, one CR taken off each line read back.
- **One review, event COMMENT.** Never APPROVE or REQUEST_CHANGES: those stay the person's, in
  GitHub's own interface. `personal` blocks are never posted.
- **Idempotent by a marker and a record.** Every part carries
  `<!-- jig-pr-review id=<hash> head=<sha> part=<k> -->` (0 the summary). Before posting, the
  reviews and review comments of the pull request by the same login are read back: all parts there
  — nothing is posted; none — one review; some (GitHub creates a review whole, so this is an answer
  that was lost) — only the missing ones, the summary as a review of its own and each comment
  alone. Another version of a review of the same head by the same login stops the post: which one
  stays is the person's call. A post GitHub took (`posted` holds its id) whose markers do not come
  back is reported and never retried blindly. After posting, the read-back says where each part
  landed; a part missing is `half-done`, exit 1, and running the same command posts only it.
- **Posting is not governed by `agent.git`.** That setting is about git in the person's own
  repository. A review is guarded by its own gate — the verbatim showing, the hash, the yes on
  every review — and a person with `agent.git: none` can still post.

## Alternatives

- A per-part content hash in the marker — rejected: an edited comment would read as "missing" and
  go up alone beside the old review. One id for the whole version keeps a retry to that version.
- Posting what remains when another version is already there — rejected: it mixes two reviews in
  the person's name; refusing and naming the other is the step that is easy to undo.
- Refusing until the summary names the unshown files in its own words — rejected: whether a path
  is "named" in prose cannot be checked reliably; a fixed line can.
- Proposing any account that can read — rejected: on a public repository that is every account,
  and a personal login in a work repository is the costliest mistake the spec names.
- A `-f body=…` per field, or JSON in an argument — rejected: shell quoting and MSYS conversion
  mangle exactly the text a review is made of (quotes, backticks, URLs, Cyrillic).
- Running `jq` in the scripts — rejected by ADR-0002; `gh`'s own `--jq` reduces each answer to
  lines the shell reads.

## Consequences

- The state directory of a pull request holds `payload.json`, `shown.md`, `shown`, `posted` and,
  for a moment, `post.json` and `part-<k>.json`; `jig pr cleanup` deletes them by name (RULES.md).
- Tests stand in for `gh` with the lines its filters would print, so the logic runs on every
  platform without `jq`; one test runs the filters themselves through `jq` where it is installed.
- Untested until the first real post: that GitHub keeps a hidden HTML comment in a review's body
  and in each comment and returns it through the API, and that gh's built-in jq (gojq) reads the
  filters as `jq` does. A marker that does not come back is reported, not retried.
- GitLab is adr-20261110-a-merge-request-review-is-posted-as-discussions: the same gate, posted
  one discussion a call. A re-review that reads the marker back is
  adr-20261110-a-follow-up-answers-its-own-threads.
