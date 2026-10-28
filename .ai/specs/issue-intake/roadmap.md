# Roadmap — Issue intake

Destination: a ticket filed in the project's own tracker is counted on `jig status`, sorted in a
developer's session, fixed by Jig through the ordinary route when only the documents for people
change, and otherwise escalated with a label and a reason until a developer files a task from it.

## Phase 1 — Prove it on YouTrack and GitHub

Goal: the hypothesis is tested on the team's real tracker, with a contract that fits more than one.
Done when: the team sorts a week of real YouTrack tickets through Jig, and the same commands work
against GitHub issues.

- [ ] Tracker contract — a written contract (read incoming, claim, label and comment, link the pull
  request, file a task from a ticket) checked against the APIs of YouTrack, GitHub, GitLab, Jira,
  ClickUp and Trello
- [ ] YouTrack adapter — the contract over YouTrack's REST API with a token of its own (after:
  Tracker contract — it implements the contract)
- [ ] GitHub adapter — the contract over `gh` (after: Tracker contract — it implements the contract)
- [ ] Waiting count on status — `jig status` shows the incoming count, cached, and names a tracker it
  cannot reach (after: YouTrack adapter — needs one adapter to read from)
- [ ] Task from a ticket — `jig-task` files a task from a ticket and links its pull request back
  (after: YouTrack adapter — needs one adapter to read from)
- [ ] Sort the incoming — a skill that sorts waiting tickets: a docs-only fix through the route, the
  rest escalated with a label and a reason, unsure means escalate (after: Task from a ticket — a
  docs-only fix runs as a task)

## Phase 2 — More trackers

Goal: teams on other trackers get intake without writing an adapter, once Phase 1 showed intake is
worth having. Done when: each adapter passes
the contract's checks.

- [ ] GitLab adapter — the contract over GitLab's REST API
- [ ] Jira adapter — the contract over Jira's REST API
- [ ] ClickUp adapter — the contract over ClickUp's API
- [ ] Trello adapter — the contract over Trello's API, cards as tickets
- [ ] fog: adapter written by an agent — whether `jig-setup` can have an agent write an adapter for an
  unknown tracker against the contract; unclear until three adapters show how much they share

## Waves

1. Tracker contract
2. YouTrack adapter; GitHub adapter
3. Waiting count on status; Task from a ticket
4. Sort the incoming
5. GitLab adapter; Jira adapter; ClickUp adapter; Trello adapter
