# Project configuration

`.ai/config.yaml`, flat YAML subset: `section.key: value`, inline lists only, no nesting.
Reference: `domains/install`. Read with `cfg`, `cfg_list`, `cfg_bool` from `scripts/lib/config.sh`.
Absent keys take the default. Paths are not configurable.

| Key | Default | Local | Meaning |
|---|---|---|---|
| `profiles` | `[generic]` | | active profiles; `generic` is always included |
| `adapters` | `[claude, codex]` | | runtimes to install skills for |
| `git.base_branch` | `main` | | merge target for ancestry checks; a new config from `jig init` names the repository's default branch (origin/HEAD, else `main` or `master`, else the current branch) |
| `git.branch_per_task` | `true` | | `jig task start` creates and checks out a branch |
| `git.branch_template` | `task/{id}` | | branch name; `{id}` is the task id |
| `git.worktree_root` | `../<project>.worktrees` | yes | where `jig task start --worktree` puts worktrees |
| `git.delete_merged_branches` | `true` | yes | a branch Jig made goes once its work has landed: right after a merge Jig made (back on the base branch, then `git branch -d` and origin's copy), and in housekeeping once its task is purged (origin's copy there only at `agent.git` `push` or above); `false` keeps every branch (adr-20261007-a-merged-branch-leaves-with-its-work) |
| `worktree.carry` | `[]` | | extra paths this project needs copied into a new worktree, beyond what the active profiles already declare (`vendor`, `node_modules`, `.env`) |
| `worktree.share` | `[]` | | directories a new worktree shares with this checkout rather than copies — each given as a real directory whose entries link to this checkout's, for separate repositories under edit such as `packages/` |
| `forge` | `auto` | | `auto`, `github`, `gitlab`, `none` |
| `housekeeping.cadence` | `1d` | yes | session hook runs housekeeping when the last run is older |
| `housekeeping.fetch` | `true` | yes | allow `git fetch` during housekeeping |
| `housekeeping.trash_ttl` | `7d` | yes | trash entries older than this are deleted |
| `housekeeping.abandoned_ttl` | `14d` | yes | abandoned workspaces are purged after this |
| `housekeeping.stale_after` | `60d` | yes | older active tasks are reported as `STALE_CANDIDATE` |
| `checkout.busy_ttl` | `12h` | yes | how long a checkout's record of work in progress still counts as a live session (adr-20260924-a-checkout-records-what-is-happening-in-it) |
| `agent.git` | `none` | only | how far the agent takes a finished task (`jig task ship`) and a spec's declaration, epic branch and final pull request (`jig spec ship`): `none`, `commit`, `push`, `pr`, `merge` — `merge` also merges the pull request once CI passed, never past branch protection; an epic's only in an unattended run (ADR adr-20260921-agent-git-rights-are-a-local-setting, adr-20260922-spec-work-ships-by-the-agent-git-level, adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci) |
| `agent.ci_timeout` | `30` | only | minutes `merge` waits for the pull request's checks before leaving it open; `0` looks once. Whole minutes |
| `autopilot.git` | - | only | the git level of an autopilot run, same values as `agent.git`: `jig task ship` of a task whose run is `on` (or `stopped`, unattended), and `jig spec ship` when `autopilot.unattended` is `true`; not set, `agent.git` answers. `jig upgrade` and every other ship keep `agent.git`; `release.merge: human` still wins for an epic's final merge (adr-20260921-agent-git-rights-are-a-local-setting, amended 2026-10-08) |
| `autopilot.unattended` | `false` | only | `true`: an autopilot run asks nothing — each stop becomes a safe default recorded in the pull request — and an epic's final pull request may be merged (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci) |
| `autopilot.parallel` | `2` | only | how many tasks of a roadmap phase a phase run has agents building at once, 1 to 16; a task whose work is consolidated and waiting its turn to ship holds no slot, and the agents that repair the merge queue are outside the limit (adr-20260922-a-phase-run-is-coordinated) |
| `route.depth` | `full` | only | how much of its class's route a task runs: `full`, or `lean`, which trims the analysis, the plan and a second review round where the class allows it and never below the class's floor — tests on changed files, CI before a merge, consolidation, and a T3/T4 gate and architecture review stay. A task's own `route_depth` (`jig task new --lean`, `jig task set`) wins over it; `jig task route <id>` names the result (adr-20261002-route-depth-is-a-personal-choice) |
| `release.merge` | `agent` | only | who merges an epic's final pull request — the release — in an unattended run at `agent.git: merge`: `agent` merges it once CI passed (a `major` is always a draft), `human` opens it and leaves the merge to you; it changes nothing for task pull requests, which `agent.git` governs (ADR-0040 as amended 2026-10-04) |
| `knowledge.require_frontmatter` | `true` | | `jig knowledge check` fails on missing frontmatter |
| `verify.full_run` | `local` | | `local` runs everything by default; `ci` narrows a flag-less `jig verify` to changed files, trusting CI to run the full set on the pull request |
| `verify.busy_ttl` | `30m` | yes | how long a run record still counts as a live `jig verify` on this clone; a second run waits while one is live, `0` never waits, and `CI` switches the whole mechanism off (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass) |
| `run.exec` | `auto` | only | where this machine runs the project's checks: `auto` detects (Laravel Sail, DDEV, Lando, a devcontainer, a docker compose service mounting the project, Devilbox) and refuses when a container is likely but unrecognised; `host` runs them here; anything else is a command prefix of plain words put in front of each check (adr-20261001-checks-run-where-the-project-runs) |
| `run.path` | `auto` | only | a directory put first on `PATH` for the checks when they run on this machine — a host runtime that is not first there; `auto` takes the Laravel Herd detector's answer, nothing otherwise (adr-20261001-checks-run-where-the-project-runs) |
| `claude.implement_model` | - | only | the model Claude Code hands the implement stage to, as a subagent: any value the runtime understands (`sonnet`, `opus`, `haiku`, a full model id), carried as written and never checked by Jig. Unset, nobody is handed the stage and the agent implements it itself; `jig task route <id>` prints a `delegate:` line when it is set (adr-20261005-jig-names-the-roles-not-the-models) |
| `claude.review_model` | - | only | the same for every review stage of a route — review, a T4's independent review, a T3/T4's architecture review; unset, a review still runs in a fresh context where the skill asks for one, on the session's own model. No line for a route without a review (T0, T1) |
| `notify.telegram.token` | - | only | the Telegram bot token autopilot messages are sent with; never printed (`********`), refused by `jig config set` — written into the file by hand. With it or the chat id missing nothing is sent (adr-20261009-autopilot-stops-reach-telegram) |
| `notify.telegram.chat_id` | - | only | the chat the messages go to: digits (a group's start with `-`) or `@name` |
| `notify.autopilot` | `true` | only | `false` stops autopilot runs' messages — a stop, an end, and an unattended run's approve and decide — while the token and chat id stay set |
| `notify.interactive` | `false` | only | `true` also sends the message when an ordinary session waits for the person's permission or answer, through the runtime hook they connected to `.ai/scripts/jig-notify-hook` (adr-20261010-a-waiting-session-reaches-telegram) |

Durations: `<n>d`, `<n>h`, `<n>m`, `<n>s`.

## Local overrides

`.ai/config.local.yaml`, same format, gitignored, created by nobody but the person who wants
it (ADR-0038). It is read before `.ai/config.yaml`, and only for the keys marked **Local**:
their answer may differ between contributors without changing what the project does. A value
for any other key is ignored. An empty value falls through to `.ai/config.yaml`.

Written by hand, or through `jig config`, which writes only this file (the main checkout's,
from a worktree) and refuses without `--local`: nothing writes `.ai/config.yaml`, which the
team edits by hand. The `jig-setup` skill asks for the values and runs it.

| Command | What it does |
|---|---|
| `jig config set <key> <value> [...] --local [--dry-run]` | sets local keys only, to values the readers accept; every pair is checked before any is written, the file is replaced atomically, and a key is replaced at its first line (the one `cfg` reads) or appended |
| `jig config unset <key> [...] --local [--dry-run]` | removes every line setting each key — any key the file holds, ignored ones included, which is how a person clears out what no reader answers from; a key the file does not hold is reported and nothing is written |
| `jig config show --local` | prints the file — the token's value as `********` — then an `ignored:` line for each key in it that no reader answers from |
| `jig config keys` | prints every key jig reads, its default and which file answers for it, marking each key the project's `.ai/config.yaml` does not mention; writes nothing and takes no `--local` |

Values `set` accepts, per key:

| Key | Accepted |
|---|---|
| `housekeeping.cadence` | whole days (`3d` or `3`) |
| `housekeeping.trash_ttl`, `housekeeping.abandoned_ttl`, `housekeeping.stale_after`, `checkout.busy_ttl`, `verify.busy_ttl` | `<n>[dhms]`; `verify.busy_ttl` also takes `0` |
| `housekeeping.fetch`, `git.delete_merged_branches`, `autopilot.unattended`, `notify.autopilot`, `notify.interactive` | `true` or `false` |
| `agent.git`, `autopilot.git` | `none`, `commit`, `push`, `pr`, `merge` |
| `agent.ci_timeout` | whole minutes, 0 to 9999 |
| `autopilot.parallel` | a whole number, 1 to 16 |
| `route.depth` | `full` or `lean` |
| `release.merge` | `agent` or `human` |
| `git.worktree_root` | a path, unquoted |
| `run.exec` | `auto`, `host`, or a command of plain words: no quote, `$`, backtick or backslash |
| `run.path` | `auto` or the absolute path of a directory, unquoted; blanks inside it are kept |
| `claude.implement_model`, `claude.review_model` | anything the file can hold: the value is the runtime's to understand, not Jig's |
| `notify.telegram.chat_id` | digits, with a leading `-` for a group, or `@name` |
| `notify.telegram.token` | nothing: a token on a command line is kept by `ps`, the shell history and the agent's transcript, so `set` refuses it and you write the line yourself |

No value may hold a line break, a `#` (the file reads one as the start of a comment) or
surrounding blanks.

There is one file per clone. A task worktree reads the file in the checkout it was added
from; a `.ai/config.local.yaml` inside the worktree is not read.

`jig status` prints a `config.local:` line for each key the file sets, each key it ignores,
and a warning when git does not ignore the file — a project installed before the line
existed in `templates/gitignore` gets it from `jig init`. `jig doctor` reports the same
warning.

A key marked **only** is read from the local file and never from `.ai/config.yaml`: a committed
value would apply to every contributor, which is exactly what such a key must not do. A value
for it in `.ai/config.yaml` is ignored, and `jig status` and `jig doctor` say so.

The list of local keys is `JIG_CFG_LOCAL_KEYS` in `scripts/lib/config.sh`, and the local-only
ones are also in `JIG_CFG_LOCAL_ONLY_KEYS`; a key added there is added to this table.

## The key inventory

The table above is not the source. `jig_config_keys` in `scripts/lib/config.sh` holds one
`<key> <default>` line per key jig reads, and `tests/config.t.sh` refuses to pass unless that
list, the `cfg`/`cfg_bool`/`cfg_list`/`cfg_list_lines` call sites it greps out of `scripts/`,
this table, `templates/config.yaml` and `docs/configuration.mdx` all agree on one set of keys
and one set of defaults. Adding a key means adding it in all of those places; the test names
whichever one was forgotten.

One key is exempt from the default comparison and says so in the test: `git.worktree_root` is
read as `cfg git.worktree_root ""`, and `_task_worktree_root` derives `../<project>.worktrees`
from the project's own directory name, which no literal at the call site could hold.

`jig_config_unmentioned` and `jig_config_unknown` compare the project's file against that
inventory — the keys it says nothing about, and the keys it sets that nothing reads. Both are
reporting only: nothing writes `.ai/config.yaml` (ADR-0024). `jig doctor` prints them, and only
when there is something to print; `jig status` does not, because an unmentioned key is a
capability to look at, not anything a task is waiting on.
