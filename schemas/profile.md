# Profile manifest

`profiles/<name>/profile.yaml`, one per profile, beside that profile's `verify.sh`;
installed into a project as `.ai/profiles/<name>/profile.yaml` (ADR-0003).
Reference: `domains/verify`, ADR-0013, ADR-0041. Read with `profile_get` and
`_profiles_list_lines` from `scripts/lib/profiles.sh`. Every key is optional; what an
absent key means is decided by its reader, not by this file.

| Key | Shape | Meaning |
|---|---|---|
| `name` | scalar | the profile's own name. Read by no script: the directory under `profiles/` is the identity everything resolves (`profiles_dir`), so a `name` that disagrees with its directory changes no behaviour. It is here for the person reading the file |
| `description` | scalar | one line on what the profile checks and which tools it reaches for. Read by no script either |
| `detect` | `always`, or an inline list of globs | how `profiles_detect` recognises a project of this stack — see **Detection** |
| `requires` | inline list of profile names | profiles this one builds on. Detection closes over it, and `profiles_check_requires` warns when an active profile's requirement is not active — see **Requires** |
| `scope` | inline list of capabilities | which parts of the verify scope protocol this profile's `verify.sh` understands: `changed` (ADR-0013), `map` (ADR-0041), `explain`, `environment` — see **Scope** |
| `covers` | inline list of `<profile>:<check>` | checks of other profiles this profile's own checks replace: `laravel` declares `covers: [php:tests]`, because `php artisan test` runs the suite php's PHPUnit or Pest would — see **Covers** |
| `checks` | inline list of check names | the checks of this profile another can take over by name. Today one name exists, `tests`, and `php`, `laravel`, `node` and `python` declare it — see **Covers** |

## Grammar

The same flat YAML subset as `.ai/config.yaml` (`schemas/config.md`), but a plain file
rather than a frontmatter block, so it is read by `profile_get` rather than by `cfg` or
`fm_get`.

- One `key: value` per line, no nesting. The key is anchored at column 0: an indented
  key is invisible to the reader.
- Two shapes only: a scalar, and an inline list `key: [a, b]`. There are no block lists.
- `#` starts a comment, to the end of the line. The grammar has no escape, so a value
  cannot contain `#`.
- A list item may be quoted with `"`; the quotes are stripped. Globs are written bare —
  the reader never lets the shell expand them.
- When a key is set on more than one line, the first one is read and the rest are ignored.

## Detection

`detect` answers one question: is this project written in that stack? `profiles_detect`
reads it from every profile directory and returns the names that matched, which a first
`jig init` turns into the project's `profiles` list (adr-20260918-init-activates-detected-profiles).

- A list of globs matches when **at least one** glob matches a path in the project.
  Unlike a verify-map glob, which is matched against a path string, a `detect` glob is
  matched against the real tree: the path has to exist.
- `**` and `*` both match across `/`, and both collapse to a single `*` in the
  `find -path` pattern the glob is compiled to. `scripts/**/*.sh` and `scripts/*.sh` are
  therefore the same glob, and both match a `.sh` file at any depth under `scripts/`.
  Depth cannot be expressed here — write the manifest file you are actually looking for
  (`go.mod`, `composer.json`) rather than a glob you expect to be shallow.
- Detection does not look inside `.git`, `.ai`, `node_modules`, `vendor`, `.venv`,
  `venv` or `.dart_tool`. A `.sh` file vendored into someone else's dependency is not
  what the project is written in.
- `always` means detected in every project. `generic` carries it, and is in the result
  before any manifest is read at all; in any other profile it would mean the same thing.

## Requires

A profile pulled in by detection pulls in everything it requires, even when that
profile's own globs matched nothing — `laravel` matches `artisan` and brings in `php`,
whose `composer.json` may be absent. The closure runs until a full pass adds nothing new.

Activation is separate and is not closed over: `.ai/config.yaml` lists exactly the
profiles the project activates. `profiles_check_requires` warns on stderr when an active
profile requires one that is not active, and is advisory — it never fails a command. The
two read different trees: detection reads the profiles shipped with the framework, the
warning reads the copies installed under `.ai/profiles/`, so a manifest the project
edited can make them disagree.

## Scope

`jig verify` computes the changed-file list once and hands it to profiles through
environment variables. A profile receives them only if `scope` declares the capability:

| Value | What the profile's `verify.sh` promises to honour |
|---|---|
| `changed` | `JIG_VERIFY_SCOPE=changed` and `JIG_VERIFY_FILES`, a file of changed paths (ADR-0013) |
| `map` | additionally `JIG_VERIFY_MAPPED`, the project's verify map applied to those paths (`schemas/verify-map.md`, ADR-0041). It means nothing without `changed`, which is checked first |
| | A `map` profile also receives `JIG_VERIFY_MAPPED_ALL` (the same decisions for every tracked file that is not a test or a document, for a profile that narrows by caller), `JIG_VERIFY_BASE` (the ref the changed list was taken against, empty for `HEAD`) and `JIG_VERIFY_FULL_RUN` (`local` or `ci`) |
| `explain` | `JIG_VERIFY_EXPLAIN=1` asks for a plan instead of checks. The profile prints one `PLAN <profile>: <check>: full\|filtered\|skip\|conditional (<reason>)` line per check, runs no project tool and exits 0. `conditional` names what remains unknown and whether the full set is possible |
| `environment` | `JIG_RUN_EXEC`, the command prefix that reaches the environment the project runs in (`docker compose exec -T -w /app app`), set only when `jig verify` decided the checks run there. The profile promises that every project command goes through `jp_run`, `jp_version`, `jp_exec` or `jp_have` — never a bare `command -v`, a host's absolute path or a shell function — so the prefix reaches all of them (adr-20261001-checks-run-where-the-project-runs) |

Support is declared, never inferred. (`JIG_VERIFY_COVERED` is declared per check, under
`checks`, rather than in `scope` — see **Covers**.) A profile that does not declare a capability is run
with those variables explicitly unset — not merely left as the caller's environment had
them — and the result line says the scope was ignored, so `pass` never quietly means
something different per profile.

For `--explain`, a profile without the `explain` capability is not run at all. Jig prints
`unknown` and exits 2 if any selected profile is unknown. A declared profile that exits
nonzero or prints no valid plan line makes the preview fail with exit 1. A real `jig verify`
always unsets `JIG_VERIFY_EXPLAIN`, even if its caller exported it. The preview never takes
the clone's verification run record and never treats a plan as a verification result.

Under an environment (`run.exec`, `schemas/config.md`), a profile without the `environment`
capability is not run at all — running it would put its checks on the host. Its result is
`skip (not adapted to run in <where>; …)`, counted like a skip for a missing tool, and in
`--explain` it is `unknown`. Without an environment, `JIG_RUN_EXEC` is unset for every
profile, so `jp_run` and `jp_version` behave exactly as they did before the capability
existed.

## Covers

Two profiles can run the same work: a Laravel project activates `laravel` and the `php` it
requires, and `php artisan test` runs the PHPUnit or Pest suite `php` would run itself. The
profile **above** says so; the profile below only names its check (adr-20261107-a-profile-covers-a-check-of-another):

```yaml
# profiles/laravel/profile.yaml
covers: [php:tests]
# profiles/php/profile.yaml
checks: [tests]
```

A check is named by its role, never by its tool: `tests` is phpunit or pest, whichever the
project has. `jig verify` decides once, before any profile starts, which covers hold in this
run. `<upper> covers <lower>:<check>` holds when:

- both profiles start in this run — the gates the run itself applies: a `verify.sh`, `explain`
  in a preview, `environment` under one. A profile that never starts covers nothing;
- the upper profile applies to the project: its `detect` is `always`, absent (a project's own
  profile, activated by name), or matches. `laravel` without an `artisan` covers nothing, and
  php keeps its tests;
- the lower profile lists the check under `checks`. Otherwise `jig verify` warns —
  `profile 'upper' covers 'lower:tests', but 'lower' names no check 'tests' (checks:), so it still runs` —
  and the check runs: support is declared, never inferred, as for `scope`;
- in a narrowed run where the lower profile has its own map, the profile that ends up running the
  check declares `map` too, so the map can follow the tests (below). If it does not, it warns and the lower profile
  keeps its tests.

When several profiles cover the same check, the first in run order takes it. Covers chain: with
`myapp` declaring `covers: [laravel:tests]` over `laravel`'s `covers: [php:tests]`, php's tests
are myapp's, and php's skip names myapp. A chain that comes back to where it started runs
the check nowhere, so its covers are dropped with a warning and every profile in it keeps its
check.

The lower profile receives `JIG_VERIFY_COVERED`, `<check>=<profile>` words, and asks it with
`jp_covered <check> <label>`, which prints the check's skip — `php: phpunit: skip (scope: covered by
laravel, php:tests)`, or the `PLAN` line in a preview — and returns 0. Every other profile runs
with the variable unset. The reason starts `scope:`: the tools are fine and the work is another
profile's, so a run where everything else narrowed away is not read as a gap in coverage. A
`verify.sh` that never calls `jp_covered` — a profile a project edited before the key existed —
runs its check anyway: twice, the safe direction.

**The map follows the tests.** A map's decisions narrow its profile's tests
(`schemas/verify-map.md`), so when `<lower>:tests` is covered, `.ai/verify/<lower>.map` is read
for the profile that runs the tests after that profile's own map — along a chain, the nearest
profile's map first — first match wins across all of them, and the result line names every map. A
map is handed on only from a profile that declares `map`: one its profile never read is no decision. By covering `<lower>:tests` the
upper profile accepts the lower profile's filter vocabulary — `php` and `laravel` both take a test
file path. The lower profile still receives its own map for the checks it keeps.

`covers` and `checks` are the first step of profile layers (`.ai/specs/profile-layers/`): one
name, one way to drop a check. A check table, overrides of a check's arguments and `extends` are
later work, and other stock profiles name their checks as that work reaches them.

## The reader is tolerant, and that is the design

`profile_get` looks up one key at a time, on demand. There is no list of known keys, no
schema check, and no command that validates a manifest. A key nobody asks for is never
asked for, so **an unknown key is ignored in silence**.

That is what makes a new key an additive change. Profiles are copied into the project
(ADR-0003) and `jig upgrade` keeps a project-modified manifest as `keep-modified`, so a
newer `jig` is guaranteed to meet manifests written before the key it now asks about
existed. Those manifests keep working untouched: the absent key reads as empty, each
reader already decides what empty means, and no profile needs migrating when this schema
grows. `scope` is the same principle made explicit one level up — ADR-0013 declares
support rather than inferring it precisely so that absence stays a valid answer.

The cost is paid in the other direction. A misspelled key is ignored just as silently:
`detects:` or `scopes:` raises no error and no warning, and the profile behaves as one
that declared nothing — never detected, or run unscoped. Nothing will tell you, and the
table above is the whole list of keys that mean anything.

The file's *presence* is checked, even though its contents are not: it is part of the
install manifest, so a profile directory missing its `profile.yaml` is reported as drift
by `jig status` and makes `jig verify` refuse the stale install (ADR-0017).

## `verifies`

Optional, and the profile's claim about the code rather than a setting. The one value is
`nothing`:

```yaml
verifies: nothing
```

It says this profile asserts nothing about the project — whatever it runs is a guard, which
may fail a run and may not pass one. `generic` carries it and nothing else does. A project in
which only such profiles are active is told that nothing verifies it, by `jig verify` and
again by `jig task ship`, and is **not** refused over it: there is nothing to install and
nothing to wait for. Where a profile that does claim something has all its checks skip — its
tools are missing — `jig verify` refuses instead, because something could have been checked
and was not (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).

**Absence means the profile verifies something**, which is the cautious default: a profile
written before this field existed keeps refusing rather than quietly becoming unverifiable.

**It is declared, never inferred, and in particular is not `detect: always` under another
name.** `detect` answers when a profile *applies*; `verifies` answers what it *asserts*. They
coincide in `generic` alone, and by accident: a secret scanner or a licence-header check is
exactly the profile that should apply everywhere **and** claim something about the code.
Reading the claim off `detect` would put such a profile in the wrong bucket, and the day its
tool went missing it would report that nothing checks the project and let the change ship
unverified.

**It cannot be computed from a run, and that is why it is declared.** A profile with no checks
and a profile whose checks could not run both produce the same thing: skips and exit 2. The
reason differs, but a check's reason is prose, and `cmd_verify` decides nothing from a
profile's prose (`domains/verify/RULES.md`). `jig task ship` settles it: it must say that
nothing verifies this project **without running anything at all**, so the answer has to be
data a file carries, not an outcome a run produces.
