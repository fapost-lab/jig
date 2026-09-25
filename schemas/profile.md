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
| `scope` | inline list of capabilities | which parts of the verify scope protocol this profile's `verify.sh` understands: `changed` (ADR-0013), `map` (ADR-0041), `explain` — see **Scope** |

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
| `explain` | `JIG_VERIFY_EXPLAIN=1` asks for a plan instead of checks. The profile prints one `PLAN <profile>: <check>: full\|filtered\|skip\|conditional (<reason>)` line per check, runs no project tool and exits 0. `conditional` names what remains unknown and whether the full set is possible |

Support is declared, never inferred. A profile that does not declare a capability is run
with those variables explicitly unset — not merely left as the caller's environment had
them — and the result line says the scope was ignored, so `pass` never quietly means
something different per profile.

For `--explain`, a profile without the `explain` capability is not run at all. Jig prints
`unknown` and exits 2 if any selected profile is unknown. A declared profile that exits
nonzero or prints no valid plan line makes the preview fail with exit 1. A real `jig verify`
always unsets `JIG_VERIFY_EXPLAIN`, even if its caller exported it. The preview never takes
the clone's verification run record and never treats a plan as a verification result.

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
