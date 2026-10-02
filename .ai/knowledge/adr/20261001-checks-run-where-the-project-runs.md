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
reviewed_at: 2026-10-02
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
  short-syntax volume; `-w` its mount target). DDEV (`.ddev/config.yaml`: `ddev exec --raw`),
  Lando (`.lando.yml`) and a devcontainer (`devcontainer.json`) follow, before the generic
  compose reading, because a devcontainer or Lando project may well contain a compose file.
  Lando and a devcontainer without its CLI are reached with `docker exec -i -w <target>
  <container>`, the container found by its label (`io.lando.container`,
  `devcontainer.local_folder`) among those mounting the project — `lando ssh -c` takes one
  string, which a prefix of plain words cannot build. A detector that recognises the project
  but finds no running container refuses with its start command. A shell already inside such
  an environment (`REMOTE_CONTAINERS`, `CODESPACES`, `IS_DDEV_PROJECT`, `LANDO`) runs on the
  host: it is where the project runs. Each detector also knows how to start its environment,
  for the refusal below.
- **Stacks that live outside the project come last**, and only when the project shows no
  sign of its own: an ambiguous mount, a `DB_HOST` naming a compose service or a
  manifest-less `.ddev/` keep their refusal rather than lose it to a stack found on the
  machine. **Devilbox** keeps every project under one data folder outside the project —
  often not the stack's own `data/www` — so nothing in the project names it; its PHP
  container does: the compose service `php` with a bind mount at `/shared/httpd` whose
  source (Docker Desktop's `/host_mnt` or `/run/desktop/mnt/host` prefix removed) is the
  project root or an ancestor of it. The prefix is `docker exec -i -u <MY_USER, else
  devilbox> -w /shared/httpd/<the project's relative path> <container>`. Stopped containers
  are read too (`docker ps -a`): one found only stopped is a refusal with `docker compose up
  -d` in the stack's folder, not a quiet run on the host. A worktree outside the data folder
  whose main checkout is inside it is refused like any environment that does not see this
  checkout. **Laravel Herd** is a host runtime, not a container: when Herd is installed
  (`~/Library/Application Support/Herd` or `~/.config/herd`, with `bin/php`) and the
  project, or its main checkout, is one of its sites (a direct child of a folder in `paths`
  of its Valet `config.json`, or the target of a link there), the answer is a directory for
  `PATH`, not a prefix.
- **A directory for `PATH` is a second local-only key, `run.path`**: `auto` (default — the
  Herd detector's answer) or a directory, blanks allowed, put first on `PATH` whenever the
  checks run on this machine and ignored under a prefix. It must be absolute: a relative one
  would name another folder depending on where verify starts. `cmd_verify` prepends it for
  every profile, adapted or not: it changes which host tool answers, the one a person's own
  shell finds, and breaks nothing a profile does on the host, so it is not a capability. A
  directory that does not exist is a refusal. `run.exec: host` turns the Herd detection off
  with the rest; an explicit `run.path` still applies.
- **A sign without a detector is a refusal.** Two services mounting the project, `DB_HOST`
  in `.env` naming a compose service, a `.devcontainer/` or `.ddev/` folder without its manifest: `jig verify`
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
- **Recognise Devilbox by the project's path** (`<stack>/data/www/<project>`). Rejected: real
  installs move the data folder out of the stack (`HOST_PATH_HTTPD_DATADIR`), and the stack's
  folder is not knowable from the project; the container's mount is.
- **Any running container that mounts an ancestor of the project.** Rejected: a container
  that mounts `$HOME` or `/Users` (an IDE server, a tool's helper) would take every project's
  checks into a container that has neither the project's runtime nor its user. Each such
  stack is a named detector with a signature of its own.
- **Herd through `run.exec env PATH=...`.** Rejected: the prefix is plain words, Herd's macOS
  home holds a blank, and `PATH=` would replace the search path rather than extend it.

## Consequences

- A Sail or compose project is checked in its container with no setting written; a project
  with signs and no detector stops with a sentence that says what to do.
- Every further environment (devcontainer, DDEV, Lando, Devilbox and Herd are done) is a detector in
  `runenv.sh` plus a test, and every further profile adaptation is `environment` in its
  `scope` plus `jp_have` for `command -v`. Both are filed as follow-up tasks.
- Every built-in profile now declares the capability (a follow-up completed the nine that were
  left). Two choices there: a profile's host-resolved absolute paths and shell-function wrappers
  became command words run through `jp_run`/`jp_exec` (`go`, `dotnet`, the Gradle and Maven
  commands), and the python profile, which reads tools from the project's own virtualenv, takes
  them under an environment from a `.venv/` or `venv/` that runs there, else from the
  environment's `PATH`, never from the host's `$VIRTUAL_ENV` or poetry.
- A worktree with a container of the main checkout is refused; giving each worktree its own
  environment is the person's choice and cost.
- The prefix is plain words: a path with a blank cannot be written in `run.exec`; Herd's
  case is answered by `run.path`, and a Devilbox project whose folder holds a blank is refused.
- With `run.exec: auto`, every run that no project file places asks `docker ps -a` once
  (tens of milliseconds; nothing when docker is absent or its daemon is down): Devilbox leaves
  no trace in the project to ask first.
