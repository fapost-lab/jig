# Tests for `jig self-update` (design.md, task framework-self-update).
# shellcheck shell=bash
#
# No network: every "remote" is a local bare repository (su_build_upstream),
# the same pattern tests/housekeeping.t.sh uses for its own remotes. Helpers
# below are prefixed su_.
#
# Fixture shape, all under the test's own isolated $HOME (tests/run.sh):
#   $HOME/work              a working framework checkout the test commits to
#   $HOME/upstream.git      a bare remote, pushed to from $HOME/work
#   $HOME/.local/share/jig  the fixture "global install" (su_share)
#   $HOME/.local/bin/jig    the fixture "global executable" (su_bin), a
#                           symlink into su_share, mirroring install.sh
#   $HOME/project           an installed project, for AC-02/AC-08/AC-11
#
# PATH is never inherited: su_path prepends the fixture bin dir to a fixed
# set of system directories resolved from this run's own PATH, so neither a
# maintainer's real ~/.local/bin/jig nor anything else ambient is reachable
# (conventions/shell.md: "a test decides its own environment").

# --- fixture builders --------------------------------------------------------

su_share() { printf '%s/.local/share/jig\n' "$HOME"; }
su_bin() { printf '%s/.local/bin\n' "$HOME"; }

# A fixed, deterministic system PATH: the directory of every tool jig's
# scripts invoke, resolved once from this run's own PATH. Never the run's
# PATH verbatim — that could also contain a real jig ahead of our fixture's.
su_system_path() {
  local tools="bash sh git sed awk grep find cut sort mktemp cp mv rm mkdir basename dirname tr date stat paste head tail wc printf env xargs ln"
  local t p dir result=""
  for t in $tools; do
    p=$(command -v "$t" 2>/dev/null) || continue
    case "$p" in /*) ;; *) continue ;; esac
    dir=${p%/*}
    # install.sh's own default bin dir (design.md section 1): excluded even
    # if it happens to hold one of the tools above, so a maintainer's real
    # ~/.local/bin/jig is never reachable through this constructed PATH.
    case "$dir" in */.local/bin) continue ;; esac
    case ":$result:" in *":$dir:"*) ;; *) result="$result:$dir" ;; esac
  done
  printf '%s\n' "${result#:}"
}

su_path() { printf '%s:%s\n' "$(su_bin)" "$(su_system_path)"; }

# Run the fixture's global jig (the symlink at su_bin) as `jig self-update`
# would find it via PATH.
su_jig() { env PATH="$(su_path)" "$(su_bin)/jig" "$@"; }

# Run a project's installed copy, the same way its own users would.
su_installed_jig() {
  local proj="$1"
  shift
  env PATH="$(su_path)" "$proj/.ai/scripts/jig" "$@"
}

# su_copy_framework_files <dest> — everything a framework source root needs
# (scripts/, skills/, templates/, adapters/, profiles/, ...), copied from
# this repository's own checkout. Mirrors upgrade.t.sh's _mk_source_v2.
su_copy_framework_files() {
  local dest="$1"
  mkdir -p "$dest"
  cp -R "$JIG_HOME"/. "$dest"/
  rm -rf "$dest/.git"
}

# su_set_version <dir> <version> — rewrite JIG_VERSION in a source tree's
# scripts/lib/version.sh (atomic tmp+mv, per shell conventions).
su_set_version() {
  local dir="$1" version="$2" f tmp
  f="$dir/scripts/lib/version.sh"
  tmp="$f.tmp.$$"
  sed 's/^JIG_VERSION=.*/JIG_VERSION="'"$version"'"/' "$f" > "$tmp"
  mv "$tmp" "$f"
}

# su_build_source <dir> — a fresh git checkout at <dir>, version 0.1.0,
# tagged v0.1.0, able to run its own scripts/jig and to be `jig init --from`.
su_build_source() {
  local dir="$1"
  # Copy first, then init: su_copy_framework_files removes any .git it
  # copied in from $JIG_HOME, which would otherwise clobber a .git created
  # beforehand.
  su_copy_framework_files "$dir"
  (cd "$dir" && git init -q . && git symbolic-ref HEAD refs/heads/main)
  su_set_version "$dir" 0.1.0
  (cd "$dir" && git add -A && git commit -q -m "v0.1.0" && git tag -a v0.1.0 -m v0.1.0)
}

# su_commit_release <dir> <version> — bump JIG_VERSION, commit, tag
# v<version>. For a plain (untagged) commit, use su_commit_plain instead.
su_commit_release() {
  local dir="$1" version="$2"
  su_set_version "$dir" "$version"
  (cd "$dir" && git add -A && git commit -q -m "release $version" && git tag -a "v$version" -m "v$version")
}

# su_commit_plain <dir> <name> — an ordinary commit that does not touch
# JIG_VERSION and carries no tag, for the branch-channel "version unchanged"
# case.
su_commit_plain() {
  local dir="$1" name="$2"
  (cd "$dir" && printf '%s\n' "$name" > "$name.txt" && git add "$name.txt" && git commit -q -m "$name")
}

# su_build_upstream <work> <upstream> — a bare remote outside any project
# fixture, with <work>'s main branch and tags pushed to it, <work>'s origin
# pointed at it.
su_build_upstream() {
  local work="$1" upstream="$2"
  git init -q --bare "$upstream"
  # A bare repo's own default branch may be "master" regardless of what the
  # pushing client uses; without this a clone's HEAD points at a ref that
  # was never pushed ("main") and checks out nothing.
  git -C "$upstream" symbolic-ref HEAD refs/heads/main
  (cd "$work" && git remote add origin "$upstream" && git push -q origin main --tags)
}

# su_push <work> — push whatever is new in <work> to its already-configured origin.
su_push() { (cd "$1" && git push -q origin main --tags); }

# su_clone_global_detached <upstream> <tag> — the fixture "global install":
# a clone of <upstream> detached at <tag>, with the fixture bin symlink
# pointing at it (install.sh's own layout, design.md section 1).
su_clone_global_detached() {
  local upstream="$1" tag="$2" share bin
  share=$(su_share)
  bin=$(su_bin)
  mkdir -p "$(dirname "$share")"
  git clone -q "$upstream" "$share"
  (cd "$share" && git checkout -q --detach "$tag")
  mkdir -p "$bin"
  ln -s "../share/jig/scripts/jig" "$bin/jig"
}

# su_clone_global_branch <upstream> — the fixture "global install" on branch
# main, tracking origin/main (a developer's checkout, `--ref main`).
su_clone_global_branch() {
  local upstream="$1" share bin
  share=$(su_share)
  bin=$(su_bin)
  mkdir -p "$(dirname "$share")"
  git clone -q "$upstream" "$share"
  mkdir -p "$bin"
  ln -s "../share/jig/scripts/jig" "$bin/jig"
}

# su_init_project <source> <project> [jig-init-args...] — a project
# initialised from <source> via the real jig (setup only; not itself under
# test). Uses $JIG_BIN directly, never PATH, so su_path's fixture PATH plays
# no part in building the fixture.
su_init_project() {
  local source="$1" proj="$2"
  shift 2
  mkdir -p "$proj"
  (
    cd "$proj" || exit 1
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    printf '# project\n' > README.md
    git add README.md
    git commit -q -m init
    jig init --from "$source" "$@" >/dev/null
  )
}

# su_tree_digest <dir> — one hash summarising every file's content under
# <dir>, order-independent of mtime/mode: sorted paths, each blob-hashed,
# the list of hashes hashed again. Used to prove a copy-mode project's
# installed files are byte-identical before and after self-update (AC-08).
su_tree_digest() {
  (cd "$1" && find . -type f | LC_ALL=C sort | xargs -n1 git hash-object) | git hash-object --stdin
}

# --- AC-01: detached checkout, release-tag channel --------------------------

test_self_update_detached_updates_to_newer_release_tag() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0

  su_commit_release "$HOME/work" 0.2.0
  su_push "$HOME/work"

  run su_jig self-update
  assert_eq 0 "$RC" "self-update should succeed: $OUT"
  assert_contains "$OUT" "self-update: updated 0.1.0 -> 0.2.0"

  local share head tag_commit
  share=$(su_share)
  head=$(git -C "$share" rev-parse HEAD)
  tag_commit=$(git -C "$share" rev-parse 'v0.2.0^{commit}')
  assert_eq "$tag_commit" "$head" "HEAD must land exactly on the new release tag"

  run su_jig version
  assert_contains "$OUT" "jig 0.2.0"
}

test_self_update_detached_rerun_reports_already_current() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0

  run su_jig self-update
  assert_eq 0 "$RC"
  assert_contains "$OUT" "self-update: already current at 0.1.0 ("

  local share head_before head_after
  share=$(su_share)
  head_before=$(git -C "$share" rev-parse HEAD)
  run su_jig self-update
  assert_eq 0 "$RC"
  assert_contains "$OUT" "self-update: already current at 0.1.0 ("
  head_after=$(git -C "$share" rev-parse HEAD)
  assert_eq "$head_before" "$head_after" "a repeat self-update must not move HEAD"
}

# A tag that is numerically older but lexically larger (0.9.0 vs 0.10.0) must
# never be picked: version.sh's ordering is field-by-field arithmetic, not
# string comparison (design.md section 3; AC-01).
test_self_update_detached_ignores_lexically_larger_older_tag() {
  su_build_source "$HOME/work"
  su_commit_release "$HOME/work" 0.10.0
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.10.0

  su_commit_release "$HOME/work" 0.9.0
  su_push "$HOME/work"

  run su_jig self-update
  assert_eq 0 "$RC" "self-update should succeed: $OUT"
  assert_contains "$OUT" "self-update: already current at 0.10.0 ("

  local share head
  share=$(su_share)
  head=$(git -C "$share" rev-parse HEAD)
  assert_eq "$(git -C "$share" rev-parse 'v0.10.0^{commit}')" "$head" \
    "a numerically older tag must never be selected"
}

test_self_update_detached_ignores_prerelease_tag() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0

  (cd "$HOME/work" && git tag -a v0.2.0-rc1 -m rc1)
  su_push "$HOME/work"

  run su_jig self-update
  assert_eq 0 "$RC" "self-update should succeed: $OUT"
  assert_contains "$OUT" "self-update: already current at 0.1.0 ("
}

# A tag whose content disagrees with its own name must be caught, not
# silently installed (design AC-01: "jig_version_of <global> must equal the
# tag's version; otherwise print the discrepancy ... and exit non-zero").
test_self_update_detached_tag_version_mismatch_fails() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0

  su_set_version "$HOME/work" 9.9.9
  (cd "$HOME/work" && git add -A && git commit -q -m "mislabeled release" && git tag -a v0.3.0 -m v0.3.0)
  su_push "$HOME/work"

  local share release_commit
  share=$(su_share)
  release_commit=$(git -C "$share" rev-parse HEAD)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must fail on a tag/version mismatch: $OUT"
  assert_contains "$OUT" "v0.3.0 reports version 9.9.9 (expected 0.3.0); staying at 0.1.0"
  # The checkout goes back to the release it came from: left on the bad tag,
  # the next run would read it as current and report nothing wrong.
  assert_eq "$release_commit" "$(git -C "$share" rev-parse HEAD)" "HEAD must return to v0.1.0"

  run su_jig self-update
  [ "$RC" != 0 ] || fail "a second run must report the mismatch again, not 'already current': $OUT"
  assert_not_contains "$OUT" "already current"
}

# --- AC-01a: branch channel, and detached-but-not-a-release refusal --------

test_self_update_branch_with_upstream_fast_forwards() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_branch "$HOME/upstream.git"

  su_commit_release "$HOME/work" 0.2.0
  su_push "$HOME/work"

  run su_jig self-update
  assert_eq 0 "$RC" "self-update should succeed: $OUT"
  assert_contains "$OUT" "self-update: updated 0.1.0 -> 0.2.0"

  local share
  share=$(su_share)
  assert_eq "$(git -C "$HOME/work" rev-parse HEAD)" "$(git -C "$share" rev-parse HEAD)" \
    "a branch checkout must fast-forward to the pushed commit"
  assert_eq "refs/heads/main" "$(git -C "$share" symbolic-ref HEAD)" "must stay on the branch"
}

test_self_update_branch_fast_forward_reports_version_unchanged() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_branch "$HOME/upstream.git"

  su_commit_plain "$HOME/work" unrelated
  su_push "$HOME/work"

  run su_jig self-update
  assert_eq 0 "$RC" "self-update should succeed: $OUT"
  assert_contains "$OUT" "self-update: source updated, version unchanged at 0.1.0 ("
}

test_self_update_detached_at_non_release_commit_is_refused() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_branch "$HOME/upstream.git"
  local share
  share=$(su_share)
  # main's tip is the v0.1.0-tagged commit itself; add one more, untagged,
  # commit so detaching HEAD lands somewhere that is genuinely not a release.
  (cd "$share" && printf 'untagged\n' > untagged.txt && git add untagged.txt \
     && git commit -q -m untagged && git checkout -q --detach HEAD)

  local head_before status_before
  head_before=$(git -C "$share" rev-parse HEAD)
  status_before=$(git -C "$share" status --porcelain)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must refuse a non-release detached commit: $OUT"
  assert_contains "$OUT" "detached at a commit that is not a release tag"

  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move"
  assert_eq "$status_before" "$(git -C "$share" status --porcelain)" "working tree must not change"
}

# --- AC-02 / AC-08: delegation from an installed project; copy mode stays
#                    pinned until an explicit `jig upgrade` -------------------

test_self_update_copy_mode_project_delegates_and_stays_pinned() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0
  su_init_project "$HOME/work" "$HOME/project"

  local digest_before
  digest_before=$(su_tree_digest "$HOME/project/.ai/scripts")

  su_commit_release "$HOME/work" 0.2.0
  su_push "$HOME/work"

  run su_installed_jig "$HOME/project" self-update
  assert_eq 0 "$RC" "delegated self-update should succeed: $OUT"
  assert_contains "$OUT" "self-update: updated 0.1.0 -> 0.2.0"

  run su_jig version
  assert_contains "$OUT" "jig 0.2.0"

  # AC-08: the copy-mode project's own installed files never moved.
  local digest_after
  digest_after=$(su_tree_digest "$HOME/project/.ai/scripts")
  assert_eq "$digest_before" "$digest_after" "a copy-mode project's files must stay pinned"

  run su_installed_jig "$HOME/project" version
  assert_contains "$OUT" "jig 0.1.0"
}

# --- AC-11: link mode acts directly, nothing to delegate to -----------------

test_self_update_link_mode_acts_without_delegation() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0
  local share
  share=$(su_share)
  su_init_project "$share" "$HOME/project" --link

  # Precondition for "nothing to delegate to": the project's installed
  # dispatcher and the global one are the same physical file (ARCHITECTURE.md,
  # install modes: link mode symlinks .ai/scripts straight into the source).
  assert_eq "$(cd -P "$share/scripts" && pwd -P)/jig" \
    "$(cd -P "$HOME/project/.ai/scripts" && pwd -P)/jig" \
    "link mode must resolve to the same executable as the global"

  su_commit_release "$HOME/work" 0.2.0
  su_push "$HOME/work"

  run su_installed_jig "$HOME/project" self-update
  assert_eq 0 "$RC" "self-update should succeed: $OUT"
  assert_contains "$OUT" "self-update: updated 0.1.0 -> 0.2.0"

  run su_installed_jig "$HOME/project" version
  assert_contains "$OUT" "jig 0.2.0"
}

# --- AC-03: negative fixtures leave HEAD and files untouched ----------------

test_self_update_refuses_dirty_tracked_change() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0
  local share
  share=$(su_share)
  printf '# dirty\n' >> "$share/scripts/lib/version.sh"

  local head_before
  head_before=$(git -C "$share" rev-parse HEAD)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must refuse a dirty checkout: $OUT"
  assert_contains "$OUT" "uncommitted changes"

  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move"
  assert_file_contains "$share/scripts/lib/version.sh" "# dirty"
}

test_self_update_refuses_dirty_untracked_file() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0
  local share
  share=$(su_share)
  printf 'scratch\n' > "$share/scratch.txt"

  local head_before
  head_before=$(git -C "$share" rev-parse HEAD)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must refuse an untracked file: $OUT"
  assert_contains "$OUT" "uncommitted changes"

  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move"
  assert_file "$share/scratch.txt"
}

test_self_update_refuses_when_source_not_a_git_checkout() {
  local plain
  plain=$(su_share)
  su_copy_framework_files "$plain"
  mkdir -p "$(su_bin)"
  ln -s "../share/jig/scripts/jig" "$(su_bin)/jig"

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must refuse a non-Git source: $OUT"
  assert_contains "$OUT" "not a git checkout"
}

test_self_update_refuses_when_nested_inside_another_worktree() {
  local outer="$HOME/outer" nested
  mkdir -p "$outer"
  (cd "$outer" && git init -q . && git symbolic-ref HEAD refs/heads/main \
     && printf 'x\n' > r.md && git add r.md && git commit -q -m init)
  nested="$outer/fw"
  su_copy_framework_files "$nested"
  (cd "$outer" && git add -A && git commit -q -m "add nested framework")
  mkdir -p "$(su_bin)"
  ln -s "$nested/scripts/jig" "$(su_bin)/jig"

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must refuse a nested worktree: $OUT"
  assert_contains "$OUT" "nested inside another git worktree"
}

test_self_update_refuses_branch_without_upstream() {
  su_build_source "$HOME/work"
  local share
  share=$(su_share)
  mkdir -p "$(dirname "$share")"
  cp -R "$HOME/work" "$share"
  mkdir -p "$(su_bin)"
  ln -s "$share/scripts/jig" "$(su_bin)/jig"

  local head_before
  head_before=$(git -C "$share" rev-parse HEAD)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must refuse a branch with no upstream: $OUT"
  assert_contains "$OUT" "no upstream"

  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move"
}

# --- AC-04: pull divergence and transport failure ---------------------------

test_self_update_branch_pull_diverged_fails_without_merge() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_branch "$HOME/upstream.git"

  su_commit_plain "$HOME/work" remote-change
  su_push "$HOME/work"

  local share
  share=$(su_share)
  (cd "$share" && printf 'local\n' > local.txt && git add local.txt && git commit -q -m "local change")

  local head_before
  head_before=$(git -C "$share" rev-parse HEAD)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must fail on divergence: $OUT"
  assert_contains "$OUT" "git pull --ff-only failed"

  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move"
  local parents
  parents=$(git -C "$share" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')
  assert_eq 2 "$parents" "no merge commit may be created (single-parent HEAD)"
}

test_self_update_branch_pull_unreachable_remote_fails() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_branch "$HOME/upstream.git"
  local share
  share=$(su_share)
  git -C "$share" remote set-url origin "$HOME/does-not-exist.git"

  local head_before
  head_before=$(git -C "$share" rev-parse HEAD)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must fail when the remote is unreachable: $OUT"
  assert_contains "$OUT" "git pull --ff-only failed"

  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move"
}

# --- no global executable ----------------------------------------------------

test_self_update_dies_when_no_global_jig_on_path() {
  # $JIG_BIN is invoked directly (an absolute path, no PATH lookup needed to
  # find it); the PATH it runs with has no `jig` entry at all, so
  # jig_global_executable's own `command -v jig` finds nothing.
  run env PATH="$(su_system_path)" "$JIG_BIN" self-update
  [ "$RC" != 0 ] || fail "self-update must fail with no global jig on PATH: $OUT"
  assert_contains "$OUT" "no global jig on PATH"
  assert_contains "$OUT" "install.sh"
}

test_self_update_refuses_untracked_file_hidden_by_git_config() {
  # status.showUntrackedFiles=no makes plain `git status --porcelain` print
  # nothing for untracked files; the clean-checkout check must not inherit it.
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0
  local share head_before
  share=$(su_share)
  git -C "$share" config status.showUntrackedFiles no
  printf 'scratch\n' > "$share/scratch.txt"
  head_before=$(git -C "$share" rev-parse HEAD)

  run su_jig self-update
  [ "$RC" != 0 ] || fail "self-update must refuse an untracked file hidden by config: $OUT"
  assert_contains "$OUT" "uncommitted changes"
  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move"
}

test_self_update_rejects_arguments() {
  su_build_source "$HOME/work"
  su_build_upstream "$HOME/work" "$HOME/upstream.git"
  su_clone_global_detached "$HOME/upstream.git" v0.1.0

  run su_jig self-update --force
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument: --force"
}
