---
id: adr-20261107-a-profile-covers-a-check-of-another
type: adr
status: accepted
date: 2026-11-07
domains:
  - verify
paths:
  - scripts/lib/verify.sh
  - scripts/lib/profile.sh
  - scripts/lib/profiles.sh
  - "profiles/**"
  - schemas/profile.md
summary: "Why the profile above declares the check of the profile below its own replaces (covers: [php:tests]) and the one below only names it (checks: [tests]), why jig verify decides the cover once per run and hands down the decision, why the covered map follows the tests, and why the unreleased scope: profiles capability was removed rather than kept beside it."
---
# The profile above declares the check its own replaces (`covers: [php:tests]`), the profile below only names it (`checks: [tests]`), and `jig verify` decides the cover

## Context

A Laravel project activates `laravel` and the `php` it requires. `laravel` runs `php artisan test`
and `php` runs PHPUnit or Pest: the same suite, two serial passes on every `jig verify` (~19 minutes
each on the project that reported it). Pull request #411, merged after 0.40.0 and in no release,
stopped it with a new capability, `scope: [..., profiles]`: `php` received the profiles the run
starts (`JIG_VERIFY_PROFILES`), asked `jp_in_run laravel`, checked `[ -f artisan ]`, and skipped
its tests.

That put the knowledge in the wrong profile. A base profile now knew about the profile built on it,
so any profile on top of a stock one — a project's own, under `.ai/profiles/`, over `node` or
`python` — could only stop a duplicate by editing the stock base, which a project cannot do: the
file is managed and `jig upgrade` replaces it. And `php` kept its tests whenever its own
`.ai/verify/php.map` handed it decisions, because `laravel` reads only `laravel.map`: such a
project still ran the suite twice.

The spec `.ai/specs/profile-layers/` aims at layers — a profile that extends another and overrides a
check by its role name. That is several phases away. This decision is its first small step.

## Decision

- **The profile above declares the cover.** `covers: [<profile>:<check>]` in its `profile.yaml`;
  `laravel` declares `covers: [php:tests]`.
- **The profile below names the check, by role, and nothing else.** `checks: [tests]` in its
  `profile.yaml`, and its `verify.sh` asks `jp_covered tests <label>` before running the check.
  `php`, `laravel`, `node` and `python` name `tests`. `profiles/php/verify.sh` mentions neither
  laravel nor artisan.
- **`jig verify` decides, once per run** (`_verify_covers`). A cover holds when both profiles start
  (the gates the loop applies: a `verify.sh`, `explain` in a preview, `environment` under one), the
  covering profile applies to the project (`profiles_applies`: its `detect` is `always`, absent, or
  matches — `laravel` without an `artisan` covers nothing, as #411's artisan test did), and the
  covered profile lists the check under `checks`. A cover of an unnamed check is a warning and the
  check runs. The first covering profile in run order wins. Covers chain (`warehouse` over
  `laravel` over `php`): each is followed to the profile that finally runs the check
  (`_verify_covers_resolve`), and a chain that returns to its start is dropped with a warning,
  since it would run the check nowhere.
- **The decision is handed down**: `JIG_VERIFY_COVERED=<check>=<profile>` to the covered profile,
  unset for every other one. `jp_covered` prints `skip (scope: covered by <profile>,
  <lower>:<check>)`, or the `PLAN` line in a preview. The reason starts `scope:`, so it counts as
  narrowing, never as a missing tool. The wording is the library's, not a profile's.
- **The map follows the tests.** A map's decisions narrow its profile's tests, so when
  `<lower>:tests` is covered, `.ai/verify/<lower>.map` is read for the covering profile after its
  own map — along a chain, the nearest profile's map first — and the result line names every map
  read. Only a profile that declares `map` hands its map on. A covering profile that
  narrows but cannot read maps does not take tests whose map would be dropped: a warning, and the
  lower profile keeps them. Covering `<lower>:tests` accepts the lower profile's filter vocabulary;
  `php` and `laravel` share it (a test file path).
- **`scope: profiles`, `JIG_VERIFY_PROFILES` and `jp_in_run` are removed.** `git tag --contains` of
  #411's merge commit is empty: no project has them, so this is not a breaking change, and two
  mechanisms for one question would be kept forever (`profile.sh` never renames a released
  function).

## Alternatives

- **Keep #411.** Rejected: the base profile names the one above it, a project's profile over a stock
  one has no way in, and `php.map` still runs the suite twice.
- **Jig skips the check itself, without the profile's help.** Not possible yet: a check lives inside a
  `verify.sh`, a top-level script Jig starts as a whole (spec, failure mode 6). Until Phase 2's check
  table exists, Jig can only decide the cover and pass the decision down; the profile below names
  its role and calls the library.
- **Match the cover against the tool name a profile prints** (`php:phpunit`, `php:pest`). Rejected:
  a Pest project would escape a cover aimed at PHPUnit (spec, failure mode 3). Roles, as the spec
  decides.
- **Declare the capability in `scope` (`scope: [..., covers]`), as every other one.** Rejected:
  a profile honours a cover check by check, and a capability in `scope` would say only that it
  understands the variable, not which check answers to which name, so a cover aimed at a check
  the profile never named (`php:test`) would stand nothing down in silence. `checks` is the
  declaration and the list a cover is validated against at once; it amends the verify rule that
  a capability is named in `scope`, for this one capability.
- **Hand `JIG_VERIFY_COVERED` to every profile, without `checks`.** Rejected: support is declared,
  never inferred, and without the declaration a cover of a check nobody honours — a typo, a profile
  a project edited before the key existed — would run twice in silence. With `checks`, Jig warns.
- **Keep the covered profile's tests whenever it has a map** (#411). Rejected: the suite then runs
  twice exactly for the projects that tuned their narrowing. Dropping the map would be worse — its
  `ALL` lines would run no test at all.
- **Name every stock profile's test check now.** Deferred: `jvm`'s Gradle `check` is wider than its
  tests and `swift` interleaves build and test, so naming them takes per-profile decisions that
  belong to the spec's Phase 2 ("stock profiles declare their checks"). Until then a cover of their
  tests warns.

## Consequences

- A project profile replaces a stock profile's tests with one line, and the stock profile stays
  managed and keeps receiving upgrades. The warehouse case is `covers: [laravel:tests]`.
- A Laravel project runs its suite once, with or without `php.map` and `laravel.map`.
- A covering profile whose own check cannot run (its tool is missing) leaves the suite unrun; its
  skip is not a `scope:` skip, so the run is not read as narrowing.
- `profile.sh` gains `jp_covered`, a distributed function: never renamed, never given a new meaning.
- The next steps of the spec — a check table, overrides, `extends` — build on `checks` names rather
  than beside them; a stock check renamed later is a breaking change and goes in the changelog.
