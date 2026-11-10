# cmd_pr — somebody else's pull request, read in the person's own clone
# (adr-20261109-a-pull-request-is-read-in-a-detached-tree-of-the-clone; the
# `jig-pr-review` skill): `fetch` takes its head and base into refs of Jig's
# own and a detached worktree beside the repository, `draft` checks and keeps
# the review as it will be shown (skills/jig-pr-review/references/draft.md), `list` says what is
# fetched, and `cleanup` takes all of it back.
#
# Nothing from the pull request's head is ever run: every git call here goes
# through _pr_git, which points `core.hooksPath` at nothing — a relative hooks
# path (`.githooks`, `.husky`) would otherwise run the head's own hook on the
# checkout of the worktree. The forge is the one the URL names, never
# jig_forge_kind's: that answers for `origin`, and the pull request may live
# on another host.
# shellcheck shell=bash

PR_USAGE="usage: jig pr fetch <url> | jig pr draft <n|url> [--from <file>] | jig pr comments check <n|url> | jig pr comments post <n|url> --shown <hash> | jig pr list | jig pr cleanup <n|url>"

cmd_pr() {
  local sub="${1:-}"
  if [ $# -gt 0 ]; then shift; fi
  jig_require_repo
  _pr_refuse_inside_a_review_tree
  case "$sub" in
    fetch) _pr_fetch "$@" ;;
    draft) _pr_draft "$@" ;;
    comments) _pr_comments "$@" ;;
    list) _pr_list "$@" ;;
    cleanup) _pr_cleanup "$@" ;;
    help | -h | --help) printf '%s\n' "$PR_USAGE" ;;
    '') jig_fail usage "pr: a subcommand is required; $PR_USAGE" ;;
    *) jig_fail usage "pr: unknown subcommand: $sub; $PR_USAGE" ;;
  esac
}

# --- git, with nothing of the head's run ------------------------------------------

# _pr_git <dir> <args>... — git in <dir> with hooks pointed at /dev/null (a file,
# so no hook can exist under it), submodules not followed and LFS objects not
# downloaded. No MSYS2_ARG_CONV_EXCL here: under Git Bash it would hand <dir>
# to git as an MSYS path (`/c/Users/...`) that git cannot change into, and the
# refspecs and ref names passed here start with `refs/`, which MSYS leaves alone.
_pr_git() {
  local dir="$1"
  shift
  GIT_LFS_SKIP_SMUDGE=1 \
    git -C "$dir" -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"
}

# _pr_refuse_inside_a_review_tree — jig pr runs in the person's own checkout,
# never in a review tree: there the head's hooks path, `.ai/config.yaml` and
# `.ai/scripts` are the author's. A checkout named `.pr-<n>` that is not the
# clone's main checkout is taken for one.
_pr_refuse_inside_a_review_tree() {
  local clone
  case "$(basename "$JIG_PROJECT")" in
    .pr-[0-9]*) ;;
    *) return 0 ;;
  esac
  clone=$(jig_config_clone_root)
  if [ "$clone" != "$JIG_PROJECT" ]; then
    jig_die "pr: $JIG_PROJECT is a pull request's review tree; run jig pr in your own checkout ($clone)"
  fi
}

# --- names --------------------------------------------------------------------------

# _pr_parse_url <url> — sets _PR_HOST, _PR_OWNER, _PR_REPO, _PR_N and _PR_URL
# (the canonical form) from https://<host>/<owner>/<repo>/pull/<n>, with any
# trailing path (`/files`), query or fragment dropped. Exit 2 for a GitLab merge
# request, 1 for anything else that is not a pull request URL.
_PR_HOST="" _PR_OWNER="" _PR_REPO="" _PR_N="" _PR_URL=""
_pr_parse_url() {
  local rest host path owner repo kind n
  case "$1" in
    https://*) rest=${1#https://} ;;
    http://*) rest=${1#http://} ;;
    *) return 1 ;;
  esac
  rest=${rest%%#*}
  rest=${rest%%\?*}
  case "$rest" in */-/merge_requests/*) return 2 ;; esac
  host=${rest%%/*}
  [ "$host" != "$rest" ] || return 1
  path=${rest#*/}
  owner=${path%%/*}
  path=${path#*/}
  repo=${path%%/*}
  path=${path#*/}
  kind=${path%%/*}
  path=${path#*/}
  n=${path%%/*}
  [ "$kind" = pull ] || return 1
  case "$host" in '' | *[!A-Za-z0-9.:-]*) return 1 ;; esac
  _pr_valid_slug_part "$owner" || return 1
  _pr_valid_slug_part "$repo" || return 1
  _pr_valid_number "$n" || return 1
  _PR_HOST=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')
  _PR_OWNER="$owner"
  _PR_REPO="$repo"
  _PR_N="$n"
  _PR_URL="https://$_PR_HOST/$owner/$repo/pull/$n"
}

# An owner or repository name: GitHub's characters, and never `.` or `..`.
_pr_valid_slug_part() {
  case "$1" in
    '' | . | .. | *[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

# A pull request number becomes part of a path and a ref name: digits only, no
# leading zero, at most nine of them.
_pr_valid_number() {
  case "$1" in
    '' | 0* | *[!0-9]* | ??????????*) return 1 ;;
    *) return 0 ;;
  esac
}

# _pr_resolve <who> <n|url> — sets _PR_N from a number or a pull request URL.
# A URL must be the one recorded for that number, when one is.
_pr_resolve() {
  local who="$1" arg="$2" rc=0 rec recorded
  if _pr_valid_number "$arg"; then
    _PR_N="$arg"
    return 0
  fi
  _pr_parse_url "$arg" || rc=$?
  case "$rc" in
    0) ;;
    2) jig_fail usage "pr $who: GitLab merge requests are not supported yet: $arg" ;;
    *) jig_fail usage "pr $who: not a pull request number or URL: $arg" ;;
  esac
  rec="$(_pr_state_dir "$_PR_N")/record"
  if [ -f "$rec" ]; then
    recorded=$(_pr_record_get "$rec" url)
    [ "$recorded" = "$_PR_URL" ] \
      || jig_die "pr $who: pull request $_PR_N of this clone is $recorded, not $_PR_URL"
  fi
}

# --- where things live ----------------------------------------------------------------

# The clone's git directory, physical: worktrees share it.
_pr_common_dir() {
  local d
  d=$(_pr_git "$JIG_PROJECT" rev-parse --git-common-dir 2>/dev/null) || return 1
  (cd "$JIG_PROJECT" && cd "$d" && pwd -P)
}

# _pr_state_dir <n> — where pull request <n>'s record and draft are kept: the
# clone's own .ai/workspace/pr/<n>/ when Jig is installed there and git ignores
# that path; otherwise <git-common-dir>/jig/pr/<n>/, inside the clone but out
# of its working tree, so nothing is left in somebody else's tree. <n> is
# checked here, the one function that builds the path.
_pr_state_dir() {
  local n="$1" clone common
  _pr_valid_number "$n" || jig_die "pr: not a pull request number: $n"
  clone=$(jig_config_clone_root)
  if [ -f "$clone/$JIG_AI_DIR/config.yaml" ] \
     && _pr_git "$clone" check-ignore -q "$JIG_AI_DIR/workspace/pr/$n/record" 2>/dev/null; then
    printf '%s/%s/workspace/pr/%s\n' "$clone" "$JIG_AI_DIR" "$n"
  else
    common=$(_pr_common_dir) || common=""
    [ -n "$common" ] || jig_die "pr: cannot find this clone's git directory"
    printf '%s/jig/pr/%s\n' "$common" "$n"
  fi
}

# _pr_worktree_path <n> — <git.worktree_root>/.pr-<n>, beside the repository.
# The setting means what it means for `task start --worktree`
# (_task_worktree_root, task.sh), but a relative root is joined to the clone's
# main checkout rather than to the checkout jig runs in, so that every checkout
# of the clone finds the same tree; the leading dot keeps the name out
# of jig_valid_id's grammar, so no task's worktree can ever be made there.
_pr_worktree_path() {
  local n="$1" clone root
  _pr_valid_number "$n" || jig_die "pr: not a pull request number: $n"
  clone=$(jig_config_clone_root)
  root=$(cfg git.worktree_root "")
  [ -n "$root" ] || root="../$(basename "$clone").worktrees"
  case "$root" in
    /*) printf '%s/.pr-%s\n' "$root" "$n" ;;
    *) printf '%s/%s/.pr-%s\n' "$clone" "$root" "$n" ;;
  esac
}

# _pr_physical <path> — <path> with every link resolved, or nothing when it
# does not exist.
_pr_physical() {
  (cd -P "$1" 2>/dev/null && pwd -P) || true
}

# _pr_worktree_kind <path> — what git says stands at <path>: `detached`,
# `locked` (a detached worktree somebody locked), `branch` (a worktree with a
# branch checked out: never ours), or `none`. Compared physically, so git's
# spelling of the path (C:/… under Git Bash) does not matter.
_pr_worktree_kind() {
  local want p="" line kind="" locked=0 found=0
  want=$(_pr_physical "$1")
  [ -n "$want" ] || { printf 'none\n'; return 0; }
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        if [ "$found" = 1 ]; then break; fi
        p=$(_pr_physical "${line#worktree }")
        if [ "$p" = "$want" ]; then found=1; fi
        ;;
      detached) if [ "$found" = 1 ]; then kind=detached; fi ;;
      "branch "*) if [ "$found" = 1 ]; then kind=branch; fi ;;
      locked | "locked "*) if [ "$found" = 1 ]; then locked=1; fi ;;
    esac
  done < <(_pr_git "$JIG_PROJECT" worktree list --porcelain 2>/dev/null)
  if [ "$found" != 1 ]; then
    printf 'none\n'
  elif [ "$kind" = detached ] && [ "$locked" = 1 ]; then
    printf 'locked\n'
  else
    printf '%s\n' "${kind:-branch}"
  fi
}

# --- the record -------------------------------------------------------------------------

# _pr_record_get <file> <key> — the value of the first `<key>: ` line.
_pr_record_get() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$2: "*) printf '%s\n' "${line#"$2: "}"; return 0 ;;
    esac
  done < "$1"
  return 0
}

# _pr_write <file> <content> — atomically, through a temporary beside it.
_pr_write() {
  local tmp="$1.tmp.$$"
  jig_cleanup_add "$tmp"
  printf '%s' "$2" > "$tmp"
  mv -f "$tmp" "$1"
}

# --- the remote and the forge ------------------------------------------------------------

# _pr_remote_names <remote-url> <host> <owner/repo> — exit 0 when <remote-url>
# reaches <owner/repo> on <host>: https, ssh:// or scp form, `.git` or not,
# owner and repository without regard to case, and an SSH alias resolved to the
# host it stands for (_jig_ssh_alias_hostname, common.sh).
_pr_remote_names() {
  local url="$1" host="$2" slug="$3" h path alias
  case "$url" in
    *://*)
      path=${url#*://}
      h=${path%%/*}
      path=${path#*/}
      h=${h#*@}
      h=${h%%:*}
      ;;
    *:*)
      h=${url%%:*}
      case "$h" in */*) return 1 ;; esac
      h=${h#*@}
      path=${url#*:}
      ;;
    *) return 1 ;;
  esac
  path=${path#/}
  path=${path%/}
  path=${path%.git}
  path=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  [ "$path" = "$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')" ] || return 1
  h=$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')
  if [ "$h" = "${host%%:*}" ]; then return 0; fi
  alias=$(_jig_ssh_alias_hostname "$url")
  if [ -n "$alias" ] && [ "$(printf '%s' "$alias" | tr '[:upper:]' '[:lower:]')" = "${host%%:*}" ]; then
    return 0
  fi
  return 1
}

# _pr_remote_for <host> <owner/repo> — the name of the first remote of this
# clone that reaches the pull request's repository, as configured (the raw
# `remote.<name>.url`, before any insteadOf).
_pr_remote_for() {
  local name url
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    url=$(_pr_git "$JIG_PROJECT" config --get "remote.$name.url" 2>/dev/null) || continue
    if _pr_remote_names "$url" "$1" "$2"; then
      printf '%s\n' "$name"
      return 0
    fi
  done < <(_pr_git "$JIG_PROJECT" remote 2>/dev/null)
  return 1
}

# _pr_accounts <host> — "<accounts><TAB><active>": the logins `gh` holds for
# <host> that are signed in, space-separated, and the active one. Read from
# `gh auth status`, whose exit status is ignored: it fails as a whole when one
# account is broken, and the others still count. An older gh that names one
# account (`Logged in to <host> as <login>`) and no active line makes that one
# active.
_pr_accounts() {
  local out
  out=$(jig_net gh auth status --hostname "$1" 2>&1) || true
  printf '%s\n' "$out" | awk '
    /Logged in to / && !/Failed/ {
      login = ""
      for (i = 1; i < NF; i++) if ($i == "account" || $i == "as") { login = $(i + 1); break }
      gsub(/[()]/, "", login)
      if (login != "") { n++; names = names (names == "" ? "" : " ") login; last = login }
      next
    }
    /Active account: true/ { if (last != "") active = last }
    END {
      if (active == "" && n == 1) active = last
      printf "%s\t%s\n", names, active
    }'
}

# _pr_token_env <host> — the token variables set in this environment that gh
# would use for <host> instead of any stored account.
_pr_token_env() {
  local names="" v
  if _pr_dotcom_kind "$1"; then
    for v in GH_TOKEN GITHUB_TOKEN; do
      eval "[ -z \"\${$v:-}\" ]" || names="$names${names:+ }$v"
    done
  else
    for v in GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; do
      eval "[ -z \"\${$v:-}\" ]" || names="$names${names:+ }$v"
    done
  fi
  printf '%s\n' "$names"
}

# --- accounts and tokens ------------------------------------------------------------------

# _pr_dotcom_kind <host> — exit 0 for a host gh reads GH_TOKEN/GITHUB_TOKEN for:
# github.com and GitHub's tenancy hosts (*.ghe.com); any other host is a GitHub
# Enterprise Server, read from GH_ENTERPRISE_TOKEN/GITHUB_ENTERPRISE_TOKEN.
_pr_dotcom_kind() {
  case "$1" in
    github.com | *.ghe.com) return 0 ;;
    *) return 1 ;;
  esac
}

# What _pr_propose_login found, and the token the next _pr_gh call uses.
_PR_TOKEN="" _PR_ACCOUNTS="" _PR_ACTIVE="" _PR_TOKEN_ENV="" _PR_LOGIN="" _PR_WHY=""

# _pr_gh <args>... — `gh api --hostname <_PR_HOST> <args>`. With _PR_TOKEN set,
# that token is the one gh uses, for this call only: in a subshell every token
# variable is unset and the host's own (GH_TOKEN for github.com and *.ghe.com,
# GH_ENTERPRISE_TOKEN for a GitHub Enterprise Server) set to it. A token is never an
# argument, where ps would show it, and never written down; the active account
# and gh's configuration stay as they are. API paths are given without a
# leading `/` and no filter holds one: gh is a native program under Git Bash,
# and MSYS would take either for a path to convert.
_pr_gh() {
  (
    if [ -n "$_PR_TOKEN" ]; then
      unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
      # shellcheck disable=SC2030 # set in the subshell on purpose: for this call only
      if _pr_dotcom_kind "$_PR_HOST"; then
        GH_TOKEN="$_PR_TOKEN"
        export GH_TOKEN
      else
        # shellcheck disable=SC2030 # as above
        GH_ENTERPRISE_TOKEN="$_PR_TOKEN"
        export GH_ENTERPRISE_TOKEN
      fi
    fi
    jig_net gh api --hostname "$_PR_HOST" "$@"
  )
}

# _pr_stored_token <login> — the token gh keeps for <login> on _PR_HOST, asked
# with every token variable unset so that gh answers for the stored account
# (`gh auth token --user`, gh 2.40 and later).
_pr_stored_token() {
  local t
  t=$(
    unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
    jig_net gh auth token --hostname "$_PR_HOST" --user "$1" 2>/dev/null
  ) || return 1
  t=$(printf '%s' "$t" | tr -d '\r\n')
  [ -n "$t" ] || return 1
  printf '%s\n' "$t"
}

# _pr_env_token — the token gh would take from the environment for _PR_HOST.
# shellcheck disable=SC2031 # the environment's own, never _pr_gh's
_pr_env_token() {
  if _pr_dotcom_kind "$_PR_HOST"; then
    printf '%s\n' "${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  else
    printf '%s\n' "${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN:-}}"
  fi
}

# _pr_access <owner/repo> — what the account of _PR_TOKEN may do there:
# `comment` as a member (push, triage, maintain or admin, or read on a private
# repository), `read` when it only reads (on a public repository every account
# does), `none` when GitHub shows it nothing.
_pr_access() {
  local out priv pull push triage maintain admin
  out=$(_pr_gh "repos/$1" \
    --jq '[.private, .permissions.pull, .permissions.push, .permissions.triage, .permissions.maintain, .permissions.admin] | map(tostring) | join(" ")' \
    2>/dev/null) || out=""
  out=$(printf '%s' "$out" | tr -d '\r')
  read -r priv pull push triage maintain admin <<EOF
$out
EOF
  if [ "$push" = true ] || [ "$triage" = true ] || [ "$maintain" = true ] || [ "$admin" = true ]; then
    printf 'comment\n'
  elif [ "$pull" = true ] && [ "$priv" = true ]; then
    printf 'comment\n'
  elif [ "$pull" = true ]; then
    printf 'read\n'
  else
    printf 'none\n'
  fi
}

# _pr_propose_login <owner/repo> — sets _PR_ACCOUNTS, _PR_ACTIVE, _PR_TOKEN_ENV,
# and the login to propose: _PR_LOGIN is the one account that may comment as a
# member, or `ask` with _PR_WHY saying why not (none, several, a token in the
# environment, a gh that gives no token per account). Leaves in _PR_TOKEN the
# first account that can read the repository, for the reads that follow; none
# leaves gh to its own choice.
_pr_propose_login() {
  local slug="$1" a t acc commenters="" reader="" n=0 tokens=0 tab
  tab=$(printf '\t')
  IFS="$tab" read -r _PR_ACCOUNTS _PR_ACTIVE <<EOF
$(_pr_accounts "$_PR_HOST")
EOF
  _PR_TOKEN_ENV=$(_pr_token_env "$_PR_HOST")
  _PR_LOGIN=ask _PR_WHY="" _PR_TOKEN=""
  if [ -n "$_PR_TOKEN_ENV" ]; then
    _PR_WHY="$_PR_TOKEN_ENV in the environment overrides every gh account"
    return 0
  fi
  if [ -z "$_PR_ACCOUNTS" ]; then
    _PR_WHY="gh holds no account for $_PR_HOST"
    return 0
  fi
  set -f
  for a in $_PR_ACCOUNTS; do
    t=$(_pr_stored_token "$a") || continue
    tokens=$((tokens + 1))
    _PR_TOKEN="$t"
    acc=$(_pr_access "$slug")
    case "$acc" in
      comment)
        commenters="$commenters${commenters:+ }$a"
        n=$((n + 1))
        if [ -z "$reader" ]; then reader="$t"; fi
        ;;
      read) if [ -z "$reader" ]; then reader="$t"; fi ;;
    esac
  done
  set +f
  _PR_TOKEN="$reader"
  if [ "$tokens" = 0 ]; then
    _PR_WHY="gh gives no token per account (gh auth token --user needs gh 2.40 or later); accounts: $_PR_ACCOUNTS"
  elif [ "$n" = 1 ]; then
    _PR_LOGIN="$commenters"
  elif [ "$n" = 0 ]; then
    _PR_WHY="no account may comment on $slug as a member; accounts: $_PR_ACCOUNTS"
  else
    _PR_WHY="several accounts may comment: $commenters; active: ${_PR_ACTIVE:-none}"
  fi
}

# _pr_pull_info <owner/repo> — `<base ref>\t<head sha>\t<state>\t<base sha>\t<locked>\t<changed files>`
# of pull request _PR_N, read with _PR_TOKEN.
_pr_pull_info() {
  local out
  out=$(_pr_gh "repos/$1/pulls/$_PR_N" \
    --jq '[.base.ref, .head.sha, .state, .base.sha, (.locked | tostring), (.changed_files | tostring)] | @tsv' \
    2>/dev/null) || return 1
  printf '%s\n' "$out" | tr -d '\r'
}

# --- fetch --------------------------------------------------------------------------------

_pr_fetch() {
  local rc=0 remote info base api_head state slug dir rec wt kind recorded head base_sha mb accounts active tok login why now t
  [ $# -eq 1 ] || jig_fail usage "pr fetch: one pull request URL is required; $PR_USAGE"
  _pr_parse_url "$1" || rc=$?
  case "$rc" in
    0) ;;
    2) jig_fail usage "pr fetch: GitLab merge requests are not supported yet: $1" ;;
    *) jig_fail usage "pr fetch: not a pull request URL (https://<host>/<owner>/<repo>/pull/<n>): $1" ;;
  esac
  slug="$_PR_OWNER/$_PR_REPO"
  remote=$(_pr_remote_for "$_PR_HOST" "$slug") \
    || jig_die "pr fetch: no remote of this clone reaches $slug on $_PR_HOST; run it in a local clone of that repository"

  dir=$(_pr_state_dir "$_PR_N")
  rec="$dir/record"
  if [ -f "$rec" ]; then
    recorded=$(_pr_record_get "$rec" url)
    [ "$recorded" = "$_PR_URL" ] \
      || jig_die "pr fetch: pull request $_PR_N of this clone is already $recorded; jig pr cleanup $_PR_N first"
  fi
  wt=$(_pr_worktree_path "$_PR_N")
  kind=$(_pr_worktree_kind "$wt")
  case "$kind" in
    detached) ;;
    none) [ ! -e "$wt" ] || jig_die "pr fetch: $wt is in the way and is not a worktree of this clone; move it" ;;
    *) jig_die "pr fetch: $wt is a worktree jig did not make ($kind); move it" ;;
  esac

  command -v gh >/dev/null 2>&1 || jig_die "pr fetch: the GitHub CLI (gh) is needed to read $_PR_URL"
  t=$(printf '\t')
  _pr_propose_login "$slug"
  info=$(_pr_pull_info "$slug") \
    || jig_die "pr fetch: GitHub did not answer for $_PR_URL (gh auth status --hostname $_PR_HOST)"
  IFS="$t" read -r base api_head state _ <<EOF
$info
EOF
  git check-ref-format --branch "$base" >/dev/null 2>&1 \
    || jig_die "pr fetch: GitHub named no usable base branch for $_PR_URL: $base"
  case "$api_head" in
    *[!0-9a-f]* | '') jig_die "pr fetch: GitHub named no head commit for $_PR_URL" ;;
  esac

  # Only into refs of Jig's own: the person's branches, remote-tracking refs and
  # FETCH_HEAD stay as they are.
  # --refmap= (empty) keeps git from also moving refs/remotes/<remote>/<base>,
  # which it does for a named remote whose fetch refspec covers the branch.
  local fetch_opts="--no-tags --no-recurse-submodules --refmap=" help
  # `fetch -h` exits 129, so its text is caught, not piped.
  help=$(git fetch -h 2>&1) || true
  case "$help" in
    *write-fetch-head*) fetch_opts="$fetch_opts --no-write-fetch-head" ;;
  esac
  # shellcheck disable=SC2086 # fetch_opts is a list of fixed flags
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$(jig_git_batch_ssh)" \
    jig_net _pr_git "$JIG_PROJECT" fetch -q $fetch_opts "$remote" \
      "+refs/pull/$_PR_N/head:refs/jig/pr/$_PR_N/head" \
      "+refs/heads/$base:refs/jig/pr/$_PR_N/base" >/dev/null \
    || jig_die "pr fetch: could not fetch pull request $_PR_N and $base from $remote"

  head=$(_pr_git "$JIG_PROJECT" rev-parse --verify --quiet "refs/jig/pr/$_PR_N/head^{commit}") || head=""
  base_sha=$(_pr_git "$JIG_PROJECT" rev-parse --verify --quiet "refs/jig/pr/$_PR_N/base^{commit}") || base_sha=""
  if [ -z "$head" ] || [ -z "$base_sha" ]; then
    jig_die "pr fetch: the fetch left no head or base for pull request $_PR_N"
  fi
  [ "$head" = "$api_head" ] \
    || jig_die "pr fetch: pull request $_PR_N moved while it was fetched (GitHub says $api_head, the fetch got $head); run it again"
  mb=$(_pr_git "$JIG_PROJECT" merge-base "$base_sha" "$head" 2>/dev/null) \
    || jig_die "pr fetch: $base and the head of pull request $_PR_N share no commit here; a shallow clone needs git fetch --unshallow $remote"

  if [ "$kind" = detached ]; then
    _pr_git "$wt" checkout -q --detach "$head" \
      || jig_die "pr fetch: could not move $wt to the new head $head; jig pr cleanup $_PR_N, then fetch again"
  else
    mkdir -p "$(dirname "$wt")"
    _pr_git "$JIG_PROJECT" worktree add -q --detach "$wt" "$head" >/dev/null \
      || jig_die "pr fetch: could not make the worktree $wt"
  fi
  wt=$(_pr_physical "$wt")

  accounts="$_PR_ACCOUNTS" active="$_PR_ACTIVE" tok="$_PR_TOKEN_ENV" login="$_PR_LOGIN" why="$_PR_WHY"

  mkdir -p "$dir"
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _pr_write "$rec" "url: $_PR_URL
host: $_PR_HOST
repo: $slug
number: $_PR_N
state: $state
remote: $remote
base: $base
base_sha: $base_sha
merge_base: $mb
head: $head
worktree: $wt
accounts: $accounts
active: $active
token_env: $tok
login: $login
fetched_at: $now
"
  printf 'pull request: %s (%s)\n' "$_PR_URL" "${state:-unknown}"
  printf 'remote: %s\n' "$remote"
  printf 'base: %s at %s\n' "$base" "$base_sha"
  printf 'head: %s (the reviewed head)\n' "$head"
  printf 'merge base: %s\n' "$mb"
  printf 'worktree: %s (detached; read it, run nothing in it)\n' "$wt"
  printf 'state: %s\n' "$dir"
  if [ "$login" = ask ]; then
    printf 'login: ask (%s)\n' "$why"
  else
    printf 'login: %s\n' "$login"
  fi
  printf 'diff: git -C %s diff %s %s\n' "$JIG_PROJECT" "$mb" "$head"
  printf 'rules: git -C %s show %s:<path>   (the base, never the head)\n' "$JIG_PROJECT" "$base_sha"
}

# --- draft ------------------------------------------------------------------------------------

# _pr_draft_check <draft> <record> — print the draft with CRs dropped when it
# keeps skills/jig-pr-review/references/draft.md and agrees with the record; die naming the first
# line that does not.
_pr_draft_check() {
  local file="$1" rec="$2" line no=0 phase=head key val have="" seen_summary=0 blocks=0 body=0 kind pos path side a b sha out=""
  local url head accounts tok mb entry tab
  tab=$(printf '\t')
  url=$(_pr_record_get "$rec" url)
  head=$(_pr_record_get "$rec" head)
  mb=$(_pr_record_get "$rec" merge_base)
  accounts=$(_pr_record_get "$rec" accounts)
  tok=$(_pr_record_get "$rec" token_env)
  while IFS= read -r line || [ -n "$line" ]; do
    no=$((no + 1))
    line=${line%"$(printf '\r')"}
    out="$out$line
"
    if [ "$no" = 1 ]; then
      [ "$line" = "jig-pr-draft: 1" ] || jig_die "pr draft: line 1 must be 'jig-pr-draft: 1'"
      continue
    fi
    if [ "$phase" = head ]; then
      if [ -z "$line" ]; then
        phase=gap
        continue
      fi
      key=${line%%: *}
      val=${line#*: }
      [ "$key" != "$line" ] || jig_die "pr draft: line $no: a header line is '<key>: <value>'"
      case " $have " in *" $key "*) jig_die "pr draft: line $no: $key is given twice" ;; esac
      have="$have $key"
      case "$key" in
        url) [ "$val" = "$url" ] || jig_die "pr draft: line $no: url is $val, but the fetched pull request is $url" ;;
        head) [ "$val" = "$head" ] || jig_die "pr draft: line $no: head is $val, but the reviewed head is $head; review what changed, or fetch again" ;;
        login)
          [ -n "$val" ] && [ "$val" != ask ] || jig_die "pr draft: line $no: login names no account"
          case " $accounts " in
            *" $val "*) ;;
            *) [ -n "$tok" ] || jig_die "pr draft: line $no: gh holds no account $val for this host (accounts: ${accounts:-none})" ;;
          esac
          ;;
        language) [ -n "$val" ] || jig_die "pr draft: line $no: language is empty" ;;
        *) jig_die "pr draft: line $no: unknown header key: $key" ;;
      esac
      continue
    fi
    case "$line" in
      "=== "*)
        if [ "$blocks" -gt 0 ] && [ "$body" = 0 ]; then
          jig_die "pr draft: line $no: the block before it is empty"
        fi
        blocks=$((blocks + 1))
        body=0
        set -f
        # shellcheck disable=SC2086 # split the header words on purpose
        set -- ${line#=== }
        set +f
        kind="${1:-}"
        case "$kind" in
          summary)
            [ $# -eq 1 ] || jig_die "pr draft: line $no: '=== summary' takes nothing after it"
            [ "$seen_summary" = 0 ] || jig_die "pr draft: line $no: a second summary"
            [ "$blocks" = 1 ] || jig_die "pr draft: line $no: the summary comes first"
            seen_summary=1
            ;;
          comment | personal)
            [ "$seen_summary" = 1 ] || jig_die "pr draft: line $no: the summary comes first"
            [ $# -ge 3 ] || jig_die "pr draft: line $no: '=== $kind <R|L><line>[-<end>] <path>'"
            pos="$2"
            path=${line#"=== $kind $pos "}
            side=${pos%"${pos#?}"}
            a=${pos#?}
            case "$a" in
              *-*) b=${a#*-}; a=${a%%-*} ;;
              *) b="" ;;
            esac
            if [ "$side" != R ] && [ "$side" != L ]; then
              jig_die "pr draft: line $no: a position is R<line> or L<line>, with -<end> for a range: $pos"
            fi
            if ! _pr_valid_number "$a" || { [ -n "$b" ] && ! _pr_valid_number "$b"; }; then
              jig_die "pr draft: line $no: a position is R<line> or L<line>, with -<end> for a range: $pos"
            fi
            if [ -n "$b" ] && [ "$b" -le "$a" ]; then
              jig_die "pr draft: line $no: a range ends after it starts: $pos"
            fi
            case "/$path/" in
              *"/../"* | *"/./"* | //*) jig_die "pr draft: line $no: a path is relative to the repository, without . or ..: $path" ;;
            esac
            if [ "$side" = R ]; then sha="$head"; else sha="$mb"; fi
            entry=$(_pr_git "$JIG_PROJECT" -c core.quotepath=false ls-tree "$sha" -- "$path" 2>/dev/null) || entry=""
            case "$entry" in
              *" blob "*"$tab$path") entry=ok ;;
            esac
            if [ "$entry" != ok ]; then
              if [ "$side" = R ]; then
                jig_die "pr draft: line $no: $path is not a file of the reviewed head"
              else
                jig_die "pr draft: line $no: $path is not a file of the merge base (L is the old side)"
              fi
            fi
            ;;
          *) jig_die "pr draft: line $no: unknown block: === $kind" ;;
        esac
        ;;
      *)
        if [ "$blocks" = 0 ]; then
          [ -z "$line" ] || jig_die "pr draft: line $no: text before the first '=== ' block"
        elif [ -n "$line" ]; then
          body=1
        fi
        ;;
    esac
  done < "$file"
  for key in url head login language; do
    case " $have " in *" $key "*) ;; *) jig_die "pr draft: the header has no $key" ;; esac
  done
  [ "$seen_summary" = 1 ] || jig_die "pr draft: there is no '=== summary' block"
  [ "$body" = 1 ] || jig_die "pr draft: the last block is empty"
  printf '%s' "$out"
}

_pr_draft() {
  local arg="" from="" dir rec draft content
  while [ $# -gt 0 ]; do
    case "$1" in
      --from)
        [ $# -ge 2 ] || jig_fail usage "pr draft: --from requires a file"
        from="$2"
        shift 2
        ;;
      -*) jig_fail usage "pr draft: unknown argument: $1; $PR_USAGE" ;;
      *)
        [ -z "$arg" ] || jig_fail usage "pr draft: one pull request at a time; $PR_USAGE"
        arg="$1"
        shift
        ;;
    esac
  done
  [ -n "$arg" ] || jig_fail usage "pr draft: a pull request number or URL is required; $PR_USAGE"
  _pr_resolve draft "$arg"
  dir=$(_pr_state_dir "$_PR_N")
  rec="$dir/record"
  [ -f "$rec" ] || jig_die "pr draft: pull request $_PR_N is not fetched here; jig pr fetch <url>"
  draft="$dir/draft.md"
  if [ -n "$from" ]; then
    [ -f "$from" ] || jig_die "pr draft: no such file: $from"
    content=$(_pr_draft_check "$from" "$rec"; printf x)
    content=${content%x}
    _pr_write "$draft" "$content"
  fi
  [ -f "$draft" ] || jig_die "pr draft: there is no draft for pull request $_PR_N yet; jig pr draft $_PR_N --from <file>"
  printf 'jig: draft: %s\n' "$draft" >&2
  cat "$draft"
}

# --- comments: check and post ---------------------------------------------------------------
#
# adr-20261109-a-review-is-posted-as-it-was-shown. `check` builds, from the kept
# draft and GitHub's own diff, the one review that would be posted — comments
# placed on lines of that diff, the rest moved into the summary, the files the
# diff does not show named there — prints it with its hash and records that
# hash as the version shown. `post` builds it again, refuses unless the hash is
# the one shown and named, and posts it as one review with the event COMMENT,
# each part carrying a hidden marker that the read-back looks for.

_pr_comments() {
  local sub="${1:-}"
  if [ $# -gt 0 ]; then shift; fi
  # shellcheck source=lib/json.sh
  . "$JIG_LIB/json.sh"
  case "$sub" in
    check) _pr_comments_check "$@" ;;
    post) _pr_comments_post "$@" ;;
    '') jig_fail usage "pr comments: check or post is required; $PR_USAGE" ;;
    *) jig_fail usage "pr comments: unknown subcommand: $sub; $PR_USAGE" ;;
  esac
}

# _pr_trim_nl <s> — <s> without its trailing newlines, into _PR_S.
_PR_S=""
_pr_trim_nl() {
  _PR_S="$1"
  while :; do
    case "$_PR_S" in
      *"$_PR_NL") _PR_S=${_PR_S%"$_PR_NL"} ;;
      *) break ;;
    esac
  done
}
_PR_NL='
'

# _pr_read_draft <file> — the kept (already checked) draft into _PR_D_LOGIN,
# _PR_D_SUMMARY and the block arrays _PR_D_KIND, _PR_D_POS, _PR_D_PATH and
# _PR_D_BODY.
_PR_D_LOGIN="" _PR_D_SUMMARY=""
_pr_read_draft() {
  local line phase=head n=-1 rest body=""
  _PR_D_LOGIN="" _PR_D_SUMMARY=""
  _PR_D_KIND=() _PR_D_POS=() _PR_D_PATH=() _PR_D_BODY=()
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$phase" = head ]; then
      case "$line" in
        "login: "*) _PR_D_LOGIN=${line#login: } ;;
        '') phase=blocks ;;
      esac
      continue
    fi
    case "$line" in
      "=== "*)
        if [ "$n" -ge 0 ]; then
          _pr_trim_nl "$body"
          _PR_D_BODY[n]="$_PR_S"
        fi
        n=$((n + 1))
        body=""
        rest=${line#=== }
        _PR_D_KIND[n]=${rest%% *}
        if [ "${_PR_D_KIND[n]}" = summary ]; then
          _PR_D_POS[n]="" _PR_D_PATH[n]=""
        else
          rest=${rest#* }
          _PR_D_POS[n]=${rest%% *}
          _PR_D_PATH[n]=${rest#* }
        fi
        ;;
      *) if [ "$n" -ge 0 ]; then body="$body$line$_PR_NL"; fi ;;
    esac
  done < "$1"
  if [ "$n" -ge 0 ]; then
    _pr_trim_nl "$body"
    _PR_D_BODY[n]="$_PR_S"
  fi
  if [ "${_PR_D_KIND[0]:-}" = summary ]; then _PR_D_SUMMARY="${_PR_D_BODY[0]}"; fi
}

# _pr_hunk <header> — `@@ -<a>[,<b>] +<c>[,<d>] @@…` into _PR_HUNK as
# "<a> <b> <c> <d>"; an omitted count is 1, and a count of 0 is a side the hunk
# has no lines on (an added or a deleted file).
_PR_HUNK=""
_pr_hunk() {
  local h="$1" old new os oc ns nc v
  case "$h" in "@@ -"*) ;; *) return 1 ;; esac
  h=${h#@@ -}
  old=${h%% *}
  h=${h#* }
  case "$h" in "+"*) ;; *) return 1 ;; esac
  new=${h%% *}
  new=${new#+}
  os=${old%%,*} oc=1 ns=${new%%,*} nc=1
  case "$old" in *,*) oc=${old#*,} ;; esac
  case "$new" in *,*) nc=${new#*,} ;; esac
  for v in "$os" "$oc" "$ns" "$nc"; do
    case "$v" in '' | *[!0-9]*) return 1 ;; esac
  done
  _PR_HUNK="$os $oc $ns $nc"
}

# _pr_read_files <owner/repo> — the pull request's files as GitHub's diff has
# them, into _PR_F_NAME, _PR_F_OLD (the name before a rename), _PR_F_SHOWN (1
# when GitHub gives the file's patch or the file is only renamed, 0 when it
# gives none: a binary file, which it lists with no changes, or one past its
# size limit) and
# _PR_F_HUNKS ("<a> <b> <c> <d>;" per hunk). Only the hunk headers cross from
# gh: the filter makes lines F (status, changes, patch given), N (name),
# O (previous name) and H (a hunk header), and the parsing is the shell's.
_pr_read_files() {
  local out line i=-1 rest tab
  tab=$(printf '\t')
  _PR_F_NAME=() _PR_F_OLD=() _PR_F_SHOWN=() _PR_F_HUNKS=()
  out=$(_pr_gh --paginate "repos/$1/pulls/$_PR_N/files?per_page=100" --jq '.[] | if ((.filename + (.previous_filename | tostring)) | contains("\n")) then "X" else ("F\t" + .status + "\t" + (.changes | tostring) + "\t" + (if .patch then "1" else "0" end)), ("N\t" + .filename), (if .previous_filename then "O\t" + .previous_filename else empty end), ((.patch | tostring) | split("\n") | .[] | select(startswith("@@ ")) | "H\t" + .) end' \
    2>/dev/null) || jig_die "pr comments: GitHub did not give the files of pull request $_PR_N"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%"$(printf '\r')"}
    case "$line" in
      X) jig_die "pr comments: pull request $_PR_N has a file whose name holds a newline; jig cannot place comments in it" ;;
      "F$tab"*)
        i=$((i + 1))
        rest=${line#F?}
        _PR_F_SHOWN[i]=1
        case "$rest" in
          "renamed${tab}0$tab"*) ;;
          *"${tab}0") _PR_F_SHOWN[i]=0 ;;
        esac
        _PR_F_NAME[i]="" _PR_F_OLD[i]="" _PR_F_HUNKS[i]=""
        ;;
      "N$tab"*) [ "$i" -lt 0 ] || _PR_F_NAME[i]=${line#N?} ;;
      "O$tab"*) [ "$i" -lt 0 ] || _PR_F_OLD[i]=${line#O?} ;;
      "H$tab"*)
        [ "$i" -ge 0 ] || continue
        _pr_hunk "${line#H?}" || jig_die "pr comments: GitHub gave a hunk header jig cannot read: ${line#H?}"
        _PR_F_HUNKS[i]="${_PR_F_HUNKS[i]}$_PR_HUNK;"
        ;;
    esac
  done <<EOF
$out
EOF
}

# _pr_place <R|L> <start> <end> <path> — exit 0 when lines <start>..<end> of
# <path> lie inside one hunk of GitHub's diff on that side, with the path the
# comment is posted under in _PR_PLACED (the new name: an `L` comment on a
# renamed file is posted under the name the pull request gives it). An `L` path
# is the merge base's: a renamed file's previous name, or an unrenamed file's.
_PR_PLACED=""
_pr_place() {
  local side="$1" a="$2" b="$3" path="$4" i=0 n=${#_PR_F_NAME[@]} f=-1 hs h s c
  if [ "$side" = L ]; then
    while [ "$i" -lt "$n" ]; do
      if [ "${_PR_F_OLD[i]}" = "$path" ]; then f=$i; break; fi
      i=$((i + 1))
    done
    i=0
    while [ "$f" -lt 0 ] && [ "$i" -lt "$n" ]; do
      if [ "${_PR_F_NAME[i]}" = "$path" ] && [ -z "${_PR_F_OLD[i]}" ]; then f=$i; fi
      i=$((i + 1))
    done
  else
    while [ "$i" -lt "$n" ]; do
      if [ "${_PR_F_NAME[i]}" = "$path" ]; then f=$i; break; fi
      i=$((i + 1))
    done
  fi
  [ "$f" -ge 0 ] || return 1
  hs=${_PR_F_HUNKS[f]}
  while [ -n "$hs" ]; do
    h=${hs%%;*}
    hs=${hs#*;}
    set -f
    # shellcheck disable=SC2086 # four numbers
    set -- $h
    set +f
    if [ "$side" = L ]; then s=$1 c=$2; else s=$3 c=$4; fi
    if [ "$c" -gt 0 ] && [ "$a" -ge "$s" ] && [ "$b" -le $((s + c - 1)) ]; then
      _PR_PLACED=${_PR_F_NAME[f]}
      return 0
    fi
  done
  return 1
}

# _pr_unshown <merge base> <head> <changed files> — the files GitHub's diff does
# not show, newline-separated, into _PR_UNSHOWN: those it gives without a patch
# (binary, or past its size limit), and, when it lists fewer files than the
# pull request changes (its own ceiling), the ones the local diff of the same
# commits has and its list does not.
_PR_UNSHOWN=""
_pr_unshown() {
  local mb="$1" head="$2" changed="$3" i=0 n=${#_PR_F_NAME[@]} listed name names
  _PR_UNSHOWN=""
  listed="$_PR_NL"
  while [ "$i" -lt "$n" ]; do
    if [ "${_PR_F_SHOWN[i]}" = 0 ]; then _PR_UNSHOWN="$_PR_UNSHOWN${_PR_F_NAME[i]}$_PR_NL"; fi
    listed="$listed${_PR_F_NAME[i]}$_PR_NL"
    if [ -n "${_PR_F_OLD[i]}" ]; then listed="$listed${_PR_F_OLD[i]}$_PR_NL"; fi
    i=$((i + 1))
  done
  case "$changed" in '' | *[!0-9]*) changed=0 ;; esac
  if [ "$changed" -gt "$n" ]; then
    names=$(_pr_git "$JIG_PROJECT" -c core.quotepath=false diff --no-renames --name-only "$mb" "$head" 2>/dev/null) || names=""
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      case "$listed" in *"$_PR_NL$name$_PR_NL"*) continue ;; esac
      _PR_UNSHOWN="$_PR_UNSHOWN$name$_PR_NL"
    done <<EOF
$names
EOF
  fi
}

# _pr_comments_prepare <who> <n|url> — everything a post is built from, each
# checked against GitHub as the draft's login: sets _PR_DIR, _PR_SLUG,
# _PR_HEAD and the draft and file arrays; dies on the first thing that does
# not hold.
_PR_DIR="" _PR_SLUG="" _PR_HEAD="" _PR_MB="" _PR_CHANGED="" _PR_DRAFT=""
_pr_comments_prepare() {
  local who="$1" arg="$2" rec info tab base api_head state base_sha locked changed who_am acc mb
  _pr_resolve "comments $who" "$arg"
  _PR_DIR=$(_pr_state_dir "$_PR_N")
  rec="$_PR_DIR/record"
  [ -f "$rec" ] || jig_die "pr comments $who: pull request $_PR_N is not fetched here; jig pr fetch <url>"
  _PR_DRAFT="$_PR_DIR/draft.md"
  [ -f "$_PR_DRAFT" ] || jig_die "pr comments $who: there is no draft for pull request $_PR_N; jig pr draft $_PR_N --from <file>"
  # The draft again, against the record as it is now: a fetch since may have
  # moved the reviewed head.
  _pr_draft_check "$_PR_DRAFT" "$rec" >/dev/null
  _pr_read_draft "$_PR_DRAFT"
  _PR_HOST=$(_pr_record_get "$rec" host)
  _PR_URL=$(_pr_record_get "$rec" url)
  _PR_SLUG=$(_pr_record_get "$rec" repo)
  _PR_HEAD=$(_pr_record_get "$rec" head)
  _PR_MB=$(_pr_record_get "$rec" merge_base)
  command -v gh >/dev/null 2>&1 || jig_die "pr comments $who: the GitHub CLI (gh) is needed"

  # The login: its own stored token, or the environment's when gh keeps none
  # for it; either way GitHub must answer with that very login.
  _PR_TOKEN=$(_pr_stored_token "$_PR_D_LOGIN") || _PR_TOKEN=$(_pr_env_token)
  [ -n "$_PR_TOKEN" ] \
    || jig_die "pr comments $who: gh gives no token for $_PR_D_LOGIN on $_PR_HOST (gh auth login --hostname $_PR_HOST; gh auth token --user needs gh 2.40 or later)"
  who_am=$(_pr_gh user --jq .login 2>/dev/null | tr -d '\r') || who_am=""
  if [ "$(printf '%s' "$who_am" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$_PR_D_LOGIN" | tr '[:upper:]' '[:lower:]')" ]; then
    jig_die "pr comments $who: the token for $_PR_D_LOGIN answers as ${who_am:-nobody}; the draft's login is the one it posts as"
  fi
  acc=$(_pr_access "$_PR_SLUG")
  [ "$acc" != none ] || jig_die "pr comments $who: $_PR_D_LOGIN cannot reach $_PR_SLUG on $_PR_HOST"

  tab=$(printf '\t')
  info=$(_pr_pull_info "$_PR_SLUG") || jig_die "pr comments $who: GitHub did not answer for $_PR_URL"
  IFS="$tab" read -r base api_head state base_sha locked changed <<EOF
$info
EOF
  [ "$api_head" = "$_PR_HEAD" ] \
    || jig_die "pr comments $who: pull request $_PR_N moved since it was reviewed (GitHub's head is ${api_head:-unknown}, the reviewed head $_PR_HEAD); fetch it again and review what changed — nothing was posted"
  if [ "$locked" = true ] && [ "$acc" != comment ]; then
    jig_die "pr comments $who: the conversation of pull request $_PR_N is locked, and $_PR_D_LOGIN is not a member who may still comment"
  fi
  case "$base_sha" in
    '' | *[!0-9a-f]*) jig_die "pr comments $who: GitHub named no base commit for $_PR_URL" ;;
  esac
  mb=$(_pr_gh "repos/$_PR_SLUG/compare/$base_sha...$_PR_HEAD" --jq .merge_base_commit.sha 2>/dev/null | tr -d '\r') || mb=""
  [ "$mb" = "$_PR_MB" ] \
    || jig_die "pr comments $who: GitHub's diff starts at ${mb:-an unknown commit}, the review at the merge base $_PR_MB; fetch it again — old-side lines would point elsewhere"
  _PR_CHANGED="$changed"
  _pr_read_files "$_PR_SLUG"
  _pr_unshown "$_PR_MB" "$_PR_HEAD" "$changed"
}

# _pr_comments_build — from what _pr_comments_prepare read, the review to
# post: _PR_SHOWN (the text shown, markers included), _PR_H (its hash, taken
# over the same text without the markers, which are made from it), _PR_PAYLOAD
# (the JSON of the one review), _PR_SUMMARY_FIELDS and _PR_C_FIELDS[k],
# _PR_C_DESC[k] for k = 1.. (each part's JSON fields and its position).
_PR_SHOWN="" _PR_H="" _PR_PAYLOAD="" _PR_SUMMARY_FIELDS="" _PR_MOVED=0 _PR_PERSONAL=0 _PR_NC=0
_pr_comments_build() {
  local i=1 n=${#_PR_D_KIND[@]} pos side a b path body moved="" k=0 sbody line unshown="" canon marker head
  local -a cbody cside cline cstart cpath
  _PR_C_FIELDS=() _PR_C_DESC=()
  _PR_MOVED=0 _PR_PERSONAL=0
  head="$_PR_HEAD"
  while [ "$i" -lt "$n" ]; do
    if [ "${_PR_D_KIND[i]}" = personal ]; then
      _PR_PERSONAL=$((_PR_PERSONAL + 1))
      i=$((i + 1))
      continue
    fi
    pos=${_PR_D_POS[i]}
    path=${_PR_D_PATH[i]}
    body=${_PR_D_BODY[i]}
    side=${pos%"${pos#?}"}
    a=${pos#?}
    b="$a"
    case "$a" in *-*) b=${a#*-} a=${a%%-*} ;; esac
    if _pr_place "$side" "$a" "$b" "$path"; then
      k=$((k + 1))
      cpath[k]="$_PR_PLACED"
      cbody[k]="$body"
      cline[k]="$b"
      cstart[k]=""
      if [ "$b" != "$a" ]; then cstart[k]="$a"; fi
      if [ "$side" = L ]; then cside[k]=LEFT; else cside[k]=RIGHT; fi
      _PR_C_DESC[k]="$pos $_PR_PLACED"
    else
      _PR_MOVED=$((_PR_MOVED + 1))
      moved="$moved$_PR_NL**$pos \`$path\`**$_PR_NL$_PR_NL$body$_PR_NL"
    fi
    i=$((i + 1))
  done
  _PR_NC=$k

  sbody="$_PR_D_SUMMARY"
  if [ -n "$moved" ]; then
    _pr_trim_nl "$moved"
    sbody="$sbody$_PR_NL$_PR_NL---$_PR_NL$_PR_S"
  fi
  if [ -n "$_PR_UNSHOWN" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      unshown="$unshown${unshown:+, }\`$line\`"
    done <<EOF
$_PR_UNSHOWN
EOF
    sbody="$sbody$_PR_NL${_PR_NL}Not in GitHub's diff, so not commented on: $unshown."
  fi

  # The hash is taken over the text without markers; the markers carry it.
  canon=$(_pr_comments_render "$sbody" "" cbody; printf x)
  canon=${canon%x}
  _PR_H=$(printf '%s' "$canon" | _pr_git "$JIG_PROJECT" hash-object --stdin) \
    || jig_die "pr comments: could not hash the review"
  marker="<!-- jig-pr-review id=$_PR_H head=$head"
  sbody="$sbody$_PR_NL$_PR_NL$marker part=0 -->"
  i=1
  while [ "$i" -le "$k" ]; do
    cbody[i]="${cbody[i]}$_PR_NL$_PR_NL$marker part=$i -->"
    i=$((i + 1))
  done
  _PR_SHOWN=$(_pr_comments_render "$sbody" "$_PR_H" cbody; printf x)
  _PR_SHOWN=${_PR_SHOWN%x}

  json_quote "$sbody"
  _PR_SUMMARY_FIELDS="\"body\":$_JSON"
  i=1
  while [ "$i" -le "$k" ]; do
    json_quote "${cpath[i]}"
    _PR_C_FIELDS[i]="\"path\":$_JSON"
    json_quote "${cbody[i]}"
    _PR_C_FIELDS[i]="${_PR_C_FIELDS[i]},\"body\":$_JSON,\"line\":${cline[i]},\"side\":\"${cside[i]}\""
    if [ -n "${cstart[i]}" ]; then
      _PR_C_FIELDS[i]="${_PR_C_FIELDS[i]},\"start_line\":${cstart[i]},\"start_side\":\"${cside[i]}\""
    fi
    i=$((i + 1))
  done
  json_quote "$head"
  _PR_PAYLOAD="{\"commit_id\":$_JSON,\"event\":\"COMMENT\",$_PR_SUMMARY_FIELDS"
  if [ "$k" -gt 0 ]; then
    _PR_PAYLOAD="$_PR_PAYLOAD,\"comments\":["
    i=1
    while [ "$i" -le "$k" ]; do
      if [ "$i" -gt 1 ]; then _PR_PAYLOAD="$_PR_PAYLOAD,"; fi
      _PR_PAYLOAD="$_PR_PAYLOAD{${_PR_C_FIELDS[i]}}"
      i=$((i + 1))
    done
    _PR_PAYLOAD="$_PR_PAYLOAD]"
  fi
  _PR_PAYLOAD="$_PR_PAYLOAD}"
}

# _pr_comments_render <summary> <hash or empty> <bodies array name> — the text
# a person is shown: the header, the summary, and each comment under the
# position it is posted at (the draft's notation, the path as posted).
_pr_comments_render() {
  local sbody="$1" i=1 ref
  printf 'jig-pr-post: 1\nurl: %s\nhead: %s\nlogin: %s\nevent: COMMENT\n\n' "$_PR_URL" "$_PR_HEAD" "$_PR_D_LOGIN"
  printf '=== summary\n%s\n' "$sbody"
  while [ "$i" -le "$_PR_NC" ]; do
    ref="$3[$i]"
    printf '=== comment %s\n%s\n' "${_PR_C_DESC[i]}" "${!ref}"
    i=$((i + 1))
  done
}

_pr_comments_check() {
  local arg="" now
  while [ $# -gt 0 ]; do
    case "$1" in
      -*) jig_fail usage "pr comments check: unknown argument: $1; $PR_USAGE" ;;
      *)
        [ -z "$arg" ] || jig_fail usage "pr comments check: one pull request at a time; $PR_USAGE"
        arg="$1"
        shift
        ;;
    esac
  done
  [ -n "$arg" ] || jig_fail usage "pr comments check: a pull request number or URL is required; $PR_USAGE"
  _pr_comments_prepare check "$arg"
  _pr_comments_build
  _pr_write "$_PR_DIR/payload.json" "$_PR_PAYLOAD"
  _pr_write "$_PR_DIR/shown.md" "$_PR_SHOWN"
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _pr_write "$_PR_DIR/shown" "hash: $_PR_H
shown_at: $now
"
  printf 'jig: to post: %s\n' "$_PR_DIR/shown.md" >&2
  if [ "$_PR_MOVED" -gt 0 ]; then
    printf 'jig: moved into the summary: %s comment(s) outside GitHub'"'"'s diff\n' "$_PR_MOVED" >&2
  fi
  if [ "$_PR_PERSONAL" -gt 0 ]; then
    printf 'jig: left out: %s personal block(s), never posted\n' "$_PR_PERSONAL" >&2
  fi
  printf '%s' "$_PR_SHOWN"
  printf 'hash: %s\n' "$_PR_H"
}

# _pr_readback — what of this review is on the pull request already, by the
# draft's login: _PR_LANDED (" <part> …", 0 the summary), _PR_LANDED_AT[k]
# (where comment k sits now), _PR_REVIEW_URL (the summary's review), and
# _PR_OTHER (a review or comment of the same head by the same login from
# another version: a half-done one may have left comments and no review). Markers by anybody else are not ours to count.
_PR_LANDED="" _PR_REVIEW_URL="" _PR_OTHER=""
_pr_readback() {
  local out line tab login marker url rest w lline lside lstart lpath me
  tab=$(printf '\t')
  me=$(printf '%s' "$_PR_D_LOGIN" | tr '[:upper:]' '[:lower:]')
  _PR_LANDED=" " _PR_REVIEW_URL="" _PR_OTHER=""
  _PR_LANDED_AT=()
  out=$(_pr_gh --paginate "repos/$_PR_SLUG/pulls/$_PR_N/reviews?per_page=100" \
    --jq '.[] | select(.body | tostring | contains("<!-- jig-pr-review ")) | (.id | tostring) + "\t" + .user.login + "\t" + (.body | split("<!-- jig-pr-review ")[1] | split(" -->")[0]) + "\t" + .html_url' \
    2>/dev/null) || jig_die "pr comments: could not read back the reviews of pull request $_PR_N"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%"$(printf '\r')"}
    [ -n "$line" ] || continue
    rest=${line#*"$tab"}
    login=${rest%%"$tab"*}
    rest=${rest#*"$tab"}
    marker=${rest%%"$tab"*}
    url=${rest#*"$tab"}
    [ "$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')" = "$me" ] || continue
    _pr_marker "$marker"
    [ "$_PR_M_HEAD" = "$_PR_HEAD" ] || continue
    if [ "$_PR_M_ID" = "$_PR_H" ]; then
      if [ "$_PR_M_PART" = 0 ]; then
        _PR_LANDED="${_PR_LANDED}0 "
        _PR_REVIEW_URL="$url"
      fi
    elif [ -z "$_PR_OTHER" ]; then
      _PR_OTHER="$url"
    fi
  done <<EOF
$out
EOF
  out=$(_pr_gh --paginate "repos/$_PR_SLUG/pulls/$_PR_N/comments?per_page=100" \
    --jq '.[] | select(.body | tostring | contains("<!-- jig-pr-review ")) | (.id | tostring) + "\t" + .user.login + "\t" + (.body | split("<!-- jig-pr-review ")[1] | split(" -->")[0]) + "\t" + (.line | tostring) + "\t" + (.side | tostring) + "\t" + (.start_line | tostring) + "\t" + .html_url + "\t" + .path' \
    2>/dev/null) || jig_die "pr comments: could not read back the comments of pull request $_PR_N"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%"$(printf '\r')"}
    [ -n "$line" ] || continue
    rest=${line#*"$tab"}
    login=${rest%%"$tab"*}
    rest=${rest#*"$tab"}
    marker=${rest%%"$tab"*}
    rest=${rest#*"$tab"}
    lline=${rest%%"$tab"*}
    rest=${rest#*"$tab"}
    lside=${rest%%"$tab"*}
    rest=${rest#*"$tab"}
    lstart=${rest%%"$tab"*}
    rest=${rest#*"$tab"}
    url=${rest%%"$tab"*}
    lpath=${rest#*"$tab"}
    [ "$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')" = "$me" ] || continue
    _pr_marker "$marker"
    [ "$_PR_M_HEAD" = "$_PR_HEAD" ] || continue
    if [ "$_PR_M_ID" != "$_PR_H" ]; then
      if [ -z "$_PR_OTHER" ]; then _PR_OTHER="$url"; fi
      continue
    fi
    case "$_PR_M_PART" in '' | 0 | *[!0-9]*) continue ;; esac
    [ "$_PR_M_PART" -le "$_PR_NC" ] || continue
    _PR_LANDED="$_PR_LANDED$_PR_M_PART "
    w="$lline"
    if [ "$lstart" != null ] && [ -n "$lstart" ]; then w="$lstart-$lline"; fi
    _PR_LANDED_AT[_PR_M_PART]="$lside $w $lpath"
  done <<EOF
$out
EOF
}

# _pr_marker <id=… head=… part=…> — into _PR_M_ID, _PR_M_HEAD and _PR_M_PART.
_PR_M_ID="" _PR_M_HEAD="" _PR_M_PART=""
_pr_marker() {
  local w
  _PR_M_ID="" _PR_M_HEAD="" _PR_M_PART=""
  set -f
  # shellcheck disable=SC2086 # the marker's words
  set -- $1
  set +f
  for w in "$@"; do
    case "$w" in
      id=*) _PR_M_ID=${w#id=} ;;
      head=*) _PR_M_HEAD=${w#head=} ;;
      part=*) _PR_M_PART=${w#part=} ;;
    esac
  done
}

# _pr_count_landed — how many of the review's parts _PR_LANDED holds.
_pr_count_landed() {
  local n=0 k=0
  while [ "$k" -le "$_PR_NC" ]; do
    case "$_PR_LANDED" in *" $k "*) n=$((n + 1)) ;; esac
    k=$((k + 1))
  done
  printf '%s\n' "$n"
}

# _pr_post_file <name> <json> <endpoint> — POST <json>, written to a file of
# the state directory and handed to gh with --input (never spliced into an
# argument), to <endpoint>; the new object's id, or gh's complaint, in
# _PR_OUT. Called in this shell, never in $(...), so that the file is
# registered for removal on an interrupt; it goes after the call.
_PR_OUT=""
_pr_post_file() {
  local file="$_PR_DIR/$1" rc=0
  jig_cleanup_add "$file"
  _pr_write "$file" "$2"
  _PR_OUT=$(_pr_gh --method POST "$3" --input "$file" --jq .id 2>&1) || rc=$?
  _PR_OUT=$(printf '%s' "$_PR_OUT" | tr -d '\r')
  rm -f "$file"
  return "$rc"
}

_pr_comments_post() {
  local arg="" shown="" recorded total landed k out rc=0 now prev posted_id="" missing=0 err=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --shown)
        [ $# -ge 2 ] || jig_fail usage "pr comments post: --shown requires the hash check printed"
        shown="$2"
        shift 2
        ;;
      -*) jig_fail usage "pr comments post: unknown argument: $1; $PR_USAGE" ;;
      *)
        [ -z "$arg" ] || jig_fail usage "pr comments post: one pull request at a time; $PR_USAGE"
        arg="$1"
        shift
        ;;
    esac
  done
  [ -n "$arg" ] || jig_fail usage "pr comments post: a pull request number or URL is required; $PR_USAGE"
  [ -n "$shown" ] || jig_fail usage "pr comments post: --shown <hash> is required: the hash of the version the person said yes to"
  _pr_resolve "comments post" "$arg"
  recorded=""
  prev="$(_pr_state_dir "$_PR_N")/shown"
  if [ -f "$prev" ]; then recorded=$(_pr_record_get "$prev" hash); fi
  [ -n "$recorded" ] || jig_die "pr comments post: nothing was shown for pull request $_PR_N; jig pr comments check $_PR_N, and show what it prints"
  [ "$shown" = "$recorded" ] \
    || jig_die "pr comments post: $shown is not the version shown last ($recorded); show the latest jig pr comments check and ask again"

  _pr_comments_prepare post "$arg"
  _pr_comments_build
  [ "$_PR_H" = "$shown" ] \
    || jig_die "pr comments post: what would be posted now ($_PR_H) is not what was shown ($shown); run jig pr comments check $_PR_N and show it again — nothing was posted"

  _pr_readback
  total=$((_PR_NC + 1))
  landed=$(_pr_count_landed)
  if [ "$landed" = 0 ] && [ -n "$_PR_OTHER" ]; then
    jig_die "pr comments post: $_PR_D_LOGIN already posted another version of a review of this head: $_PR_OTHER; decide there what stays — nothing was posted"
  fi
  if [ "$landed" = 0 ] && [ -f "$_PR_DIR/posted" ] && [ "$(_pr_record_get "$_PR_DIR/posted" hash)" = "$_PR_H" ]; then
    jig_die "pr comments post: this version was posted as review $(_pr_record_get "$_PR_DIR/posted" review), but GitHub shows none of its markers; look at $_PR_URL before posting anything again"
  fi

  if [ "$landed" = "$total" ]; then
    printf 'already posted: nothing is missing\n'
  elif [ "$landed" = 0 ]; then
    _pr_post_file post.json "$_PR_PAYLOAD" "repos/$_PR_SLUG/pulls/$_PR_N/reviews" || rc=$?
    out="$_PR_OUT"
    if [ "$rc" = 0 ]; then
      posted_id="$out"
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      _pr_write "$_PR_DIR/posted" "hash: $_PR_H
review: $posted_id
login: $_PR_D_LOGIN
posted_at: $now
"
    else
      err="$out"
    fi
  else
    # Some parts landed and the answer was lost: post only the rest, each
    # alone — the summary as a review without comments, a comment by itself.
    json_quote "$_PR_HEAD"
    case "$_PR_LANDED" in
      *" 0 "*) ;;
      *)
        _pr_post_file part-0.json "{\"commit_id\":$_JSON,\"event\":\"COMMENT\",$_PR_SUMMARY_FIELDS}" \
          "repos/$_PR_SLUG/pulls/$_PR_N/reviews" || err="$err$_PR_OUT$_PR_NL"
        ;;
    esac
    k=1
    while [ "$k" -le "$_PR_NC" ]; do
      case "$_PR_LANDED" in
        *" $k "*) ;;
        *)
          _pr_post_file "part-$k.json" "{\"commit_id\":$_JSON,${_PR_C_FIELDS[k]}}" \
            "repos/$_PR_SLUG/pulls/$_PR_N/comments" || err="$err$_PR_OUT$_PR_NL"
          ;;
      esac
      k=$((k + 1))
    done
  fi

  _pr_readback
  printf 'posted as: %s\n' "$_PR_D_LOGIN"
  printf 'review: %s\n' "${_PR_REVIEW_URL:-${posted_id:-not found}}"
  case "$_PR_LANDED" in
    *" 0 "*) printf 'landed: summary\n' ;;
    *) printf 'missing: summary\n'; missing=$((missing + 1)) ;;
  esac
  k=1
  while [ "$k" -le "$_PR_NC" ]; do
    case "$_PR_LANDED" in
      *" $k "*) printf 'landed: comment %s at %s\n' "${_PR_C_DESC[k]}" "${_PR_LANDED_AT[k]}" ;;
      *)
        printf 'missing: comment %s\n' "${_PR_C_DESC[k]}"
        missing=$((missing + 1))
        ;;
    esac
    k=$((k + 1))
  done
  if [ -n "$err" ]; then
    jig_warn "pr comments post: GitHub answered: $(printf '%s' "$err" | tr '\n' ' ')"
  fi
  if [ "$missing" = "$total" ] && [ -n "$posted_id" ]; then
    jig_die "pr comments post: GitHub took review $posted_id, but none of its markers came back; do not post again — look at $_PR_URL"
  fi
  if [ "$missing" = "$total" ]; then
    jig_die "pr comments post: nothing landed on $_PR_URL"
  fi
  if [ "$missing" -gt 0 ]; then
    jig_die "pr comments post: half-done: $((total - missing)) of $total parts landed; run jig pr comments post $_PR_N --shown $_PR_H again to post only what is missing"
  fi
}

# --- list ---------------------------------------------------------------------------------------

_pr_list() {
  local root d n rec any=0 clone common has
  [ $# -eq 0 ] || jig_fail usage "pr list: unknown argument: $1; $PR_USAGE"
  clone=$(jig_config_clone_root)
  common=$(_pr_common_dir) || common=""
  for root in "$clone/$JIG_AI_DIR/workspace/pr" "${common:+$common/jig/pr}"; do
    if [ -z "$root" ] || [ ! -d "$root" ]; then continue; fi
    for d in "$root"/*/; do
      [ -d "$d" ] || continue
      n=$(basename "$d")
      _pr_valid_number "$n" || continue
      rec="$d/record"
      [ -f "$rec" ] || continue
      any=1
      has=no
      if [ -f "$d/draft.md" ]; then has=yes; fi
      printf '%s %s head=%s worktree=%s draft=%s\n' "$n" "$(_pr_record_get "$rec" url)" \
        "$(_pr_record_get "$rec" head)" "$(_pr_record_get "$rec" worktree)" "$has"
    done
  done
  [ "$any" = 1 ] || printf 'no pull requests fetched in this clone\n'
}

# --- cleanup ------------------------------------------------------------------------------------

# Takes back what fetch made for one pull request, and nothing else:
# - the worktree, only by `git worktree remove` without --force, only at the
#   path _pr_worktree_path builds from a checked number, and only when git lists
#   it there detached and unlocked; git refuses one with changes, and then
#   nothing else goes either. What git leaves behind (Windows) is cleared by
#   jig_worktree_leftover: links and empty directories only.
# - the refs refs/jig/pr/<n>/head and /base, each by `update-ref -d` at the
#   commit it holds when read.
# - the record and the draft, by name, then `rmdir` of their directory, which
#   refuses anything else in it.
_pr_cleanup() {
  local n wt kind dir r sha did=0
  [ $# -eq 1 ] || jig_fail usage "pr cleanup: one pull request number or URL is required; $PR_USAGE"
  _pr_resolve cleanup "$1"
  n="$_PR_N"
  wt=$(_pr_worktree_path "$n")
  kind=$(_pr_worktree_kind "$wt")
  case "$kind" in
    detached)
      if ! _pr_git "$JIG_PROJECT" worktree remove "$wt"; then
        jig_die "pr cleanup: git kept the worktree $wt (above); commit nothing there — discard what changed in it, then run cleanup again"
      fi
      if [ -e "$wt" ] && ! jig_worktree_leftover "$wt"; then
        jig_warn "pr cleanup: $wt still holds files git did not remove; delete them yourself"
      fi
      printf 'removed worktree %s\n' "$wt"
      did=1
      ;;
    none)
      if [ -e "$wt" ]; then
        jig_warn "pr cleanup: $wt is not a worktree of this clone; left as it is"
      fi
      ;;
    locked) jig_die "pr cleanup: the worktree $wt is locked; git worktree unlock it first, then run cleanup again" ;;
    *) jig_die "pr cleanup: $wt has a branch checked out; it is not a pull request jig fetched, so it stays" ;;
  esac
  for r in head base; do
    sha=$(_pr_git "$JIG_PROJECT" rev-parse --verify --quiet "refs/jig/pr/$n/$r") || continue
    _pr_git "$JIG_PROJECT" update-ref -d "refs/jig/pr/$n/$r" "$sha" \
      || jig_die "pr cleanup: could not delete refs/jig/pr/$n/$r"
    printf 'deleted ref refs/jig/pr/%s/%s\n' "$n" "$r"
    did=1
  done
  dir=$(_pr_state_dir "$n")
  if [ -d "$dir" ]; then
    rm -f "$dir/record" "$dir/draft.md" "$dir/payload.json" "$dir/shown.md" "$dir/shown" "$dir/posted" "$dir/post.json"
    for r in "$dir"/part-*.json; do
      r=${r##*/part-}
      r=${r%.json}
      if _pr_valid_number "$r" || [ "$r" = 0 ]; then rm -f "$dir/part-$r.json"; fi
    done
    if rmdir "$dir" 2>/dev/null; then
      printf 'removed %s\n' "$dir"
      did=1
    else
      jig_warn "pr cleanup: $dir holds files jig did not write; left as it is"
    fi
  fi
  [ "$did" = 1 ] || printf 'nothing to clean up for pull request %s\n' "$n"
}
