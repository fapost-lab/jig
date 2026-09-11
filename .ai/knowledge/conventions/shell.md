---
id: convention-shell
type: convention
status: active
domains: [scripts, tests]
paths:
  - "scripts/**"
  - "adapters/**"
  - "profiles/**"
  - "tests/**"
reviewed_at: 2026-09-11
summary: Shell practices every Jig script follows, each one paid for by a real bug.
---
# Shell conventions

Practices for every script in the framework. They exist because each one caught a real
bug during Phase 1; the rationale column says which.

## Practice

| Rule | Rationale |
|---|---|
| Every executable starts with `set -eu` and `set -o pipefail`; libraries are sourced and start with `# shellcheck shell=bash`. | `pipefail` is the only way a failing `find` in a pipeline is noticed under `set -e`. |
| Validate before `shift`: `[ $# -ge 2 ] \|\| jig_die "cmd: --flag requires a value"`. | A bare `shift 2` with one argument left kills the process under `set -e` with no message. |
| Never pipe into `while read`; use `while read ...; done < <(cmd)`. | A piped loop runs in a subshell and every counter or accumulator set inside it is lost. |
| Variables referenced from an `EXIT` trap are script-global, never `local`. | The trap runs after the function returned and `set -u` reports an unbound variable. |
| Compare directories with `pwd -P` output, not raw strings. | `git rev-parse --show-toplevel` resolves symlinks and macOS maps `/var` to `/private/var`. |
| Write files atomically: write `file.tmp.$$`, then `mv`. | A crash mid-write must not leave a half-written manifest or config. |
| Untrusted names (task ids, profile and adapter names, from flags *and* from config) are validated at the one function that builds the path, before any filesystem access or `sed`. | Validating at call sites leaves gaps: `jig verify --profile ../../x` executed a foreign script, `jig init --profiles ..` copied a whole tree into `.ai/`, and `--profiles ../x` reached a `sed` substitution and broke it. |
| Any `rm -rf` or `mv` on a computed path is preceded by a validation that the path is inside `.ai/` and shaped as expected. | RULES.md invariant; ADR-0006. |
| No bash 4 features: no associative arrays, `${var,,}`, `mapfile`, `readlink -f`, `cp --parents`, `sort -V`, `grep -P`. | macOS ships bash 3.2 (ADR-0002). |
| Never write `A && B || C` as a statement, even when `C` exits. Use `if`. | shellcheck 0.10.0 reports SC2015 on it and 0.11.0 does not, so the same code passes `jig verify` on one machine and fails on another. `scripts/lib/upgrade.sh` had one such line: with shellcheck 0.10.0 (Debian stable, Ubuntu LTS) the shell profile failed on jig's own source, and every test whose fixture runs that profile failed with it — 6 failures on Linux that were one line. The linter version is not pinned anywhere and there is no CI, so this is invisible on the maintainer's machine. |
| Never build a path by substituting a variable into a `sed` replacement. Concatenate in the shell. | `&` in a sed replacement means "the text that matched", and `\\` escapes. `init` prefixed the project root onto relative paths with `sed "s\|^\|$JIG_PROJECT/\|"`; under a project named `R&D/` every path silently lost that segment, git died with a raw error after the framework was already copied in, and `.ai/manifest` was left with a header and no body — an install `upgrade` and `status` no longer recognised. The project root comes from `git rev-parse --show-toplevel`, so it is always an arbitrary user path. |
| Build a file the next command consumes in full before handing it over, when the consumer replaces something. | The same manifest write streamed entries through a pipe into `manifest_write_entries`, so a failure mid-batch still replaced the manifest with a truncated one. Assembling the entries in a file first costs ~100 ms on an install and leaves the previous manifest untouched on any failure. |
| A test that asserts a tool is **absent** controls `PATH` by enumerating the tools it needs, never by listing directories it believes are tool-free. | `run_no_tools` set `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and called that "no toolchain". That is only true where development tools live elsewhere: on macOS php and go come from `/opt/homebrew/bin` and fall away, on a Linux runner they sit in `/usr/bin` and stayed fully visible. Three "skips without toolchain" tests passed locally and failed in CI, and the bug was **unreproducible on macOS by construction** — `/usr/bin` is read-only under SIP, so no local test could plant a tool there to catch it. |
| Build such a `PATH` by resolving each tool through `env -i /bin/sh -c "command -v X"`, and keep only absolute answers. | A bare `command -v` answers from the developer's shell. On a machine where `grep` is aliased to ugrep it returns the string `grep`, which became a self-referential symlink and a `grep: command not found` in the middle of a run. A helper written to remove environment dependence must not inherit any. |
| Measure shell benchmarks under `bash`, not the interactive shell. | zsh does not word-split an unquoted parameter, so `for f in $files` runs **once** over the whole multi-line string. That turned "35 files hashed in 45 ms" into a measurement of one call, and led to the wrong conclusion that `git hash-object` was cheap; under `bash` it is ~13.6 ms per call and was the largest single cost of `jig init`. |
| Glob matching against the tree uses `find -path` with `**` collapsed to `*`. | BSD and GNU `find -path` both match `*` across `/`, so one substitution covers any-depth and single-segment globs without `globstar`. |
| A listing hides finished or superseded entries by default and counts them in a trailing line; `--all` shows everything. | Applies to `jig task list` and `jig context` alike. On a long-lived branch, done work outnumbers live work and crowds it out, and a listing nobody reads is worse than no listing. |
| Under `set -e`, neither a loop body nor a function may end in `cmd && cmd`: the loop, or the function, takes that status, so one false condition aborts the caller before its own `return 0`. Use `if cmd; then ...; fi`. | Cost a silent `exit 1` with no output twice: in `profiles/shell/verify.sh` (loop body), and in `context.sh`'s `_ctx_parse_selectors` (last statement of the function), where it killed `context resolve\|pending\|guard` for every task with no domains — the common case. Note a probe that calls the function as `f && ...` cannot reproduce it — a condition context suspends `errexit` inside the callee. |
| `profiles_detect` is called with an explicit profiles root, normally `profiles_installed_dir`. | With no argument it falls back to `profiles_source_dir`, which is empty whenever jig runs from `.ai/scripts` rather than a framework checkout — and it then reports `generic` and nothing else, with no error. Note also that it can only see stacks whose profile the project has installed, so it answers "which profiles are active", never "what is this codebase". |
| Two files in one directory may not differ only by case. | macOS is case-insensitive by default, so `glossary.md` and `GLOSSARY.md` are one file: creating the type template silently overwrote the global knowledge template. The domain-pack templates live in `templates/knowledge/domain/` for this reason (ADR-0014). |
| A command's primary output is plain `printf`, never `jig_log`. | `jig_log` obeys the global `JIG_QUIET`, so `JIG_QUIET=1` erased exactly the line `context guard` prints to say a check did not run — the property ADR-0015 depends on. See `_init_out` in `init.sh`. |
| Commands that produce human output use plain `printf`; `jig_info`/`jig_warn`/`jig_die` go to stderr. A command's `--quiet` flag is local to that command. | Tests capture stdout per test, so there is no need for a global quiet switch. |
| An awk two-file join on `NR == FNR` handles the empty-first-file case explicitly. | `NR == FNR` identifies the first file only while that file has lines. With an empty first file the condition is true for every line of the **second** file too, so the join silently keeps nothing. In `measure.sh` the first file is the live task workspaces and the second is the purge records: on a machine with no live tasks — the ordinary state after housekeeping — every historical task was discarded as if it were live, and the report said "no task workspaces and no purge records" while the log held plenty. |
| A `git` read whose result becomes a number pins the options that change it, rather than inheriting the user's config. | `git diff --numstat` obeys `diff.renames`, which is on by default and which some developers switch off globally. A renamed file is then either one file and one line, or two files and all their lines. `jig measure` would report a different change size for the same history depending on whose machine printed it — the same "do not inherit the environment" failure as `run_no_tools`, but in arithmetic rather than in `PATH`. `jig_git_change_rows` already pins `--no-renames`; new readers must too. |
| Shell division truncates towards zero, so floor explicitly wherever the numerator can be negative. | `$(( (tip - fork) / 86400 ))` on a branch tip older than its own fork point — a rebased base, a stale `base_commit` — gives `0` for any gap under a day instead of a negative number. The anomaly a reader needed to see is printed as "finished the same day", which is the most plausible reading and the wrong one. |

## Example

```sh
cmd_example() {
  local from=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) [ $# -ge 2 ] || jig_die "example: --from requires a value"; from="$2"; shift 2 ;;
      *) jig_die "example: unknown argument: $1" ;;
    esac
  done
  _EXAMPLE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/jig-example.XXXXXX")
  trap '[ -n "${_EXAMPLE_TMP:-}" ] && rm -rf "$_EXAMPLE_TMP"' EXIT INT TERM
  local count=0
  while IFS= read -r line; do count=$((count + 1)); done < <(find "$from" -type f)
  printf '%d files\n' "$count"
}
```

## Testing

- One `tests/<command>.t.sh` per command; functions `test_*`; each runs in a fresh temp
  directory with `HOME` isolated and a deterministic git identity (see `tests/run.sh`).
- Assert behaviour, not only exit codes: file presence, symlink targets, manifest lines,
  output substrings via `run cmd; assert_contains "$OUT" ...`.
- Every negative path that ends in `jig_die` has a test asserting the message.
- During edits, use `tests/run.sh <name-filter>` for the affected behavior; reuse valid
  results across stages and avoid simultaneous duplicate full runs. Wait on the run's own
  handle — `tests/run.sh >"${TMPDIR:-/tmp}/jig-run.log" 2>&1 & wait $!` — and read that
  exit code; a `pgrep -f` poll matches its own command line and never returns.
  **Write the log outside the repository.** This line used to say `>run.log`, and every
  agent that followed it left a file in the working tree: one of them reached the index and
  was a `git commit` away from being shipped. A convention that manufactures untracked
  junk teaches the next reader to make the same mess.
- Tests of commands that only need a default Jig installation may use `fixture_jig_repo`.
  It installs once per sequential runner invocation and copies the complete fixture into
  each isolated test directory, including independent Git state. The cache is temporary
  and never preserves test results. Tests of init, upgrade, or non-default installation
  options must perform their own real setup.
