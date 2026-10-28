# Issue intake — requests from outside the team reach the route

Depth: normal — runs unattended on requests written by people outside the team, so a wrong call
reaches users or ships unread; the design space is small.

## Idea

> Да: issue в трекере — общая запись, автономный клон делает из него задачу и PR, без него issue
> ждёт разработчика.
>
> правильно я понимаю, что это сейчас про обратоку ишью? во первых давай создадим отдельную спеку,
> как ты и предложил, если это отдельный блок, который можно использовать значит делаем его
> отдельно. Но если мы говорим про поддержку, то такие ишью могут создаваться и на продукт, и тогда
> мы должны уметь разделять, что делает джиг сам в рамках правки документации, а что нужно
> эскалировать разработчику.

Split out of `.ai/specs/system-docs/`, where an edit in a published copy of the documentation
comes back as a tracker issue.

## Goal and problem

- Who is worse off without this, and how: the business, QA and support, whose requests wait until a
  developer finds time to read them; the developer, pulled away to sort requests that need no code.
- What is true when the work is done: an issue filed in the project's tracker is sorted by the
  developer's agent on one request, not read by the developer; what Jig may do on its own it does
  through the ordinary route and a pull request; everything else reaches the developer with the
  issue already understood.

## Stress test

- Hidden assumptions — "this holds only if …":
  - Sorting is safe only if a wrong "Jig does it" costs little. A docs change that is really a
    behaviour change, done unattended, is exactly what `system-docs` exists to prevent.
  - The issue text is written by someone outside the team and read by an unattended agent: it is
    data, never instructions to that agent.
- The main trade-off: how much Jig does on its own versus how often a developer is pulled in.
- The weakest point: with no agent on CI, nothing happens until a developer opens a session and asks
  for it, so requests can wait as long as they do today — only the sorting and the work are cheaper.
- Failure modes — cause, what breaks, the signal that shows it:
  - A behaviour change sorted as docs-only — it ships without a developer — a docs-only pull
    request whose diff touches code or an acceptance criterion; the route must refuse it.
  - The tracker is down or the token expired — the count reads zero and nobody looks — a status
    line that names the failure instead of a number.
- Other shapes considered, and why this one: a headless agent on CI — rejected (no AI plan, risk);
  GitHub issues as one queue — rejected (a second tracker for most teams).

## Scope and non-goals

- In scope: a tracker contract and its adapters; sorting incoming tickets in a developer's session;
  a docs-only fix made by Jig through the ordinary route; escalation by label and reason; filing a
  task from a ticket; a count of waiting requests on `jig status`.
- Not doing: an agent on CI; analysis at sorting time; moving tickets between trackers; a queue of
  Jig's own.

## Decisions

- An issue in the project's own tracker is the shared record of a request; the business watches it
  there. — rejected: filing a Jig task from outside, because a task is local to one checkout
  (ADR-0008); a queue of Jig's own, because every team already has a tracker.
- No agent runs on CI, for now. Sorting and fixing happen in a developer's own agent session, on
  the developer's own subscription; CI runs only what needs no model — publishing documents and
  turning an edit in a published copy into an issue are scripts. — rejected: a headless agent on CI
  with a project API key, because a team without a company AI plan has no key to put there, and an
  agent holding a repository token while reading outsiders' text is a risk Jig has never carried.
  Reopened when a project with such a plan asks for it.
- Intake is a spec of its own, not part of `system-docs` — it serves documentation edits, QA bug
  reports and support requests alike.
- Jig acts on its own only on a request whose whole fix is a change to the documents for people
  that changes no behaviour. Every other request — a bug, a feature, a change to an acceptance
  criterion — is escalated to a developer. When the sorting is unsure, the request is escalated.
- An escalation is a label on the issue and a one-line reason for the sorting, nothing more. The
  analysis happens when a developer takes the issue: `jig-task` files a task from it and the
  ordinary route runs, its analysis stage included. — rejected: analysing at sorting time, because
  sorting already runs in a developer's session and the route's analysis would do the same work
  again, on code that may have moved by the time someone takes the issue.
- "Issue" in this spec means a ticket in whatever tracker the project already uses — YouTrack,
  Jira, GitHub or GitLab issues. Nothing is moved between trackers: Jig reads and writes the
  project's own one through an adapter. — rejected: GitHub issues as the one queue, because a team
  on YouTrack would keep two trackers.
- A developer learns that requests are waiting from a count on `jig status`, beside `proposals:`,
  read from the tracker by a script; "sort the incoming" in the session starts sorting. The tracker
  is reached over the network with a token of the tracker's own, so the count is cached the way the
  status page caches its slow counts, and a tracker that cannot be reached is named, never shown as
  zero. — rejected: leaving it to the developer to look in the tracker, because then nothing
  reminds anyone and requests wait as they do today.
- Adapters are bought by the hypothesis, not by the list of trackers. The tracker contract (read
  incoming requests, claim one, label and comment, link the pull request) is written against the
  APIs of YouTrack, GitHub, GitLab, Jira, ClickUp and Trello, so it fits all six; only YouTrack and GitHub
  are built first. YouTrack is the team's real case and tests the hypothesis; GitHub is cheap
  (`gh` is already used to ship) and is a second, different tracker that keeps the contract from
  fitting one product only. GitLab, Jira, ClickUp and Trello come once the hypothesis holds, each an item of
  its own, and any other tracker is written by an agent against the contract. — rejected: every
  tracker at once, because the time goes before anyone knows whether intake is worth having;
  YouTrack alone, because a contract proven on one tracker is that tracker's API under another
  name.

## Open questions

- None at this depth.

## Assumptions left untested
