---
id: adr-20261009-a-secret-is-typed-only-into-the-persons-terminal
type: adr
status: accepted
date: 2026-10-09
domains: []
paths:
  - scripts/lib/notify.sh
  - skills/jig-setup/SKILL.md
summary: Why jig notify setup takes the bot token only from the person's terminal, bounded and with the terminal restored, and why jig notify test sends through the autopilot's own _notify_post from the agent's session.
reviewed_at: 2026-10-09
---
# A secret enters Jig only through the person's own terminal, never through the agent, and a sent test proves the setting from the agent's session

## Context

The Telegram bot token is the first secret Jig keeps (adr-20261009-autopilot-stops-reach-telegram).
`jig config set` refuses it, because a command line is kept by `ps`, the shell history and the
agent's transcript. That left a hand edit of `.ai/config.local.yaml` as the only way in — and no
way to learn, before the first silent stop, whether a message can actually leave the agent's
sandbox (spec: `.ai/specs/notifications/`).

## Decision

- **`jig notify setup` is the person's.** It asks for the token with hidden input and for the chat
  id, checks both shapes, writes both keys into `.ai/config.local.yaml` (one `mv`, the file left at
  mode 600 where the filesystem keeps modes), then sends the test below. It is Jig's first
  interactive command, and three rules make it safe to leave next to agents:
  - It reads only with a terminal on stdin and refuses at once without one. No piped token is
    accepted: an agent has no terminal, so the token never passes through it.
  - Both reads are bounded (300 s). A runtime that hands commands a pseudo-terminal passes the
    terminal check, and nobody there types; the wait ends in the same refusal. bash 3.2 reports
    the timeout like the end of input, so the elapsed time tells them apart.
  - The terminal's state is saved before the hidden read and restored on every exit, Ctrl-C
    included, from `/dev/tty` — bash leaves echo off when the INT trap exits during `read -s`, and
    the exit list runs with a here-document on stdin.
  It refuses while git does not ignore the local file, and never echoes an argument (the likeliest
  one is the token).
- **`jig notify test` goes the way a real message goes.** The sender's network half is one
  function, `_notify_post` (notify.sh): shape checks, curl with the URL on stdin and the text from
  a file, the answer read into `ok` or `failed: <why>` with the token masked. The autopilot's
  detached sender and the synchronous test both call it. The test is meant to run from the agent's
  own session — `jig-setup` asks the person to run `setup` and then runs `test` itself — because
  that session's sandbox is where autopilot sends from.

## Alternatives

- **The token from stdin when it is not a terminal** (`pass show bot | jig notify setup`) — also
  `printf '<token>' | jig notify setup` in an agent's shell, with the token in its transcript. A
  `--stdin` option can be added later without breaking anyone; taking one back cannot.
- **Reading `/dev/tty` directly** — works with stdin redirected, but is unpredictable under Git
  Bash and CI, and buys nothing over the terminal check.
- **A test-only "I am a terminal" variable** — a seam an agent could use too. The tests stand in
  for the terminal by redefining `_notify_terminal` in a shell that sources the library.
- **A separate curl call in the test** — a second path that can drift from the one autopilot uses.
- **A successful test clearing `jig status`'s `notify:` line** — would change the failure record of
  the previous decision; the test says instead that the line clears with the next autopilot message.

## Consequences

- The token reaches the file without passing through any command line, output or agent.
- The interactive read is not exercised end to end in CI (no terminal); the refusal without one,
  the timeout and the writing are. Under a Windows console through `jig.cmd` the terminal check and
  `read -s` are untested; a terminal not recognised gives the refusal, not a hang.
- A synchronous test does not prove that a detached sender survives a sandbox that kills the
  process group when a command returns; the `notify:` status line still covers that.
- Any later secret follows the same road: a `setup`-style command in the person's terminal, never
  `jig config set`, and masked wherever it is printed (`_cfg_secret_key`).
