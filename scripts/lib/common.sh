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

# --- framework versions and the global executable -------------------------
#
# Release tags are the update channel: a release is `v<major>.<minor>.<patch>`,
# digits only, and the newest one is what `install.sh` installs and what
# `jig self-update` moves to. Versions are ordered in shell arithmetic because
# `sort -V` is not available everywhere jig runs (conventions/shell.md).

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

# jig_version_of <executable> — the version a jig executable reports, taken
# only from a single line shaped exactly `jig <version>`. Fails otherwise, so
# a wrapper or an unrelated `jig` on PATH is never mistaken for a version.
jig_version_of() {
  local out
  out=$("$1" version 2>/dev/null) || return 1
  case "$out" in
    *'
'*) return 1 ;;
    'jig '?*) printf '%s\n' "${out#jig }" ;;
    *) return 1 ;;
  esac
}

# jig_declared_version <source> — the version a framework checkout declares in
# scripts/lib/version.sh, read without running anything. Fails unless exactly
# one line is shaped `JIG_VERSION="<version>"` with a value free of quotes and
# spaces. `jig status` uses this rather than jig_version_of: a read-only
# command must not execute whatever PATH selects, and a broken global checkout
# would otherwise hang it, with no portable timeout to bound the wait.
jig_declared_version() {
  local file="$1/scripts/lib/version.sh" found
  [ -f "$file" ] || return 1
  found=$(sed -n 's/^JIG_VERSION="\([^" ]\{1,\}\)"[[:space:]]*$/\1/p' "$file" 2>/dev/null) \
    || return 1
  case "$found" in
    '' | *'
'*) return 1 ;;
  esac
  printf '%s\n' "$found"
}

# jig_global_executable — the physical path of the `jig` the current PATH
# selects, when it is the dispatcher of a framework source checkout. Fails,
# printing nothing, when PATH has no `jig` or it resolves anywhere else.
#
# Symlinks are resolved with the dispatcher's own jig_resolve_path, defined in
# scripts/jig before any library is sourced; it is reused rather than copied
# here, because two resolvers would drift. Directories are then made physical
# (conventions/shell.md), so the path compares equal to JIG_SELF resolved the
# same way — equal means the same checkout, as in link mode.
jig_global_executable() {
  local found path dir
  found=$(command -v jig 2>/dev/null) || return 1
  case "$found" in
    /*) ;;
    *) return 1 ;;
  esac
  path=$(jig_resolve_path "$found") || return 1
  dir=$(cd -P "${path%/*}" 2>/dev/null && pwd -P) || return 1
  path="$dir/${path##*/}"
  case "$path" in
    */scripts/jig) ;;
    *) return 1 ;;
  esac
  jig_is_source_root "${path%/scripts/jig}" || return 1
  printf '%s\n' "$path"
}

# jig_physical_path <file> — <file> with its directory made physical.
jig_physical_path() {
  local dir
  dir=$(cd -P "${1%/*}" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "${1##*/}"
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

# jig_copy_tree <src-dir> <dst-dir> — copy every regular file under <src-dir>
# (`find -type f`: symlinks and empty directories are not copied) to the same
# relative path under <dst-dir>, with `cp -p`. Plain overwrite, no conflict
# handling: for scratch trees such as upgrade's stage, not for a project.
#
# One `mkdir -p` and one `cp` per directory rather than per file. The file list
# is sorted so each directory's files arrive together; a directory split
# around a subdirectory only costs an extra `cp`, never a wrong copy. The
# per-file loop — `dirname`, `mkdir` and `cp` for each of 43 framework files —
# was the largest part of what `jig status` still spent once hashing was
# batched.
jig_copy_tree() {
  local src="$1" dst="$2" f dir last="" n=0
  local -a batch
  mkdir -p "$dst"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f=${f#./}
    case "$f" in
      */*) dir=${f%/*} ;;
      *) dir=. ;;
    esac
    if [ "$dir" != "$last" ] && [ "$n" -gt 0 ]; then
      mkdir -p "$dst/$last"
      cp -p "${batch[@]}" "$dst/$last/"
      n=0
      batch=()
    fi
    last=$dir
    batch[n]="$src/$f"
    n=$((n + 1))
  done < <(cd "$src" && find . -type f | LC_ALL=C sort)
  if [ "$n" -gt 0 ]; then
    mkdir -p "$dst/$last"
    cp -p "${batch[@]}" "$dst/$last/"
  fi
  return 0
}

# jig_hash_list <file> — the blob hash of every path listed in <file>, one per
# line and in the same order, from a single `git hash-object` process. Nothing
# for an empty list. Every listed path must exist: git fails the whole batch
# otherwise, which the caller turns into an error rather than a missing hash.
#
# Use this, not a loop over jig_hash, whenever there is more than one file.
# Each call is a git startup, and on 65 manifest files the loop took 0.879 s
# where one call took 0.013 s — it was most of what `jig status` cost.
# Pair the output back with its paths by position (`paste`); a path containing
# a newline would desync that, and none of jig's line-based lists can hold one.
jig_hash_list() {
  [ -s "$1" ] || return 0
  git hash-object --stdin-paths < "$1"
}

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

# jig_review_commit <ref> [message-prefix]
#
# The prefix names the *calling* command in the error. Without it the message
# was hardcoded to "task changes", so a second caller told the user about a
# command they had not run.
jig_review_commit() {
  local who="${2:-task changes}"
  case "$1" in '' | -*) jig_die "$who: invalid base: $1" ;; esac
  git -C "$JIG_PROJECT" rev-parse --verify "$1^{commit}" 2>/dev/null \
    || jig_die "$who: cannot resolve commit: $1"
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
