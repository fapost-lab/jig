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

# --- share: link rather than copy (item 3, 4) --------------------------------

test_bootstrap_share_links_a_file_and_writes_reach_the_owner() {
  skip_unless_symlinks
  bootstrap_setup_nested
  mkdir -p config
  printf 'v1\n' > config/shared.txt
  printf 'worktree.share: [config/shared.txt]\n' >> .ai/config.yaml
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_symlink "$wt/config/shared.txt"
  assert_contains "$ERR" "shared config/shared.txt"

  printf 'v2 from the worktree\n' > "$wt/config/shared.txt"
  assert_eq "v2 from the worktree" "$(cat config/shared.txt)" \
    "a write through the shared link did not reach the owning checkout"
}

# A shared directory is mirrored -- created for real, each of its entries a
# link -- rather than linked whole (bootstrap.sh's _bootstrap_share comment):
# git does not apply a trailing-slash ignore pattern like `packages/` to a
# symlink, so a linked-whole directory would read as untracked forever and
# `git worktree remove` would refuse the worktree for good.
test_bootstrap_share_of_a_directory_mirrors_it_entry_by_entry() {
  skip_unless_symlinks
  bootstrap_setup_nested
  printf 'worktree.share: [packages]\n' >> .ai/config.yaml
  mkdir -p packages/left
  printf 'left pkg\n' > packages/left/index.js
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_dir "$wt/packages"
  [ ! -L "$wt/packages" ] || fail "the shared directory itself must not be a symlink"
  assert_symlink "$wt/packages/left"
  assert_eq "$(cd packages/left && pwd -P)" "$(cd "$wt/packages/left" && pwd -P)"
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
  git commit -q -m "ignore derived and shared state"
  printf 'worktree.share: [packages]\n' >> .ai/config.yaml
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
  printf 'worktree.share: ["x y", "z"]\n' >> .ai/config.yaml

  run _cfg_list_lines worktree.share
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
  printf 'worktree.share: [packages/*]\n' >> .ai/config.yaml

  run _cfg_list_lines worktree.share
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
  skip_unless_symlinks
  bootstrap_setup_nested
  printf 'worktree.share: [packages/]\n' >> .ai/config.yaml
  mkdir -p packages/left
  printf 'pkg\n' > packages/left/index.js
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  assert_not_contains "$ERR" "not a plain repository-relative path"
  assert_symlink "$OUT/packages/left"
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

# F7 (P3, but it carries the weight of the mirror's trade-off). The mirror was
# accepted on the promise that `jig task bootstrap` brings in a package added
# later. The outer "already there, leave it alone" check used to swallow that
# promise whole, because a mirror *is* an existing destination.
test_task_bootstrap_adds_a_package_added_after_the_worktree_was_made() {
  skip_unless_symlinks
  bootstrap_setup_nested
  printf 'worktree.share: [packages]\n' >> .ai/config.yaml
  mkdir -p packages/one
  printf 'one\n' > packages/one/index.js
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  assert_symlink "$wt/packages/one"
  assert_no_file "$wt/packages/two"

  # a package installed in the owning checkout afterwards
  mkdir -p packages/two
  printf 'two\n' > packages/two/index.js

  run jig task bootstrap T-1
  assert_eq 0 "$RC"
  assert_symlink "$wt/packages/two" \
    "jig task bootstrap must bring in a package added after the worktree was made"
  assert_eq "two" "$(cat "$wt/packages/two/index.js")"
  assert_contains "$OUT" "packages"
}

# F7's safety half: topping up is only ever jig's own mirror. A directory git
# tracks is the worktree's own, and adding links inside it would make the tree
# untracked-dirty -- stranding it exactly as F8 did.
test_bootstrap_does_not_top_up_a_git_tracked_directory() {
  skip_unless_symlinks
  bootstrap_setup_nested
  printf 'worktree.share: [packages]\n' >> .ai/config.yaml
  mkdir -p packages/tracked
  printf 'tracked\n' > packages/tracked/index.js
  git add -A
  git commit -q -m "packages is tracked here"
  jig task new T-1 >/dev/null

  run_split jig task start T-1 --worktree
  assert_eq 0 "$RC"
  local wt="$OUT"
  [ ! -L "$wt/packages/tracked" ] || fail "a git-tracked entry was replaced by a link"

  mkdir -p packages/untracked_pkg
  printf 'later\n' > packages/untracked_pkg/index.js

  run jig task bootstrap T-1
  assert_eq 0 "$RC"
  [ ! -e "$wt/packages/untracked_pkg" ] \
    || fail "topped up a directory git tracks; the worktree is now untracked-dirty"
  assert_eq "" "$(git -C "$wt" status --porcelain)"
}
