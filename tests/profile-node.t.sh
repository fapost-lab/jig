# Tests for the node profile (profiles/node/verify.sh, profiles/node/profile.yaml).
# Domains: verify, profiles. ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools.
# shellcheck shell=bash

# --- fixtures --------------------------------------------------------------

# run_no_tools <cmd...> — like tests/verify.t.sh's own helper of the same
# name (not in scope here: tests/run.sh sources one *.t.sh file at a time),
# minus its shared-cache optimisation, which this file's two callers do not
# need. Resolves each tool once through `env -i PATH="$PATH" /bin/sh -c
# "command -v ..."` (never a bare `command -v`, which answers from this
# shell and can return an alias) and wraps it in a small script rather than
# a symlink (Git Bash copies on `ln -s`, which strands a copied bash.exe
# away from msys-2.0.dll — conventions/shell.md).
_NODE_NO_TOOLS_LIST="bash sh git sed awk grep find mktemp cat cp mv rm mkdir sort tr head tail wc chmod ls date dirname basename cmp paste stat readlink diff env"

run_no_tools() {
  local dir t p out
  dir="$PWD/.no-tools-bin"
  mkdir -p "$dir"
  for t in $_NODE_NO_TOOLS_LIST; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*)
        {
          printf '#!/bin/sh\n'
          printf "exec '%s' \"\$@\"\n" "$p"
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
  export OUT RC
}

# _node_pkg <scripts-json> [deps-json] — write a minimal package.json with a
# "scripts" object and, when given, a "devDependencies" object (used to
# declare vitest/jest so _node_test_runner finds them).
_node_pkg() {
  local scripts="$1" deps="${2:-}"
  {
    printf '{\n'
    printf '  "scripts": %s' "$scripts"
    if [ -n "$deps" ]; then
      printf ',\n  "devDependencies": %s\n' "$deps"
    else
      printf '\n'
    fi
    printf '}\n'
  } > package.json
}

# _node_mgr_stub <name> <version> <exit-code> — a package-manager binary on
# PATH (stub-bin, prepended like sc_stub's shellcheck stub) that answers
# --version and otherwise logs its own invocation to "<name>-invoked.log"
# and exits <exit-code>.
_node_mgr_stub() {
  local name="$1" ver="$2" rc="$3"
  mkdir -p stub-bin
  cat > "stub-bin/$name" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$ver"
  exit 0
fi
{
  printf '%s' "$name"
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$PWD/$name-invoked.log"
exit $rc
STUB
  chmod +x "stub-bin/$name"
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _node_local_tool_stub <name> <version> <exit-code> — a project-environment
# tool (eslint, jest, vitest) at node_modules/.bin/<name>, D2's rule that
# dev tools come only from the project, never PATH. Logs every invocation's
# arguments, one line per call, to "<name>-invoked.log".
_node_local_tool_stub() {
  local name="$1" ver="$2" rc="$3"
  mkdir -p node_modules/.bin
  cat > "node_modules/.bin/$name" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$ver"
  exit 0
fi
{
  printf '%s' "$name"
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$PWD/$name-invoked.log"
exit $rc
STUB
  chmod +x "node_modules/.bin/$name"
}

# _node_jest_stub <version> <related-count> <run-exit-code> — jest's
# --listTests --findRelatedTests prints <related-count> fake test paths and
# exits 0 (it only lists and exits); any other invocation (the narrowed
# --findRelatedTests run) logs its arguments and exits <run-exit-code>.
_node_jest_stub() {
  local ver="$1" n="$2" rc="$3"
  mkdir -p node_modules/.bin
  cat > node_modules/.bin/jest <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
  printf '%s\n' "$ver"
  exit 0
fi
{
  printf 'jest'
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$PWD/jest-invoked.log"
case " \$* " in
  *" --listTests "*)
    i=0
    while [ "\$i" -lt $n ]; do
      printf 'related-%s.test.js\n' "\$i"
      i=\$((i + 1))
    done
    exit 0
    ;;
esac
exit $rc
STUB
  chmod +x node_modules/.bin/jest
}

# _node_scope <files-list-path> [mapped-file-path] — run the profile
# directly (never through `jig verify`) with JIG_VERIFY_SCOPE/FILES/MAPPED
# set to files this test wrote, per conventions/shell.md ("a test decides
# its own environment").
_node_scope() {
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$1"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  if [ -n "${2:-}" ]; then
    JIG_VERIFY_MAPPED="$2"
    export JIG_VERIFY_MAPPED
  fi
  run bash "$JIG_HOME/profiles/node/verify.sh"
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
}

# _node_files <path>... — write a JIG_VERIFY_FILES-shaped list (one path per
# line) and print its own path.
_node_files() {
  local f
  : > .changed-files
  for f in "$@"; do printf '%s\n' "$f" >> .changed-files; done
  printf '%s/.changed-files\n' "$PWD"
}

# profiles_harness <script> — profiles_detect the way tests/profiles.t.sh
# tests it: sourced with its own dependencies, against the real framework's
# profiles directory. Duplicated locally: tests/run.sh sources one *.t.sh
# file at a time, so tests/profiles.t.sh's own copy is not in scope here.
profiles_harness() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
  '"$1"
}

# --- detect ------------------------------------------------------------------

test_profile_node_detected_by_package_json() {
  fixture_repo
  printf '{}\n' > package.json
  # shellcheck disable=SC2016
  profiles_harness 'profiles_detect "$JIG_HOME/profiles"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "node"
}

# --- no tools / no scripts (back-compat: existing tests/verify.t.sh assertions) --

test_profile_node_skips_every_check_without_any_manager() {
  fixture_repo
  _node_pkg '{"test": "echo ok", "lint": "echo ok", "typecheck": "echo ok"}'

  run_no_tools bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: skip"
  assert_contains "$OUT" "node: npm run lint: skip"
  assert_contains "$OUT" "node: npm run typecheck: skip"
}

test_profile_node_skips_when_no_scripts_declared() {
  fixture_repo
  printf '{}\n' > package.json
  _node_mgr_stub npm 9.9.9 0

  run bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: skip (no test script or npm not found)"
  assert_contains "$OUT" "node: npm run lint: skip (no lint script or npm not found)"
  assert_contains "$OUT" "node: npm run typecheck: skip (no typecheck script or npm not found)"
}

# --- full run: pass/fail, version in the verdict ----------------------------

test_profile_node_full_run_passes_and_names_npm_version() {
  fixture_repo
  _node_pkg '{"test": "echo ok", "lint": "echo ok", "typecheck": "echo ok"}'
  _node_mgr_stub npm 10.2.0 0

  run bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (10.2.0)"
  assert_contains "$OUT" "node: npm run lint: pass (10.2.0)"
  assert_contains "$OUT" "node: npm run typecheck: pass (10.2.0)"
  assert_file_contains npm-invoked.log "npm test"
  assert_file_contains npm-invoked.log "npm run lint"
  assert_file_contains npm-invoked.log "npm run typecheck"
}

test_profile_node_full_run_fails_and_names_npm_version() {
  fixture_repo
  _node_pkg '{"test": "exit 1"}'
  _node_mgr_stub npm 10.2.0 1

  run bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: fail (10.2.0)"
}

# --- package manager selection ----------------------------------------------

test_profile_node_names_manager_from_package_manager_field() {
  fixture_repo
  {
    printf '{\n'
    printf '  "packageManager": "pnpm@8.6.0",\n'
    printf '  "scripts": {"test": "echo ok"}\n'
    printf '}\n'
  } > package.json
  _node_mgr_stub pnpm 8.6.0 0

  run bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: pnpm test: pass (8.6.0)"
  assert_file_contains pnpm-invoked.log "pnpm test"
}

test_profile_node_names_manager_from_pnpm_lock_file() {
  fixture_repo
  _node_pkg '{"test": "echo ok"}'
  : > pnpm-lock.yaml
  _node_mgr_stub pnpm 8.0.0 0

  run bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: pnpm test: pass"
}

test_profile_node_names_manager_from_yarn_lock_file() {
  fixture_repo
  _node_pkg '{"test": "echo ok"}'
  : > yarn.lock
  _node_mgr_stub yarn 1.22.0 0

  run bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: yarn test: pass"
}

test_profile_node_bun_uses_run_test_not_bun_test() {
  # `bun test` is Bun's own built-in test runner and ignores package.json's
  # "test" script entirely; only `bun run test` runs it.
  fixture_repo
  _node_pkg '{"test": "echo ok"}'
  : > bun.lockb
  _node_mgr_stub bun 1.1.0 0

  run bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: bun run test: pass"
  assert_file_contains bun-invoked.log "bun run test"
}

test_profile_node_chosen_manager_missing_on_path_skips_naming_it() {
  fixture_repo
  _node_pkg '{"test": "echo ok"}'
  : > pnpm-lock.yaml
  # No pnpm stub anywhere: run_no_tools strips PATH to the base system dirs.

  run_no_tools bash "$JIG_HOME/profiles/node/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "node: pnpm test: skip (no test script or pnpm not found)"
}

# --- lint narrowing (D4) -----------------------------------------------------

test_profile_node_lint_narrows_to_changed_eslint_files() {
  fixture_repo
  _node_pkg '{"lint": "eslint ."}'
  _node_mgr_stub npm 10.0.0 0
  _node_local_tool_stub eslint 8.5.0 0
  printf 'x\n' > a.ts
  printf 'y\n' > b.ts
  printf '# doc\n' > README.md
  files=$(_node_files a.ts b.ts README.md)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm run lint: pass (8.5.0, scope: eslint, 2 files)"
  assert_file_contains eslint-invoked.log "a.ts"
  assert_file_contains eslint-invoked.log "b.ts"
  assert_not_contains "$(cat eslint-invoked.log)" "README.md"
}

test_profile_node_lint_full_when_script_does_not_invoke_eslint() {
  fixture_repo
  _node_pkg '{"lint": "prettier --check ."}'
  _node_mgr_stub npm 10.0.0 0
  _node_local_tool_stub eslint 8.5.0 0
  printf 'x\n' > a.ts
  files=$(_node_files a.ts)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm run lint: pass (10.0.0, scope: not narrowable, ran full set)"
  assert_no_file eslint-invoked.log
  assert_file_contains npm-invoked.log "npm run lint"
}

test_profile_node_lint_full_when_eslint_binary_missing() {
  fixture_repo
  _node_pkg '{"lint": "eslint ."}'
  _node_mgr_stub npm 10.0.0 0
  printf 'x\n' > a.ts
  files=$(_node_files a.ts)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm run lint: pass (10.0.0, scope: not narrowable, ran full set)"
}

test_profile_node_lint_all_trigger_on_package_json_change() {
  fixture_repo
  _node_pkg '{"lint": "eslint ."}'
  _node_mgr_stub npm 10.0.0 0
  _node_local_tool_stub eslint 8.5.0 0
  files=$(_node_files package.json)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm run lint: pass (10.0.0, scope: project configuration changed, whole project)"
  assert_no_file eslint-invoked.log
}

test_profile_node_lint_skips_when_no_lintable_files_changed() {
  fixture_repo
  _node_pkg '{"lint": "eslint ."}'
  _node_mgr_stub npm 10.0.0 0
  _node_local_tool_stub eslint 8.5.0 0
  printf '# doc\n' > README.md
  files=$(_node_files README.md)

  _node_scope "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm run lint: skip (scope: no changed lintable files)"
}

# --- test narrowing (D4): jest -----------------------------------------------

test_profile_node_test_narrows_via_jest_related_tests() {
  fixture_repo
  _node_pkg '{"test": "jest"}' '{"jest": "^29.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_jest_stub 29.0.0 2 0
  printf 'x\n' > a.ts
  files=$(_node_files a.ts)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (29.0.0, scope: jest related, 2 files)"
  assert_file_contains jest-invoked.log "--listTests --findRelatedTests a.ts"
  assert_file_contains jest-invoked.log "--findRelatedTests a.ts"
}

test_profile_node_test_jest_confirms_zero_related_falls_back_to_full() {
  fixture_repo
  _node_pkg '{"test": "jest"}' '{"jest": "^29.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_jest_stub 29.0.0 0 0
  printf 'x\n' > a.ts
  files=$(_node_files a.ts)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (10.0.0, scope: jest finds no related tests, ran full set)"
  assert_file_contains npm-invoked.log "npm test"
}

# --- test narrowing (D4): vitest --------------------------------------------

test_profile_node_test_narrows_via_vitest_for_a_changed_test_file() {
  fixture_repo
  _node_pkg '{"test": "vitest run"}' '{"vitest": "^1.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_local_tool_stub vitest 1.4.0 0
  printf 'x\n' > a.test.ts
  files=$(_node_files a.test.ts)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (1.4.0, scope: vitest related, 1 files)"
  assert_file_contains vitest-invoked.log "run a.test.ts"
}

test_profile_node_test_vitest_non_test_source_change_forces_full() {
  # vitest's own `related` command runs the tests it selects rather than
  # listing them, so there is no way to confirm a narrowed run would select
  # anything without already running it (design D4): a changed source file
  # that is not itself a test file always sends vitest to the full script.
  fixture_repo
  _node_pkg '{"test": "vitest run"}' '{"vitest": "^1.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_local_tool_stub vitest 1.4.0 0
  printf 'x\n' > a.ts
  files=$(_node_files a.ts)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (10.0.0, scope: not narrowable, ran full set)"
  assert_no_file vitest-invoked.log
  assert_file_contains npm-invoked.log "npm test"
}

# --- always-ALL trigger for test (D4) ---------------------------------------

test_profile_node_test_all_trigger_on_lock_file_change() {
  fixture_repo
  _node_pkg '{"test": "jest"}' '{"jest": "^29.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_jest_stub 29.0.0 3 0
  files=$(_node_files package-lock.json)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (10.0.0, scope: not narrowable, ran full set)"
  assert_no_file jest-invoked.log
}

# --- typecheck never narrows (D4) -------------------------------------------

test_profile_node_typecheck_always_runs_full_when_scoped() {
  fixture_repo
  _node_pkg '{"typecheck": "tsc --noEmit"}'
  _node_mgr_stub npm 10.0.0 0
  printf 'x\n' > a.ts
  files=$(_node_files a.ts)

  _node_scope "$files"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm run typecheck: pass (10.0.0, scope: not narrowable, ran full set)"
  assert_file_contains npm-invoked.log "npm run typecheck"
}

# --- zero selection is not a pass (ADR-0041) ---------------------------------

test_profile_node_zero_selection_empty_decision_skips() {
  fixture_repo
  _node_pkg '{"test": "jest"}' '{"jest": "^29.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_jest_stub 29.0.0 1 0
  printf '# doc\n' > README.md
  files=$(_node_files README.md)

  _node_scope "$files"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: skip (scope: no changed file maps to a test)"
  assert_no_file jest-invoked.log
}

test_profile_node_zero_selection_missing_filter_runs_full() {
  # A deleted tracked file is still "changed"; the map (or the builtin,
  # here proven through it) can therefore point at a test file that no
  # longer exists. That must never quietly select nothing.
  fixture_repo
  _node_pkg '{"test": "jest"}' '{"jest": "^29.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_jest_stub 29.0.0 1 0
  files=$(_node_files gone.ts)
  mapped="$PWD/.mapped"
  printf 'gone.ts\tgone.test.ts\n' > "$mapped"

  _node_scope "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (10.0.0, scope: filter 'gone.test.ts' selects no tests, ran full set)"
  assert_no_file jest-invoked.log
}

# --- map filters (D5): a test file path, used directly ----------------------

test_profile_node_map_filter_overrides_builtin() {
  fixture_repo
  _node_pkg '{"test": "jest"}' '{"jest": "^29.0.0"}'
  _node_mgr_stub npm 10.0.0 0
  _node_jest_stub 29.0.0 1 0
  printf 'x\n' > a.ts
  printf 'x\n' > custom.test.ts
  files=$(_node_files a.ts)
  mapped="$PWD/.mapped"
  printf 'a.ts\tcustom.test.ts\n' > "$mapped"

  _node_scope "$files" "$mapped"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "node: npm test: pass (29.0.0, scope: jest related, 1 files)"
  assert_file_contains jest-invoked.log "custom.test.ts"
  assert_not_contains "$(cat jest-invoked.log)" "a.ts "
}
