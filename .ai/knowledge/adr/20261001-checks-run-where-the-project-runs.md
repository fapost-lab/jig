---
id: adr-20261001-checks-run-where-the-project-runs
type: adr
status: accepted
date: 2026-10-01
domains:
  - verify
paths:
  - scripts/lib/runenv.sh
  - scripts/lib/verify.sh
  - scripts/lib/profile.sh
  - "profiles/**"
  - schemas/profile.md
  - schemas/config.md
  - skills/jig-setup/SKILL.md
summary: Why jig verify decides once where a project's commands run (host or a container prefix from run.exec or a detector), refuses rather than guessing the host, and passes the prefix only to profiles declaring the environment capability.
reviewed_at: 2026-10-01
---
# A project's checks run where the project runs, and never on the host by guess

## Context

`jig verify` ran every profile's tools from this machine's `PATH`. On a Laravel project on
Sail that meant the host's PHP 8.2 against a project requiring 8.4, and tests whose `.env`
says `DB_HOST=mysql` — a name that resolves only inside Docker — failing, or, with
`RefreshDatabase`, reaching some other database. Nothing in the profiles knew an environment
existed. The same holds for any stack in any container (docker compose, a devcontainer, DDEV,
Lando, Devilbox) and for a host runtime that is not the first on `PATH` (Herd). The owner
asked for one mechanism for every profile and every environment, for zero configuration —
a detector or the agent writes the setting, a person never does — and for verify never to
run a project's checks on the host silently when signs say the project lives elsewhere.

## Decision

- **One decision per run, before any profile.** `runenv_resolve` (`scripts/lib/runenv.sh`)
  answers where the project's commands run: the host, or a command prefix of plain words
  (`docker compose exec -T -w /app app`). It reads one key, `run.exec`, **local only**:
  `auto` (default), `host`, or the prefix. Where the project runs is a property of one
  person's machine, and a committed value would send every contributor's checks to one
  person's environment.
- **Detectors under `auto`**, first match wins: Laravel Sail (`vendor/bin/sail` and the
  `APP_SERVICE` service, `laravel.test` by default, mounting the project; runs as Sail's
  `sail` user), then docker compose (exactly one service mounting the project root with a
  short-syntax volume; `-w` its mount target). Each one also knows how to start its
  environment, for the refusal below.
- **A sign without a detector is a refusal.** Two services mounting the project, `DB_HOST`
  in `.env` naming a compose service, `.devcontainer/`, `.ddev/`, `.lando.yml`: `jig verify`
  prints why and exits 3 — no verdict — rather than running anything on the host. A compose
  file whose app does not mount the project and whose `DB_HOST` is local is not a sign:
  that is an ordinary host setup and keeps working.
- **One probe before the first check**, for any environment: `<prefix> sh -c 'cat .git'`.
  Its failure means the environment is not running (refusal, with the start command when a
  detector knows it). In a linked worktree, its output must equal this worktree's `.git`
  file: otherwise the container mounts another checkout and its verdict would be about other
  code (refusal).
- **CI is left alone.** With `CI` set, `auto` neither detects nor refuses: a pipeline
  describes its own environment, and existing pipelines must not change under it.
- **A capability, like every other.** The prefix reaches a profile as `JIG_RUN_EXEC` only
  when its `profile.yaml` lists `environment` in `scope`, and is unset for every other
  profile, whatever the caller exported. `profile.sh` gains `jp_exec` (run where the project
  runs) and `jp_have` (is a command there); `jp_run` and `jp_version` run through `jp_exec`,
  which without a prefix is exactly `"$@"` — so an installed user profile sees no change.
- **An unadapted profile under an environment is not run.** Its result is
  `skip (not adapted to run in <where>; its checks were not run on the host)`, counted like a
  skip for a missing tool, so a run where nothing else passed is not a pass. In this change
  `php`, `laravel`, `node` and `generic` declare the capability; the rest follow.
- **`jig verify --explain` names the place** (`verify: checks run in <where>`), and the
  `jig-setup` skill asks where the tests run, shows what was detected, and writes `run.exec`
  through `jig config set --local` only when the detection is wrong or missing.

## Alternatives

- **Run the whole profile inside the container** (`docker compose exec app bash
  .ai/profiles/x/verify.sh`). Rejected: it needs bash and git in the image, the changed-file
  list and the busy record live on the host, and a profile would see the container's
  paths for files `jig verify` computed on the host. Per-command prefixing needs only the
  tool itself in the container.
- **Change `jp_run` for every profile, no capability.** Rejected: profiles that resolve a
  host's absolute path (`go=$(command -v go)`) or run shell functions through `jp_run` would
  break under a prefix, and the verify rules require a new capability to be declared before
  it is granted.
- **Run on the host when nothing is detected, with a warning.** Rejected by the owner: a
  warning beside a green verdict is the silent wrong run this exists to end.
- **Separate keys for readiness, working directory and start command.** Rejected: the
  working directory is part of the prefix (`-w`), and one probe answers readiness for every
  environment; fewer keys is what zero-config means for the person.
- **A project-layer key.** Rejected: colleagues on the same project run it on Herd, Sail or
  Devilbox.

## Consequences

- A Sail or compose project is checked in its container with no setting written; a project
  with signs and no detector stops with a sentence that says what to do.
- Every further environment (devcontainer, DDEV, Lando, Herd, Devilbox) is a detector in
  `runenv.sh` plus a test, and every further profile adaptation is `environment` in its
  `scope` plus `jp_have` for `command -v`. Both are filed as follow-up tasks.
- A worktree with a container of the main checkout is refused; giving each worktree its own
  environment is the person's choice and cost.
- The prefix is plain words: a path with a blank cannot be written in `run.exec` (Herd's
  case), which the Herd detector has to answer differently.
