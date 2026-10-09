# Notifications — a short message when an agent stops

Depth: normal — few decisions, but two are costly when wrong: a leaked bot token, and a channel
so noisy that the human mutes it.

## Idea

Jig idea: I want to send messages to Telegram when the agent stops — either it is waiting for
an answer from me, or it has finished the task, and so on. This is especially useful when you
run many tasks on autopilot, to stay aware of what is going on. Very brief, not like in the
chat. The token and chat id settings can be kept in config.local.

*(Translated from the human's Russian, 2026-10-09.)*

## Goal and problem

- Who is worse off without this, and how: a person running several tasks on autopilot. Each
  run stops on its own schedule — for an answer, at a gate, at the repair limit, or done with a
  pull request — and the only way to learn that is to go and look at each session. A run that
  stopped for a one-line answer sits idle until somebody happens to check.
- What is true when the work is done: when an autopilot run stops or ends, a one-line message
  naming the task and the reason reaches the person's Telegram within seconds; with nothing
  configured, nothing is sent and nothing changes.

## Stress test

- Hidden assumptions — "this holds only if …":
  - A run that stops records its stop. A session that dies — killed, out of context, out of
    usage, the machine asleep — writes no `stop`, so it sends nothing, and silence reads as "still
    working". This feature makes recorded stops loud; it does not detect unrecorded ones.
  - The detached sender can reach the network. A runtime sandbox that blocks network for
    commands (Codex by default, Claude Code's sandbox when enabled) makes every send fail; the
    failure record and the `jig status` line are what surface it.
  - An agent in an attended chat that asks a question without `autopilot stop` sends nothing;
    phase 2's `Notification` hook covers part of that, not all.
- The main trade-off: few messages that each need the person (stop, end, the unattended run's own
  choices) against a feed that shows progress; the first stays unmuted, the second is what a
  status page is for.
- The weakest point: silence is ambiguous — a run that is still working and a run that died look
  the same from Telegram.
- Failure modes — cause, what breaks, the signal that shows it:
  - Token in `.ai/config.yaml` — committed and pushed, the bot is anyone's — `jig status` warns,
    the key is ignored there.
  - Token on a command line — visible in `ps` to every user of the machine while `curl` runs —
    the sender passes the URL to `curl` on stdin (`--config -`), never as an argument.
  - Token printed by `jig config show --local` — lands in an agent transcript — the value is
    masked.
  - Markdown in a reason — Telegram rejects the message — sent as plain text, no `parse_mode`.
  - Wrong token or chat id — every send fails — `jig notify test` shows Telegram's answer at setup;
    later, the journal line and `jig status`.
- From the independent failure hunt (2026-10-09), beyond the above:
  - A sandbox that kills the command's process group when the command returns — the detached
    sender dies before it sends and before it records a failure — nothing; a test run by the
    person in their own shell passes while every real send from the agent is lost.
  - Byte-wise truncation of a Russian heading or goal — invalid UTF-8, Telegram answers 400 — a
    failure for some tasks only.
  - Quotes, backslashes or a very long reason in a curl config file or form body — a parse error
    or a refused message — failures that track the reason's text.
  - Parallel runs ending together, several `decide` lines in a row — Telegram's rate limit (429),
    messages dropped — gaps in a burst.
  - The sender appending its failure line to the journal while the agent appends the next event —
    the journal is copied and moved into place with no lock, so one line is lost, and with it
    `report`, the pull request's "decided without you" block or the repair count — rare, nearly
    invisible.
  - `end` that is not a finished change — a phase-run task agent ends at consolidation with no
    pull request; `not merged: <why>`; "ready for your commit" — a ✅ the person reads as merged.
  - A phase run's coordinator stops in chat, not in a journal — the costliest stop, a whole wave
    waiting, sends nothing.
  - The repair-limit stop of an unattended run — ⏸ reads "waiting for you", but `resume` is
    refused there and the real outcome is a draft pull request later.
  - Settings per clone, not per person — a new clone or another project is silent, and nothing
    says notifications are off there.
  - The token on `jig config set`'s command line — in `ps`, shell history and the agent's
    transcript; a committed token is reported only once it is in history.
  - A failure line that stays forever, or a laptop asleep for an hour — "notifications failing"
    sits next to messages that arrive, and the warning stops meaning anything.
  - A reason written for the journal (`repair limit reached (2): …`) — the message does not say
    what is needed, and the person opens every session anyway.
- Other shapes considered, and why this one: the runtime's `Stop` hook (see Decisions); a generic
  "run my command on stop" hook — more flexible, but every person would write the same Telegram
  script, and project hooks are their own spec (`project-hooks`); a status page polled by the
  person — already exists, needs the person to look, which is the problem.

## Scope and non-goals

- In scope: Telegram messages on the autopilot journal's `stop` and `end`, and on `approve` and
  `decide` in unattended runs; local-only keys for the token and chat id; masking and the
  committed-token warning; the failure record and its `jig status` line; `jig notify test`; a
  question in `jig-setup`; the runtime's `Notification` hook as a later phase.
- Not doing: other channels (Slack, email, a webhook) until somebody asks; answering a stop from
  Telegram (a reply that resumes the run) — it needs an inbound side and a listener, which is a
  different feature; detecting a dead session (a heartbeat); messages outside autopilot runs.

## Decisions

- The source of a notification is Jig's own events first: the autopilot journal's stop and end
  (and what they carry — a gate, the repair limit, a pull request). The runtime's own hooks come
  later as a separate phase, and only `Notification` ("the agent is waiting for permission or
  input") — rejected: the runtime's `Stop` hook, because it fires at the end of every turn (noise
  in any interactive session), carries no task and no reason, needs JSON parsing of the
  transcript, and is one integration per runtime; Jig's events know the task and the reason and
  are the same under every runtime.
- The events that send: `stop` and `end` in every run, and in an unattended run also `approve`
  and `decide` — "the agent approved its own design" and "the agent chose for you" are what a
  person running many tasks unattended wants to see as they happen, not only later in the pull
  request body — rejected: `start`, `stage`, `repair` and `resume`, because they need nothing
  from the person and would turn the channel into a progress feed nobody reads; a per-person
  event filter key, because no one has asked for a different set yet (zero-config).
- Every message names the project and the task, and the task by a short description, not only
  its id: with several projects and several runs at once an id alone does not tell the person
  which work stopped. The description is the heading of the task's `task.md` when it differs
  from the id, otherwise the first sentence of its `## Goal`, cut to one short line.
- The project is named by the repository name from `origin`'s URL, or, with no `origin`, by the
  directory name of the main clone — the same in every worktree and every clone of it, with
  nothing to configure — rejected: the checkout's directory name, because a worktree's
  directory is named after the task, not the project; a `notify.project` key, because the
  default already answers and a key can be added when somebody wants a different name.
- A message is three short lines: a mark and `<project> · <task-id>`, the task's description,
  and the reason from the journal line. Marks: `⏸` stop, `✅` end, `🤖` approve and decide.

  ```
  ⏸ bpai · fix-login-redirect
  Login redirect loses the return URL
  Needs you: Google or GitHub as the OAuth provider?
  ```
- Sending never holds up or fails the Jig command that triggered it: it runs detached with a
  timeout of about ten seconds, and with no `curl` it is skipped. A failed send is written as
  one line to a file of its own beside the journal — never the journal, which the agent appends
  to at the same moment with no lock — and `jig status` reports that notifications are failing
  while the latest send failed (a later success clears it), so a wrong token or chat id does not
  stay silent forever — the same rule as the session hook,
  where background work never breaks the foreground — rejected: a synchronous send, because
  every stop could hang on a bad network and the error would reach the agent, not the person;
  fire-and-forget with no record, because a wrong chat id would then never be noticed.
- The settings are two local-only keys, `notify.telegram.token` and `notify.telegram.chat_id`,
  written with `jig config set --local`; with either missing nothing is sent. A token found in
  `.ai/config.yaml` is ignored and reported by `jig status`, and `jig config show --local` masks
  the token — rejected: environment variables that override the file, until an unattended run in
  a cloud clone needs them (see Open questions).
- Two local-only switches, controlled independently: `notify.autopilot` (autopilot runs'
  events, default `true` once the token and chat id are set) and `notify.interactive` (the
  runtime's `Notification` hook in an ordinary session, default `false`, phase 2) — "write to me
  about autopilot, not while I sit at the computer" is the case — rejected: attended against
  unattended autopilot as the split, because the line a person draws is whether they are at the
  computer, and without an off switch the phase 2 hook would be noise in every chat session.
- The token is entered by the person in their own terminal: `jig notify setup` asks for it with
  hidden input and for the chat id, writes both to `.ai/config.local.yaml` and sends a test. The
  agent never sees the token. `jig notify test` sends one message (`🔔 <project> · notifications
  work`) synchronously and, on failure, prints Telegram's answer with the token masked.
  `jig-setup` asks whether to send Telegram messages, explains where the token and chat id come
  from (@BotFather, the bot's first message), asks the person to run `jig notify setup`, then runs
  `jig notify test` from its own session — the sandbox real sends run in — rejected: the token
  pasted into chat and written with `jig config set --local`, because it then sits in the
  session's transcript, `ps` and shell history; no test command, because a wrong setting would
  show only after the first real stop. (Taken as the recommended default when the person moved
  the spec to autopilot without answering, 2026-10-09.)
- On `end`, the third line is the journal's text and a fourth is the pull request URL when the
  task has one: the text says what actually happened (merged, not merged and why, ready for the
  person's commit), the link is what the person opens next — rejected: the URL instead of the
  text, because the failure hunt showed `end` covers outcomes that are not a merged change.
- A stop in an unattended run is marked `⛔`, not `⏸`: nothing waits for the person there and
  `resume` is refused — the mark must not ask for an answer nobody can give.
- A reason is written for a phone: `jig-autopilot` tells the agent that `--reason` of `stop`,
  `approve` and `decide` is one sentence saying what is needed or what was chosen, and the
  message text is cut by characters, never bytes, and sent form-encoded from a file (curl's
  `--data-urlencode text@<file>`), never spliced into a config line.

## Open questions

- Environment variables for the token and chat id — needed only when unattended runs happen in a
  clone nobody configures (a cloud session, CI); decide at the first such run.
- Phase 2: what the runtime's `Notification` hook carries under Claude Code and under Codex, how a
  hook call is tied to a project and a task when no autopilot run is active, and whether it is
  quiet enough in an interactive session — the phase cannot be cut into items before this.

- A phase run's coordinator stops in the person's chat, not in a task journal, so a waiting wave
  sends nothing — whether the coordinator records its stop somewhere a sender sees, and where.
- Settings live per clone; a person with many projects configures each. Whether a per-person
  layer (outside every repository) is wanted is a question beyond this spec — ADR-0038 places
  personal settings in the clone.
- Telegram's rate limit on bursts — whether the sender spaces messages, or a dropped one in a burst
  is acceptable.

## Assumptions left untested

- `curl` is present where autopilot runs (macOS, Linux, Git for Windows ship it) — taken at
  normal; a run without it sends nothing and `jig notify test` says why.
- A detached child survives the Jig command and the agent's shell that started it, as the
  session hook's housekeeping does — taken at normal; the failure hunt doubts it under a runtime
  sandbox that kills the process group. Tested by sending from inside an agent session, which is
  why setup runs `jig notify test` from the agent, not from the person's shell.
