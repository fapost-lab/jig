# The forge cache: what housekeeping last heard from the forge about pull
# requests, kept so that a read never asks the forge itself
# (adr-20261015-a-read-is-one-json-envelope; schemas/json.md). Written by
# `jig housekeeping` from the list it already fetches, which replaces it whole;
# `jig upgrade` adds the one pull request it has just opened (forgecache_record),
# so the upgrade waiting for its merge is known before housekeeping next runs
# (adr-20261029-an-upgrade-pull-request-is-landed-by-jig). Read by
# `jig task list --json` and `jig status`.
#
#   .ai/runtime/forge-cache, one line per pull request, newest first as the
#   forge listed them:
#     <head><TAB><base><TAB><state><TAB><ci><TAB><fetched_at><TAB><head-commit><TAB><url><TAB><mergeable>
#   <state> open|merged|closed; <ci> green|red|pending|none, `-` when it was
#   not asked (a pull request that is not open, a forge that does not list it);
#   <fetched_at> UTC, when the forge said so; <head-commit> and <url> the pull
#   request's head and address, `-` when the forge did not say; <mergeable>
#   conflicting|mergeable for an open pull request the forge judged against
#   its base, `-` otherwise (read by the staging drift report,
#   jig_staging_drift). A line written before a column existed ends before it
#   and reads as if each missing one were `-`. Lines starting with `#` are
#   comments.
#
# The file lives in the runtime directory of the checkout that owns the task
# workspaces: a worktree that borrows the owner's `tasks/` (ADR-0029) reads the
# owner's file and never writes it, so one clone has one cache.
#
# Depends on `_task_borrowed_tasks_root` (lib/task.sh): a caller sources task.sh
# first, as for lib/hklog.sh.
# shellcheck shell=bash

# forgecache_file — the cache's path, in the owner's runtime directory when this
# checkout borrows its task workspaces.
forgecache_file() {
  local borrowed
  if borrowed=$(_task_borrowed_tasks_root); then
    printf '%s/runtime/forge-cache\n' "${borrowed%/workspace/tasks}"
    return 0
  fi
  printf '%s/%s/runtime/forge-cache\n' "$JIG_PROJECT" "$JIG_AI_DIR"
}

# forgecache_owned — exit 0 when this checkout keeps the cache it reads: not
# when it borrows the owner's task workspaces, whose housekeeping keeps the
# owner's cache. A writer asks before it asks the forge for anything.
forgecache_owned() {
  ! _task_borrowed_tasks_root >/dev/null
}

# forgecache_write <rows> — replace the cache with <rows>, atomically. Does
# nothing in a checkout that does not own its cache (forgecache_owned). Never
# fails the caller: a cache that could not be written is the old one, whose
# entries still say how old they are.
forgecache_write() {
  local rows="$1" file tmp
  forgecache_owned || return 0
  file=$(forgecache_file)
  tmp="$file.tmp.$$"
  jig_cleanup_add "$tmp"
  mkdir -p "${file%/*}" 2>/dev/null || return 0
  {
    printf '# jig forge cache: <head> <base> <state> <ci> <fetched_at> <head-commit> <url> <mergeable>, written by jig housekeeping\n'
    [ -z "$rows" ] || printf '%s\n' "$rows"
  } > "$tmp" 2>/dev/null || return 0
  mv "$tmp" "$file" 2>/dev/null || return 0
  # `task list --json` reports what the cache holds, so a written cache raises
  # the clone's revision (adr-20261016-the-clone-revision-is-a-claimed-name).
  # housekeeping raises it again when its run ends; this one keeps any other
  # writer (forgecache_record) from forgetting.
  jig_record_changed
  return 0
}

# forgecache_record <head> <base> <state> <head-commit> <url> — put one pull
# request a command has just heard of at the top of the cache, in place of any
# line for the same <head> and <base>, every other line kept as it was: the
# newest is first, as the forge lists them. <ci> and <mergeable> are `-`, not
# asked; <fetched_at> is now; <head-commit> or <url> that is empty or does not
# look like one is `-`. The next housekeeping run replaces the whole cache with
# what the forge says. Never fails the caller (forgecache_write).
forgecache_record() {
  local head="$1" base="$2" state="$3" sha="$4" url="$5" t at rest
  [ -n "$head" ] && [ -n "$base" ] || return 0
  case "$state" in open | merged | closed) ;; *) return 0 ;; esac
  case "$sha" in '' | *[!0-9a-f]*) sha="-" ;; esac
  case "$url" in '' | *[[:space:]]*) url="-" ;; esac
  t=$(printf '\t')
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  rest=$(forgecache_read | awk -F '\t' -v h="$head" -v b="$base" '!($1 == h && $2 == b)')
  forgecache_write "$head$t$base$t$state$t-$t$at$t$sha$t$url$t-${rest:+
$rest}"
}

# forgecache_read — the cache's lines, comments left out; nothing when there is
# no cache.
forgecache_read() {
  local file
  file=$(forgecache_file)
  [ -f "$file" ] || return 0
  sed '/^#/d;/^$/d' "$file" 2>/dev/null || true
}

# forgecache_entry <cache> <head> <base> — sets _FORGECACHE_STATE, _FORGECACHE_CI
# and _FORGECACHE_AT from the first line of <cache> (forgecache_read's output)
# for a pull request from <head> into <base>: the newest, as the forge lists
# them and as housekeeping's own remote state takes it. Each is empty when the
# cache does not say. In the caller's shell, without a process per lookup.
_FORGECACHE_STATE=""
_FORGECACHE_CI=""
_FORGECACHE_AT=""
forgecache_entry() {
  local cache="$1" head="$2" base="$3" t nl rest line
  _FORGECACHE_STATE=""
  _FORGECACHE_CI=""
  _FORGECACHE_AT=""
  [ -n "$cache" ] && [ -n "$head" ] && [ -n "$base" ] || return 0
  t=$'\t'
  nl=$'\n'
  rest=${nl}${cache}
  case "$rest" in
    *"$nl$head$t$base$t"*) ;;
    *) return 0 ;;
  esac
  rest=${rest#*"$nl$head$t$base$t"}
  line=${rest%%"$nl"*}
  IFS="$t" read -r _FORGECACHE_STATE _FORGECACHE_CI _FORGECACHE_AT _ <<EOF
$line
EOF
  [ "$_FORGECACHE_CI" != "-" ] || _FORGECACHE_CI=""
  return 0
}

# forgecache_pr <cache> <url> <head> <into> — the same three variables for the
# pull request <url> names: the first (newest) line of <cache> whose <url>
# column is <url>, whatever branch it goes into. A pull request with no line of
# that url (an old line without the column, or `-`, or an empty <url>) is
# looked up as forgecache_entry does, by <head> and <into>, the branch it goes
# into. This is the one lookup of a task's own pull request: on the staging
# flow the pull request `pr_url` names goes into the staging branch, which a
# lookup by the task's base never finds. jig_parked_states (common.sh) picks the
# same line, first by url. In the caller's shell, without a process.
forgecache_pr() {
  local cache="$1" url="$2" head="$3" into="$4" t s c a u
  if [ -n "$cache" ] && [ -n "$url" ] && [ "$url" != "-" ]; then
    t=$'\t'
    while IFS="$t" read -r _ _ s c a _ u _; do
      [ "$u" = "$url" ] || continue
      _FORGECACHE_STATE=$s
      _FORGECACHE_CI=$c
      _FORGECACHE_AT=$a
      [ "$_FORGECACHE_CI" != "-" ] || _FORGECACHE_CI=""
      return 0
    done <<EOF
$cache
EOF
  fi
  forgecache_entry "$cache" "$head" "$into"
}

# forgecache_upgrades <cache> <base> — the pull requests of Jig's own upgrade
# branches (`jig/upgrade-*`) into <base>, from <cache> (forgecache_read's
# output), the newest of each branch only, one line each:
#   <head><TAB><state><TAB><fetched_at><TAB><url>
# <url> is `-` when the cache does not know it. `jig status` reads an upgrade
# still waiting for its merge from this.
forgecache_upgrades() {
  [ -n "$1" ] && [ -n "$2" ] || return 0
  printf '%s\n' "$1" | awk -F '\t' -v base="$2" '
    $2 == base && index($1, "jig/upgrade-") == 1 && length($1) > 12 && !($1 in seen) {
      seen[$1] = 1
      u = $7
      if (u == "") u = "-"
      print $1 "\t" $3 "\t" $5 "\t" u
    }'
}
