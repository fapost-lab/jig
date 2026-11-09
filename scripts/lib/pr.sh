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

PR_USAGE="usage: jig pr fetch <url> | jig pr draft <n|url> [--from <file>] | jig pr list | jig pr cleanup <n|url>"

cmd_pr() {
  local sub="${1:-}"
  if [ $# -gt 0 ]; then shift; fi
  jig_require_repo
  _pr_refuse_inside_a_review_tree
  case "$sub" in
    fetch) _pr_fetch "$@" ;;
    draft) _pr_draft "$@" ;;
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
# downloaded. MSYS2_ARG_CONV_EXCL keeps Git Bash from rewriting a refspec that
# holds both `/` and `:` as a path list (conventions/shell.md).
_pr_git() {
  local dir="$1"
  shift
  GIT_LFS_SKIP_SMUDGE=1 MSYS2_ARG_CONV_EXCL='*' \
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
  if [ "$1" = github.com ]; then
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
  info=$(jig_net gh api --hostname "$_PR_HOST" "repos/$slug/pulls/$_PR_N" \
    --jq '[.base.ref, .head.sha, .state] | @tsv' 2>/dev/null) \
    || jig_die "pr fetch: GitHub did not answer for $_PR_URL (gh auth status --hostname $_PR_HOST)"
  IFS="$t" read -r base api_head state <<EOF
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

  IFS="$t" read -r accounts active <<EOF
$(_pr_accounts "$_PR_HOST")
EOF
  tok=$(_pr_token_env "$_PR_HOST")
  login="$active" why=""
  if [ -n "$tok" ]; then
    login=ask why="$tok in the environment overrides every gh account"
  elif [ -z "$accounts" ]; then
    login=ask why="gh holds no account for $_PR_HOST"
  else
    case "$accounts" in
      *" "*) login=ask why="several accounts: $accounts; active: ${active:-none}" ;;
    esac
  fi

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
    rm -f "$dir/record" "$dir/draft.md"
    if rmdir "$dir" 2>/dev/null; then
      printf 'removed %s\n' "$dir"
      did=1
    else
      jig_warn "pr cleanup: $dir holds files jig did not write; left as it is"
    fi
  fi
  [ "$did" = 1 ] || printf 'nothing to clean up for pull request %s\n' "$n"
}
