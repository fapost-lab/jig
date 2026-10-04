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

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

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

# _shell_fn_spans — read a script on stdin and print its top-level functions,
# one `<name> <first line> <last line>` per line. A function is a `name() {` at
# column 0 closed by a `}` at column 0, the layout every script in this
# repository uses; a script written another way yields fewer spans, which only
# makes the narrowing below give up (ALL), never narrow wrongly.
_shell_fn_spans() {
  awk '
    /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/ && !name {
      name = $0; sub(/[[:space:]]*\(\).*/, "", name); first = NR
      # A one-line function closes where it opens.
      if ($0 ~ /\{.*\}[[:space:]]*$/) { print name, first, NR; name = "" }
      next
    }
    /^}/ && name { print name, first, NR; name = "" }
  '
}

# _shell_changed_functions <file> — the functions of <file> the change edited,
# one per line; ALL when that cannot be told. Read from `git diff` against the
# base the run narrows to (JIG_VERIFY_BASE, HEAD without one): an added line
# belongs to the function that holds it in the new file, a removed one to the
# function that held it in the old. Anything but comments and blank lines
# changed outside a function (a global, a `source`), a function that is new,
# or one removed, is ALL: the callers of a name that did not exist before
# cannot be listed, and top-level code runs for every test that loads the file.
_shell_changed_functions() {
  local f="$1" base="${JIG_VERIFY_BASE:-HEAD}" newspans oldspans hits name
  git cat-file -e "$base:$f" 2>/dev/null || { printf 'ALL\n'; return 0; }
  newspans=$(_shell_fn_spans < "$f")
  oldspans=$(git show "$base:$f" 2>/dev/null | _shell_fn_spans) || oldspans=""
  hits=$(git diff -U0 --no-color --no-ext-diff "$base" -- "$f" 2>/dev/null \
    | NEWSPANS="$newspans" OLDSPANS="$oldspans" awk '
        function load(text, nm, lo, hi,   rows, n, i, p) {
          n = split(text, rows, "\n")
          for (i = 1; i <= n; i++) {
            split(rows[i], p, " "); nm[i] = p[1]; lo[i] = p[2]; hi[i] = p[3]
          }
          return n
        }
        function owner(line, nm, lo, hi, n,   i) {
          for (i = 1; i <= n; i++) if (line >= lo[i] && line <= hi[i]) return nm[i]
          return "ALL"
        }
        BEGIN {
          nn = load(ENVIRON["NEWSPANS"], nnm, nlo, nhi)
          no = load(ENVIRON["OLDSPANS"], onm, olo, ohi)
        }
        /^@@/ {
          inhunk = 1
          o = $2; sub(/^-/, "", o); split(o, q, ","); oldl = q[1] + 0
          h = $3; sub(/^\+/, "", h); split(h, q, ","); newl = q[1] + 0
          next
        }
        !inhunk { next }
        /^[-+]/ {
          body = substr($0, 2)
          blank = (body ~ /^[[:space:]]*(#.*)?$/)
          if ($0 ~ /^\+/) {
            if (!blank) print owner(newl, nnm, nlo, nhi, nn)
            newl++
          } else {
            if (!blank) print owner(oldl, onm, olo, ohi, no)
            oldl++
          }
        }
      ' | LC_ALL=C sort -u) || hits=ALL
  case $'\n'"$hits"$'\n' in *$'\n'ALL$'\n'*) printf 'ALL\n'; return 0 ;; esac
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # In both versions, or the change is a new or a removed function.
    case $'\n'"$newspans" in *$'\n'"$name "*) ;; *) printf 'ALL\n'; return 0 ;; esac
    case $'\n'"$oldspans" in *$'\n'"$name "*) ;; *) printf 'ALL\n'; return 0 ;; esac
    printf '%s\n' "$name"
  done <<EOF2
$hits
EOF2
  return 0
}

# _shell_function_filters <file> — the tests a script with no test file of its
# own reaches, found through the functions the change edited and their
# callers rather than the file name. The edited functions are looked up by
# word in every other script (not the tests); each function that mentions one
# joins the set, until no new function joins (twenty rounds at most, past
# which it is ALL). Each script that mentions a name is mapped as the project
# map or the built-in rules map it, so one that has no test of its own either
# is ALL — the library's own file is not asked for a test it does not have. Prints filters, ALL, or nothing when only comments changed.
_shell_function_filters() {
  local f="$1" names seen pat depth=0 out new found s scripts
  names=$(_shell_changed_functions "$f")
  case $'\n'"$names"$'\n' in *$'\n'ALL$'\n'*) printf 'ALL\n'; return 0 ;; esac
  [ -n "$names" ] || return 0
  scripts=$(_shell_all_scripts | sed '/^tests\//d')
  seen="$names"
  found=""
  while :; do
    pat=$(printf '%s\n' "$seen" | paste -sd'|' -)
    # One pass over every script: the files that mention a name, and the
    # functions that do. $scripts is split on newlines only, never globbed.
    set -f
    # shellcheck disable=SC2086
    out=$(IFS=$'\n'; awk -v pat="(^|[^A-Za-z0-9_])($pat)([^A-Za-z0-9_]|\$)" '
      FNR == 1 { fn = "" }
      /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/ && !fn {
        fn = $0; sub(/[[:space:]]*\(\).*/, "", fn)
        # A one-line function ends where it starts.
        one = ($0 ~ /\{.*\}[[:space:]]*$/)
      }
      $0 ~ pat { hit[FILENAME] = 1; if (fn) print "FN " fn }
      /^}/ || one { fn = ""; one = 0 }
      END { for (h in hit) print "FILE " h }
    ' $scripts)
    set +f
    found=$(printf '%s\n' "$out" | sed -n 's/^FILE //p' | LC_ALL=C sort -u)
    new=$(printf '%s\n%s\n' "$seen" "$(printf '%s\n' "$out" | sed -n 's/^FN //p')" \
      | sed '/^$/d' | LC_ALL=C sort -u)
    [ "$new" != "$(printf '%s\n' "$seen" | LC_ALL=C sort -u)" ] || break
    depth=$((depth + 1))
    if [ "$depth" -ge 20 ]; then printf 'ALL\n'; return 0; fi
    seen="$new"
  done
  # No script but its own mentions the edited functions: a call by a computed
  # name, or only by a test. Nobody can say what reaches it, so no test is
  # named — ALL, never a pass that ran nothing.
  if [ -z "$(printf '%s\n' "$found" | sed -e '/^$/d' -e "\\#^$f\$#d")" ]; then
    printf 'ALL\n'
    return 0
  fi
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ "$s" != "$f" ] || continue
    _shell_caller_filters "$s"
  done <<EOF2
$found
EOF2
  return 0
}

# _shell_caller_filters <path> — what a script that calls a changed function
# needs: the project map's answer when it names the path (JIG_VERIFY_MAPPED_ALL,
# parsed by `jig verify` for every tracked file), the built-in rules otherwise.
_shell_caller_filters() {
  local f="$1" decision="?" tok
  if [ -n "${JIG_VERIFY_MAPPED_ALL:-}" ] && [ -f "${JIG_VERIFY_MAPPED_ALL:-}" ]; then
    decision=$(awk -F '\t' -v p="$f" '$1 == p { print $2; exit }' "$JIG_VERIFY_MAPPED_ALL")
    [ -n "$decision" ] || decision="?"
  fi
  case "$decision" in
    '?') _shell_builtin_filters "$f" noscan ;;
    -) ;;
    *)
      set -f
      for tok in $decision; do
        printf '%s\n' "$tok"
      done
      set +f
      ;;
  esac
  return 0
}

# _shell_trim_ci — with `verify.full_run: ci` the project has said CI runs the
# full set, so an ALL that sits beside filters is left to CI and the filters run
# here. Alone, ALL stays: nothing would run otherwise, and a green that ran
# nothing is the defect the filter check below exists to prevent. Works on the
# global `filters`; sets ci_left=1 when ALL was dropped.
ci_left=0
_shell_trim_ci() {
  local rest
  ci_left=0
  [ "${JIG_VERIFY_FULL_RUN:-}" = ci ] || return 0
  case $'\n'"$filters"$'\n' in *$'\n'ALL$'\n'*) ;; *) return 0 ;; esac
  rest=$(printf '%s\n' "$filters" | sed -e '/^ALL$/d' -e '/^$/d')
  [ -n "$rest" ] || return 0
  filters="$rest"
  ci_left=1
  return 0
}

# _shell_builtin_filters <path> — the profile's own answer for one path, true
# for any project: a tests/run.sh filter per line, ALL for "run everything",
# nothing when the path cannot affect a test. Anything specific to one
# project's layout belongs in its map (.ai/verify/shell.map, ADR-0041), never
# here: this file is copied into every project that uses the profile.
_shell_builtin_filters() {
  local f="$1" scan="${2:-scan}" base
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
        if [ "$scan" = scan ]; then _shell_function_filters "$f"; else printf 'ALL\n'; fi
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

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  # shell is older than the shared profile library: it uses the library's
  # plan format and where-the-project-runs helpers, while the ordinary
  # verification path keeps its own verdicts.
  jp_begin shell

  if ! jp_have shellcheck; then
    jp_plan shellcheck skip "shellcheck not found"
  elif [ "$scoped" = 1 ] && grep -qE '(^|/)\.shellcheckrc$' "$JIG_VERIFY_FILES"; then
    scripts=$(_shell_all_scripts)
    if [ -z "$scripts" ]; then
      jp_plan shellcheck skip "no shell scripts found"
    else
      jp_plan shellcheck full ".shellcheckrc changed; whole script set"
    fi
  elif [ "$scoped" = 1 ]; then
    scripts=$(_shell_changed_scripts)
    if [ -z "$scripts" ]; then
      jp_plan shellcheck skip "no changed shell scripts"
    else
      jp_plan shellcheck filtered "changed scripts: $(printf '%s\n' "$scripts" | paste -sd, -)"
    fi
  else
    scripts=$(_shell_all_scripts)
    if [ -z "$scripts" ]; then
      jp_plan shellcheck skip "no shell scripts found"
    else
      jp_plan shellcheck full "full script set"
    fi
  fi

  if [ ! -x tests/run.sh ]; then
    jp_plan tests/run.sh skip "not found or not executable"
  elif [ "$scoped" = 0 ]; then
    jp_plan tests/run.sh full "full scope"
  else
    filters=$(_shell_test_filters | LC_ALL=C sort -u)
    _shell_trim_ci
    case $'\n'"$filters"$'\n' in *$'\n'ALL$'\n'*) filters=ALL ;; esac
    if [ -n "$filters" ] && [ "$filters" != ALL ]; then
      names=$(_shell_test_names)
      while IFS= read -r filter; do
        [ -n "$filter" ] || continue
        case "$names" in *"$filter"*) ;; *) filters=ALL; break ;; esac
      done <<EOF
$filters
EOF
    fi
    if [ "$ci_left" = 1 ]; then
      jp_plan_selection tests/run.sh "$filters" "test filters, full set left to CI"
    else
      jp_plan_selection tests/run.sh "$filters" "test filters"
    fi
  fi
  exit 0
fi

if jp_have shellcheck; then
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
  sc_version=$(jp_exec shellcheck --version 2>/dev/null | sed -n 's/^version: //p' | head -n 1) \
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
    jp_exec shellcheck -s bash -e SC1091 "$f" || sc_failed=1
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
    _shell_trim_ci
    # What the decision needed is read; the suite below must not inherit it,
    # as it does not inherit the scope (tests/run.sh unsets the others).
    unset JIG_VERIFY_BASE JIG_VERIFY_FULL_RUN JIG_VERIFY_MAPPED_ALL

    # A filter that selects no test is not a narrowing: tests/run.sh answers
    # "no test matched" and exits 1, and a red nobody earned is as wrong as a
    # green nothing produced (ADR-0041). Such a filter runs the full set.
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
      jp_exec tests/run.sh || t_rc=$?
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
        jp_exec tests/run.sh "$filter" || t_rc=$?
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
      if [ "$ci_left" = 1 ]; then
        _shell_tests_verdict "$t_worst" "scope: $t_count filters, full set left to CI"
      else
        _shell_tests_verdict "$t_worst" "scope: $t_count filters"
      fi
    fi
  else
    ran_any=1
    t_rc=0
    jp_exec tests/run.sh || t_rc=$?
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
