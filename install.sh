#!/usr/bin/env bash
# Jig remote installer (design.md, task framework-self-update, section 1).
#
# Bootstraps a per-user global framework checkout and a `jig` command
# without requiring a prior clone:
#
#   curl -fsSL https://raw.githubusercontent.com/fapost-lab/jig/main/install.sh | bash
#
# Defaults: repository https://github.com/fapost-lab/jig.git, ref = the
# newest release tag, checkout $HOME/.local/share/jig (detached at that
# tag), executable $HOME/.local/bin/jig symlinked to the checkout's
# scripts/jig. Never uses sudo and never touches the caller's current
# project (no `jig init`, no read of the launch directory).
#
# Downloaded and piped straight into bash, so it must tolerate a transfer
# cut short mid-stream: every behaviour lives inside a function, and the
# file ends with a compound `if` statement that calls main "$@" — no proper
# prefix of that statement is itself a complete command, so a truncated
# file either fails to parse (an unterminated function body, heredoc, or
# this final `if`) or, at best, finishes defining functions without ever
# reaching the `if`'s body — either way, nothing it defines has run (AC-10).
set -eu
set -o pipefail

_install_die()  { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }
_install_info() { printf '%s\n' "$*"; }
_install_warn() { printf 'install.sh: warning: %s\n' "$*" >&2; }

# --- release versions and source-root check ---------------------------------
#
# Mirrors scripts/lib/common.sh's jig_release_version, jig_version_newer,
# jig_newest_release and jig_is_source_root, verbatim. install.sh runs
# before any checkout exists, so it cannot source common.sh; both copies
# are exercised against the same cases (tests/dispatcher.t.sh's AC-12 cases,
# reused in tests/install.t.sh) so they cannot silently drift apart.

# jig_release_version <tag> — the `X.Y.Z` of release tag `vX.Y.Z`. Prints
# nothing and fails for anything else: a pre-release suffix, a stray tag, a
# version with more or fewer than three fields.
jig_release_version() {
  local v a b c rest
  case "$1" in
    v*) v="${1#v}" ;;
    *) return 1 ;;
  esac
  case "$v" in
    '' | *[!0-9.]* | .* | *. | *..*) return 1 ;;
  esac
  IFS=. read -r a b c rest <<EOF
$v
EOF
  if [ -z "$a" ] || [ -z "$b" ] || [ -z "$c" ] || [ -n "$rest" ]; then
    return 1
  fi
  printf '%s\n' "$v"
}

# jig_version_newer <a> <b> — true when release version <a> (`X.Y.Z`) is
# strictly newer than <b>, comparing each field as a number: 0.10.0 is newer
# than 0.9.0. False for equal versions and for anything that is not three
# numeric fields, so an unparsable version never reads as an upgrade.
jig_version_newer() {
  local a1 a2 a3 b1 b2 b3
  jig_release_version "v$1" >/dev/null || return 1
  jig_release_version "v$2" >/dev/null || return 1
  IFS=. read -r a1 a2 a3 <<EOF
$1
EOF
  IFS=. read -r b1 b2 b3 <<EOF
$2
EOF
  # 10#: a field with a leading zero is still decimal, not octal.
  a1=$((10#$a1)); a2=$((10#$a2)); a3=$((10#$a3))
  b1=$((10#$b1)); b2=$((10#$b2)); b3=$((10#$b3))
  if [ "$a1" -ne "$b1" ]; then [ "$a1" -gt "$b1" ]; return; fi
  if [ "$a2" -ne "$b2" ]; then [ "$a2" -gt "$b2" ]; return; fi
  [ "$a3" -gt "$b3" ]
}

# jig_newest_release — read tag names on stdin, one per line, and print the
# newest release tag (`vX.Y.Z`). Accepts `git tag` names and `git ls-remote
# --tags` lines alike: a `refs/tags/` prefix and the `^{}` of a peeled
# annotated tag are stripped. Fails, printing nothing, when no line is a
# release tag.
jig_newest_release() {
  local line tag v best="" best_v=""
  while IFS= read -r line; do
    tag=${line##*refs/tags/}
    tag=${tag%'^{}'}
    v=$(jig_release_version "$tag") || continue
    if [ -z "$best_v" ] || jig_version_newer "$v" "$best_v"; then
      best="$tag"
      best_v="$v"
    fi
  done
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

# jig_is_source_root <dir> — true when <dir> is a framework source checkout.
jig_is_source_root() {
  [ -d "$1/skills" ] && [ -d "$1/templates" ] && [ -f "$1/scripts/jig" ]
}

# --- filesystem helpers ------------------------------------------------------

# _install_resolve_symlink <path> — <path> with every symlink in it resolved,
# without readlink -f (absent on older macOS). Mirrors scripts/jig's own
# jig_resolve_path, duplicated for the same reason as the functions above:
# no library exists yet to source. Uses pwd -P (not plain pwd) because the
# result is compared against other physical paths, and macOS maps /tmp to
# /private/tmp (conventions/shell.md).
_install_resolve_symlink() {
  local p="$1" dir
  while [ -L "$p" ]; do
    dir=$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P) || return 1
    p=$(readlink "$p")
    case "$p" in /*) ;; *) p="$dir/$p" ;; esac
  done
  dir=$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$p")"
}

# _install_physical_path <path> — <path> with its directory made physical;
# the path itself need not exist, only its directory.
_install_physical_path() {
  local dir
  dir=$(cd -P "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$1")"
}

# --- usage -------------------------------------------------------------------

_install_usage() {
  cat <<'EOF'
Usage: install.sh [options]

Installs Jig into a per-user location and creates a `jig` command.

Options:
  --repository <url>      Git remote to install from
                           (default: https://github.com/fapost-lab/jig.git)
  --ref <branch-or-tag>   Install this ref instead of the newest release tag.
                           Use --ref main for the development channel.
  --install-dir <dir>     Framework checkout location
                           (default: $HOME/.local/share/jig)
  --bin-dir <dir>         Where to place the jig executable
                           (default: $HOME/.local/bin)
  --no-path               Do not modify shell startup files
  --help                  Show this help and exit
EOF
}

# --- environment checks -------------------------------------------------------

_install_check_environment() {
  [ -n "${BASH_VERSION:-}" ] \
    || _install_die "this installer must be run with bash: bash install.sh, or curl ... | bash"
  [ -n "${HOME:-}" ] || _install_die "HOME is not set"
  [ -d "$HOME" ] || _install_die "HOME does not name a directory: $HOME"
  command -v git >/dev/null 2>&1 \
    || _install_die "git is required and was not found on PATH"
}

# --- ref resolution ------------------------------------------------------------

# _install_resolve_ref — sets INSTALL_REF from $REF, or from the newest
# release tag at $REPOSITORY when $REF is empty. Never falls back to a
# branch on its own: the day the first tag exists, a silent fallback would
# change what the default install-dir installs (design.md section 1).
_install_resolve_ref() {
  local ls_out ls_rc=0
  if [ -n "$REF" ]; then
    INSTALL_REF="$REF"
    return 0
  fi
  ls_out=$(git ls-remote --tags -- "$REPOSITORY" 2>&1) || ls_rc=$?
  if [ "$ls_rc" -ne 0 ]; then
    _install_die "could not reach $REPOSITORY: $ls_out"
  fi
  INSTALL_REF=$(printf '%s\n' "$ls_out" | jig_newest_release) \
    || _install_die "no release tag found at $REPOSITORY; install the development channel with --ref main"
}

# --- checkout: fresh clone or repeat-run update -------------------------------

# _install_setup_checkout — clone $REPOSITORY at $INSTALL_REF into
# $INSTALL_DIR, or update an existing, clean, correctly-tracked checkout
# already there (design.md section 1, "on repeat runs"). Sets ACTUAL_REF and
# ACTUAL_IS_RELEASE from the checkout's final state.
_install_setup_checkout() {
  if [ -e "$INSTALL_DIR" ]; then
    _install_update_checkout
  else
    _install_fresh_checkout
  fi
  jig_is_source_root "$INSTALL_DIR" \
    || _install_die "$INSTALL_DIR is not a Jig framework checkout"
  _install_describe_checkout
}

_install_fresh_checkout() {
  local parent out
  parent=$(dirname "$INSTALL_DIR")
  if [ ! -d "$parent" ]; then
    CREATED_INSTALL_PARENT=1
    INSTALL_PARENT="$parent"
  fi
  mkdir -p "$parent" || _install_die "could not create $parent"
  # Create $INSTALL_DIR itself atomically with a plain mkdir (no -p): it
  # either creates the directory, in which case nothing could have raced
  # into it between the caller's [ -e ] check and this line, or it fails
  # because something now exists there, in which case we die immediately
  # without touching it. CREATED_INSTALL_DIR is set only right after that
  # mkdir succeeds, never before, so _install_cleanup_on_failure can only
  # ever remove a directory this process itself created — never something
  # that appeared at $INSTALL_DIR in between.
  mkdir "$INSTALL_DIR" || _install_die "could not create $INSTALL_DIR"
  CREATED_INSTALL_DIR=1
  # git accepts an existing empty directory as its clone target.
  out=$(git clone --quiet --branch "$INSTALL_REF" -- "$REPOSITORY" "$INSTALL_DIR" 2>&1) \
    || _install_die "could not clone $REPOSITORY at $INSTALL_REF: $out"
}

# _install_update_checkout — the repeat-run path. Refuses, without touching
# anything, unless $INSTALL_DIR is the clean root of a checkout whose
# 'origin' is exactly $REPOSITORY (design.md: "a dirty checkout, unexpected
# remote, or conflicting file/link fails without overwrite, stash, reset or
# deletion").
_install_update_checkout() {
  local top physical origin head_ref
  [ -d "$INSTALL_DIR" ] \
    || _install_die "$INSTALL_DIR exists and is not a directory; refusing to overwrite it"
  top=$(cd "$INSTALL_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) \
    || _install_die "$INSTALL_DIR exists and is not a git checkout; refusing to overwrite it"
  top=$(cd "$top" && pwd -P)
  physical=$(cd "$INSTALL_DIR" && pwd -P)
  [ "$top" = "$physical" ] \
    || _install_die "$INSTALL_DIR is not the root of its git checkout; refusing to overwrite it"
  origin=$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null) \
    || _install_die "$INSTALL_DIR has no 'origin' remote; refusing to overwrite it"
  [ "$origin" = "$REPOSITORY" ] \
    || _install_die "$INSTALL_DIR tracks $origin, not $REPOSITORY; refusing to overwrite it"
  [ -z "$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null)" ] \
    || _install_die "$INSTALL_DIR has local changes; refusing to overwrite it"

  head_ref=$(git -C "$INSTALL_DIR" symbolic-ref -q --short HEAD 2>/dev/null || true)

  if [ -n "$REF" ]; then
    # An explicit --ref pins the channel: a repeat run must already be on
    # what it names, or it dies rather than silently switching (design.md
    # section 1, "--ref"). A named tag is a pin and is never advanced past,
    # even toward a newer release (the branch below, once confirmed
    # current, still updates normally: a branch is not a pin).
    _install_verify_ref_pin "$head_ref"
    [ -n "$head_ref" ] || return 0
  fi

  if [ -n "$head_ref" ]; then
    _install_update_branch "$head_ref"
  else
    _install_update_release_tag
  fi
}

# _install_verify_ref_pin <head_ref> — dies unless the existing checkout is
# already on what --ref ($REF) names. This installer only ever leaves a
# repeat-run checkout in one of two states: on a branch (the branch
# channel) or detached at a release tag (the tag channel); <head_ref>,
# already resolved by the caller, says which, so that alone decides the
# comparison without a separate query of what $REF names on origin (the
# simplest detection that is still correct here).
_install_verify_ref_pin() {
  local head_ref="$1" current
  if [ -n "$head_ref" ]; then
    [ "$head_ref" = "$REF" ] \
      || _install_die "$INSTALL_DIR is on branch $head_ref, not $REF; switching channels on a repeat run is not done by rerunning the installer -- remove $INSTALL_DIR or switch it by hand"
    return 0
  fi
  # Read the tags first, then match: `git ... | grep -q` under pipefail can
  # fail on a match, when grep exits before git has finished writing and git
  # dies of SIGPIPE, and a tag that is there would read as missing.
  local tags
  tags=$(git -C "$INSTALL_DIR" tag --points-at HEAD 2>/dev/null) || tags=""
  if printf '%s\n' "$tags" | grep -Fx -- "$REF" >/dev/null; then
    return 0
  fi
  current=$(printf '%s\n' "$tags" | jig_newest_release) \
    || current="a commit that is not a release tag"
  _install_die "$INSTALL_DIR is on tag $current, not $REF; switching channels on a repeat run is not done by rerunning the installer -- remove $INSTALL_DIR or switch it by hand"
}

# _install_update_branch <branch> — the branch channel (--ref main): fast
# forward only, same rule as `jig self-update`. Unlike the tag channel
# (_install_update_release_tag), a failed verification after this is not
# rolled back: undoing a `pull --ff-only` would need a reset, which the
# design forbids for state this run did not create itself.
_install_update_branch() {
  local branch="$1" out
  git -C "$INSTALL_DIR" rev-parse --abbrev-ref "$branch@{upstream}" >/dev/null 2>&1 \
    || _install_die "$INSTALL_DIR is on branch $branch with no upstream; refusing to update it"
  out=$(git -C "$INSTALL_DIR" pull --quiet --ff-only 2>&1) \
    || _install_die "could not fast-forward $INSTALL_DIR on branch $branch: $out"
}

# _install_update_release_tag — the default channel: fetch tags and move
# forward to the newest release tag, never backwards. Detached anywhere that
# is not exactly a release tag is refused rather than guessed at. Before
# checking out a newer tag, records the current commit in PREVIOUS_COMMIT
# and marks the move with MOVED_CHECKOUT=1, so a verification failure later
# in this run (_install_verify, in _install_setup_checkout's caller) can be
# rolled back by _install_cleanup_on_failure instead of leaving an
# already-existing install detached on a release that never verified.
_install_update_release_tag() {
  local current current_v newest newest_v out
  # Every tag at HEAD, newest release among them, as `jig self-update` does:
  # `git describe --exact-match` names one tag of its own choosing, which may
  # be a non-release tag sharing the commit.
  current=$(git -C "$INSTALL_DIR" tag --points-at HEAD 2>/dev/null | jig_newest_release) \
    || _install_die "$INSTALL_DIR is detached at a commit that is not a release tag; refusing to update it"
  current_v=$(jig_release_version "$current")
  out=$(git -C "$INSTALL_DIR" fetch --quiet --tags origin 2>&1) \
    || _install_die "could not fetch tags for $INSTALL_DIR: $out"
  newest=$(git -C "$INSTALL_DIR" tag --list | jig_newest_release) || newest=""
  if [ -n "$newest" ]; then
    newest_v=$(jig_release_version "$newest")
    if jig_version_newer "$newest_v" "$current_v"; then
      PREVIOUS_COMMIT=$(git -C "$INSTALL_DIR" rev-parse HEAD) \
        || _install_die "could not read the current commit in $INSTALL_DIR"
      out=$(git -C "$INSTALL_DIR" checkout --quiet --detach "$newest" 2>&1) \
        || _install_die "could not check out $newest in $INSTALL_DIR: $out"
      MOVED_CHECKOUT=1
    fi
  fi
}

# _install_describe_checkout — sets ACTUAL_REF/ACTUAL_IS_RELEASE from
# $INSTALL_DIR's actual HEAD, independent of what was requested: a repeat
# run may have moved a detached checkout to a newer tag than $INSTALL_REF
# named, and that is what verification must check against.
_install_describe_checkout() {
  local exact head_ref
  exact=$(git -C "$INSTALL_DIR" tag --points-at HEAD 2>/dev/null | jig_newest_release) || exact=""
  if [ -n "$exact" ]; then
    ACTUAL_REF="$exact"
    ACTUAL_IS_RELEASE=1
    return 0
  fi
  head_ref=$(git -C "$INSTALL_DIR" symbolic-ref -q --short HEAD 2>/dev/null || true)
  if [ -n "$head_ref" ]; then
    ACTUAL_REF="$head_ref"
  else
    ACTUAL_REF="$INSTALL_REF"
  fi
  ACTUAL_IS_RELEASE=0
}

# --- the bin-dir symlink -------------------------------------------------------

# _install_place_symlink — three outcomes for an existing $BIN_DIR/jig
# (design.md section 1): already pointing at our checkout is kept; pointing
# at a different, still-valid Jig source checkout is preserved and reported,
# never overwritten; anything else (a regular file, an unrelated or broken
# link) fails without overwriting. Nothing here is set up when $BIN_DIR/jig
# does not exist yet.
_install_place_symlink() {
  local link="$BIN_DIR/jig" resolved dir target_physical
  if [ ! -e "$BIN_DIR" ]; then
    CREATED_BIN_DIR=1
  fi
  mkdir -p "$BIN_DIR" || _install_die "could not create $BIN_DIR"

  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    _install_link_new
    CREATED_SYMLINK=1
    return 0
  fi

  if [ -L "$link" ]; then
    resolved=$(_install_resolve_symlink "$link") || resolved=""
    target_physical=$(_install_physical_path "$INSTALL_DIR/scripts/jig") \
      || _install_die "could not resolve $INSTALL_DIR/scripts/jig"
    if [ -n "$resolved" ] && [ "$resolved" = "$target_physical" ]; then
      return 0
    fi
    if [ -n "$resolved" ]; then
      dir=${resolved%/scripts/jig}
      if [ "$dir" != "$resolved" ] && jig_is_source_root "$dir"; then
        SYMLINK_ELSEWHERE=1
        _install_info "note: $link already selects another Jig checkout ($dir); left unchanged."
        return 0
      fi
    fi
    _install_die "$link already exists and does not select a Jig checkout; refusing to overwrite it"
  fi

  _install_die "$link already exists and is not a symlink; refusing to overwrite it"
}

# _install_link_new — a relative target when both directories are still at
# their defaults (siblings under $HOME/.local: it keeps working if $HOME
# itself resolves to a different absolute path later, e.g. a different
# machine or a symlinked home directory); an absolute target otherwise,
# since arbitrary --install-dir/--bin-dir values need not share a parent.
_install_link_new() {
  local target
  if [ "$INSTALL_DIR_IS_DEFAULT" = 1 ] && [ "$BIN_DIR_IS_DEFAULT" = 1 ]; then
    target="../share/jig/scripts/jig"
  else
    target=$(_install_physical_path "$INSTALL_DIR/scripts/jig") \
      || _install_die "could not resolve $INSTALL_DIR/scripts/jig"
  fi
  ln -s "$target" "$BIN_DIR/jig" || _install_die "could not create $BIN_DIR/jig"
}

# --- verification --------------------------------------------------------------

# _install_verify — runs $INSTALL_DIR/scripts/jig directly, not through
# $BIN_DIR/jig: when the symlink was preserved pointing at another checkout
# (_install_place_symlink), $BIN_DIR/jig deliberately is not ours, and
# verification is about this run's own clone, not about whatever bin-dir
# happens to select. A release tag must match exactly; a branch only needs a
# single non-empty `jig <version>` line (design.md section 1).
_install_verify() {
  local out version
  out=$("$INSTALL_DIR/scripts/jig" version 2>&1) \
    || _install_die "installed jig failed to run: $out"
  case "$out" in
    *'
'*) _install_die "installed jig printed more than one line: $out" ;;
  esac
  if [ "$ACTUAL_IS_RELEASE" = 1 ]; then
    version=$(jig_release_version "$ACTUAL_REF") \
      || _install_die "internal error: $ACTUAL_REF is not a release tag"
    [ "$out" = "jig $version" ] \
      || _install_die "installed jig reports '$out', expected 'jig $version' for $ACTUAL_REF"
  else
    case "$out" in
      'jig '?*) ;;
      *) _install_die "installed jig printed unexpected output: $out" ;;
    esac
  fi
}

# --- PATH setup ------------------------------------------------------------

# _install_startup_file — the one file PATH setup may touch, chosen from
# $SHELL the way login shells are actually configured; unknown or unset
# $SHELL falls back to .profile, which every POSIX-ish shell reads.
_install_startup_file() {
  case "$(basename "${SHELL:-}")" in
    zsh) printf '%s/.zshrc\n' "$HOME" ;;
    bash) printf '%s/.bashrc\n' "$HOME" ;;
    *) printf '%s/.profile\n' "$HOME" ;;
  esac
}

# _install_setup_path — writes nothing when $BIN_DIR is already on $PATH or
# the target startup file already mentions it (repeat runs never duplicate
# the block). The piped process cannot change its parent shell's
# environment, so both the new-terminal instruction and the command that
# works immediately are printed either way that PATH gets there.
_install_setup_path() {
  case ":$PATH:" in
    *":$BIN_DIR:"*)
      return 0
      ;;
  esac

  local rc_file
  rc_file=$(_install_startup_file)

  if [ -f "$rc_file" ] && grep -qF "$BIN_DIR" "$rc_file" 2>/dev/null; then
    return 0
  fi

  {
    printf '\n# added by the Jig installer (install.sh)\n'
    # shellcheck disable=SC2016 # $PATH must reach the file literally, expanded when the shell starts, not now
    printf 'export PATH="%s:$PATH"\n' "$BIN_DIR"
  } >> "$rc_file" || _install_die "could not update $rc_file"

  _install_info ""
  _install_info "Added $BIN_DIR to PATH in $rc_file."
  _install_info "Open a new terminal, or run this in the current one:"
  _install_info "  export PATH=\"$BIN_DIR:\$PATH\""
}

# --- failure cleanup ---------------------------------------------------------

# _install_cleanup_on_failure — removes only what this run itself created
# (design.md: never overwrite, stash, reset or delete pre-existing state).
# CREATED_* is set at the one place each thing gets created, right after
# confirming nothing was there before, so provenance is established before
# the flag exists, not re-derived here. MOVED_CHECKOUT is the one exception:
# it is not something created, but a pre-existing checkout's own HEAD moved
# forward by _install_update_release_tag; on failure it is moved back to
# PREVIOUS_COMMIT rather than deleted, so a rejected update never leaves an
# existing install wedged on a release that failed to verify. The branch
# channel (_install_update_branch) has no equivalent: undoing its `pull
# --ff-only` would need a reset, which the design forbids for state this run
# did not create. Referenced from an EXIT trap, so every variable it reads
# is script-global (conventions/shell.md), never local to main.
_install_cleanup_on_failure() {
  local rc=$?
  [ "$rc" -ne 0 ] || return 0
  if [ "${CREATED_SYMLINK:-0}" = 1 ] && [ -L "${BIN_DIR:-}/jig" ]; then
    rm -f "$BIN_DIR/jig"
  fi
  if [ "${MOVED_CHECKOUT:-0}" = 1 ] && [ -n "${PREVIOUS_COMMIT:-}" ]; then
    git -C "${INSTALL_DIR:-}" checkout -q --detach "$PREVIOUS_COMMIT" 2>/dev/null \
      || _install_warn "could not restore $INSTALL_DIR to its previous commit ($PREVIOUS_COMMIT); check it out by hand"
  fi
  if [ "${CREATED_INSTALL_DIR:-0}" = 1 ] && [ -e "${INSTALL_DIR:-}" ]; then
    rm -rf "$INSTALL_DIR"
  fi
  if [ "${CREATED_INSTALL_PARENT:-0}" = 1 ] && [ -d "${INSTALL_PARENT:-}" ]; then
    rmdir "$INSTALL_PARENT" 2>/dev/null || true
  fi
  if [ "${CREATED_BIN_DIR:-0}" = 1 ] && [ -d "${BIN_DIR:-}" ]; then
    rmdir "$BIN_DIR" 2>/dev/null || true
  fi
}

# --- entry point --------------------------------------------------------------

main() {
  _install_check_environment

  REPOSITORY="https://github.com/fapost-lab/jig.git"
  REF=""
  INSTALL_DIR="$HOME/.local/share/jig"
  BIN_DIR="$HOME/.local/bin"
  ADD_PATH=1
  INSTALL_DIR_IS_DEFAULT=1
  BIN_DIR_IS_DEFAULT=1

  while [ $# -gt 0 ]; do
    case "$1" in
      --repository)
        [ $# -ge 2 ] || _install_die "--repository requires a value"
        REPOSITORY="$2"; shift 2 ;;
      --ref)
        [ $# -ge 2 ] || _install_die "--ref requires a value"
        REF="$2"; shift 2 ;;
      --install-dir)
        [ $# -ge 2 ] || _install_die "--install-dir requires a value"
        INSTALL_DIR="$2"; INSTALL_DIR_IS_DEFAULT=0; shift 2 ;;
      --bin-dir)
        [ $# -ge 2 ] || _install_die "--bin-dir requires a value"
        BIN_DIR="$2"; BIN_DIR_IS_DEFAULT=0; shift 2 ;;
      --no-path)
        ADD_PATH=0; shift ;;
      --help)
        _install_usage; exit 0 ;;
      *)
        _install_die "unknown argument: $1 (see --help)" ;;
    esac
  done

  CREATED_INSTALL_DIR=0
  CREATED_INSTALL_PARENT=0
  INSTALL_PARENT=""
  CREATED_BIN_DIR=0
  CREATED_SYMLINK=0
  SYMLINK_ELSEWHERE=0
  MOVED_CHECKOUT=0
  PREVIOUS_COMMIT=""
  trap _install_cleanup_on_failure EXIT

  _install_resolve_ref
  _install_setup_checkout
  _install_place_symlink
  _install_verify

  if [ "$ADD_PATH" = 1 ]; then
    _install_setup_path
  fi

  if [ "$SYMLINK_ELSEWHERE" = 1 ]; then
    printf 'jig installed: %s (%s)\n' "$INSTALL_DIR" "$ACTUAL_REF"
  else
    printf 'jig installed: %s -> %s (%s)\n' "$BIN_DIR/jig" "$INSTALL_DIR" "$ACTUAL_REF"
  fi
}

# The guard lets tests source this file and exercise its functions (e.g. the
# release-ordering helpers above) without running the installer. It is part
# of this final `if`, not a separate trailing line: a bare
# `[ cond ] || main "$@"` is a complete command the instant `main "$@"` is
# fully spelled out, so a transfer truncated right after those characters
# would run the installer with default arguments instead of failing to
# parse. Written as `if`/`fi`, no proper prefix of this statement is a
# complete command, so any truncation before the closing `fi` is a syntax
# error and nothing defined above ever runs (AC-10).
if [ "${JIG_INSTALL_NO_MAIN:-}" != 1 ]; then
  main "$@"
fi
