---
name: jig-setup
description: Ask a person, one question at a time in plain words, how far their agent may go on its own — git rights, autopilot without questions, CI wait, cleanup — and write their answers to their personal `.ai/config.local.yaml` after a yes. Use after `jig init`, or when the user says "set up Jig for me", "configure my settings", "change my personal settings", "let the agent merge".
---

# jig-setup — personal settings, asked for in plain words

The person may not know `.ai/config.local.yaml` exists. You ask; `jig config set --local`
checks and writes (ADR-0001). The file is theirs alone: it changes what **their** agent does
in **this** clone, never a colleague's. Never write `.ai/config.yaml` — the team's file, edited
by hand.

## Speak in blocks

Say each message in the form Jig's reports and its installer use
(adr-20261005-the-installer-speaks-one-form-in-two-shells), in a code block so the columns
survive: a level word padded to six columns, then the first line; every further line indented
six columns. `ask` is a question, with the options and your recommendation on the lines under
it; `ok` is what is now set; `warn` is what needs the person (an `ignored:` key, a file git does
not ignore); `fail` is a refusal. One question per message stays the rule. For example:

```
ask   When the agent finishes a task, how far should it take the change?
      none    leave the change for you to commit (default)
      pr      commit, push and open the pull request
      I recommend pr: gh is installed and signed in.
```

`jig config set --dry-run` output is shown verbatim, as below, never re-laid-out: it is the file.

## 1. Start from what is set

```
.ai/scripts/jig config show --local
```

Say in one line what is already set, or that nothing is. Any `ignored:` line is a key no
reader answers from — a misspelling, or a setting from a Jig that had it: name those, say they
do nothing, and offer to remove them. On a yes:

```
.ai/scripts/jig config unset <key> [<key>...] --local
```

Then ask the questions below, **one per message**, in the person's words — no key names unless
they ask. Each question says what the choice changes, offers the options, and names your
recommendation with its reason. A person who says "keep the default" or "skip" moves on:
nothing is written for that question. One who wants a setting they already have taken out of
their own file is answered by `config unset` too — say that the key then answers from
`.ai/config.yaml` if the team set it there, and from the default otherwise.

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
5. **At once** (`autopilot.parallel`). "When a whole roadmap phase runs, how many of its tasks
   may agents work on at the same time?" Each one gets its own folder and its own agent, so
   more means more of the machine and more to read when they finish. Default 2, at most 16.
   Recommend 2, or 1 for someone who wants to watch every change.
6. **Process** (`route.depth`). "How much process should your tasks get?" `full` — each risk
   class's whole route (default); `lean` — a shorter analysis, the plan folded into it, one
   review round where the class allows it. Say what never changes: tests on changed files, CI
   before a merge, the design approval and architecture review of risky work. Recommend `full`;
   `lean` for someone who would rather trade a little review depth for time and tokens. One
   task can always differ.
7. **Cleanup** (`housekeeping.*`) — one question, offer to skip: how long an abandoned task is
   kept (`abandoned_ttl`, 14d), how long the trash is kept (`trash_ttl`, 7d), when an idle task
   is called stale (`stale_after`, 60d), how often cleanup runs (`cadence`, whole days, 1d),
   whether it may `git fetch` (`fetch`, true). Recommend the defaults.
8. **Worktrees** (`git.worktree_root`) — only if they run several agents at once and want the
   task folders somewhere other than `../<project>.worktrees`.
9. **Where the checks run** (`run.exec`). First run `.ai/scripts/jig verify --explain` and read
   its `verify: checks run in …` or `verify: refused: …` line: it names what Jig detected, or
   the signs of a container it could not place. Ask: "Where do this project's tests run — here,
   or in a container?" With a detection that is right, nothing needs writing (`auto` keeps
   finding it); say so. Otherwise offer `host`, or the command prefix that reaches the
   container — work it out from the project (`docker compose exec -T -w <dir> <service>`,
   `docker exec -i -w <dir> <container>`) and show it; never ask the person to type one. A PHP on
   this machine that is not first on `PATH` and was not detected (Herd's is) goes to `run.path`,
   the folder that holds it.
10. **Helpers** (`claude.implement_model`, `claude.review_model`) — only in Claude Code. Explain:
    the agent can hand writing the code, and reviewing it, to a helper on another model; what the
    helper does is still checked — review findings block, the checks must pass — and the agent
    keeps the design, the decisions and shipping. One review setting covers every review,
    architecture review included. Ask: "Should helpers do the coding and the reviews, and on
    which model?" Options: no helpers (default — the agent does every stage itself); one model for
    both; a different one for each. Write the name as the person gives it — `sonnet`, `opus`,
    `haiku` or a full model id: Jig passes it to Claude Code unchanged and checks nothing.
    Recommend no helpers to someone unsure why they would want them; `sonnet` for both to someone
    whose session runs on Opus and who wants their limits to last.

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
