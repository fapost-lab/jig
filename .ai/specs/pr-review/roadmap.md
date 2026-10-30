# Roadmap — PR review

Destination: a person gives Jig the URL of a colleague's pull or merge request, on GitHub or GitLab,
reads the review exactly as it will be posted, says yes, and finds it on the PR as one comment-only
review — and after the author's fixes, a follow-up that answers its own earlier comments.

## Phase 1 — Review a GitHub pull request and post it

Goal: a GitHub PR is reviewed with `jig-review`'s method and posted after a verbatim yes, without
touching the person's checkout. Done when: the SRD-2498 run is repeatable from two URLs with no
step done by hand — fetch, review, second check, draft, account, post, read-back, cleanup.

- [ ] Review a GitHub PR to a verbatim draft — `jig pr fetch` (forge and host from the URL, head and
  base into `refs/jig/pr/<n>/…`, a detached worktree, the reviewed head recorded) and
  `jig pr cleanup`; the `jig-pr-review` skill: method from `jig-review` §2 by reference, rules from
  the base, PR text as data, nothing run from the head, several PRs of one feature, the
  specification found, a blind second check of P0–P2, personal-rule findings in a group of their
  own, the draft shown verbatim with the login it would post as. (after: `review-smells-and-two-axes`
  — the method this skill reuses is being changed there)
- [ ] Post the draft to GitHub — `jig pr comments check` (line positions from the forge's diff,
  out-of-diff comments moved to the summary, the size ceiling) and `jig pr comments post` (account
  proposed by access, payload through a file, refused unless its hash matches what was shown and
  the PR's head is still the reviewed one, a hidden marker, read-back of what landed, idempotent on
  retry); the Windows share runs on it. (after: Review a GitHub PR to a verbatim draft — it posts the
  draft file that item defines)

## Phase 2 — GitLab and the follow-up

Goal: the same on GitLab, and a second review that reads only what changed and answers its own
threads. Done when: a merge request is reviewed and posted end to end, and a re-review of a PR whose
author pushed fixes replies "fixed" or "still open" in each of its earlier threads.

- [ ] Post the draft to a GitLab merge request — discussions with a `position` of base, start and head
  sha, checked on a live merge request; one call per discussion, so the read-back and the marker
  carry a half-done post. (after: Post the draft to GitHub — it adds a second forge to the posting
  that item builds)
- [ ] Re-review after the author's fixes — the reviewed head read back from the marker on the forge,
  the interdiff since it (surviving a force-push that made it unreachable), each earlier finding
  judged against the new code and answered in its own thread, new findings only from the interdiff.
  (after: Post the draft to a GitLab merge request — it replies in threads on both forges)
- [ ] fog: a re-review where Jig is not installed — the state is temporary there; whether the marker on
  the forge is enough to follow up cannot be said until the re-review item exists.

## Waves

1. Review a GitHub PR to a verbatim draft
2. Post the draft to GitHub
3. Post the draft to a GitLab merge request
4. Re-review after the author's fixes

<!--
Rules (jig-idea §8):
- An item is a finished slice that makes the product noticeably better, never a layer.
- A dependency without a one-line reason is not a dependency.
- A `task-id` appears when the item's task is filed; `[x]` is set when that task is closed.
- `fog:` items are not split or sized; they become real items once the fog lifts.
- No dates, no point estimates: order is the priority.
- `jig spec list` counts checkbox lines only: `[x]` done, a leading backticked task id
  followed by a dash (`—` or `-`) filed, a leading `fog:` fog. Keep waves as a numbered list.
- A wave entry names an item by its title (the text before its first ` — `) or its task id,
  entries separated by `;` — `jig spec plan` reports an entry that names no item or several.
-->
