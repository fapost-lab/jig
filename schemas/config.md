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
| `worktree.carry` | `[]` | | extra paths this project needs copied into a new worktree, beyond what the active profiles already declare (`vendor`, `node_modules`, `.env`) |
| `forge` | `auto` | | `auto`, `github`, `gitlab`, `none` |
| `housekeeping.cadence` | `1d` | yes | session hook runs housekeeping when the last run is older |
| `housekeeping.fetch` | `true` | yes | allow `git fetch` during housekeeping |
| `housekeeping.trash_ttl` | `7d` | yes | trash entries older than this are deleted |
| `housekeeping.abandoned_ttl` | `14d` | yes | abandoned workspaces are purged after this |
| `housekeeping.stale_after` | `60d` | yes | older active tasks are reported as `STALE_CANDIDATE` |
| `checkout.busy_ttl` | `12h` | yes | how long a checkout's record of work in progress still counts as a live session (adr-20260924-a-checkout-records-what-is-happening-in-it) |
| `agent.git` | `none` | only | how far the agent takes a finished task (`jig task ship`) and a spec's declaration, epic branch and final pull request (`jig spec ship`): `none`, `commit`, `push`, `pr`, `merge` — `merge` also merges the pull request once CI passed, never past branch protection; an epic's only in an unattended run (ADR adr-20260921-agent-git-rights-are-a-local-setting, adr-20260922-spec-work-ships-by-the-agent-git-level, adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci) |
| `agent.ci_timeout` | `30` | only | minutes `merge` waits for the pull request's checks before leaving it open; `0` looks once. Whole minutes |
| `autopilot.unattended` | `false` | only | `true`: an autopilot run asks nothing — each stop becomes a safe default recorded in the pull request — and an epic's final pull request may be merged (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci) |
| `autopilot.parallel` | `2` | only | how many tasks of a roadmap phase a phase run has agents building at once, 1 to 16; a task whose work is consolidated and waiting its turn to ship holds no slot, and the agents that repair the merge queue are outside the limit (adr-20260922-a-phase-run-is-coordinated) |
| `knowledge.require_frontmatter` | `true` | | `jig knowledge check` fails on missing frontmatter |
| `verify.full_run` | `local` | | `local` runs everything by default; `ci` narrows a flag-less `jig verify` to changed files, trusting CI to run the full set on the pull request |

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
| `jig config show --local` | prints the file, then an `ignored:` line for each key in it that no reader answers from |

Values `set` accepts, per key:

| Key | Accepted |
|---|---|
| `housekeeping.cadence` | whole days (`3d` or `3`) |
| `housekeeping.trash_ttl`, `housekeeping.abandoned_ttl`, `housekeeping.stale_after`, `checkout.busy_ttl` | `<n>[dhms]` |
| `housekeeping.fetch`, `autopilot.unattended` | `true` or `false` |
| `agent.git` | `none`, `commit`, `push`, `pr`, `merge` |
| `agent.ci_timeout` | whole minutes, 0 to 9999 |
| `autopilot.parallel` | a whole number, 1 to 16 |
| `git.worktree_root` | a path, unquoted |

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
