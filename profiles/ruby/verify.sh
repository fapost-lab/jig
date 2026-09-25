#!/usr/bin/env bash
# Verification for the ruby profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "ruby: <check>: pass|fail|skip (<note>)".
#
# Tools come from `bundle exec` only, and only when the project's own
# Gemfile.lock names them (adr-20260918-profiles-narrow-per-check-with-project-tools): a global rubocop or rspec runs with
# another version and without the project's plugins, and its verdict says
# nothing about this project. `bundle` itself is the one thing read from
# PATH (D2); without it every check is out of reach and the whole profile
# skips with one reason.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools), per check: rubocop lints the changed .rb
# and .rake files. The test check is rspec when Gemfile.lock lists it,
# otherwise minitest through `bin/rails test` (narrowable, when bin/rails
# exists) or `bundle exec rake test` (not narrowable, when a Rakefile and a
# test/ directory exist). A changed spec/test file maps to itself; a changed
# app/x/y.rb maps to spec/x/y_spec.rb or test/x/y_test.rb; a changed lib/y.rb
# maps to spec/lib/y_spec.rb or spec/y_spec.rb (first existing), or the
# test/ equivalents — everything else maps to ALL.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin ruby

# Files whose change can alter the result of the test check, whichever
# framework runs it.
RB_TEST_ALL_GLOBS="Gemfile Gemfile.lock spec/spec_helper.rb spec/rails_helper.rb test/test_helper.rb config/* .rspec"

# _rb_gem_locked <name> — whether Gemfile.lock resolved a gem named <name>.
# Bundler lists every resolved gem, direct or transitive, as its own
# 4-space-indented "<name> (<version>)" line under "specs:"; a 6-space line
# is only that gem's own dependency, not a separate resolution, so the
# indent is what tells the two apart.
_rb_gem_locked() {
  [ -f Gemfile.lock ] || return 1
  grep -qE "^    $1 \(" Gemfile.lock
}

# _rb_is_test_file <path> — a spec or minitest file by naming convention,
# regardless of which framework this project uses.
_rb_is_test_file() {
  case "$1" in
    spec/*_spec.rb) return 0 ;;
    test/*_test.rb) return 0 ;;
  esac
  return 1
}

_rb_minitest_via_rails() { [ -f bin/rails ]; }
_rb_minitest_via_rake() { [ -f Rakefile ] && [ -d test ]; }

# _rb_test_check_name — the name the test check reports under: "rspec" when
# Gemfile.lock resolved it, "minitest" when a runner for it exists, "test"
# when neither is true. Computed without bundle, so a "bundle not found"
# skip can still name the right check.
_rb_test_check_name() {
  if _rb_gem_locked rspec-core || _rb_gem_locked rspec; then
    printf 'rspec\n'
  elif _rb_minitest_via_rails || _rb_minitest_via_rake; then
    printf 'minitest\n'
  else
    printf 'test\n'
  fi
}

RB_TEST=$(_rb_test_check_name)

if ! command -v bundle >/dev/null 2>&1; then
  if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
    jp_plan rubocop skip "bundle not found on PATH"
    jp_plan "$RB_TEST" skip "bundle not found on PATH"
    exit 0
  fi
  jp_skip rubocop "bundle not found on PATH"
  jp_skip "$RB_TEST" "bundle not found on PATH"
  jp_end
fi

# --- rubocop -------------------------------------------------------------

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  if [ ! -f Gemfile.lock ] || ! _rb_gem_locked rubocop; then
    jp_plan rubocop skip "rubocop not listed in Gemfile.lock"
  elif jp_scoped && jp_changed_any .rubocop.yml; then
    jp_plan rubocop full ".rubocop.yml changed"
  elif jp_scoped; then
    files=$(jp_changed rb rake)
    if [ -z "$files" ]; then
      jp_plan rubocop skip "no changed .rb or .rake files"
    else
      jp_plan rubocop filtered "changed files: $(printf '%s\n' "$files" | paste -sd, -)"
    fi
  else
    jp_plan rubocop full "full scope"
  fi
else

if [ ! -f Gemfile.lock ]; then
  jp_skip rubocop "no Gemfile.lock"
elif ! _rb_gem_locked rubocop; then
  jp_skip rubocop "rubocop not listed in Gemfile.lock"
else
  v=$(jp_version bundle exec rubocop --version)
  if jp_scoped && ! jp_changed_any .rubocop.yml; then
    files=$(jp_changed rb rake)
    if [ -z "$files" ]; then
      jp_skip rubocop "scope: no changed .rb or .rake files"
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
      jp_run rubocop "$v, scope: $n files" bundle exec rubocop "$@"
    fi
  elif jp_scoped; then
    jp_run rubocop "$v, scope: .rubocop.yml changed, whole project" bundle exec rubocop
  else
    jp_run rubocop "$v" bundle exec rubocop
  fi
fi
fi

# --- rspec / minitest ------------------------------------------------------

# _rb_builtin_test <path> — the tests a changed path needs: itself for a
# spec/test file, the file the naming convention derives for app/ and lib/
# sources, ALL for a project-wide file or anything that maps to nothing,
# nothing for documentation.
_rb_builtin_test() {
  local f="$1" rest c1 c2
  if jp_path_matches "$f" "$RB_TEST_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  case "$f" in
    *.md|*.rst|docs/*|.ai/*) return 0 ;;
  esac
  case "$f" in
    *.rb) ;;
    *) printf 'ALL\n'; return 0 ;;
  esac
  if _rb_is_test_file "$f"; then
    printf '%s\n' "$f"
    return 0
  fi
  case "$f" in
    app/*)
      rest=${f#app/}
      rest=${rest%.rb}
      if [ "$RB_TEST" = rspec ]; then
        printf 'spec/%s_spec.rb\n' "$rest"
      else
        printf 'test/%s_test.rb\n' "$rest"
      fi
      ;;
    lib/*)
      rest=${f#lib/}
      rest=${rest%.rb}
      if [ "$RB_TEST" = rspec ]; then
        c1="spec/lib/${rest}_spec.rb"
        c2="spec/${rest}_spec.rb"
      else
        c1="test/lib/${rest}_test.rb"
        c2="test/${rest}_test.rb"
      fi
      if [ -f "$c1" ]; then
        printf '%s\n' "$c1"
      elif [ -f "$c2" ]; then
        printf '%s\n' "$c2"
      else
        printf 'ALL\n'
      fi
      ;;
    *) printf 'ALL\n' ;;
  esac
  return 0
}

# _rb_run_narrowed <check> <note> <cmd...> — run a narrowed test check: the
# full set for ALL or an unnarrowable runner, a reasoned full run when the
# selection is empty or names a file that does not exist (ADR-0041: a
# narrowing that selects nothing is not a pass), else the selected files
# appended to <cmd...>.
_rb_run_narrowed() {
  local check="$1" note="$2" filters missing n
  shift 2
  if ! jp_scoped; then
    jp_run "$check" "$note" "$@"
    return 0
  fi
  filters=$(jp_decide _rb_builtin_test)
  if [ -z "$filters" ]; then
    jp_skip "$check" "scope: no changed file maps to a test"
  elif [ "$filters" = ALL ]; then
    jp_run "$check" "$note, scope: not narrowable, ran full set" "$@"
  else
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    if missing=$(jp_first_missing $filters); then
      set +f
      IFS=$' \t\n'
      jp_run "$check" "$note, scope: filter '$missing' selects no tests, ran full set" "$@"
    else
      n=$(printf '%s\n' "$filters" | grep -c .)
      # shellcheck disable=SC2086
      set -- "$@" $filters
      set +f
      IFS=$' \t\n'
      jp_run "$check" "$note, scope: $n test files" "$@"
    fi
  fi
  return 0
}

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  case "$RB_TEST" in
    rspec)
      filters=$(jp_decide _rb_builtin_test)
      ;;
    minitest)
      if _rb_minitest_via_rake && ! _rb_minitest_via_rails; then
        jp_plan minitest full "rake test cannot narrow by file"
        exit 0
      fi
      filters=$(jp_decide _rb_builtin_test)
      ;;
    *)
      jp_plan test skip "no rspec or minitest runner found"
      exit 0
      ;;
  esac
  if [ -n "$filters" ] && [ "$filters" != ALL ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ ! -e "$f" ]; then filters=ALL; break; fi
    done <<EOF
$filters
EOF
  fi
  jp_plan_selection "$RB_TEST" "$filters" "test files"
  exit 0
fi

case "$RB_TEST" in
  rspec)
    v=$(jp_version bundle exec rspec --version)
    _rb_run_narrowed rspec "$v" bundle exec rspec
    ;;
  minitest)
    if _rb_minitest_via_rails; then
      v=$(jp_version bin/rails --version)
      _rb_run_narrowed minitest "$v" bin/rails test
    else
      # bundle exec rake test has no per-file interface to narrow: the task
      # always runs the whole suite it is given (design.md D4, ruby row).
      v=$(jp_version bundle exec rake --version)
      note="$v"
      if jp_scoped; then note="$v, scope: not narrowable, ran full set"; fi
      jp_run minitest "$note" bundle exec rake test
    fi
    ;;
  *)
    jp_skip test "no rspec or minitest runner found: no rspec-core/rspec in Gemfile.lock, no bin/rails, no Rakefile with a test/ directory"
    ;;
esac

jp_end
