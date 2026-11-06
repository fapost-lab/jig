# Roadmap — Profile layers

Destination: a project changes one stock check in a few lines of its own layer, lower layers keep
receiving upgrades, no suite runs twice, and a profile that never runs is named rather than silent.

## Phase 1 — Stop paying for what exists today

Goal: the two failures of the motivating case stop without the layer model. Done when: a Laravel
project's `jig verify --explain` plans one PHPUnit pass, and `jig doctor` names a profile under
`.ai/profiles/` that `profiles:` does not reach.

- [ ] `laravel-php-duplicate-suite` — `php` leaves its test check to `laravel` when both are active, and `--explain` says so
- [ ] Unreached profiles are named — `jig doctor` and `jig status` name a profile under `.ai/profiles/` that no active profile reaches

## Phase 2 — Checks have names

Goal: every check is addressable by a stable role name. Done when: `--explain` prints
`php:tests (phpunit)` style lines for every stock profile, and the names are documented.

- [ ] Check table format — a profile declares its checks by role name, command and full/narrowed arguments in a form the flat reader holds, with an explicit rule for where narrowed test paths go
- [ ] Stock profiles declare their checks — every stock profile's checks carry role names in the table, the tool chosen at run time shown inside the check (after: Check table format — the table must exist to be filled)

## Phase 3 — Profiles build on profiles

Goal: a profile extends another and changes only what differs. Done when: the warehouse case is a
project layer of a few lines over stock `laravel`, and `laravel` no longer copies `php`'s narrowing.

- [ ] Layer stacks resolve — `profiles:` lists top layers; Jig resolves the bases through `extends`, installs and upgrades them, runs each once, fails on a missing base and on a project layer taking a stock name
- [ ] A layer overrides a check — a layer above changes a check's arguments or drops it by role name, and `--explain` names the layer that did (after: Stock profiles declare their checks — overrides need names to aim at; after: Layer stacks resolve — a project layer must sit on its base)
- [ ] `laravel` builds on `php` — `laravel` extends `php`, overrides `php:tests` with `artisan test`, its copied narrowing removed, and the Phase 1 fix retired (after: A layer overrides a check — this is the first stock use of it)
- [ ] fog: function overrides — reached only by a real case the check table cannot express; none is known

## Waves

1. `laravel-php-duplicate-suite`; Unreached profiles are named; Check table format; Layer stacks resolve
2. Stock profiles declare their checks
3. A layer overrides a check
4. `laravel` builds on `php`
