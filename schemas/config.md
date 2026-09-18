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
| `forge` | `auto` | | `auto`, `github`, `gitlab`, `none` |
| `housekeeping.cadence` | `1d` | yes | session hook runs housekeeping when the last run is older |
| `housekeeping.fetch` | `true` | yes | allow `git fetch` during housekeeping |
| `housekeeping.trash_ttl` | `7d` | yes | trash entries older than this are deleted |
| `housekeeping.abandoned_ttl` | `14d` | yes | abandoned workspaces are purged after this |
| `housekeeping.stale_after` | `60d` | yes | older active tasks are reported as `STALE_CANDIDATE` |
| `knowledge.require_frontmatter` | `true` | | `jig knowledge check` fails on missing frontmatter |
| `verify.full_run` | `local` | | `local` runs everything by default; `ci` narrows a flag-less `jig verify` to changed files, trusting CI to run the full set on the pull request |

Durations: `<n>d`, `<n>h`, `<n>m`, `<n>s`.

## Local overrides

`.ai/config.local.yaml`, same format, gitignored, created by nobody but the person who wants
it (ADR-0038). It is read before `.ai/config.yaml`, and only for the keys marked **Local**:
their answer may differ between contributors without changing what the project does. A value
for any other key is ignored. An empty value falls through to `.ai/config.yaml`.

There is one file per clone. A task worktree reads the file in the checkout it was added
from; a `.ai/config.local.yaml` inside the worktree is not read.

`jig status` prints a `config.local:` line for each key the file sets, each key it ignores,
and a warning when git does not ignore the file — a project installed before the line
existed in `templates/gitignore` gets it from `jig init`. `jig doctor` reports the same
warning.

The list of local keys is `JIG_CFG_LOCAL_KEYS` in `scripts/lib/config.sh`; a key added
there is added to this table.
