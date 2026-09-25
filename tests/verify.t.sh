# Tests for `jig verify` (ARCHITECTURE.md, Scripts layout; domains/verify).
# shellcheck shell=bash

# run_no_tools <cmd...> — like `run`, but with PATH stripped down to the
# base system directories, so a profile's verify.sh takes its "nothing
# found" skip path deterministically regardless of what happens to be
# installed (composer/go/npm/php/shellcheck) on the machine running the
# tests. git and bash themselves live under /usr/bin and /bin, so the
# dispatcher and every verify.sh shebang still resolve.
# The tools jig and its profiles actually invoke. Anything not on this list
# is invisible to a command run through run_no_tools, which is the point.
_NO_TOOLS_LIST="bash sh git sed awk grep find mktemp cat cp mv rm mkdir sort
tr head tail wc chmod ls date dirname basename cmp paste stat readlink diff env"

# A directory of wrapper scripts for exactly those tools, built once per
# runner invocation under $JIG_TEST_CACHE so the runner's own EXIT trap
# removes it. Reuse is decided by the directory being on disk, not by an
# exported variable: every test runs in its own forked subshell, so a
# variable set by one can never be seen by the next, and the first draft's
# env-var check could not fire even once.
#
# Wrapper scripts, not symlinks: on Windows Git Bash `ln -sf` copies instead
# of linking, which moves each tool binary (bash.exe, env.exe, ...) away
# from msys-2.0.dll in /usr/bin — nothing in the copy can start, so PATH="$bin"
# resolved to nothing and every "skips without toolchain" test hung on
# exit 127 instead of taking the skip path it meant to exercise. A tiny
# `#!/bin/sh; exec '<real path>' "$@"` wrapper has no such dependency: the OS
# reads its own shebang, not PATH, so `/bin/sh` resolves even here (and `sh`
# itself is on _NO_TOOLS_LIST for callers that need it directly).
#
# Published atomically, because tests run in parallel. It used to be filled
# in place and taken as ready once `git` was in it; `git` is third on the
# list, so a test running alongside the one building it could see `git`
# before `sed` and `awk` existed, and fail its `jig verify` with exit 1 —
# seen at 16 workers. Now it is built complete in a private directory and
# published by `mv "$build" "$dir"` — a plain rename, so unlike `ln -s` it
# never risks becoming a copy on Windows in the first place. Verified on
# macOS: when this is the first test to publish, `$dir` does not yet exist
# and the rename lands exactly there. When two tests race, the loser's `mv`
# does not error (a POSIX `mv` onto an existing, non-empty directory nests
# the source *inside* it instead of failing) — but that nested leftover sits
# under a random mktemp name that never collides with a real tool, so `$dir`
# itself still holds exactly the winner's complete, real set of wrapper
# scripts and every lookup through it resolves correctly. `rm -rf "$build"`
# below only fires if the rename itself errors (e.g. a permissions problem);
# it is not what protects against the race, so it is a courtesy, not the
# safety net the "if mv fails, discard the build" framing might suggest.
#
# Resolution goes through `env -i /bin/sh -c`, not a bare `command -v`,
# because the latter answers from the *developer's* shell: on a machine where
# grep is aliased to ugrep it returns the string `grep` rather than a path,
# which produced a self-referential symlink and a `grep: command not found`
# in the middle of a run. A helper built to remove environment dependence
# must not inherit any. PATH is the one thing passed in: the default search
# path of a bare `env -i` shell differs per platform, and under Git Bash it
# leaves out /mingw64/bin, where git lives — the no-tools directory then had
# no git at all and every run died with "not inside a git repository".
# Script-global, never `local`: the EXIT trap below runs after the function
# has returned, and a `local` would be out of scope by then — leaving the
# trap to `rm -rf ""` and the directory to leak, which is exactly what the
# first attempt at this cleanup did (conventions/shell.md).
_NO_TOOLS_TMP=""

_no_tools_bin() {
  local dir build
  if [ -n "${JIG_TEST_CACHE:-}" ]; then
    dir="$JIG_TEST_CACHE/no-tools-bin"
    if [ -d "$dir" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    build=$(mktemp -d "$JIG_TEST_CACHE/no-tools-bin.XXXXXX")
    _no_tools_fill "$build"
    mv "$build" "$dir" 2>/dev/null || rm -rf "$build"
    printf '%s\n' "$dir"
    return 0
  else
    # No runner cache to live in, and therefore no runner trap to clean up
    # after: this branch owns its directory and removes it itself.
    dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-no-tools.XXXXXX")
    _NO_TOOLS_TMP="$dir"
    trap 'rm -rf "$_NO_TOOLS_TMP"' EXIT INT TERM
  fi
  _no_tools_fill "$dir"
  printf '%s\n' "$dir"
}

# _no_tools_fill <dir> — a wrapper script in <dir> for each tool in
# _NO_TOOLS_LIST, each one `exec`ing the real tool's resolved absolute path.
# Not a symlink (see the comment above _no_tools_bin). The path is single-
# quoted with every embedded quote escaped, so a tool path containing a
# space or a single quote still execs correctly.
_no_tools_fill() {
  local t p esc
  for t in $_NO_TOOLS_LIST; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*)
        esc=$(printf '%s' "$p" | sed "s/'/'\\\\''/g")
        {
          printf '#!/bin/sh\n'
          printf "exec '%s' \"\$@\"\n" "$esc"
        } > "$1/$t"
        chmod +x "$1/$t"
        ;;
    esac
  done
  return 0
}

# Run a command with no development toolchain reachable at all.
#
# The previous form set PATH to the system directories and called that "no
# tools". That is only true where development tools live somewhere else: on
# macOS php and go come from /opt/homebrew/bin and fall away, while on a
# Linux CI runner they sit in /usr/bin and stayed perfectly visible — so
# every "skips without toolchain" test passed locally and failed in CI.
run_no_tools() {
  local bin out
  bin=$(_no_tools_bin)
  out=$(_run_out)
  set +e
  ( PATH="$bin" "$@" ) >"$out" 2>&1
  RC=$?
  set -e
  OUT=$(cat "$out")
  rm -f "$out"
  export OUT RC
}

# _fixture_probe_profile <name> <scope-line> — install a fixture profile at
# .ai/profiles/<name> whose verify.sh reports the JIG_VERIFY_SCOPE /
# JIG_VERIFY_FILES it observes (including the contents of the files list, so
# a test can assert on individual changed paths) and touches "<name>.ran" in
# the project root so a test can prove whether it ran at all. <scope-line>
# is a full profile.yaml line (e.g. "scope: [changed]") to declare scope
# support, or "" to omit the key entirely.
_fixture_probe_profile() {
  local name="$1" scope_line="$2"
  mkdir -p ".ai/profiles/$name"
  {
    printf 'name: %s\n' "$name"
    printf 'description: fixture profile reporting the scope env vars it receives.\n'
    printf 'detect: always\n'
    [ -z "$scope_line" ] || printf '%s\n' "$scope_line"
  } > ".ai/profiles/$name/profile.yaml"
  cat > ".ai/profiles/$name/verify.sh" <<EOF
#!/usr/bin/env bash
touch "$name.ran"
echo "$name: scope=\${JIG_VERIFY_SCOPE:-<unset>}"
if [ -n "\${JIG_VERIFY_FILES:-}" ] && [ -f "\${JIG_VERIFY_FILES:-}" ]; then
  echo "$name: files-set"
  cat "\$JIG_VERIFY_FILES"
else
  echo "$name: files-unset"
fi
if [ -n "\${JIG_VERIFY_MAPPED:-}" ] && [ -f "\${JIG_VERIFY_MAPPED:-}" ]; then
  echo "$name: mapped-set"
  cat "\$JIG_VERIFY_MAPPED"
else
  echo "$name: mapped-unset"
fi
exit 0
EOF
  chmod +x ".ai/profiles/$name/verify.sh"
}

# _map_check <map-file> — validate a project map exactly the way `jig verify`
# does, without an installed project: source the framework's own
# scripts/lib/verify.sh in a throwaway subshell and call `_verify_map_check`
# directly. Prints its `<line>: <reason>` output; returns its exit code.
_map_check() {
  bash -c '
    set -eu
    . "$JIG_HOME/scripts/lib/verify.sh"
    _verify_map_check "$1"
  ' _ "$1"
}

# _map_apply <map-file> <path...> — the `_verify_map_apply` decision for each
# path, sourcing the framework's own scripts/lib/verify.sh directly rather
# than going through `jig verify`, so the map protocol's own mechanics
# (precedence, `-`/ALL, `**`/`*`, no filesystem glob expansion, CRLF) are
# tested in isolation from the CLI and from any one profile.
_map_apply() {
  local map="$1" files
  shift
  files=$(_run_out .maplist)
  printf '%s\n' "$@" > "$files"
  bash -c '
    set -eu
    . "$JIG_HOME/scripts/lib/verify.sh"
    _verify_map_apply "$1" "$2"
  ' _ "$map" "$files"
  rm -f "$files"
}

# --- shell profile -----------------------------------------------------------

test_verify_shell_profile_passes_on_clean_scripts() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  # A linter the test supplies, not one the machine happens to have: without
  # this the shell profile skips the lint, reports `skip` rather than `pass`,
  # and this test fails on any runner where shellcheck is not installed.
  sc_stub 1.0.0 0

  run jig verify
  assert_eq 0 "$RC"
  # generic verifies nothing about the code on its own (profiles/generic/
  # verify.sh); shell is what makes this run a pass.
  assert_contains "$OUT" "RESULT generic: skip"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_contains "$OUT" "verify: 2 profiles, 1 pass, 0 fail, 1 skip"
}

test_verify_shell_profile_fails_on_bad_script() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\necho $1\n' > bad.sh
  chmod +x bad.sh
  # A linter that rejects what it is given. What is under test is the
  # profile's plumbing — a failing lint becomes `RESULT shell: fail` and a
  # non-zero verify — not shellcheck's own rules, which are shellcheck's to
  # keep and which jig's real `verify` exercises on its own source anyway.
  sc_stub 1.0.0 1

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "RESULT shell: fail"
  assert_contains "$OUT" "verify: 2 profiles, 0 pass, 1 fail, 1 skip"
}

# _shell_all_scripts takes its file list from git inside a work tree, so
# nested worktrees agent runtimes create (e.g. .claude/worktrees/<name>/)
# and anything gitignored are never linted, and a tracked or untracked
# (non-ignored) script always is.
test_verify_shell_all_scripts_uses_git_view_in_repo() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null

  printf '#!/usr/bin/env bash\necho tracked\n' > tracked.sh
  chmod +x tracked.sh
  git add tracked.sh
  git commit -q -m "add tracked script"

  printf '#!/usr/bin/env bash\necho untracked\n' > untracked.sh
  chmod +x untracked.sh

  printf 'ignored.sh\n' >> .gitignore
  printf '#!/usr/bin/env bash\necho ignored\n' > ignored.sh
  chmod +x ignored.sh

  # A nested worktree, the way an agent runtime creates one inside the
  # repository: git reports it as a single directory entry without
  # descending, so a script inside it never reaches the linter.
  git worktree add -q .nested/tree -b nested-wt >/dev/null
  printf '#!/usr/bin/env bash\necho nested\n' > .nested/tree/nested.sh
  chmod +x .nested/tree/nested.sh

  sc_stub_logging 1.0.0

  run jig verify
  assert_eq 0 "$RC"
  assert_file_contains sc-linted.log tracked.sh
  assert_file_contains sc-linted.log untracked.sh
  assert_not_contains "$(cat sc-linted.log)" "ignored.sh"
  assert_not_contains "$(cat sc-linted.log)" "nested.sh"
}

# git lists a tracked file from the index even after it was deleted from disk
# and the deletion not yet staged — the ordinary state after `rm` or a rename.
# Such a path must not reach the linter, which would fail on a missing file.
test_verify_shell_all_scripts_skips_a_deleted_tracked_script() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null

  printf '#!/usr/bin/env bash\necho gone\n' > gone.sh
  chmod +x gone.sh
  git add gone.sh
  git commit -q -m "add a script"
  rm gone.sh

  sc_stub_logging 1.0.0

  run jig verify
  assert_eq 0 "$RC"
  assert_not_contains "$(cat sc-linted.log 2>/dev/null)" "gone.sh"
}

# Outside a git work tree, _shell_all_scripts falls back to the find-based
# walk it always used. Run the profile script directly, in a plain
# directory with no .git, rather than through `jig verify` — jig itself
# locates the project root via `git rev-parse --show-toplevel`, so a `jig`
# command cannot run at all outside a repository.
test_verify_shell_all_scripts_find_fallback_outside_git_repo() {
  printf '#!/usr/bin/env bash\necho plain\n' > plain.sh
  chmod +x plain.sh
  sc_stub_logging 1.0.0

  bash "$JIG_HOME/profiles/shell/verify.sh" >out 2>&1
  rc=$?
  assert_eq 0 "$rc"
  assert_file_contains sc-linted.log plain.sh
}

# --- the "not installed (run jig upgrade)" hint stays actionable (domains/install) -
# Activating a profile in config.yaml after init used to leave the hint a
# dead end: copy mode's own decision table already installed the profile,
# but link mode's `jig upgrade` was a pure no-op. Covers both modes.
#
# Since the stale-install-check task, the framework-level pending gate
# (below) catches this case earlier than the per-profile "not installed"
# check ever runs: activating `shell` without upgrading first now fails as
# a framework staleness problem, not a per-profile one — a strictly earlier
# and more actionable diagnosis of the same root cause, so these two tests
# assert on the new message instead of the old per-profile one.

test_verify_hint_resolved_by_upgrade_copy_mode() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  sc_stub 1.0.0 0
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "install .ai/profiles/shell/profile.yaml"
  assert_contains "$OUT" "install .ai/profiles/shell/verify.sh"
  assert_contains "$OUT" "FAIL framework: 2 framework files not installed (run jig upgrade)"
  assert_not_contains "$OUT" "RESULT"

  jig upgrade --from "$JIG_HOME" >/dev/null

  run jig verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_not_contains "$OUT" "not installed"
}

test_verify_hint_resolved_by_upgrade_link_mode() {
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF
  # generic no longer passes on its own (profiles/generic/verify.sh), so the
  # final run below needs shell to actually pass; a stub keeps that
  # deterministic on a machine with no real shellcheck.
  sc_stub 1.0.0 0

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "link .ai/profiles/shell"
  assert_contains "$OUT" "FAIL framework: 1 framework file not installed (run jig upgrade)"
  assert_not_contains "$OUT" "RESULT"

  jig upgrade --from "$JIG_HOME" >/dev/null

  run jig verify --list --profile shell
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell: installed"

  run jig verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_not_contains "$OUT" "not installed"
}

# --- framework staleness gate runs no profile at all (stale-install-check) -
# A pass from a stale install is meaningless: prove no profile's verify.sh
# executes at all while framework files are pending, using a profile that
# *is* installed and would otherwise run cleanly (touching its own ".ran"
# marker) — its absence afterward is the evidence.

test_verify_fails_before_running_any_profile_when_framework_pending() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  sc_stub 1.0.0 0
  _fixture_probe_profile probe ""
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, probe, shell]
adapters: [claude, codex]
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "install .ai/profiles/shell/profile.yaml"
  assert_contains "$OUT" "install .ai/profiles/shell/verify.sh"
  assert_contains "$OUT" "FAIL framework: 2 framework files not installed (run jig upgrade)"
  assert_not_contains "$OUT" "RESULT"
  assert_not_contains "$OUT" "SKIP"
  assert_no_file probe.ran

  jig upgrade --from "$JIG_HOME" >/dev/null

  run jig verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT shell: pass"
  # generic verifies nothing about the code on its own and moved from the
  # pass column to the skip column (profiles/generic/verify.sh); probe and
  # shell still pass, so the run as a whole still does.
  assert_contains "$OUT" "verify: 3 profiles, 2 pass, 0 fail, 1 skip"
  assert_file probe.ran
}

# A copy-mode install whose source checkout no longer exists on this
# machine must not turn into a verify failure (domains/install): pending state is
# simply unknown, so verify falls back to running the profiles normally. It
# does run the (only) active profile — generic — rather than refusing, which
# is the thing under test here; generic itself has nothing stack-specific to
# check, so the run legitimately ends in "nothing was checked" (rc 3), not
# in the framework-staleness failure this test guards against.
test_verify_runs_profiles_when_source_root_unknown() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-del.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" --profiles generic >/dev/null
  rm -rf "$src"

  run jig_installed verify
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT generic: skip"
  assert_contains "$OUT" "verify: nothing was checked"
  assert_not_contains "$OUT" "FAIL framework"
}

# --- path traversal in profile names (profile-name-validation task) -------

test_verify_rejects_path_traversal_profile_names() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  local bad
  for bad in .. '../x' .hidden 'a b' ''; do
    run jig verify --profile "$bad"
    assert_eq 1 "$RC" "verify accepted profile [$bad]"
    assert_contains "$OUT" "invalid profile name"
  done
}

# Positive control for the reproduced bug: `jig verify --profile
# ../../../<dir>/evilprofile` used to run an arbitrary verify.sh outside the
# project. A rejected name must never reach the point of executing anything.
test_verify_profile_traversal_executes_nothing() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  local evil marker
  evil=$(mktemp -d "${TMPDIR:-/tmp}/jig-evil.XXXXXX")
  marker="$evil/ran"
  cat > "$evil/verify.sh" <<EOF
#!/usr/bin/env bash
touch "$marker"
EOF
  chmod +x "$evil/verify.sh"

  run jig verify --profile "../../../$(basename "$evil")"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
  assert_no_file "$marker"

  rm -rf "$evil"
}

# The same unvalidated name is reachable through .ai/config.yaml, without
# any CLI flag at all.
test_verify_config_profiles_reject_path_traversal() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [.., generic]
adapters: [claude, codex]
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
}

# --- profile-not-installed / no-verify.sh / --profile filter ---------------

test_verify_missing_profile_dir_fails_with_message() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --profile does-not-exist
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL does-not-exist: not installed (run jig upgrade)"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 1 fail, 0 skip"
}

test_verify_profile_without_verify_script_is_skipped() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/noverify

  run jig verify --profile noverify
  # Every profile skipped, so the run checked nothing and says so (M7).
  assert_eq 3 "$RC"
  assert_contains "$OUT" "SKIP noverify: no verify.sh"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
}

test_verify_profile_verify_script_exit_2_is_skip() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/fake
  cat > .ai/profiles/fake/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "fake: nothing to do: skip"
exit 2
EOF
  chmod +x .ai/profiles/fake/verify.sh

  run jig verify --profile fake
  # Exit 2 is still a skip, and a run of nothing but skips is not a pass (M7).
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT fake: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
}

# A profile checked out on Windows (or restored by any path that does not
# preserve unix file modes) has verify.sh at mode 644, no executable bit.
# `cmd_verify` runs it through `bash` rather than executing it directly, so
# the result must not depend on that bit (scripts/lib/verify.sh).
test_verify_profile_verify_script_runs_without_executable_bit() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/noexec
  cat > .ai/profiles/noexec/profile.yaml <<'EOF'
name: noexec
description: fixture profile with a non-executable verify.sh.
detect: always
EOF
  cat > .ai/profiles/noexec/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "noexec: ran"
exit 0
EOF
  chmod -x .ai/profiles/noexec/verify.sh
  if [ -x .ai/profiles/noexec/verify.sh ]; then
    skip "chmod cannot clear the executable bit here"
  fi

  run jig verify --profile noexec
  assert_eq 0 "$RC"
  assert_contains "$OUT" "noexec: ran"
  assert_contains "$OUT" "RESULT noexec: pass"
  assert_contains "$OUT" "verify: 1 profiles, 1 pass, 0 fail, 0 skip"
}

test_verify_profile_filter_accepts_comma_list() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  sc_stub 1.0.0 0

  run jig verify --profile generic,shell
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT generic: skip"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_contains "$OUT" "verify: 2 profiles"
}

test_verify_profile_filter_accepts_repeated_flag() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  sc_stub 1.0.0 0

  run jig verify --profile generic --profile shell
  assert_eq 0 "$RC"
  assert_contains "$OUT" "RESULT generic: skip"
  assert_contains "$OUT" "RESULT shell: pass"
  assert_contains "$OUT" "verify: 2 profiles"
}

test_verify_profile_without_value_dies() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --profile
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires a value"
}

test_verify_unknown_argument_dies() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument"
}

test_verify_requires_init() {
  fixture_repo
  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig init"
}

# --- --list --------------------------------------------------------------------

test_verify_list_reports_active_and_installed_state() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null

  run jig verify --list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic: installed"
  assert_contains "$OUT" "shell: installed"
}

test_verify_list_reports_not_installed_profile() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig verify --list --profile generic,ghost
  assert_eq 0 "$RC"
  assert_contains "$OUT" "generic: installed"
  assert_contains "$OUT" "ghost: not installed"
}

# --- php / go / node: skip paths (no toolchain in the fixture) -------------

# A single profile filtered to `php` with nothing on the toolchain checks
# every one of its own checks as skip; the run as a whole then checked
# nothing at all, so cmd_verify's own "nothing was checked" rule fires (rc
# 3, not 0) — this is not a framework-staleness or argument-error failure,
# it is the correct verdict for a project with no PHP toolchain present.
test_verify_php_skips_every_check_without_toolchain() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles php >/dev/null

  run_no_tools jig verify --profile php
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: skip"
  assert_contains "$OUT" "php: phpstan: skip"
  assert_contains "$OUT" "php: pint: skip"
  assert_contains "$OUT" "php: composer validate: skip"
  assert_contains "$OUT" "RESULT php: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
  assert_contains "$OUT" "verify: nothing was checked"
}

test_verify_php_passes_with_fake_phpunit_binary() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles php >/dev/null
  mkdir -p vendor/bin
  cat > vendor/bin/phpunit <<'EOF'
#!/usr/bin/env bash
echo "OK (0 tests)"
exit 0
EOF
  chmod +x vendor/bin/phpunit

  run_no_tools jig verify --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "php: phpunit: pass"
  assert_contains "$OUT" "RESULT php: pass"
  assert_contains "$OUT" "verify: 1 profiles, 1 pass, 0 fail, 0 skip"
}

test_verify_go_skips_without_toolchain() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles go >/dev/null

  run_no_tools jig verify --profile go
  # See the comment on test_verify_php_skips_every_check_without_toolchain:
  # every check skips, so the run checked nothing (rc 3), not a pass.
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: skip"
  assert_contains "$OUT" "go: test: skip"
  assert_contains "$OUT" "RESULT go: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
  assert_contains "$OUT" "verify: nothing was checked"
}

test_verify_node_skips_without_toolchain() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles node >/dev/null
  printf '{"scripts": {"test": "echo ok", "lint": "echo ok"}}\n' > package.json

  run_no_tools jig verify --profile node
  # See the comment on test_verify_php_skips_every_check_without_toolchain:
  # every check skips, so the run checked nothing (rc 3), not a pass.
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: skip"
  assert_contains "$OUT" "node: npm run lint: skip"
  assert_contains "$OUT" "RESULT node: skip"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 1 skip"
  assert_contains "$OUT" "verify: nothing was checked"
}

test_verify_node_skips_when_no_scripts_declared() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles node >/dev/null
  printf '{}\n' > package.json

  run jig verify --profile node
  # See the comment on test_verify_php_skips_every_check_without_toolchain:
  # every check skips, so the run checked nothing (rc 3), not a pass.
  assert_eq 3 "$RC"
  assert_contains "$OUT" "node: npm test: skip (no test script or npm not found)"
  assert_contains "$OUT" "node: npm run lint: skip (no lint script or npm not found)"
  assert_contains "$OUT" "RESULT node: skip"
}

# --- laravel: requires php, does not duplicate its checks -------------------

test_verify_laravel_skips_without_artisan_or_php() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null

  run_no_tools jig verify --profile laravel
  # See the comment on test_verify_php_skips_every_check_without_toolchain:
  # every check skips, so the run checked nothing (rc 3), not a pass.
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "laravel: artisan test: skip"
  assert_contains "$OUT" "RESULT laravel: skip"
}

test_verify_check_requires_warns_when_php_not_active() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null
  cat > .ai/config.yaml <<EOF
profiles: [laravel]
EOF

  run jig verify --profile laravel
  # laravel still skips every check without php active (as above), so the
  # run checked nothing (rc 3); what is under test here is only the warning
  # about the missing 'php' requirement, which prints regardless.
  assert_eq 3 "$RC"
  assert_contains "$OUT" "requires 'php', which is not active"
}

# --- scope protocol (--changed / --base) (ADR-0013) -------------------------

test_verify_changed_scope_ignored_for_profile_without_declaration() {
  fixture_jig_repo

  run jig verify --changed
  # generic is the only active profile here and does not declare scope
  # support, so --changed is ignored and it runs its ordinary way — which is
  # now a skip, not a pass, and the run as a whole checked nothing (rc 3).
  # The note text is what this test is really about: it is appended
  # regardless of the profile's own verdict.
  assert_eq 3 "$RC"
  assert_contains "$OUT" "generic: repository: skip (no stack-specific checks: this profile verifies nothing about the code)"
  assert_contains "$OUT" "RESULT generic: skip (scope ignored: profile declares no scope support, ran full set)"
}

test_verify_changed_scope_passed_to_supporting_profile() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"
  echo unstaged-change >> README.md

  run jig verify --changed --profile probe
  assert_eq 0 "$RC"
  assert_file probe.ran
  assert_contains "$OUT" "probe: scope=changed"
  assert_contains "$OUT" "probe: files-set"
  assert_contains "$OUT" "README.md"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 1 files)"
}

# The important one: `upgrade` keeps a user-modified verify.sh as-is, so a
# profile that never declared `scope` must never observe one — not even
# when the caller's own environment happens to export the same variable
# names `jig verify` uses internally.
test_verify_changed_scope_cleared_for_nonsupporting_profile_even_when_exported() {
  fixture_jig_repo
  _fixture_probe_profile probe2 ""
  git add -A
  git commit -q -m "add probe2 profile"
  echo unstaged-change >> README.md

  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES=/tmp/should-not-leak
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  run jig verify --changed --profile probe2
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES

  assert_eq 0 "$RC"
  assert_file probe2.ran
  assert_contains "$OUT" "probe2: scope=<unset>"
  assert_contains "$OUT" "probe2: files-unset"
  assert_contains "$OUT" "RESULT probe2: pass (scope ignored: profile declares no scope support, ran full set)"
}

test_verify_changed_empty_file_list_skips_supporting_profile_without_running() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"

  run jig verify --changed --profile probe
  # Every profile skipped, so the run checked nothing and says so (M7).
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT probe: skip (scope: changed, no changed files)"
  assert_not_contains "$OUT" "RESULT probe: pass"
  assert_no_file probe.ran
}

test_verify_changed_file_list_includes_staged_unstaged_and_untracked() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"

  echo staged-change >> staged.txt
  git add staged.txt
  echo unstaged-change >> README.md
  echo untracked-content > untracked.txt

  run jig verify --changed --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "probe: files-set"
  assert_contains "$OUT" "staged.txt"
  assert_contains "$OUT" "README.md"
  assert_contains "$OUT" "untracked.txt"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 3 files)"
}

test_verify_changed_base_flag_also_diffs_against_given_ref() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  git add -A
  git commit -q -m "add probe profile"
  local base
  base=$(git rev-parse HEAD)

  echo committed-after-base > committed-after-base.txt
  git add committed-after-base.txt
  git commit -q -m "second commit"
  echo unstaged-change >> README.md

  run jig verify --changed --base "$base" --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "committed-after-base.txt"
  assert_contains "$OUT" "README.md"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 2 files)"
}

test_verify_base_without_changed_dies() {
  fixture_jig_repo

  run jig verify --base HEAD
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: --base requires --changed"
}

test_verify_base_non_commit_ref_dies() {
  fixture_jig_repo

  run jig verify --changed --base not-a-real-ref
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: not a commit: not-a-real-ref"
}

test_verify_without_changed_flag_has_no_scope_text() {
  fixture_jig_repo

  run jig verify
  # generic is the only active profile here and it skips (verifies nothing
  # stack-specific), so the run checked nothing (rc 3) — orthogonal to what
  # this test actually guards: that no "scope" text leaks in without
  # --changed.
  assert_eq 3 "$RC"
  assert_not_contains "$OUT" "scope"
}

# --- reproducibility: the verdict names the linter that produced it ----------

# Put a fake `shellcheck` on PATH, the way hk_stub_gh does for the forge tier.
# Two reasons over asserting against the real binary: the tests then run on a
# machine that has no shellcheck at all — an early `return 0` would be logged
# `ok` by this harness, which has no skip, making the test a silent pass — and
# the asserted version is fixed instead of whatever the runner happens to ship.
#
# Usage: sc_stub <version> <lint-exit-code>
sc_stub() {
  mkdir -p stub-bin
  cat > stub-bin/shellcheck <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf 'ShellCheck - shell script analysis tool\n'
  printf 'version: $1\n'
  printf 'license: GNU General Public License, version 3\n'
  exit 0
fi
exit $2
STUB
  chmod +x stub-bin/shellcheck
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# Like sc_stub, but also records every path it is invoked with (skipping
# flags) to sc-linted.log, one per line, so a test can assert on exactly
# which files reached the linter rather than only on the overall verdict.
# Always reports version 1.0.0-shaped output and passes.
#
# Usage: sc_stub_logging <version>
sc_stub_logging() {
  mkdir -p stub-bin
  cat > stub-bin/shellcheck <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf 'ShellCheck - shell script analysis tool\n'
  printf 'version: $1\n'
  printf 'license: GNU General Public License, version 3\n'
  exit 0
fi
for a in "\$@"; do
  case "\$a" in
    -*) continue ;;
  esac
  printf '%s\n' "\$a" >> "$PWD/sc-linted.log"
done
exit 0
STUB
  chmod +x stub-bin/shellcheck
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

test_verify_shellcheck_verdict_names_its_version() {
  # A pass means different things under different shellcheck releases (SC2015
  # fires in 0.10.0, not in 0.11.0), so a verdict that does not say which
  # version produced it cannot be compared across machines.
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  sc_stub 1.2.3 0

  run jig verify
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell: shellcheck: pass (shellcheck 1.2.3)"
}

test_verify_shellcheck_failure_also_names_its_version() {
  # The failing verdict is the one people actually need to compare: "it fails
  # here and passes there" is unanswerable without the version.
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  sc_stub 4.5.6 1

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "shell: shellcheck: fail (shellcheck 4.5.6)"
}

test_verify_shellcheck_scoped_verdict_keeps_both_facts() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  printf '#!/usr/bin/env bash\necho ok\n' > extra.sh
  chmod +x extra.sh
  sc_stub 7.8.9 0

  run jig verify --changed
  assert_contains "$OUT" "shell: shellcheck: pass (shellcheck 7.8.9"
  assert_contains "$OUT" "scope: "
}

test_verify_survives_a_shellcheck_that_cannot_report_its_version() {
  # A version probe annotates a verdict; it must never be able to fail the
  # thing it annotates. Under `set -e` with `pipefail` an unguarded
  # `x=$(cmd | ...)` would abort the profile here and print nothing at all —
  # for the shellcheck check AND for the tests that run after it.
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  mkdir -p stub-bin
  printf '#!/usr/bin/env bash\nexit 1\n' > stub-bin/shellcheck
  chmod +x stub-bin/shellcheck
  PATH="$PWD/stub-bin:$PATH"
  export PATH

  run jig verify
  # The lint itself fails (the stub fails everything), but the profile must
  # still report both of its checks rather than dying silently.
  assert_contains "$OUT" "shell: shellcheck: fail (shellcheck unknown)"
  assert_contains "$OUT" "shell: tests/run.sh:"
}

# --- CI-backed projects: verify.full_run (ADR-0041) -------------------------
# `verify.full_run: ci` in .ai/config.yaml is the project's claim that CI runs
# the full set; a flag-less `jig verify` then narrows to what changed since
# the merge base with git.base_branch, unless CI is set or --full is given.

test_verify_full_run_local_explicit_has_no_scope_text() {
  fixture_jig_repo
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: local
EOF

  run jig verify
  # generic is the only active profile and it skips, so the run checked
  # nothing (rc 3) — orthogonal to what this test guards: no scope text.
  assert_eq 3 "$RC"
  assert_not_contains "$OUT" "scope"
  assert_not_contains "$OUT" "verify: full run"
}

test_verify_full_flag_in_local_mode_runs_with_no_header() {
  fixture_jig_repo

  run jig verify --full
  # generic is the only active profile and it skips, so the run checked
  # nothing (rc 3) — orthogonal to what this test guards: no scope/header
  # text with --full in local mode.
  assert_eq 3 "$RC"
  assert_contains "$OUT" "generic: repository: skip (no stack-specific checks: this profile verifies nothing about the code)"
  assert_not_contains "$OUT" "scope"
  assert_not_contains "$OUT" "verify: full run"
}

test_verify_ci_mode_scopes_files_committed_on_branch_and_unstaged() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF
  git add -A
  git commit -q -m "add probe profile, enable ci mode"

  git checkout -q -b work
  echo committed-on-branch > branch-file.txt
  git add branch-file.txt
  git commit -q -m "branch work"
  echo unstaged-change >> README.md

  unset CI
  run jig verify --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "probe: scope=changed"
  assert_contains "$OUT" "probe: files-set"
  assert_contains "$OUT" "branch-file.txt"
  assert_contains "$OUT" "README.md"
}

test_verify_ci_mode_no_merge_base_scopes_working_tree_only() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  # The template already sets git.base_branch (its first line always wins,
  # config.sh's _cfg_read), so it is replaced rather than shadowed by a
  # second, later line for the same key.
  sed 's/^git\.base_branch:.*/git.base_branch: nosuch/' .ai/config.yaml \
    > .ai/config.yaml.new && mv .ai/config.yaml.new .ai/config.yaml
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF
  git add -A
  git commit -q -m "add probe profile"
  echo unstaged-change >> README.md

  unset CI
  run jig verify --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "verify: scope changed in the working tree only, no merge base with nosuch (verify.full_run: ci, full set runs in CI)"
  assert_contains "$OUT" "probe: files-set"
  assert_contains "$OUT" "README.md"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 1 files)"
}

test_verify_ci_mode_header_names_local_only_base_branch() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF
  git add -A
  git commit -q -m "add probe profile"
  local expect_sha
  expect_sha=$(git rev-parse --short HEAD)

  git checkout -q -b work
  echo change > work.txt
  git add work.txt
  git commit -q -m "work"

  unset CI
  run jig verify --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "verify: scope changed since main@$expect_sha (verify.full_run: ci, full set runs in CI)"
}

test_verify_ci_mode_with_ci_env_set_runs_full_and_clears_scope() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF
  git add -A
  git commit -q -m "add probe profile"

  CI=true
  export CI
  run jig verify --profile probe
  unset CI

  assert_eq 0 "$RC"
  assert_contains "$OUT" "verify: full run (CI is set)"
  assert_contains "$OUT" "probe: scope=<unset>"
  assert_contains "$OUT" "probe: files-unset"
}

test_verify_ci_mode_with_ci_env_and_explicit_changed_still_scopes() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF
  git add -A
  git commit -q -m "add probe profile"
  echo unstaged-change >> README.md

  CI=true
  export CI
  run jig verify --changed --profile probe
  unset CI

  assert_eq 0 "$RC"
  assert_contains "$OUT" "probe: scope=changed"
  assert_not_contains "$OUT" "verify: full run"
}

test_verify_ci_mode_base_flag_without_changed_is_accepted_and_scoped() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF
  git add -A
  git commit -q -m "add probe profile"
  local base
  base=$(git rev-parse HEAD)
  echo committed-after-base > after-base.txt
  git add after-base.txt
  git commit -q -m "second commit"

  unset CI
  run jig verify --base "$base" --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "verify: scope changed since $base (--base)"
  assert_contains "$OUT" "probe: scope=changed"
  assert_contains "$OUT" "after-base.txt"
}

test_verify_ci_mode_full_flag_runs_unscoped() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF
  git add -A
  git commit -q -m "add probe profile"

  unset CI
  run jig verify --full --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "verify: full run (--full)"
  assert_contains "$OUT" "probe: scope=<unset>"
}

test_verify_full_with_changed_dies() {
  fixture_jig_repo
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF

  run jig verify --full --changed
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: --full cannot be combined with --changed or --base"
}

test_verify_full_with_base_dies() {
  fixture_jig_repo
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: ci
EOF

  run jig verify --full --base HEAD
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: --full cannot be combined with --changed or --base"
}

test_verify_invalid_full_run_value_dies() {
  fixture_jig_repo
  cat >> .ai/config.yaml <<'EOF'
verify.full_run: sometimes
EOF

  run jig verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: invalid verify.full_run: sometimes (expected local or ci)"
}

# verify.full_run is not in JIG_CFG_LOCAL_KEYS (config.sh, ADR-0038): a value
# set only in .ai/config.local.yaml must never narrow or widen a run, and
# `jig status` must name it as ignored (see also tests/status.t.sh).
test_verify_full_run_in_local_config_is_not_honoured() {
  fixture_jig_repo
  cat > .ai/config.local.yaml <<'EOF'
verify.full_run: ci
EOF

  unset CI
  run jig verify
  # generic is the only active profile and it skips, so the run checked
  # nothing (rc 3) — orthogonal to what this test guards: that a
  # config.local.yaml value never narrows or widens the run.
  assert_eq 3 "$RC"
  assert_not_contains "$OUT" "verify: scope"
  assert_not_contains "$OUT" "verify: full run"
}

# --- project map: JIG_VERIFY_MAPPED protocol (ADR-0041) --------------------
# `.ai/verify/<profile>.map` is parsed once by `jig verify` itself and handed
# to a profile declaring `scope: [changed, map]` as JIG_VERIFY_MAPPED; a
# profile that only declares `scope: [changed]` must never see it, even when
# a map file happens to exist on disk.

test_verify_map_scope_reports_mapped_file_to_profile() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed, map]"
  mkdir -p .ai/verify
  printf 'README.md fixture-filter::\n' > .ai/verify/probe.map
  git add -A
  git commit -q -m "add probe profile with a map"
  echo unstaged-change >> README.md

  run jig verify --changed --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "probe: mapped-set"
  assert_contains "$OUT" "$(printf 'README.md\tfixture-filter::')"
  assert_contains "$OUT" "RESULT probe: pass (scope: changed, 1 files, map .ai/verify/probe.map)"
}

test_verify_scope_changed_only_never_gets_mapped_even_when_exported() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed]"
  mkdir -p .ai/verify
  printf 'README.md fixture-filter::\n' > .ai/verify/probe.map
  git add -A
  git commit -q -m "add probe profile (scope: changed only) with a map on disk"
  echo unstaged-change >> README.md

  JIG_VERIFY_MAPPED=/tmp/should-not-leak
  export JIG_VERIFY_MAPPED
  run jig verify --changed --profile probe
  unset JIG_VERIFY_MAPPED

  assert_eq 0 "$RC"
  assert_contains "$OUT" "probe: mapped-unset"
  assert_not_contains "$OUT" "map .ai/verify/probe.map"
}

test_verify_map_scope_without_map_file_is_unset() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed, map]"
  git add -A
  git commit -q -m "add probe profile with map scope, no map file present"
  echo unstaged-change >> README.md

  run jig verify --changed --profile probe
  assert_eq 0 "$RC"
  assert_contains "$OUT" "probe: mapped-unset"
  assert_not_contains "$OUT" "map .ai/verify/probe.map"
}

# An empty changed-file list is decided before the map is ever read: the
# "no changed files" skip (cmd_verify) comes first, so a broken map sitting
# on disk must never turn a skip into a fail.
test_verify_map_scope_empty_changed_file_list_skips_before_reading_the_map() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed, map]"
  mkdir -p .ai/verify
  # Deliberately broken (no decision for the glob): if the skip-before-map
  # ordering ever regressed, this would surface as a `fail`, not a `skip`.
  printf 'README.md\n' > .ai/verify/probe.map
  git add -A
  git commit -q -m "add probe profile with a broken map, nothing left uncommitted"

  run jig verify --changed --profile probe
  # Every profile skipped, so the run checked nothing and says so (M7).
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT probe: skip (scope: changed, no changed files)"
  assert_not_contains "$OUT" "RESULT probe: fail"
  assert_no_file probe.ran
}

# A broken map fails the one profile that reads it, without running its
# verify.sh at all — a line silently skipped would narrow the wrong way —
# while other, unrelated profiles still run.
test_verify_map_line_with_no_decision_fails_the_profile_without_running_it() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed, map]"
  _fixture_probe_profile other "scope: [changed]"
  mkdir -p .ai/verify
  printf 'README.md\n' > .ai/verify/probe.map
  git add -A
  git commit -q -m "add probe profiles with a broken map (no decision)"
  echo unstaged-change >> README.md

  run jig verify --changed --profile probe,other
  assert_eq 1 "$RC"
  assert_contains "$OUT" "RESULT probe: fail (map .ai/verify/probe.map:1: no decision for README.md)"
  assert_no_file probe.ran
  assert_file other.ran
  assert_contains "$OUT" "RESULT other: pass"
}

test_verify_map_dash_mixed_with_filters_fails_the_profile() {
  fixture_jig_repo
  _fixture_probe_profile probe "scope: [changed, map]"
  mkdir -p .ai/verify
  printf 'README.md - some::\n' > .ai/verify/probe.map
  git add -A
  git commit -q -m "add probe profile with a broken map (- mixed with filters)"
  echo unstaged-change >> README.md

  run jig verify --changed --profile probe
  assert_eq 1 "$RC"
  assert_contains "$OUT" \
    "RESULT probe: fail (map .ai/verify/probe.map:1: '-' and 'ALL' stand alone: - some::)"
  assert_no_file probe.ran
}

# --- map protocol mechanics (_verify_map_check / _verify_map_apply) --------
# Exercised directly against the framework's own functions, without an
# installed project or a call to `jig verify`, so the map's own precedence
# and glob rules are pinned down in isolation (ADR-0041; schemas/verify-map.md).

test_verify_map_apply_first_matching_line_wins() {
  local map out
  map=$(_run_out .map)
  cat > "$map" <<'EOF'
foo.sh first::
*.sh second::
EOF
  out=$(_map_apply "$map" "foo.sh")
  assert_eq "$(printf 'foo.sh\tfirst::')" "$out"
  rm -f "$map"
}

test_verify_map_apply_dash_means_no_test() {
  local map out
  map=$(_run_out .map)
  printf 'docs/** -\n' > "$map"
  out=$(_map_apply "$map" "docs/readme.md")
  assert_eq "$(printf 'docs/readme.md\t-')" "$out"
  rm -f "$map"
}

test_verify_map_apply_all_means_everything() {
  local map out
  map=$(_run_out .map)
  printf 'tests/run.sh ALL\n' > "$map"
  out=$(_map_apply "$map" "tests/run.sh")
  assert_eq "$(printf 'tests/run.sh\tALL')" "$out"
  rm -f "$map"
}

test_verify_map_apply_multiple_filters() {
  local map out
  map=$(_run_out .map)
  printf 'adapters/** adapters:: verify::\n' > "$map"
  out=$(_map_apply "$map" "adapters/claude/adapter.sh")
  assert_eq "$(printf 'adapters/claude/adapter.sh\tadapters:: verify::')" "$out"
  rm -f "$map"
}

test_verify_map_apply_unmatched_path_gets_question_mark() {
  local map out
  map=$(_run_out .map)
  printf 'docs/** -\n' > "$map"
  out=$(_map_apply "$map" "scripts/lib/task.sh")
  assert_eq "$(printf 'scripts/lib/task.sh\t?')" "$out"
  rm -f "$map"
}

test_verify_map_apply_double_star_and_star_match_across_slash() {
  local map out
  map=$(_run_out .map)
  cat > "$map" <<'EOF'
adapters/** wide::
scripts/*.sh single::
EOF
  out=$(_map_apply "$map" "adapters/claude/deep/nested.sh" "scripts/jig.sh")
  assert_contains "$out" "$(printf 'adapters/claude/deep/nested.sh\twide::')"
  assert_contains "$out" "$(printf 'scripts/jig.sh\tsingle::')"
  rm -f "$map"
}

# Files sitting in the working directory that happen to match the map's own
# glob token would, without `set -f` around the word-split, turn that token
# into their names instead of leaving it as a literal pattern.
test_verify_map_check_and_apply_do_not_expand_glob_against_filesystem() {
  printf 'x\n' > a.txt
  printf 'y\n' > b.txt
  local map out
  map=$(_run_out .map)
  printf '*.txt matched::\n' > "$map"

  assert_exit 0 _map_check "$map"

  out=$(_map_apply "$map" "sample.txt")
  assert_eq "$(printf 'sample.txt\tmatched::')" "$out"
  rm -f "$map" a.txt b.txt
}

# A map saved on Windows ends its lines in CRLF; both functions must strip
# the CR before splitting or matching, so neither the validation nor the
# decision it produces ever carries one.
test_verify_map_check_and_apply_strip_crlf_line_endings() {
  local map out
  map=$(_run_out .map)
  printf 'a/** x::\r\n' > "$map"

  assert_exit 0 _map_check "$map"

  out=$(_map_apply "$map" "a/b.sh")
  assert_eq "$(printf 'a/b.sh\tx::')" "$out"
  rm -f "$map"
}

# --- own map: this repository's .ai/verify/shell.map (ADR-0041) ------------

test_verify_own_shell_map_is_valid() {
  assert_exit 0 _map_check "$JIG_HOME/.ai/verify/shell.map"
}

test_verify_own_shell_map_decides_known_paths() {
  local out
  out=$(_map_apply "$JIG_HOME/.ai/verify/shell.map" \
    "scripts/jig-session-hook" \
    "adapters/claude/adapter.sh" \
    "profiles/shell/verify.sh" \
    "scripts/jig" \
    "templates/gitignore" \
    "skills/jig-review/SKILL.md" \
    "tests/routing/jig-review.cases" \
    "templates/AGENTS.md" \
    "AGENTS.md" \
    "docs/install.mdx" \
    "docs/concepts.mdx" \
    ".ai/manifest" \
    "scripts/lib/task.sh")
  assert_contains "$out" "$(printf 'scripts/jig-session-hook\thousekeeping::')"
  assert_contains "$out" "$(printf 'adapters/claude/adapter.sh\tadapters::')"
  assert_contains "$out" "$(printf 'profiles/shell/verify.sh\tprofiles:: verify::')"
  assert_contains "$out" "$(printf 'scripts/jig\tdispatcher::')"
  assert_contains "$out" "$(printf 'templates/gitignore\tinit:: upgrade::')"
  assert_contains "$out" "$(printf 'skills/jig-review/SKILL.md\trouting::')"
  assert_contains "$out" "$(printf 'tests/routing/jig-review.cases\trouting::')"
  # One template is read by a suite the general templates/** line does not
  # name, and the specific line above it must win.
  assert_contains "$out" "$(printf 'templates/AGENTS.md\tinit:: upgrade:: adapters::')"
  # Prose, and the one page that is not prose. Both halves are asserted
  # together on purpose (conventions/detectors.md): a map that reports nothing
  # passes this test as easily as a correct one, so the line it must report
  # sits beside the lines it must stay silent about.
  assert_contains "$out" "$(printf 'docs/install.mdx\tadapters::test_docs_agents_section_matches_the_template')"
  assert_contains "$out" "$(printf 'docs/concepts.mdx\t-')"
  assert_contains "$out" "$(printf 'AGENTS.md\t-')"
  assert_contains "$out" "$(printf '.ai/manifest\t-')"
  assert_contains "$out" "$(printf 'scripts/lib/task.sh\t?')"
}

# --- shell profile: map-driven and unmatched-filter narrowing --------------

# A tiny project with its own executable tests/run.sh stub, so a test can
# assert exactly which filter(s) the shell profile narrowed to without
# invoking this repository's own (heavy) test runner recursively. Logs each
# invocation's arguments to run-log, one call per line; "(full)" for a call
# with none.
_fixture_shell_scope_project() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  mkdir -p tests
  cat > tests/run.sh <<'EOF'
#!/usr/bin/env bash
if [ $# -eq 0 ]; then
  echo "(full)" >> run-log
else
  printf '%s\n' "$@" >> run-log
fi
exit 0
EOF
  chmod +x tests/run.sh
}

test_verify_shell_profile_map_dash_skips_the_narrowed_run() {
  _fixture_shell_scope_project
  mkdir -p .ai/verify
  printf 'skip.sh -\n' > .ai/verify/shell.map
  printf '#!/usr/bin/env bash\necho hi\n' > skip.sh
  chmod +x skip.sh
  # The stub lands in $PWD (tests/lib/assert.sh): committed with everything
  # else so it is not itself a "changed" file the profile has to narrow on.
  sc_stub 1.0.0 0
  git add -A
  git commit -q -m "baseline"
  printf '#!/usr/bin/env bash\necho hi2\n' > skip.sh

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell: tests/run.sh: skip (scope: no changed file maps to a test)"
  assert_no_file run-log
}

test_verify_shell_profile_map_question_mark_falls_back_to_builtin_rule() {
  _fixture_shell_scope_project
  mkdir -p .ai/verify
  printf 'irrelevant/** -\n' > .ai/verify/shell.map
  printf '#!/usr/bin/env bash\necho hi\n' > foo.sh
  chmod +x foo.sh
  printf 'test_something() { :; }\n' > tests/foo.t.sh
  sc_stub 1.0.0 0
  git add -A
  git commit -q -m "baseline"
  printf '#!/usr/bin/env bash\necho hi2\n' > foo.sh

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell: tests/run.sh: pass (scope: 1 filters)"
  assert_file_contains run-log "foo::"
}

test_verify_shell_profile_full_run_when_filter_selects_no_tests() {
  _fixture_shell_scope_project
  printf '# placeholder, no test functions in this file\n' > tests/foo.t.sh
  sc_stub 1.0.0 0
  git add -A
  git commit -q -m "baseline"
  printf '# still no test functions\n' >> tests/foo.t.sh

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "shell: tests/run.sh: pass (scope: filter 'foo::' selects no tests, ran full set)"
  assert_file_contains run-log "(full)"
}

test_verify_shell_profile_full_run_when_script_has_no_matching_test_file() {
  _fixture_shell_scope_project
  printf '#!/usr/bin/env bash\necho hi\n' > lonely.sh
  chmod +x lonely.sh
  sc_stub 1.0.0 0
  git add -A
  git commit -q -m "baseline"
  printf '#!/usr/bin/env bash\necho hi2\n' > lonely.sh

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell: tests/run.sh: pass (scope: not narrowable, ran full set)"
  assert_file_contains run-log "(full)"
}

# _shell_test_names also recognises `function test_x` with the brace on its
# own line (not only `test_x()` or `function test_x() {` on one line): the
# function name is captured off the `function test_x` line itself, so where
# the brace lands does not matter.
test_verify_shell_profile_recognises_function_test_without_parens_across_lines() {
  _fixture_shell_scope_project
  mkdir -p .ai/verify
  printf 'trigger.sh foo::test_bar\n' > .ai/verify/shell.map
  cat > tests/foo.t.sh <<'EOF'
function test_bar
{
  :
}
EOF
  printf '#!/usr/bin/env bash\necho hi\n' > trigger.sh
  chmod +x trigger.sh
  sc_stub 1.0.0 0
  git add -A
  git commit -q -m "baseline"
  printf '#!/usr/bin/env bash\necho hi2\n' > trigger.sh

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "shell: tests/run.sh: pass (scope: 1 filters)"
  assert_not_contains "$OUT" "selects no tests"
  assert_file_contains run-log "foo::test_bar"
}

# A map decision is a hand-edited string, so `_shell_test_filters` must
# word-split it under `set -f`: without that, an unquoted `for tok in
# $decision` also pathname-expands the token against files sitting in the
# project root, turning a literal `a*` filter into the names of files that
# happen to match it.
test_verify_shell_profile_map_decision_glob_token_is_not_expanded_against_files() {
  _fixture_shell_scope_project
  : > a1
  : > a2
  mkdir -p .ai/verify
  printf 'trigger.sh a*\n' > .ai/verify/shell.map
  printf '#!/usr/bin/env bash\necho hi\n' > trigger.sh
  chmod +x trigger.sh
  sc_stub 1.0.0 0
  git add -A
  git commit -q -m "baseline"
  printf '#!/usr/bin/env bash\necho hi2\n' > trigger.sh

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "shell: tests/run.sh: pass (scope: filter 'a*' selects no tests, ran full set)"
  assert_not_contains "$OUT" "filter 'a1'"
  assert_not_contains "$OUT" "filter 'a2'"
}

# --- shell profile: .shellcheckrc widens the lint to the whole tree --------

test_verify_shell_profile_widens_lint_to_whole_tree_when_shellcheckrc_changes() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles shell >/dev/null
  printf '#!/usr/bin/env bash\necho tracked\n' > tracked.sh
  chmod +x tracked.sh
  printf '# shellcheck config\n' > .shellcheckrc
  git add -A
  git commit -q -m "baseline with a tracked script and .shellcheckrc"

  printf '# widened\n' >> .shellcheckrc
  sc_stub_logging 1.0.0

  run jig verify --changed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "scope: .shellcheckrc changed, whole tree"
  assert_file_contains sc-linted.log tracked.sh
}

# --- a run that dies is not a pass (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass) ---
# A profile that started and did not finish is a third outcome, `incomplete`,
# never folded into `fail`: exit 3 is the profile itself saying so, and
# 128+N is the profile killed by a signal, which every stack profile reports
# through jp_run/jp_incomplete (scripts/lib/profile.sh) without being taught
# to.

test_verify_profile_exit_3_is_incomplete() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/dies
  cat > .ai/profiles/dies/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "dies: a check: incomplete (simulated)"
exit 3
EOF
  chmod +x .ai/profiles/dies/verify.sh

  run jig verify --profile dies
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT dies: incomplete"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 0 skip, 1 incomplete"
  assert_contains "$OUT" \
    "verify: the run did not finish, so it neither passed nor failed — run it again"
}

test_verify_profile_killed_by_signal_is_incomplete() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/killed
  cat > .ai/profiles/killed/verify.sh <<'EOF'
#!/usr/bin/env bash
kill -9 $$
EOF
  chmod +x .ai/profiles/killed/verify.sh

  run jig verify --profile killed
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT killed: incomplete (killed by signal 9)"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 0 skip, 1 incomplete"
}

test_verify_incomplete_outranks_fail() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/failing .ai/profiles/dies
  cat > .ai/profiles/failing/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "failing: a check: fail"
exit 1
EOF
  chmod +x .ai/profiles/failing/verify.sh
  cat > .ai/profiles/dies/verify.sh <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
  chmod +x .ai/profiles/dies/verify.sh

  run jig verify --profile failing,dies
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT failing: fail"
  assert_contains "$OUT" "RESULT dies: incomplete"
  assert_contains "$OUT" "verify: 2 profiles, 0 pass, 1 fail, 0 skip, 1 incomplete"
}

# Guards the tally format itself: an ordinary passing run still names the
# incomplete field, at zero, and exits 0. generic itself has nothing to
# pass (profiles/generic/verify.sh), so a trivial always-passing profile
# stands in for "an ordinary passing run" here.
test_verify_ordinary_pass_tally_names_zero_incomplete() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/passes
  cat > .ai/profiles/passes/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "passes: a check: pass"
exit 0
EOF
  chmod +x .ai/profiles/passes/verify.sh

  run jig verify --profile passes
  assert_eq 0 "$RC"
  assert_contains "$OUT" "verify: 1 profiles, 1 pass, 0 fail, 0 skip, 0 incomplete"
}

# --- one run per clone (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass) ---
# `jig verify` takes a run record shared by every worktree of the clone
# (`.ai/runtime/verify/busy/run`) and waits while another run holds it. CI is
# unset and JIG_VERIFY_BUSY_HELD is unset for every test (tests/run.sh), so
# the mechanism runs for real here unless a test sets verify.busy_ttl: 0.

test_verify_writes_and_removes_the_busy_record() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/probe
  cat > .ai/profiles/probe/verify.sh <<'EOF'
#!/usr/bin/env bash
if [ -f .ai/runtime/verify/busy/run ]; then
  cp .ai/runtime/verify/busy/run seen-record.txt
fi
exit 0
EOF
  chmod +x .ai/profiles/probe/verify.sh

  run jig verify --profile probe
  assert_eq 0 "$RC"
  assert_file_contains seen-record.txt "checkout: $(pwd -P)"
  assert_file_contains seen-record.txt "pid: "
  assert_no_file .ai/runtime/verify/busy
}

# A worktree and its main checkout share one record: `jig_config_clone_root`
# resolves both to the same `.ai/runtime/verify` under the main checkout, so
# a run started in the worktree writes and reads it there, never under the
# worktree's own `.ai`.
test_verify_busy_record_resolves_to_main_checkout_from_worktree() {
  mkdir repo
  cd repo || fail "setup"
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  git add -A
  git commit -q -m "jig init snapshot"
  local main_root
  main_root=$(pwd -P)

  git worktree add -q ../wt -b wt-branch >/dev/null

  mkdir -p ../wt/.ai/profiles/probe
  cat > "../wt/.ai/profiles/probe/verify.sh" <<EOF
#!/usr/bin/env bash
if [ -f "$main_root/.ai/runtime/verify/busy/run" ]; then
  cp "$main_root/.ai/runtime/verify/busy/run" seen-record.txt
fi
exit 0
EOF
  chmod +x "../wt/.ai/profiles/probe/verify.sh"

  # The record names the checkout the run is in, not the one it lives in, and
  # that is the whole claim: a worktree writes into the clone's main checkout.
  # Compared against `pwd -P`, never a raw string (conventions/shell.md).
  local wt_root
  wt_root=$(cd "$main_root/../wt" && pwd -P)

  run bash -c 'cd ../wt && "$JIG_BIN" verify --profile probe'
  assert_eq 0 "$RC"
  assert_file_contains ../wt/seen-record.txt "checkout: $wt_root"
  assert_file_contains ../wt/seen-record.txt "pid: "
  assert_no_file ../wt/.ai/runtime/verify
  assert_no_file "$main_root/.ai/runtime/verify/busy"
}

# A record whose pid is alive makes a run wait; when the holder dies the
# waiter takes over and reports having waited. verify.busy_ttl is set small
# so the record expires on its own even if the kill below misfires — the
# test cannot hang.
test_verify_waits_for_a_live_record_then_proceeds_once_it_is_freed() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  # Long on purpose: the expiry must not be what frees the record, or the test
  # would pass for the wrong reason. Only the holder dying may free it.
  jig config set verify.busy_ttl 5m --local >/dev/null
  # generic itself has nothing to check (profiles/generic/verify.sh); what
  # this test needs is a profile that runs and passes, to show the run
  # proceeded normally once the record was freed.
  _fixture_probe_profile probe ""

  sleep 120 &
  local holder_pid=$!
  mkdir -p .ai/runtime/verify/busy
  printf 'checkout: /elsewhere\npid: %s\n' "$holder_pid" > .ai/runtime/verify/busy/run

  # The holder is killed only once the run has said, itself, that it is
  # waiting — never after a fixed pause. A pause races the run's own startup:
  # kill too early and the run takes the record over without waiting, which is
  # a green test for the wrong reason and a red one whenever the machine is
  # loaded. The deadline is wall-clock and sized for a loaded machine, and a
  # passing test leaves at the first poll that succeeds
  # (conventions/shell.md, testing).
  "$JIG_BIN" verify --profile probe > verify-out.log 2>&1 &
  local verify_pid=$!
  local start=$SECONDS
  until grep -q "waiting for it" verify-out.log 2>/dev/null; do
    if ! kill -0 "$verify_pid" 2>/dev/null; then
      kill "$holder_pid" 2>/dev/null || true
      fail "verify finished without ever saying it was waiting: $(cat verify-out.log)"
    fi
    if [ $((SECONDS - start)) -ge 60 ]; then
      kill "$holder_pid" 2>/dev/null || true
      kill "$verify_pid" 2>/dev/null || true
      fail "verify never said it was waiting within 60s: $(cat verify-out.log)"
    fi
    sleep 1
  done

  kill "$holder_pid" 2>/dev/null || true
  local rc=0
  wait "$verify_pid" || rc=$?

  assert_eq 0 "$rc"
  assert_file_contains verify-out.log "verify: waited"
  assert_file_contains verify-out.log "RESULT probe: pass"

  wait 2>/dev/null || true
}

# A dead pid (reaped before the record is even read) is taken over on the
# first poll: no wait is reported.
test_verify_takes_over_a_dead_pid_record_at_once() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  jig config set verify.busy_ttl 20s --local >/dev/null
  # See test_verify_waits_for_a_live_record_then_proceeds_once_it_is_freed:
  # generic cannot pass on its own, so a trivial passing profile stands in.
  _fixture_probe_profile probe ""

  local dead_pid
  ( exit 0 ) &
  dead_pid=$!
  wait "$dead_pid" 2>/dev/null || true

  mkdir -p .ai/runtime/verify/busy
  printf 'checkout: /elsewhere\npid: %s\n' "$dead_pid" > .ai/runtime/verify/busy/run

  run jig verify --profile probe
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "verify: waited"
  assert_contains "$OUT" "RESULT probe: pass"
}

# CI turns the whole mechanism off: a live record is neither waited for nor
# touched.
test_verify_ci_env_ignores_a_live_record_and_leaves_it_untouched() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  jig config set verify.busy_ttl 20s --local >/dev/null
  # See test_verify_waits_for_a_live_record_then_proceeds_once_it_is_freed:
  # generic cannot pass on its own, so a trivial passing profile stands in.
  _fixture_probe_profile probe ""

  sleep 30 &
  local holder_pid=$!
  mkdir -p .ai/runtime/verify/busy
  printf 'checkout: /elsewhere\npid: %s\n' "$holder_pid" > .ai/runtime/verify/busy/run

  run env CI=1 "$JIG_BIN" verify --profile probe
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "verify: waited"
  assert_contains "$OUT" "RESULT probe: pass"
  assert_file_contains .ai/runtime/verify/busy/run "checkout: /elsewhere"
  assert_file_contains .ai/runtime/verify/busy/run "pid: $holder_pid"

  kill "$holder_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}

# verify.busy_ttl: 0 is the escape hatch: a live record is ignored outright,
# nothing waits and nothing is written.
test_verify_busy_ttl_zero_disables_the_mechanism() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  jig config set verify.busy_ttl 0 --local >/dev/null
  # See test_verify_waits_for_a_live_record_then_proceeds_once_it_is_freed:
  # generic cannot pass on its own, so a trivial passing profile stands in.
  _fixture_probe_profile probe ""

  sleep 30 &
  local holder_pid=$!
  mkdir -p .ai/runtime/verify/busy
  printf 'checkout: /elsewhere\npid: %s\n' "$holder_pid" > .ai/runtime/verify/busy/run

  run jig verify --profile probe
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "verify: waited"
  assert_contains "$OUT" "RESULT probe: pass"
  assert_file_contains .ai/runtime/verify/busy/run "checkout: /elsewhere"

  kill "$holder_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}

# Registering a key in JIG_CFG_LOCAL_KEYS is not one edit but three (see
# tests/checkout.t.sh's own checkout.busy_ttl test): the list, the value
# check in jig_config_value_problem, and schemas/config.md.
test_verify_busy_ttl_config_set_accepts_duration_and_rejects_garbage() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig config set verify.busy_ttl 5m --local
  assert_eq 0 "$RC"

  run jig config show --local
  assert_eq 0 "$RC"
  assert_contains "$OUT" "verify.busy_ttl: 5m"
  assert_not_contains "$OUT" "ignored: verify.busy_ttl"

  run jig config set verify.busy_ttl nonsense --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a duration"
}

# --- the jp_* interface exception (adr-20260918 amendment 2026-09-25) --------
#
# The amendment claims two things about changing jp_run's verdict for a killed
# check. Both are claims about profiles nobody here wrote, so both are run, not
# argued.

# A profile written without scripts/lib/profile.sh — the shape every profile had
# before jp_* existed, where any non-zero from the check is a failure — is not
# reached by the library change at all.
test_verify_a_library_free_profile_reads_a_killed_check_as_before() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/oldstyle
  cat > .ai/profiles/oldstyle/verify.sh <<'EOF'
#!/usr/bin/env bash
set -u
# `sh -c` so the signal reaches a child of this shell: a bare `kill -9 $$` in a
# test names the runner, not the subshell under test.
if sh -c 'kill -9 $$'; then
  echo "oldstyle: check: pass"
  exit 0
else
  echo "oldstyle: check: fail"
  exit 1
fi
EOF
  chmod +x .ai/profiles/oldstyle/verify.sh

  run jig verify --profile oldstyle
  assert_eq 1 "$RC"
  assert_contains "$OUT" "oldstyle: check: fail"
  assert_contains "$OUT" "RESULT oldstyle: fail"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 1 fail, 0 skip, 0 incomplete"
}

# A profile that does use the library gets the third state — and its exit code
# stays non-zero, which is the whole safety argument: a consumer that only asks
# whether the code is zero reads `incomplete` exactly as it read a failure.
test_verify_jp_run_reports_a_killed_check_as_incomplete_and_still_nonzero() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/vialib
  cat > .ai/profiles/vialib/verify.sh <<'EOF'
#!/usr/bin/env bash
set -eu
set -o pipefail
. "$(dirname "$0")/../../scripts/lib/profile.sh"
jp_begin vialib
jp_run tests "" sh -c 'kill -9 $$'
jp_end
EOF
  chmod +x .ai/profiles/vialib/verify.sh

  run jig verify --profile vialib
  assert_eq 3 "$RC"
  [ "$RC" -ne 0 ] || fail "incomplete must stay non-zero for a zero-or-not consumer"
  assert_contains "$OUT" "vialib: tests: incomplete (killed by signal 9)"
  assert_contains "$OUT" "RESULT vialib: incomplete"
  assert_contains "$OUT" "verify: 1 profiles, 0 pass, 0 fail, 0 skip, 1 incomplete"
}

# --- a run that checked nothing is not a pass (M7) ---------------------------
#
# `cmd_verify` used to end in `[ "$failn" -eq 0 ]`, so a set of pure skips
# answered 0 — success on a project not one line of which had been examined,
# and `jig task ship` and the autopilot read that code. The rule is the
# domain's own ("a skip is not a pass"); these tests hold the exit code to it,
# and hold the new rule to its bounds so it cannot swallow a real answer.

test_verify_every_profile_skipping_is_not_a_pass() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  local p
  for p in quiet1 quiet2; do
    mkdir -p ".ai/profiles/$p"
    cat > ".ai/profiles/$p/verify.sh" <<EOF
#!/usr/bin/env bash
echo "$p: nothing applicable: skip"
exit 2
EOF
    chmod +x ".ai/profiles/$p/verify.sh"
  done

  run jig verify --profile quiet1,quiet2
  assert_eq 3 "$RC"
  assert_contains "$OUT" "verify: 2 profiles, 0 pass, 0 fail, 2 skip, 0 incomplete"
  assert_contains "$OUT" "verify: nothing was checked, so this is not a pass"
}

# The scenario the external review exhibited: the shell profile active, with
# no linter on PATH and no tests/run.sh, plus generic. Every check skips, and
# before this rule the run answered 0.
test_verify_shell_without_tools_and_generic_together_check_nothing() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic,shell >/dev/null
  assert_no_file tests/run.sh

  run_no_tools jig verify --profile generic,shell
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT generic: skip"
  assert_contains "$OUT" "RESULT shell: skip"
  assert_contains "$OUT" "verify: nothing was checked, so this is not a pass"
}

# The bound on the new rule: one real pass is enough, and a skip beside it is
# still just a skip.
test_verify_one_pass_beside_a_skip_is_still_a_pass() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/real .ai/profiles/quiet
  cat > .ai/profiles/real/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "real: a check: pass"
exit 0
EOF
  cat > .ai/profiles/quiet/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "quiet: nothing applicable: skip"
exit 2
EOF
  chmod +x .ai/profiles/real/verify.sh .ai/profiles/quiet/verify.sh

  run jig verify --profile real,quiet
  assert_eq 0 "$RC"
  assert_contains "$OUT" "verify: 2 profiles, 1 pass, 0 fail, 1 skip, 0 incomplete"
  assert_not_contains "$OUT" "nothing was checked"
}

# Incomplete still outranks it: a run something died in says so, not that it
# checked nothing, because the two need different things from the reader.
test_verify_incomplete_outranks_nothing_was_checked() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/quiet .ai/profiles/dies
  cat > .ai/profiles/quiet/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "quiet: nothing applicable: skip"
exit 2
EOF
  cat > .ai/profiles/dies/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "dies: a check: incomplete (simulated)"
exit 3
EOF
  chmod +x .ai/profiles/quiet/verify.sh .ai/profiles/dies/verify.sh

  run jig verify --profile quiet,dies
  assert_eq 3 "$RC"
  assert_contains "$OUT" "verify: the run did not finish"
  assert_not_contains "$OUT" "nothing was checked"
}

# And a real failure is still a failure, exit 1, whatever skipped beside it:
# the new rule must not swallow the one answer that was never in doubt.
test_verify_a_failure_beside_a_skip_still_exits_one() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  mkdir -p .ai/profiles/broken .ai/profiles/quiet
  cat > .ai/profiles/broken/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "broken: a check: fail"
exit 1
EOF
  cat > .ai/profiles/quiet/verify.sh <<'EOF'
#!/usr/bin/env bash
echo "quiet: nothing applicable: skip"
exit 2
EOF
  chmod +x .ai/profiles/broken/verify.sh .ai/profiles/quiet/verify.sh

  run jig verify --profile broken,quiet
  assert_eq 1 "$RC"
  assert_contains "$OUT" "verify: 2 profiles, 0 pass, 1 fail, 1 skip, 0 incomplete"
  assert_not_contains "$OUT" "nothing was checked"
}
