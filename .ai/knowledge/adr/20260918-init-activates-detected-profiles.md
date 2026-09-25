---
id: adr-20260918-init-activates-detected-profiles
type: adr
status: accepted
date: 2026-09-18
domains:
  - install
  - verify
paths:
  - scripts/lib/init.sh
  - scripts/lib/profiles.sh
summary: Why a first jig init without --profiles activates the detected profiles, never widens an existing choice, and skips dependency directories when detecting.
---
# A first `jig init` activates the profiles it detects

## Context

`jig init` detected a project's stacks and printed `suggested profiles: …`, but installed only
what `--profiles` named, or `generic`. A person who does not read that line — the vibe coder Jig
is for — got `generic`, whose verify checks nothing and passes. With profiles for most popular
stacks (adr-20260918-profiles-narrow-per-check-with-project-tools) the suggestion was the last
step between a project and its checks.

Detection searched the whole tree, dependency directories included, and on a re-run it saw
jig's own `.ai/scripts/*.sh`: every installed project looked like a shell project.

## Decision

- **A first `jig init` without `--profiles`, in a project without `.ai/config.yaml`, writes
  `generic` and every detected profile into `profiles:`** (with the `requires` closure — `artisan`
  brings `laravel` and `php`) and prints `detected profiles: …`.
- **A choice already made is never widened.** With `--profiles`, or on a re-run against an
  existing config, detection only suggests, as before. `upgrade` never activates a profile.
- **Detection skips what is not the project's own code:** `.git`, `node_modules`, `vendor`,
  `.venv`, `venv`, `.dart_tool` and `.ai`.

## Alternatives

- **Keep suggesting.** Leaves the people least likely to act on a suggestion with checks that do
  nothing.
- **Ask which profiles to enable.** `init` is non-interactive by design; an agent or a script
  runs it as often as a person does.
- **Also activate on re-run or in `upgrade`.** Would override a configuration someone chose.

## Consequences

- A new project gets its stack's checks with no flag. A detected stack whose tools are missing
  skips with the reason, so activating it never fails a verify.
- A project that did not want a detected profile removes it from `profiles:` once; a re-run
  does not bring it back.
- Detection now matters more, so its globs stay root manifests; a monorepo whose stacks live in
  subdirectories is detected only where a root file matches.

> **Amendment (2026-09-25).** The sentence this decision rests on — "got `generic`, whose
> verify checks nothing and passes" — is half retired. `generic` still checks nothing, but it
> no longer *passes*: a check that cannot come out false where jig runs at all is a tally
> entry, not evidence, and that entry was painting whole runs green
> (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass). It now reports a skip,
> and a project it is alone in is told plainly that nothing checks it — at `jig verify` and
> again at `jig task ship`, without being refused, because there is nothing there to install.
> This strengthens the decision rather than changing it: activating what is detected is still
> how a project gets checks, and the state it rescues people from is now audible instead of
> silently green.
