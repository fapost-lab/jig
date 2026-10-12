---
id: adr-20261010-a-waiting-session-reaches-telegram
type: adr
status: accepted
date: 2026-10-10
domains:
  - task
  - config
paths:
  - scripts/jig-notify-hook
  - scripts/lib/notify.sh
  - adapters/claude/adapter.sh
  - adapters/codex/adapter.sh
summary: Why an ordinary session that waits for the person sends the autopilot's Telegram message through an opted-in runtime Notification hook calling a script of its own, behind notify.interactive (default false), why the runtime's JSON is not parsed, and why Codex is not supported.
---
# A session that waits for the person sends the autopilot's message through a runtime hook they opted into, behind `notify.interactive`

## Context

Autopilot stops reach Telegram from the run's journal
(adr-20261009-autopilot-stops-reach-telegram). An ordinary session that waits — a permission
prompt, a question left unanswered — records nothing, so it stayed silent while the person was away
(spec: `.ai/specs/release-2026-10-10/`). Only the runtime knows that a session waits. The
notifications spec rejected its `Stop` hook as noise: it fires every turn and knows no task and no
reason.

What the runtimes give, read from their documentation on 2026-10-10:

- **Claude Code's `Notification` hook** gets JSON on stdin (`cwd`, `message`, `notification_type`,
  …). `permission_prompt` fires once a permission prompt has waited about six seconds.
  `idle_prompt` fires a minute after an answer with nothing typed, and the elicitation dialogs
  after six seconds. In the terminal these reach the hook only when the person seems away. In the
  desktop app and the IDE extensions a permission prompt reaches it after six seconds even while
  the person is there. The hook cannot block anything, and `async` runs it in the background.
- **Codex** has no such event. Its `notify` program is called on `agent-turn-complete` only, which
  is the `Stop` noise again. Its `PermissionRequest` hook fires the moment it asks for approval,
  with no sign of whether anyone is there.

## Decision

- **Opted in twice.** A new local-only key, `notify.interactive`, defaults to `false`, so "message
  me about autopilot, not while I sit at the computer" stays possible (ADR-0038). The hook itself
  is added to the runtime's settings by the person, or by their agent after their yes. Jig prints
  the snippet and never edits that file (ADR-0024). The snippet points at
  `.claude/settings.local.json`, because the messages go to one person's Telegram and the hook is
  theirs, not the team's.
- **A script of its own, `.ai/scripts/jig-notify-hook <permission|input>`.** It is not a `jig`
  subcommand, because the dispatcher records every run as work going on in the checkout
  (adr-20260924-a-checkout-records-what-is-happening-in-it), and a notification is not work. Like
  `jig-session-hook`, it exits 0 in every case and prints nothing: under any runtime a hook that
  fails can break its session, and stdout is the channel a hook answers through.
- **The runtime's JSON is not parsed.** The kind comes from the snippet's `matcher`:
  `permission_prompt` maps to `permission`; `idle_prompt` and the elicitation dialogs map to
  `input`. The one value read is a top-level `"cwd"` string that needs no decoding, which names
  the checkout the session works in. When it has an escape (a Windows path) or is missing, the
  hook's own working directory is used. ADR-0002 allows a `sed` reader for Jig's own formats only.
- **The command is `bash "$CLAUDE_PROJECT_DIR"/.ai/scripts/jig-notify-hook <kind>`.** Claude Code
  exports the variable to every hook, and it still names the original root once the session
  enters a worktree. That is why the checkout and the task come from `cwd`, not from where the
  script lives.
- **The same message, through the same sender.** The text is `⏸ <project> · <task-id>`, then the
  task's description, then `Waiting for your permission` or `Waiting for your answer`. With no
  task the first line names the branch instead. The task is the one `task current` would choose,
  and none when the choice is ambiguous. The checks before sending are the same as the autopilot's
  (keys, `curl`), the send is detached the same way, and Telegram is called only through
  `_notify_post`, so the token rules hold unchanged. The outcome goes to the task's `notify` file,
  or without a task to the checkout's `.ai/runtime/notify`, which `jig status` reads as a waiting
  session.
- **No second message about one wait.** While the task's autopilot run is `on` or `stopped`,
  `input` sends nothing, because the journal's stop already said it. `permission` is sent whatever
  the run, because the journal never sees a runtime prompt. `notify.autopilot` keeps its meaning:
  the hook reads only `notify.interactive`.
- **Codex is not supported.** Its adapter's `notify_hook_hint` exits 2 (not applicable), and the
  documentation says why.
- `jig status` and `jig doctor` mention the hook only while `notify.interactive` is `true`. Before
  that, a "not connected" line is one the reader never asked for and cannot clear.

## Alternatives

- **The runtime's `Stop` hook, or Codex's `notify`.** Every turn, no task and no reason (rejected
  in the spec).
- **Codex's `PermissionRequest`.** Every approval reaches the phone at once, while the person sits
  at the screen. Waiting a few seconds first does not help: nothing tells the sender that the
  approval was given meanwhile.
- **`jig notify hook` through the dispatcher.** It would leave a busy-checkout record on every
  notification, and could die with exit 1.
- **Parsing `message` and `notification_type`.** That needs a JSON string decoder in bash 3.2.
  The matcher already gives the kind, and the runtime's text adds little to "waiting for your
  permission".
- **Writing the hook into `.claude/settings.json`, create-if-absent like `init --session-hook`.**
  That file is the team's, and it almost always exists already.
- **A relative command path, as the session hook uses.** It depends on the directory the runtime
  starts hooks in. `$CLAUDE_PROJECT_DIR` is documented for that purpose.

## Consequences

- With the key on, a desktop or IDE session sends one message for every permission the person
  takes longer than six seconds to give. The documentation and the hint say this where the person
  decides.
- **An unverified assumption.** The behaviour of `$CLAUDE_PROJECT_DIR` was taken from Claude
  Code's documentation and not measured in a real hook: an agent session cannot fire its own
  `Notification` hook without the person's settings being edited. If the variable were empty, the
  command would run `bash "/.ai/scripts/jig-notify-hook"` and fail silently, while `jig status`
  still reports the hook as connected (detection is a substring). The first real message, or its
  absence, settles it; `jig notify test` does not, because it sends without the hook.
- The `jig-setup` skill may write the snippet into the person's own settings file after their yes.
  That is an amendment to ADR-0024, recorded there: the framework's scripts still never edit an
  existing runtime config.
- A session that waits but has no Jig install at `$CLAUDE_PROJECT_DIR` runs a hook that fails. Claude
  Code ignores a `Notification` hook's exit status and stderr.
- `.ai/runtime/notify` is a new per-checkout file. A failure recorded in a worktree's runtime is
  visible to `jig status` run in that worktree only.
- Any new runtime gets the contract `adapter_<name>_notify_hook_hint`: print the snippet, print
  nothing once connected, exit 2 when the runtime has no event for a waiting session.
