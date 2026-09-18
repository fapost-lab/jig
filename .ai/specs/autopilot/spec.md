# Autopilot — agents that finish a task on their own

Depth: normal — six connected features; the risky decisions (commit rights, gates under
autopilot) get one question each, the rest are taken as recorded assumptions.

## Idea

Translated from Russian, as said on 2026-09-18:

> Wait, we need to drop "agents do not commit"! It should be decided at the user level, by
> choice — in CLAUDE.local for example. This matters most. That is why autopilot is really
> cool. Let's create a spec for 1–4 and autopilot.

Items 1–4, from a comparison with aiblueprinthq/ai-blueprint:

1. A findings ledger: review findings recorded with an id, a severity P0–P3 and a status;
   open P0/P1 block completion.
2. An independent review receipt pinned to the reviewed commit and the spec; a stale receipt
   blocks completion.
3. Routing evals: prompts that must and must not trigger each skill.
4. A status dashboard readable by people who do not live in a terminal.

Plus: autopilot — one task driven through its route to the end without stopping, within
boundaries the user configured.

## Goal and problem

- Who is worse off without this, and how: a user who trusts the process has to sit through
  every stage and do the git work by hand; "agents do not commit" is a convention nobody
  chose per project, and it turns every finished task into manual chores.
- What is true when the work is done: a user who opted in says "take this task" and gets
  back an open pull request — classified, analysed, implemented, reviewed, verified,
  consolidated — or a clear stop naming the one thing only a human can decide. A user who did
  not opt in sees no change. Completion is refused by scripts, not by agent discipline, while
  a serious finding is open or the review no longer matches the code.

## Stress test

- Hidden assumptions — "this holds only if …":
  - Autopilot is safe only if its stops are mechanical. A skill that says "stop on P0" is a
    request to a model; a script that refuses `verify` or consolidation is a stop. Hence the
    ledger and the receipt come before autopilot, not after.
  - Waiving the T3/T4 gate is tolerable only if the design still reaches a human before the
    change lands — at the pull request instead of before the code.
  - "Uncommitted files are the human's review queue" (`jig status`, task domain) holds only
    while agents do not commit. With commit rights on, the queue is open pull requests.
- The main trade-off: autonomy against the human gate. The user chose that the gate can be
  waived; the price is that architecture can be decided by an agent and reviewed only after
  it is built.
- The weakest point: routing evals. A lexical check of skill descriptions is cheap and runs
  in CI but says little about what a model will actually pick; a live model run says more but
  needs a key, costs money and is not deterministic.
- Failure modes — cause, what breaks, the signal that shows it:
  - Autopilot loops on a failing repair → burns tokens, never stops. Signal: repair attempts
    counted in task state; a limit ends the run as a stop.
  - A receipt is written, then a fix lands → the reviewed code is not the shipped code.
    Signal: HEAD differs from the receipt's commit; the gate refuses.
  - Commit rights granted in one clone leak into the project → every contributor's agent
    commits. Signal: none unless the key is local-only by design (ADR-0038 whitelist).
  - Gate waived, design never read → an architectural change merges unexamined. Signal: the
    pull request body carries the design verbatim and says the gate was waived.
- Other shapes considered, and why this one: prose in `CLAUDE.local.md` (the user's first
  suggestion) — rejected, see Decisions; autopilot over a whole roadmap phase first —
  deferred until the single-task run is proven.

## Scope and non-goals

- In scope: an opt-in for agent git actions; a findings ledger and a review receipt that
  scripts enforce; autopilot for one task, then for a roadmap phase; routing evals; an HTML
  status page.
- Not doing: merging. The agent may at most open a pull request; merging and therefore
  closing the task after landing (ADR-0030) stay with the human. No server for the
  dashboard, no new runtime dependency (ADR-0002).

## Decisions

- **Agent git rights are a setting, off by default.** A key `agent.git: none | commit | push
  | pr` (name final at design), default `none` — today's behaviour. Each level includes the
  ones before it. — rejected: dropping the rule for everyone, because a user who never asked
  for commits would get them.
- **The setting lives in `.ai/config.local.yaml`** and joins the ADR-0038 whitelist: scripts
  read it, both runtimes see it, `jig status` can say what it changes. — rejected: prose in
  `CLAUDE.local.md`, because scripts and Codex cannot read it and `jig status` would keep
  calling uncommitted files the human's queue; both layers, because two sources drift.
- **Autopilot ends at an open pull request** at most, with `knowledge_consolidated` recorded.
  Merge is the human's; the task closes after landing as ADR-0030 says. — rejected: an
  autopilot merge level, because it would bypass the branch ruleset and the only human look
  at the change.
- **The T3/T4 human gate can be waived** by a separate opt-in, not implied by git rights. A
  waived gate is recorded in `task.md`, and the pull request carries the design verbatim with
  a line saying the gate was waived. Without the opt-in, autopilot runs T3/T4 to the gate,
  stops, and continues on its own after approval. — rejected: gate always kept, because the
  user wants full autonomy available; T0–T2 only, same reason. Needs an ADR refining
  ADR-0009's "human gates are full stops".
- **One task first, a roadmap phase later.** The phase run is its own phase of this spec,
  started once single-task runs are proven. — rejected: phase first, because a phase run
  multiplies every flaw of the single run.

## Open questions

- Is the gate waiver local-only, or may a project forbid it in `config.yaml` (a ceiling the
  local layer cannot raise)? — decides whether a team can keep ADR-0009 for its repository.
- Live routing evals against a model: worth a key and a cost, or is the lexical check
  enough? — decides whether item 3 grows a second half.

## Assumptions left untested

Taken at normal depth as reversible; each is decided again at the task's design.

- The findings ledger is a task workspace file written by a `jig task` subcommand (id,
  severity P0–P3, status open | fixed | closed, file:line), gitignored like the rest of the
  workspace; `jig verify` and consolidation refuse while a P0 or P1 is open or fixed-but-not-
  re-reviewed. Test: a T2 task with a planted P1 cannot be consolidated.
- The review receipt records the reviewed commit, the base, and a hash of the approved
  documents (`task.md`, `design.md`); the gate refuses when HEAD or the hash moved. Required
  for T4, written for T2/T3 when review runs. Test: amend after review, the gate refuses.
- Autopilot stops on: the human gate (unless waived), an unresolved P0/P1 after two repair
  attempts, red verification after repairs, a re-classification above what the user allowed,
  a product decision nobody made, and any destructive operation. Test: each stop has a case.
- Routing evals are prompt cases per skill scored against skill descriptions by a shell
  script in `tests/`. Test: a deliberately vague description fails.
- The dashboard is a static self-contained HTML file written by `jig status --html` into
  `.ai/runtime/`, opened by the user; no server. Test: it renders tasks, findings, receipts
  and spec progress with the browser offline.
