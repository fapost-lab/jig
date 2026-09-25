# Tests for the jvm profile's verify.sh (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools; domains/verify).
# shellcheck shell=bash
#
# Most tests run .ai/profiles/jvm/verify.sh directly with JIG_VERIFY_SCOPE /
# JIG_VERIFY_FILES / JIG_VERIFY_MAPPED set by hand, the same variables
# `jig verify` itself sets (scripts/lib/verify.sh) — this exercises the
# profile's own narrowing logic without depending on `jig verify`'s map
# parsing or its git-diff computation of "changed". enter_test_env already
# unsets these three (and CI) before every test, so nothing here leaks
# between tests.

_JVM_VERIFY=".ai/profiles/jvm/verify.sh"

# _jvm_install_gradle — a fixture repository with the jvm profile installed
# and a two-subproject Gradle build (so `detect` would also find it).
_jvm_install_gradle() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles jvm >/dev/null
  mkdir -p app lib
  cat > settings.gradle.kts <<'EOF'
rootProject.name = "demo"
include(":app", ":lib")
EOF
  : > build.gradle.kts
  : > app/build.gradle.kts
  : > app/Foo.kt
  : > lib/build.gradle.kts
  : > lib/Bar.kt
  git add -A
  git commit -q -m "gradle fixture"
}

# _jvm_install_maven — a fixture repository with the jvm profile installed
# and a two-module Maven reactor (so `detect` would also find it).
_jvm_install_maven() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles jvm >/dev/null
  mkdir -p module-a module-b
  : > pom.xml
  : > module-a/pom.xml
  : > module-a/A.java
  : > module-b/pom.xml
  : > module-b/B.java
  git add -A
  git commit -q -m "maven fixture"
}

# _gradle_stub <version> <rc> <log> — a `gradle` on PATH (stack toolchain,
# adr-20260918-profiles-narrow-per-check-with-project-tools). --version prints a banner shaped like the real CLI's own: a
# blank line, then a "Gradle <version>" line (this is exactly why the
# profile does not use jp_version for this tool — see verify.sh); every
# other invocation logs its arguments (one line, space-joined) to <log> and
# exits <rc>.
_gradle_stub() {
  local version="$1" rc="$2" log="$3"
  mkdir -p stub-bin
  cat > stub-bin/gradle <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '\nGradle %s\n' "$version"
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
exit $rc
STUB
  chmod +x stub-bin/gradle
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _gradlew_stub <version> <rc> <log> — a ./gradlew in the project root,
# deliberately left without +x: the profile must run it via `sh`.
_gradlew_stub() {
  local version="$1" rc="$2" log="$3"
  cat > gradlew <<STUB
#!/bin/sh
if [ "\$1" = "--version" ]; then
  printf '\nGradle %s\n' "$version"
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
exit $rc
STUB
}

# _mvn_stub <version> <rc> <log> — an `mvn` on PATH.
_mvn_stub() {
  local version="$1" rc="$2" log="$3"
  mkdir -p stub-bin
  cat > stub-bin/mvn <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$version"
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
exit $rc
STUB
  chmod +x stub-bin/mvn
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _mvnw_stub <version> <rc> <log> — an ./mvnw in the project root,
# deliberately left without +x: the profile must run it via `sh`.
_mvnw_stub() {
  local version="$1" rc="$2" log="$3"
  cat > mvnw <<STUB
#!/bin/sh
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$version"
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
exit $rc
STUB
}

# _files_list <path>... — a JIG_VERIFY_FILES file naming <path>, one per
# line; prints its name.
_files_list() {
  local f
  f=$(mktemp "$PWD/scope-files.XXXXXX")
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

# _mapped_file <line>... — a JIG_VERIFY_MAPPED file; each <line> is already
# "<path><TAB><decision>" (build with printf '%s\t%s' so the tab is real).
_mapped_file() {
  local f
  f=$(mktemp "$PWD/scope-mapped.XXXXXX")
  printf '%s\n' "$@" > "$f"
  printf '%s\n' "$f"
}

# _jvm_no_tools_bin — a fresh directory of wrapper scripts for exactly the
# tools a profile run needs to reach git/bash/coreutils, resolved through
# `env -i` so an aliased `grep` on the developer's shell cannot leak in
# (conventions/shell.md). Not cached across tests (unlike verify.t.sh's
# run_no_tools, which every test file that runs in isolation would need
# its own copy of): each test using this builds its own directory, and
# there is no shared state to race on.
_jvm_no_tools_bin() {
  local dir t p esc
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-jvm-no-tools.XXXXXX")
  for t in bash sh git sed awk grep find mktemp cat cp mv rm mkdir sort \
           tr head tail wc chmod ls date dirname basename cmp paste stat \
           readlink diff env; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*)
        esc=$(printf '%s' "$p" | sed "s/'/'\\\\''/g")
        {
          printf '#!/bin/sh\n'
          printf "exec '%s' \"\$@\"\n" "$esc"
        } > "$dir/$t"
        chmod +x "$dir/$t"
        ;;
    esac
  done
  printf '%s\n' "$dir"
}

# _jvm_no_tools <cmd...> — like run, but with PATH stripped to exactly the
# tools above, so `gradle`/`mvn` are deterministically unreachable
# regardless of what the machine running the tests happens to have
# installed.
_jvm_no_tools() {
  local bin
  bin=$(_jvm_no_tools_bin)
  PATH="$bin" run "$@"
}

# _jvm_scoped <files-file> [mapped-file] — run verify.sh narrowed to
# <files-file>, with <mapped-file> as JIG_VERIFY_MAPPED when given.
_jvm_scoped() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$1"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  if [ -n "${2:-}" ]; then
    JIG_VERIFY_MAPPED="$2"
    export JIG_VERIFY_MAPPED
  else
    unset JIG_VERIFY_MAPPED
  fi
  run bash "$_JVM_VERIFY"
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
}

# --- detect ------------------------------------------------------------------

_jvm_detect() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_HOME/profiles"
  '
}

test_profile_jvm_detected_for_build_gradle() {
  fixture_repo
  : > build.gradle
  _jvm_detect
  assert_eq 0 "$RC"
  assert_contains "$OUT" "jvm"
}

test_profile_jvm_detected_for_build_gradle_kts() {
  fixture_repo
  : > build.gradle.kts
  _jvm_detect
  assert_contains "$OUT" "jvm"
}

test_profile_jvm_detected_for_settings_gradle() {
  fixture_repo
  : > settings.gradle
  _jvm_detect
  assert_contains "$OUT" "jvm"
}

test_profile_jvm_detected_for_pom_xml() {
  fixture_repo
  : > pom.xml
  _jvm_detect
  assert_contains "$OUT" "jvm"
}

# --- skip without toolchain ---------------------------------------------------

test_profile_jvm_skips_every_check_without_toolchain() {
  _jvm_install_gradle
  _jvm_no_tools jig verify --profile jvm
  # Every check skipped, so the run checked nothing and says so, exit 3
  # (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: skip (gradlew not found and gradle not found on PATH)"

  _jvm_install_maven
  _jvm_no_tools jig verify --profile jvm
  # Every check skipped, so the run checked nothing and says so, exit 3
  # (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: skip (mvnw not found and mvn not found on PATH)"
}

test_profile_jvm_skips_both_checks_with_neither_build_file_at_root() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles jvm >/dev/null
  run jig verify --profile jvm
  # Every check skipped, so the run checked nothing and says so, exit 3
  # (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: skip (no build.gradle(.kts) or settings.gradle(.kts) at the repository root)"
  assert_contains "$OUT" "jvm: test: skip (no pom.xml at the repository root)"
}

# --- Gradle: pass / fail / version, wrapper preferred over PATH ---------------

test_profile_jvm_gradle_pass_and_fail_report_version() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  run jig verify --profile jvm
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: pass (8.5)"

  _gradle_stub 8.5 1 gradle.log
  run jig verify --profile jvm
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jvm: check: fail (8.5)"
}

test_profile_jvm_gradlew_preferred_over_path_gradle() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  _gradlew_stub 8.5-wrapper 0 gradlew.log
  run jig verify --profile jvm
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gradlew.log "check"
  assert_no_file gradle.log
}

# --- Maven: pass / fail / version, wrapper preferred over PATH ---------------

test_profile_jvm_maven_pass_and_fail_report_version() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  run jig verify --profile jvm
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: pass (Apache Maven 3.9.6)"

  _mvn_stub "Apache Maven 3.9.6" 1 mvn.log
  run jig verify --profile jvm
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jvm: test: fail (Apache Maven 3.9.6)"
}

test_profile_jvm_mvnw_preferred_over_path_mvn() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  _mvnw_stub "Apache Maven 3.9.6 (wrapper)" 0 mvnw.log
  run jig verify --profile jvm
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains mvnw.log "test"
  assert_no_file mvn.log
}

# --- Gradle narrowing (D4) -----------------------------------------------------

test_profile_jvm_gradle_narrows_to_subproject_task() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list app/Foo.kt)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: pass (8.5, scope: 1 subprojects)"
  assert_file_contains gradle.log ":app:check"
}

test_profile_jvm_gradle_narrows_to_two_subproject_tasks() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list app/Foo.kt lib/Bar.kt)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: pass (8.5, scope: 2 subprojects)"
  assert_file_contains gradle.log ":app:check"
  assert_file_contains gradle.log ":lib:check"
}

test_profile_jvm_gradle_root_build_file_runs_full() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list build.gradle.kts)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: pass (8.5, scope: not narrowable, ran full set)"
  assert_file_contains gradle.log "^check$"
}

test_profile_jvm_gradle_wrapper_dir_change_runs_full() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  mkdir -p gradle/wrapper
  : > gradle/wrapper/gradle-wrapper.properties
  files=$(_files_list gradle/wrapper/gradle-wrapper.properties)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: pass (8.5, scope: not narrowable, ran full set)"
}

test_profile_jvm_gradle_file_outside_any_subproject_runs_full() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  : > notes.txt
  files=$(_files_list notes.txt)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: pass (8.5, scope: not narrowable, ran full set)"
}

test_profile_jvm_gradle_zero_selection_skips_check() {
  # No changed file at all, and this fixture has no pom.xml (so `test` is
  # never even attempted): `check` is the only line this run could print,
  # and it skips, so the direct script exit is 2 (jp_end: nothing ran).
  # `jig verify` itself still reports this as skip, not fail (RULES.md).
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list)

  _jvm_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: skip (scope: no changed file maps to a subproject)"
}

test_profile_jvm_gradle_missing_selected_module_falls_back_to_full() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list app/Foo.kt)
  mapped=$(_mapped_file "$(printf 'app/Foo.kt\tgone')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "jvm: check: pass (8.5, scope: filter 'gone' selects no tests, ran full set)"
}

# --- Gradle map filters (D5: a subproject path) --------------------------------

test_profile_jvm_gradle_map_filter_overrides_builtin() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list app/Foo.kt)
  mapped=$(_mapped_file "$(printf 'app/Foo.kt\tlib')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gradle.log ":lib:check"
  assert_not_contains "$(cat gradle.log)" ":app:check"
}

test_profile_jvm_gradle_map_dash_means_no_impact() {
  # `check` is the only line a Gradle-only fixture prints; it skips here,
  # so the direct script exit is 2 (jp_end: nothing ran). `jig verify`
  # reports skip, not fail (RULES.md).
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list docs/change.md)
  mapped=$(_mapped_file "$(printf 'docs/change.md\t-')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: skip (scope: no changed file maps to a subproject)"
}

test_profile_jvm_gradle_map_question_mark_falls_back_to_builtin() {
  _jvm_install_gradle
  _gradle_stub 8.5 0 gradle.log
  files=$(_files_list app/Foo.kt)
  mapped=$(_mapped_file "$(printf 'app/Foo.kt\t?')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gradle.log ":app:check"
}

# --- Maven narrowing (D4) -------------------------------------------------------

test_profile_jvm_maven_narrows_to_module() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list module-a/A.java)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: pass (Apache Maven 3.9.6, scope: 1 modules)"
  assert_file_contains mvn.log "-pl module-a -am test"
}

test_profile_jvm_maven_narrows_to_two_modules_joined_by_comma() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list module-a/A.java module-b/B.java)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: pass (Apache Maven 3.9.6, scope: 2 modules)"
  assert_file_contains mvn.log "-pl module-a,module-b -am test"
}

test_profile_jvm_maven_root_pom_runs_full() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list pom.xml)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: pass (Apache Maven 3.9.6, scope: not narrowable, ran full set)"
  assert_file_contains mvn.log "^test$"
}

test_profile_jvm_maven_dot_mvn_dir_change_runs_full() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  mkdir -p .mvn
  : > .mvn/jvm.config
  files=$(_files_list .mvn/jvm.config)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: pass (Apache Maven 3.9.6, scope: not narrowable, ran full set)"
}

test_profile_jvm_maven_file_outside_any_module_runs_full() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  : > notes.txt
  files=$(_files_list notes.txt)

  _jvm_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: pass (Apache Maven 3.9.6, scope: not narrowable, ran full set)"
}

test_profile_jvm_maven_zero_selection_skips_test() {
  # No changed file at all, and this fixture has no Gradle build file (so
  # `check` is never even attempted): `test` is the only line this run
  # could print, and it skips, so the direct script exit is 2 (jp_end:
  # nothing ran). `jig verify` itself still reports this as skip, not
  # fail (RULES.md).
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list)

  _jvm_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: skip (scope: no changed file maps to a module)"
}

test_profile_jvm_maven_missing_selected_module_falls_back_to_full() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list module-a/A.java)
  mapped=$(_mapped_file "$(printf 'module-a/A.java\tmodule-gone')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "jvm: test: pass (Apache Maven 3.9.6, scope: filter 'module-gone' selects no tests, ran full set)"
}

# --- Maven map filters (D5: a module path) --------------------------------------

test_profile_jvm_maven_map_filter_overrides_builtin() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list module-a/A.java)
  mapped=$(_mapped_file "$(printf 'module-a/A.java\tmodule-b')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains mvn.log "-pl module-b -am test"
  assert_not_contains "$(cat mvn.log)" "module-a"
}

test_profile_jvm_maven_map_dash_means_no_impact() {
  # `test` is the only line a Maven-only fixture prints; it skips here, so
  # the direct script exit is 2 (jp_end: nothing ran). `jig verify`
  # reports skip, not fail (RULES.md).
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list docs/change.md)
  mapped=$(_mapped_file "$(printf 'docs/change.md\t-')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: skip (scope: no changed file maps to a module)"
}

test_profile_jvm_maven_map_question_mark_falls_back_to_builtin() {
  _jvm_install_maven
  _mvn_stub "Apache Maven 3.9.6" 0 mvn.log
  files=$(_files_list module-a/A.java)
  mapped=$(_mapped_file "$(printf 'module-a/A.java\t?')")

  _jvm_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains mvn.log "-pl module-a -am test"
}
