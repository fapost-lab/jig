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
reviewed_at: 2026-09-22
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
| Compare directories with `pwd -P` output, not raw strings. | `git rev-parse --show-toplevel` resolves symlinks and macOS maps `/var` to `/private/var`. In Git Bash `git.exe` prints `C:/…` and `pwd -P` prints `/c/…` for the same directory; `jig_require_repo` sets `JIG_PROJECT` through `cd -P … && pwd -P` for that reason, and a test compares against `pwd -P`, never against `--show-toplevel`. |
| Hand a path to native git as an argument, or relative to a directory the command `cd`s into — never an absolute path through stdin. | MSYS converts `/c/…` to `C:\…` in arguments only. `upgrade` piped absolute paths into `git hash-object --stdin-paths`, and on every Windows machine git could not find one of them. `jig_hash_list <base> <file>` takes paths relative to `<base>` (ADR-0037). |
| Never hand git a `<ref>:<path>` argument whose ref may contain `/`; resolve the ref to a commit SHA first. `jig_git_show_path <ref> <path>` does both for `git show`. | MSYS rewrites an argument holding both `/` and `:` as a path list before git sees it. The status page read an open epic's roadmap with `git show "epic/idea-x:.ai/specs/..."`; on Windows it read nothing, and the page lost the epic's phases. `<sha>:<path>` is left alone. |
| Make a directory link with `jig_link_dir`, never `ln -s`. | Git Bash copies on `ln -s` unless Developer Mode is on, and exits 0: a worktree's workspace silently became a second copy with its own `state`. `jig_link_dir` makes a symlink or an NTFS junction and fails when it can make neither; code that needs a real symlink (link mode) checks `jig_link_detect` first (ADR-0037). |
| Run a framework script as `bash <file>`, never through its executable bit. | Git on Windows checks files out as `100644` in a repository whose index says so, and a colleague's clone inherits it. The session hook tested `-x .ai/scripts/jig` and silently never ran housekeeping for them. |
| Write files atomically: write `file.tmp.$$`, then `mv`. | A crash mid-write must not leave a half-written manifest or config. |
| Untrusted names (task ids, profile and adapter names, from flags *and* from config) are validated at the one function that builds the path, before any filesystem access or `sed`. | Validating at call sites leaves gaps: `jig verify --profile ../../x` executed a foreign script, `jig init --profiles ..` copied a whole tree into `.ai/`, and `--profiles ../x` reached a `sed` substitution and broke it. |
| A walk over existing directories (`workspace/tasks/*/`) checks each name with the same validator and skips the ones that fail; it never hands them to the path builder, which dies. | Names on disk predate the current grammar. `jig task new --help` filed a workspace named `--help`; once ids could no longer start with `-`, `task list` and `task current` would have died on that directory, while `measure` and `housekeeping`, which already skipped, kept working. |
| Any `rm -rf` or `mv` on a computed path is preceded by a validation that the path is inside `.ai/` and shaped as expected. | RULES.md invariant; ADR-0006. |
| No bash 4 features: no associative arrays, `${var,,}`, `mapfile`, `readlink -f`, `cp --parents`, `sort -V`, `grep -P`. | macOS ships bash 3.2 (ADR-0002). |
| Never write `A && B || C` as a statement, even when `C` exits. Use `if`. | shellcheck 0.10.0 reports SC2015 on it and 0.11.0 does not, so the same code passes `jig verify` on one machine and fails on another. `scripts/lib/upgrade.sh` had one such line: with shellcheck 0.10.0 (Debian stable, Ubuntu LTS) the shell profile failed on jig's own source, and every test whose fixture runs that profile failed with it — 6 failures on Linux that were one line. The linter version is not pinned anywhere, so this is invisible on the maintainer's machine; CI's Ubuntu runner (shellcheck 0.9.0) catches it. It came back with the live status page (`scripts/lib/status.sh`, `[ -n "$stage" ] && [ "$stage" != "-" ] \|\| stage=...`) and turned the epic's CI red. |
| Never build a path by substituting a variable into a `sed` replacement. Concatenate in the shell. | `&` in a sed replacement means "the text that matched", and `\\` escapes. `init` prefixed the project root onto relative paths with `sed "s\|^\|$JIG_PROJECT/\|"`; under a project named `R&D/` every path silently lost that segment, git died with a raw error after the framework was already copied in, and `.ai/manifest` was left with a header and no body — an install `upgrade` and `status` no longer recognised. The project root comes from `git rev-parse --show-toplevel`, so it is always an arbitrary user path. |
| Build a file the next command consumes in full before handing it over, when the consumer replaces something. | The same manifest write streamed entries through a pipe into `manifest_write_entries`, so a failure mid-batch still replaced the manifest with a truncated one. Assembling the entries in a file first costs ~100 ms on an install and leaves the previous manifest untouched on any failure. |
| A test that asserts a tool is **absent** controls `PATH` by enumerating the tools it needs, never by listing directories it believes are tool-free. | `run_no_tools` set `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and called that "no toolchain". That is only true where development tools live elsewhere: on macOS php and go come from `/opt/homebrew/bin` and fall away, on a Linux runner they sit in `/usr/bin` and stayed fully visible. Three "skips without toolchain" tests passed locally and failed in CI, and the bug was **unreproducible on macOS by construction** — `/usr/bin` is read-only under SIP, so no local test could plant a tool there to catch it. |
| Build such a `PATH` by resolving each tool through `env -i PATH="$PATH" /bin/sh -c "command -v X"`, keep only absolute answers, and put a wrapper script that `exec`s each one in the directory, never a symlink. | A bare `command -v` answers from the developer's shell. On a machine where `grep` is aliased to ugrep it returns the string `grep`, which became a self-referential symlink and a `grep: command not found` in the middle of a run. A helper written to remove environment dependence must not inherit any. In Git Bash `ln -s` copies, and a copied `bash.exe` or `env.exe`, moved away from `msys-2.0.dll`, cannot start: every no-tools test died with exit 127. And `env -i` without `PATH` resets it to a default that leaves out `/mingw64/bin`, where git lives there, so the directory had no git at all. |
| A list of files is hashed by one `git hash-object --stdin-paths` (`jig_hash_list`), the manifest is read once (`manifest_entries`), and a scratch tree is copied one `cp` per directory (`jig_copy_tree`). Never loop over `jig_hash`, `manifest_hash_of` or a per-file `cp`. | Every one of those is a process start per file, and they were almost all of what `jig status` cost: 1.5 s on drift and 3.5 s asking `upgrade` whether anything was pending, on a 72-file install. On 65 files the hashing loop took 0.879 s, one call 0.013 s, with identical hashes. Batching took `jig status` on a copy install from ~4 s to ~0.6 s. `jig verify` asks the same pending question (ADR-0017), so the `status` and `verify` tests alone were 47% of the suite's wall-clock time. |
| Measure shell benchmarks under `bash`, not the interactive shell. | zsh does not word-split an unquoted parameter, so `for f in $files` runs **once** over the whole multi-line string. That turned "35 files hashed in 45 ms" into a measurement of one call, and led to the wrong conclusion that `git hash-object` was cheap; under `bash` it is ~13.6 ms per call and was the largest single cost of `jig init`. |
| A space-separated list of globs is split with pathname expansion off (`set -f`, or `jp_path_matches`), never `for g in $list` alone. | Unquoted, `config/*` expands against the files on disk before `case` sees it: a deleted `config/app.php` no longer matched once only `config/database.php` existed, and a nested `config/a/b.php` never did. Five profiles lost their "send this change to the full set" rule that way (adr-20260918-profiles-narrow-per-check-with-project-tools). |
| After splitting a newline list with `IFS=<newline>`, restore `IFS=$' \t\n'`, and a function that splits on spaces sets its own `local IFS`. | Every profile "restored" IFS to a newline again after passing a file list, so each later split on spaces — a list of triggers, a map decision with two filters — produced one token. The tests passed because no test took a file-list branch before a list split. |
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
- **Tests run in parallel**, `JIG_TEST_JOBS` at a time, by default one per CPU;
  `JIG_TEST_JOBS=1` runs them one after another. Each test prints its `ok`/`FAIL` line when
  it finishes; the logs of the failures, the five slowest tests and the wall time follow,
  and the last line is still `N passed, M failed`. On this repository the suite went from
  724 s to ~90 s (10 jobs): 476 s of that from batching jig's own hashing (the row above),
  the rest from the workers.
- **A test never assumes it runs alone.** Anything shared between tests — the fixture
  cache, the no-tools `PATH` directory — is built complete and then published atomically
  (`mv` of the finished directory, or built by the runner before any test starts), never filled in place and
  taken as ready by a marker inside it. `_no_tools_bin` did the latter: `git` is third on
  its list, so a test running alongside the builder saw `git` before `sed` and failed its
  `jig verify` — 2 to 4 failures in every `verify::` run at 32 workers until it was fixed.
- **A test that needs something a filesystem may not give checks for it, and skips with the
  reason** — `skip_unless_symlinks`, `skip_unless_readonly_dirs`, `skip_unless_unreadable_files`,
  `skip_unless_control_char_names` in `tests/lib/assert.sh`, never a test of the OS name. `skip`
  exits 77 and the runner counts it apart from passes and failures (ADR-0013: a skip is not a
  pass). A test *about* symlinks skips without them; a test that only uses a linked directory as
  a fixture plants it with `plant_dir_link`, which makes a junction where it must. On
  `windows-latest` Git Bash `chmod 555` leaves a directory writable, `chmod 000` leaves a file
  readable, and a tab cannot be part of a file name — each once failed a test for reasons that
  had nothing to do with the code under test.
- **A wait on something a test cannot `wait` for has a wall-clock deadline sized for a
  loaded machine** (`hk_wait_for`). A passing test leaves at the first poll that succeeds,
  so a generous deadline costs only a real failure. The session-hook test gave the
  detached housekeeping run 50 × `sleep 0.1`; at 10 workers each sleep takes longer
  than it says, the test took 13 s, and it failed once in a full `jig verify` while
  passing every time alone. Count `$SECONDS`, not iterations.
- **Output is captured through a file, never a pipe** (`run`, `run_split`,
  `run_no_tools`). bash 3.2 does not restart a write that SIGCHLD interrupts: a jig
  command whose child exits while its output pipe is full loses the line it was writing
  (`printf: write error: Interrupted system call`). Reproduced in isolation — 1 lost line
  in 3000 into a slow pipe, 0 into a file — and seen once in a real run, where a test
  missed the line it asserted on. The same limit applies to any caller piping jig's output
  into a slow reader; it is bash's, and only capturing to a file avoids it.
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
- **A test whose verdict depends on when a ref moved sets git's clock itself.** Ancestry
  compares reflog times, a tie goes to the base (ADR-0032), and a test commits and merges
  within one second, so without a clock its own work reads as the base's: six existing
  housekeeping tests went red at once. `hk_tick` moves `GIT_COMMITTER_DATE` ten seconds per
  step. Its counter lives in the repository's git directory, not in `HOME`: the runner's
  `HOME` is often the test repository itself, and a file there made every clean-checkout
  assertion see an untracked change.
- Tests of commands that only need a default Jig installation may use `fixture_jig_repo`.
  It installs once per runner invocation (`fixture_cache_prepare`, which a parallel run
  calls before starting any test) and copies the complete fixture into
  each isolated test directory, including independent Git state. The cache is temporary
  and never preserves test results. Tests of init, upgrade, or non-default installation
  options must perform their own real setup.
