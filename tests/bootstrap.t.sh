# Tests for carrying into a task worktree the state git does not track
# (adr-20260924-a-worktree-carries-what-git-does-not; domains/task): the engine in scripts/lib/bootstrap.sh, its
# declarations (profiles_carry/profiles_lock/profiles_install in
# scripts/lib/profiles.sh, cfg_list_lines in scripts/lib/config.sh), and the
# two commands that drive it, `jig task start --worktree` and
# `jig task bootstrap`, both in scripts/lib/task.sh.
# shellcheck shell=bash

# --- fixtures -----------------------------------------------------------

# bootstrap_setup_nested — a fresh, committed jig project one level below
# this test's own temporary directory, with only the `generic` profile
# active. Nested so the default `../<project>.worktrees` root
# `task start --worktree` uses lands inside this test's directory and is
# removed with it. Mirrors task_setup_nested (tests/task.t.sh); duplicated
# because each test file sources only itself.
bootstrap_setup_nested() {
  mkdir repo || return 1
  cd repo || return 1
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init snapshot"
  bootstrap_ignore
}

# bootstrap_ignore — keep out of git the paths these tests carry, which is
# what every project with an install step does and what the carry now
# requires: anything it puts in a worktree that git can see would strand that
# worktree, so the carry refuses it. jig init already wrote and tracked
# .gitignore, so no `git add -f` is needed here -- only a brand new .gitignore
# hits this machine's gitignore-of-.gitignore.
bootstrap_ignore() {
  printf 'vendor/\nnode_modules/\npackages/\ndata/\nconfig/\n.env\n' >> .gitignore
  git add .gitignore
  git commit -q -m "keep derived state out of git"
}

# bootstrap_setup_php — bootstrap_setup_nested, but with a composer.json in
# place before `jig init` runs, so init's own detection activates the php
# profile (profiles: [generic, php]) the way a real PHP project would,
# instead of an explicit --profiles flag.
bootstrap_setup_php() {
  mkdir repo || return 1
  cd repo || return 1
  fixture_repo
  printf '{}\n' > composer.json
  jig init --from "$JIG_HOME" >/dev/null
  git add -A
  git commit -q -m "jig init snapshot"
  bootstrap_ignore
}

# run_split <command...> — as run() (tests/lib/assert.sh), but stdout and
# stderr land in separate OUT/ERR variables. `_task_start_in_worktree`
# prints only the worktree path to stdout and everything else (jig_info,
# jig_warn) to stderr, so this is what lets a test read the path without a
# bootstrap message accidentally matching it. Mirrors tests/task.t.sh's
# run_split; duplicated for the same reason as bootstrap_setup_nested above.
run_split() {
  local out err
  out=$(_run_out)
  err=$(_run_out .err)
  ( "$@" ) >"$out" 2>"$err"
  RC=$?
  OUT=$(cat "$out")
  ERR=$(cat "$err")
  rm -f "$out" "$err"
  export OUT RC ERR
}

# --- carry: profile- and project-declared paths (item 1, 2) -----------------

test_bootstrap_carries_a_profile_declared_path() {
  bootstrap_setup_php
  mkdir -p vendor/pkg
  printf 'autoload\n' > vendor/pkg/autoload.php
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_file "$wt/vendor/pkg/autoload.php"
  assert_eq "autoload" "$(cat "$wt/vendor/pkg/autoload.php")"
  assert_contains "$ERR" "carried vendor"
}

test_bootstrap_carries_a_project_declared_path() {
  bootstrap_setup_nested
  printf 'worktree.carry: [data]\n' >> .ai/config.yaml
  mkdir -p data
  printf 'seed\n' > data/seed.txt
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_file "$wt/data/seed.txt"
  assert_eq "seed" "$(cat "$wt/data/seed.txt")"
  assert_contains "$ERR" "carried data"
}



# --- a clean worktree that `git worktree remove` can actually delete (item 5) -

test_bootstrap_leaves_a_worktree_git_worktree_remove_can_delete() {
  skip_unless_symlinks
  bootstrap_setup_php
  # .gitignore already exists (jig init wrote it) and is tracked, so no
  # `git add -f` is needed here -- only a *new* .gitignore hits the global
  # gitignore-of-.gitignore trap this machine has.
  printf 'vendor/\npackages/\n' >> .gitignore
  git add .gitignore
  git commit -q -m "ignore derived state"
  printf 'worktree.carry: [packages]\n' >> .ai/config.yaml
  mkdir -p vendor/pkg packages/left
  printf 'autoload\n' > vendor/pkg/autoload.php
  printf 'left pkg\n' > packages/left/index.js
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_eq "" "$(git -C "$wt" status --porcelain)"

  rm -f "$wt/.ai/workspace/tasks/T-1"
  run git worktree remove "$wt"
  assert_eq 0 "$RC" "git worktree remove refused a clean worktree: $OUT"
  assert_no_file "$wt"
  assert_dir packages/left
  assert_file packages/left/index.js
}

# --- a path git already tracked is left exactly alone (item 6) --------------

test_bootstrap_leaves_a_git_tracked_path_alone() {
  bootstrap_setup_nested
  printf 'worktree.carry: [README.md]\n' >> .ai/config.yaml
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT" original
  original=$(cat "$wt/README.md")
  assert_not_contains "$ERR" "carried README.md"

  printf 'owner edited this after the worktree was cut\n' >> README.md
  run jig task bootstrap T-1
  assert_eq 0 "$RC"
  assert_eq "$original" "$(cat "$wt/README.md")" \
    "a git-tracked path was overwritten by the carry"
}

# --- refusals: never fatal to the task being started (item 7, 8) -----------

test_bootstrap_refuses_unsafe_paths_without_failing_the_task() {
  bootstrap_setup_nested
  printf 'worktree.carry: [.ai/workspace, /etc/passwd, ../outside]\n' >> .ai/config.yaml
  jig task new T-1 >/dev/null

  run jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_contains "$OUT" "refusing to carry .ai/workspace: it is inside .ai/"
  assert_contains "$OUT" "refusing to carry /etc/passwd: it is absolute"
  assert_contains "$OUT" "refusing to carry ../outside: it is not a plain repository-relative path"

  grep -q '^branch:' .ai/workspace/tasks/T-1/state || fail "branch was not recorded"
  grep -q '^base_commit: [0-9a-f]\{40\}$' .ai/workspace/tasks/T-1/state \
    || fail "base_commit was not recorded"
}

test_bootstrap_refuses_a_declared_path_that_is_a_symlink_in_the_owner() {
  skip_unless_symlinks
  bootstrap_setup_nested
  ln -s /tmp linked-thing
  printf 'worktree.carry: [linked-thing]\n' >> .ai/config.yaml
  jig task new T-1 >/dev/null

  run jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_contains "$OUT" "refusing to carry linked-thing: it is a link in this checkout"
  grep -q '^branch:' .ai/workspace/tasks/T-1/state || fail "branch was not recorded"
  grep -q '^base_commit: [0-9a-f]\{40\}$' .ai/workspace/tasks/T-1/state \
    || fail "base_commit was not recorded"
}

# --- a declared path absent in the owner too (item 8/9) ---------------------

test_bootstrap_reports_a_declared_path_missing_in_the_owner() {
  bootstrap_setup_php
  printf 'worktree.carry: [data]\n' >> .ai/config.yaml
  # A stub on PATH: if the install command were ever executed rather than
  # merely printed, this file would exist afterwards.
  mkdir -p bin
  cat > bin/composer <<'STUB'
#!/bin/sh
touch "$PWD/composer-was-run"
STUB
  chmod +x bin/composer
  jig task new T-1 >/dev/null

  PATH="$PWD/bin:$PATH" run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  # shellcheck disable=SC2016 # backticks are part of the message
  assert_contains "$ERR" 'vendor is absent in this checkout too, so nothing was carried; run `composer install` in the worktree'
  assert_contains "$ERR" "data is absent in this checkout too, so nothing was carried"
  assert_no_file composer-was-run
}

# --- --no-bootstrap (item 9) -------------------------------------------------

test_bootstrap_no_bootstrap_flag_carries_nothing() {
  bootstrap_setup_php
  mkdir -p vendor/pkg
  printf 'autoload\n' > vendor/pkg/autoload.php
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree --no-bootstrap
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_no_file "$wt/vendor"
  assert_not_contains "$ERR" "carried"
  assert_not_contains "$ERR" "is absent in this checkout too"
}

test_task_start_no_bootstrap_without_worktree_is_refused() {
  bootstrap_setup_nested
  jig task new T-1 >/dev/null

  run jig task start T-1 --no-bootstrap
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--no-bootstrap says what not to carry into a worktree; it needs --worktree"
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/state)" "branch:"
}

# --- `jig task bootstrap` (item 10) ------------------------------------------

test_task_bootstrap_fills_a_worktree_started_with_no_bootstrap() {
  bootstrap_setup_php
  mkdir -p vendor/pkg
  printf 'autoload\n' > vendor/pkg/autoload.php
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree --no-bootstrap
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_no_file "$wt/vendor"

  run jig task bootstrap T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "carried vendor"
  assert_file "$wt/vendor/pkg/autoload.php"
}

test_task_bootstrap_is_idempotent() {
  bootstrap_setup_php
  mkdir -p vendor/pkg
  printf 'autoload\n' > vendor/pkg/autoload.php
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_file "$wt/vendor/pkg/autoload.php"

  run jig task bootstrap T-1
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "carried"
  assert_file "$wt/vendor/pkg/autoload.php"
}

test_task_bootstrap_refuses_an_unknown_task() {
  bootstrap_setup_nested
  run jig task bootstrap T-nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task: T-nope"
}

test_task_bootstrap_refuses_a_task_never_started() {
  bootstrap_setup_nested
  jig task new T-1 >/dev/null

  run jig task bootstrap T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1 has not been started yet"
}

test_task_bootstrap_refuses_a_task_with_no_worktree_of_its_own() {
  bootstrap_setup_nested
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null

  run jig task bootstrap T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "T-1 has no worktree of its own"
}

# --- a stale lock file warns but never fails (item 11) -----------------------

test_bootstrap_warns_about_a_stale_lock_file() {
  bootstrap_setup_php
  printf 'lock-v1\n' > composer.lock
  git add composer.lock
  git commit -q -m "add lock"
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_eq "lock-v1" "$(cat "$wt/composer.lock")"

  # The owner's lock moves on after the worktree was cut from it.
  printf 'lock-v2\n' > composer.lock

  run jig task bootstrap T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "composer.lock differs from this checkout's; what was carried may be stale"
  # A warning, never a refusal: the worktree's own lock is untouched.
  assert_eq "lock-v1" "$(cat "$wt/composer.lock")"
}

# --- cfg_list_lines (item 12) -------------------------------------------------
# Tested directly, the way tests/config.t.sh probes cfg(): a bare `bash -c`
# sourcing common.sh and config.sh, without going through any jig command.

_cfg_list_lines() {
  bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg_list_lines "$1"
  ' _ "$1"
}

test_cfg_list_lines_reads_a_bracketed_list() {
  fixture_jig_repo
  printf 'worktree.carry: [a, b]\n' >> .ai/config.yaml

  run _cfg_list_lines worktree.carry
  assert_eq 0 "$RC"
  assert_eq "$(printf 'a\nb')" "$OUT"
}

test_cfg_list_lines_reads_a_bare_scalar() {
  fixture_jig_repo
  printf 'worktree.carry: data\n' >> .ai/config.yaml

  run _cfg_list_lines worktree.carry
  assert_eq 0 "$RC"
  assert_eq "data" "$OUT"
}

test_cfg_list_lines_strips_quotes() {
  fixture_jig_repo
  printf 'worktree.carry: ["x y", "z"]\n' >> .ai/config.yaml

  run _cfg_list_lines worktree.carry
  assert_eq 0 "$RC"
  assert_eq "$(printf 'x y\nz')" "$OUT"
}

# The reason cfg_list_lines exists rather than a bareword `for p in $(cfg_list ...)`:
# a glob-shaped item must reach its caller as the literal pattern, never as
# whatever files in the real tree happen to match it (cfg_list_lines's own
# doc comment, config.sh).
test_cfg_list_lines_does_not_expand_a_glob_shaped_item() {
  fixture_jig_repo
  mkdir -p packages/one packages/two
  touch packages/one/f packages/two/g
  printf 'worktree.carry: [packages/*]\n' >> .ai/config.yaml

  run _cfg_list_lines worktree.carry
  assert_eq 0 "$RC"
  assert_eq "packages/*" "$OUT"
}

# --- regressions from the architecture review (2026-09-24) -------------------
# Each of these reproduces a finding that review raised against the first
# implementation, so the hole stays shut.

# F1 (P0). The `.ai/` refusal used to compare the first segment case
# sensitively, and macOS and NTFS are case-insensitive by default: `.AI/runtime`
# opened the real `.ai/runtime`, the carry copied it into the worktree, and the
# untracked result made `git worktree remove` refuse that worktree for good --
# the very failure ADR-0029's cleanup and this design's mirroring exist to
# prevent.
test_bootstrap_refuses_a_case_variant_of_the_ai_directory() {
  bootstrap_setup_nested
  printf 'worktree.carry: [.AI/runtime]\n' >> .ai/config.yaml
  mkdir -p .ai/runtime
  printf 'marker\n' > .ai/runtime/marker.txt
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_contains "$ERR" "refusing to carry .AI/runtime"
  assert_no_file "$wt/.ai/runtime/marker.txt"
  # not fatal: the task is still started
  assert_file_contains .ai/workspace/tasks/T-1/state "branch: task/T-1"
}

# F1, the same hole one level down: the check looks at every segment, not just
# the first, so a declaration can neither spell nor nest its way into .ai/.
test_bootstrap_refuses_the_ai_directory_at_any_depth() {
  bootstrap_setup_nested
  printf 'worktree.carry: [sub/.ai/state]\n' >> .ai/config.yaml
  mkdir -p sub/.ai/state
  printf 'x\n' > sub/.ai/state/f
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_contains "$ERR" "refusing to carry sub/.ai/state"
  assert_no_file "$OUT/sub/.ai/state/f"
}

# F5 (P3). `packages/` is how .gitignore writes a directory -- the convention
# this whole design leans on -- so it is normalised, not refused with a message
# about dot segments.
test_bootstrap_normalises_a_trailing_slash_in_a_declaration() {
  bootstrap_setup_nested
  printf 'worktree.carry: [packages/]\n' >> .ai/config.yaml
  mkdir -p packages/left
  printf 'pkg\n' > packages/left/index.js
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_not_contains "$ERR" "not a plain repository-relative path"
  assert_eq "pkg" "$(cat "$OUT/packages/left/index.js")"
}

# F2 (P1) and F3 (P1). A carry that fails partway must remove what it made:
# the loop reads an existing destination as already carried, so remains would
# be taken for a finished carry by every later run, `jig task bootstrap`
# included. And the removal is the one deletion this library makes, so it is
# bounded -- never outside the worktree, never the worktree root.
test_bootstrap_discard_removes_its_own_remains_and_nothing_else() {
  bootstrap_setup_nested
  local root outside
  root=$(pwd -P)/tree
  outside=$(pwd -P)/outside
  mkdir -p "$root/packages/half" "$outside"
  printf 'keep\n' > "$outside/keep.txt"

  (
    # All three are read or called by the library sourced just below.
    # shellcheck disable=SC2034
    JIG_AI_DIR=.ai
    # shellcheck disable=SC2329
    jig_info() { :; }
    # shellcheck disable=SC2329
    jig_warn() { :; }
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/bootstrap.sh"

    _bootstrap_discard "$root" "$root/packages"
    [ -e "$root/packages" ] && exit 11

    _bootstrap_discard "$root" "$outside"
    [ -e "$outside/keep.txt" ] || exit 12

    _bootstrap_discard "$root" "$root"
    [ -d "$root" ] || exit 13
    exit 0
  )
  local rc=$?
  case "$rc" in
    0) ;;
    11) fail "discard left its own remains behind" ;;
    12) fail "discard deleted a path outside the worktree" ;;
    13) fail "discard deleted the worktree root itself" ;;
    *) fail "discard check exited $rc" ;;
  esac
}

# F6 (P2). `rm -rf` exits 0 having deleted nothing when a directory inside the
# tree is not writable -- and a copy keeps the source's modes, so a carried
# tree can contain one. The cleanup used to swallow that and report success,
# which put the remains back where the outer loop reads them as already
# carried: F2's hole, reopened from the other end.
test_bootstrap_discard_does_not_report_a_removal_that_failed() {
  skip_unless_readonly_dirs
  bootstrap_setup_nested
  local root
  root=$(pwd -P)/tree
  mkdir -p "$root/carried/locked"
  printf 'x\n' > "$root/carried/locked/file.txt"
  chmod 500 "$root/carried/locked"

  local rc=0
  (
    # shellcheck disable=SC2034
    JIG_AI_DIR=.ai
    # shellcheck disable=SC2329
    jig_info() { :; }
    # shellcheck disable=SC2329
    jig_warn() { :; }
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/bootstrap.sh"
    _bootstrap_discard "$root" "$root/carried"
  ) || rc=$?
  chmod 700 "$root/carried/locked" 2>/dev/null || true

  [ "$rc" -ne 0 ] || fail "discard reported success for a removal that did not happen"
}

# F6, the property that actually matters: whatever the cleanup manages, the
# destination must never hold a half-finished carry, because the next run --
# `jig task bootstrap`, the repair this design relies on -- reads an existing
# destination as finished work. Each path is staged beside its destination and
# renamed in, so a failure leaves the destination untouched.
test_bootstrap_a_failed_carry_leaves_the_destination_free() {
  bootstrap_setup_nested
  local root
  root=$(pwd -P)/tree
  mkdir -p "$root/wt" "$root/owner/vendor/pkg"
  printf 'v\n' > "$root/owner/vendor/pkg/f"

  (
    # shellcheck disable=SC2034
    JIG_AI_DIR=.ai
    # shellcheck disable=SC2329
    jig_info() { :; }
    # shellcheck disable=SC2329
    jig_warn() { :; }
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/bootstrap.sh"
    # shellcheck disable=SC2329
    profiles_carry() { printf 'php\tvendor\n'; }
    # shellcheck disable=SC2329
    profiles_lock() { :; }
    # shellcheck disable=SC2329
    profiles_install() { :; }
    # shellcheck disable=SC2329
    cfg_list_lines() { :; }
    # a copy that creates something and then fails
    # shellcheck disable=SC2329
    jig_copy_dir() { mkdir -p "$2/partial"; return 1; }
    jig_bootstrap_worktree "$root/owner" "$root/wt" "task start"
  ) >/dev/null 2>&1

  [ ! -e "$root/wt/vendor" ] \
    || fail "a failed carry left its destination in place; the next run would call it finished"
}

# F8 (P1). Staging used to sit beside the destination as
# `<path>.jig-partial.<pid>`. A project ignores `vendor/`; it does not ignore
# `vendor.jig-partial.60347`. An interrupted carry therefore left an untracked
# path, and `git worktree remove` without --force -- the only removal jig
# performs -- refused that worktree for the rest of its life. Staging lives
# under `.ai/runtime/` now, which jig's own gitignore covers, so even remains a
# kill -9 leaves behind cannot strand the tree.
test_bootstrap_staging_leftovers_cannot_strand_the_worktree() {
  skip_unless_symlinks
  bootstrap_setup_php
  # jig init already wrote and tracked .gitignore, so no `git add -f` is
  # needed -- only a brand new one hits this machine's gitignore-of-.gitignore.
  printf 'vendor/\n' >> .gitignore
  git add .gitignore
  git commit -q -m "ignore derived state"
  mkdir -p vendor/pkg
  printf 'v\n' > vendor/pkg/f
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_eq "" "$(git -C "$wt" status --porcelain)" "the carry itself must leave a clean tree"

  # what an interrupted carry would leave
  mkdir -p "$wt/.ai/runtime/bootstrap/vendor"
  printf 'half\n' > "$wt/.ai/runtime/bootstrap/vendor/f"

  assert_eq "" "$(git -C "$wt" status --porcelain)" \
    "staging remains must be invisible to git, or they strand the worktree"

  rm "$wt/.ai/workspace/tasks/T-1"
  run git worktree remove "$wt"
  assert_eq 0 "$RC" "git worktree remove refused a worktree holding staging remains: $OUT"
}

# F8, the other half: a carry must not leave a `jig-partial` name anywhere git
# can see, and repeated failures must not pile up. The staging directory is
# cleared on the way in and swept on the way out.
test_bootstrap_a_failed_carry_leaves_no_untracked_remains() {
  bootstrap_setup_nested
  local root
  root=$(pwd -P)/tree
  mkdir -p "$root/wt/.ai" "$root/owner/vendor/pkg"
  printf 'v\n' > "$root/owner/vendor/pkg/f"

  local n=0
  while [ "$n" -lt 3 ]; do
    n=$((n + 1))
    (
      # shellcheck disable=SC2034
      JIG_AI_DIR=.ai
      # shellcheck disable=SC2329
      jig_info() { :; }
      # shellcheck disable=SC2329
      jig_warn() { :; }
      # shellcheck source=/dev/null
      . "$JIG_HOME/scripts/lib/bootstrap.sh"
      # shellcheck disable=SC2329
      profiles_carry() { printf 'php\tvendor\n'; }
      # shellcheck disable=SC2329
      profiles_lock() { :; }
      # shellcheck disable=SC2329
      profiles_install() { :; }
      # shellcheck disable=SC2329
      cfg_list_lines() { :; }
      # shellcheck disable=SC2329
      jig_copy_dir() { mkdir -p "$2/partial"; return 1; }
      jig_bootstrap_worktree "$root/owner" "$root/wt" "task start"
    ) >/dev/null 2>&1
  done

  [ -z "$(find "$root/wt" -name '*jig-partial*' 2>/dev/null)" ] \
    || fail "a carry left a jig-partial path where git would see it"
  [ ! -e "$root/wt/vendor" ] || fail "a failed carry left its destination in place"
  [ -z "$(ls -A "$root/wt/.ai/runtime/bootstrap" 2>/dev/null)" ] \
    || fail "three failed carries piled up in the staging directory"
}

# F11 (P2). The carry's safety rests entirely on the project keeping the
# declared path out of git, and nothing used to check that. A project that
# declares a path in neither git nor .gitignore got a cheerful success and a
# worktree `git worktree remove` would refuse for good. The refusal names
# .gitignore, because that is the fix.
test_bootstrap_refuses_a_carry_git_would_see() {
  bootstrap_setup_nested
  printf 'worktree.carry: [libs]\n' >> .ai/config.yaml
  mkdir -p libs/one
  printf 'one\n' > libs/one/index.js
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_contains "$ERR" "git does not ignore"
  assert_contains "$ERR" ".gitignore"
  [ ! -e "$wt/libs" ] && [ ! -L "$wt/libs" ] \
    || fail "a carry git can see was left in the worktree, which strands it"
  assert_eq "" "$(git -C "$wt" status --porcelain)"
}

# F12 (P3). A directory that appears at the destination while a large tree is
# being copied would swallow the rename: `mv` moves *into* an existing
# directory, leaving vendor/vendor/ and a destination that looks empty while
# the report says it was carried.
test_bootstrap_leaves_a_destination_that_appeared_mid_carry_alone() {
  bootstrap_setup_nested
  local root
  root=$(pwd -P)/tree
  mkdir -p "$root/wt/.ai" "$root/owner/vendor/pkg"
  printf 'v\n' > "$root/owner/vendor/pkg/f"

  (
    # shellcheck disable=SC2034
    JIG_AI_DIR=.ai
    # shellcheck disable=SC2329
    jig_info() { :; }
    # shellcheck disable=SC2329
    jig_warn() { printf '%s\n' "$*"; }
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/bootstrap.sh"
    # shellcheck disable=SC2329
    profiles_carry() { printf 'php\tvendor\n'; }
    # shellcheck disable=SC2329
    profiles_lock() { :; }
    # shellcheck disable=SC2329
    profiles_install() { :; }
    # shellcheck disable=SC2329
    cfg_list_lines() { :; }
    # a copy that takes long enough for the destination to appear under it
    # shellcheck disable=SC2329
    jig_copy_dir() { mkdir -p "$2"; mkdir -p "$root/wt/vendor"; return 0; }
    jig_bootstrap_worktree "$root/owner" "$root/wt" "task start"
  ) > "$root/out" 2>&1

  grep -q 'appeared in the worktree while it was being carried' "$root/out" \
    || fail "a destination that appeared mid-carry was not reported: $(cat "$root/out")"
  [ ! -e "$root/wt/vendor/vendor" ] \
    || fail "the rename nested the carried tree inside the destination"
}

# F13 (P1). The undo used to report success from its own bookkeeping without
# asking git, which is the one place the rebuilt placement's principle had not
# been applied. `_BOOTSTRAP_MADE` is newline-separated, and an entry whose own
# name holds a newline reaches the undo as two lines that name nothing: every
# guard skipped, nothing removed, and a clean refusal reported over a worktree
# `git worktree remove` refuses for the rest of its life.
#
# The accounting is not what is tested here — a gap in it is the point. The
# undo is driven with a list that does not describe what was placed, and it
# must still say so, because the answer comes from git.
test_bootstrap_take_back_asks_git_rather_than_its_own_list() {
  skip_unless_symlinks
  bootstrap_setup_nested
  local root
  root=$(pwd -P)/tree
  mkdir -p "$root/wt" "$root/owner/libs"
  git -C "$root/wt" init -q .
  git -C "$root/wt" -c user.email=t@e -c user.name=t commit -q --allow-empty -m base
  mkdir -p "$root/wt/.ai/runtime/bootstrap"

  local rc=0
  (
    # shellcheck disable=SC2034
    JIG_AI_DIR=.ai
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/bootstrap.sh"

    baseline=$(_bootstrap_dirt "$root/wt")
    # a placement git can see, recorded under a name that does not match it
    ln -s "$root/owner/libs" "$root/wt/stray"
    _bootstrap_take_back "$root/wt" "$root/wt/.ai/runtime/bootstrap" \
      "$root/wt/not-what-was-made" "$baseline"
  ) || rc=$?
  assert_eq 1 "$rc" \
    "the undo reported success while git still saw what the placement left"
}


# F14 (P1). The backstop that closed F12 used to ask by name — is there a
# `<dst>/<staged basename>` — and a carried tree that legitimately holds a
# top-level entry of its own name answers yes without any race. `carry: [data]`
# over a `data/data/` therefore reported "left alone" while placing a tree with
# `data/data` missing from it, and because the destination then existed, every
# later `jig task bootstrap` skipped the path in silence for good.
test_bootstrap_carries_a_tree_holding_an_entry_of_its_own_name() {
  bootstrap_setup_nested
  # `data/` is already in .gitignore (bootstrap_ignore)
  printf 'worktree.carry: [data]\n' >> .ai/config.yaml
  mkdir -p data/data/inner data/other
  printf 'inner\n' > data/data/inner/f
  printf 'other\n' > data/other/f
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_not_contains "$ERR" "without nesting it" \
    "a tree holding an entry of its own name was mistaken for a nested rename"
  assert_eq "inner" "$(cat "$wt/data/data/inner/f" 2>/dev/null)" \
    "the carried tree lost the entry that shares its name"
  assert_eq "other" "$(cat "$wt/data/other/f" 2>/dev/null)"
  assert_no_file "$wt/data/data/data" "the rename nested the carried tree"
  assert_eq "" "$(git -C "$wt" status --porcelain)"
}


# --- the nesting backstop: what it must catch, and what it must not ----------
# F14 and F17 were the same defect twice: the backstop told a nested rename from
# a legitimate one by a single inode comparison, and each single form truncated a
# carried tree in the mode the other form survived. The suite could not tell any
# of the forms apart -- every one of them was green -- which is why an unmeasured
# one-liner reached the tree. These three stands discriminate.
#
# _bootstrap_inode is stubbed, because the property under test is not "what does
# this filesystem do" but "what does the backstop conclude when inode reads stop
# discriminating objects". Two stubs are needed: a constant inode reddens the
# positive half alone, a path-derived inode reddens the negative half alone, and
# no single mode reddens both.

# bootstrap_nesting_stand <inode-stub-body> <outfile> — carry `data` (a tree that
# legitimately holds a top-level `data/` of its own name) into a worktree with
# _bootstrap_inode replaced. Mirrors the F12 stand's shape.
bootstrap_nesting_stand() {
  local body="$1" out="$2" root
  root=$(pwd -P)/tree
  rm -rf "$root"
  mkdir -p "$root/wt/.ai" "$root/owner/data/data/inner" "$root/owner/data/other"
  printf 'inner\n' > "$root/owner/data/data/inner/f"
  printf 'other\n' > "$root/owner/data/other/f"
  (
    # shellcheck disable=SC2034
    JIG_AI_DIR=.ai
    # shellcheck disable=SC2329
    jig_info() { printf 'INFO %s\n' "$*"; }
    # shellcheck disable=SC2329
    jig_warn() { printf 'WARN %s\n' "$*"; }
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/bootstrap.sh"
    # shellcheck disable=SC2329
    profiles_carry() { :; }
    # shellcheck disable=SC2329
    profiles_lock() { :; }
    # shellcheck disable=SC2329
    profiles_install() { :; }
    # shellcheck disable=SC2329
    cfg_list_lines() { [ "$1" = worktree.carry ] && printf 'data\n'; return 0; }
    # shellcheck disable=SC2329
    jig_copy_dir() { cp -a "$1" "$2"; }
    eval "$body"
    jig_bootstrap_worktree "$root/owner" "$root/wt" "task bootstrap"
  ) > "$out" 2>&1
  printf '%s\n' "$root"
}

# bootstrap_assert_whole <root> <out> — the carried tree arrived entire and was
# not reported as untouched.
bootstrap_assert_whole() {
  local root="$1" out="$2"
  if grep -q 'without nesting it' "$out"; then
    fail "the backstop fired on a tree that only holds an entry of its own name: $(cat "$out")"
  fi
  assert_eq "inner" "$(cat "$root/wt/data/data/inner/f" 2>/dev/null)" \
    "the carried tree lost the subtree that shares its name"
  assert_eq "other" "$(cat "$root/wt/data/other/f" 2>/dev/null)"
}

# Mode: every path answers the same inode. Reddens the positive half on its own
# (staged and <dst>/data both read alike, so "the object there is the staged one"
# is satisfied by a rename that landed cleanly).
test_bootstrap_backstop_stands_down_when_inodes_do_not_discriminate() {
  bootstrap_setup_nested
  local root out
  out=$(pwd -P)/out
  root=$(bootstrap_nesting_stand '_bootstrap_inode() { printf "%s\n" 4242; }' "$out")
  bootstrap_assert_whole "$root" "$out"
}

# Mode: the inode is a function of the path. Reddens the negative half on its own
# (<dst> and staged sit at different paths, so "<dst> is not the staged object"
# is satisfied by a rename that landed cleanly).
test_bootstrap_backstop_stands_down_when_inodes_follow_the_path() {
  bootstrap_setup_nested
  local root out
  out=$(pwd -P)/out
  # shellcheck disable=SC2016  # the stub body is eval'd inside the stand
  root=$(bootstrap_nesting_stand \
    '_bootstrap_inode() { printf "%s" "$1" | cksum | awk "{print \$1}"; }' "$out")
  bootstrap_assert_whole "$root" "$out"
}

# And the catch itself. The destination is planted in the one window the re-test
# before `mv` cannot close, through the only call that happens inside it, so the
# rename really does nest. With the backstop removed this run reports a carry and
# leaves data/data holding the whole tree; with it, the carry declines and says so.
test_bootstrap_backstop_catches_a_rename_that_really_nested() {
  bootstrap_setup_nested
  local root out
  out=$(pwd -P)/out
  # shellcheck disable=SC2016  # the stub body is eval'd inside the stand
  root=$(bootstrap_nesting_stand '
    _bootstrap_inode() {
      if [ ! -e "$root/planted" ]; then
        : > "$root/planted"
        mkdir -p "$root/wt/data"
      fi
      ls -di "$1" 2>/dev/null | awk "NR==1 {print \$1; exit}"
    }' "$out")
  grep -q 'without nesting it' "$out" \
    || fail "a rename that nested for real was not caught: $(cat "$out")"
  [ ! -e "$root/wt/data/data" ] \
    || fail "the carried tree was left nested inside the destination"
}
