# Shared helpers for every jig command. Sourced by scripts/jig.
# bash 3.2 compatible: no associative arrays, no ${var,,}, no mapfile.
# shellcheck shell=bash

JIG_AI_DIR=".ai"
export JIG_AI_DIR

# --- output --------------------------------------------------------------

jig_log()  { [ -n "${JIG_QUIET:-}" ] || printf '%s\n' "$*"; }
jig_info() { [ -n "${JIG_QUIET:-}" ] || printf 'jig: %s\n' "$*" >&2; }
jig_warn() { printf 'jig: warning: %s\n' "$*" >&2; }
jig_die()  {
  printf 'jig: error: %s\n' "$*" >&2
  # A command that changed a task and then failed still redraws the status
  # page, so the page never shows less than the files do.
  jig_status_page_flush
  exit 1
}

# --- repository ------------------------------------------------------------

# Print the git repository root of the current directory or fail.
jig_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# Set JIG_PROJECT to the repository root; die when not inside a repository.
#
# The root is made physical in bash's own spelling. Git for Windows prints
# C:/Users/..., while every path bash builds is /c/Users/...; a symlink target
# computed between the two, or a prefix comparison, finds no common part —
# `init --link` produced ../../../../d/a/jig/jig/scripts, dangling, on the
# same drive. git already resolves symlinks on macOS and Linux, so this
# changes nothing there.
jig_require_repo() {
  local top
  top=$(jig_repo_root) || jig_die "not inside a git repository"
  JIG_PROJECT=$(cd -P "$top" 2>/dev/null && pwd -P) \
    || jig_die "cannot resolve the repository root: $top"
  export JIG_PROJECT
}

# jig_valid_id <id> — the grammar of a name that becomes a directory under
# .ai/: a task id and a spec id. Both must agree, because a spec's roadmap
# names task ids and a spec id follows task id rules; two copies of the case
# below would be free to drift.
# No leading dot: rules out `.`, `..` and hidden directories, which the `*/`
# walks over workspaces and specs would not see.
# No leading dash: every subcommand reads its id from the first argument, so
# `-x` is a flag in the wrong place, never a name. `jig task new --help` used
# to file a workspace named `--help`.
jig_valid_id() {
  case "$1" in
    '' | .* | -* | *[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
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

# --- directory links ----------------------------------------------------------

# How this machine links one directory to another: symlink, junction or none.
# Set by jig_link_detect, once per process. Cleared here so that a value in the
# caller's environment is never taken for a measurement.
_JIG_LINK_KIND=""

# jig_link_detect — measure which kind of directory link works here and keep it
# in _JIG_LINK_KIND. Not a `$(...)` helper: the answer must outlive the call.
#
# `ln -s` is never trusted to have made a link. Git Bash on Windows copies by
# default, and a copied task workspace diverges from its first write — two
# `state` files, and housekeeping keeping the worktree forever, because a copy
# is "a workspace of its own" (ADR-0029). Where symlinks are unavailable an
# NTFS junction needs no privilege; bash reads it as a link (`-L`,
# `find -type l`), and `git worktree remove` and `rm -rf` remove the junction
# without touching its target (measured on windows-latest, 2026-09-14).
jig_link_detect() {
  [ -z "$_JIG_LINK_KIND" ] || return 0
  local dir
  _JIG_LINK_KIND=none
  dir=$(mktemp -d "${TMPDIR:-/tmp}/jig-link-probe.XXXXXX") || return 0
  mkdir "$dir/target" || { rm -rf "$dir"; return 0; }
  if ln -s "$dir/target" "$dir/symlink" 2>/dev/null && [ -L "$dir/symlink" ]; then
    _JIG_LINK_KIND=symlink
  elif _jig_junction "$dir/target" "$dir/junction" && [ -L "$dir/junction" ]; then
    _JIG_LINK_KIND=junction
  fi
  rm -rf "$dir"
  return 0
}

# _jig_junction <target-abs> <link-abs> — an NTFS junction made by cmd.exe.
# MSYS rewrites mklink's `/J` into a path unless argument conversion is off,
# and cmd.exe needs both paths in Windows form.
_jig_junction() {
  local target link
  command -v cmd >/dev/null 2>&1 || return 1
  command -v cygpath >/dev/null 2>&1 || return 1
  target=$(cygpath -w "$1") || return 1
  link=$(cygpath -w "$2") || return 1
  MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$link" "$target" >/dev/null 2>&1
}

# jig_link_dir <target-abs> <link-abs> — link <link-abs> to the existing
# directory <target-abs> with the kind jig_link_detect found. Non-zero when no
# kind works, or when what was made does not read as a link.
jig_link_dir() {
  jig_link_detect
  case "$_JIG_LINK_KIND" in
    symlink) ln -s "$1" "$2" 2>/dev/null || return 1 ;;
    junction) _jig_junction "$1" "$2" || return 1 ;;
    *) return 1 ;;
  esac
  [ -L "$2" ]
}

# jig_physical_path <file> — <file> with its directory made physical.
jig_physical_path() {
  local dir
  dir=$(cd -P "${1%/*}" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "${1##*/}"
}

# jig_task_base <task-id> — the branch a task was cut from and has to land on:
# `base_branch` from its state file, or `git.base_branch` when the task never
# recorded one (not started, or started before the field existed). One answer
# for `task`, `housekeeping`, `context` and `knowledge`, which must never
# disagree about what a task is judged against (ADR-0039). The state file is
# the task domain's; reading it here is allowed, writing it is not. An id that
# is not a task id gets the configured base, never a path built from it.
jig_task_base() {
  local id="${1:-}" file value=""
  if jig_valid_id "$id"; then
    file="$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks/$id/state"
    if [ -f "$file" ]; then
      value=$(sed -n 's/^base_branch:[[:space:]]*//p' "$file" | head -n 1)
    fi
  fi
  [ -n "$value" ] || value=$(cfg git.base_branch main)
  printf '%s\n' "$value"
}

# jig_base_ref <name> — the ref a base branch is judged by:
# refs/remotes/origin/<name> when it exists, else refs/heads/<name>, else
# nothing. Origin first because landed means landed on the remote: a local
# base can be behind it (a teammate who never fetched the branch) or ahead of
# it (commits nobody pushed), and a bare name lets git pick the local one.
jig_base_ref() {
  local name="${1:-}"
  [ -n "$name" ] || return 0
  if git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/remotes/origin/$name^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "refs/remotes/origin/$name"
  elif git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/heads/$name^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "refs/heads/$name"
  fi
  return 0
}

# jig_git_show_path <ref> <path> — the content of <path> as committed at <ref>,
# on stdout; non-zero when <ref> names no commit or <path> is not in it.
# The ref is resolved to a commit SHA first and git is handed `<sha>:<path>`,
# never `<ref>:<path>`: under Git Bash (MSYS) an argument holding both `/`
# and `:` — `epic/idea-x:.ai/specs/...` — is rewritten as a path list before
# git sees it, so a ref with `/` in its name read nothing on Windows.
jig_git_show_path() {
  local sha
  sha=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "$1^{commit}" 2>/dev/null) || return 1
  [ -n "$sha" ] || return 1
  git -C "$JIG_PROJECT" show "$sha:$2"
}

# jig_fresh_base_ref <name> <who> — the ref to cut from <name>: the fresher of
# refs/heads/<name> and refs/remotes/origin/<name>, or HEAD when neither exists.
#
# Freshest, not nearest: resolving refs/heads/<base> first meant a local base
# that had fallen behind produced a stale branch *and* a stale base_commit,
# silently. That happened on 2026-09-11 — a branch was cut from the previous
# merge and the work done on it was missing a command merged an hour earlier.
# Diverged refs are refused rather than guessed: picking either surprises
# somebody, and the surprise surfaces far from its cause. <who> prefixes the
# messages (`task start`, `spec epic`). Shared because a task and an epic are
# both cut this way, and must never disagree about which commit is fresh.
jig_fresh_base_ref() {
  local base="$1" who="$2" local_ref remote_ref has_local=0 has_remote=0
  local_ref="refs/heads/$base"
  remote_ref="refs/remotes/origin/$base"
  git -C "$JIG_PROJECT" rev-parse --verify --quiet "$local_ref" >/dev/null 2>&1 && has_local=1
  git -C "$JIG_PROJECT" rev-parse --verify --quiet "$remote_ref" >/dev/null 2>&1 && has_remote=1

  if [ "$has_local" = 1 ] && [ "$has_remote" = 1 ]; then
    if git -C "$JIG_PROJECT" merge-base --is-ancestor "$local_ref" "$remote_ref" 2>/dev/null; then
      if ! git -C "$JIG_PROJECT" merge-base --is-ancestor "$remote_ref" "$local_ref" 2>/dev/null; then
        jig_info "$who: local $base is behind origin/$base; branching from origin/$base"
        printf '%s\n' "$remote_ref"
      else
        printf '%s\n' "$local_ref"
      fi
    elif git -C "$JIG_PROJECT" merge-base --is-ancestor "$remote_ref" "$local_ref" 2>/dev/null; then
      printf '%s\n' "$local_ref"
    else
      jig_die "$who: $base and origin/$base have diverged; reconcile them first"
    fi
  elif [ "$has_local" = 1 ]; then
    printf '%s\n' "$local_ref"
  elif [ "$has_remote" = 1 ]; then
    printf '%s\n' "$remote_ref"
  else
    printf 'HEAD\n'
  fi
}

# jig_fetch_branches <who> <name>... — refresh origin/<name> for each branch
# from origin, one at a time, so that a branch origin does not have fails
# alone. Does nothing without an origin. A failure is a warning, never fatal:
# the caller goes on with the refs it has, and says what it decided from them.
# GIT_TERMINAL_PROMPT=0: a command that only wanted fresh refs must not stop
# and wait for a password.
jig_fetch_branches() {
  local who="$1" name
  shift
  git -C "$JIG_PROJECT" remote get-url origin >/dev/null 2>&1 || return 0
  for name in "$@"; do
    [ -n "$name" ] || continue
    if ! GIT_TERMINAL_PROMPT=0 git -C "$JIG_PROJECT" fetch --quiet origin \
         "+refs/heads/$name:refs/remotes/origin/$name" >/dev/null 2>&1; then
      jig_warn "$who: could not fetch $name from origin; using the refs this checkout has"
    fi
  done
  return 0
}

# --- forge -------------------------------------------------------------------

# jig_forge_kind — which forge CLI this checkout should use: cfg `forge`
# (auto|github|gitlab|none, default auto) resolved against the origin URL
# when auto, then confirmed actually usable here — the CLI on PATH and
# authenticated. Prints github|gitlab|none; dies only on an unrecognised
# `forge` value, the one case a caller cannot paper over with "none".
#
# Shared rather than kept in housekeeping.sh: `housekeeping`'s remote-state
# tier and the pull-request step of `task ship` and `spec ship` (jig_ship_pr)
# all have to agree on which forge this checkout uses, and one command library
# never sources another (ARCHITECTURE.md, Scripts layout) — so the decision
# common to them lives here.
jig_forge_kind() {
  local want origin
  want=$(cfg forge auto)
  case "$want" in
    none) printf 'none\n'; return 0 ;;
    auto|github|gitlab) ;;
    *) jig_die "invalid forge: $want (expected auto|github|gitlab|none)" ;;
  esac

  origin=$(git -C "$JIG_PROJECT" remote get-url origin 2>/dev/null || printf '')
  if [ -z "$origin" ]; then
    printf 'none\n'
    return 0
  fi

  if [ "$want" = "auto" ]; then
    case "$origin" in
      *github.com*) want="github" ;;
      *gitlab.com*|*gitlab.*) want="gitlab" ;;
      *) printf 'none\n'; return 0 ;;
    esac
  fi

  case "$want" in
    github)
      if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        printf 'github\n'
      else
        printf 'none\n'
      fi
      ;;
    gitlab)
      if command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
        printf 'gitlab\n'
      else
        printf 'none\n'
      fi
      ;;
  esac
}

# jig_glab_fields <key>... — read `glab ... --output json` on stdin and print
# one tab-separated row of the given string fields per object, skipping an
# object whose first field is empty. `glab` returns a compact single-line
# array, so it is split into one object per line first: a greedy `.*` across
# the whole line would keep only the last merge request. Each field is taken
# at its first occurrence, whatever the key order: nested objects (author,
# assignees) carry a `state` of their own, later on. Housekeeping and
# jig_ship_pr both read `glab` through this, so they cannot disagree on it.
jig_glab_fields() {
  sed 's/},[[:space:]]*{/}\
{/g' | awk -v keys="$*" '
    function field(key,   k) {
      k = "\"" key "\":\""
      if (!match($0, k "[^\"]*\"")) return ""
      return substr($0, RSTART + length(k), RLENGTH - length(k) - 1)
    }
    BEGIN { n = split(keys, want, " ") }
    {
      row = field(want[1])
      if (row == "") next
      for (i = 2; i <= n; i++) row = row "\t" field(want[i])
      print row
    }'
}

# --- shipping a change ---------------------------------------------------------
#
# The git steps `jig task ship` and `jig spec ship` both take, as far as
# `agent.git` allows (jig_agent_git, config.sh): commit what the agent staged,
# push a branch, open a pull request. Shared here because the two commands must
# never disagree about what may be committed, how a push is made or when a pull
# request is a duplicate, and one command library never sources another
# (ARCHITECTURE.md, Scripts layout). Each caller keeps its own gates — a task's
# knowledge decision and review, a spec's mode — and decides which of these
# steps to take; <who> prefixes every message with the command that was run.
# Nothing here stages, forces a push, skips hooks or merges
# (adr-20260921-agent-git-rights-are-a-local-setting).

# Referenced from the EXIT trap jig_ship_pr sets for the pull request body it
# cuts from a commit message, so it is script-global rather than `local`
# (conventions/shell.md: a trap runs after its function returned). One ship
# runs per dispatch, so this is the only EXIT trap in that process.
_JIG_SHIP_BODY_TMP=""
# The pull request's URL as jig_ship_pr found or opened it; empty when none.
JIG_SHIP_URL=""

# jig_ship_staged — the paths staged in the index, one per line.
jig_ship_staged() {
  git -C "$JIG_PROJECT" diff --cached --name-only 2>/dev/null | sed '/^$/d'
}

# jig_ship_check_staged <who> — refuse, changing nothing, when anything under
# .ai/workspace/ or .ai/runtime/ is staged: those are never committed
# (RULES.md).
jig_ship_check_staged() {
  local who="$1" bad="" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      "$JIG_AI_DIR/workspace/"* | "$JIG_AI_DIR/runtime/"*) bad="$bad
$p" ;;
    esac
  done <<EOF
$(jig_ship_staged)
EOF
  bad=$(printf '%s\n' "$bad" | sed '/^$/d')
  if [ -n "$bad" ]; then
    jig_die "$who: staged changes under $JIG_AI_DIR/workspace/ or $JIG_AI_DIR/runtime/ are not shippable:
$bad"
  fi
}

# jig_ship_commit <who> <message-file> — commit the index as it is: only what
# is staged, never `-a`; hooks run, never --no-verify. An empty index is not an
# error: the change may have been committed by an earlier run.
jig_ship_commit() {
  local who="$1" message_file="$2"
  if [ -n "$(jig_ship_staged)" ]; then
    git -C "$JIG_PROJECT" commit -F "$message_file" >/dev/null \
      || jig_die "$who: git commit failed"
    printf 'committed %s\n' "$(git -C "$JIG_PROJECT" rev-parse --short HEAD)"
  else
    printf 'nothing staged; no commit\n'
  fi
}

# jig_ship_push <who> <branch> — push <branch> to origin and track it. Never
# --force: a branch origin has moved past is refused by git, and the refusal
# is the answer.
jig_ship_push() {
  local who="$1" branch="$2" out
  if ! out=$(git -C "$JIG_PROJECT" push -u origin "$branch" 2>&1); then
    jig_die "$who: git push failed:
$out"
  fi
  printf 'pushed %s\n' "$branch"
}

# jig_ship_pr <who> <head> <base> <message-file> [<title>] [<body-file>] — open
# a pull request from <head> into <base> through whichever forge this checkout
# uses (jig_forge_kind), or report the one already open from <head> rather
# than opening a second. The title defaults to the message's first line, the
# body to the rest of it. With no usable forge it says the pull request is the
# human's and returns 0. Leaves the URL in JIG_SHIP_URL, so it is called
# directly, never in `$()`.
# shellcheck disable=SC2034 # JIG_SHIP_URL is read by the caller
jig_ship_pr() {
  local who="$1" head="$2" base="$3" message_file="$4" title="${5:-}" body_file="${6:-}" kind
  JIG_SHIP_URL=""
  kind=$(jig_forge_kind) || exit 1
  if [ "$kind" = none ]; then
    printf "no forge available; the pull request is the human's\n"
    return 0
  fi
  [ -n "$title" ] || title=$(head -n 1 "$message_file")
  if [ -z "$body_file" ]; then
    _JIG_SHIP_BODY_TMP=$(mktemp "${TMPDIR:-/tmp}/jig-ship-body.XXXXXX")
    trap '[ -z "${_JIG_SHIP_BODY_TMP:-}" ] || rm -f "$_JIG_SHIP_BODY_TMP"' EXIT
    tail -n +2 "$message_file" > "$_JIG_SHIP_BODY_TMP"
    body_file="$_JIG_SHIP_BODY_TMP"
  fi
  case "$kind" in
    github) _jig_ship_pr_github "$who" "$head" "$base" "$title" "$body_file" ;;
    gitlab) _jig_ship_pr_gitlab "$who" "$head" "$base" "$title" "$body_file" ;;
  esac
}

# _jig_ship_pr_github <who> <head> <base> <title> <body-file>
# shellcheck disable=SC2034 # JIG_SHIP_URL is read by the caller
_jig_ship_pr_github() {
  local who="$1" head="$2" base="$3" title="$4" body_file="$5" url out
  url=$(gh pr list --head "$head" --state open --json url --jq '.[0].url' 2>/dev/null || printf '')
  case "$url" in '' | null) url="" ;; esac
  if [ -n "$url" ]; then
    JIG_SHIP_URL="$url"
    printf 'pr %s (already open)\n' "$url"
    return 0
  fi
  out=$(gh pr create --base "$base" --head "$head" --title "$title" --body-file "$body_file" 2>&1) \
    || jig_die "$who: gh pr create failed:
$out"
  url=$(printf '%s\n' "$out" | tail -n 1)
  JIG_SHIP_URL="$url"
  printf 'pr %s\n' "$url"
}

# _jig_ship_pr_gitlab <who> <head> <base> <title> <body-file> — the same
# through `glab`, whose JSON is read by jig_glab_fields, the reader
# housekeeping uses.
# shellcheck disable=SC2034 # JIG_SHIP_URL is read by the caller
_jig_ship_pr_gitlab() {
  local who="$1" head="$2" base="$3" title="$4" body_file="$5" out url desc
  out=$(glab mr list --source-branch "$head" --output json 2>/dev/null || printf '')
  url=$(printf '%s' "$out" | jig_glab_fields web_url | head -n 1)
  if [ -n "$url" ]; then
    JIG_SHIP_URL="$url"
    printf 'pr %s (already open)\n' "$url"
    return 0
  fi
  desc=$(cat "$body_file")
  out=$(glab mr create --target-branch "$base" --source-branch "$head" --title "$title" --description "$desc" 2>&1) \
    || jig_die "$who: glab mr create failed:
$out"
  url=$(printf '%s\n' "$out" | grep -oE 'https://[^[:space:]]+' | tail -n 1)
  JIG_SHIP_URL="$url"
  printf 'pr %s\n' "${url:-$out}"
}

# --- specification links ------------------------------------------------------

# jig_spec_link <task.md> — the spec id a task links to, or nothing.
#
# A link is a whole line `Spec: .ai/specs/<id>/`, optionally followed by a
# dash and `Phase <n>`. A line whose id breaks the id grammar links to
# nothing. Exits 2 when the file links to two different specs: which roadmap
# to read would be a guess. Here rather than in spec.sh because `task start`
# needs it too, and one command library never sources another.
jig_spec_link() {
  awk '
    /^Spec: \.ai\/specs\/[A-Za-z0-9._-]+\/([[:space:]]+(—|-|--)[[:space:]]+Phase[[:space:]]+[0-9]+)?[[:space:]]*$/ {
      id = $0
      sub(/^Spec: \.ai\/specs\//, "", id)
      sub(/\/.*$/, "", id)
      if (id ~ /^[.-]/) next
      if (found == "") found = id
      else if (found != id) conflict = 1
    }
    END {
      if (conflict) exit 2
      if (found != "") print found
    }
  ' "$1"
}

# jig_spec_epic <roadmap.md|-> — "<branch> open" or "<branch> finished" when
# the roadmap declares an epic branch, nothing when it does not (ADR-0040).
#
# The declaration is a whole line `Epic: <branch>`, closed before the epic's
# final pull request as `Epic: <branch> — finished`. Exits 2 when two lines
# disagree, on the branch or on its state: which base a task is cut from
# would be a guess. The branch name is not validated here; a caller that
# builds a ref from it runs `git check-ref-format --branch` first.
jig_spec_epic() {
  awk '
    /^Epic:[[:space:]]+[^[:space:]]+([[:space:]]+(—|-|--)[[:space:]]+finished)?[[:space:]]*$/ {
      line = $0
      sub(/^Epic:[[:space:]]+/, "", line)
      b = line
      sub(/[[:space:]].*$/, "", b)
      st = (line ~ /finished[[:space:]]*$/) ? "finished" : "open"
      v = b " " st
      if (found == "") found = v
      else if (found != v) conflict = 1
    }
    END {
      if (conflict) exit 2
      if (found != "") print found
    }
  ' "$1"
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
# `--base-branch <name>` names the base a task was cut from (jig_task_base);
# without it the configured `git.base_branch` is used. Either way the base is
# resolved as jig_base_ref resolves it, origin first.
#
# Lives here rather than in one command's library because `context` and
# `knowledge paths` both need the same answer to "what did this task touch",
# and they must never disagree about it (ARCHITECTURE.md, scripts layout).
jig_git_touched_files() {
  local base=""
  if [ "${1:-}" = "--base-branch" ]; then
    [ "$#" -ge 2 ] || { jig_warn "jig_git_touched_files: --base-branch requires a value"; return 1; }
    base="$2"
    shift 2
  fi
  if [ "$#" -gt 0 ]; then
    local explicit_base explicit_head explicit_rows
    explicit_base=$(jig_review_commit "$1") || return 1
    explicit_head=$(jig_review_commit "${2:-HEAD}") || return 1
    explicit_rows=$(jig_git_change_rows "$explicit_base" "$explicit_head") || return 1
    printf '%s\n' "$explicit_rows" | sed '/^$/d' | cut -f1 | LC_ALL=C sort -u
    return 0
  fi
  local ref mb out=""
  [ -n "$base" ] || base=$(cfg git.base_branch main)
  ref=$(jig_base_ref "$base")
  if [ -n "$ref" ] && mb=$(git -C "$JIG_PROJECT" merge-base "$ref" HEAD 2>/dev/null); then
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

# jig_knowledge_source <doc> — the `source:` a document links, or nothing.
# A document with one is a stub for an existing file (ADR-0036). `knowledge`
# validates stubs and `context` resolves them to their sources, and the two
# must agree on what a stub is — so the question is asked here, once.
# Callers have sourced frontmatter.sh, as both commands do.
jig_knowledge_source() {
  fm_get "$1" source
}

# jig_knowledge_read_path <doc> — the repository-relative path an agent reads
# for <doc>: the source of a stub, the document itself otherwise. Exit 3, with
# the source path still printed, when a stub's source is not a regular file
# inside the repository — a path that could leave it, a symlink, or a file
# reached through a symlinked directory. Checked on every resolution, not only
# at acceptance: a hand-edited stub is not validated before it is resolved, and
# a source can be swapped for a link to `/etc/passwd` after it was accepted
# without touching the stub. Whether git tracks the file with this exact case
# is `knowledge check`'s question, not this one's.
jig_knowledge_read_path() {
  local src
  src=$(jig_knowledge_source "$1")
  if [ -z "$src" ]; then
    jig_relpath "$1" "$JIG_PROJECT"
    return 0
  fi
  printf '%s\n' "$src"
  case "$src" in
    /* | ../* | */../* | *.. ) return 3 ;;
  esac
  if [ ! -f "$JIG_PROJECT/$src" ] || [ -L "$JIG_PROJECT/$src" ]; then
    return 3
  fi
  local root dir
  root=$(cd -P "$JIG_PROJECT" 2>/dev/null && pwd -P) || return 3
  dir=$(cd -P "$(dirname "$JIG_PROJECT/$src")" 2>/dev/null && pwd -P) || return 3
  case "$dir/" in
    "$root/"*) return 0 ;;
    *) return 3 ;;
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

# jig_trash_dest <name> — where <name> goes in trash today:
# .ai/runtime/trash/<date>/<name>, or <name>-2, -3, … when that is taken. Never
# overwrites and never merges into an existing entry (ADR-0006). Shared by
# housekeeping (a workspace, named by its task id) and `jig spec remove`
# (`spec-<id>`), so two commands putting things in the same trash cannot
# disagree about collisions. Prints the path; creates nothing.
jig_trash_dest() {
  local base dest n
  base="$JIG_PROJECT/$JIG_AI_DIR/runtime/trash/$(jig_today)/$1"
  dest="$base"
  n=2
  while [ -e "$dest" ]; do
    dest="$base-$n"
    n=$((n + 1))
  done
  printf '%s\n' "$dest"
}

# --- the live status page (adr-20260922-the-status-page-stays-current-without-a-server)
#
# The page, .ai/runtime/status.html, is redrawn by the commands that change
# what it shows, synchronously and from the counts the last full `jig status`
# cached, so a redraw costs a fraction of a second. Shared here because task,
# spec and housekeeping all trigger it and none of them may source status.sh:
# the redraw is a process, `jig status --refresh`, the way one domain runs
# another's command (ARCHITECTURE.md, Scripts layout).

_JIG_PAGE_DIRTY=""

# jig_status_page_touch [--full | --refresh] — redraw the clone's status page
# if it exists.
# One page per clone: a command run in a task worktree redraws the page of the
# main checkout, with that checkout's own jig. A page nobody has opened yet
# (`jig status --html` or `--open` writes the first one) is never created
# here. --full recounts everything and refreshes the cached counts
# (`status --html`); --refresh, the default, reads them (`status --refresh`).
# Callers in this file pass the mode explicitly: shellcheck 0.9.0 reports
# SC2120 on a function that reads $1 when every call it can see passes none.
# Always returns 0 and prints nothing: a failed redraw never changes the
# output or the exit code of the command that triggered it.
jig_status_page_touch() {
  local mode="--refresh" root jig
  [ "${1:-}" != --full ] || mode="--html"
  root=$(jig_config_clone_root 2>/dev/null) || return 0
  [ -f "$root/$JIG_AI_DIR/runtime/status.html" ] || return 0
  jig="$root/$JIG_AI_DIR/scripts/jig"
  [ -f "$jig" ] || return 0
  (cd "$root" && bash "$jig" status "$mode") </dev/null >/dev/null 2>&1 || true
  return 0
}

# jig_status_page_dirty — note that this command changed something the page
# shows. The writers call it themselves, so a new command that writes through
# them is covered without anyone remembering to; jig_status_page_flush then
# redraws once, however many writes came before.
jig_status_page_dirty() { _JIG_PAGE_DIRTY=1; }

# jig_status_page_flush — redraw the page when this command changed something.
jig_status_page_flush() {
  [ -n "${_JIG_PAGE_DIRTY:-}" ] || return 0
  _JIG_PAGE_DIRTY=""
  jig_status_page_touch --refresh
}

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

# jig_hash_list <base> <file> — the blob hash of every path listed in <file>,
# one per line and in the same order, from a single `git hash-object` process
# run in <base>. Nothing for an empty list. Every listed path must exist under
# <base>: git fails the whole batch otherwise, which the caller turns into an
# error rather than a missing hash.
#
# The paths are relative to <base>, never absolute. MSYS converts a path only
# when it is an argument; on stdin Git for Windows gets /tmp/... verbatim and
# cannot open it — `jig upgrade` died on every Windows run with "could not open
# '/tmp/jig-upgrade-stage…'". A relative path is spelled the same everywhere.
#
# Use this, not a loop over jig_hash, whenever there is more than one file.
# Each call is a git startup, and on 65 manifest files the loop took 0.879 s
# where one call took 0.013 s — it was most of what `jig status` cost.
# Pair the output back with its paths by position (`paste`); a path containing
# a newline would desync that, and none of jig's line-based lists can hold one.
jig_hash_list() {
  [ -s "$2" ] || return 0
  (cd "$1" && git hash-object --stdin-paths) < "$2"
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
