# Shared helpers for every jig command. Sourced by scripts/jig.
# bash 3.2 compatible: no associative arrays, no ${var,,}, no mapfile.
# shellcheck shell=bash

JIG_AI_DIR=".ai"
export JIG_AI_DIR

# --- output --------------------------------------------------------------

jig_log()  { [ -n "${JIG_QUIET:-}" ] || printf '%s\n' "$*"; }
jig_info() { [ -n "${JIG_QUIET:-}" ] || printf 'jig: %s\n' "$*" >&2; }
jig_warn() { printf 'jig: warning: %s\n' "$*" >&2; }
jig_die()  { printf 'jig: error: %s\n' "$*" >&2; exit 1; }

# --- repository ------------------------------------------------------------

# Print the git repository root of the current directory or fail.
jig_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# Set JIG_PROJECT to the repository root; die when not inside a repository.
jig_require_repo() {
  JIG_PROJECT=$(jig_repo_root) || jig_die "not inside a git repository"
  export JIG_PROJECT
}

# Die unless the project has been initialised with jig init.
jig_require_init() {
  jig_require_repo
  [ -f "$JIG_PROJECT/$JIG_AI_DIR/config.yaml" ] \
    || jig_die "project is not initialised; run: jig init"
}

# True when <dir> is a framework source checkout (has skills/ and templates/).
jig_is_source_root() {
  [ -d "$1/skills" ] && [ -d "$1/templates" ] && [ -f "$1/scripts/jig" ]
}

# Best-effort framework source root: the checkout this script runs from, or
# JIG_SOURCE, or empty when running from an installed copy.
jig_source_root() {
  local candidate
  candidate=$(cd "$JIG_LIB/../.." && pwd)
  if jig_is_source_root "$candidate"; then
    printf '%s\n' "$candidate"
  elif [ -n "${JIG_SOURCE:-}" ] && jig_is_source_root "$JIG_SOURCE"; then
    printf '%s\n' "$JIG_SOURCE"
  fi
}

# Files this checkout has touched: the union of the diff against the merge-base
# with the configured base branch, the staged and unstaged diffs, and untracked
# files — all repo-relative (SPEC §26). `-C "$JIG_PROJECT"` matters: `git diff`
# reports paths relative to the repository root regardless of cwd, but
# `git ls-files` reports them relative to cwd unless it is the root, so without
# -C the two halves of the union could disagree on the path of the same file.
# When the base branch does not exist, merge-base fails and only the working
# tree diffs (staged, unstaged, untracked) are used.
#
# Lives here rather than in one command's library because `context` and
# `knowledge paths` both need the same answer to "what did this task touch",
# and they must never disagree about it (ARCHITECTURE.md, scripts layout).
jig_git_touched_files() {
  local base mb out=""
  base=$(cfg git.base_branch main)
  if mb=$(git -C "$JIG_PROJECT" merge-base "$base" HEAD 2>/dev/null); then
    out="$out
$(git -C "$JIG_PROJECT" diff --name-only "$mb" 2>/dev/null)"
  fi
  # Staged changes are listed independently: without a merge base they would
  # otherwise vanish from both the unstaged diff and the untracked list.
  out="$out
$(git -C "$JIG_PROJECT" diff --cached --name-only 2>/dev/null)"
  out="$out
$(git -C "$JIG_PROJECT" diff --name-only 2>/dev/null)"
  out="$out
$(git -C "$JIG_PROJECT" ls-files --others --exclude-standard 2>/dev/null)"
  printf '%s\n' "$out" | sed '/^$/d' | sort -u
}

# --- knowledge documents ---------------------------------------------------

# Document types that carry frontmatter and ship a template under
# templates/knowledge/ (schemas/frontmatter.md, ADR-0004).
JIG_DOC_TYPES="feature adr convention"
export JIG_DOC_TYPES

# Translate a frontmatter `paths` glob into a pattern usable both with
# `find -path` and with a bash `case`: `**` (any depth, including zero
# directories) collapses to a single `*`. BSD and GNU `find -path` match `*`
# across `/` (no FNM_PATHNAME) and a `case` pattern does the same, so this one
# substitution covers any-depth and single-segment globs in both consumers
# (convention-shell). Used by context.sh, knowledge.sh.
jig_glob_pattern() {
  printf '%s' "$1" | sed 's#[*][*]/#*#g; s#[*][*]#*#g'
}

# --- misc ------------------------------------------------------------------

jig_today() { date +%Y-%m-%d; }

# Content hash used by the manifest (ADR-0003, SPEC §6.2). git is mandatory,
# shasum/sha256sum are not portable.
jig_hash() { git hash-object "$1"; }

# Path of <file> relative to <base>, both absolute. Pure string operation.
jig_relpath() {
  local base="${2%/}/" file="$1"
  case "$file" in
    "$base"*) printf '%s\n' "${file#"$base"}" ;;
    *) printf '%s\n' "$file" ;;
  esac
}

# Age of a file in whole days (0 when it does not exist). Uses mtime.
jig_file_age_days() {
  local f="$1" mtime now
  [ -f "$f" ] || { printf '0\n'; return; }
  if mtime=$(stat -f %m "$f" 2>/dev/null); then :; else mtime=$(stat -c %Y "$f"); fi
  now=$(date +%s)
  printf '%d\n' $(( (now - mtime) / 86400 ))
}

# Convert a duration like 7d / 12h / 30m to seconds.
jig_duration_seconds() {
  local d="$1" n unit
  n=${d%[dhms]}; unit=${d#"$n"}
  case "$n" in ''|*[!0-9]*) jig_die "invalid duration: $d" ;; esac
  case "$unit" in
    d|'') printf '%d\n' $((n * 86400)) ;;
    h) printf '%d\n' $((n * 3600)) ;;
    m) printf '%d\n' $((n * 60)) ;;
    s) printf '%d\n' "$n" ;;
  esac
}
