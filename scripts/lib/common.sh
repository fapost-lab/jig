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
# files — all repo-relative (ARCHITECTURE.md, Scripts layout). `-C "$JIG_PROJECT"` matters: `git diff`
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
  if [ "$#" -gt 0 ]; then
    local explicit_base explicit_head explicit_rows
    explicit_base=$(jig_review_commit "$1") || return 1
    explicit_head=$(jig_review_commit "${2:-HEAD}") || return 1
    explicit_rows=$(jig_git_change_rows "$explicit_base" "$explicit_head") || return 1
    printf '%s\n' "$explicit_rows" | sed '/^$/d' | cut -f1 | LC_ALL=C sort -u
    return 0
  fi
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
# templates/knowledge/ (schemas/frontmatter.md, ADR-0004). `domain`,
# `glossary` and `rule` are the three files of a domain pack.
JIG_DOC_TYPES="feature adr convention domain glossary rule"
export JIG_DOC_TYPES

# The three documents directly under .ai/knowledge/ that carry no frontmatter
# by design. Takes an absolute path and matches on the repository-relative
# path, never on the basename: a domain pack is `domains/<d>/RULES.md`, and a
# basename test would exempt that file from validation and hide it from every
# consumer of jig_knowledge_docs — silently, which is the worst way to lose a
# document (design.md, "Global documents are recognised by path").
jig_knowledge_is_global() {
  local rel
  rel=$(jig_relpath "$1" "$JIG_PROJECT")
  case "$rel" in
    "$JIG_AI_DIR/knowledge/GLOSSARY.md" | \
      "$JIG_AI_DIR/knowledge/ARCHITECTURE.md" | \
      "$JIG_AI_DIR/knowledge/RULES.md") return 0 ;;
    *) return 1 ;;
  esac
}

# Every knowledge document that can carry frontmatter, absolute paths, sorted.
# Walks .ai/knowledge recursively: applicability lives in frontmatter, not in
# the directory (ADR-0004), so a document counts wherever it sits — including
# under domains/<d>/.
#
# Lives here, with the other shared knowledge helpers, because `context` and
# `knowledge` must never disagree about which files exist: one walking
# recursively while the other read three fixed directories is how a domain
# document ended up validated but never resolved.
jig_knowledge_docs() {
  local dir="$JIG_PROJECT/$JIG_AI_DIR/knowledge" f
  [ -d "$dir" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    jig_knowledge_is_global "$f" && continue
    printf '%s\n' "$f"
  done < <(find "$dir" -type f -name '*.md' | sort)
}

# jig_knowledge_status_resolvable <status> — true when a document may be loaded into
# an agent's context, listed in the catalog, or pulled in as a `requires` target.
#
# An allowlist, deliberately: a denylist of retired values resolves anything it has not
# heard of — a typo'd status, or a lifecycle value added later — as if it were active.
# `proposed` is exactly such a later value, and the guarantee that a proposed document
# cannot reach an agent rests on this being an allowlist. `accepted` is the ADR spelling
# of `active`.
jig_knowledge_status_resolvable() {
  case "$1" in
    active | accepted) return 0 ;;
    *) return 1 ;;
  esac
}

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

# Content hash used by the manifest (ADR-0003, domains/install). git is mandatory,
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

# Fixed route vocabulary shared by context and knowledge metadata validation.
jig_valid_stage() {
  case "$1" in
    analyze | discover | specify | alternatives | design | plan | implement | review | architecture-review | verify | consolidate) return 0 ;;
    *) return 1 ;;
  esac
}

# Literal repository-relative paths for a review inventory (not shell/Git patterns).
jig_check_review_path() {
  case "$1" in
    '' | /* | *"$(printf '\t')"* | *'
'*) jig_die "task changes: unsupported path (absolute, empty, tab or newline): $1" ;;
  esac
  case "/$1/" in
    */../* | */./* | *//*) jig_die "task changes: path must be repository-relative without dot segments: $1" ;;
  esac
}

jig_review_commit() {
  case "$1" in '' | -*) jig_die "task changes: invalid base: $1" ;; esac
  git -C "$JIG_PROJECT" rev-parse --verify "$1^{commit}" 2>/dev/null \
    || jig_die "task changes: cannot resolve commit: $1"
}

# Strict inventory, path<TAB>layer. NUL Git output is decoded only after checking
# producer exit status; process substitution would hide a failing Git command.
# Buffer all rows so failures cannot be mistaken for a complete partial inventory.
jig_git_change_rows() (
  local base="$1" head="$2" layer path
  JIG_CHANGE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/jig-changes.XXXXXX") || exit 1
  trap 'rm -rf "$JIG_CHANGE_TMP"' EXIT
  : > "$JIG_CHANGE_TMP/rows"
  for layer in committed staged unstaged untracked; do
    case "$layer" in
      committed) git -C "$JIG_PROJECT" diff --no-ext-diff --no-textconv --ignore-submodules=none --no-renames --name-only -z "$base" "$head" -- > "$JIG_CHANGE_TMP/paths" ;;
      staged) git -C "$JIG_PROJECT" diff --no-ext-diff --no-textconv --ignore-submodules=none --no-renames --cached --name-only -z "$head" -- > "$JIG_CHANGE_TMP/paths" ;;
      unstaged) git -C "$JIG_PROJECT" diff --no-ext-diff --no-textconv --ignore-submodules=none --no-renames --name-only -z -- > "$JIG_CHANGE_TMP/paths" ;;
      untracked) git -C "$JIG_PROJECT" ls-files --others --exclude-standard -z > "$JIG_CHANGE_TMP/paths" ;;
    esac || jig_die "task changes: Git inventory failed for $layer"
    while IFS= read -r -d '' path; do
      jig_check_review_path "$path"
      printf '%s\t%s\n' "$path" "$layer" >> "$JIG_CHANGE_TMP/rows"
    done < "$JIG_CHANGE_TMP/paths"
  done
  LC_ALL=C sort -u "$JIG_CHANGE_TMP/rows"
)
