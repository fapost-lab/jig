#!/usr/bin/env bash
# Verification for the shell profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no shellcheck and no
# tests/run.sh — nothing applicable was found), 3 = a check started and did
# not finish (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
# Prints one line per check:
# "shell: <check>: pass|fail|skip|incomplete (<reason>)".
#
# Scope (ADR-0013): when JIG_VERIFY_SCOPE=changed, JIG_VERIFY_FILES names a
# file listing the repo-relative paths that changed. shellcheck then lints
# only those; tests are narrowed through the mapping in _shell_test_filters.
# A changed path the mapping does not recognise means the profile cannot
# narrow safely, so it runs the full set and says so — narrowing to the
# wrong subset is how a green verify stops meaning anything.
#
# Map (ADR-0041): when the project has .ai/verify/shell.map, JIG_VERIFY_MAPPED
# carries the decision `jig verify` read from it for each changed path; the
# built-in rules answer only for paths the map does not name.
set -eu
set -o pipefail

status=0
ran_any=0
incomplete=0

# _shell_tests_verdict <rc> <note> — read one tests/run.sh exit code.
#
# 3 is the runner saying a test was killed rather than failing; 128+N is the
# runner itself killed by signal N, which is how `Killed: 9` reaches a caller.
# Neither is a verdict on the code, and reading one as a failure is what cost
# four investigations in one night. Sets `incomplete` or `status`; never both.
_shell_tests_verdict() {
  local rc="$1" note="$2"
  if [ "$rc" -eq 0 ]; then
    echo "shell: tests/run.sh: pass${note:+ ($note)}"
    return 0
  fi
  if [ "$rc" -eq 3 ] || [ "$rc" -ge 128 ]; then
    incomplete=1
    if [ "$rc" -ge 128 ]; then
      echo "shell: tests/run.sh: incomplete (killed by signal $((rc - 128))${note:+, $note})"
    else
      echo "shell: tests/run.sh: incomplete (a test did not finish${note:+, $note})"
    fi
    return 0
  fi
  echo "shell: tests/run.sh: fail${note:+ ($note)}"
  status=1
  return 0
}

scoped=0
if [ "${JIG_VERIFY_SCOPE:-}" = "changed" ] && [ -n "${JIG_VERIFY_FILES:-}" ] \
   && [ -f "${JIG_VERIFY_FILES:-}" ]; then
  scoped=1
fi

# _shell_is_script <path> — true for a .sh file or a shebang'd script.
_shell_is_script() {
  case "$1" in
    *.sh) return 0 ;;
  esac
  [ -f "$1" ] || return 1
  case "$(head -n 1 "$1" 2>/dev/null || true)" in
    '#!'*bash*) return 0 ;;
    '#!'*/sh | '#!'*'env sh') return 0 ;;
  esac
  return 1
}

# _shell_all_scripts — every script in the tree, one per line.
#
# Inside a git work tree, the listing comes from git, not the filesystem: an
# agent runtime creates nested worktrees inside the repository (e.g.
# .claude/worktrees/<name>/, a full copy of the repo — measured 39 extra
# scripts from one such worktree), and those are not the project's code,
# nor is anything gitignored or generated. git reports a nested
# worktree — and a submodule the same way — as a single directory entry
# without descending into it, which _shell_is_script rejects because it is
# not a file, so nothing under it is linted. Outside a git work tree, fall
# back to the previous filesystem walk.
_shell_all_scripts() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Guarded with `|| true`: under pipefail a git failure here must not
    # abort the profile, only leave the list short.
    # `-c` answers from the index, so a tracked script deleted but not yet
    # staged is still listed; `[ -f ]` keeps shellcheck from failing on it.
    git ls-files -co --exclude-standard \
    | while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -f "$f" ] || continue
        if _shell_is_script "$f"; then printf '%s\n' "$f"; fi
      done || true
    return 0
  fi
  find . \
    \( -path './.git' -o -path './node_modules' -o -path './vendor' \
       -o -path './.ai/runtime' -o -path './.ai/workspace' \) -prune -o \
    -type f -print \
  | while IFS= read -r f; do
      [ -n "$f" ] || continue
      if _shell_is_script "$f"; then printf '%s\n' "$f"; fi
    done
  return 0
}

# _shell_changed_scripts — the changed paths that are scripts and still exist
# (a deleted file has nothing left to lint).
_shell_changed_scripts() {
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    if _shell_is_script "$f"; then printf '%s\n' "$f"; fi
  done < "$JIG_VERIFY_FILES"
  return 0
}

# _shell_builtin_filters <path> — the profile's own answer for one path, true
# for any project: a tests/run.sh filter per line, ALL for "run everything",
# nothing when the path cannot affect a test. Anything specific to one
# project's layout belongs in its map (.ai/verify/shell.map, ADR-0041), never
# here: this file is copied into every project that uses the profile.
_shell_builtin_filters() {
  local f="$1" base
  case "$f" in
    # Documentation, knowledge and plans carry no shell behaviour.
    *.md|docs/*|.ai/knowledge/*|.ai/workspace/*|.ai/specs/*) return 0 ;;
    # Linter configuration changes lint verdicts, not tests (see shellcheck).
    .shellcheckrc|*/.shellcheckrc) return 0 ;;
    # The harness itself: any change to it can affect every test.
    tests/run.sh|tests/lib/*) printf 'ALL\n' ;;
    # A test file tests its own command.
    tests/*.t.sh)
      base=${f#tests/}
      printf '%s::\n' "${base%.t.sh}"
      ;;
    # A script maps to the test file named after it, when there is one.
    *.sh)
      base=${f##*/}
      base=${base%.sh}
      if [ -f "tests/$base.t.sh" ]; then
        printf '%s::\n' "$base"
      else
        printf 'ALL\n'
      fi
      ;;
    *) printf 'ALL\n' ;;
  esac
}

# _shell_test_filters — map every changed path to a tests/run.sh filter, one
# per line. Prints ALL when some path cannot be mapped, which the caller
# treats as "run everything". Prints nothing when every path is irrelevant to
# tests. With a project map, `jig verify` has already decided each path
# (JIG_VERIFY_MAPPED: `<path><TAB><decision>`); `?` means the map had no line
# for it and the built-in rules answer.
_shell_test_filters() {
  local f decision tok
  if [ -n "${JIG_VERIFY_MAPPED:-}" ] && [ -f "${JIG_VERIFY_MAPPED:-}" ]; then
    while IFS="$(printf '\t')" read -r f decision; do
      [ -n "$f" ] || continue
      case "$decision" in
        '?') _shell_builtin_filters "$f" ;;
        -) ;;
        *)
          # The decision comes from a hand-edited file: a token must never
          # expand against the files in the project root.
          set -f
          for tok in $decision; do
            printf '%s\n' "$tok"
          done
          set +f
          ;;
      esac
    done < "$JIG_VERIFY_MAPPED"
    return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _shell_builtin_filters "$f"
  done < "$JIG_VERIFY_FILES"
  return 0
}

# _shell_test_names — the tests tests/run.sh would discover, as
# `<file>::<function>`, one per line: the names the runner matches a filter
# against, so a filter that selects none of them is caught before the runner
# reports `0 passed` as a pass. Read from the text, not by sourcing the files
# as the runner does — a profile must not execute a project's test files to
# decide what to run. `test_x()` and `function test_x` are both recognised; a
# definition the patterns miss can only make a filter look empty, which runs
# the full set: the mismatch costs time, never coverage.
_shell_test_names() {
  local t base
  for t in tests/*.t.sh; do
    [ -f "$t" ] || continue
    base=${t#tests/}
    base=${base%.t.sh}
    sed -n \
      -e 's/^[[:space:]]*\(function[[:space:]][[:space:]]*\)\{0,1\}\(test_[A-Za-z0-9_]*\)[[:space:]]*().*/\2/p' \
      -e 's/^[[:space:]]*function[[:space:]][[:space:]]*\(test_[A-Za-z0-9_]*\)[[:space:]]*\({.*\)\{0,1\}$/\1/p' \
      "$t" \
      | while IFS= read -r fn; do printf '%s::%s\n' "$base" "$fn"; done
  done
  return 0
}

# --- shellcheck --------------------------------------------------------------

if command -v shellcheck >/dev/null 2>&1; then
  # Every shellcheck verdict names the version that produced it. Rule sets
  # move between releases — SC2015 fires in 0.10.0 and not in 0.11.0 — so the
  # same tree honestly passes on one machine and fails on another. That is
  # not a bug to hide; what was missing is any way to see it from the report.
  # Measured: Debian stable (0.10.0) 440/446 against macOS (0.11.0) 446/446,
  # on one line of source, with nothing in the output pointing at the linter.
  #
  # Reported, never enforced: refusing an unexpected version would fail the
  # gate for shipping an ordinary distro rather than for anything about the
  # code, and shellcheck is an optional dependency (ADR-0002).
  # Guarded assignment: under `set -e` with `pipefail` a bare
  # `x=$(cmd | ...)` takes the pipeline's status, so a shellcheck that is
  # installed but cannot answer `--version` (a broken build, a shim, a
  # wrapper) would abort this profile here — printing nothing at all, for
  # either check, and taking the tests down with it. A version probe must
  # never be able to fail the thing it only annotates.
  sc_version=$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p' | head -n 1) \
    || sc_version=""
  [ -n "$sc_version" ] || sc_version="unknown"

  list=$(mktemp "${TMPDIR:-/tmp}/jig-shell-verify.XXXXXX")
  trap 'rm -f "$list"' EXIT INT TERM

  # A changed .shellcheckrc changes the verdict for every script, not only
  # the changed ones, so it widens the lint to the whole tree.
  sc_wide=0
  if [ "$scoped" = 1 ] && grep -qE '(^|/)\.shellcheckrc$' "$JIG_VERIFY_FILES"; then
    sc_wide=1
  fi

  if [ "$scoped" = 1 ] && [ "$sc_wide" = 0 ]; then
    _shell_changed_scripts > "$list"
  else
    _shell_all_scripts > "$list"
  fi

  sc_checked=0
  sc_failed=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sc_checked=$((sc_checked + 1))
    # -e SC1091: "not following sourced file" is expected noise for any
    # framework that sources libraries through a computed path variable
    # (e.g. `. "$LIB_DIR/foo.sh"`) rather than a literal, shellcheck-visible
    # path — jig's own .ai/scripts/lib/*.sh included (see .shellcheckrc at
    # the framework's own source root, which disables it the same way).
    shellcheck -s bash -e SC1091 "$f" || sc_failed=1
  done < "$list"
  rm -f "$list"
  trap - EXIT INT TERM

  if [ "$sc_checked" -eq 0 ]; then
    if [ "$scoped" = 1 ] && [ "$sc_wide" = 0 ]; then
      echo "shell: shellcheck: skip (scope: no changed shell scripts)"
    else
      echo "shell: shellcheck: skip (no shell scripts found)"
    fi
  else
    ran_any=1
    if [ "$sc_failed" -eq 1 ]; then
      echo "shell: shellcheck: fail (shellcheck $sc_version)"
      status=1
    else
      if [ "$sc_wide" = 1 ]; then
        echo "shell: shellcheck: pass (shellcheck $sc_version, scope: .shellcheckrc changed, whole tree)"
      elif [ "$scoped" = 1 ]; then
        echo "shell: shellcheck: pass (shellcheck $sc_version, scope: $sc_checked files)"
      else
        echo "shell: shellcheck: pass (shellcheck $sc_version)"
      fi
    fi
  fi
else
  echo "shell: shellcheck: skip (shellcheck not found)"
fi

# --- tests/run.sh ------------------------------------------------------------

if [ -x tests/run.sh ]; then
  if [ "$scoped" = 1 ]; then
    filters=$(_shell_test_filters | LC_ALL=C sort -u)
    reason="not narrowable"

    # A filter that selects no test is not a narrowing: tests/run.sh reports
    # `0 passed` and exits 0, and a pass nothing produced is the defect this
    # check exists to prevent (ADR-0041). Such a filter runs the full set.
    # Whole-line and substring tests are `case`s, never `printf | grep -q`:
    # grep quits on the first hit while printf still writes, and pipefail
    # turns the SIGPIPE into "no match" (conventions/shell.md).
    case $'\n'"$filters"$'\n' in *$'\n'ALL$'\n'*) has_all=1 ;; *) has_all=0 ;; esac
    if [ -n "$filters" ] && [ "$has_all" = 0 ]; then
      names=$(_shell_test_names)
      while IFS= read -r filter; do
        [ -n "$filter" ] || continue
        # A substring, as tests/run.sh selects.
        case "$names" in *"$filter"*) ;; *)
          reason="filter '$filter' selects no tests"
          filters="ALL"
          break
          ;;
        esac
      done <<EOF
$filters
EOF
    fi

    if [ "$filters" = ALL ] || [ "$has_all" = 1 ]; then
      ran_any=1
      t_rc=0
      tests/run.sh || t_rc=$?
      _shell_tests_verdict "$t_rc" "scope: $reason, ran full set"
    elif [ -z "$filters" ]; then
      echo "shell: tests/run.sh: skip (scope: no changed file maps to a test)"
    else
      ran_any=1
      t_worst=0
      t_count=0
      while IFS= read -r filter; do
        [ -n "$filter" ] || continue
        t_count=$((t_count + 1))
        t_rc=0
        tests/run.sh "$filter" || t_rc=$?
        # The worst answer of the filters decides, and "did not finish" is
        # worse than "failed": one filter killed makes the whole narrowed run
        # unfinished, whatever the others said.
        if [ "$t_rc" -ge 128 ] || [ "$t_rc" -eq 3 ]; then
          t_worst="$t_rc"
        elif [ "$t_rc" -ne 0 ] && [ "$t_worst" -eq 0 ]; then
          t_worst=1
        fi
      done <<EOF
$filters
EOF
      _shell_tests_verdict "$t_worst" "scope: $t_count filters"
    fi
  else
    ran_any=1
    t_rc=0
    tests/run.sh || t_rc=$?
    _shell_tests_verdict "$t_rc" ""
  fi
else
  echo "shell: tests/run.sh: skip (not found or not executable)"
fi

if [ "$incomplete" -eq 1 ]; then
  exit 3
fi
if [ "$ran_any" -eq 0 ]; then
  exit 2
fi
exit "$status"
