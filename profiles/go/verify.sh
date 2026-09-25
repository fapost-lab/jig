#!/usr/bin/env bash
# Verification for the go profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "go: <check>: pass|fail|skip (<note>)".
#
# go itself is the stack toolchain (adr-20260918-profiles-narrow-per-check-with-project-tools): resolved from $PATH, as this
# profile always did.
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools): a changed .go file, or another changed
# file inside a package directory (its own testdata/ subtree, or an
# embedded file sitting beside the .go source), narrows to that package,
# expressed as the `./<dir>` pattern `go` itself accepts on its command
# line (`.` for the repository root package). `go vet` runs on exactly
# those packages. `go test` runs on them plus every package that imports
# one of them, directly or through another package -- `go list`'s own
# `.Deps` is already the transitive closure, so one pass finds every
# affected importer. A changed go.mod, go.sum, go.work or go.work.sum
# affects the whole module and sends both checks to their full set; so does
# a package directory that no longer has any .go file (a deleted package),
# a filter naming one (built in or from the project map), or `go list`
# itself failing to answer.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin go

GO_ALL_GLOBS="go.mod go.sum go.work go.work.sum"

# _go_pkg_dir <path> — the package directory a changed path belongs to: the
# directory before a `testdata/` component (go's own convention, and where
# golden files live), else the path's own directory. "." for a file at the
# repository root.
_go_pkg_dir() {
  local f="$1"
  case "$f" in
    */testdata/*) printf '%s\n' "${f%/testdata/*}"; return 0 ;;
    testdata/*) printf '.\n'; return 0 ;;
  esac
  case "$f" in
    */*) printf '%s\n' "${f%/*}" ;;
    *) printf '.\n' ;;
  esac
  return 0
}

# _go_pkg_pattern <dir> — a package directory as the pattern `go` itself
# accepts on its command line; the repository root package is `.`, never
# `./.`.
_go_pkg_pattern() {
  case "$1" in
    .) printf '.\n' ;;
    *) printf './%s\n' "$1" ;;
  esac
}

# _go_dir_of_pattern <pattern> — the inverse of _go_pkg_pattern.
_go_dir_of_pattern() {
  case "$1" in
    .) printf '.\n' ;;
    ./*) printf '%s\n' "${1#./}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# _go_builtin <path> — the packages a changed path affects: ALL for a
# module-wide file, nothing for documentation and knowledge (ADR-0041: they
# affect no test), else the pattern of the package that contains it (D4).
_go_builtin() {
  local f="$1"
  if jp_path_matches "$f" "$GO_ALL_GLOBS"; then
    printf 'ALL\n'
    return 0
  fi
  case "$f" in
    *.md|*.rst|docs/*|.ai/*) return 0 ;;
  esac
  _go_pkg_pattern "$(_go_pkg_dir "$f")"
  return 0
}

# _go_pkg_has_go_files <dir> — a package directory that still has at least
# one .go file. A deleted package (D4) fails this even though the
# directory itself still exists.
_go_pkg_has_go_files() {
  local dir="$1" f
  for f in "$dir"/*.go; do
    if [ -f "$f" ]; then
      return 0
    fi
  done
  return 1
}

# _go_first_missing_pkg <pattern>... — jp_first_missing's contract
# (RULES.md: a narrowing that selects nothing is not a pass), but for a
# go package: the first pattern whose directory does not exist or has no
# .go file, printed; exit 1 when every pattern names a real package. Not
# jp_first_missing itself, which the library only asks to check mere
# existence -- an emptied package directory still exists (the gap: report
# it, per the brief, rather than stretch jp_first_missing's meaning).
_go_first_missing_pkg() {
  local p dir
  for p in "$@"; do
    dir=$(_go_dir_of_pattern "$p")
    if [ ! -d "$dir" ] || ! _go_pkg_has_go_files "$dir"; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

# _go_list_importpath_dir <out-file> — "<import-path> <dir>" per package
# under ./..., <dir> the absolute directory `go list` itself prints. Exit 1
# when `go list` cannot answer (no go.mod, a build error, ...): the caller
# falls back to the full set (D4: "if go list fails").
_go_list_importpath_dir() {
  "$go" list -f '{{.ImportPath}} {{.Dir}}' ./... > "$1" 2>/dev/null || return 1
  [ -s "$1" ] || return 1
  return 0
}

# _go_list_dir_deps <out-file> — "<dir> <dep-import-path>..." per package
# under ./..., <dir> like above. `go list`'s `.Deps` is already the
# transitive closure, so this one pass finds every package that depends on
# a changed one through any number of hops.
_go_list_dir_deps() {
  "$go" list -f '{{.Dir}} {{join .Deps " "}}' ./... > "$1" 2>/dev/null || return 1
  [ -s "$1" ] || return 1
  return 0
}

# _go_importpath_for_dir <dir> <impmap-file> — the import path of the
# package whose directory is <dir> (relative to the repository root, "."
# for the root package). Nothing when `go list` never listed it -- a
# deleted package, or a directory that is not one of the module's packages.
# Never fails: an unmatched directory is a normal, expected answer here.
_go_importpath_for_dir() {
  local dir="$1" file="$2" want
  if [ "$dir" = . ]; then
    want="$PWD"
  else
    want="$PWD/$dir"
  fi
  awk -v want="$want" '$2 == want { print $1; exit }' "$file"
  return 0
}

# _go_reverse_dependents <targets-file> <depmap-file> — the package
# patterns (one per line, `_go_pkg_pattern` form) whose `go list` Deps
# include an import path listed in <targets-file>. <targets-file> must be
# non-empty; NR == FNR only identifies the first file while it has lines,
# so an empty one would misread every line of <depmap-file> as belonging to
# it instead (conventions/shell.md).
_go_reverse_dependents() {
  local targets="$1" depmap="$2"
  awk -v pwd="$PWD" '
    NR == FNR { want[$1] = 1; next }
    {
      dir = $1
      hit = 0
      for (i = 2; i <= NF; i++) { if ($i in want) { hit = 1; break } }
      if (!hit) { next }
      if (dir == pwd) { print "."; next }
      prefix = pwd "/"
      if (index(dir, prefix) == 1) {
        print "./" substr(dir, length(prefix) + 1)
      } else {
        print "./" dir
      }
    }
  ' "$targets" "$depmap"
  return 0
}

# _go_test_packages <patterns> — the packages `go test` narrows to: the
# packages a changed path affects directly (D4, <patterns>, newline
# separated, neither empty nor ALL) union every package that imports one of
# them, directly or transitively. Prints the pattern list, sorted and
# deduplicated; exit 1 with nothing printed when `go list` cannot answer.
_go_test_packages() {
  local base="$1" impmap depmap targets result dir ip
  impmap=$(mktemp "${TMPDIR:-/tmp}/jig-go-imp.XXXXXX") || return 1
  depmap=$(mktemp "${TMPDIR:-/tmp}/jig-go-dep.XXXXXX") || return 1
  targets=$(mktemp "${TMPDIR:-/tmp}/jig-go-tgt.XXXXXX") || return 1
  if ! _go_list_importpath_dir "$impmap" || ! _go_list_dir_deps "$depmap"; then
    rm -f "$impmap" "$depmap" "$targets"
    return 1
  fi
  : > "$targets"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    dir=$(_go_dir_of_pattern "$p")
    ip=$(_go_importpath_for_dir "$dir" "$impmap")
    [ -n "$ip" ] || continue
    printf '%s\n' "$ip" >> "$targets"
  done <<EOF
$base
EOF
  result="$base"
  if [ -s "$targets" ]; then
    result="$result
$(_go_reverse_dependents "$targets" "$depmap")"
  fi
  rm -f "$impmap" "$depmap" "$targets"
  printf '%s\n' "$result" | sed '/^$/d' | LC_ALL=C sort -u
  return 0
}

# --- tool --------------------------------------------------------------------

if [ "${JIG_VERIFY_EXPLAIN:-}" = 1 ]; then
  if ! command -v go >/dev/null 2>&1; then
    jp_plan vet skip "go not found in PATH"
    jp_plan test skip "go not found in PATH"
    exit 0
  fi
  pkg_patterns=$(jp_decide _go_builtin)
  if ! jp_scoped; then
    jp_plan vet full "full scope"
    jp_plan test full "full scope"
  elif [ -z "$pkg_patterns" ]; then
    jp_plan vet skip "no changed file maps to a package"
    jp_plan test skip "no changed file maps to a package"
  elif [ "$pkg_patterns" = ALL ]; then
    jp_plan vet full "module-wide change"
    jp_plan test full "module-wide change"
  else
    missing=""
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      dir=$(_go_dir_of_pattern "$pattern")
      if ! _go_pkg_has_go_files "$dir"; then
        missing="$pattern"
        break
      fi
    done <<EOF
$pkg_patterns
EOF
    if [ -n "$missing" ]; then
      jp_plan vet full "package $missing has no .go files"
      jp_plan test full "package $missing has no .go files"
    else
      jp_plan_selection vet "$pkg_patterns" "packages"
      jp_plan test conditional "changed packages: $(printf '%s\n' "$pkg_patterns" | paste -sd, -); importers require go list; full set possible"
    fi
  fi
  exit 0
fi

go=""
if command -v go >/dev/null 2>&1; then
  go=$(command -v go)
fi

if [ -z "$go" ]; then
  jp_skip "vet" "go not found in \$PATH"
  jp_skip "test" "go not found in \$PATH"
  jp_end
fi

v=$(jp_version "$go" version)

# The packages the changed files affect directly (D4); shared by vet, which
# runs on exactly them, and test, which adds their importers. Empty and
# unused outside a scoped run (jp_decide already returns nothing then).
pkg_patterns=$(jp_decide _go_builtin)

# --- go vet --------------------------------------------------------------------

if ! jp_scoped; then
  jp_run "vet" "$v" "$go" vet ./...
elif [ -z "$pkg_patterns" ]; then
  jp_skip "vet" "scope: no changed file maps to a package"
elif [ "$pkg_patterns" = ALL ]; then
  jp_run "vet" "$v, scope: module-wide file changed, whole project" "$go" vet ./...
else
  IFS='
'
  set -f
  # shellcheck disable=SC2086
  set -- $pkg_patterns
  set +f
  IFS=$' \t\n'
  if missing=$(_go_first_missing_pkg "$@"); then
    jp_run "vet" "$v, scope: package '$missing' has no .go files, ran full set" "$go" vet ./...
  else
    n=$#
    jp_run "vet" "$v, scope: $n packages" "$go" vet "$@"
  fi
fi

# --- go test -------------------------------------------------------------------

# _go_test_run <note> [<pkg>...] — go test, in full when no package is
# named.
_go_test_run() {
  local note="$1"
  shift
  if [ $# -eq 0 ]; then
    jp_run "test" "$note" "$go" test ./...
  else
    jp_run "test" "$note" "$go" test "$@"
  fi
}

if ! jp_scoped; then
  _go_test_run "$v"
elif [ -z "$pkg_patterns" ]; then
  jp_skip "test" "scope: no changed file maps to a package"
elif [ "$pkg_patterns" = ALL ]; then
  _go_test_run "$v, scope: module-wide file changed, whole project"
else
  if ! expanded=$(_go_test_packages "$pkg_patterns"); then
    _go_test_run "$v, scope: go list failed, ran full set"
  else
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    set -- $expanded
    set +f
    IFS=$' \t\n'
    if missing=$(_go_first_missing_pkg "$@"); then
      _go_test_run "$v, scope: package '$missing' has no .go files, ran full set"
    else
      n=$#
      _go_test_run "$v, scope: $n packages" "$@"
    fi
  fi
fi

jp_end
