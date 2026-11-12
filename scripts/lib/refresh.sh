# cmd_refresh — bring this clone up to origin, for a person or a program that shows
# the project (adr-20261112-refresh-brings-the-clone-up-to-origin): fetch origin, then
# fast-forward the base branch to origin's, without moving the person's checkout and
# never over their changes. A base that cannot move is an answer, not a failure: it
# says why, and the command exits 0. Reads stay offline; this is the one command a
# program runs to make what they show current.
# shellcheck shell=bash

REFRESH_USAGE="usage: jig refresh [--json]"

_REFRESH_AS_JSON=""
_REFRESH_FETCH=""
_REFRESH_FETCH_MSG=""
_REFRESH_BASE=""
_REFRESH_OUTCOME=""
_REFRESH_FROM=""
_REFRESH_TO=""
_REFRESH_MSG=""
_REFRESH_WHERE=""

cmd_refresh() {
  local arg
  for arg in "$@"; do
    if [ "$arg" = --json ]; then
      # shellcheck source=lib/json.sh
      . "$JIG_LIB/json.sh"
      _REFRESH_AS_JSON=1
      json_run _refresh_main "$@"
      return
    fi
  done
  _refresh_main "$@"
}

_refresh_main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --json) ;;
      -h | --help) printf '%s\n' "$REFRESH_USAGE"; return 0 ;;
      *) jig_fail usage "refresh: unexpected argument: $arg; $REFRESH_USAGE" ;;
    esac
  done
  jig_require_init
  _REFRESH_BASE=$(cfg git.base_branch main)
  _refresh_fetch
  _refresh_base
  # What the status page shows moved with the base (base-behind-origin, landed knowledge).
  jig_status_page_touch >/dev/null 2>&1 || true
  if [ -n "$_REFRESH_AS_JSON" ]; then
    _refresh_json
  else
    _refresh_text
  fi
}

# _refresh_fetch — fetch origin as housekeeping does (_hk_fetch): the clone's own
# account, no prompt, `--no-prune` so a squash-merged branch keeps the origin/ ref its
# deletion is checked against. Bounded, since a program waits on the answer.
_refresh_fetch() {
  local err
  if ! git -C "$JIG_PROJECT" remote get-url origin >/dev/null 2>&1; then
    _REFRESH_FETCH=skipped
    _REFRESH_FETCH_MSG="this clone has no origin"
    return 0
  fi
  jig_git_origin_account refresh read
  _JIG_NET_DEADLINE=$(( $(date +%s) + _JIG_NET_CALL ))
  if err=$(jig_net jig_git_origin fetch --quiet --no-prune origin 2>&1 >/dev/null); then
    _REFRESH_FETCH="done"
  else
    _REFRESH_FETCH=failed
    _REFRESH_FETCH_MSG=$(printf '%s\n' "$err" | sed '/^[[:space:]]*$/d' | tail -n 3)
    [ -n "$_REFRESH_FETCH_MSG" ] || _REFRESH_FETCH_MSG="git fetch failed"
  fi
  _JIG_NET_DEADLINE=""
}

# _refresh_checked_out_at <branch> — the worktree <branch> is checked out in, or nothing.
# A list git could not give is answered `?`: the base may be checked out, and stays.
_refresh_checked_out_at() {
  local list
  list=$(git -C "$JIG_PROJECT" worktree list --porcelain 2>/dev/null) || { printf '?\n'; return 0; }
  printf '%s\n' "$list" | awk -v want="branch refs/heads/$1" '
    /^worktree / { wt = substr($0, 10) }
    $0 == want { print wt; exit }'
}

# _refresh_base — fast-forward the base to origin's, the only move it ever makes:
# `merge --ff-only` where it is checked out here (git itself refuses to touch changes a
# fast-forward would overwrite), `git branch -f` where it is checked out nowhere — git
# refuses that for a branch any worktree has checked out, or is rebasing or bisecting;
# elsewhere, ahead, diverged or missing, nothing moves.
_refresh_base() {
  local base="$_REFRESH_BASE" local_sha origin_sha here out
  origin_sha=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/remotes/origin/$base^{commit}" 2>/dev/null) || origin_sha=""
  local_sha=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/heads/$base^{commit}" 2>/dev/null) || local_sha=""
  _REFRESH_FROM=$local_sha
  _REFRESH_TO=$local_sha
  if [ -z "$origin_sha" ] || [ -z "$local_sha" ]; then
    _REFRESH_OUTCOME=missing
    if [ -z "$origin_sha" ]; then
      _REFRESH_MSG="origin/$base is not known here"
    else
      _REFRESH_MSG="there is no branch $base here"
    fi
    return 0
  fi
  if [ "$local_sha" = "$origin_sha" ]; then
    _REFRESH_OUTCOME=up-to-date
    return 0
  fi
  if ! git -C "$JIG_PROJECT" merge-base --is-ancestor "$local_sha" "$origin_sha" 2>/dev/null; then
    _REFRESH_OUTCOME=diverged
    _REFRESH_MSG="$base here has commits origin/$base does not have, so it cannot be fast-forwarded"
    return 0
  fi
  here=$(git -C "$JIG_PROJECT" symbolic-ref --quiet HEAD 2>/dev/null) || here=""
  if [ "$here" = "refs/heads/$base" ]; then
    # merge.autoStash off: refresh never stashes (a person's config may say otherwise).
    if out=$(git -C "$JIG_PROJECT" -c merge.autoStash=false merge --ff-only -q "$origin_sha" 2>&1); then
      _REFRESH_OUTCOME=fast-forwarded
      _REFRESH_TO=$origin_sha
    else
      _REFRESH_OUTCOME=blocked-by-changes
      _REFRESH_MSG=$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d')
      [ -n "$_REFRESH_MSG" ] || _REFRESH_MSG="git refused to fast-forward $base over the changes in this checkout"
    fi
    return 0
  fi
  _REFRESH_WHERE=$(_refresh_checked_out_at "$base")
  if [ "$_REFRESH_WHERE" = "?" ]; then
    _REFRESH_WHERE=""
    _REFRESH_OUTCOME=checked-out-elsewhere
    _REFRESH_MSG="git could not list this clone's worktrees, so $base may be checked out in one; nothing was changed"
    return 0
  fi
  if [ -n "$_REFRESH_WHERE" ]; then
    _REFRESH_OUTCOME=checked-out-elsewhere
    _REFRESH_MSG="$base is checked out in $_REFRESH_WHERE; it moves there, with \`jig refresh\` run in it"
    return 0
  fi
  if [ "$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/heads/$base^{commit}" 2>/dev/null)" != "$local_sha" ]; then
    _REFRESH_OUTCOME=diverged
    _REFRESH_MSG="$base moved while it was being fast-forwarded; nothing was changed"
  elif out=$(git -C "$JIG_PROJECT" branch -f "$base" "$origin_sha" 2>&1); then
    _REFRESH_OUTCOME=fast-forwarded
    _REFRESH_TO=$origin_sha
  else
    _REFRESH_OUTCOME=checked-out-elsewhere
    _REFRESH_MSG=$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d')
    [ -n "$_REFRESH_MSG" ] || _REFRESH_MSG="git refused to move $base"
  fi
}

_refresh_text() {
  case "$_REFRESH_FETCH" in
    done) printf 'fetch: done\n' ;;
    *) printf 'fetch: %s (%s)\n' "$_REFRESH_FETCH" "$_REFRESH_FETCH_MSG" ;;
  esac
  case "$_REFRESH_OUTCOME" in
    fast-forwarded) printf '%s: fast-forwarded %s..%s\n' "$_REFRESH_BASE" "${_REFRESH_FROM:0:12}" "${_REFRESH_TO:0:12}" ;;
    up-to-date) printf '%s: up to date with origin/%s\n' "$_REFRESH_BASE" "$_REFRESH_BASE" ;;
    *) printf '%s: %s — %s\n' "$_REFRESH_BASE" "$_REFRESH_OUTCOME" "$(printf '%s' "$_REFRESH_MSG" | tr '\n' ' ' | sed 's/ *$//')" ;;
  esac
}

_refresh_json() {
  local rec fetched_at
  fetched_at=$(jig_origin_fetched_at) || fetched_at=""
  json_quote "$_REFRESH_FETCH"; rec="{\"fetch\":{\"outcome\":$_JSON"
  json_str_or_null "$_REFRESH_FETCH_MSG"; rec="$rec,\"message\":$_JSON"
  json_str_or_null "$fetched_at"; rec="$rec,\"fetched_at\":$_JSON}"
  json_quote "$_REFRESH_BASE"; rec="$rec,\"base\":{\"name\":$_JSON"
  json_quote "$_REFRESH_OUTCOME"; rec="$rec,\"outcome\":$_JSON"
  json_str_or_null "$_REFRESH_FROM"; rec="$rec,\"from\":$_JSON"
  json_str_or_null "$_REFRESH_TO"; rec="$rec,\"to\":$_JSON"
  json_str_or_null "$_REFRESH_WHERE"; rec="$rec,\"checked_out_in\":$_JSON"
  json_str_or_null "$_REFRESH_MSG"; rec="$rec,\"message\":$_JSON}}"
  printf '%s\n' "$rec"
}
