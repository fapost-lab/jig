# Tests for the rust profile (domains/verify; profiles-scope-and-languages
# design D1/D2/D4/D5). Every check comes from `cargo`, resolved on PATH
# alone (D2), so these run the profile script directly — with
# JIG_VERIFY_SCOPE/JIG_VERIFY_FILES/JIG_VERIFY_MAPPED set the way `jig
# verify` sets them (scripts/lib/profile.sh header) — rather than through
# `jig init` + `jig verify`, the same shortcut tests/verify.t.sh takes for
# the shell profile outside a git repository. The map-filter behaviour is
# covered once through the real `jig verify --changed` path instead, so the
# core's own map parsing is exercised too, not only the profile's reading
# of JIG_VERIFY_MAPPED.
# shellcheck shell=bash

# --- no-toolchain PATH -------------------------------------------------------

# _RUST_NO_TOOLS_LIST — every tool the rust profile and the library it
# sources need when `cargo` itself is absent: bash's own shebang,
# sed/awk/grep/sort (jp_version, jp_decide, the crate-name parser) and the
# usual coreutils profile.sh's helpers call. Deliberately excludes cargo:
# the point of run_no_tools is that it is not on PATH regardless of what
# the machine running the suite happens to have installed
# (conventions/shell.md: a PATH built from an allow-list, never from
# "system directories believed tool-free").
_RUST_NO_TOOLS_LIST="bash sh sed awk grep mktemp cat cp mv rm mkdir sort tr head tail wc chmod ls date dirname basename env"

# run_no_tools <cmd...> — like `run`, but PATH is rebuilt from
# _RUST_NO_TOOLS_LIST alone, through wrapper scripts (never symlinks:
# tests/verify.t.sh's own _no_tools_fill explains why), so the rust
# profile's "cargo not found" skip path is exercised deterministically.
run_no_tools() {
  local dir out t p esc
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-rust-no-tools.XXXXXX")
  for t in $_RUST_NO_TOOLS_LIST; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*)
        esc=$(printf '%s' "$p" | sed "s/'/'\\\\''/g")
        {
          printf '#!/bin/sh\n'
          printf "exec '%s' \"\$@\"\n" "$esc"
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
  rm -rf "$dir"
  export OUT RC
}

# _rust_stub <fmt-installed> <fmt-rc> <clippy-installed> <clippy-rc> <test-rc>
# — a cargo stub on PATH. Answers `cargo --version`, `cargo fmt --version`
# and `cargo clippy --version` (the latter two failing when the matching
# *-installed flag is 0, simulating a missing rustup component), logs every
# invocation's full argument line to cargo.log (one per invocation, so a
# test can assert on the exact flags a check received), and exits with the
# given code for `fmt --check`, `clippy` or `test`.
_rust_stub() {
  local fmt_installed="$1" fmt_rc="$2" clippy_installed="$3" clippy_rc="$4" test_rc="$5"
  mkdir -p stub-bin
  cat > stub-bin/cargo <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/cargo.log"
if [ "\$1 \$2" = "fmt --version" ]; then
  if [ "$fmt_installed" = 1 ]; then
    printf 'rustfmt 1.7.0-stable (abc 2024-01-01)\n'
    exit 0
  fi
  exit 1
fi
if [ "\$1 \$2" = "clippy --version" ]; then
  if [ "$clippy_installed" = 1 ]; then
    printf 'clippy 0.1.77 (abc 2024-01-01)\n'
    exit 0
  fi
  exit 1
fi
if [ "\$1" = "--version" ]; then
  printf 'cargo 1.77.0 (abc 2024-01-01)\n'
  exit 0
fi
if [ "\$1 \$2" = "fmt --check" ]; then exit $fmt_rc; fi
if [ "\$1" = "clippy" ]; then exit $clippy_rc; fi
if [ "\$1" = "test" ]; then exit $test_rc; fi
exit 0
STUB
  chmod +x stub-bin/cargo
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _rust_workspace — a two-crate workspace: crate-a (crates/a) and crate-b
# (crates/b), plus a root workspace manifest with no [package] of its own.
_rust_workspace() {
  mkdir -p crates/a/src crates/b/src
  cat > Cargo.toml <<'EOF'
[workspace]
members = ["crates/a", "crates/b"]
EOF
  cat > crates/a/Cargo.toml <<'EOF'
[package]
name = "crate-a"
version = "0.1.0"
EOF
  printf 'pub fn a() {}\n' > crates/a/src/lib.rs
  cat > crates/b/Cargo.toml <<'EOF'
[package]
name = "crate-b"
version = "0.1.0"
EOF
  printf 'pub fn b() {}\n' > crates/b/src/lib.rs
}

# _rust_run — run the profile with whatever JIG_VERIFY_* the test already
# exported, capturing OUT/RC the way run() does, without going through
# `jig`: JIG_HOME is exported by tests/run.sh.
_rust_run() {
  run bash "$JIG_HOME/profiles/rust/verify.sh"
}

# --- detect ------------------------------------------------------------------

test_profile_rust_detected_by_cargo_toml() {
  fixture_repo
  printf '[package]\nname = "x"\nversion = "0.1.0"\n' > Cargo.toml
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "detected profiles:"
  assert_contains "$OUT" "rust"
}

test_profile_rust_not_detected_without_cargo_toml() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "rust"
}

# --- no cargo on PATH: every check skips (AC-02) -----------------------------

test_profile_rust_skips_every_check_without_cargo() {
  _rust_workspace
  run_no_tools bash "$JIG_HOME/profiles/rust/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: skip (cargo not found on PATH)"
  assert_contains "$OUT" "rust: clippy: skip (cargo not found on PATH)"
  assert_contains "$OUT" "rust: test: skip (cargo not found on PATH)"
}

# --- unscoped: pass, fail, version, missing components (AC-05) --------------

test_profile_rust_unscoped_pass_with_version_in_verdict() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  _rust_run
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: pass (rustfmt 1.7.0-stable (abc 2024-01-01))"
  assert_contains "$OUT" "rust: clippy: pass (clippy 0.1.77 (abc 2024-01-01))"
  assert_contains "$OUT" "rust: test: pass (cargo 1.77.0 (abc 2024-01-01))"
  assert_file_contains cargo.log "fmt --check"
  assert_file_contains cargo.log "clippy --all-targets -- -D warnings"
  assert_file_contains cargo.log "test"
}

test_profile_rust_unscoped_fail_on_nonzero_exit() {
  _rust_workspace
  _rust_stub 1 1 1 1 1
  _rust_run
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: fail"
  assert_contains "$OUT" "rust: clippy: fail"
  assert_contains "$OUT" "rust: test: fail"
}

test_profile_rust_skips_fmt_when_rustfmt_not_installed() {
  _rust_workspace
  _rust_stub 0 0 1 0 0
  _rust_run
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: skip (rustfmt not installed)"
  assert_contains "$OUT" "rust: clippy: pass"
  assert_contains "$OUT" "rust: test: pass"
}

test_profile_rust_skips_clippy_when_not_installed() {
  _rust_workspace
  _rust_stub 1 0 0 0 0
  _rust_run
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: pass"
  assert_contains "$OUT" "rust: clippy: skip (clippy not installed)"
  assert_contains "$OUT" "rust: test: pass"
}

# --- narrowing (D4 rust row): a changed source file narrows to its crate ----

test_profile_rust_scoped_narrows_to_owning_crate() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  printf 'crates/a/src/lib.rs\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: pass (rustfmt 1.7.0-stable (abc 2024-01-01), scope: crates crate-a)"
  assert_contains "$OUT" "rust: clippy: pass (clippy 0.1.77 (abc 2024-01-01), scope: crates crate-a)"
  assert_contains "$OUT" "rust: test: pass (cargo 1.77.0 (abc 2024-01-01), scope: crates crate-a)"
  # Exact arguments each check received: -p crate-a, nowhere else.
  assert_file_contains cargo.log "fmt --check -p crate-a"
  assert_file_contains cargo.log "clippy --all-targets -p crate-a -- -D warnings"
  assert_file_contains cargo.log "test -p crate-a"
  assert_not_contains "$(cat cargo.log)" "crate-b"
}

test_profile_rust_scoped_narrows_to_two_crates() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  printf 'crates/a/src/lib.rs\ncrates/b/src/lib.rs\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: crates crate-a,crate-b"
  assert_file_contains cargo.log "test -p crate-a -p crate-b"
}

# A changed member Cargo.toml narrows to the crate it declares (D4: "a
# change to any Cargo.toml narrows to that crate only if it is a member
# crate manifest").
test_profile_rust_member_manifest_narrows_to_its_own_crate() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  printf 'crates/a/Cargo.toml\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: crates crate-a"
  assert_file_contains cargo.log "test -p crate-a"
}

# A single-crate project's own root Cargo.toml is a member manifest too:
# narrows to that one crate, not a full run.
test_profile_rust_root_package_manifest_narrows_to_its_crate() {
  mkdir -p src
  cat > Cargo.toml <<'EOF'
[package]
name = "solo"
version = "0.1.0"
EOF
  printf 'fn main() {}\n' > src/main.rs
  _rust_stub 1 0 1 0 0
  printf 'Cargo.toml\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: crates solo"
  assert_file_contains cargo.log "test -p solo"
}

# --- "always ALL" column (D4): lockfile, .cargo/, toolchain pin, root ------
# workspace manifest, and anything outside every crate.

test_profile_rust_cargo_lock_change_runs_full_set() {
  _rust_workspace
  : > Cargo.lock
  _rust_stub 1 0 1 0 0
  printf 'Cargo.lock\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: full"
  assert_file_contains cargo.log "^test\$"
  assert_not_contains "$(cat cargo.log)" " -p "
}

test_profile_rust_dot_cargo_config_runs_full_set() {
  _rust_workspace
  mkdir -p .cargo
  : > .cargo/config.toml
  _rust_stub 1 0 1 0 0
  printf '.cargo/config.toml\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: full"
}

test_profile_rust_toolchain_pin_runs_full_set() {
  _rust_workspace
  : > rust-toolchain.toml
  _rust_stub 1 0 1 0 0
  printf 'rust-toolchain.toml\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: full"
}

test_profile_rust_root_workspace_manifest_runs_full_set() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  printf 'Cargo.toml\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: full"
}

# Regression: RUST_ALL_GLOBS includes ".cargo/*"; before the fix it was
# split with `for g in $LIST` with pathname expansion on, so the word
# expanded to whichever .cargo/* sibling sits on disk (here
# .cargo/other.toml) instead of staying the literal pattern. A changed
# .cargo/config.toml (deleted, never created on disk) then failed to match
# it and fell through to the crate-directory lookup — which, for a
# single-crate project whose root Cargo.toml declares [package], wrongly
# narrowed to that one crate instead of running the full set.
test_profile_rust_dot_cargo_deleted_file_runs_full_despite_sibling_on_disk() {
  mkdir -p src .cargo
  cat > Cargo.toml <<'EOF'
[package]
name = "solo"
version = "0.1.0"
EOF
  printf 'fn main() {}\n' > src/main.rs
  : > .cargo/other.toml
  _rust_stub 1 0 1 0 0
  printf '.cargo/config.toml\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: full"
  assert_file_contains cargo.log "^test\$"
  assert_not_contains "$(cat cargo.log)" " -p "
}

test_profile_rust_file_outside_any_crate_runs_full_set() {
  _rust_workspace
  : > notes.txt
  _rust_stub 1 0 1 0 0
  printf 'notes.txt\n' > "$JIG_TEST_TMP.files"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: full"
}

# --- zero selection: every changed file maps to "-" (map-driven) -----------
# _rust_builtin never answers "nothing" on its own (D4: outside any crate is
# ALL, not nothing), so the only way the decision comes back completely
# empty is a project map that marks every changed path "-" — which must
# skip, never silently pass (ADR-0041).

test_profile_rust_map_marks_everything_dash_skips() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  printf 'README.md\n' > "$JIG_TEST_TMP.files"
  printf 'README.md\t-\n' > "$JIG_TEST_TMP.mapped"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files" JIG_VERIFY_MAPPED="$JIG_TEST_TMP.mapped"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: skip (scope: no changed file affects this check)"
  assert_contains "$OUT" "rust: clippy: skip (scope: no changed file affects this check)"
  assert_contains "$OUT" "rust: test: skip (scope: no changed file affects this check)"
}

# --- map filters (D5): a crate name, and an unknown one (AC-09) ------------
# Through JIG_VERIFY_MAPPED directly (the profile's side of the protocol);
# the real `jig verify --changed` + .ai/verify/rust.map path is covered
# separately below, once, to prove the core's own map parsing wires up too.

test_profile_rust_map_names_a_crate_overriding_builtin() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  printf 'crates/a/src/lib.rs\n' > "$JIG_TEST_TMP.files"
  printf 'crates/a/src/lib.rs\tcrate-b\n' > "$JIG_TEST_TMP.mapped"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files" JIG_VERIFY_MAPPED="$JIG_TEST_TMP.mapped"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "scope: crates crate-b"
  assert_file_contains cargo.log "test -p crate-b"
}

test_profile_rust_map_names_unknown_crate_runs_full_set() {
  _rust_workspace
  _rust_stub 1 0 1 0 0
  printf 'crates/a/src/lib.rs\n' > "$JIG_TEST_TMP.files"
  printf 'crates/a/src/lib.rs\tno-such-crate\n' > "$JIG_TEST_TMP.mapped"
  JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_TEST_TMP.files" JIG_VERIFY_MAPPED="$JIG_TEST_TMP.mapped"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  _rust_run
  unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "crate 'no-such-crate' not declared, ran full set"
  assert_not_contains "$(cat cargo.log)" " -p "
}

# --- the real jig verify --changed path, with a committed .ai/verify/rust.map
#
# `jig verify --changed` (no --base) diffs against HEAD but still counts
# every untracked file as changed (RULES.md), so the workspace, the map and
# everything `jig init` created are committed first; only the later edit to
# crates/a/src/lib.rs is left uncommitted, and the stub `cargo` lives
# outside the repository entirely so it never appears in the changed-file
# list itself.

test_profile_rust_real_verify_changed_reads_project_map() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles rust >/dev/null
  _rust_workspace
  mkdir -p .ai/verify
  printf 'crates/a/src/lib.rs crate-b\n' > .ai/verify/rust.map
  git add -A
  git commit -q -m "workspace"
  printf 'pub fn a2() {}\n' >> crates/a/src/lib.rs

  local stub_dir="$JIG_TEST_TMP-stub-bin"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/cargo" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/cargo.log"
if [ "\$1 \$2" = "fmt --version" ]; then printf 'rustfmt 1.7.0-stable\n'; exit 0; fi
if [ "\$1 \$2" = "clippy --version" ]; then printf 'clippy 0.1.77\n'; exit 0; fi
if [ "\$1" = "--version" ]; then printf 'cargo 1.77.0\n'; exit 0; fi
exit 0
STUB
  chmod +x "$stub_dir/cargo"
  PATH="$stub_dir:$PATH"
  export PATH

  run jig verify --changed --profile rust
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "RESULT rust: pass"
  assert_contains "$OUT" "map .ai/verify/rust.map"
  assert_contains "$OUT" "scope: crates crate-b"
  assert_file_contains cargo.log "test -p crate-b"
}
