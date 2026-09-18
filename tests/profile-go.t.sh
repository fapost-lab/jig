# Tests for the go profile (domains/verify, ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools).
# shellcheck shell=bash
#
# Each test either goes through `profiles_detect`/`run_no_tools` for
# detection and the no-toolchain path, or runs profiles/go/verify.sh
# directly with JIG_VERIFY_SCOPE/JIG_VERIFY_FILES/JIG_VERIFY_MAPPED set to
# files the test writes -- both explicitly sanctioned by the brief for a
# profile that narrows through the shared library rather than through
# `jig verify` itself. Every test supplies its own fake `go` (go_stub); the
# machine's real toolchain, if any, is never on PATH for these checks
# (conventions/shell.md: "a test decides its own environment").

# --- fixtures ------------------------------------------------------------

# _GO_NO_TOOLS_LIST — every tool the go profile and the library it sources
# need when `go` itself is absent: git for nothing here (verify.sh runs
# directly, not through `jig`), but bash's own shebang, sed/awk/grep/sort
# (jp_version, jp_decide) and the usual coreutils profile.sh's helpers call.
# Deliberately excludes go: the point of run_no_tools is that it is not on
# PATH regardless of what the machine running the suite happens to have
# installed (conventions/shell.md: a PATH built from an allow-list, never
# from "system directories believed tool-free").
_GO_NO_TOOLS_LIST="bash sh sed awk grep mktemp cat cp mv rm mkdir sort tr head tail wc chmod ls date dirname basename env"

# run_no_tools <cmd...> — like `run`, but PATH is rebuilt from
# _GO_NO_TOOLS_LIST alone, through wrapper scripts (never symlinks: a
# symlink can strand a binary away from its shared library on some
# platforms, tests/verify.t.sh's own _no_tools_fill), so the go profile's
# "go not found" skip path is exercised deterministically.
run_no_tools() {
  local dir out t p esc
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-go-no-tools.XXXXXX")
  for t in $_GO_NO_TOOLS_LIST; do
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

# go_stub <version> <vet-rc> <test-rc> [<impfile> <depfile>] — a fake `go`
# on PATH ahead of everything else. Every invocation is appended, arguments
# only and space-joined, to go-calls.log, so a test can assert on exactly
# which package patterns a check received. `go version` answers a fixed
# line built from <version>; `go vet`/`go test` exit with the given codes
# regardless of their own arguments. `go list -f '{{.ImportPath}} {{.Dir}}'
# ./...` and `go list -f '{{.Dir}} {{join .Deps " "}}' ./...` are told apart
# by their format string (`ImportPath` vs `Deps`) and answer from <impfile>
# / <depfile> when both are given; without them `go list` fails, the way a
# real one does outside a module -- the "go list failed" fallback tests use
# that.
go_stub() {
  local version="$1" vet_rc="$2" test_rc="$3" impfile="${4:-}" depfile="${5:-}"
  mkdir -p stub-bin
  if [ -n "$impfile" ]; then
    cp "$impfile" stub-bin/.go-list-imp
    cp "$depfile" stub-bin/.go-list-dep
  fi
  cat > stub-bin/go <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/go-calls.log"
case "\$1" in
  version)
    printf 'go version go$version darwin/arm64\n'
    exit 0
    ;;
  vet)
    exit $vet_rc
    ;;
  test)
    exit $test_rc
    ;;
  list)
    if [ ! -f "$PWD/stub-bin/.go-list-imp" ]; then
      exit 1
    fi
    case "\$3" in
      *ImportPath*) cat "$PWD/stub-bin/.go-list-imp" ;;
      *Deps*) cat "$PWD/stub-bin/.go-list-dep" ;;
    esac
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x stub-bin/go
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# set_go_scope <path>... — a scoped run naming <path>... as the changed
# files, the way `jig verify --changed` would build JIG_VERIFY_FILES.
set_go_scope() {
  local f
  GO_SCOPE_FILE=$(_run_out .files)
  : > "$GO_SCOPE_FILE"
  for f in "$@"; do
    printf '%s\n' "$f" >> "$GO_SCOPE_FILE"
  done
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$GO_SCOPE_FILE"
  export JIG_VERIFY_SCOPE JIG_VERIFY_FILES
}

# set_go_mapped <line>... — JIG_VERIFY_MAPPED, one already-built
# "<path><TAB><decision>" line per argument (schemas/verify-map.md's
# decision vocabulary, as `jig verify` would hand it to a profile after
# applying .ai/verify/go.map).
set_go_mapped() {
  local line
  GO_MAPPED_FILE=$(_run_out .mapped)
  : > "$GO_MAPPED_FILE"
  for line in "$@"; do
    printf '%s\n' "$line" >> "$GO_MAPPED_FILE"
  done
  JIG_VERIFY_MAPPED="$GO_MAPPED_FILE"
  export JIG_VERIFY_MAPPED
}

# --- detect ----------------------------------------------------------------

test_profile_go_detect_by_go_mod() {
  fixture_repo
  printf 'module example.com/x\n' > go.mod
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"
    JIG_PROJECT="$(pwd)"
    export JIG_LIB JIG_PROJECT
    . "$JIG_LIB/common.sh"
    . "$JIG_LIB/config.sh"
    . "$JIG_LIB/profiles.sh"
    profiles_detect "$JIG_HOME/profiles"
  '
  assert_eq 0 "$RC"
  assert_contains "$OUT" "go"
}

# --- no toolchain ------------------------------------------------------------

test_profile_go_skip_without_toolchain() {
  fixture_repo
  run_no_tools bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  # Literal text, not an expansion.
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'go: vet: skip (go not found in $PATH)'
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'go: test: skip (go not found in $PATH)'
}

# --- full (unscoped) run -----------------------------------------------------

test_profile_go_full_run_passes_and_names_version() {
  fixture_repo
  mkdir -p internal/foo
  printf 'package foo\n' > internal/foo/foo.go
  go_stub 1.22.1 0 0

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64)"
  assert_contains "$OUT" "go: test: pass (go version go1.22.1 darwin/arm64)"
  assert_file_contains go-calls.log "vet ./..."
  assert_file_contains go-calls.log "test ./..."
}

test_profile_go_full_run_fails_on_vet_and_test_failure() {
  fixture_repo
  go_stub 1.22.1 1 1

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: fail (go version go1.22.1 darwin/arm64)"
  assert_contains "$OUT" "go: test: fail (go version go1.22.1 darwin/arm64)"
}

# --- narrowing: vet by package (D4) ------------------------------------------

test_profile_go_vet_narrows_to_changed_package() {
  fixture_repo
  mkdir -p internal/foo cmd/bar
  printf 'package foo\n' > internal/foo/foo.go
  printf 'package bar\n' > cmd/bar/bar.go
  go_stub 1.22.1 0 0
  set_go_scope internal/foo/foo.go

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: 1 packages)"
  assert_file_contains go-calls.log "vet ./internal/foo"
  assert_not_contains "$(cat go-calls.log)" "vet ./..."
}

# A changed file in a package's testdata/ subtree maps to that package
# (D4), not to a "testdata" package of its own -- go itself has no such
# package.
test_profile_go_testdata_file_narrows_to_its_package() {
  fixture_repo
  mkdir -p internal/foo/testdata
  printf 'package foo\n' > internal/foo/foo.go
  printf 'golden\n' > internal/foo/testdata/golden.txt
  go_stub 1.22.1 0 0
  set_go_scope internal/foo/testdata/golden.txt

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: 1 packages)"
  assert_file_contains go-calls.log "vet ./internal/foo"
}

# --- narrowing: test by package plus importers (D4) --------------------------

test_profile_go_test_narrows_to_changed_and_importing_packages() {
  fixture_repo
  mkdir -p internal/foo cmd/bar
  printf 'package foo\n' > internal/foo/foo.go
  printf 'package bar\n' > cmd/bar/bar.go
  imp="$PWD/list-imp.txt"
  dep="$PWD/list-dep.txt"
  printf 'example.com/x/internal/foo %s/internal/foo\n' "$PWD" > "$imp"
  printf 'example.com/x/cmd/bar %s/cmd/bar\n' "$PWD" >> "$imp"
  printf '%s/internal/foo std/fmt\n' "$PWD" > "$dep"
  printf '%s/cmd/bar example.com/x/internal/foo std/fmt\n' "$PWD" >> "$dep"
  go_stub 1.22.1 0 0 "$imp" "$dep"
  set_go_scope internal/foo/foo.go

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  # vet never adds importers: only the package the change is in.
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: 1 packages)"
  assert_file_contains go-calls.log "vet ./internal/foo"
  # test adds cmd/bar, which imports internal/foo, transitively through Deps.
  assert_contains "$OUT" "go: test: pass (go version go1.22.1 darwin/arm64, scope: 2 packages)"
  assert_file_contains go-calls.log "test ./cmd/bar ./internal/foo"
}

# --- always ALL (D4): go.mod, go.sum, go.work --------------------------------

test_profile_go_gomod_change_forces_full_run() {
  fixture_repo
  mkdir -p internal/foo
  printf 'package foo\n' > internal/foo/foo.go
  go_stub 1.22.1 0 0
  set_go_scope go.mod

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: module-wide file changed, whole project)"
  assert_contains "$OUT" "go: test: pass (go version go1.22.1 darwin/arm64, scope: module-wide file changed, whole project)"
  assert_file_contains go-calls.log "vet ./..."
  assert_file_contains go-calls.log "test ./..."
}

test_profile_go_gosum_change_forces_full_run() {
  fixture_repo
  go_stub 1.22.1 0 0
  set_go_scope go.sum

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: module-wide file changed, whole project)"
  assert_contains "$OUT" "go: test: pass (go version go1.22.1 darwin/arm64, scope: module-wide file changed, whole project)"
}

test_profile_go_gowork_change_forces_full_run() {
  fixture_repo
  go_stub 1.22.1 0 0
  set_go_scope go.work

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: module-wide file changed, whole project)"
  assert_contains "$OUT" "go: test: pass (go version go1.22.1 darwin/arm64, scope: module-wide file changed, whole project)"
}

# --- zero selection is not a pass (RULES.md, ADR-0041) -----------------------

test_profile_go_doc_only_change_skips_both_checks() {
  fixture_repo
  go_stub 1.22.1 0 0
  set_go_scope README.md

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: skip (scope: no changed file maps to a package)"
  assert_contains "$OUT" "go: test: skip (scope: no changed file maps to a package)"
}

# --- deleted package (D4) -----------------------------------------------------

# The changed path's directory still exists but no longer has any .go file
# -- the ordinary state after the last source file of a package is removed.
test_profile_go_deleted_package_forces_full_run() {
  fixture_repo
  mkdir -p internal/dead internal/live
  printf 'was here\n' > internal/dead/NOTES.md
  printf 'package live\n' > internal/live/live.go
  # go list itself would never list the deleted package; a real answer
  # about the packages that remain must still be enough for `go test` to
  # reach its own "has no .go files" check rather than fail earlier on
  # "go list failed" (the go_list_failure test covers that path instead).
  imp="$PWD/list-imp.txt"
  dep="$PWD/list-dep.txt"
  printf 'example.com/x/internal/live %s/internal/live\n' "$PWD" > "$imp"
  printf '%s/internal/live std/fmt\n' "$PWD" > "$dep"
  go_stub 1.22.1 0 0 "$imp" "$dep"
  set_go_scope internal/dead/x.go

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: package './internal/dead' has no .go files, ran full set)"
  assert_contains "$OUT" "go: test: pass (go version go1.22.1 darwin/arm64, scope: package './internal/dead' has no .go files, ran full set)"
  assert_file_contains go-calls.log "vet ./..."
  assert_file_contains go-calls.log "test ./..."
}

# --- go list failing sends test alone to its full set (D4) -------------------

test_profile_go_go_list_failure_forces_full_test_run() {
  fixture_repo
  mkdir -p internal/foo
  printf 'package foo\n' > internal/foo/foo.go
  go_stub 1.22.1 0 0
  set_go_scope internal/foo/foo.go

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  # vet needs no importer graph, so it still narrows.
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: 1 packages)"
  assert_contains "$OUT" "go: test: pass (go version go1.22.1 darwin/arm64, scope: go list failed, ran full set)"
  assert_file_contains go-calls.log "test ./..."
}

# --- map filters (D5): package path, .ai/verify/go.map's grammar -------------

test_profile_go_map_filter_narrows_to_named_package() {
  fixture_repo
  mkdir -p internal/foo
  printf 'package foo\n' > internal/foo/foo.go
  go_stub 1.22.1 0 0
  set_go_scope unrelated.txt
  set_go_mapped "$(printf 'unrelated.txt\t./internal/foo')"

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: 1 packages)"
  assert_file_contains go-calls.log "vet ./internal/foo"
}

test_profile_go_map_filter_missing_package_forces_full_run() {
  fixture_repo
  go_stub 1.22.1 0 0
  set_go_scope unrelated.txt
  set_go_mapped "$(printf 'unrelated.txt\t./internal/nope')"

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: package './internal/nope' has no .go files, ran full set)"
}

test_profile_go_map_decision_all_forces_full_run() {
  fixture_repo
  go_stub 1.22.1 0 0
  set_go_scope unrelated.txt
  set_go_mapped "$(printf 'unrelated.txt\tALL')"

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22.1 darwin/arm64, scope: module-wide file changed, whole project)"
}

test_profile_go_map_decision_dash_excludes_path() {
  fixture_repo
  go_stub 1.22.1 0 0
  set_go_scope README.md
  set_go_mapped "$(printf 'README.md\t-')"

  run bash "$JIG_HOME/profiles/go/verify.sh"
  assert_eq 2 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: skip (scope: no changed file maps to a package)"
  assert_contains "$OUT" "go: test: skip (scope: no changed file maps to a package)"
}
