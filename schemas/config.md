# Project configuration

`.ai/config.yaml`, flat YAML subset: `section.key: value`, inline lists only, no nesting.
Reference: SPEC §6.1. Read with `cfg`, `cfg_list`, `cfg_bool` from `scripts/lib/config.sh`.
Absent keys take the default. Paths are not configurable.

| Key | Default | Meaning |
|---|---|---|
| `profiles` | `[generic]` | active profiles; `generic` is always included |
| `adapters` | `[claude, codex]` | runtimes to install skills for |
| `git.base_branch` | `main` | merge target for ancestry checks |
| `forge` | `auto` | `auto`, `github`, `gitlab`, `none` |
| `housekeeping.cadence` | `1d` | session hook runs housekeeping when the last run is older |
| `housekeeping.fetch` | `true` | allow `git fetch` during housekeeping |
| `housekeeping.trash_ttl` | `7d` | trash entries older than this are deleted |
| `housekeeping.abandoned_ttl` | `14d` | abandoned workspaces are purged after this |
| `housekeeping.stale_after` | `60d` | older active tasks are reported as `STALE_CANDIDATE` |
| `knowledge.require_frontmatter` | `true` | `jig knowledge check` fails on missing frontmatter |

Durations: `<n>d`, `<n>h`, `<n>m`, `<n>s`.
