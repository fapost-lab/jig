# Tests for install.sh (design.md, task framework-self-update, section 1).
# shellcheck shell=bash
#
# No network: every "remote" is a local bare repository, always passed via
# --repository, the same pattern tests/self-update.t.sh uses. Helpers below
# are prefixed inst_.
#
# Fixture shape, all under the test's own isolated $HOME (tests/run.sh):
#   $HOME/remote.git         a bare remote built by inst_build_remote
#   $HOME/.local/share/jig   the default install-dir install.sh targets
#   $HOME/.local/bin/jig     the default bin-dir symlink install.sh creates
#
# PATH is never inherited: inst_system_path resolves a fixed set of tool
# directories from this run's own PATH and excludes any */.local/bin, so
# neither a maintainer's real ~/.local/bin/jig nor anything else ambient is
# reachable (conventions/shell.md: "a test decides its own environment").
# Tests that do not exercise PATH/startup-file behaviour pass --no-path to
# stay independent of it.

# --- fixture builders --------------------------------------------------------

# A fixed, deterministic system PATH: the directory of every tool install.sh
# or the installed scripts/jig might invoke, resolved once from this run's
# own PATH. Never the run's PATH verbatim -- that could also contain a real
# jig ahead of our fixture's.
inst_system_path() {
  local tools="bash sh git sed awk grep find cut sort mktemp cp mv rm mkdir basename dirname tr date stat paste head tail wc printf env xargs ln readlink"
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

# inst_fixture_source_tree <dir> — a minimal framework source tree at <dir>:
# the real scripts/ (so `scripts/jig version` runs for real), and skills/
# and templates/ each holding a placeholder file (jig_is_source_root only
# checks the directories exist, but an empty directory is not tracked by
# git and would silently vanish from a clone).
inst_fixture_source_tree() {
  mkdir -p "$1"
  cp -R "$JIG_HOME/scripts" "$1/scripts"
  mkdir -p "$1/skills" "$1/templates"
  touch "$1/skills/.gitkeep" "$1/templates/.gitkeep"
}

# inst_set_version <source-tree-dir> <X.Y.Z>
inst_set_version() {
  printf 'JIG_VERSION="%s"\nexport JIG_VERSION\n' "$2" > "$1/scripts/lib/version.sh"
}

# inst_build_remote <bare-dir> <tag>... — a bare repository at <bare-dir>,
# reachable only on the local filesystem so the suite never touches the
# network (AC-00). One commit per tag with scripts/lib/version.sh set to
# that tag's own version, an annotated tag per commit, all on branch main.
# The work tree used to build it is a sibling of $JIG_TEST_TMP (dot-suffixed,
# like assert.sh's _run_out), never inside it, so it cannot pollute a repo a
# test builds in its own directory.
inst_build_remote() {
  local bare="$1" work tag
  shift
  git init -q --bare "$bare"
  # A bare repo's HEAD defaults to refs/heads/master (or init.defaultBranch);
  # pushing "main" to it does not retarget HEAD, so a later `git clone` of
  # this bare repo alone would warn "remote HEAD refers to nonexistent ref"
  # and check out nothing at all.
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  work="$JIG_TEST_TMP.src"
  inst_fixture_source_tree "$work"
  (
    cd "$work" || exit 1
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    git remote add origin "$bare"
    for tag in "$@"; do
      inst_set_version "$work" "${tag#v}"
      git add -A
      git commit -q -m "$tag"
      git tag -a -m "$tag" "$tag"
    done
    git push -q origin main --tags
  )
  rm -rf "$work"
}

# inst_build_remote_no_tags <bare-dir> — a reachable remote with a commit on
# main and no tags at all (AC-00d: no release tag must fail, never install
# main by default).
inst_build_remote_no_tags() {
  local bare="$1" work
  git init -q --bare "$bare"
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  work="$JIG_TEST_TMP.src"
  inst_fixture_source_tree "$work"
  inst_set_version "$work" "0.0.0"
  (
    cd "$work" || exit 1
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    git remote add origin "$bare"
    git add -A
    git commit -q -m "no releases yet"
    git push -q origin main
  )
  rm -rf "$work"
}

# inst_push_tag <bare-dir> <tag> — clone <bare-dir>, add one more commit and
# annotated tag on top of its existing history, and push it back: models a
# release landing on an already-installed remote (AC-00a).
inst_push_tag() {
  local bare="$1" tag="$2" work
  work="$JIG_TEST_TMP.src2"
  git clone -q "$bare" "$work"
  (
    cd "$work" || exit 1
    inst_set_version "$work" "${tag#v}"
    git add -A
    git commit -q -m "$tag"
    git tag -a -m "$tag" "$tag"
    git push -q origin main --tags
  )
  rm -rf "$work"
}

# inst_push_mislabeled_tag <bare-dir> <tag> — like inst_push_tag, but the new
# commit does NOT bump scripts/lib/version.sh: its own `jig version` still
# reports the previous release, so <tag>'s name disagrees with what it
# installs (models a release tagged without bumping JIG_VERSION, on a
# remote that already has an earlier, correctly-labeled install behind it).
inst_push_mislabeled_tag() {
  local bare="$1" tag="$2" work
  work="$JIG_TEST_TMP.src3"
  git clone -q "$bare" "$work"
  (
    cd "$work" || exit 1
    git commit -q --allow-empty -m "$tag (mislabeled)"
    git tag -a -m "$tag" "$tag"
    git push -q origin main --tags
  )
  rm -rf "$work"
}

# inst_git_stub_dir <log-file> — a directory holding a `git` script that
# appends its arguments to <log-file> and exits 1 instead of doing anything
# real; prints the directory. Prepended to PATH, it proves a script never
# invoked git at all (AC-10): a truncated install.sh that wrongly reached
# `main` would try to clone the default GitHub repository, which is both
# unreachable in this sandboxed suite and slow to fail over the network --
# the stub makes that mistake instant, network-free and observable in the
# log instead.
inst_git_stub_dir() {
  local log="$1" dir="$JIG_TEST_TMP.gitstub"
  mkdir -p "$dir"
  cat > "$dir/git" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$log"
exit 1
STUB
  chmod +x "$dir/git"
  printf '%s\n' "$dir"
}

inst_share() { printf '%s/.local/share/jig\n' "$HOME"; }
inst_bin() { printf '%s/.local/bin\n' "$HOME"; }

# inst_global_jig — the executable install.sh actually put where a user's
# PATH would find it: the bin-dir symlink when `ln -s` made one, or the
# checkout's own scripts/jig otherwise (install.sh's no-symlink fallback,
# _install_symlinks_work). Tests that only care "the installed jig runs and
# reports the right version" use this instead of assuming the bin-dir symlink
# always exists, so they pass unmodified whether or not this machine can make
# a symlink -- on Windows Git Bash, production installs never get the
# symlink, so these tests must exercise that real path, not skip it.
inst_global_jig() {
  if [ -e "$(inst_bin)/jig" ]; then
    printf '%s/jig\n' "$(inst_bin)"
  else
    printf '%s/scripts/jig\n' "$(inst_share)"
  fi
}

# inst_path_dir — the directory install.sh put on PATH for this install: the
# bin dir when the symlink exists, the checkout's own physical scripts/
# otherwise (PATH_DIR in install.sh, made physical there via
# _install_physical_path).
inst_path_dir() {
  if [ -e "$(inst_bin)/jig" ]; then
    inst_bin
  else
    (cd -P "$(inst_share)/scripts" && pwd -P)
  fi
}

# inst_predict_path_dir — inst_path_dir's answer, but usable *before*
# install.sh has ever run: a "skips when already on PATH / already mentioned"
# test has to pre-seed that state ahead of the install, when $(inst_share)
# does not exist yet and inst_path_dir's own `cd -P` would fail. Probes
# whether `ln -s` makes a real symlink here -- the same check install.sh's
# own _install_symlinks_work makes -- and predicts the bin dir when it does,
# the checkout's would-be scripts/ dir otherwise, built as a string
# concatenation onto $(inst_share) (consistent with inst_share itself, which
# never resolves physically either) rather than by cd -P into a directory
# that may not exist yet.
inst_predict_path_dir() {
  local probe linked=0
  probe=$(mktemp -d "${TMPDIR:-/tmp}/jig-inst-predict.XXXXXX") || return 1
  mkdir "$probe/target" || { rm -rf "$probe"; return 1; }
  if ln -s "$probe/target" "$probe/link" 2>/dev/null && [ -L "$probe/link" ]; then
    linked=1
  fi
  rm -rf "$probe"
  if [ "$linked" -eq 1 ]; then
    inst_bin
  else
    printf '%s/scripts\n' "$(inst_share)"
  fi
}

# --- AC-00: fresh install through the documented one-liner -------------------

test_install_fresh_via_piped_bash() {
  skip_unless_symlinks
  inst_build_remote "$PWD/remote.git" v0.1.0

  run bash -c 'cat "$JIG_HOME/install.sh" | bash -s -- --repository "'"$PWD"'/remote.git" --no-path'
  assert_eq 0 "$RC" "install should succeed: $OUT"
  assert_contains "$OUT" "jig installed"

  assert_dir "$(inst_share)"
  assert_symlink "$(inst_bin)/jig"
  # Not a literal-text comparison: Cygwin's readlink answers a relative link
  # with a different (but still correct) spelling — seen in CI as
  # "../../../../../../../runneradmin/AppData/Local/Temp/jig-test.X/.local/share/jig/scripts/jig"
  # instead of "../share/jig/scripts/jig" — because it renders the link
  # relative to a different base than plain POSIX readlink. The invariant
  # this test protects is "defaults are siblings under $HOME/.local: the
  # link must be relative", so assert that (not absolute) and that it still
  # resolves, physically, to the installed jig.
  local link_text target target_dir resolved expected
  link_text=$(readlink "$(inst_bin)/jig")
  case "$link_text" in
    /*) fail "defaults are siblings under \$HOME/.local: the link must be relative: $link_text" ;;
  esac
  # A relative target resolves against the directory holding the link, not
  # cwd; make it physical the way the scripts do (jig_physical_path,
  # common.sh): cd -P into its directory, then append the basename.
  target="$(inst_bin)/$link_text"
  target_dir=$(cd -P "${target%/*}" 2>/dev/null && pwd -P) \
    || fail "symlink target directory does not exist: $target"
  resolved="$target_dir/${target##*/}"
  expected="$(cd -P "$(inst_share)/scripts" && pwd -P)/jig"
  assert_eq "$expected" "$resolved" \
    "relative link must resolve to the installed jig: $link_text"

  run "$(inst_bin)/jig" version
  assert_eq 0 "$RC"
  assert_eq "jig 0.1.0" "$OUT"
}

test_install_direct_invocation_matches_piped_result() {
  inst_build_remote "$PWD/remote.git" v0.1.0

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "install should succeed: $OUT"

  run "$(inst_global_jig)" version
  assert_eq "jig 0.1.0" "$OUT"
}

# Non-default --install-dir and --bin-dir need not share a parent, so the
# link between them cannot be relative (_install_link_new): it must be
# absolute, and that absolute target must still resolve to the checkout.
test_install_custom_dirs_use_absolute_symlink() {
  skip_unless_symlinks
  inst_build_remote "$PWD/remote.git" v0.1.0
  local install_dir="$HOME/custom/share-jig" bin_dir="$HOME/custom/bin-jig"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" \
    --install-dir "$install_dir" --bin-dir "$bin_dir" --no-path
  assert_eq 0 "$RC" "install should succeed: $OUT"

  assert_symlink "$bin_dir/jig"
  case "$(readlink "$bin_dir/jig")" in
    /*) ;;
    *) fail "a non-default install-dir/bin-dir pair must produce an absolute symlink target: $(readlink "$bin_dir/jig")" ;;
  esac
  run "$bin_dir/jig" version
  assert_eq "jig 0.1.0" "$OUT" "the absolute symlink must resolve to the installed checkout"
}

# --- Windows Git Bash: `ln -s` copies instead of linking ---------------------

test_install_copying_symlinks_falls_back_to_the_physical_scripts_dir() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  local lndir
  lndir=$(stub_ln_copy_dir)
  export PATH
  PATH="$lndir:$(inst_system_path)"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "install should still succeed: $OUT"
  assert_no_file "$(inst_bin)/jig"

  local expected_dir
  expected_dir=$(cd -P "$(inst_share)/scripts" && pwd -P)
  assert_contains "$OUT" "add $expected_dir to PATH"

  run "$(inst_share)/scripts/jig" version
  assert_eq 0 "$RC"
  assert_eq "jig 0.1.0" "$OUT"

  # A repeat run is a no-op, not a retry that tries (and fails) to link.
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "repeat run should still succeed: $OUT"
  assert_no_file "$(inst_bin)/jig"
}

test_install_copying_symlinks_adds_scripts_dir_to_path_once() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/usr/bin/zsh
  local lndir
  lndir=$(stub_ln_copy_dir)
  export PATH
  PATH="$lndir:$(inst_system_path)"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "install should succeed: $OUT"

  local expected_dir
  expected_dir=$(cd -P "$(inst_share)/scripts" && pwd -P)
  assert_file_contains "$HOME/.zshrc" "$expected_dir"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "repeat run should succeed: $OUT"

  grep -c -- "$expected_dir" "$HOME/.zshrc" > "$JIG_TEST_TMP.count"
  assert_eq "1" "$(cat "$JIG_TEST_TMP.count")" "the PATH entry must not be duplicated"
}

# --- AC-00a: idempotent repeat runs ------------------------------------------

test_install_repeat_run_is_a_no_op_at_the_same_tag() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC"
  local head_before head_after
  head_before=$(git -C "$(inst_share)" rev-parse HEAD)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "repeat run should succeed: $OUT"
  head_after=$(git -C "$(inst_share)" rev-parse HEAD)
  assert_eq "$head_before" "$head_after" "a repeat run at the same tag must not move HEAD"

  run "$(inst_global_jig)" version
  assert_eq "jig 0.1.0" "$OUT"
}

test_install_repeat_run_moves_to_a_newly_pushed_tag() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC"

  inst_push_tag "$PWD/remote.git" v0.2.0

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "repeat run should move forward: $OUT"

  run "$(inst_global_jig)" version
  assert_eq "jig 0.2.0" "$OUT"
  git -C "$(inst_share)" describe --tags --exact-match HEAD > "$JIG_TEST_TMP.tag"
  assert_eq "v0.2.0" "$(cat "$JIG_TEST_TMP.tag")"
}

test_install_repeat_run_preserves_a_dirty_checkout() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC"

  local share head_before
  share=$(inst_share)
  head_before=$(git -C "$share" rev-parse HEAD)
  printf 'local change\n' >> "$share/scripts/lib/version.sh"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  [ "$RC" != 0 ] || fail "a dirty checkout must refuse the update: $OUT"

  assert_contains "$(git -C "$share" status --porcelain)" "version.sh"
  assert_eq "$head_before" "$(git -C "$share" rev-parse HEAD)" "HEAD must not move on refusal"
}

test_install_repeat_run_refuses_a_different_remote() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  inst_build_remote "$PWD/other-remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC"

  git -C "$(inst_share)" remote set-url origin "$PWD/other-remote.git"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  [ "$RC" != 0 ] || fail "a checkout tracking a different remote must refuse: $OUT"
  # Not a literal-text comparison: git.exe on Windows stores (and echoes
  # back) a converted spelling of the path, e.g.
  # "C:/Users/RUNNER~1/.../other-remote.git" instead of "$PWD/other-remote.git",
  # even though both name the same directory. Compare physical directories,
  # the way the scripts do (conventions/shell.md), so the assertion still
  # means what it says: the refused run must not change origin.
  assert_eq \
    "$(cd -P "$PWD/other-remote.git" && pwd -P)" \
    "$(cd -P "$(git -C "$(inst_share)" remote get-url origin)" && pwd -P)" \
    "a refused install must not change origin"
}

test_install_repeat_run_refuses_conflicting_bin_dir_file_and_cleans_up() {
  skip_unless_symlinks
  inst_build_remote "$PWD/remote.git" v0.1.0
  mkdir -p "$(inst_bin)"
  printf 'not jig\n' > "$(inst_bin)/jig"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  [ "$RC" != 0 ] || fail "a conflicting bin-dir file must refuse: $OUT"

  assert_eq "not jig" "$(cat "$(inst_bin)/jig")"
  assert_no_file "$(inst_share)" "a failed install must remove the checkout it just cloned"
}

test_install_repeat_run_preserves_another_valid_checkout_linked() {
  skip_unless_symlinks
  inst_build_remote "$PWD/remote.git" v0.1.0
  inst_fixture_source_tree "$HOME/other-jig"
  mkdir -p "$(inst_bin)"
  ln -s "$HOME/other-jig/scripts/jig" "$(inst_bin)/jig"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "another valid checkout must be preserved, not treated as a conflict: $OUT"
  assert_contains "$OUT" "already selects another Jig checkout"

  assert_eq "$HOME/other-jig/scripts/jig" "$(readlink "$(inst_bin)/jig")" \
    "the pre-existing link must be left exactly as it was"
  assert_dir "$(inst_share)"
  run "$(inst_share)/scripts/jig" version
  assert_eq "jig 0.1.0" "$OUT"
}

# A repeat run that moves an existing checkout forward must not leave it on
# a tag whose own `jig version` disagrees with the tag's name: verification
# runs after the checkout, and a failure there must roll the checkout back
# to the commit it was on before this run touched it, not wedge the install.
test_install_repeat_run_tag_mismatch_rolls_back_and_stays_failing() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC"
  local head_v1
  head_v1=$(git -C "$(inst_share)" rev-parse HEAD)

  inst_push_mislabeled_tag "$PWD/remote.git" v0.2.0

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  [ "$RC" != 0 ] || fail "a tag/version mismatch on a repeat run must fail: $OUT"
  assert_not_contains "$OUT" "jig installed"
  assert_eq "$head_v1" "$(git -C "$(inst_share)" rev-parse HEAD)" \
    "a failed repeat-run update must roll the checkout back to its previous commit"
  run "$(inst_global_jig)" version
  assert_eq "jig 0.1.0" "$OUT"

  # A third run must retry the same update and fail the same way, never
  # read the rolled-back state as if the bad tag were now accepted.
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  [ "$RC" != 0 ] || fail "a third run must still fail rather than report success: $OUT"
  assert_not_contains "$OUT" "jig installed"
  assert_eq "$head_v1" "$(git -C "$(inst_share)" rev-parse HEAD)"
}

# --- AC-00b: PATH setup -------------------------------------------------------

test_install_path_appends_zshrc_for_zsh() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/usr/bin/zsh
  export PATH
  PATH=$(inst_system_path)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "install should succeed: $OUT"

  assert_file_contains "$HOME/.zshrc" "$(inst_path_dir)"
  assert_no_file "$HOME/.bashrc"
  assert_no_file "$HOME/.profile"
  assert_contains "$OUT" "new terminal"
}

test_install_path_appends_bashrc_for_bash() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/bin/bash
  export PATH
  PATH=$(inst_system_path)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "install should succeed: $OUT"

  assert_file_contains "$HOME/.bashrc" "$(inst_path_dir)"
  assert_no_file "$HOME/.zshrc"
  assert_no_file "$HOME/.profile"
}

test_install_path_falls_back_to_profile_for_other_shells() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/bin/tcsh
  export PATH
  PATH=$(inst_system_path)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "install should succeed: $OUT"

  assert_file_contains "$HOME/.profile" "$(inst_path_dir)"
  assert_no_file "$HOME/.zshrc"
  assert_no_file "$HOME/.bashrc"
}

test_install_path_skips_when_bin_dir_already_on_path() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/usr/bin/zsh
  export PATH
  # Whichever directory this install will actually put on PATH (the bin dir
  # when `ln -s` works here, the physical scripts dir otherwise) -- not
  # unconditionally $(inst_bin): without symlinks install.sh puts the scripts
  # dir on PATH regardless of whether the bin dir is already there, and a
  # fixture that only pre-seeded the bin dir was silently missing that case
  # (CI: a startup file got written that this test expected to stay absent).
  PATH="$(inst_predict_path_dir):$(inst_system_path)"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "install should succeed: $OUT"

  assert_no_file "$HOME/.zshrc"
  assert_no_file "$HOME/.bashrc"
  assert_no_file "$HOME/.profile"
}

test_install_path_skips_when_startup_file_already_mentions_bin_dir() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/usr/bin/zsh
  export PATH
  PATH=$(inst_system_path)
  # Pre-seed the startup file with whatever directory this install will
  # actually put on PATH (see test_install_path_skips_when_bin_dir_already_on_path
  # for why this must not be unconditionally $(inst_bin)).
  # shellcheck disable=SC2016 # $PATH is meant to stay literal in the file
  printf '# manually configured\nexport PATH="%s:$PATH"\n' "$(inst_predict_path_dir)" > "$HOME/.zshrc"
  local before
  before=$(cat "$HOME/.zshrc")

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "install should succeed: $OUT"
  assert_eq "$before" "$(cat "$HOME/.zshrc")" "an existing mention must not be duplicated or altered"
}

test_install_no_path_flag_writes_no_startup_file() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/usr/bin/zsh
  export PATH
  PATH=$(inst_system_path)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "install should succeed: $OUT"

  assert_no_file "$HOME/.zshrc"
  assert_no_file "$HOME/.bashrc"
  assert_no_file "$HOME/.profile"
}

test_install_path_rerun_does_not_duplicate_the_entry() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  export SHELL=/usr/bin/zsh
  export PATH
  PATH=$(inst_system_path)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC"
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git"
  assert_eq 0 "$RC" "repeat run should succeed: $OUT"

  grep -c -- "$(inst_path_dir)" "$HOME/.zshrc" > "$JIG_TEST_TMP.count"
  assert_eq "1" "$(cat "$JIG_TEST_TMP.count")"
}

# --- AC-00c: failure never touches the caller's project, and never claims success

test_install_from_inside_a_separate_project_leaves_it_untouched() {
  local root="$PWD" bare="$PWD/remote.git" before after
  inst_build_remote "$bare" v0.1.0
  mkdir -p project
  (cd project && fixture_repo)
  before=$(cd project && git status --porcelain)

  cd project
  run bash "$JIG_HOME/install.sh" --repository "$bare" --no-path
  cd "$root"

  assert_eq 0 "$RC" "install should still succeed: $OUT"
  assert_no_file "project/.ai"
  after=$(cd project && git status --porcelain)
  assert_eq "$before" "$after" "the launch directory's project must be untouched"
}

test_install_unreachable_repository_fails_without_side_effects() {
  run bash "$JIG_HOME/install.sh" --repository "$HOME/does-not-exist.git" --no-path
  [ "$RC" != 0 ] || fail "an unreachable repository must fail: $OUT"
  assert_not_contains "$OUT" "jig installed"
  assert_no_file "$(inst_share)"
  assert_no_file "$(inst_bin)/jig"
}

test_install_nonexistent_ref_fails_without_side_effects() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref no-such-branch-or-tag --no-path
  [ "$RC" != 0 ] || fail "a ref that does not exist must fail: $OUT"
  assert_not_contains "$OUT" "jig installed"
  assert_no_file "$(inst_share)"
  assert_no_file "$(inst_bin)/jig"
}

# A tag whose commit disagrees with its own name must be caught, not
# silently installed (mirrors self-update's AC-01 tag/version-mismatch case).
test_install_tag_version_mismatch_fails_without_side_effects() {
  local bare="$PWD/remote.git" work="$JIG_TEST_TMP.src"
  git init -q --bare "$bare"
  inst_fixture_source_tree "$work"
  (
    cd "$work" || exit 1
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    git remote add origin "$bare"
    inst_set_version "$work" "0.1.0"
    git add -A
    git commit -q -m v0.1.0
    git tag -a -m v0.1.0 v0.1.0
    # v0.5.0 is the newest tag but its content was never bumped: install.sh
    # must refuse it rather than install a mislabelled release.
    git commit -q --allow-empty -m "v0.5.0 (mislabeled)"
    git tag -a -m v0.5.0 v0.5.0
    git push -q origin main --tags
  )
  rm -rf "$work"

  run bash "$JIG_HOME/install.sh" --repository "$bare" --no-path
  [ "$RC" != 0 ] || fail "a tag/version mismatch must fail: $OUT"
  assert_contains "$OUT" "expected 'jig 0.5.0'"
  assert_not_contains "$OUT" "jig installed"
  assert_no_file "$(inst_share)"
  assert_no_file "$(inst_bin)/jig"
}

# --- AC-00d: release ordering and channel selection --------------------------

test_install_picks_the_numerically_highest_release_tag() {
  inst_build_remote "$PWD/remote.git" v0.1.0 v0.9.0 v0.10.0 v1.0.0-rc1
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "install should succeed: $OUT"
  run "$(inst_global_jig)" version
  assert_eq "jig 0.10.0" "$OUT"
}

test_install_with_no_release_tag_fails_naming_ref_main() {
  inst_build_remote_no_tags "$PWD/remote.git"
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  [ "$RC" != 0 ] || fail "no release tag must fail rather than silently install main: $OUT"
  assert_contains "$OUT" "--ref main"
  assert_no_file "$(inst_share)"
}

test_install_ref_main_installs_the_branch() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref main --no-path
  assert_eq 0 "$RC" "install should succeed: $OUT"

  git -C "$(inst_share)" symbolic-ref --short HEAD > "$JIG_TEST_TMP.branch"
  assert_eq "main" "$(cat "$JIG_TEST_TMP.branch")"
  run "$(inst_global_jig)" version
  case "$OUT" in
    'jig '?*) ;;
    *) fail "branch install must still print jig <version>: $OUT" ;;
  esac
}

test_install_ref_explicit_tag_installs_that_tag() {
  inst_build_remote "$PWD/remote.git" v0.1.0 v0.9.0 v1.0.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref v0.9.0 --no-path
  assert_eq 0 "$RC" "install should succeed: $OUT"

  git -C "$(inst_share)" describe --tags --exact-match HEAD > "$JIG_TEST_TMP.tag"
  assert_eq "v0.9.0" "$(cat "$JIG_TEST_TMP.tag")"
  run "$(inst_global_jig)" version
  assert_eq "jig 0.9.0" "$OUT"
}

# --ref names a channel; a repeat run does not switch it. Installed at a
# release tag, a rerun asking for the branch channel must refuse rather than
# silently keep doing the tag-channel update it would do without --ref.
test_install_ref_repeat_run_refuses_switching_from_tag_to_branch() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC"
  local head_before
  head_before=$(git -C "$(inst_share)" rev-parse HEAD)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref main --no-path
  [ "$RC" != 0 ] || fail "switching from a tag to a branch on a repeat run must fail: $OUT"
  assert_contains "$OUT" "v0.1.0" "the message must name the current tag"
  assert_eq "$head_before" "$(git -C "$(inst_share)" rev-parse HEAD)" "HEAD must not move on refusal"
}

# The reverse: installed on the branch channel, a rerun asking for a tag
# must refuse rather than fast-forwarding the branch as if --ref were absent.
test_install_ref_repeat_run_refuses_switching_from_branch_to_tag() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref main --no-path
  assert_eq 0 "$RC"
  local head_before
  head_before=$(git -C "$(inst_share)" rev-parse HEAD)

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref v0.1.0 --no-path
  [ "$RC" != 0 ] || fail "switching from a branch to a tag on a repeat run must fail: $OUT"
  assert_contains "$OUT" "main" "the message must name the current branch"
  assert_eq "$head_before" "$(git -C "$(inst_share)" rev-parse HEAD)" "HEAD must not move on refusal"
}

# An explicit tag pin is never advanced, even to a newer release, as long as
# --ref keeps naming it; dropping --ref resumes the normal forward movement.
test_install_ref_explicit_tag_pin_is_not_advanced_until_ref_dropped() {
  inst_build_remote "$PWD/remote.git" v0.1.0 v0.9.0
  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref v0.9.0 --no-path
  assert_eq 0 "$RC"

  inst_push_tag "$PWD/remote.git" v0.10.0

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --ref v0.9.0 --no-path
  assert_eq 0 "$RC" "a repeat run pinned to its own current tag must succeed: $OUT"
  run "$(inst_global_jig)" version
  assert_eq "jig 0.9.0" "$OUT" "an explicit tag pin must not advance even when a newer release exists"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  assert_eq 0 "$RC" "dropping --ref must resume normal forward movement: $OUT"
  run "$(inst_global_jig)" version
  assert_eq "jig 0.10.0" "$OUT"
}

# --- AC-10: a truncated download executes nothing ----------------------------

test_install_truncated_download_executes_nothing() {
  local len frac n
  len=$(wc -c < "$JIG_HOME/install.sh")
  for frac in 100 20 4 2 1; do
    n=$((len / frac))
    [ "$n" -gt 0 ] || n=1
    rm -rf "$HOME/.local" "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"
    set +e
    head -c "$n" "$JIG_HOME/install.sh" | env HOME="$HOME" PATH="$(inst_system_path)" bash >/dev/null 2>&1
    set -e
    assert_no_file "$HOME/.local" "a $n-byte prefix must not create $HOME/.local"
    assert_no_file "$HOME/.zshrc" "a $n-byte prefix must not touch shell startup files"
    assert_no_file "$HOME/.bashrc"
    assert_no_file "$HOME/.profile"
  done
}

# The final `if` guarding main "$@" is the part of the file most exposed to
# an off-by-a-few-bytes truncation: check every prefix length near the very
# end (the whole final `if` block plus a margin before it), not only the
# coarse fractions above, and prove -- not just infer from absent files --
# that git was never invoked, via a PATH-stub that records invocations.
#
# Starts at len-2, not len-1: the file's very last byte is the newline after
# the closing `fi`, and every POSIX shell treats a trailing newline as
# insignificant -- `if ... fi` (no newline) parses and runs identically to
# `if ... fi\n`. Dropping only that byte reproduces the complete script
# byte-for-semantic-byte, so it is not a truncation this installer (or any
# shell script ending in a keyword rather than raw text) could ever detect;
# len-2 is where a real prefix -- missing part of `fi` itself -- begins.
test_install_truncated_download_near_end_never_invokes_git() {
  local len n stub_log stub_dir
  len=$(wc -c < "$JIG_HOME/install.sh")
  stub_log="$JIG_TEST_TMP.gitstub.log"
  : > "$stub_log"
  stub_dir=$(inst_git_stub_dir "$stub_log")

  n=$((len - 2))
  while [ "$n" -ge $((len - 40)) ] && [ "$n" -gt 0 ]; do
    rm -rf "$HOME/.local" "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"
    : > "$stub_log"
    set +e
    head -c "$n" "$JIG_HOME/install.sh" \
      | env HOME="$HOME" PATH="$stub_dir:$(inst_system_path)" bash >/dev/null 2>&1
    set -e
    assert_no_file "$HOME/.local" "a $n-byte prefix must not create $HOME/.local"
    assert_no_file "$HOME/.zshrc" "a $n-byte prefix must not touch shell startup files"
    assert_no_file "$HOME/.bashrc"
    assert_no_file "$HOME/.profile"
    assert_eq "" "$(cat "$stub_log")" "a $n-byte prefix must never invoke git"
    n=$((n - 1))
  done
}

# --- atomic install-dir creation avoids a TOCTOU delete ----------------------
#
# _install_fresh_checkout creates $INSTALL_DIR with a plain `mkdir` (not
# `mkdir -p`) and only marks it as created after that call succeeds, so
# cleanup can never remove something that appeared there after the caller's
# own [ -e ] check.

# The observable guarantee, exercised through the whole installer: something
# already at --install-dir that is not a git checkout is refused untouched.
test_install_refuses_existing_non_git_install_dir_and_leaves_file_intact() {
  inst_build_remote "$PWD/remote.git" v0.1.0
  mkdir -p "$(inst_share)"
  printf 'pre-existing\n' > "$(inst_share)/marker"

  run bash "$JIG_HOME/install.sh" --repository "$PWD/remote.git" --no-path
  [ "$RC" != 0 ] || fail "a pre-existing non-git install-dir must refuse: $OUT"

  assert_eq "pre-existing" "$(cat "$(inst_share)/marker")" \
    "a pre-existing install-dir's contents must be left untouched"
  assert_no_file "$(inst_bin)/jig"
}

# The unit-level guarantee: _install_fresh_checkout itself, called directly
# with $INSTALL_DIR already occupied, dies at the mkdir and never reaches the
# line that sets CREATED_INSTALL_DIR=1 -- proven by a trap that reports the
# flag's value at exit, since _install_die's `exit` would otherwise skip any
# later statement in this same inline script.
test_install_fresh_checkout_dies_when_install_dir_exists() {
  local dir="$JIG_TEST_TMP.raced-install-dir"
  mkdir -p "$dir"
  printf 'pre-existing\n' > "$dir/marker"
  RACED_DIR="$dir"
  export RACED_DIR

  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  inst_lib_run 'INSTALL_DIR="$RACED_DIR"; REPOSITORY="unused"; INSTALL_REF="unused"
    CREATED_INSTALL_DIR=0; CREATED_INSTALL_PARENT=0; INSTALL_PARENT=""
    trap "echo CREATED_INSTALL_DIR=\$CREATED_INSTALL_DIR" EXIT
    _install_fresh_checkout'

  [ "$RC" != 0 ] || fail "_install_fresh_checkout must die when \$INSTALL_DIR already exists: $OUT"
  assert_contains "$OUT" "CREATED_INSTALL_DIR=0" \
    "a failed mkdir of an already-existing install-dir must never set CREATED_INSTALL_DIR"
  assert_eq "pre-existing" "$(cat "$dir/marker")" \
    "a pre-existing install-dir must be left untouched"
}

# --- AC-12: release ordering (mirrors tests/dispatcher.t.sh) -----------------
#
# install.sh runs before any checkout exists and cannot source common.sh, so
# it carries its own copy of the release-ordering helpers (see install.sh's
# own comment). These are the exact cases from tests/dispatcher.t.sh, run
# against install.sh's copy instead, pinning both to the same behavior.
# JIG_INSTALL_NO_MAIN=1 makes install.sh define its functions without running
# the installer (install.sh's own trailing guard line).

inst_lib_run() {
  run bash -c 'JIG_INSTALL_NO_MAIN=1; . "$JIG_HOME/install.sh"; '"$1"
}

test_install_release_version_accepts_only_three_numeric_fields() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  inst_lib_run 'for t in v0.1.0 v10.20.30 v01.2.3 0.1.0 v1.0.0-rc1 v1.0 v1.0.0.0 v1..0 va.b.c ""; do
      if v=$(jig_release_version "$t"); then printf "%s=%s " "$t" "$v"; else printf "%s=no " "$t"; fi
    done'
  assert_eq 0 "$RC"
  assert_eq "v0.1.0=0.1.0 v10.20.30=10.20.30 v01.2.3=01.2.3 0.1.0=no v1.0.0-rc1=no v1.0=no v1.0.0.0=no v1..0=no va.b.c=no =no " "$OUT"
}

test_install_version_newer_compares_fields_as_numbers() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  inst_lib_run 'check() { if jig_version_newer "$1" "$2"; then printf "%s>%s " "$1" "$2"; else printf "%s!>%s " "$1" "$2"; fi; }
    check 0.10.0 0.9.0; check 1.0.0 0.99.99; check 0.1.1 0.1.0; check 0.1.0 0.1.0
    check 0.9.0 0.10.0; check 08.0.0 7.0.0; check 1.0.0-rc1 0.1.0; check 0.1.0 junk'
  assert_eq 0 "$RC"
  assert_eq "0.10.0>0.9.0 1.0.0>0.99.99 0.1.1>0.1.0 0.1.0!>0.1.0 0.9.0!>0.10.0 08.0.0>7.0.0 1.0.0-rc1!>0.1.0 0.1.0!>junk " "$OUT"
}

test_install_newest_release_reads_tags_and_ls_remote_lines() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  inst_lib_run 'printf "%s\n" \
      "4e41650e	refs/tags/v0.9.0" "0b9ed917	refs/tags/v0.9.0^{}" \
      "v0.10.0" "v1.0.0-rc1" "not-a-release" "refs/tags/v0.2.0" | jig_newest_release'
  assert_eq 0 "$RC"
  assert_eq "v0.10.0" "$OUT"
}

test_install_newest_release_fails_without_a_release_tag() {
  # Unlike common.sh, install.sh itself carries `set -eu -o pipefail` (it is
  # an executable, not a library), which is now active in the sourcing
  # shell too. rc=$? must be captured through a guard, or the failing
  # pipeline would abort this inline script before it ever runs.
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  inst_lib_run 'rc=0; printf "%s\n" v1.0.0-rc1 latest | jig_newest_release || rc=$?; printf "rc=%s" "$rc"'
  assert_eq "rc=1" "$OUT"
}

# --- _install_same_repository ------------------------------------------------
#
# Unit-level, same sourcing pattern as the release-ordering tests above:
# equal strings are true outright, either side matching a URL shape makes
# it false without ever touching the filesystem, and two local paths are
# compared as the physical directories they resolve to (install.sh's own
# comment: Git for Windows stores a converted spelling of a local path).

test_install_same_repository_resolves_local_paths_physically() {
  skip_unless_symlinks
  local dir_a dir_b parent linked
  dir_a="$JIG_TEST_TMP.same-repo-a"
  dir_b="$JIG_TEST_TMP.same-repo-b"
  mkdir -p "$dir_a" "$dir_a/sub" "$dir_b"
  # A symlinked parent: the same directory reached through a differently
  # spelled path, the general case behind "Git for Windows stores a
  # converted spelling", reproducible on macOS/Linux with a plain symlink.
  parent=$(dirname "$dir_a")
  ln -s "$parent" "$JIG_TEST_TMP.same-repo-a-parent-link"
  linked="$JIG_TEST_TMP.same-repo-a-parent-link/$(basename "$dir_a")"

  SAME_A="$dir_a" SAME_A_DOTDOT="$dir_a/sub/.." SAME_A_VIA_LINK="$linked" \
    SAME_B="$dir_b" SAME_MISSING="$dir_a/does-not-exist"
  export SAME_A SAME_A_DOTDOT SAME_A_VIA_LINK SAME_B SAME_MISSING

  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  inst_lib_run 'check() { if _install_same_repository "$1" "$2"; then printf "%s==%s " "$1" "$2"; else printf "%s!=%s " "$1" "$2"; fi; }
    check "$SAME_A" "$SAME_A"
    check "$SAME_A" "$SAME_A_DOTDOT"
    check "$SAME_A" "$SAME_A_VIA_LINK"
    check "$SAME_A" "$SAME_B"
    check "$SAME_A" "$SAME_MISSING"'
  assert_eq 0 "$RC"
  assert_eq \
    "$SAME_A==$SAME_A $SAME_A==$SAME_A_DOTDOT $SAME_A==$SAME_A_VIA_LINK $SAME_A!=$SAME_B $SAME_A!=$SAME_MISSING " \
    "$OUT"
}

test_install_same_repository_treats_urls_literally_never_resolving_them() {
  local dir_b url1 url2
  dir_b="$JIG_TEST_TMP.same-repo-url-b"
  mkdir -p "$dir_b"
  url1="https://example.com/$(basename "$dir_b").git"
  url2="https://example.com/other.git"

  SAME_URL1="$url1" SAME_URL2="$url2" SAME_B="$dir_b"
  export SAME_URL1 SAME_URL2 SAME_B

  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  inst_lib_run 'check() { if _install_same_repository "$1" "$2"; then printf "%s==%s " "$1" "$2"; else printf "%s!=%s " "$1" "$2"; fi; }
    check "$SAME_URL1" "$SAME_URL1"
    check "$SAME_URL1" "$SAME_URL2"
    check "$SAME_URL1" "$SAME_B"'
  assert_eq 0 "$RC"
  # A URL matching the local path's basename still compares false: a URL is
  # compared as written, never resolved against the filesystem.
  assert_eq \
    "$SAME_URL1==$SAME_URL1 $SAME_URL1!=$SAME_URL2 $SAME_URL1!=$SAME_B " \
    "$OUT"
}
