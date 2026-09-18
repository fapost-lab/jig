# Tests for the dotnet profile's verify.sh (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools; domains/verify).
# shellcheck shell=bash
#
# Most tests run .ai/profiles/dotnet/verify.sh directly with JIG_VERIFY_SCOPE /
# JIG_VERIFY_FILES / JIG_VERIFY_MAPPED set by hand, the same variables
# `jig verify` itself sets (scripts/lib/verify.sh) — this exercises the
# profile's own narrowing logic without depending on `jig verify`'s map
# parsing or its git-diff computation of "changed". enter_test_env already
# unsets these three (and CI) before every test, so nothing here leaks
# between tests.

_DOTNET_VERIFY=".ai/profiles/dotnet/verify.sh"

# _dotnet_install — a fixture repository with the dotnet profile installed
# and one project + one test project (so `detect` would also find it).
_dotnet_install() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles dotnet >/dev/null
  mkdir -p src/App tests/App.Tests
  cat > App.sln <<'EOF'
Microsoft Visual Studio Solution File, Format Version 12.00
EOF
  cat > src/App/App.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk" />
EOF
  : > src/App/Program.cs
  cat > tests/App.Tests/App.Tests.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.8.0" />
    <PackageReference Include="xunit" Version="2.6.0" />
  </ItemGroup>
</Project>
EOF
  : > tests/App.Tests/FooTests.cs
  git add -A
  git commit -q -m "dotnet fixture"
}

# _dotnet_stub — a `dotnet` on PATH (stack toolchain, adr-20260918-profiles-narrow-per-check-with-project-tools) that answers
# --version, logs `format`/`test` invocations (one line, space-joined
# arguments) to <log>, and exits <rc> for that subcommand.
#
# _dotnet_stub <version> <format-rc> <test-rc> <log>
_dotnet_stub() {
  local version="$1" format_rc="$2" test_rc="$3" log="$4"
  mkdir -p stub-bin
  cat > stub-bin/dotnet <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$version"
  exit 0
fi
printf '%s\n' "\$*" >> "$PWD/$log"
case "\$1" in
  format) exit $format_rc ;;
  test) exit $test_rc ;;
esac
exit 0
STUB
  chmod +x stub-bin/dotnet
  PATH="$PWD/stub-bin:$PATH"
  export PATH
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

# _dotnet_no_tools_bin — a fresh directory of wrapper scripts for exactly
# the tools a profile run needs to reach git/bash/coreutils, resolved
# through `env -i` so an aliased `grep` on the developer's shell cannot
# leak in (conventions/shell.md). Not cached across tests (unlike
# verify.t.sh's run_no_tools, which every test file that runs in isolation
# would need its own copy of): each test using this builds its own
# directory, and there is no shared state to race on.
_dotnet_no_tools_bin() {
  local dir t p esc
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-dotnet-no-tools.XXXXXX")
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

# _dotnet_no_tools <cmd...> — like run, but with PATH stripped to exactly
# the tools above, so `dotnet` is deterministically unreachable regardless
# of what the machine running the tests happens to have installed.
_dotnet_no_tools() {
  local bin
  bin=$(_dotnet_no_tools_bin)
  PATH="$bin" run "$@"
}

# _dotnet_scoped <files-file> [mapped-file] — run verify.sh narrowed to
# <files-file>, with <mapped-file> as JIG_VERIFY_MAPPED when given.
_dotnet_scoped() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$1"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  if [ -n "${2:-}" ]; then
    JIG_VERIFY_MAPPED="$2"
    export JIG_VERIFY_MAPPED
  else
    unset JIG_VERIFY_MAPPED
  fi
  run bash "$_DOTNET_VERIFY"
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
}

# --- detect ------------------------------------------------------------------

test_profile_dotnet_detected_for_csproj() {
  fixture_repo
  : > App.csproj
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_HOME/profiles"
  '
  assert_eq 0 "$RC"
  assert_contains "$OUT" "dotnet"
}

test_profile_dotnet_detected_for_sln() {
  fixture_repo
  : > App.sln
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_HOME/profiles"
  '
  assert_contains "$OUT" "dotnet"
}

test_profile_dotnet_detected_for_fsproj() {
  fixture_repo
  : > App.fsproj
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_HOME/profiles"
  '
  assert_contains "$OUT" "dotnet"
}

# --- skip without toolchain ---------------------------------------------------

test_profile_dotnet_skips_every_check_without_toolchain() {
  _dotnet_install
  _dotnet_no_tools jig verify --profile dotnet
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: format: skip (not found on PATH)"
  assert_contains "$OUT" "dotnet: test: skip (not found on PATH)"
  assert_contains "$OUT" "RESULT dotnet: skip"
}

# --- pass / fail / version per check ------------------------------------------

test_profile_dotnet_format_pass_and_fail_report_version() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  run jig verify --profile dotnet
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: format: pass (8.0.100)"

  _dotnet_stub 8.0.100 1 0 dotnet.log
  run jig verify --profile dotnet
  assert_eq 1 "$RC"
  assert_contains "$OUT" "dotnet: format: fail (8.0.100)"
}

test_profile_dotnet_test_pass_and_fail_report_version() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  run jig verify --profile dotnet
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100)"

  _dotnet_stub 8.0.100 0 1 dotnet.log
  run jig verify --profile dotnet
  assert_eq 1 "$RC"
  assert_contains "$OUT" "dotnet: test: fail (8.0.100)"
}

test_profile_dotnet_full_mode_runs_plain_dotnet_test_no_project_guessed() {
  # "several .sln files at the root and no narrowing: run plain `dotnet
  # test`, let dotnet report" — the profile never picks among them itself.
  _dotnet_install
  : > Second.sln
  _dotnet_stub 8.0.100 0 0 dotnet.log
  run jig verify --profile dotnet
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains dotnet.log "^test$"
  assert_not_contains "$(cat dotnet.log)" ".sln"
}

# --- narrowing: format on changed .cs/.fs/.vb files (D4) ----------------------

test_profile_dotnet_format_narrowed_to_changed_files() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  : > src/App/Extra.txt
  files=$(_files_list src/App/Program.cs src/App/Extra.txt)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: format: pass (8.0.100, scope: 1 files)"
  assert_file_contains dotnet.log "src/App/Program.cs"
  assert_not_contains "$(cat dotnet.log)" "Extra.txt"
}

test_profile_dotnet_format_skips_when_no_changed_source_files() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list notes.txt)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: format: skip (scope: no changed .cs/.fs/.vb files)"
}

# Documentation reaches no check (jp_is_doc): both checks skip, and the
# profile reports skip rather than pass.
test_profile_dotnet_documentation_only_change_skips_every_check() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  : > README.md
  files=$(_files_list README.md)

  _dotnet_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: format: skip"
  assert_contains "$OUT" "dotnet: test: skip"
}

# --- always-ALL triggers (D4) --------------------------------------------------

test_profile_dotnet_sln_change_runs_full_format_and_test() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list App.sln)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "dotnet: format: pass (8.0.100, scope: sln/build config changed, whole project)"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100, scope: not narrowable, ran full set)"
  assert_file_contains dotnet.log "^format --verify-no-changes$"
  assert_file_contains dotnet.log "^test$"
}

test_profile_dotnet_directory_build_props_runs_full() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list Directory.Build.props)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100, scope: not narrowable, ran full set)"
}

test_profile_dotnet_global_json_runs_full() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list global.json)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100, scope: not narrowable, ran full set)"
}

test_profile_dotnet_nuget_config_runs_full() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list nuget.config)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100, scope: not narrowable, ran full set)"
}

# --- narrowing: test project resolution (D4) -----------------------------------

test_profile_dotnet_changed_file_in_test_project_narrows_to_that_project() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list tests/App.Tests/FooTests.cs)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100, scope: 1 test projects)"
  assert_file_contains dotnet.log "test tests/App.Tests/App.Tests.csproj"
}

test_profile_dotnet_changed_file_in_non_test_project_runs_full() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list src/App/Program.cs)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100, scope: not narrowable, ran full set)"
  assert_file_contains dotnet.log "^test$"
}

test_profile_dotnet_changed_file_with_no_ancestor_project_runs_full() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  : > notes.txt
  files=$(_files_list notes.txt)

  _dotnet_scoped "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: pass (8.0.100, scope: not narrowable, ran full set)"
}

test_profile_dotnet_zero_selection_skips_test() {
  # No changed file at all: format has nothing to lint either, so both
  # checks skip and the direct script exit is 2 (jp_end: nothing ran).
  # `jig verify` itself still reports this as skip, not fail (RULES.md).
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list)

  _dotnet_scoped "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: skip (scope: no changed file maps to a test project)"
}

test_profile_dotnet_missing_selected_project_falls_back_to_full() {
  # The map names a test project that no longer exists on disk: a narrowing
  # that selects nothing is not a pass (ADR-0041) — the full set runs.
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list tests/App.Tests/FooTests.cs)
  mapped=$(_mapped_file "$(printf 'tests/App.Tests/FooTests.cs\ttests/Gone/Gone.csproj')")

  _dotnet_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" \
    "dotnet: test: pass (8.0.100, scope: filter 'tests/Gone/Gone.csproj' selects no tests, ran full set)"
}

# --- map filters (D5: a test project path) -------------------------------------

test_profile_dotnet_map_filter_overrides_the_builtin_project_mapping() {
  _dotnet_install
  mkdir -p tests/Other.Tests
  cat > tests/Other.Tests/Other.Tests.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.8.0" />
    <PackageReference Include="NUnit" Version="3.14.0" />
  </ItemGroup>
</Project>
EOF
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list src/App/Program.cs)
  mapped=$(_mapped_file "$(printf 'src/App/Program.cs\ttests/Other.Tests/Other.Tests.csproj')")

  _dotnet_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains dotnet.log "test tests/Other.Tests/Other.Tests.csproj"
  assert_not_contains "$(cat dotnet.log)" "App.Tests.csproj"
}

test_profile_dotnet_map_dash_means_no_impact() {
  # docs/change.md does not exist on disk and is not a .cs/.fs/.vb file
  # either way, so format also skips: both checks skip and the direct
  # script exit is 2 (jp_end: nothing ran); `jig verify` reports skip, not
  # fail (RULES.md).
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list docs/change.md)
  mapped=$(_mapped_file "$(printf 'docs/change.md\t-')")

  _dotnet_scoped "$files" "$mapped"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: test: skip (scope: no changed file maps to a test project)"
}

test_profile_dotnet_map_question_mark_falls_back_to_builtin() {
  _dotnet_install
  _dotnet_stub 8.0.100 0 0 dotnet.log
  files=$(_files_list tests/App.Tests/FooTests.cs)
  mapped=$(_mapped_file "$(printf 'tests/App.Tests/FooTests.cs\t?')")

  _dotnet_scoped "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains dotnet.log "test tests/App.Tests/App.Tests.csproj"
}
