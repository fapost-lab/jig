# Roadmap — notifications

Destination: a person running autopilot tasks learns within seconds, from one short Telegram
message naming the project, the task and the reason, that a run stopped, ended or chose for them —
and a wrong setting is caught at setup, not after the first silent stop.

Epic: epic/notifications
Release: minor

## Phase 1 — Telegram on autopilot events

Goal: autopilot's stops and ends reach Telegram. Done when: with the token and chat id set,
`jig task autopilot <id> stop --reason <r>` sends the three-line message and returns without
waiting for it, and an unattended stop is marked `⛔`; `end` sends its text and the pull request
URL; `approve` and `decide` send only in an unattended run; a Russian description is cut without
breaking a character and a reason with quotes arrives intact; with a key missing, `notify.autopilot:
false` or no `curl` nothing is sent and nothing fails; a failed send leaves a line beside the
journal and a `jig status` line that a later success clears; a token in `.ai/config.yaml` is
ignored and reported; `jig config show --local` masks the token.

- [x] `autopilot-telegram-messages` — autopilot messages: the local-only keys (token, chat id, `notify.autopilot`), the message
  (project, description, reason, marks), the detached sender with the token off the command line
  and the text form-encoded from a file, the failure record and its status line, masking and the
  committed-token warning, the phone-sized `--reason` rule in `jig-autopilot`, docs and an ADR (a
  first outbound network call)
- [ ] `notify-setup-and-test` — notify test and setup: `jig notify setup` (hidden token input), `jig notify test` and the
  Telegram question in `jig-setup`, which runs the test from the agent's own session (after: autopilot messages — the test sends through the
  same sender and keys)

## Phase 2 — the runtime's Notification hook

Goal: a session that waits for the person's permission or input outside a recorded autopilot stop
also sends a message. Done when: decided once the fog lifts.

- [ ] fog: Notification hook — behind `notify.interactive`; what the hook carries under Claude
  Code and Codex, how a call is tied to a project and a task, and whether it is quiet enough in an
  interactive session; see the open questions

## Waves

1. autopilot-telegram-messages
2. notify-setup-and-test
3. Notification hook

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
