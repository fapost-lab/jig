# Profile layers — a profile builds on another, as an image builds on its base

Depth: deep — the idea retires the rule that every shipped `verify.sh` is an independent file
(D2/D3, quoted in `profiles/laravel/verify.sh`) and changes the profile format every project
reads.

## Idea

In the human's words, translated from Russian: "I gave the example of Docker, where we can add
different images. In the same way I would like to be able to add dependencies here and somehow
interact with them. Tests are the example, because in Laravel and in PHP both run PHPUnit."

A dependency here is another profile, not a service: the human confirmed it with the case below.

## Goal and problem

- Who is worse off without this, and how:
  - A Laravel project gets `[generic, laravel, php]` from `jig init`. `laravel` runs
    `php artisan test` and `php` runs `phpunit`: the same suite twice. On the reporting project,
    about a thousand test files and ~19 minutes a pass, every `jig verify` costs ~38 minutes.
  - To change three arguments (`--parallel --functional` for a full run, `--compact` for a
    narrowed one) the project copied `laravel/verify.sh` into `.ai/profiles/warehouse/`
    (230 lines) and pulled `composer validate` over from `php`. Upstream fixes to the selection
    logic stopped reaching it.
  - The copy's `profile.yaml` says it "replaces the laravel and php profiles", but Jig has no such
    key and reads nothing from it. `profiles:` still listed `laravel` and `php`, the copy was never
    run, and nothing warned: the only signal was the 38 minutes.
  - Stock profile authors: `laravel/verify.sh` keeps its own copy of php's narrowing rules,
    because profiles may not share code, so a fix lands twice.
- What is true when the work is done:
  - A project layer is a few lines — "the stock laravel checks, with these arguments" — and
    lower layers stay managed and keep receiving `jig upgrade`.
  - A check is addressed by a stable name and can be replaced, reconfigured or dropped from a
    layer above; each such change shows in `--explain` with the layer that made it.
  - No suite runs twice because two layers both carry it.
  - A project profile that exists but does not run is reported, not silent.

## Stress test

- Hidden assumptions — "this holds only if …":
  - Overrides stay correct across upgrades only if check names are stable. Today they are not:
    `php` names its test check `phpunit` or `pest` at run time, and `jp_run` takes the name as a
    free string (`scripts/lib/profile.sh:438`).
  - A declarative check table fits only if `profile.yaml` can hold it. The reader takes the first
    line per key (`profile_get`, `scripts/lib/profiles.sh:24-30`) and lists only inline; a repeated
    key is silently ignored.
  - "Arguments" mean one thing only if full and narrowed runs agree on where they go. They do not:
    a narrowed `artisan test` appends test paths as positional arguments, a full one passes none.
- The main trade-off: expressiveness against a stable surface. Function overrides can say
  anything and turn every private `_php_*` helper into an API; a declarative table says less and
  can be kept stable.
- The weakest point: activation and upgrade. Without changing them, layers do not fix the case
  that motivated them (failure modes 1, 2 and 11 below).
- Failure modes — cause, what breaks, the signal that shows it (independent hunt, ranked by
  likelihood × cost):
  1. `jig upgrade` installs only what `profiles:` lists (`scripts/lib/upgrade.sh:1522`); the
     `requires` closure is computed only at detection. A project listing only its top layer gets
     its bases missing or frozen at an old copy. Signal: `FAIL php: not installed`, or nothing.
  2. The suite still runs twice: `php` stays in `profiles:` on its own while `laravel` inherits
     its checks, or `jig init` re-adds stock `laravel` next to the project layer. Signal: a slow
     run nobody reports.
  3. Unstable check names (above): a `drop phpunit` does nothing on a Pest project, an override
     aimed at a renamed check does nothing after an upgrade. Signal: none while things pass.
  4. The flat YAML reader cannot hold a check table (above). Signal: an override with no effect
     and no parse error.
  5. Arguments differ between full and narrowed runs (above). Signal: failures in `--changed`
     runs only, or CI differing from local — read as flakiness.
  6. Function overrides need a restructuring that does not exist: `verify.sh` is a top-level
     script that runs its checks and exits through `jp_end` (`scripts/lib/profile.sh:486-500`),
     so sourcing a base runs it before anything is overridden. Once restructured, renaming a
     private helper in an upgrade silently disables a project's override.
  7. A base upgrade changes rules a project's overrides relied on; the failure is blamed on the
     upgrade. The keep-modified warning never fires: the project layer is not a managed file.
  8. Project and stock profiles share `.ai/profiles/`: a project layer named `laravel` collides
     with the managed file.
  9. `requires` only warns (`scripts/lib/profiles.sh:274-290`). If `extends` inherits that
     leniency, a layer with a missing base runs partially and reports pass; if strict, it fails
     the whole run.
  10. Output names the profile, not the layer that owns a check's command
      (`scripts/lib/profile.sh:444-452`): triage fixes the wrong layer.
  11. Activation is still forgettable: a project layer missing from `profiles:` with no `detect`
      never runs, and verify passes. The original failure, unchanged.
- Other shapes considered, and why this one: see Decisions.

## Scope and non-goals

- In scope: how a profile builds on another; how a check is named and addressed; what a layer
  may change about a check; activation and upgrade of a layer stack; what `--explain`,
  `jig doctor` and `jig status` say about it.
- Not doing: services a check depends on (databases, queues — the docker-compose reading of the
  idea); the human chose profiles only.

## Decisions

- A dependency is a lower profile layer, not a service — rejected: services as dependencies,
  because the motivating case is about checks, and running services is a separate, larger idea.
- A layer changes the layer below declaratively: a check table in `profile.yaml` (or a file next
  to it) names each check, its command, its arguments for a full and for a narrowed run, and
  whether it is dropped; a layer above states only what differs — rejected for now: overriding
  shell functions of the base's `verify.sh` (alone or as an escape hatch), because it needs every
  stock profile rewritten into functions and turns every private helper into an API whose rename
  silently disables a project's override (failure mode 6). Revisit only on a real case the table
  cannot express. Prerequisites this decision brings: stable check names, a format that holds the
  table (failure mode 4), and an explicit rule for where arguments and narrowed test paths go
  (failure mode 5).
- A check is named by its role, not its tool: `php:tests`, `php:static`, `php:style`,
  `php:manifest`. The tool chosen at run time (phpunit or pest) is a detail inside the check,
  shown in `--explain` — rejected: naming by tool, because a `pest` project would silently escape
  an override aimed at `phpunit` (failure mode 3). Renaming a stock check is a breaking change and
  goes in the changelog. With role names, `laravel` overriding `php:tests` is what ends the
  duplicate suite.
- `profiles:` lists the top layers only; Jig resolves the layers below, installs and upgrades them,
  and runs each layer once however many layers above name it. A missing base is an error, not a
  warning. A profile under `.ai/profiles/` that no active stack reaches is named by `jig doctor`
  and `jig status` — rejected: keeping `requires` as a warning and the list as the user writes it,
  because that is exactly how warehouse was never run (failure modes 1, 2, 9, 11).
- Project layers stay in `.ai/profiles/`, and a project layer may not take a stock profile's name:
  the clash is an error naming both — rejected: a separate directory for project layers, because
  it moves every existing project profile and changes how they are found, for a collision a name
  rule prevents at the same cost (failure mode 8). Which profiles are stock is what the manifest
  already records.
- The duplicate PHPUnit run is fixed now in the stock profiles, ahead of layers: `php` leaves its
  test check to `laravel` when both are active and says so in `--explain` — task
  `laravel-php-duplicate-suite`. Laravel projects stop paying a second ~19-minute pass in the next
  release; once layers exist the fix is replaced by `laravel` overriding `php:tests` — rejected:
  waiting for layers, because that is several phases away and the cost is paid on every run.

## Open questions

- The exact form of the check table: dotted keys in `profile.yaml`, or a separate file the flat
  reader can hold — decided in the first phase's design.
- How a check's narrowing logic (the shell that maps changed files to tests) is inherited when a
  layer only changes arguments — it must stay the base's code, reached through the table.

## Assumptions left untested

- Other stacks have the same shape (a framework profile over a language profile running the same
  suite) — taken at deep from one case; a look at the other stock profiles would test it.
