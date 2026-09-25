# Project verify map

`.ai/verify/<profile>.map`, one per profile. Project-owned and committed: `jig init` and
`jig upgrade` never create or touch it, unlike the profile itself. Reference: ADR-0041.
Parsed by `_verify_map_check`/`_verify_map_apply` in `scripts/lib/verify.sh`; declared
support is `scope: [changed, map]` in the profile's `profile.yaml`.

A profile is copied into every project that uses it, so its built-in rules for turning
changed files into checks know only what is true for any project of that stack. Which path
affects which check in *this* project belongs in the project, not in a file `upgrade`
replaces. No map, no change: the profile narrows by its built-in rules alone.

## Grammar

```
# comment
<glob>  <decision>
```

- One rule per line: a glob, whitespace, a decision. `#` starts a comment, to end of line
  or the whole line; blank lines are skipped; a trailing CR (a file saved on Windows) is
  ignored.
- The glob follows `detect` (`schemas/profile.md`): `**` and `*` both match across `/`.
  It is matched against the path string, never the filesystem — a path need not exist.
- **First match wins.** Rules are tried top to bottom per path; later rules for an
  already-matched path are never reached.
- A decision is `-` (this path affects no check), `ALL` (run the full set), or one or more
  profile-specific filters separated by spaces (e.g. a `tests/run.sh` filter for the shell
  profile). `-` and `ALL` must stand alone — combining either with anything else, or with
  each other, is an error.
- A line with a glob and no decision is an error.

## Validation

`jig verify` validates the whole map before using any of it (`_verify_map_check`), not
only the lines a run happens to match — a line that is wrong today narrows the wrong way
the day a path starts matching it. A broken line fails that profile without running it:

```
RESULT shell: fail (map .ai/verify/shell.map:12: no decision for scripts/*.sh)
```

## What a profile receives

Whenever a run is narrowed (`--changed`, `--base`, or `verify.full_run: ci`) and the
profile declares `scope: [changed, map]`, `jig verify` applies the map to the changed-file
list and hands the profile `JIG_VERIFY_MAPPED`: a path to a file of `<path><TAB><decision>`
lines, one per changed path, in the same order as `JIG_VERIFY_FILES`. `?` stands for a path
no line matched — the profile's own built-in rules answer for it. Without a map, or for a
profile that does not declare `map`, the variable is unset. The result line names the map:

```
RESULT shell: pass (scope: changed, 7 files, map .ai/verify/shell.map)
```

## What a filter means, per profile

A filter narrows the profile's tests; linters are narrowed by the changed files
themselves. A filter that names nothing (a missing file, an empty package, an unknown
crate) runs that profile's tests in full and says so.

| Profile | Filter |
|---|---|
| `shell` | a `tests/run.sh` name filter (`<file>::`, `<file>::<test>`) |
| `php`, `laravel`, `python`, `ruby`, `dart`, `node` | a test file path |
| `go` | a package path, `./internal/foo` |
| `rust` | a crate name |
| `dotnet` | a test project file path |
| `jvm` | a Gradle subproject or Maven module directory |
| `swift` | none: only `-` and `ALL` mean anything |
