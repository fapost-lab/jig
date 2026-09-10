# cmd_task — task workspace and state (domains/task; schemas/state.md;
# ARCHITECTURE.md, Scripts layout; ADR-0005; ADR-0008).
# Sourced by scripts/jig; defines cmd_task plus the reusable readers
# `task_dir` and `task_state_get` that other libraries (context.sh) source
# this file for. bash 3.2 compatible: no associative arrays, no ${var,,},
# no mapfile.
# shellcheck shell=bash

cmd_task() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    new) task_new "$@" ;;
    set) task_set "$@" ;;
    abandon) task_abandon "$@" ;;
    pause) task_pause "$@" ;;
    resume) task_resume "$@" ;;
    list) task_list "$@" ;;
    show) task_show "$@" ;;
    current) task_current "$@" ;;
    changes) task_changes "$@" ;;
    artifacts) task_artifacts "$@" ;;
    *) jig_die "usage: jig task new|set|abandon|pause|resume|list|show|current|changes|artifacts ..." ;;
  esac
}

# --- reusable readers (also used by scripts/lib/context.sh) -----------------

# task_dir <id> — absolute path of the task's workspace directory. Pure
# string computation; does not check the workspace exists.
task_dir() {
  # Every subcommand goes through here, so an id like `..` or `../x` can never
  # resolve to a path outside the tasks directory (RULES.md invariant).
  _task_valid_id "$1" || jig_die "invalid task id: $1"
  printf '%s/%s/workspace/tasks/%s\n' "$JIG_PROJECT" "$JIG_AI_DIR" "$1"
}

# task_state_get <id> <key> — print the value of <key> from the task's state
# file, or nothing when the task or the key does not exist. Never dies:
# callers that need "unknown task" to be an error check for the state file
# themselves (see task_show, task_set).
task_state_get() {
  local id="$1" key="$2" file
  file="$(task_dir "$id")/state"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}:[[:space:]]*//p" "$file" | head -n 1
}

# --- validation ---------------------------------------------------------------

_task_valid_id() {
  # No leading dot: rules out `.`, `..` and hidden directories, which the
  # `*/` walks in task_list / task_current would not see.
  case "$1" in
    '' | .* | *[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

_task_valid_class() {
  case "$1" in
    T0 | T1 | T2 | T3 | T4) return 0 ;;
    *) return 1 ;;
  esac
}

_task_valid_status() {
  case "$1" in
    active | ready | consolidated | abandoned) return 0 ;;
    *) return 1 ;;
  esac
}

_task_valid_bool() {
  case "$1" in
    true | false) return 0 ;;
    *) return 1 ;;
  esac
}

# Comma-separated `^[a-z0-9-]+(,[a-z0-9-]+)*$` (schemas/state.md). Rejects
# empty, leading/trailing/doubled commas explicitly: field-splitting a
# trailing comma does not yield a trailing empty field in bash, so that case
# needs its own check rather than relying on the per-item loop below.
_task_valid_domains() {
  local val="$1" d
  case "$val" in
    '' | ,* | *, | *,,*) return 1 ;;
  esac
  local IFS=','
  for d in $val; do
    case "$d" in
      '' | *[!a-z0-9-]*) return 1 ;;
    esac
  done
  return 0
}

# --- branch -------------------------------------------------------------------

# Current branch of the checkout, or "detached" (ADR-0008: a workspace
# belongs to the checkout it was created in).
_task_current_branch() {
  local b
  if b=$(git -C "$JIG_PROJECT" symbolic-ref --short HEAD 2>/dev/null); then
    printf '%s\n' "$b"
  else
    printf 'detached\n'
  fi
}

# --- candidates (design §1) -----------------------------------------------------

# Number of non-empty lines in <text>. Avoids `wc -l`'s BSD/GNU leading-space
# quirk; used everywhere a count feeds an `[ -eq ]`/`[ -gt ]` comparison.
_task_count_lines() {
  printf '%s\n' "$1" | sed '/^$/d' | awk 'END { print NR }'
}

# _task_candidates_for_branch <branch> — ids, one per line and sorted, of
# every task whose `branch` equals <branch>, whose `status` is `active` or
# `ready`, and which is not paused (design §1). `consolidated` and
# `abandoned` are excluded on purpose: their work is finished and they stay
# reachable by explicit id, which is what keeps a trunk-based repository from
# becoming permanently ambiguous once finished-but-unmerged workspaces pile
# up on the same branch.
_task_candidates_for_branch() {
  local branch="$1" base dir id br st paused list=""
  base="$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"
  for dir in "$base"/*/; do
    [ -f "${dir}state" ] || continue
    id=$(basename "$dir")
    br=$(task_state_get "$id" branch)
    [ "$br" = "$branch" ] || continue
    st=$(task_state_get "$id" status)
    case "$st" in
      active | ready) ;;
      *) continue ;;
    esac
    paused=$(task_state_get "$id" paused)
    [ "$paused" = "true" ] && continue
    list="$list
$id"
  done
  printf '%s\n' "$list" | sed '/^$/d' | sort
}

# The single candidate on <branch>, or nothing when there are zero or several
# (an advisory hint for `task new`'s dirty-tree refusal, not a resume
# decision — ambiguity there is fine, it just means the message stays
# generic rather than naming a task it cannot be sure of).
_task_likely_owner() {
  local branch="$1" candidates
  candidates=$(_task_candidates_for_branch "$branch")
  [ "$(_task_count_lines "$candidates")" -eq 1 ] || return 0
  printf '%s\n' "$candidates"
}

# --- task.md template ----------------------------------------------------------

# Write <dest> with {{TASK_ID}} substituted, from <from> when given
# (task_new --from: a path, or "-" for stdin — the user's own document,
# copied as-is), otherwise from templates/task.md. Uses jig_source_root when
# the running copy is a framework source checkout (dev mode, and every test
# run); an installed copy (`.ai/scripts/`) ships no templates/ directory at
# all — jig init only ever places files *sourced from* templates/, never the
# directory itself — so that case falls back to a minimal built-in copy of
# the same template. Written atomically.
#
# The substitution is a single `sed s/{{TASK_ID}}/<id>/g` over the source
# stream: <id> is restricted to `[A-Za-z0-9._-]` (_task_valid_id) so it is
# safe as a sed replacement, and sed passes every byte outside the matched
# placeholder through unchanged — no reformatting, no whole-body rewrite, so
# a --from document with backslashes, `&`, backticks, tabs or non-ASCII
# survives byte-for-byte except at the placeholder itself. A document
# without the placeholder is copied verbatim.
_task_write_task_md() {
  local id="$1" dest="$2" from="${3:-}" source tmpl tmp
  tmp="$dest.tmp.$$"
  if [ -n "$from" ]; then
    if [ "$from" = "-" ]; then
      sed "s/{{TASK_ID}}/$id/g" > "$tmp"
    else
      sed "s/{{TASK_ID}}/$id/g" "$from" > "$tmp"
    fi
  else
    source=$(jig_source_root)
    tmpl=""
    [ -n "$source" ] && [ -f "$source/templates/task.md" ] && tmpl="$source/templates/task.md"
    if [ -n "$tmpl" ]; then
      sed "s/{{TASK_ID}}/$id/g" "$tmpl" > "$tmp"
    else
      cat > "$tmp" <<EOF
# $id

## Goal

<!-- One paragraph: what must be true when this task is done. -->

## Scope

<!-- In / out. Affected areas or files if known; \`jig context --files\` uses the diff, not this list. -->

## Notes

<!-- Working notes for this task. Nothing here survives the task unless consolidation moves it to .ai/knowledge/. -->
EOF
    fi
  fi
  mv "$tmp" "$dest"
}

# --- state file rewriting -------------------------------------------------------

# Rewrite <dir>/state with <key> set to <value> (replacing an existing line,
# or inserting one before `created_at:` when the key is absent) and
# `updated_at` refreshed to today. Atomic write (ADR-0008): state.tmp.$$
# then mv. awk, not sed, does the substitution: <value> is printed literally
# rather than used as a sed replacement, so it needs no escaping.
_task_rewrite_state() {
  local dir="$1" key="$2" value="$3" file tmp today
  file="$dir/state"
  tmp="$dir/state.tmp.$$"
  today=$(jig_today)
  awk -v key="$key" -v value="$value" -v today="$today" '
    {
      line = $0
      if (line ~ ("^" key ":")) {
        print key ": " value
        done = 1
      } else if (!done && line ~ /^created_at:/) {
        print key ": " value
        print line
        done = 1
      } else if (line ~ /^updated_at:/) {
        print "updated_at: " today
      } else {
        print line
      }
    }
    END {
      if (!done) print key ": " value
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Rewrite <dir>/state with the <key> line removed (companion to
# _task_rewrite_state above, same atomic write and `updated_at` refresh).
# A no-op, beyond refreshing `updated_at`, when <key> is already absent.
_task_rewrite_state_remove() {
  local dir="$1" key="$2" file tmp today
  file="$dir/state"
  tmp="$dir/state.tmp.$$"
  today=$(jig_today)
  awk -v key="$key" -v today="$today" '
    {
      line = $0
      if (line ~ ("^" key ":")) {
        next
      } else if (line ~ /^updated_at:/) {
        print "updated_at: " today
      } else {
        print line
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# --- pause / resume helpers (design §4, §5) --------------------------------------

# Whole days between <date> (YYYY-MM-DD) and today; 0 when <date> is empty or
# unparsable. Mirrors jig_file_age_days's BSD/GNU `date` portability trick
# (ADR-0002: no GNU-only tools assumed).
_task_days_since() {
  local d="$1" ts now
  [ -n "$d" ] || { printf '0\n'; return; }
  if ts=$(date -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null); then :; else
    ts=$(date -d "$d" +%s 2>/dev/null) || { printf '0\n'; return; }
  fi
  now=$(date +%s)
  printf '%d\n' $(( (now - ts) / 86400 ))
}

# Files this task changed that were also changed on the configured base
# branch since the merge base (design §5: overlap, not distance). Empty,
# rather than an error, when the base branch or the merge base is missing —
# the resume report simply omits the section then.
_task_resume_overlap() {
  local base mb task_files base_files
  base=$(cfg git.base_branch main)
  git -C "$JIG_PROJECT" rev-parse --verify "$base" >/dev/null 2>&1 || return 0
  mb=$(git -C "$JIG_PROJECT" merge-base "$base" HEAD 2>/dev/null) || return 0
  task_files=$(jig_git_touched_files)
  base_files=$(git -C "$JIG_PROJECT" diff --name-only "$mb" "$base" 2>/dev/null)
  comm -12 \
    <(printf '%s\n' "$task_files" | sed '/^$/d' | sort -u) \
    <(printf '%s\n' "$base_files" | sed '/^$/d' | sort -u)
}

# Refuse to start a new task on a dirty working tree (design §6): untracked
# files never block (build output is not work in progress), only tracked
# changes do — a `git status --porcelain` line that is not `??`.
# _task_branch_name <id> — the branch this task will live on, from
# `git.branch_template` with {id} substituted. Dies on a name git would
# reject, using git's own rules rather than a hand-rolled regex: the set of
# invalid ref names is long (`..`, a trailing `.lock`, control characters, a
# leading dash) and getting it wrong here means creating a ref nobody can
# delete without plumbing.
_task_branch_name() {
  local id="$1" template name
  template=$(cfg git.branch_template "task/{id}")
  case "$template" in
    *'{id}'*) ;;
    *) jig_die "task new: git.branch_template must contain {id}: $template" ;;
  esac
  name=${template%%'{id}'*}$id${template#*'{id}'}
  git check-ref-format --branch "$name" >/dev/null 2>&1 \
    || jig_die "task new: git rejects the branch name: $name"
  if git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/heads/$name" >/dev/null 2>&1; then
    jig_die "task new: branch already exists: $name (reusing it would attach this task to someone else's work)"
  fi
  printf '%s\n' "$name"
}

# _task_create_branch <name> — create <name> off the base branch, check it
# out, and print the commit it starts from. Non-zero when git refuses.
#
# The branch is cut from `git.base_branch`, not from HEAD: a task is work
# proposed against the base, and starting it from wherever the checkout
# happened to be is how a task quietly inherits an unrelated branch's history.
# When the base cannot be resolved (a repository with no commits yet) the
# branch is cut from HEAD instead, which is the only thing that exists.
_task_create_branch() {
  local name="$1" base start
  base=$(cfg git.base_branch main)
  if git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/heads/$base" >/dev/null 2>&1; then
    start="refs/heads/$base"
  elif git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/remotes/origin/$base" >/dev/null 2>&1; then
    start="refs/remotes/origin/$base"
  else
    start="HEAD"
  fi
  git -C "$JIG_PROJECT" checkout -q -b "$name" "$start" >/dev/null 2>&1 || return 1
  git -C "$JIG_PROJECT" rev-parse HEAD 2>/dev/null || return 1
}

_task_refuse_dirty_tree() {
  local branch="$1" tracked owner
  tracked=$(git -C "$JIG_PROJECT" status --porcelain 2>/dev/null | grep -v '^??' || true)
  [ -n "$tracked" ] || return 0

  owner=$(_task_likely_owner "$branch")
  if [ -n "$owner" ]; then
    jig_die "task new: uncommitted changes in the working tree, likely from task $owner; run \`jig task pause $owner --stash\` or pass --force"
  else
    jig_die "task new: uncommitted changes in the working tree; pause the task that owns them with --stash, or pass --force"
  fi
}

# --- subcommands ----------------------------------------------------------------

task_new() {
  jig_require_init
  [ $# -ge 1 ] || jig_die "usage: jig task new <id> [--class T0..T4] [--domains a,b] [--from <file>] [--force]"
  local id="$1"
  shift
  local class="" domains="" from="" force=0 no_branch=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --class) [ $# -ge 2 ] || jig_die "task new: --class requires a value"; class="$2"; shift 2 ;;
      --domains) [ $# -ge 2 ] || jig_die "task new: --domains requires a value"; domains="$2"; shift 2 ;;
      --from) [ $# -ge 2 ] || jig_die "task new: --from requires a value"; from="$2"; shift 2 ;;
      --force) force=1; shift ;;
      --no-branch) no_branch=1; shift ;;
      *) jig_die "task new: unknown argument: $1" ;;
    esac
  done

  _task_valid_id "$id" || jig_die "task new: invalid task id: $id"

  local dir
  dir=$(task_dir "$id")
  [ -e "$dir" ] && jig_die "task new: task already exists: $id"

  [ -z "$class" ] || _task_valid_class "$class" || jig_die "task new: invalid class: $class"
  [ -z "$domains" ] || _task_valid_domains "$domains" || jig_die "task new: invalid domains: $domains"

  # --from is validated here, before the workspace directory exists, so a
  # missing/unreadable/non-regular source (a directory, for instance) never
  # leaves a half-created task behind. "-" means stdin: nothing to check.
  if [ -n "$from" ] && [ "$from" != "-" ]; then
    [ -e "$from" ] || jig_die "task new: --from: no such file: $from"
    [ -f "$from" ] || jig_die "task new: --from: not a regular file: $from"
    [ -r "$from" ] || jig_die "task new: --from: file not readable: $from"
  fi

  local branch
  branch=$(_task_current_branch)

  # Prevention beats resolution (design §6): a dirty tracked tree is refused
  # before the new workspace is even created, naming the branch's likely
  # owner when there is exactly one. Untracked-only trees pass through.
  [ "$force" -eq 1 ] || _task_refuse_dirty_tree "$branch"

  # Everything that can refuse this task refuses it before anything is
  # created, so a rejected `task new` leaves neither a workspace nor a branch.
  local new_branch=""
  if [ "$no_branch" -eq 0 ] && cfg_bool git.branch_per_task true; then
    new_branch=$(_task_branch_name "$id")
  fi

  mkdir -p "$dir"

  # Create the branch after the workspace so a failure here can be undone
  # cleanly: the directory was made by this call and nothing else has written
  # to it yet. The reverse order would leave the checkout on a branch with no
  # task behind it.
  local base_commit=""
  if [ -n "$new_branch" ]; then
    if ! base_commit=$(_task_create_branch "$new_branch"); then
      rm -rf "$dir"
      jig_die "task new: could not create branch $new_branch"
    fi
    branch="$new_branch"
  fi

  local tmp="$dir/state.tmp.$$"
  {
    printf 'task_id: %s\n' "$id"
    printf 'branch: %s\n' "$branch"
    [ -z "$base_commit" ] || printf 'base_commit: %s\n' "$base_commit"
    [ -z "$class" ] || printf 'class: %s\n' "$class"
    printf 'status: active\n'
    printf 'knowledge_consolidated: false\n'
    [ -z "$domains" ] || printf 'domains: %s\n' "$domains"
    printf 'created_at: %s\n' "$(jig_today)"
    printf 'updated_at: %s\n' "$(jig_today)"
  } > "$tmp"
  mv "$tmp" "$dir/state"

  _task_write_task_md "$id" "$dir/task.md" "$from"

  jig_relpath "$dir" "$JIG_PROJECT"
}

task_set() {
  [ $# -eq 3 ] || jig_die "usage: jig task set <id> <key> <value>"
  jig_require_init
  local id="$1" key="$2" value="$3" dir
  dir=$(task_dir "$id")
  [ -f "$dir/state" ] || jig_die "task set: unknown task: $id"

  case "$key" in
    class) _task_valid_class "$value" || jig_die "task set: invalid class: $value" ;;
    status) _task_valid_status "$value" || jig_die "task set: invalid status: $value" ;;
    knowledge_consolidated) _task_valid_bool "$value" || jig_die "task set: invalid knowledge_consolidated: $value" ;;
    domains) _task_valid_domains "$value" || jig_die "task set: invalid domains: $value" ;;
    task_id | branch | base_commit | created_at | updated_at | paused | paused_at | paused_reason | paused_stash)
      jig_die "task set: key is not writable: $key" ;;
    *) jig_die "task set: unknown key: $key" ;;
  esac

  _task_rewrite_state "$dir" "$key" "$value"
}

task_abandon() {
  [ $# -eq 1 ] || jig_die "usage: jig task abandon <id>"
  task_set "$1" status abandoned
}

# --- pause / resume ---------------------------------------------------------------

# Pause is a field, not a status (design §3): it is orthogonal to `status`
# and must return the task to wherever `status` left it. --stash is opt-in
# and never the default (an unwanted default that loses work cannot be
# undone; the reverse costs one flag) and records the stash's SHA, not its
# index, because `stash@{0}` shifts as other entries are pushed.
task_pause() {
  jig_require_init
  [ $# -ge 1 ] || jig_die "usage: jig task pause <id> [--reason <text>] [--stash]"
  local id="$1"
  shift
  local reason="" stash=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) [ $# -ge 2 ] || jig_die "task pause: --reason requires a value"; reason="$2"; shift 2 ;;
      --stash) stash=1; shift ;;
      *) jig_die "task pause: unknown argument: $1" ;;
    esac
  done

  local dir
  dir=$(task_dir "$id")
  [ -f "$dir/state" ] || jig_die "task pause: unknown task: $id"
  [ "$(task_state_get "$id" paused)" != "true" ] || jig_die "task pause: already paused: $id"

  # paused_reason is one flat `key: value` line (schemas/state.md); an
  # embedded newline would corrupt the state file, so it is refused up front
  # rather than silently truncated or split across lines. $'\n', not
  # $(printf '\n'): command substitution strips trailing newlines, which
  # would leave nl empty and turn the pattern below into a bare `*`.
  local nl=$'\n'
  case "$reason" in
    *"$nl"*) jig_die "task pause: --reason must be a single line" ;;
  esac

  local stash_sha=""
  if [ "$stash" -eq 1 ]; then
    local changed count
    changed=$(git -C "$JIG_PROJECT" status --porcelain 2>/dev/null)
    count=$(_task_count_lines "$changed")
    if [ "$count" -gt 0 ]; then
      git -C "$JIG_PROJECT" stash push -u -m "jig: $id" >/dev/null \
        || jig_die "task pause: git stash push failed"
      stash_sha=$(git -C "$JIG_PROJECT" rev-parse "stash@{0}")
      printf 'stashed %s file(s): %s\n' "$count" "$stash_sha"
    else
      printf 'working tree is clean; nothing to stash\n'
    fi
  fi

  _task_rewrite_state "$dir" paused true
  _task_rewrite_state "$dir" paused_at "$(jig_today)"
  [ -z "$reason" ] || _task_rewrite_state "$dir" paused_reason "$reason"
  [ -z "$stash_sha" ] || _task_rewrite_state "$dir" paused_stash "$stash_sha"

  printf 'paused %s\n' "$id"
}

# resume refuses when the task is not paused and when the current branch
# differs from the state's `branch` (design §4). A failed stash apply clears
# nothing and exits non-zero: a conflicted restore must not silently look
# like a successful resume. `apply`, never `pop` — the stash entry survives
# as a backup, which is why `paused_stash` itself is not cleared here.
task_resume() {
  jig_require_init
  [ $# -eq 1 ] || jig_die "usage: jig task resume <id>"
  local id="$1" dir
  dir=$(task_dir "$id")
  [ -f "$dir/state" ] || jig_die "task resume: unknown task: $id"
  [ "$(task_state_get "$id" paused)" = "true" ] || jig_die "task resume: not paused: $id"

  local state_branch cur_branch
  state_branch=$(task_state_get "$id" branch)
  cur_branch=$(_task_current_branch)
  [ "$cur_branch" = "$state_branch" ] || jig_die "task resume: switch to $state_branch first"

  local sha stash_line=""
  sha=$(task_state_get "$id" paused_stash)
  if [ -n "$sha" ]; then
    if git -C "$JIG_PROJECT" stash apply "$sha" >/dev/null 2>&1; then
      stash_line="stash: applied $sha (kept; drop with git stash drop $sha)"
    else
      jig_die "task resume: git stash apply failed for $sha (conflicts); resolve them, then run \`jig task resume $id\` again"
    fi
  fi

  local days
  days=$(_task_days_since "$(task_state_get "$id" paused_at)")

  _task_rewrite_state_remove "$dir" paused
  _task_rewrite_state_remove "$dir" paused_at
  _task_rewrite_state_remove "$dir" paused_reason

  printf 'resumed %s (paused %s days)\n' "$id" "$days"

  local uncommitted n
  uncommitted=$(git -C "$JIG_PROJECT" status --porcelain 2>/dev/null)
  n=$(_task_count_lines "$uncommitted")
  [ "$n" -eq 0 ] || printf 'uncommitted: %s files\n' "$n"

  [ -z "$stash_line" ] || printf '%s\n' "$stash_line"

  local overlap k base
  overlap=$(_task_resume_overlap)
  k=$(_task_count_lines "$overlap")
  if [ "$k" -gt 0 ]; then
    base=$(cfg git.base_branch main)
    printf 'overlap: %s files you changed also changed on %s\n' "$k" "$base"
    printf '%s\n' "$overlap" | sed 's/^/  /'
  fi
}

# Live work: unfinished, whether or not it is dormant. A paused task is still
# live — it is listed, with its marker. `consolidated` and `abandoned` are done
# and pile up on a long-lived branch, so they are hidden unless asked for. Same
# convention as `jig context`, which hides superseded and deprecated documents
# behind --all.
_task_is_live() {
  case "$1" in
    active | ready) return 0 ;;
    *) return 1 ;;
  esac
}

task_list() {
  jig_require_init
  local show_all=0 want_status=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) show_all=1; shift ;;
      --status)
        [ $# -ge 2 ] || jig_die "task list: --status requires a value"
        _task_valid_status "$2" || jig_die "task list: invalid status: $2"
        want_status="$2"
        shift 2
        ;;
      *) jig_die "task list: unknown argument: $1" ;;
    esac
  done

  local base="$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"
  local dir id class status branch paused line lines="" hidden=0
  for dir in "$base"/*/; do
    [ -f "${dir}state" ] || continue
    id=$(basename "$dir")
    class=$(task_state_get "$id" class)
    status=$(task_state_get "$id" status)
    branch=$(task_state_get "$id" branch)
    paused=$(task_state_get "$id" paused)
    if [ -n "$want_status" ]; then
      [ "$status" = "$want_status" ] || continue
    elif [ "$show_all" -eq 0 ] && ! _task_is_live "$status"; then
      hidden=$((hidden + 1))
      continue
    fi
    [ -n "$class" ] || class="-"
    line="$id class=$class status=$status branch=$branch"
    [ "$paused" = "true" ] && line="$line paused"
    lines="$lines
$line"
  done
  lines=$(printf '%s\n' "$lines" | sed '/^$/d')
  if [ -z "$lines" ]; then
    if [ "$hidden" -gt 0 ]; then
      printf 'no live tasks (%d finished; jig task list --all)\n' "$hidden"
    else
      printf 'no tasks\n'
    fi
    return 0
  fi
  printf '%s\n' "$lines" | sort
  [ "$hidden" -gt 0 ] && printf '(%d finished; jig task list --all)\n' "$hidden"
  return 0
}

task_show() {
  jig_require_init
  [ $# -eq 1 ] || jig_die "usage: jig task show <id>"
  local file
  file="$(task_dir "$1")/state"
  [ -f "$file" ] || jig_die "task show: unknown task: $1"
  cat "$file"
}

# The task for this checkout's current branch (design §2). Deterministic,
# never a ranking: exactly one candidate (design §1: branch matches, status
# `active` or `ready`, not paused) prints its id on stdout and exits 0; zero
# candidates is a normal, silent outcome (exit 1, a warning on stderr) so
# `jig context` can treat "no current task" as ordinary rather than fatal;
# several candidates is refused outright (exit 2, one line per candidate on
# stderr, nothing on stdout) rather than picked by any tie-break — silently
# guessing wrong here is exactly the bug this replaced.
task_current() {
  jig_require_init
  local branch candidates count
  branch=$(_task_current_branch)
  candidates=$(_task_candidates_for_branch "$branch")
  count=$(_task_count_lines "$candidates")

  if [ "$count" -eq 0 ]; then
    jig_warn "no current task for branch: $branch"
    return 1
  fi

  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$candidates"
    return 0
  fi

  local cid cst cupd
  while IFS= read -r cid; do
    [ -n "$cid" ] || continue
    cst=$(task_state_get "$cid" status)
    cupd=$(task_state_get "$cid" updated_at)
    printf '%s  %s  updated_at=%s\n' "$cid" "$cst" "$cupd" >&2
  done < <(printf '%s\n' "$candidates")
  return 2
}

# Read-only review inventory; the task ID establishes context, not hunk ownership.
task_changes() {
  jig_require_init
  [ $# -ge 1 ] || jig_die "usage: jig task changes <id> --base <ref> [--files <list>|-] [--format report|paths]"
  local id="$1" base="" head format=report files="" has_files=0 row path layer rows selected="" candidates kept t
  shift
  [ -f "$(task_dir "$id")/state" ] || jig_die "task changes: unknown task: $id"
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) [ $# -ge 2 ] || jig_die "task changes: --base requires a value"; base="$2"; shift 2 ;;
      --files)
        [ $# -ge 2 ] || jig_die "task changes: --files requires a value"
        [ "$has_files" -eq 0 ] || jig_die "task changes: duplicate --files"
        has_files=1
        if [ "$2" = - ]; then files=$(cat); else
          case "$2" in *'
'*) jig_die "task changes: use stdin for a multiline scope" ;; esac
          files=$(printf '%s' "$2" | tr ',' '\n')
        fi
        shift 2 ;;
      --format) [ $# -ge 2 ] || jig_die "task changes: --format requires a value"; format="$2"; shift 2 ;;
      *) jig_die "task changes: unknown argument: $1" ;;
    esac
  done
  case "$format" in report | paths) ;; *) jig_die "task changes: invalid format: $format" ;; esac
  [ -n "$base" ] || jig_die "task changes: --base is required; establish the task baseline first"
  base=$(jig_review_commit "$base") || return 1
  head=$(jig_review_commit HEAD) || return 1
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    jig_check_review_path "$path"
  done < <(printf '%s\n' "$files")
  rows=$(jig_git_change_rows "$base" "$head") || return 1
  t=$(printf '\t')
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    path=${row%%"$t"*}
    if [ "$has_files" -eq 1 ] && ! printf '%s\n' "$files" | grep -qxF -- "$path"; then continue; fi
    selected="$selected$row
"
  done < <(printf '%s\n' "$rows")
  if [ "$format" = paths ]; then
    printf '%s' "$selected" | cut -f1 | LC_ALL=C sort -u
  else
    candidates=$(printf '%s\n' "$rows" | sed '/^$/d' | cut -f1 | sort -u | wc -l | tr -d ' ')
    kept=$(printf '%s' "$selected" | cut -f1 | sort -u | wc -l | tr -d ' ')
    printf 'task: %s\nbase: %s\nhead: %s\nselected: %s paths; excluded: %s candidate paths\n' "$id" "$base" "$head" "$kept" "$((candidates - kept))"
    while IFS="$t" read -r path layer; do
      [ -n "$path" ] || continue
      printf '%-10s %s\n' "$layer" "$path"
    done < <(printf '%s' "$selected")
    printf 'inventory only; task ownership and review remain unassessed\n'
  fi
}

_task_artifact_kind() {
  case "$1" in discovery | spec | alternatives | design | plan | review | verification | handoff) return 0 ;; *) return 1 ;; esac
}

# Resolve links without readlink -f. Do not read an artifact outside the workspace.
_task_artifact_fact() {
  local root="$1" kind="$2" provided="$3" path target parent hops=0
  if printf '%s\n' "$provided" | grep -qxF -- "$kind"; then
    printf 'provided-claim (caller must substantiate)\n'; return 0
  fi
  path="$root/$kind.md"
  while [ -L "$path" ]; do
    hops=$((hops + 1))
    if [ "$hops" -gt 40 ]; then printf 'unavailable (symlink loop)\n'; return 0; fi
    target=$(readlink "$path") || { printf 'unavailable (unreadable link)\n'; return 0; }
    case "$target" in /*) path="$target" ;; *) path="$(dirname "$path")/$target" ;; esac
  done
  parent=$(cd -P "$(dirname "$path")" 2>/dev/null && pwd -P) || { printf 'unavailable (missing parent)\n'; return 0; }
  path="$parent/$(basename "$path")"
  case "$path" in "$root"/*) ;; *) printf 'unavailable (outside workspace)\n'; return 0 ;; esac
  if [ ! -f "$path" ]; then printf 'unavailable (missing or not a regular file)\n'
  elif [ ! -r "$path" ]; then printf 'unavailable (unreadable)\n'
  elif [ ! -s "$path" ]; then printf 'unavailable (empty)\n'
  else printf 'present\n'; fi
}

# stage|documentary inputs|unassessed semantic prerequisites. This is not a router.
_task_artifact_route() {
  case "$1" in
    T0) printf '%s\n' 'implement|task|task intent' 'verify|task|implementation' ;;
    T1) printf '%s\n' 'analyze|task|task intent' 'implement|task discovery|analysis sufficiency' 'verify|task|implementation' ;;
    T2) printf '%s\n' 'analyze|task|task intent' 'plan|task discovery|analysis sufficiency' 'implement|task plan|plan sufficiency' 'review|task plan|implementation' 'verify|task plan|implementation and review outcome' ;;
    T3) printf '%s\n' 'discover|task|task intent' 'design|task discovery|discovery sufficiency' 'human-gate|task design|human design decision' 'implement|task design|human design approval' 'architecture-review|task design|implementation' 'verify|task design|implementation and architecture review outcome' 'consolidate|task verification|implementation, review and verification outcomes' ;;
    T4) printf '%s\n' 'discover|task|task intent' 'specify|task discovery|discovery sufficiency' 'alternatives|task spec|specification sufficiency' 'design|task spec alternatives|alternatives evaluated' 'human-gate|task spec design|human design decision' 'implement|task spec design|human design approval' 'review|task spec design|implementation and independent reviewer' 'verify|task spec design|implementation and independent review outcome' 'consolidate|task verification|implementation, review and verification outcomes' ;;
  esac
}

task_artifacts() {
  jig_require_init
  [ $# -ge 1 ] || jig_die "usage: jig task artifacts <id> [--provided discovery,design,...]"
  local id="$1" root class provided="" seen=0 kinds kind fact stage inputs semantic availability facts="" t
  shift
  root=$(task_dir "$id") || return 1
  [ -f "$root/state" ] || jig_die "task artifacts: unknown task: $id"
  # A linked task directory can point outside the validated checkout workspace.
  [ ! -L "$root" ] || jig_die "task artifacts: linked task workspace is unsupported"
  root=$(cd -P "$root" && pwd -P) || jig_die "task artifacts: cannot inspect workspace"
  local tasks_root
  tasks_root=$(cd -P "$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks" && pwd -P) || return 1
  case "$root" in "$tasks_root"/"$id") ;; *) jig_die "task artifacts: workspace outside task root" ;; esac
  class=$(task_state_get "$id" class)
  _task_valid_class "$class" || jig_die "task artifacts: invalid or missing class: $class"
  while [ $# -gt 0 ]; do
    case "$1" in
      --provided)
        [ $# -ge 2 ] || jig_die "task artifacts: --provided requires a value"
        [ "$seen" -eq 0 ] || jig_die "task artifacts: duplicate --provided"
        seen=1
        case "$2" in '' | ,* | *, | *,,* | *[!a-z,]*) jig_die "task artifacts: malformed --provided: $2" ;; esac
        provided=$(printf '%s' "$2" | tr ',' '\n')
        kinds=""
        while IFS= read -r kind; do
          _task_artifact_kind "$kind" || jig_die "task artifacts: unknown provided kind: $kind"
          case " $kinds " in *" $kind "*) jig_die "task artifacts: duplicate provided kind: $kind" ;; esac
          kinds="$kinds $kind"
        done < <(printf '%s\n' "$provided")
        shift 2 ;;
      *) jig_die "task artifacts: unknown argument: $1" ;;
    esac
  done
  t=$(printf '\t')
  printf 'task: %s; class: %s\nartifacts (optional unless consumed by a route stage):\n' "$id" "$class"
  for kind in task discovery spec alternatives design plan review verification handoff; do
    fact=$(_task_artifact_fact "$root" "$kind" "$provided")
    facts="$facts$kind$t$fact
"
    printf '  %-14s %s\n' "$kind" "$fact"
  done
  while IFS='|' read -r stage inputs semantic; do
    availability="inputs-available"
    for kind in $inputs; do
      fact=$(printf '%s' "$facts" | awk -F "$t" -v k="$kind" '$1 == k {print $2}')
      case "$fact" in unavailable*) availability="needs-input" ;; esac
    done
    printf '%s: %s; inputs: %s\n  unassessed: %s\n' "$stage" "$availability" "$inputs" "$semantic"
  done < <(_task_artifact_route "$class")
  printf 'Presence and provided claims do not prove approval, quality or completion; state unchanged.\n'
}
