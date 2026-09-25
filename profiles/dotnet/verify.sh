#!/usr/bin/env bash
# Verification for the dotnet profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "dotnet: <check>: pass|fail|skip (<note>)".
#
# The `dotnet` CLI is the only tool (adr-20260918-profiles-narrow-per-check-with-project-tools): the stack toolchain, from
# PATH. dotnet itself resolves which project or solution to build or test;
# this profile never guesses among several root *.sln files, it only ever
# passes an explicit project path when narrowing names one (D4). With
# several .sln files at the root and no narrowing, `dotnet test` runs plain
# and dotnet reports the ambiguity itself.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools), per check: `dotnet format` lints the
# changed .cs/.fs/.vb files via `--include`; `dotnet test` runs the test
# project a changed path resolves to — the nearest ancestor directory that
# holds a *.csproj/*.fsproj, when that project references a test SDK
# (Microsoft.NET.Test.Sdk, or a PackageReference for xunit/NUnit/MSTest) —
# and runs the full suite, with a reason, for every other change. A solution
# file, a Directory.Build.props/targets, a Directory.Packages.props, a
# global.json or a nuget.config always sends both checks to their full run.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin dotnet

# _dotnet_is_always_all <path> — a file whose change can alter the result of
# any check regardless of which project it lives in: a solution, an
# MSBuild-wide props/targets file, central package versions, the pinned SDK,
# or the NuGet configuration. A plain `case` (never a for-loop over a glob
# list): a list built from these globs would be pathname-expanded against
# the real .sln file every project has, silently losing the pattern.
_dotnet_is_always_all() {
  case "$1" in
    *.sln|*Directory.Build.props|*Directory.Build.targets| \
    *Directory.Packages.props|global.json|*nuget.config|*NuGet.Config)
      return 0 ;;
  esac
  return 1
}

# _dotnet_always_all_changed — exit 0 when a changed path (deleted ones
# included) is one of the always-ALL files above.
_dotnet_always_all_changed() {
  local f
  jp_scoped || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _dotnet_is_always_all "$f" && return 0
  done < <(jp_changed)
  return 1
}

DOTNET_WHERE="not found on PATH"

if ! command -v dotnet >/dev/null 2>&1; then
  if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
    jp_plan format skip "$DOTNET_WHERE"
    jp_plan test skip "$DOTNET_WHERE"
    exit 0
  fi
  jp_skip "format" "$DOTNET_WHERE"
  jp_skip "test" "$DOTNET_WHERE"
  jp_end
fi

dotnet=$(command -v dotnet)
if [ "${JIG_VERIFY_EXPLAIN:-}" != 1 ]; then
  v=$(jp_version "$dotnet" --version)
fi

# --- format --------------------------------------------------------------------

if [ "${JIG_VERIFY_EXPLAIN:-}" != 1 ]; then

if jp_scoped && ! _dotnet_always_all_changed; then
  files=$(jp_changed cs fs vb)
  if [ -z "$files" ]; then
    jp_skip "format" "scope: no changed .cs/.fs/.vb files"
  else
    n=$(printf '%s\n' "$files" | grep -c .)
    # One argument per line, so a path with a space stays one path.
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    set -- $files
    set +f
    IFS=$' \t\n'
    jp_run "format" "$v, scope: $n files" "$dotnet" format --verify-no-changes --include "$@"
  fi
elif jp_scoped; then
  jp_run "format" "$v, scope: sln/build config changed, whole project" "$dotnet" format --verify-no-changes
else
  jp_run "format" "$v" "$dotnet" format --verify-no-changes
fi
fi

# --- test ------------------------------------------------------------------

# Every *.csproj/*.fsproj in the project, computed once (a scoped run only):
# each ancestor lookup below would otherwise re-walk the whole file list.
DOTNET_PROJECT_FILES=""
if jp_scoped; then
  while IFS= read -r pf; do
    case "$pf" in
      *.csproj|*.fsproj)
        DOTNET_PROJECT_FILES="$DOTNET_PROJECT_FILES
$pf"
        ;;
    esac
  done < <(jp_files)
fi

# _dotnet_project_at <dir> — the project file directly inside <dir>, or
# nothing. Not inlined into a `$( )`: bash 3.2 misparses a `case` there.
_dotnet_project_at() {
  local dir="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$(dirname "$p")" = "$dir" ] && { printf '%s\n' "$p"; return 0; }
  done <<EOF
$DOTNET_PROJECT_FILES
EOF
  return 1
}

# _dotnet_nearest_project <path> — the project file of the nearest ancestor
# directory that has one, walking up from <path>'s own directory to the
# repository root. Nothing when no ancestor has a project file at all.
_dotnet_nearest_project() {
  local f="$1" dir hit
  dir=$(dirname "$f")
  while :; do
    if hit=$(_dotnet_project_at "$dir"); then
      printf '%s\n' "$hit"
      return 0
    fi
    [ "$dir" = "." ] && return 1
    dir=$(dirname "$dir")
  done
}

# _dotnet_is_test_project <project-file> — the project references a test
# SDK: Microsoft.NET.Test.Sdk, or a PackageReference for xunit, NUnit or
# MSTest (any of their common package names: xunit.core, NUnit3TestAdapter,
# MSTest.TestFramework, MSTest.TestAdapter, ...).
_dotnet_is_test_project() {
  local proj="$1"
  [ -f "$proj" ] || return 1
  grep -q 'Microsoft.NET.Test.Sdk' "$proj" && return 0
  grep -Eqi '<PackageReference[[:space:]]+Include="(xunit|nunit|mstest)' "$proj" && return 0
  return 1
}

# _dotnet_builtin <path> — the test project a changed path needs: that
# project's file when the nearest ancestor project references a test SDK;
# ALL for a project-wide file, a path with no ancestor project, or an
# ancestor project that is not itself a test project (D4: "any other
# change" runs the full suite, it is never widened to a sibling test
# project).
_dotnet_builtin() {
  local f="$1" proj
  if jp_is_doc "$f"; then return 0; fi
  if _dotnet_is_always_all "$f"; then
    printf 'ALL\n'
    return 0
  fi
  if proj=$(_dotnet_nearest_project "$f") && _dotnet_is_test_project "$proj"; then
    printf '%s\n' "$proj"
  else
    printf 'ALL\n'
  fi
  return 0
}

# _dotnet_test <note> [<project>...] — `dotnet test`, once with no argument
# for a full run, once per project when narrowed: `dotnet test` accepts at
# most one project or solution, so several selected test projects are run
# one invocation each rather than passed on a single command line.
_dotnet_test() {
  local note="$1" proj failed=0
  shift
  if [ $# -eq 0 ]; then
    if "$dotnet" test; then jp_pass "test" "$note"; else jp_fail "test" "$note"; fi
    return 0
  fi
  for proj in "$@"; do
    "$dotnet" test "$proj" || failed=1
  done
  if [ "$failed" = 0 ]; then jp_pass "test" "$note"; else jp_fail "test" "$note"; fi
  return 0
}

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  if jp_scoped && _dotnet_always_all_changed; then
    jp_plan format full "solution or build configuration changed"
  elif jp_scoped; then
    files=$(jp_changed cs fs vb)
    if [ -z "$files" ]; then
      jp_plan format skip "no changed .cs/.fs/.vb files"
    else
      jp_plan format filtered "changed files: $(printf '%s\n' "$files" | paste -sd, -)"
    fi
  else
    jp_plan format full "full scope"
  fi
  filters=$(jp_decide _dotnet_builtin)
  if [ -n "$filters" ] && [ "$filters" != ALL ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ ! -e "$f" ]; then filters=ALL; break; fi
    done <<EOF
$filters
EOF
  fi
  jp_plan_selection test "$filters" "test projects"
  exit 0
fi

if ! jp_scoped; then
  _dotnet_test "$v"
else
  filters=$(jp_decide _dotnet_builtin)
  if [ -z "$filters" ]; then
    jp_skip "test" "scope: no changed file maps to a test project"
  elif [ "$filters" = ALL ]; then
    _dotnet_test "$v, scope: not narrowable, ran full set"
  else
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    set -- $filters
    set +f
    IFS=$' \t\n'
    if missing=$(jp_first_missing "$@"); then
      _dotnet_test "$v, scope: filter '$missing' selects no tests, ran full set"
    else
      _dotnet_test "$v, scope: $# test projects" "$@"
    fi
  fi
fi

jp_end
