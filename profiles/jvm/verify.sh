#!/usr/bin/env bash
# Verification for the jvm profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "jvm: <check>: pass|fail|skip (<note>)".
#
# Two build systems, each optional and independent (adr-20260918-profiles-narrow-per-check-with-project-tools): Gradle, when
# a Gradle build file sits at the repository root -- the project's own
# `./gradlew` first, `gradle` from PATH otherwise; check `check`. Maven,
# when a root `pom.xml` exists -- `./mvnw` first, `mvn` from PATH otherwise;
# check `test`. A project that has both runs both; a project that has
# neither (the profile activated without either manifest) skips both,
# naming what it looked for. `gradlew`/`mvnw` are run through `sh`, never
# through their own executable bit: a checkout that lost +x (common coming
# from Windows) must not turn into "command not found".
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools), per check: a changed file maps to the
# nearest ancestor directory *below the repository root* that holds a
# build.gradle(.kts) (Gradle) or a pom.xml (Maven) -- a root-level build
# file is deliberately not a candidate here, it is one of the "always ALL"
# triggers below instead. Gradle turns that directory into the task
# `:<dir, / replaced by :>:check`; Maven turns it into `-pl <dir> -am
# test`. A path with no such ancestor (outside every subproject) runs the
# full set, with a reason. A root build/settings file, `gradle/**`,
# `gradlew*` or `gradle.properties` sends Gradle's check to its full set; a
# root `pom.xml`, `.mvn/**` or `mvnw*` sends Maven's. A project map's
# filters, like the built-in ones, are subproject or module *paths*: a
# project map cannot know Gradle's task syntax, and a path is what
# `schemas/verify-map.md` documents for this profile.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin jvm

HAS_GRADLE=0
if [ -f build.gradle ] || [ -f build.gradle.kts ] \
   || [ -f settings.gradle ] || [ -f settings.gradle.kts ]; then
  HAS_GRADLE=1
fi
HAS_MAVEN=0
[ -f pom.xml ] && HAS_MAVEN=1

if [ "$HAS_GRADLE" = 0 ] && [ "$HAS_MAVEN" = 0 ]; then
  if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
    jp_plan check skip "no root Gradle build"
    jp_plan test skip "no root pom.xml"
    exit 0
  fi
  jp_skip "check" "no build.gradle(.kts) or settings.gradle(.kts) at the repository root"
  jp_skip "test" "no pom.xml at the repository root"
  jp_end
fi

# --- module/subproject resolution, shared shape for both build systems -----

# _jvm_nearest_module <marker> <path> — the nearest ancestor directory of
# <path>, strictly below the repository root, that directly contains a file
# matching <marker> (a case pattern: "build.gradle|build.gradle.kts" or
# "pom.xml"). Nothing when no such ancestor exists (the path is outside
# every subproject, or there is only the root project). Not inlined into a
# `$( )`: bash 3.2 misparses a `case` there.
_jvm_nearest_module() {
  local marker="$1" f="$2" dir
  dir=$(dirname "$f")
  while [ "$dir" != "." ]; do
    if _jvm_dir_has "$marker" "$dir"; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# _jvm_dir_has <marker> <dir> — <dir> directly contains a file matching
# <marker>. A filesystem check, not a scan of tracked files: build.gradle(.kts)
# and pom.xml are fixed, conventional names, so there is nothing to search
# for beyond the path itself.
_jvm_dir_has() {
  case "$1" in
    'build.gradle|build.gradle.kts')
      [ -f "$2/build.gradle" ] || [ -f "$2/build.gradle.kts" ] ;;
    pom.xml)
      [ -f "$2/pom.xml" ] ;;
    *)
      return 1 ;;
  esac
}

# _jvm_join <sep> <arg>... — <arg>s joined by <sep>, e.g. for Maven's
# comma-separated `-pl`.
_jvm_join() {
  local sep="$1" out="" a
  shift
  for a in "$@"; do
    if [ -z "$out" ]; then out="$a"; else out="$out$sep$a"; fi
  done
  printf '%s\n' "$out"
}

_jvm_gradle_always_all() {
  case "$1" in
    build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts| \
    gradle.properties|gradlew*|gradle/*) return 0 ;;
  esac
  return 1
}

_jvm_gradle_builtin() {
  local f="$1" dir
  if jp_is_doc "$f"; then return 0; fi
  if _jvm_gradle_always_all "$f"; then printf 'ALL\n'; return 0; fi
  if dir=$(_jvm_nearest_module 'build.gradle|build.gradle.kts' "$f"); then
    printf '%s\n' "$dir"
  else
    printf 'ALL\n'
  fi
  return 0
}

_jvm_maven_always_all() {
  case "$1" in
    pom.xml|mvnw*|.mvn/*) return 0 ;;
  esac
  return 1
}

_jvm_maven_builtin() {
  local f="$1" dir
  if jp_is_doc "$f"; then return 0; fi
  if _jvm_maven_always_all "$f"; then printf 'ALL\n'; return 0; fi
  if dir=$(_jvm_nearest_module pom.xml "$f"); then
    printf '%s\n' "$dir"
  else
    printf 'ALL\n'
  fi
  return 0
}

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  if [ "$HAS_GRADLE" = 0 ]; then
    jp_plan check skip "no root Gradle build"
  elif [ ! -f ./gradlew ] && ! command -v gradle >/dev/null 2>&1; then
    jp_plan check skip "gradlew not found and gradle not found on PATH"
  else
    filters=$(jp_decide _jvm_gradle_builtin)
    if [ -n "$filters" ] && [ "$filters" != ALL ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ ! -e "$f" ]; then filters=ALL; break; fi
      done <<EOF
$filters
EOF
    fi
    jp_plan_selection check "$filters" "Gradle subprojects"
  fi
  if [ "$HAS_MAVEN" = 0 ]; then
    jp_plan test skip "no root pom.xml"
  elif [ ! -f ./mvnw ] && ! command -v mvn >/dev/null 2>&1; then
    jp_plan test skip "mvnw not found and mvn not found on PATH"
  else
    filters=$(jp_decide _jvm_maven_builtin)
    if [ -n "$filters" ] && [ "$filters" != ALL ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ ! -e "$f" ]; then filters=ALL; break; fi
      done <<EOF
$filters
EOF
    fi
    jp_plan_selection test "$filters" "Maven modules"
  fi
  exit 0
fi

# --- Gradle ------------------------------------------------------------------

if [ "$HAS_GRADLE" = 1 ]; then
  GRADLE_VIA_SH=""
  GRADLE_BIN=""
  if [ -f ./gradlew ]; then
    GRADLE_VIA_SH=1
    GRADLE_BIN="./gradlew"
  elif command -v gradle >/dev/null 2>&1; then
    GRADLE_BIN=$(command -v gradle)
  fi

  if [ -z "$GRADLE_BIN" ]; then
    jp_skip "check" "gradlew not found and gradle not found on PATH"
  else
    # _jvm_gradle_exec <arg...> — gradlew (via sh, +x-independent) or gradle
    # from PATH, whichever was resolved above.
    _jvm_gradle_exec() {
      if [ -n "$GRADLE_VIA_SH" ]; then
        sh "$GRADLE_BIN" "$@"
      else
        "$GRADLE_BIN" "$@"
      fi
    }

    # Not jp_version: the real Gradle CLI's `--version` banner starts with
    # a blank line, so jp_version's plain first-line capture always reports
    # "unknown" for it -- a gap in the shared library, worth a version this
    # profile can actually name (RULES.md: the verdict names the tool's
    # version so "green here, red there" has a visible cause). Same
    # guarantee as jp_version: guarded, so a tool that cannot answer this
    # way never fails the check it only annotates.
    gv=$(_jvm_gradle_exec --version 2>/dev/null | sed -n 's/^Gradle //p' | sed -n '1p') || gv=""
    [ -n "$gv" ] || gv="unknown"

    # _jvm_gradle_always_all <path> — a root build/settings file, the
    # wrapper's own files, or gradle.properties: none of these belong to one
    # subproject.
    # _jvm_gradle_builtin <path> — the subproject directory a changed path
    # belongs to (D4), or ALL for an always-ALL file or a path outside every
    # subproject.
    # _jvm_gradle_run <note> [<task>...] — `check`, or the given tasks.
    _jvm_gradle_run() {
      local note="$1"
      shift
      if [ $# -eq 0 ]; then
        jp_run "check" "$note" _jvm_gradle_exec check
      else
        jp_run "check" "$note" _jvm_gradle_exec "$@"
      fi
    }

    if ! jp_scoped; then
      _jvm_gradle_run "$gv"
    else
      filters=$(jp_decide _jvm_gradle_builtin)
      if [ -z "$filters" ]; then
        jp_skip "check" "scope: no changed file maps to a subproject"
      elif [ "$filters" = ALL ]; then
        _jvm_gradle_run "$gv, scope: not narrowable, ran full set"
      else
        IFS='
'
        set -f
        # shellcheck disable=SC2086
        set -- $filters
        set +f
        IFS=$' \t\n'
        if missing=$(jp_first_missing "$@"); then
          _jvm_gradle_run "$gv, scope: filter '$missing' selects no tests, ran full set"
        else
          n=$#
          # One subproject directory per line -> one Gradle task per line,
          # `:` for `/`, ":check" appended; a second IFS-newline `set --`
          # turns them into _jvm_gradle_run's argument list.
          tasks=$(for d in "$@"; do
            printf ':%s:check\n' "$(printf '%s' "$d" | tr '/' ':')"
          done)
          IFS='
'
          set -f
          # shellcheck disable=SC2086
          set -- $tasks
          set +f
          IFS=$' \t\n'
          _jvm_gradle_run "$gv, scope: $n subprojects" "$@"
        fi
      fi
    fi
  fi
fi

# --- Maven -------------------------------------------------------------------

if [ "$HAS_MAVEN" = 1 ]; then
  MVN_VIA_SH=""
  MVN_BIN=""
  if [ -f ./mvnw ]; then
    MVN_VIA_SH=1
    MVN_BIN="./mvnw"
  elif command -v mvn >/dev/null 2>&1; then
    MVN_BIN=$(command -v mvn)
  fi

  if [ -z "$MVN_BIN" ]; then
    jp_skip "test" "mvnw not found and mvn not found on PATH"
  else
    # _jvm_maven_exec <arg...> — mvnw (via sh, +x-independent) or mvn from
    # PATH, whichever was resolved above.
    _jvm_maven_exec() {
      if [ -n "$MVN_VIA_SH" ]; then
        sh "$MVN_BIN" "$@"
      else
        "$MVN_BIN" "$@"
      fi
    }

    mv_=$(jp_version _jvm_maven_exec --version)

    # _jvm_maven_always_all <path> — the root pom.xml, `.mvn/**` or the
    # wrapper's own files: none of these belong to one module.
    # _jvm_maven_builtin <path> — the module directory a changed path
    # belongs to (D4), or ALL for an always-ALL file or a path outside every
    # module.
    # _jvm_maven_run <note> [-pl <modules> -am] — `test`, narrowed or not.
    _jvm_maven_run() {
      local note="$1"
      shift
      if [ $# -eq 0 ]; then
        jp_run "test" "$note" _jvm_maven_exec test
      else
        jp_run "test" "$note" _jvm_maven_exec "$@" test
      fi
    }

    if ! jp_scoped; then
      _jvm_maven_run "$mv_"
    else
      filters=$(jp_decide _jvm_maven_builtin)
      if [ -z "$filters" ]; then
        jp_skip "test" "scope: no changed file maps to a module"
      elif [ "$filters" = ALL ]; then
        _jvm_maven_run "$mv_, scope: not narrowable, ran full set"
      else
        IFS='
'
        set -f
        # shellcheck disable=SC2086
        set -- $filters
        set +f
        IFS=$' \t\n'
        if missing=$(jp_first_missing "$@"); then
          _jvm_maven_run "$mv_, scope: filter '$missing' selects no tests, ran full set"
        else
          n=$#
          joined=$(_jvm_join , "$@")
          _jvm_maven_run "$mv_, scope: $n modules" -pl "$joined" -am
        fi
      fi
    fi
  fi
fi

jp_end
