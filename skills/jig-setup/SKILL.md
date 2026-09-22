---
name: jig-setup
description: Ask a person, one question at a time in plain words, how far their agent may go on its own — git rights, autopilot without questions, CI wait, cleanup — and write their answers to their personal `.ai/config.local.yaml` after a yes. Use after `jig init`, or when the user says "set up Jig for me", "configure my settings", "change my personal settings", "let the agent merge".
---

# jig-setup — personal settings, asked for in plain words

The person may not know `.ai/config.local.yaml` exists. You ask; `jig config set --local`
checks and writes (ADR-0001). The file is theirs alone: it changes what **their** agent does
in **this** clone, never a colleague's. Never write `.ai/config.yaml` — the team's file, edited
by hand.

## 1. Start from what is set

```
.ai/scripts/jig config show --local
```

Say in one line what is already set, or that nothing is. Then ask the questions below, **one
per message**, in the person's words — no key names unless they ask. Each question says what
the choice changes, offers the options, and names your recommendation with its reason. A
person who says "keep the default" or "skip" moves on: nothing is written for that question.

## 2. The questions

1. **Git** (`agent.git`). "When the agent finishes a task, how far should it take the change?"
   `none` — it leaves the change for you to commit (default); `commit`; `push`; `pr` — it
   commits, pushes and opens the pull request, and you review and merge there; `merge` — see
   below. Recommend `pr` when `gh` or `glab` is installed and signed in, else `commit`.
2. **Merging** — only if they want more than `pr`. Before asking, explain: with `merge` the
   agent also merges its own pull request once CI ran and every check passed, never past
   branch protection or a required review, never a draft; the change then goes wherever the
   main branch goes — a deploy included. Set `merge` only on an explicit yes to that.
3. **Asking** (`autopilot.unattended`). Before asking, explain: on autopilot the agent stops to
   ask at a design approval, an unmade decision, a destructive step or a problem it could not
   fix; with `true` it asks nothing — it approves its own design, picks the most reversible
   option, never destroys anything, opens a draft when fixing fails, and writes every such
   choice into the pull request. Recommend `false` for a developer who can answer those
   questions, `true` only for someone who cannot and would rather have the change delivered.
   Set `true` only on an explicit yes.
4. **CI wait** (`agent.ci_timeout`) — only with `merge`. "How many minutes should it wait for
   the checks before leaving the pull request open for you?" Default 30.
5. **Cleanup** (`housekeeping.*`) — one question, offer to skip: how long an abandoned task is
   kept (`abandoned_ttl`, 14d), how long the trash is kept (`trash_ttl`, 7d), when an idle task
   is called stale (`stale_after`, 60d), how often cleanup runs (`cadence`, whole days, 1d),
   whether it may `git fetch` (`fetch`, true). Recommend the defaults.
6. **Worktrees** (`git.worktree_root`) — only if they run several agents at once and want the
   task folders somewhere other than `../<project>.worktrees`.

Ask about no other key. If `jig config set` refuses a key as not local, this version of Jig
does not have it: drop the question.

## 3. Show the whole file, then write

Put every answer into one dry run — it prints exactly the file that would be written:

```
.ai/scripts/jig config set <key> <value> [<key> <value>...] --local --dry-run
```

Show that output whole, verbatim, and after it, labelled as yours, one line per setting in plain
words. Ask for a yes. A change of mind goes back to its question and to a new dry run. After the
yes, run the same command without `--dry-run`. A refusal names the key and why; fix the answer
with the person, never by editing the file yourself.

If it warns that the file is not ignored by git, say so and offer `jig init`, which adds the
line to `.gitignore`. End with `.ai/scripts/jig status`: its `config.local:` lines are what
took effect.
