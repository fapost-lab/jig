#!/usr/bin/env bash
# Verification for the shell profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no shellcheck and no
# tests/run.sh — nothing applicable was found). Prints one line per check:
# "shell: <check>: pass|fail|skip (<reason>)".
#
# Scope (ADR-0013): when JIG_VERIFY_SCOPE=changed, JIG_VERIFY_FILES names a
# file listing the repo-relative paths that changed. shellcheck then lints
# only those; tests are narrowed through the mapping in _shell_test_filters.
# A changed path the mapping does not recognise means the profile cannot
# narrow safely, so it runs the full set and says so — narrowing to the
# wrong subset is how a green verify stops meaning anything.
set -eu
set -o pipefail

status=0
ran_any=0

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
_shell_all_scripts() {
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

# _shell_test_filters — map every changed path to a tests/run.sh filter, one
# per line. Prints the single token ALL when some path cannot be mapped,
# which the caller treats as "run everything". Prints nothing when every
# path is irrelevant to tests (documentation, knowledge).
_shell_test_filters() {
  local f base
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      # Documentation and knowledge carry no shell behaviour.
      *.md|docs/*|.ai/knowledge/*|.ai/workspace/*) continue ;;
      # The harness itself: any change to it can affect every test.
      tests/run.sh|tests/lib/*) printf 'ALL\n'; return 0 ;;
      # A test file tests its own command.
      tests/*.t.sh)
        base=${f#tests/}
        printf '%s::\n' "${base%.t.sh}"
        ;;
      # A library maps to the test file named after it, when there is one.
      scripts/lib/*.sh)
        base=${f#scripts/lib/}
        base=${base%.sh}
        if [ -f "tests/$base.t.sh" ]; then
          printf '%s::\n' "$base"
        else
          printf 'ALL\n'
          return 0
        fi
        ;;
      # The session hook is not a command library, so it has no test file of
      # its own; its tests live with the command it triggers.
      scripts/jig-session-hook) printf 'housekeeping::\n' ;;
      adapters/*) printf 'adapters::\n' ;;
      profiles/*) printf 'profiles::\n'; printf 'verify::\n' ;;
      *) printf 'ALL\n'; return 0 ;;
    esac
  done < "$JIG_VERIFY_FILES"
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

  if [ "$scoped" = 1 ]; then
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
    if [ "$scoped" = 1 ]; then
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
      if [ "$scoped" = 1 ]; then
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

    if printf '%s\n' "$filters" | grep -qx 'ALL'; then
      ran_any=1
      if tests/run.sh; then
        echo "shell: tests/run.sh: pass (scope: not narrowable, ran full set)"
      else
        echo "shell: tests/run.sh: fail (scope: not narrowable, ran full set)"
        status=1
      fi
    elif [ -z "$filters" ]; then
      echo "shell: tests/run.sh: skip (scope: no changed file maps to a test)"
    else
      ran_any=1
      t_failed=0
      t_count=0
      while IFS= read -r filter; do
        [ -n "$filter" ] || continue
        t_count=$((t_count + 1))
        tests/run.sh "$filter" || t_failed=1
      done <<EOF
$filters
EOF
      if [ "$t_failed" = 1 ]; then
        echo "shell: tests/run.sh: fail (scope: $t_count filters)"
        status=1
      else
        echo "shell: tests/run.sh: pass (scope: $t_count filters)"
      fi
    fi
  else
    ran_any=1
    if tests/run.sh; then
      echo "shell: tests/run.sh: pass"
    else
      echo "shell: tests/run.sh: fail"
      status=1
    fi
  fi
else
  echo "shell: tests/run.sh: skip (not found or not executable)"
fi

if [ "$ran_any" -eq 0 ]; then
  exit 2
fi
exit "$status"
