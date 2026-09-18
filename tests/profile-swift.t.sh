# Tests for the swift profile (domains/verify; profiles-scope-and-languages
# design D1/D2/D4/D5). `swift` is resolved on PATH alone (D2), so most tests
# run the profile script directly with JIG_VERIFY_SCOPE/JIG_VERIFY_FILES/
# JIG_VERIFY_MAPPED set the way `jig verify` sets them
# (scripts/lib/profile.sh header) — the same shortcut tests/verify.t.sh
# takes for the shell profile outside a git repository, and explicitly
# sanctioned by the brief. The map-filter behaviour is covered once through
# the real `jig verify --changed` path instead, so the core's own map
# parsing is exercised too.
# shellcheck shell=bash

# --- no-toolchain PATH -------------------------------------------------------

# _SWIFT_NO_TOOLS_LIST — every tool the swift profile and the library it
# sources need when `swift` itself is absent: bash's own shebang,
# sed/awk/grep/sort (jp_version, jp_decide) and the usual coreutils
# profile.sh's helpers call. Deliberately excludes swift: the point of
# run_no_tools is that it is not on PATH regardless of what the machine
# running the suite happens to have installed — this is also the D7/D2
# scenario itself (no Swift toolchain, e.g. Windows) that the profile must
# skip rather than fail (conventions/shell.md: a PATH built from an
# allow-list, never from "system directories believed tool-free").
_SWIFT_NO_TOOLS_LIST="bash sh sed awk grep mktemp cat cp mv rm mkdir sort tr head tail wc chmod ls date dirname basename env"

# run_no_tools <cmd...> — like `run`, but PATH is rebuilt from
# _SWIFT_NO_TOOLS_LIST alone, through wrapper scripts (never symlinks:
# tests/verify.t.sh's own _no_tools_fill explains why), so the swift
# profile's "swift not found" skip path is exercised deterministically.
run_no_tools() {
  local dir out t p esc
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-swift-no-tools.XXXXXX")
  for t in $_SWIFT_NO_TOOLS_LIST; do
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
  out=$(_run_out)
  set +e
  ( PATH="$dir" "$@" ) >"$out" 2>&1
  RC=$?
  set -e
  OUT=$(cat "$out")
  rm -f "$out"
  rm -rf "$dir"
  export OUT RC
}

# _swift_stub <build-rc> <test-rc> — a swift stub on PATH. Answers `swift
# --version`, logs every invocation's full argument line to swift.log (one
# per invocation), and exits with the given code for `build` or `test`.
_swift_stub() {
  local build_rc="$1" test_rc="$2"
  mkdir -p stub-bin
  cat > stub-bin/swift <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/swift.log"
if [ "\$1" = "--version" ]; then
  printf 'Swift version 5.9 (swift-5.9-RELEASE)\n'
  exit 0
fi
if [ "\$1" = "build" ]; then exit $build_rc; fi
if [ "\$1" = "test" ]; then exit $test_rc; fi
exit 0
STUB
  chmod +x stub-bin/swift
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _swift_package — a minimal Package.swift and one source file, so a
# scoped run has something other than documentation to narrow around.
_swift_package() {
  mkdir -p Sources/App
  printf '// swift-tools-version:5.9\n' > Package.swift
  printf 'print("hi")\n' > Sources/App/main.swift
}

_swift_run() {
  run bash "$JIG_HOME/profiles/swift/verify.sh"
}

# --- detect ------------------------------------------------------------------

test_profile_swift_detected_by_package_swift() {
  fixture_repo
  printf '// swift-tools-version:5.9\n' > Package.swift
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "detected profiles:"
  assert_contains "$OUT" "swift"
}

test_profile_swift_not_detected_without_package_swift() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "swift"
}

# --- no swift on PATH (D7: e.g. Windows without a toolchain) ---------------

test_profile_swift_skips_both_checks_without_swift() {
  _swift_package
  run_no_tools bash "$JIG_HOME/profiles/swift/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: skip (swift not found on PATH)"
  assert_contains "$OUT" "swift: test: skip (swift not found on PATH)"
}

# --- unscoped: pass, fail, version in verdict (AC-05) -----------------------

test_profile_swift_unscoped_pass_with_version_in_verdict() {
  _swift_package
  _swift_stub 0 0
  _swift_run
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: pass (Swift version 5.9 (swift-5.9-RELEASE))"
  assert_contains "$OUT" "swift: test: pass (Swift version 5.9 (swift-5.9-RELEASE))"
  assert_file_contains swift.log "^build\$"
  assert_file_contains swift.log "^test\$"
}

test_profile_swift_unscoped_fail_on_nonzero_exit() {
  _swift_package
  _swift_stub 1 1
  _swift_run
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: fail"
  assert_contains "$OUT" "swift: test: fail"
}

test_profile_swift_unscoped_build_fail_does_not_skip_test() {
  _swift_package
  _swift_stub 1 0
  _swift_run
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: fail"
  assert_contains "$OUT" "swift: test: pass"
}

# --- never narrowed (D4 swift row): a scoped run still runs both in full ---

test_profile_swift_scoped_code_change_runs_full_set_not_narrowable() {
  _swift_package
  _swift_stub 0 0
  printf 'Sources/App/main.swift\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _swift_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: pass (Swift version 5.9 (swift-5.9-RELEASE), scope: not narrowable, ran full set)"
  assert_contains "$OUT" "swift: test: pass (Swift version 5.9 (swift-5.9-RELEASE), scope: not narrowable, ran full set)"
  assert_file_contains swift.log "^build\$"
  assert_file_contains swift.log "^test\$"
}

test_profile_swift_scoped_package_manifest_change_runs_full_set() {
  _swift_package
  _swift_stub 0 0
  printf 'Package.swift\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _swift_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: not narrowable, ran full set"
}

# --- doc-only change: skip both checks instead of running them (D4) --------

test_profile_swift_scoped_docs_only_skips_both_checks() {
  _swift_package
  _swift_stub 0 0
  printf 'README.md\ndocs/guide.md\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _swift_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: skip (scope: only documentation changed)"
  assert_contains "$OUT" "swift: test: skip (scope: only documentation changed)"
  # The version probe always runs (it only names the tool, adr-20260918-profiles-narrow-per-check-with-project-tools); build
  # and test themselves never do.
  assert_not_contains "$(cat swift.log)" "build"
  assert_not_contains "$(cat swift.log)" "test"
}

test_profile_swift_scoped_mixed_docs_and_code_runs_full_set() {
  _swift_package
  _swift_stub 0 0
  printf 'README.md\nSources/App/main.swift\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _swift_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: not narrowable, ran full set"
}

# --- map decisions (D5: swift declares only "-" and "ALL", no filters) -----

test_profile_swift_map_dash_on_the_only_changed_file_skips() {
  _swift_package
  _swift_stub 0 0
  printf 'Sources/App/main.swift\n' > "$JIG_TEST_TMP.files"
  printf 'Sources/App/main.swift\t-\n' > "$JIG_TEST_TMP.mapped"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files" JIG_VERIFY_MAPPED="$JIG_TEST_TMP.mapped"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _swift_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: skip (scope: only documentation changed)"
  assert_contains "$OUT" "swift: test: skip (scope: only documentation changed)"
}

# A map decision other than "-" forces the full run even when the profile's
# own builtin rule would have called the path documentation (D5: swift has
# no filters to honour anything more specific with).
test_profile_swift_map_marks_a_doc_file_all_runs_full_set() {
  _swift_package
  _swift_stub 0 0
  printf 'README.md\n' > "$JIG_TEST_TMP.files"
  printf 'README.md\tALL\n' > "$JIG_TEST_TMP.mapped"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files" JIG_VERIFY_MAPPED="$JIG_TEST_TMP.mapped"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _swift_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: not narrowable, ran full set"
}

# --- the real jig verify --changed path, with a committed .ai/verify/swift.map

test_profile_swift_real_verify_changed_reads_project_map() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles swift >/dev/null
  _swift_package
  mkdir -p .ai/verify
  printf 'docs/*.md -\n' > .ai/verify/swift.map
  mkdir -p docs
  printf '# guide\n' > docs/guide.md
  git add -A
  git commit -q -m "package"
  printf '# guide, updated\n' >> docs/guide.md

  local stub_dir="$JIG_TEST_TMP-stub-bin"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/swift" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/swift.log"
if [ "\$1" = "--version" ]; then printf 'Swift version 5.9\n'; exit 0; fi
exit 0
STUB
  chmod +x "$stub_dir/swift"
  PATH="$stub_dir:$PATH"
  export PATH

  run jig verify --changed --profile swift
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "map .ai/verify/swift.map"
  assert_contains "$OUT" "swift: build: skip (scope: only documentation changed)"
  assert_contains "$OUT" "swift: test: skip (scope: only documentation changed)"
  assert_contains "$OUT" "RESULT swift: skip"
  assert_not_contains "$(cat swift.log)" "build"
  assert_not_contains "$(cat swift.log)" "test"
}
