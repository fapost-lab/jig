# Assertion helpers and fixtures for tests/*.t.sh. Sourced by tests/run.sh
# inside each test's subshell; every helper exits 1 on failure.
# shellcheck shell=bash

# --- fixtures ----------------------------------------------------------------

# Create an empty git repository in the current (temporary) directory with
# one commit on branch main. Prints nothing.
fixture_repo() {
  git init -q .
  git symbolic-ref HEAD refs/heads/main
  printf '# fixture\n' > README.md
  git add README.md
  git commit -q -m "init"
}

# fixture_release_source <dir> — make framework copy <dir> a released source:
# a git repository of its own, one commit, tagged v<the version it declares>.
# A copy-mode install takes released code only
# (adr-20261106-copy-mode-projects-take-released-code-only), so a test that
# builds a source by copying and changing $JIG_HOME releases it after the
# change. Any .git the copy brought along is replaced.
fixture_release_source() {
  local dir="$1" version
  version=$(sed -n 's/^JIG_VERSION="\([^"]*\)".*/\1/p' "$dir/scripts/lib/version.sh") || return 1
  [ -n "$version" ] || return 1
  rm -rf "$dir/.git"
  (
    cd "$dir" || exit 1
    git init -q . && git add -A \
      && git -c user.name=jig-tests -c user.email=tests@jig.invalid \
        commit -q --no-verify -m "release $version" \
      && git -c user.name=jig-tests -c user.email=tests@jig.invalid \
        tag -a "v$version" -m "v$version"
  ) >/dev/null 2>&1
}

# fixture_unreleased_source <dir> — <dir> becomes a copy of the released
# framework ($JIG_HOME) with one commit past its release tag: code that is on
# a branch but in no release, which a copy-mode install refuses unless asked
# (--unreleased). Prints nothing; the version it names is X.Y.Z+<sha7>.
fixture_unreleased_source() {
  local dir="$1"
  mkdir -p "$dir"
  cp -R "$JIG_HOME"/. "$dir"/ || return 1
  printf '\n# past the release tag\n' >> "$dir/profiles/generic/verify.sh"
  git -C "$dir" add -A \
    && git -C "$dir" -c user.name=jig-tests -c user.email=tests@jig.invalid \
      commit -q --no-verify -m "past the release tag" >/dev/null 2>&1
}

# A default copy-mode install for tests of commands other than init/upgrade.
# Cache only preparation, never results; the runner discards it after each run.
# cp (not hard links) isolates both the installed files and Git state per test.
fixture_jig_repo() {
  if [ -z "${JIG_TEST_CACHE:-}" ]; then
    fixture_repo && jig init --from "$JIG_HOME" >/dev/null
    return $?
  fi
  fixture_cache_prepare || return 1
  cp -R "$JIG_TEST_CACHE/installed/." .
}

# task_route_class <id> — classify a task filed without a class as T0, the
# route that records nothing before verify; a task with a class keeps it. The
# completion gates refuse an unclassified task filed under the route-evidence
# check (adr-20261004-a-route-stage-is-proven-by-its-record), and most tests
# file one only to reach those gates.
task_route_class() {
  if ! grep -q '^class:' ".ai/workspace/tasks/$1/state" 2>/dev/null; then
    jig task set "$1" class T0 >/dev/null 2>&1
  fi
  return 0
}

# task_route_done <id> — task_route_class, then verify's sign-off (`status
# ready`), which `knowledge_consolidated true` and `task ship` ask for. Silent:
# a refused `ready` is left for the test's own assertion to meet.
task_route_done() {
  task_route_class "$1"
  jig task set "$1" status ready >/dev/null 2>&1
  return 0
}

# fixture_cache_prepare — build the cached install fixture_jig_repo copies, once
# per runner invocation. Lazy when tests run one at a time; a parallel runner
# calls it before it starts any test, because two tests building it at once
# would both miss `ready`, and the second `mv` would put its build *inside* the
# first one's — a fixture corrupted without an error.
fixture_cache_prepare() {
  local seed="$JIG_TEST_CACHE/installed" build
  [ ! -f "$JIG_TEST_CACHE/ready" ] || return 0
  mkdir -p "$JIG_TEST_CACHE" || return 1
  build=$(mktemp -d "$JIG_TEST_CACHE/build.XXXXXX") || return 1
  # An empty result with status 0 is a substitution that never ran (tests/run.sh,
  # run_dir_ok): `cd ""` would build the fixture where the caller stands.
  [ -n "$build" ] && [ -d "$build" ] || return 1
  (
    cd "$build" || exit 1
    fixture_repo && jig init --from "$JIG_HOME" >/dev/null
  ) || return 1
  mv "$build" "$seed" || return 1
  touch "$JIG_TEST_CACHE/ready" || return 1
}

# fixture_source_v2_build <dir> — <dir> (existing, empty) becomes the "source
# v2" the upgrade tests install over a project: a released copy of $JIG_HOME
# with a changed profile script, version 9.9.9 and a brand-new skill (with a
# slash invocation, so the codex transform is exercised on install too).
fixture_source_v2_build() {
  local dest="$1" tmp_version
  cp -R "$JIG_HOME"/. "$dest"/ || return 1
  fixture_release_source "$dest" || return 1
  printf '\n# v2 marker\n' >> "$dest/profiles/generic/verify.sh"
  mkdir -p "$dest/skills/jig-newthing"
  cat > "$dest/skills/jig-newthing/SKILL.md" <<'EOT'
---
name: jig-newthing
description: fixture skill added in source-v2
---
# jig-newthing
Run `/jig-newthing` to do the thing.
EOT
  tmp_version="$dest/scripts/lib/version.sh.tmp"
  sed 's/^JIG_VERSION=.*/JIG_VERSION="9.9.9"/' "$dest/scripts/lib/version.sh" > "$tmp_version"
  mv "$tmp_version" "$dest/scripts/lib/version.sh"
  fixture_release_source "$dest"
}

# fixture_source_v2_copy <dir> — put the source v2 into the existing directory
# <dir>: a copy of the cached build when fixture_caches_prepare made one, else
# a fresh build (serial runner, cache absent). Same tree either way.
fixture_source_v2_copy() {
  if [ -n "${JIG_TEST_CACHE:-}" ] && [ -f "$JIG_TEST_CACHE/source-v2-ready" ]; then
    cp -R "$JIG_TEST_CACHE/source-v2/." "$1"/
    return $?
  fi
  fixture_source_v2_build "$1"
}

# fixture_caches_prepare <list-file> — what a parallel runner calls once, before
# it starts any worker, in place of fixture_cache_prepare. <list-file> holds the
# selected tests, one per line: `<idx>\t<file>\t<name>\t<full>`. It always
# builds the install cache (fixture_cache_prepare) and builds the source-v2
# cache only when a selected test is in a file that uses it (upgrade::). Safe to
# call again: a cache that is ready is left alone. No locks — never call it
# from two processes at once, nor from a worker.
fixture_caches_prepare() {
  local list="$1" file name full build tab want=0
  tab=$(printf '\t')
  fixture_cache_prepare || return 1
  if [ -f "$JIG_TEST_CACHE/source-v2-ready" ]; then
    return 0
  fi
  while IFS="$tab" read -r _ file name full; do
    case "$full" in
      upgrade::*) want=1 ;;
    esac
  done < "$list"
  if [ "$want" -eq 0 ]; then
    return 0
  fi
  build=$(mktemp -d "$JIG_TEST_CACHE/source-v2-build.XXXXXX") || return 1
  [ -n "$build" ] && [ -d "$build" ] || return 1
  fixture_source_v2_build "$build" || return 1
  mv "$build" "$JIG_TEST_CACHE/source-v2" || return 1
  touch "$JIG_TEST_CACHE/source-v2-ready"
}

# Build the merge topologies housekeeping has to tell apart, on top of the
# current repository (call after fixture_jig_repo). Every branch below is
# created off main and left behind so ancestry detection can be asserted
# against a known answer:
#
#   ff-merged       fast-forwarded into main          -> merged
#   commit-merged   merged with a real merge commit   -> merged
#   squash-merged   squashed into one commit on main  -> merged
#   rebase-merged   replayed commit-by-commit on main -> merged
#   still-open      never merged                      -> unknown
#   gone-merged     squash-merged, then branch deleted-> unknown (no local ref)
#
# `gone-merged` is the case only a forge can answer: with the branch deleted
# there is no tip to compare, which is why the ancestry tier must say
# `unknown` rather than guess.
fixture_merge_repo() {
  git checkout -q -b ff-merged
  printf 'ff\n' > ff.txt
  git add ff.txt
  git commit -q -m "ff work"
  git checkout -q main
  git merge -q --ff-only ff-merged

  git checkout -q -b commit-merged
  printf 'mc\n' > mc.txt
  git add mc.txt
  git commit -q -m "merge-commit work"
  git checkout -q main
  git merge -q --no-ff -m "merge commit-merged" commit-merged

  # Two commits, so a per-commit patch-id comparison would miss this and only
  # the combined diff matches (design.md §2 step 2).
  git checkout -q -b squash-merged
  printf 'sq1\n' > sq.txt
  git add sq.txt
  git commit -q -m "squash work 1"
  printf 'sq2\n' >> sq.txt
  git add sq.txt
  git commit -q -m "squash work 2"
  git checkout -q main
  # `--squash` always says "Squash commit -- not updating HEAD" on stdout and
  # `cherry-pick` has no --quiet at all, so both are silenced here rather than
  # leaking into the output a test asserts on.
  git merge --squash squash-merged >/dev/null
  git commit -q -m "squashed squash-merged"

  git checkout -q -b rebase-merged
  printf 'rb\n' > rb.txt
  git add rb.txt
  git commit -q -m "rebase work"
  git checkout -q main
  git cherry-pick rebase-merged >/dev/null

  git checkout -q -b still-open
  printf 'open\n' > open.txt
  git add open.txt
  git commit -q -m "open work"
  git checkout -q main

  git checkout -q -b gone-merged
  printf 'gone\n' > gone.txt
  git add gone.txt
  git commit -q -m "gone work"
  git checkout -q main
  git merge --squash gone-merged >/dev/null
  git commit -q -m "squashed gone-merged"
  git branch -q -D gone-merged
}

# Create a task workspace directly, bypassing `jig task new`'s dirty-tree and
# branch checks: housekeeping tests need workspaces whose `branch` and
# `updated_at` are set to values the current checkout does not have.
# Usage: fixture_task <id> <branch> <status> [key:value ...]
fixture_task() {
  local id="$1" branch="$2" status="$3" kv key value today file
  shift 3
  today=$(date +%Y-%m-%d)
  file=".ai/workspace/tasks/$id/state"
  mkdir -p ".ai/workspace/tasks/$id"
  {
    printf 'task_id: %s\n' "$id"
    printf 'branch: %s\n' "$branch"
    printf 'status: %s\n' "$status"
    # A closed task always carries a recorded knowledge decision: `task set`
    # refuses the other combination (ADR-0030), so a fixture must not build it.
    if [ "$status" = consolidated ]; then
      printf 'knowledge_consolidated: true\n'
    else
      printf 'knowledge_consolidated: false\n'
    fi
    printf 'created_at: %s\n' "$today"
    printf 'updated_at: %s\n' "$today"
  } > "$file"
  # An override replaces its key rather than appending a second copy:
  # task_state_get reads the first match, so a duplicate `updated_at` would
  # silently defeat every ageing test.
  for kv in "$@"; do
    key="${kv%%:*}"
    value="${kv#*:}"
    if grep -q "^$key:" "$file"; then
      sed "s|^$key:.*|$key: $value|" "$file" > "$file.tmp"
      mv "$file.tmp" "$file"
    else
      printf '%s: %s\n' "$key" "$value" >> "$file"
    fi
  done
  printf '# %s\n' "$id" > ".ai/workspace/tasks/$id/task.md"
}

# fixture_staging_repo — a project on the staging flow (git.flow: staging,
# git.staging_branch: staging) with an origin, and five started tasks, each on
# its branch task/<id>: `on` merged into origin's staging; `behind` merged
# there and then given a fix; `promoted` merged there and then given origin's
# main, which moved since, by a merge; `never` with a commit nobody shipped;
# `fresh` with no commit of its own. HEAD is back on main.
fixture_staging_repo() {
  local id fork
  fixture_jig_repo
  printf 'origin.git/\n' >> .git/info/exclude
  printf 'git.flow: staging\ngit.staging_branch: staging\n' >> .ai/config.yaml
  git add -A >/dev/null
  git commit -q -m "jig init snapshot"
  fork=$(git rev-parse HEAD)
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git branch staging
  git push -q origin main staging
  for id in on behind promoted never; do
    git checkout -q -b "task/$id" main
    printf '%s\n' "$id" > "$id.txt"
    git add "$id.txt"
    git commit -q -m "$id"
  done
  git branch task/fresh main
  for id in on behind promoted; do
    git checkout -q staging
    git merge -q --no-ff -m "ship $id" "task/$id"
  done
  git push -q origin staging
  git checkout -q task/behind
  printf 'fix\n' >> behind.txt
  git commit -q -am "fix behind"
  git checkout -q main
  printf 'later\n' > later.txt
  git add later.txt
  git commit -q -m "main moves on"
  git push -q origin main
  git checkout -q task/promoted
  git merge -q --no-ff -m "bring main in" origin/main
  git checkout -q main
  git branch -D -q staging
  for id in on behind promoted never fresh; do
    fixture_task "$id" "task/$id" active "class:T2" "base_commit:$fork"
  done
}

# fixture_staging_ci_lands <id> — what CI does under `git.staging_land:
# external`, after fixture_staging_repo: task/<id> is pushed, merged into
# origin's staging branch from a clone of its own with no pull request, and
# this checkout fetches.
fixture_staging_ci_lands() {
  local id="$1"
  git push -q origin "task/$id"
  if [ ! -d ci ]; then
    git clone -q origin.git ci
    printf 'ci/\n' >> .git/info/exclude
  fi
  git -C ci fetch -q origin
  git -C ci checkout -q -B staging origin/staging
  git -C ci merge -q --no-ff -m "CI lands $id" "origin/task/$id"
  git -C ci push -q origin staging
  git fetch -q origin
}

# Run jig from the framework source checkout.
jig() { "$JIG_BIN" "$@"; }

# Run jig from the copy installed into the current project.
jig_installed() { ".ai/scripts/jig" "$@"; }

# path_without_jig [prepend-dir] — this run's PATH with every directory that
# holds an executable `jig` left out, optionally with <prepend-dir> first. A
# copy-mode install whose recorded source is gone reads from the global jig
# (upgrade_source), so a test about "no source anywhere" must not find a
# maintainer's real ~/.local/bin/jig — CI has none, and the same assertion
# would pass there and fail on a laptop.
path_without_jig() {
  local prepend="${1:-}" dir out="" IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] || continue
    [ -x "$dir/jig" ] && continue
    out="$out:$dir"
  done
  out="${out#:}"
  if [ -n "$prepend" ]; then
    printf '%s:%s\n' "$prepend" "$out"
  else
    printf '%s\n' "$out"
  fi
}

# jig_installed_without_global ... — jig_installed with no global jig on PATH.
jig_installed_without_global() { env PATH="$(path_without_jig)" ".ai/scripts/jig" "$@"; }

# --- directory-link stubs (Windows Git Bash simulation) -----------------------
#
# On Windows Git Bash `ln -s` silently copies instead of linking, so
# jig_link_detect/jig_link_dir (common.sh) and install.sh's
# _install_symlinks_work never see a real symlink there and fall back to an
# NTFS junction or a physical PATH entry. Neither code path runs naturally on
# macOS/Linux, so tests simulate the Windows toolchain with stubs on PATH.
# Callers build the stub dir(s) they need, then prepend them to PATH only for
# the one invocation under test (conventions/shell.md: "a test decides its
# own environment") -- never for the fixture setup that runs before it.

# stub_ln_copy_dir -- prints a directory holding an `ln` that, for
# `-s TARGET LINK`, copies TARGET to LINK (an empty directory when TARGET
# does not exist) and exits 0, instead of linking. Any other invocation falls
# through to the real `ln`, resolved once here, before this directory is ever
# put on PATH. Side of $JIG_TEST_TMP, never inside it, so it never shows up
# in a `git status` a test asserts on (same reason install.t.sh's gitstub
# dir and _run_out live beside the test directory, not in it).
stub_ln_copy_dir() {
  local dir="${JIG_TEST_TMP}.lnstub" real_ln
  real_ln=$(command -v ln) || fail "stub_ln_copy_dir: no real ln on PATH to wrap"
  mkdir -p "$dir"
  cat > "$dir/ln" <<STUB
#!/bin/sh
if [ "\$1" = "-s" ]; then
  target="\$2"
  link="\$3"
  if [ -d "\$target" ]; then
    cp -R "\$target" "\$link"
  elif [ -e "\$target" ]; then
    cp "\$target" "\$link"
  else
    mkdir -p "\$link"
  fi
  exit 0
fi
exec "$real_ln" "\$@"
STUB
  chmod +x "$dir/ln"
  printf '%s\n' "$dir"
}

# stub_junction_dir -- prints a directory holding `cmd` and `cygpath` stubs
# that simulate an NTFS junction (_jig_junction, common.sh) with a real
# symlink: `cygpath -w X` prints X unchanged (these tests only ever pass
# already-POSIX paths through it), and `cmd /c mklink /J LINK TARGET` makes a
# real symlink at LINK with the true `ln`, resolved once here before any stub
# reaches PATH -- so it works even when this directory is combined with
# stub_ln_copy_dir's, whose own `ln -s` copies. bash reads a symlink as a
# link (`-L`), which is what a real junction would give jig_link_detect too.
# Combine with stub_ln_copy_dir on PATH (that one first) to reproduce a
# machine where plain `ln -s` copies but a junction is available.
stub_junction_dir() {
  local dir="${JIG_TEST_TMP}.junctionstub" real_ln
  real_ln=$(command -v ln) || fail "stub_junction_dir: no real ln on PATH to wrap"
  mkdir -p "$dir"
  cat > "$dir/cygpath" <<'STUB'
#!/bin/sh
shift
printf '%s\n' "$1"
STUB
  chmod +x "$dir/cygpath"
  cat > "$dir/cmd" <<STUB
#!/bin/sh
# \$1=/c \$2=mklink \$3=/J \$4=link \$5=target
"$real_ln" -s "\$5" "\$4"
STUB
  chmod +x "$dir/cmd"
  printf '%s\n' "$dir"
}

# stub_git_env_log_dir <log-file> — a directory holding a `git` that appends
# one line per invocation to <log-file> — the env vars a network call must
# carry so it never sits waiting for a credential prompt
# (fetch-never-waits-for-a-prompt: GIT_TERMINAL_PROMPT, GIT_SSH_COMMAND) plus
# the arguments it was called with — then execs the real git (resolved once
# here, before this directory is ever put on PATH), so whatever is under test
# still gets a working git and a real local fixture remote. `<unset>` for a
# var this wrapper's own shell never saw, so a test can tell "not passed"
# from "passed empty".
stub_git_env_log_dir() {
  local dir="${JIG_TEST_TMP}.gitstub" real_git log="$1"
  real_git=$(command -v git) || fail "stub_git_env_log_dir: no real git on PATH to wrap"
  mkdir -p "$dir"
  cat > "$dir/git" <<STUB
#!/bin/sh
printf 'TERMINAL_PROMPT=%s SSH_COMMAND=%s ARGS=%s\n' \
  "\${GIT_TERMINAL_PROMPT-<unset>}" "\${GIT_SSH_COMMAND-<unset>}" "\$*" >> "$log"
exec "$real_git" "\$@"
STUB
  chmod +x "$dir/git"
  printf '%s\n' "$dir"
}

# --- assertions --------------------------------------------------------------

fail() { printf 'ASSERT FAIL: %s\n' "$*"; exit 1; }

# skip <reason> — mark the running test skipped rather than passed or
# failed: print "SKIP: <reason>" and exit 77, the code tests/run.sh treats
# as a skip. A skip is not a pass (RULES.md, ADR-0013): it must stay
# distinguishable in the tally, the same invariant verify.sh already
# applies to a profile's exit code 2.
skip() {
  printf 'SKIP: %s\n' "$1"
  exit 77
}

# skip_unless_readonly_dirs — skip the calling test unless `chmod 555` on a
# directory actually blocks creating a file inside it on this filesystem.
# Windows/MSYS was seen to ignore the read-only bit for a directory owned by
# the running user, so a negative-path test that depends on the write
# failing must confirm the guarantee itself rather than assume POSIX
# permission semantics everywhere.
skip_unless_readonly_dirs() {
  local dir blocked=0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-ro-check.XXXXXX") || return 1
  # Checked by name too, here and in every probe below: out of descriptors the
  # substitution is empty with status 0, and the probe would run in the test's
  # own directory (tests/run.sh, run_dir_ok).
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  chmod 555 "$dir"
  ( : > "$dir/probe" ) 2>/dev/null || blocked=1
  chmod 755 "$dir"
  rm -rf "$dir"
  [ "$blocked" -eq 1 ] || skip "chmod 555 does not make a directory read-only here"
}

# skip_unless_sha256_repos — skip the calling test unless this git can create a
# repository whose object names are SHA-256. The format is optional and was
# experimental for several releases, so a test that needs one asks git whether
# it can make one rather than reading a version number.
skip_unless_sha256_repos() {
  local dir made=0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-sha256-check.XXXXXX") || return 1
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  if ( cd "$dir" && git init -q --object-format=sha256 . ) >/dev/null 2>&1; then
    made=1
  fi
  rm -rf "$dir"
  [ "$made" -eq 1 ] || skip "this git cannot create a SHA-256 repository"
}

# skip_unless_unreadable_files — skip the calling test unless `chmod 000` on a
# file actually blocks reading it. The same two gaps as a read-only directory:
# root reads anyway, and Git Bash on NTFS keeps the file readable.
skip_unless_unreadable_files() {
  local dir blocked=0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-unreadable-check.XXXXXX") || return 1
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  printf 'probe\n' > "$dir/probe"
  chmod 000 "$dir/probe"
  cat "$dir/probe" >/dev/null 2>&1 || blocked=1
  chmod 644 "$dir/probe"
  rm -rf "$dir"
  [ "$blocked" -eq 1 ] || skip "chmod 000 does not make a file unreadable here"
}

# plant_dir_link <target> <link> — a directory link made the way jig makes
# one (jig_link_dir: a symbolic link, else an NTFS junction), for a test that
# needs a linked directory as its fixture. bash sees either as `-L`. Skips
# when this machine can make neither.
plant_dir_link() {
  bash -c '
    set -eu
    JIG_LIB="$JIG_HOME/scripts/lib"
    . "$JIG_LIB/version.sh"; . "$JIG_LIB/common.sh"
    jig_link_dir "$1" "$2"
  ' _ "$1" "$2" || skip "no directory link can be made here"
}

# skip_unless_control_char_names — skip the calling test unless a file name
# containing a tab round-trips through `git status --porcelain`, which
# quotes such names as "bad\tname". NTFS under MSYS maps a tab in a file
# name to a private-use Unicode character instead of keeping the byte, so a
# test that plants a tab and expects to see it quoted back must confirm
# this filesystem can represent it at all.
skip_unless_control_char_names() {
  local dir name status
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-ctrl-check.XXXXXX") || return 1
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  name=$(printf 'bad\tname')
  status=$(
    cd "$dir" || exit 1
    git init -q .
    : > "$name" 2>/dev/null
    git status --porcelain 2>/dev/null
  )
  rm -rf "$dir"
  case "$status" in
    *'bad\tname'*) ;;
    *) skip "this filesystem cannot represent a tab in a file name" ;;
  esac
}

# skip_unless_non_ascii_names — skip the calling test unless a file name
# holding a byte above 0x7F round-trips through git. The name is built from
# octal escapes so this file stays pure ASCII, the way the tests that use it
# do; a filesystem or a git that cannot carry it back unchanged cannot host a
# test about how such a name is printed.
skip_unless_non_ascii_names() {
  local dir name listed
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-utf8-check.XXXXXX") || return 1
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  name=$(printf 'caf\303\251.sh')
  listed=$(
    cd "$dir" || exit 1
    git init -q .
    : > "$name" 2>/dev/null
    git add -A 2>/dev/null
    git -c core.quotePath=false diff --cached --name-only 2>/dev/null
  )
  rm -rf "$dir"
  [ "$listed" = "$name" ] ||
    skip "this filesystem cannot represent a non-ASCII file name"
}

# skip_unless_symlinks — skip the calling test unless `ln -s` makes a real
# symbolic link here. Git Bash on Windows copies instead, by default. A test
# that is about symbolic links themselves (link mode, a link the test plants)
# has nothing to check without them; a test that merely *uses* a link as a
# fixture should build its fixture another way rather than skip.
skip_unless_symlinks() {
  local dir linked=0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-symlink-check.XXXXXX") || return 1
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  mkdir "$dir/target"
  if ln -s "$dir/target" "$dir/link" 2>/dev/null && [ -L "$dir/link" ]; then
    linked=1
  fi
  rm -rf "$dir"
  [ "$linked" -eq 1 ] || skip "symbolic links cannot be made here"
}

# skip_unless_link_simulation — skip the calling test unless stubs on PATH can
# stand for "this machine cannot link": real `ln -s` must work (the junction
# stub makes its "junction" with it) and no real `cmd` may be reachable, or a
# genuine junction gets made instead. On Windows the cases these tests
# simulate are the real machine, and other tests exercise them for real.
skip_unless_link_simulation() {
  skip_unless_symlinks
  if command -v cmd >/dev/null 2>&1; then
    skip "cmd is on PATH, so link failures cannot be simulated here"
  fi
}

assert_eq() {
  # assert_eq <expected> <actual> [message]
  [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$1] got [$2]"
}

assert_contains() {
  # assert_contains <haystack> <needle> [message]
  case "$1" in *"$2"*) ;; *) fail "${3:-missing substring}: [$2] not in [$1]" ;; esac
}

assert_not_contains() {
  case "$1" in *"$2"*) fail "${3:-unexpected substring}: [$2] found in [$1]" ;; esac
}

assert_file() { [ -f "$1" ] || fail "${2:-expected file}: $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "${2:-unexpected path}: $1"; }
assert_dir() { [ -d "$1" ] || fail "${2:-expected directory}: $1"; }
assert_symlink() { [ -L "$1" ] || fail "${2:-expected symlink}: $1"; }

assert_file_contains() {
  # assert_file_contains <file> <substring>
  assert_file "$1"
  grep -q -- "$2" "$1" || fail "file $1 does not contain [$2]"
}

assert_exit() {
  # assert_exit <code> <command...> — run command, compare its exit code.
  local expected="$1" actual
  shift
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  [ "$actual" -eq "$expected" ] || fail "exit code: expected $expected got $actual for: $*"
}

# Run a command, capture stdout+stderr into OUT and exit code into RC without
# failing the test. Usage: run cmd args...; then assert on $OUT / $RC.
#
# Captured through a file, never a pipe. bash 3.2 does not restart a write
# that SIGCHLD interrupts: a jig command whose own child exits while the pipe
# it writes to is full loses the line it was writing, with "printf: write
# error: Interrupted system call". Under load that happened to a test, which
# then missed a line it asserted on. A write to a regular file does not block,
# so nothing interrupts it. The command still runs in a subshell, as it did
# inside $(...), so an `exit` or a `cd` in it cannot reach the test.
run() {
  local out
  out=$(_run_out)
  set +e
  ( "$@" ) >"$out" 2>&1
  RC=$?
  set -e
  OUT=$(cat "$out")
  rm -f "$out"
  export OUT RC
}

# _run_out [suffix] — the file run() and its variants capture into: beside the
# test's directory, never inside it, since that directory is often the
# repository under test and `git status` would list the file. tests/run.sh
# removes it with the directory.
_run_out() {
  if [ -n "${JIG_TEST_TMP:-}" ]; then
    printf '%s.out%s\n' "$JIG_TEST_TMP" "${1:-}"
  else
    mktemp "${TMPDIR:-/tmp}/jig-run-out.XXXXXX"
  fi
}

# --- writes in Jig's own tree (lib/owntree.sh) --------------------------------------

# own_tree_repo <level> — an installed project at that `agent.git`, everything
# committed, with a roadmap on main and a bare `origin` holding main. The bare
# repository is excluded from git's view, so that a clean checkout reads clean.
own_tree_repo() {
  fixture_jig_repo
  mkdir -p .ai/specs/idea-x
  printf '# Idea X\n' > .ai/specs/idea-x/spec.md
  cat > .ai/specs/idea-x/roadmap.md <<'ROADMAP'
# Roadmap: Idea X

## Phase 1 — One

Why this phase.

- [ ] Alpha item
  continued here
- [x] Beta item
- [ ] fog: gamma area — why

## Phase 2 — Two

## Waves

1. Alpha item
ROADMAP
  git add -A >/dev/null
  git commit -q -m "a roadmap"
  printf 'origin.git/\nstub-gh/\nstub-git/\n' >> .git/info/exclude
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
  own_tree_level "$1"
}

# own_tree_in_the_window <script> — make a race deterministic. A fake `git`, kept in
# .git-excluded stub-git/, runs <script> once, from here, the first time a write asks
# origin about its branch (_ot_origin_has): after the write has looked for a holder and
# before it has done anything on what it saw.
own_tree_in_the_window() {
  local real
  real=$(command -v git)
  mkdir -p stub-git
  printf '%s\n' "$1" > stub-git/window
  cat > stub-git/git <<STUB
#!/usr/bin/env bash
d='$PWD/stub-git'
case " \$* " in
  *" ls-remote "*)
    if [ ! -f "\$d/fired" ]; then
      : > "\$d/fired"
      (cd '$PWD' && bash "\$d/window") > "\$d/window.out" 2>&1
    fi ;;
esac
exec '$real' "\$@"
STUB
  chmod +x stub-git/git
  PATH="$PWD/stub-git:$PATH"
  export PATH
}

# own_tree_level <level> — agent.git in this clone's own settings.
own_tree_level() {
  mkdir -p .ai
  printf 'agent.git: %s\n' "$1" > .ai/config.local.yaml
}

# own_tree_level_in <checkout> — agent.git commit in another checkout of the clone, for
# a layout where each checkout has its own settings.
own_tree_level_in() {
  (cd "$1" && own_tree_level commit)
}

# own_tree_show <ref> <path> — <path> as committed at <ref>. Resolved to a commit first:
# MSYS rewrites an argument holding a `/` before its `:` (conventions/shell.md).
own_tree_show() {
  git show "$(git rev-parse --verify "$1^{commit}"):$2"
}

# own_tree_rev — the clone's revision, as a read reports it.
own_tree_rev() {
  jig spec list --json | sed -E 's/^\{"schema":1,"revision":([0-9]+).*/\1/'
}

# own_tree_snapshot — what a person's checkout must still be after a write: its HEAD,
# the commit there, the index and every change in the tree.
own_tree_snapshot() {
  git symbolic-ref --short HEAD
  git rev-parse HEAD
  git diff --cached
  git status --porcelain
  git diff
}

# own_tree_gone — the write left no tree and no lock behind.
own_tree_gone() {
  assert_no_file .git/jig/tree "the tree outlives the write"
  assert_no_file .ai/runtime/writes/lock/busy/run "the lock outlives the write"
  assert_eq 1 "$(git worktree list --porcelain | grep -c '^worktree ')"
}

# own_tree_stub_gh — a fake, authenticated `gh`, kept in .git-excluded stub-gh/. One
# pull request at a time: `pr create` opens it, `pr list` finds it, stub-gh/state is
# its state, stub-gh/checks its checks (`pass` unless the file says otherwise).
own_tree_stub_gh() {
  mkdir -p stub-gh
  cat > stub-gh/gh <<STUB
#!/usr/bin/env bash
d='$PWD/stub-gh'
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr list") if [ -f "\$d/url" ]; then cat "\$d/url"; else printf 'null\n'; fi ;;
  "pr create")
    shift 2
    printf '%s\n' "\$@" >> "\$d/create.argv"
    # gh warns on stderr whenever the checkout it runs in is dirty.
    if [ -f "\$d/warn" ]; then printf 'Warning: 1 uncommitted change\n' >&2; fi
    printf 'https://github.com/example/example/pull/42\n' | tee "\$d/url" ;;
  "pr view")
    case "\$*" in
      *isDraft*) printf 'false %s\n' "\$(git rev-parse "\$(cat "\$d/head")")" ;;
      *) if [ -f "\$d/state" ]; then cat "\$d/state"; else printf 'OPEN\n'; fi ;;
    esac ;;
  "pr checks")
    if [ -f "\$d/checks" ]; then cat "\$d/checks"; else printf 'pass\n'; fi ;;
  "pr merge")
    printf '%s\n' "\$*" > "\$d/merged"
    if [ -f "\$d/on-merge" ]; then bash "\$d/on-merge"; fi ;;
  "repo view") printf 'true false false\n' ;;
esac
STUB
  chmod +x stub-gh/gh
  sed "s|^forge:.*|forge: github|" .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml
  git add .ai/config.yaml >/dev/null
  git commit -q -m "forge" || true
  git push -q origin main 2>/dev/null || true
  git fetch -q origin
  PATH="$PWD/stub-gh:$PATH"
  export PATH
}
