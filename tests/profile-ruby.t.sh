# Tests for the ruby profile (profiles/ruby/verify.sh; design.md D2/D4/D5;
# adr-20260918-profiles-narrow-per-check-with-project-tools). Runs the profile script directly rather than through `jig
# verify`, setting JIG_VERIFY_SCOPE/JIG_VERIFY_FILES/JIG_VERIFY_MAPPED the
# way `jig verify` does (ADR-0013, ADR-0041), so each test controls its own
# scope without a full init. This file is sourced alone (tests/run.sh),
# so it carries its own fixtures and stubs rather than reusing
# tests/verify.t.sh's.
# shellcheck shell=bash

# --- fixtures and stubs ------------------------------------------------------

# rb_lockfile <gem...> — a minimal Gemfile.lock that resolves exactly the
# given gems, in the 4-space-indented "specs:" shape _rb_gem_locked reads.
rb_lockfile() {
  local g
  {
    printf 'GEM\n  remote: https://rubygems.org/\n  specs:\n'
    for g in "$@"; do
      printf '    %s (1.0.0)\n' "$g"
    done
    printf '\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n'
    for g in "$@"; do
      printf '  %s\n' "$g"
    done
    printf '\nBUNDLED WITH\n   2.4.10\n'
  } > Gemfile.lock
}

# rb_fixture <gem...> — an empty Gemfile, a Gemfile.lock resolving <gem...>,
# and the directories a test plants files under.
rb_fixture() {
  : > Gemfile
  mkdir -p app/models lib spec/models spec/lib test/models
  rb_lockfile "$@"
}

# rb_stub_bundle [<rc-rubocop>] [<rc-rspec>] [<rc-rake>] — a `bundle` on
# PATH that logs every `bundle exec <tool> <args...>` call's arguments to
# "<tool>.args" (one line, space-joined; empty for a bare "bundle exec
# <tool>") and exits with the code given for that tool (0 when omitted).
# `bundle exec <tool> --version` answers "<tool> stub-version" without
# touching the log, so a version probe never counts as an invocation.
rb_stub_bundle() {
  local rc_rubocop="${1:-0}" rc_rspec="${2:-0}" rc_rake="${3:-0}"
  mkdir -p stub-bin
  cat > stub-bin/bundle <<STUB
#!/usr/bin/env bash
if [ "\$1" != exec ]; then
  exit 1
fi
shift
tool="\$1"
shift
if [ "\$1" = "--version" ]; then
  printf '%s stub-version\n' "\$tool"
  exit 0
fi
printf '%s\n' "\$*" >> "\$PWD/\$tool.args"
case "\$tool" in
  rubocop) exit $rc_rubocop ;;
  rspec) exit $rc_rspec ;;
  rake) exit $rc_rake ;;
esac
exit 0
STUB
  chmod +x stub-bin/bundle
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# rb_stub_bin_rails [<rc>] — the project's own bin/rails, logging its
# arguments to "rails.args" the same way rb_stub_bundle does, answering
# --version without logging.
rb_stub_bin_rails() {
  local rc="${1:-0}"
  mkdir -p bin
  cat > bin/rails <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf 'Rails stub-version\n'
  exit 0
fi
printf '%s\n' "\$*" >> "\$PWD/rails.args"
exit $rc
STUB
  chmod +x bin/rails
}

# The tools scripts/lib/profile.sh and profiles/ruby/verify.sh actually use
# once bundle is out of the picture — matches tests/verify.t.sh's
# _NO_TOOLS_LIST, minus the point of this list: bundle is deliberately never
# on it.
_RB_NO_TOOLS_LIST="bash sh sed awk grep find mktemp cat cp mv rm mkdir sort tr head tail wc chmod ls date dirname basename cmp paste stat readlink diff env"

# rb_notools_path — a directory of wrapper scripts for every tool in
# _RB_NO_TOOLS_LIST, resolved through `env -i` so a shell alias (e.g. grep
# aliased to ugrep) cannot leak in as a self-referential symlink
# (conventions/shell.md). No `bundle` wrapper is ever created.
rb_notools_path() {
  local dir="${JIG_TEST_TMP}.rb-notools" t p
  mkdir -p "$dir"
  for t in $_RB_NO_TOOLS_LIST; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*)
        printf '#!/bin/sh\nexec %s "$@"\n' "$p" > "$dir/$t"
        chmod +x "$dir/$t"
        ;;
    esac
  done
  printf '%s\n' "$dir"
}

# rb_scope <files> — export JIG_VERIFY_SCOPE/JIG_VERIFY_FILES for a
# narrowed run; <files> is the changed-path list, one per line.
rb_scope() {
  printf '%s\n' "$1" > "${JIG_TEST_TMP}.rb-files"
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="${JIG_TEST_TMP}.rb-files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
}

# rb_mapped <tsv> — export JIG_VERIFY_MAPPED with the given
# "<path><TAB><decision>" lines (already formatted, one per line).
rb_mapped() {
  printf '%s\n' "$1" > "${JIG_TEST_TMP}.rb-mapped"
  JIG_VERIFY_MAPPED="${JIG_TEST_TMP}.rb-mapped"
  export JIG_VERIFY_MAPPED
}

rb_verify() {
  run bash "$JIG_HOME/profiles/ruby/verify.sh"
}

# --- detect ------------------------------------------------------------------

test_profile_ruby_detect_gemfile_is_ruby() {
  mkdir -p fx
  : > fx/Gemfile
  run bash -c '
    JIG_LIB="$1/scripts/lib"
    JIG_PROJECT="$2"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_LIB/../../profiles"
  ' _ "$JIG_HOME" "$PWD/fx"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic"
  assert_contains "$OUT" "ruby"
  assert_not_contains "$OUT" "node"
  assert_not_contains "$OUT" "dart"
}

# --- bundle absent: skip everything, one reason ----------------------------

test_profile_ruby_skips_everything_without_bundle() {
  rb_fixture rspec-core rspec
  local bin
  bin=$(rb_notools_path)
  PATH="$bin" rb_verify
  assert_eq 2 "$RC"
  assert_contains "$OUT" "ruby: rubocop: skip (bundle not found on PATH)"
  assert_contains "$OUT" "ruby: rspec: skip (bundle not found on PATH)"
}

# --- rubocop: pass, fail, version in the verdict ---------------------------

test_profile_ruby_rubocop_pass_names_its_version() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rubocop: pass (rubocop stub-version)"
}

test_profile_ruby_rubocop_fail_names_its_version() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 1 0 0
  rb_verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "ruby: rubocop: fail (rubocop stub-version)"
}

test_profile_ruby_rubocop_skips_when_not_in_lockfile() {
  rb_fixture rspec-core rspec
  rb_stub_bundle 0 0 0
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rubocop: skip (rubocop not listed in Gemfile.lock)"
}

# --- rubocop narrowing (D4: changed .rb / .rake files only) ----------------

test_profile_ruby_rubocop_narrows_to_changed_rb_and_rake_files() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  mkdir -p lib/tasks
  printf 'class Foo\nend\n' > app/models/foo.rb
  printf 'task :x\n' > lib/tasks/x.rake
  printf '# fixture\n' > README.md
  rb_scope "$(printf 'app/models/foo.rb\nlib/tasks/x.rake\nREADME.md\n')"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rubocop: pass (rubocop stub-version, scope: 2 files)"
  assert_eq "app/models/foo.rb lib/tasks/x.rake" "$(cat rubocop.args)"
}

test_profile_ruby_rubocop_full_run_when_rubocop_yml_changes() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  : > .rubocop.yml
  rb_scope ".rubocop.yml"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rubocop: pass (rubocop stub-version, scope: .rubocop.yml changed, whole project)"
}

test_profile_ruby_rubocop_scope_selects_nothing_skips() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  printf '# fixture\n' > README.md
  rb_scope "README.md"
  rb_verify
  # Neither check finds anything to run against a documentation-only
  # change: rubocop has no .rb/.rake file, and README.md maps to nothing
  # for rspec either (a doc file, not a project-wide one) — so the profile
  # reports skip on both and exits 2 (ADR-0013: a skip is not a pass).
  assert_eq 2 "$RC"
  assert_contains "$OUT" "ruby: rubocop: skip (scope: no changed .rb or .rake files)"
  assert_contains "$OUT" "ruby: rspec: skip (scope: no changed file maps to a test)"
}

# --- rspec narrowing (D4: app/x/y.rb, lib/y.rb, changed spec itself) -------

test_profile_ruby_rspec_narrows_app_and_lib_and_spec_paths() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  printf 'class Foo\nend\n' > app/models/foo.rb
  printf 'RSpec.describe Foo do\nend\n' > spec/models/foo_spec.rb
  printf 'module Bar\nend\n' > lib/bar.rb
  printf 'RSpec.describe "Bar" do\nend\n' > spec/bar_spec.rb
  printf 'RSpec.describe "Other" do\nend\n' > spec/other_spec.rb
  rb_scope "$(printf 'app/models/foo.rb\nlib/bar.rb\nspec/other_spec.rb\n')"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rspec: pass (rspec stub-version, scope: 3 test files)"
  assert_eq "spec/bar_spec.rb spec/models/foo_spec.rb spec/other_spec.rb" "$(cat rspec.args)"
}

test_profile_ruby_rspec_lib_prefers_lib_subdir_spec_when_both_exist() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  mkdir -p spec/lib
  printf 'module Baz\nend\n' > lib/baz.rb
  printf 'RSpec.describe "Baz nested" do\nend\n' > spec/lib/baz_spec.rb
  printf 'RSpec.describe "Baz root" do\nend\n' > spec/baz_spec.rb
  rb_scope "lib/baz.rb"
  rb_verify
  assert_eq 0 "$RC"
  assert_eq "spec/lib/baz_spec.rb" "$(cat rspec.args)"
}

test_profile_ruby_rspec_full_run_when_gemfile_lock_changes() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  rb_scope "Gemfile.lock"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rspec: pass (rspec stub-version, scope: not narrowable, ran full set)"
  assert_eq "" "$(cat rspec.args)"
}

test_profile_ruby_rspec_missing_target_falls_back_to_full_run() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  mkdir -p app/orphan
  printf 'class Missing\nend\n' > app/orphan/missing.rb
  rb_scope "app/orphan/missing.rb"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rspec: pass (rspec stub-version, scope: filter 'spec/orphan/missing_spec.rb' selects no tests, ran full set)"
  assert_eq "" "$(cat rspec.args)"
}

test_profile_ruby_rspec_fail_names_its_version() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 1 0
  rb_verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "ruby: rspec: fail (rspec stub-version)"
}

# --- minitest: bin/rails (narrowable) and rake (not) -----------------------

test_profile_ruby_minitest_via_bin_rails_narrows() {
  rb_fixture
  rb_stub_bundle 0 0 0
  rb_stub_bin_rails 0
  printf 'class Foo\nend\n' > app/models/foo.rb
  printf 'require "test_helper"\n' > test/models/foo_test.rb
  rb_scope "app/models/foo.rb"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: minitest: pass (Rails stub-version, scope: 1 test files)"
  assert_eq "test test/models/foo_test.rb" "$(cat rails.args)"
}

test_profile_ruby_minitest_via_bin_rails_unscoped_runs_plain_test() {
  rb_fixture
  rb_stub_bundle 0 0 0
  rb_stub_bin_rails 0
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: minitest: pass (Rails stub-version)"
  assert_eq "test" "$(cat rails.args)"
}

test_profile_ruby_minitest_via_rake_is_never_narrowed() {
  rb_fixture minitest rake
  rb_stub_bundle 0 0 0
  : > Rakefile
  printf 'require "minitest/autorun"\n' > test/foo_test.rb
  rb_scope "test/foo_test.rb"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: minitest: pass (rake stub-version, scope: not narrowable, ran full set)"
  assert_eq "test" "$(cat rake.args)"
}

test_profile_ruby_no_test_framework_skips_with_reason() {
  rb_fixture sinatra
  rb_stub_bundle 0 0 0
  rb_verify
  assert_eq 2 "$RC"
  assert_contains "$OUT" "ruby: rubocop: skip (rubocop not listed in Gemfile.lock)"
  assert_contains "$OUT" "ruby: test: skip (no rspec or minitest runner found"
}

# --- project map (ADR-0041, D5: filters are spec/test file paths) ---------

test_profile_ruby_map_filter_overrides_builtin_mapping() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  printf 'class Foo\nend\n' > app/models/foo.rb
  printf 'RSpec.describe "Custom" do\nend\n' > spec/custom_spec.rb
  rb_scope "app/models/foo.rb"
  rb_mapped "$(printf 'app/models/foo.rb\tspec/custom_spec.rb')"
  rb_verify
  assert_eq 0 "$RC"
  assert_eq "spec/custom_spec.rb" "$(cat rspec.args)"
}

# --- glob-list regression: an always-ALL glob must not be expanded against -
# --- files on disk (jp_path_matches) -----------------------------------------

test_profile_ruby_rspec_config_glob_not_masked_by_sibling_on_disk() {
  # RB_TEST_ALL_GLOBS includes "config/*"; before the fix it was split with
  # `for g in $LIST` with pathname expansion on, so the word expanded to
  # whichever config/* sibling sits on disk (here config/application.rb)
  # instead of staying the literal pattern, and a changed config/routes.rb
  # (deleted, never created on disk) no longer matched it.
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  mkdir -p config
  : > config/application.rb
  rb_scope "config/routes.rb"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rspec: pass (rspec stub-version, scope: not narrowable, ran full set)"
}

# --- IFS regression: rubocop's own file-list narrowing must not corrupt ----
# --- rspec's later scope decision (_jp_decide_raw) --------------------------
# Before the fix, a profile narrowing a check to a changed-file list did
# `IFS='<newline>'; set -f; set -- $files; set +f` and then left IFS as
# that literal newline instead of restoring the default, so a later
# space-separated map decision (two filters on one line) in the same run
# collapsed into one token. rubocop runs before rspec in this profile, so
# this exercises it taking the changed-file-list path first.

test_profile_ruby_rspec_map_decision_two_filters_after_rubocop_file_list_path() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  mkdir -p app/models
  printf 'class User\nend\n' > app/models/user.rb
  printf 'RSpec.describe "A" do\nend\n' > spec/models/user_a_spec.rb
  printf 'RSpec.describe "B" do\nend\n' > spec/models/user_b_spec.rb
  rb_scope "app/models/user.rb"
  rb_mapped "$(printf 'app/models/user.rb\tspec/models/user_a_spec.rb spec/models/user_b_spec.rb')"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rubocop: pass (rubocop stub-version, scope: 1 files)"
  assert_contains "$OUT" "ruby: rspec: pass (rspec stub-version, scope: 2 test files)"
  assert_eq "spec/models/user_a_spec.rb spec/models/user_b_spec.rb" "$(cat rspec.args)"
}

test_profile_ruby_rspec_runs_full_after_rubocop_file_list_path() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  mkdir -p app/models
  printf 'class User\nend\n' > app/models/user.rb
  rb_scope "$(printf 'app/models/user.rb\nGemfile\n')"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rubocop: pass (rubocop stub-version, scope: 1 files)"
  assert_contains "$OUT" "ruby: rspec: pass (rspec stub-version, scope: not narrowable, ran full set)"
}

test_profile_ruby_map_dash_selects_nothing_skips() {
  rb_fixture rubocop rspec-core rspec
  rb_stub_bundle 0 0 0
  printf 'class Foo\nend\n' > app/models/foo.rb
  rb_scope "app/models/foo.rb"
  rb_mapped "$(printf 'app/models/foo.rb\t-')"
  rb_verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "ruby: rspec: skip (scope: no changed file maps to a test)"
}
