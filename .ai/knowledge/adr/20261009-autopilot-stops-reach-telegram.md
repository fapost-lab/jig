---
id: adr-20261009-autopilot-stops-reach-telegram
type: adr
status: accepted
date: 2026-10-09
domains:
  - task
  - config
paths:
  - scripts/lib/notify.sh
  - scripts/lib/task.sh
  - scripts/lib/config.sh
  - scripts/lib/status.sh
  - skills/jig-autopilot/SKILL.md
summary: Why autopilot stops, ends and unattended choices send a Telegram message through an optional, detached curl that reads the token from stdin, why the token is local-only, masked and refused on a command line, and why a failed send is recorded beside the journal, never in it.
---
# An autopilot run's stops and ends reach Telegram through an optional curl, detached, with the token kept off every command line and out of every output

## Context

A person running several autopilot tasks learns that one stopped — for an answer, at the repair
limit, or done — only by going to look (spec: `.ai/specs/notifications/`). The journal already
records each stop and end with its reason, under every runtime. What was missing is a way for
that record to reach the person. Two things make it more than a feature: it is the first time a
Jig script calls the network for something other than git, and the first time a setting holds a
secret — a Telegram bot token is a bot anyone can use once it leaks.

## Decision

- **The events are the journal's own.** `stop` (the repair-limit stop included) and `end` in every
  run, `approve` and `decide` in an unattended run (where the script already refuses them
  otherwise). A message is sent right after the journal line is written, never before. `end`
  takes an optional `--reason` — how the run ended — so its message does not read as "merged"
  when nothing merged; without it the message says `Run ended`.
- **The message** is plain text (no `parse_mode`): a mark and `<project> · <task-id>`, the task's
  description (`task.md`'s heading when it differs from the id, else the first sentence of
  `## Goal`, cut to 80 characters), the journal's text (300 characters), and on `end` the task's
  `pr_url`. Marks: `⏸` an attended stop, `⛔` an unattended one (nothing waits there; `resume` is
  refused), `✅` end, `🤖` approve and decide. The project is `origin`'s repository name, else the
  main clone's directory name. Text is cut by characters, counted from UTF-8 lead bytes under
  `LC_ALL=C`, never by bytes, and never with a locale that may not be installed.
- **Three local-only keys** (ADR-0038): `notify.telegram.token`, `notify.telegram.chat_id`,
  `notify.autopilot` (default `true`). Nothing is sent unless both of the first two are set,
  `notify.autopilot` is not off and `curl` is on `PATH`. curl stays optional: without it Jig sends
  nothing and changes nothing else (ADR-0002 still holds — git is the one mandatory dependency).
- **Sending never holds up or fails the command.** The command checks only the keys and `curl`;
  everything else runs detached, in a process group of its own (`set -m`), with every descriptor
  on `/dev/null`, bounded by curl's own `--max-time 10`. The command's output and exit status are
  what they would be without notifications — `repair`'s exit 3 included.
- **The token is never on a command line and never printed.** curl reads the URL that holds it
  from stdin (`--config -`); a token not shaped `<digits>:<[A-Za-z0-9_-]+>` is never written into
  that line. The text goes form-encoded from a file (`--data-urlencode text@<file>`), so quotes and
  backslashes in a reason cannot break a config line. `jig config show --local`, `jig config set`
  (`--dry-run` and its refusals) and `jig status` print `********` for the token. `jig config set`
  refuses the token outright — `ps`, shell history and the agent's transcript would keep it — so
  the person writes it into `.ai/config.local.yaml` themselves. A token in `.ai/config.yaml` is
  ignored like every local-only key there, and `jig status` adds that it must be revoked.
- **A failed send is recorded beside the journal, never in it.** The task's `notify` file holds one
  line, the outcome of its latest send, replaced atomically. The journal is written by copy and
  `mv` with no lock, so a sender appending to it while the agent records the next event would lose
  a line — and with it `report`, a "decided without you" entry or the repair count. `jig status`
  prints a `notify:` line while the latest send across all tasks failed; a later success clears
  it, so the warning stays true.

## Alternatives

- **The runtime's `Stop` hook** — fires at the end of every turn, knows no task and no reason, and
  is one integration per runtime (rejected in the spec).
- **A synchronous send** — every stop could hang on a bad network, and the error would reach the
  agent rather than the person.
- **Fire and forget with no record** — a wrong chat id would never be noticed.
- **Plain `( … ) &`, as the session hook does** — dies with the command's process group under a
  runtime sandbox that kills it when the command returns.
- **Appending the failure to the journal** — the lost-line race above.
- **Accepting the token in `jig config set` and masking its output** — the value has already gone
  through `ps` and the shell history by then; refusing is the step that is easy to take back.
- **Showing the token's last characters** — a part of a secret in a transcript buys only
  recognition.
- **Deriving `end`'s text from state** — the script cannot know whether a pull request merged
  (ADR-0005), and `✅` would again read as "merged".

## Consequences

- The person learns of a recorded stop within seconds. A run that dies without recording one —
  killed, out of context, the machine asleep — still sends nothing; silence is not "working".
- A sandbox that blocks the network makes every send fail; the `notify:` status line is how that
  shows. `jig notify test` (next wave) is meant to catch it at setup, from the agent's session.
- A secret now lives in `.ai/config.local.yaml`. Any new command that prints a local value goes
  through `_cfg_secret_key` / `JIG_CFG_MASK` (config.sh), the one place that names it.
- `notify` is a new workspace file; it goes with the workspace like the journal does.
