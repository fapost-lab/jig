#!/usr/bin/env bash
# Verification for the rust profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "rust: <check>: pass|fail|skip (<note>)".
#
# Tools come from PATH only (adr-20260918-profiles-narrow-per-check-with-project-tools D2): cargo is the stack toolchain, and
# fmt/clippy are its own subcommands (`rustup component add`), never a
# project-local binary. `cargo fmt --version` and `cargo clippy --version`
# gate their checks: a missing rustup component fails that probe, not a
# missing cargo.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools; D4 rust row): a changed path is mapped to
# the crate that owns it — the nearest ancestor directory (starting at the
# path's own directory) whose Cargo.toml declares a [package]. fmt, clippy
# and test narrow identically, each with one `-p <crate>` per crate the
# change touched. A changed member Cargo.toml narrows to the crate it
# declares; the root workspace manifest (a Cargo.toml with no [package] of
# its own), Cargo.lock, .cargo/** and a rust-toolchain* pin file always run
# the full set, and so does any path outside every crate — this includes a
# changed file whose only ancestor Cargo.toml is a pure workspace manifest.
# Dependents of a changed crate are not tested locally: CI, not this
# profile, covers the rest of the workspace (ADR-0041), so the note names
# only the crates that were changed (`scope: crates a,b`), never their
# dependents.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin rust

if ! command -v cargo >/dev/null 2>&1; then
  jp_skip "fmt" "cargo not found on PATH"
  jp_skip "clippy" "cargo not found on PATH"
  jp_skip "test" "cargo not found on PATH"
  jp_end
fi

# Files whose change can alter the result of every crate's checks.
RUST_ALL_GLOBS="Cargo.lock .cargo/* rust-toolchain*"

# _rust_has_package <cargo-toml> — the manifest exists and declares
# `[package]`: a member crate manifest, not a pure workspace root.
_rust_has_package() {
  [ -f "$1" ] || return 1
  grep -q '^\[package\]' "$1"
}

# _rust_crate_name <cargo-toml> — the `name = "..."` line inside that
# manifest's own [package] section (never [workspace.package] or another
# table).
_rust_crate_name() {
  awk '
    /^\[package\]/ { insec = 1; next }
    /^\[/          { insec = 0 }
    insec && /^[[:space:]]*name[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^"|"[[:space:]]*$/, "")
      print
      exit
    }
  ' "$1"
}

# _rust_crate_dir <path> — the nearest ancestor directory (starting at
# <path>'s own directory, so a changed Cargo.toml can name its own crate)
# whose Cargo.toml declares [package]; nothing when no ancestor does, i.e.
# <path> is outside every crate. Not inlined into a `$( )`: bash 3.2
# misparses a `case`/loop written there (conventions/shell.md).
_rust_crate_dir() {
  local d
  d=$(dirname "$1")
  while :; do
    if _rust_has_package "$d/Cargo.toml"; then
      printf '%s\n' "$d"
      return 0
    fi
    if [ "$d" = "." ]; then
      return 1
    fi
    d=$(dirname "$d")
  done
}

# _rust_builtin <path> — the narrowing a changed path forces on its own,
# before the project's map has a say: ALL for the lockfile, `.cargo/`
# config or a toolchain pin, or when the path is outside every crate
# (including a pure workspace root manifest); otherwise the name of the
# crate that owns it.
_rust_builtin() {
  local f="$1" dir crate
  if jp_is_doc "$f"; then return 0; fi
  if jp_path_matches "$f" "$RUST_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  if dir=$(_rust_crate_dir "$f"); then
    crate=$(_rust_crate_name "$dir/Cargo.toml")
    if [ -n "$crate" ]; then
      printf '%s\n' "$crate"
      return 0
    fi
  fi
  printf 'ALL\n'
  return 0
}

# _rust_known_crates — every crate name a member Cargo.toml in the project
# declares, one per line. Used to validate a crate name coming from the
# project's map (D5): a name no member Cargo.toml declares is a hollow
# filter, same as a test path that does not exist.
_rust_known_crates() {
  local f
  while IFS= read -r f; do
    case "$f" in
      Cargo.toml | */Cargo.toml) ;;
      *) continue ;;
    esac
    _rust_has_package "$f" || continue
    _rust_crate_name "$f"
  done < <(jp_files)
  return 0
}

# _rust_first_unknown <crate>... — the first crate name no member Cargo.toml
# declares; nothing when every one is known. Mirrors jp_first_missing, but
# against crate names instead of paths.
_rust_first_unknown() {
  local known="" name
  known=$(_rust_known_crates)
  for name in "$@"; do
    if ! jp_has_line "$name" "$known"; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  return 1
}

# _rust_scope — fmt, clippy and test narrow identically (D4 rust row), so
# this is computed once per check rather than three separate copies of the
# same map/builtin logic. On return 0, $RUST_NOTE is the verdict suffix
# (empty for an unscoped run) and $RUST_ARGS holds the `-p <crate>` pairs to
# pass, one token per line (empty for a full run — the caller then runs
# cargo with no extra flags). On return 1 nothing changed maps to this
# check at all; $RUST_SKIP_REASON says why.
RUST_NOTE=""
RUST_ARGS=""
RUST_SKIP_REASON=""
_rust_scope() {
  RUST_NOTE=""
  RUST_ARGS=""
  RUST_SKIP_REASON=""
  jp_scoped || return 0
  local sel crates missing c
  sel=$(jp_decide _rust_builtin)
  if [ -z "$sel" ]; then
    RUST_SKIP_REASON="scope: no changed file affects this check"
    return 1
  fi
  if [ "$sel" = ALL ]; then
    RUST_NOTE=", scope: full (root manifest, lockfile, toolchain pin or a file outside any crate changed)"
    return 0
  fi
  crates="$sel"
  local IFS
  IFS='
'
  set -f
  # shellcheck disable=SC2086
  set -- $crates
  set +f
  if missing=$(_rust_first_unknown "$@"); then
    RUST_NOTE=", scope: crate '$missing' not declared, ran full set"
    return 0
  fi
  RUST_NOTE=", scope: crates $(printf '%s,' "$@" | sed 's/,$//')"
  for c in "$@"; do
    RUST_ARGS="$RUST_ARGS-p
$c
"
  done
  return 0
}

# --- cargo fmt ---------------------------------------------------------------

if cargo fmt --version >/dev/null 2>&1; then
  v=$(jp_version cargo fmt --version)
  if _rust_scope; then
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    set -- $RUST_ARGS
    set +f
    IFS=$' \t\n'
    jp_run "fmt" "$v$RUST_NOTE" cargo fmt --check "$@"
  else
    jp_skip "fmt" "$RUST_SKIP_REASON"
  fi
else
  jp_skip "fmt" "rustfmt not installed"
fi

# --- cargo clippy -------------------------------------------------------------

if cargo clippy --version >/dev/null 2>&1; then
  v=$(jp_version cargo clippy --version)
  if _rust_scope; then
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    set -- $RUST_ARGS
    set +f
    IFS=$' \t\n'
    jp_run "clippy" "$v$RUST_NOTE" cargo clippy --all-targets "$@" -- -D warnings
  else
    jp_skip "clippy" "$RUST_SKIP_REASON"
  fi
else
  jp_skip "clippy" "clippy not installed"
fi

# --- cargo test ---------------------------------------------------------------

v=$(jp_version cargo --version)
if _rust_scope; then
  IFS='
'
  set -f
  # shellcheck disable=SC2086
  set -- $RUST_ARGS
  set +f
  IFS=$' \t\n'
  jp_run "test" "$v$RUST_NOTE" cargo test "$@"
else
  jp_skip "test" "$RUST_SKIP_REASON"
fi

jp_end
