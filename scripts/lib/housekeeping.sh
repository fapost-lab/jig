# cmd_housekeeping — reconcile task workspaces with remote merge state and
# retire what is finished (domains/housekeeping; ADR-0005, ADR-0006).
# Sourced by scripts/jig; defines cmd_housekeeping.
#
# Deterministic and unattended: no LLM (ADR-0001), no prompt, no interactive
# input. It runs from a terminal, from `scripts/jig-session-hook` and from an
# external scheduler with identical semantics, so every decision it makes has
# to be reconstructable afterwards from the log alone.
#
# bash 3.2 compatible: no associative arrays, no ${var,,}, no mapfile.
# shellcheck shell=bash

# Derived remote state is never written into a task `state` file (ADR-0005);
# it lives in these run-scoped globals and in the log.
_HK_VIA=""          # tier that decided the last remote state: forge|ancestry|none
_HK_FORGE_KIND=""   # github|gitlab|none — resolved once per run
_HK_FORGE_PRS=""    # "<branch><TAB><state>" lines, fetched once per run (C1)
_HK_STALE_REMOTE=0  # 1 when the fetch or the forge tier could not answer

cmd_housekeeping() {
  jig_require_init
  # shellcheck source=lib/task.sh
  . "$JIG_LIB/task.sh"

  local dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1; shift ;;
      *) jig_die "usage: jig housekeeping [--dry-run]" ;;
    esac
  done

  local runtime="$JIG_PROJECT/$JIG_AI_DIR/runtime"
  local tasks_dir="$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"

  local trash_ttl abandoned_ttl stale_after
  trash_ttl=$(cfg housekeeping.trash_ttl 7d)
  abandoned_ttl=$(cfg housekeeping.abandoned_ttl 14d)
  stale_after=$(cfg housekeeping.stale_after 60d)
  # Validate all three before touching anything: a typo in config.yaml must
  # fail the run, not silently become "0 days" and expire every trash entry.
  local trash_ttl_days abandoned_ttl_days stale_after_days
  trash_ttl_days=$(( $(jig_duration_seconds "$trash_ttl") / 86400 ))
  abandoned_ttl_days=$(( $(jig_duration_seconds "$abandoned_ttl") / 86400 ))
  stale_after_days=$(( $(jig_duration_seconds "$stale_after") / 86400 ))

  _hk_fetch "$dry"
  _hk_forge_init

  # A run boundary in the log. Without it the log is an undifferentiated
  # append-only history, and any reader asking "what does the latest run say"
  # has to guess with a line count — which is how `jig status` came to report
  # one unconsolidated task as three.
  if [ "$dry" != 1 ]; then
    _hk_log "--- run $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi

  local needs_consolidation=0 found=0
  local state_file tid st paused age branch base_commit remote remote_pair decision action flags dest facts

  if [ -d "$tasks_dir" ]; then
    while IFS= read -r state_file; do
      [ -z "$state_file" ] && continue
      tid=$(basename "$(dirname "$state_file")")
      # A directory that is not a well-formed task id is not ours to touch:
      # report it and never build a path from it (RULES.md, convention-shell).
      if ! _task_valid_id "$tid"; then
        printf 'skip %s (invalid task id)\n' "$tid"
        continue
      fi
      found=1

      st=$(task_state_get "$tid" status)
      paused=$(task_state_get "$tid" paused)
      branch=$(task_state_get "$tid" branch)
      age=$(_hk_task_age_days "$tid")

      base_commit=$(task_state_get "$tid" base_commit)
      remote_pair=$(_hk_remote_state "$branch" "$base_commit")
      remote=${remote_pair%% *}
      _HK_VIA=${remote_pair#* }

      decision=$(housekeeping_decide \
        "$st" "$remote" "$paused" "$age" "$abandoned_ttl_days" "$stale_after_days")
      action=${decision%% *}
      flags=${decision#* }
      [ "$flags" = "$decision" ] && flags=""

      case "$flags" in
        *needs-consolidation*) needs_consolidation=1 ;;
      esac

      dest=""
      facts=""
      if [ "$action" = "purge" ]; then
        # Read the facts a measurement needs *before* the workspace moves:
        # after `_hk_purge` the state file is in trash and this task's class
        # and age exist nowhere else (jig measure, ADR-0006).
        facts=$(_hk_task_facts "$tid")
        if [ "$dry" = 1 ]; then
          dest=$(_hk_trash_dest "$tid")
        else
          dest=$(_hk_purge "$tid")
        fi
      fi

      _hk_report "$dry" "$tid" "$st" "$remote" "$action" "$flags" "$dest" "$facts"
    done < <(find "$tasks_dir" -mindepth 2 -maxdepth 2 -name state -type f 2>/dev/null | LC_ALL=C sort)
  fi

  [ "$found" = 1 ] || printf 'no task workspaces\n'

  _hk_trash_expire "$dry" "$trash_ttl_days"

  [ "$_HK_STALE_REMOTE" = 1 ] && printf 'stale-remote: remote state could not be refreshed\n'

  if [ "$dry" = 1 ]; then
    printf 'dry run: nothing was changed\n'
    return 0
  fi

  mkdir -p "$runtime"
  : > "$runtime/last-housekeeping"

  # Exit 3, not 1: a hook or a cron job must be able to tell "someone has to
  # consolidate this" from "the command crashed" (jig_die uses 1), and 2 is
  # already `task current`'s ambiguity code (domains/housekeeping).
  if [ "$needs_consolidation" = 1 ]; then
    printf 'action needed: consolidate the tasks flagged needs-consolidation\n'
    return 3
  fi
  return 0
}

# --- policy ------------------------------------------------------------------

# housekeeping_decide <status> <remote> <paused> <age_days> <abandoned_ttl_days>
#                     <stale_after_days>
# Print "<action> [flags]" where action is purge|preserve and flags is a
# comma-separated subset of needs-consolidation, abandoned?, STALE_CANDIDATE.
#
# A pure function of six strings: no filesystem, no git, no config. That is
# what makes the domains/housekeeping policy table exhaustively testable, and it is the reason
# the destructive decision is separated from the destructive act.
housekeeping_decide() {
  local status="$1" remote="$2" paused="$3" age="$4" abandoned_ttl="$5" stale_after="$6"
  local action="preserve" flags=""

  case "$status:$remote" in
    consolidated:merged)
      action="purge"
      ;;
    active:merged|ready:merged)
      flags="needs-consolidation"
      ;;
    *:closed)
      flags="abandoned?"
      ;;
  esac

  # A merged task that was paused before consolidation still needs
  # consolidating: pause is orthogonal to status (ADR-0012) and never
  # suppresses a flag.
  if [ "$paused" = "true" ] && [ "$remote" = "merged" ]; then
    case "$status" in
      consolidated) ;;
      *) flags="needs-consolidation" ;;
    esac
  fi

  # `abandoned` is the one status whose purge is driven by a TTL rather than
  # by remote state, because a closed PR gives the workspace no other end.
  if [ "$status" = "abandoned" ] && [ "$age" -gt "$abandoned_ttl" ]; then
    action="purge"
    flags=""
  fi

  # Reported, never acted on: age is a hint, semantic lifecycle has priority
  # over TTL (domains/housekeeping).
  if [ "$age" -gt "$stale_after" ] && [ "$action" != "purge" ]; then
    if [ -n "$flags" ]; then
      flags="$flags,STALE_CANDIDATE"
    else
      flags="STALE_CANDIDATE"
    fi
  fi

  if [ -n "$flags" ]; then
    printf '%s %s\n' "$action" "$flags"
  else
    printf '%s\n' "$action"
  fi
}

# --- remote state ------------------------------------------------------------

# _hk_remote_state <branch> — print "<state> <via>" where state is
# merged|open|closed|unknown and via is the tier that decided it (domains/housekeeping).
#
# Both values are printed rather than one of them assigned to a global,
# because every caller reads this through `$(...)` and a subshell would
# discard the assignment — the log would then report a tier that never ran.
_hk_remote_state() {
  local branch="$1" base_commit="${2:-}" state

  if [ -z "$branch" ] || [ "$branch" = "detached" ]; then
    # `detached` is task.sh:100's fallback when HEAD is not on a branch, not a
    # ref name: there is nothing to resolve and nothing to infer from.
    printf 'unknown none\n'
    return 0
  fi

  state=$(_hk_forge_state "$branch")
  if [ -n "$state" ]; then
    printf '%s forge\n' "$state"
    return 0
  fi

  state=$(_hk_ancestry_state "$branch" "$base_commit")
  if [ "$state" = "merged" ]; then
    printf 'merged ancestry\n'
    return 0
  fi

  printf 'unknown none\n'
}

# _hk_fetch <dry> — refresh remote refs once per run when allowed. A failure
# is not fatal: the run continues on local state and says so (domains/housekeeping).
_hk_fetch() {
  local dry="$1"
  if ! cfg_bool housekeeping.fetch true; then
    return 0
  fi
  if [ "$dry" = 1 ]; then
    return 0
  fi
  if ! git -C "$JIG_PROJECT" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    return 0
  fi
  if ! git -C "$JIG_PROJECT" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  if ! git -C "$JIG_PROJECT" fetch --quiet origin >/dev/null 2>&1; then
    _HK_STALE_REMOTE=1
  fi
  return 0
}

# _hk_forge_init — resolve which forge CLI to use and pull every pull request
# in one call (alternatives.md C1). One network call per run, not per task:
# this command may fire at the start of every agent session.
_hk_forge_init() {
  _HK_FORGE_KIND="none"
  _HK_FORGE_PRS=""

  local want origin
  want=$(cfg forge auto)
  case "$want" in
    none) return 0 ;;
    auto|github|gitlab) ;;
    *) jig_die "invalid forge: $want (expected auto|github|gitlab|none)" ;;
  esac

  origin=$(git -C "$JIG_PROJECT" remote get-url origin 2>/dev/null || printf '')
  [ -n "$origin" ] || return 0

  if [ "$want" = "auto" ]; then
    case "$origin" in
      *github.com*) want="github" ;;
      *gitlab.com*|*gitlab.*) want="gitlab" ;;
      *) return 0 ;;
    esac
  fi

  case "$want" in
    github)
      command -v gh >/dev/null 2>&1 || return 0
      gh auth status >/dev/null 2>&1 || return 0
      _HK_FORGE_PRS=$(gh pr list --state all --limit 200 \
        --json headRefName,state \
        --jq '.[] | "\(.headRefName)\t\(.state)"' 2>/dev/null || printf '__failed__')
      ;;
    gitlab)
      command -v glab >/dev/null 2>&1 || return 0
      glab auth status >/dev/null 2>&1 || return 0
      # One JSON object per line first: `glab` returns a compact single-line
      # array, and a greedy `.*` across the whole line would keep only the
      # last merge request and silently drop every other one.
      _HK_FORGE_PRS=$(glab mr list --all --output json 2>/dev/null \
        | sed 's/},[[:space:]]*{/}\
{/g' \
        | sed -n 's/.*"source_branch":"\([^"]*\)".*"state":"\([^"]*\)".*/\1	\2/p' \
        || printf '__failed__')
      ;;
  esac

  if [ "$_HK_FORGE_PRS" = "__failed__" ]; then
    # The tier is abandoned for the whole run rather than retried per task:
    # a forge that failed once will fail 40 times, slowly.
    _HK_FORGE_PRS=""
    _HK_STALE_REMOTE=1
    return 0
  fi
  _HK_FORGE_KIND="$want"
  return 0
}

# _hk_forge_state <branch> — merged|open|closed from the cached listing, or
# nothing when this branch has no pull request (fall through to ancestry).
_hk_forge_state() {
  local branch="$1" line raw
  [ "$_HK_FORGE_KIND" = "none" ] && return 0
  [ -n "$_HK_FORGE_PRS" ] || return 0

  line=$(printf '%s\n' "$_HK_FORGE_PRS" | awk -F'\t' -v b="$branch" '$1 == b { print $2; exit }')
  [ -n "$line" ] || return 0

  raw=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
  case "$raw" in
    merged) printf 'merged\n' ;;
    open|opened) printf 'open\n' ;;
    closed|locked) printf 'closed\n' ;;
    *) return 0 ;;
  esac
}

# _hk_ancestry_state <branch> — merged|unknown.
#
# Deliberately narrower than domains/housekeeping (design.md §2): git knows whether work
# landed and knows nothing about pull requests, so "not an ancestor" is not
# evidence of an open PR. The housekeeping policy gives `open` and `unknown` the same
# action, so this costs no behaviour and keeps the report honest.
_hk_ancestry_state() {
  local branch="$1" base_commit="${2:-}" base tip mb combined c base_name
  base_name=$(cfg git.base_branch main)

  # The task never had a branch of its own: it was worked on directly on the
  # base branch. "Did it merge?" is then unanswerable locally, because
  # `merge-base --is-ancestor main main` is trivially true — a commit is its
  # own ancestor — and would report every such task as merged.
  #
  # This is not hypothetical. On this repository, where 17 of 19 workspaces
  # carry `branch: main`, the earlier version of this function reported
  # `merged` for all of them, which turned 13 `consolidated` workspaces into
  # would-purge on the first real run. Trunk-based work has no local evidence
  # of landing, so the honest answer is `unknown` and the workspace is
  # preserved; only a forge can resolve these (domains/housekeeping: when uncertain,
  # preserve).
  if [ "$branch" = "$base_name" ]; then
    printf 'unknown\n'
    return 0
  fi

  base=$(_hk_base_ref) || return 0
  [ -n "$base" ] || { printf 'unknown\n'; return 0; }

  tip=$(_hk_resolve_ref "$branch")
  if [ -z "$tip" ]; then
    printf 'unknown\n'
    return 0
  fi

  # 0. The branch has contributed nothing since the task forked it, so there
  # is nothing that could have landed. Without this, a freshly created task
  # branch answers `merged` — its tip *is* the base's — and a task that
  # reaches `consolidated` without ever committing gets purged while all of
  # its work sits uncommitted in the working tree. Measured, not theorised.
  #
  # Only tasks that recorded a fork point can be asked this; a workspace from
  # before `base_commit` existed skips the check and behaves as it always did.
  # `cat-file -e <sha>^{commit}`, not `rev-parse --verify`: the latter accepts
  # the all-zero SHA as a well-formed object name and reports success, so a
  # stale fork point from a rewritten history would pass the check and then
  # make every rev-list against it empty — reading as "did nothing" for a
  # branch that may well have landed.
  if [ -n "$base_commit" ] \
     && git -C "$JIG_PROJECT" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
    if [ -z "$(git -C "$JIG_PROJECT" rev-list -n 1 "$base_commit..$tip" 2>/dev/null)" ]; then
      printf 'unknown\n'
      return 0
    fi
  fi

  # 1. Fast-forward or a real merge commit.
  if git -C "$JIG_PROJECT" merge-base --is-ancestor "$tip" "$base" 2>/dev/null; then
    printf 'merged\n'
    return 0
  fi

  mb=$(git -C "$JIG_PROJECT" merge-base "$base" "$tip" 2>/dev/null || printf '')
  if [ -z "$mb" ]; then
    printf 'unknown\n'
    return 0
  fi

  # 2. Squash merge: the branch's whole contribution collapses into one commit
  # on the base, so its patch-id matches the combined diff — not any single
  # commit's. Comparing commit-by-commit is what gets this case wrong.
  # Guarded: an unguarded pipeline assignment under `set -e` + `pipefail`
  # would abort the whole run mid-loop, and every git call here silences its
  # own stderr, so there would be no diagnostic to explain the silence.
  combined=$(git -C "$JIG_PROJECT" diff "$mb" "$tip" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1) || combined=""
  if [ -n "$combined" ]; then
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      if [ "$c" = "$combined" ]; then
        printf 'merged\n'
        return 0
      fi
    done < <(_hk_base_patch_ids "$mb" "$base")
  fi

  # 3. Rebase merge: every commit is upstream individually. `git cherry`
  # marks those with `-`; a single `+` means something did not land.
  local cherry plus
  cherry=$(git -C "$JIG_PROJECT" cherry "$base" "$tip" 2>/dev/null || printf '')
  if [ -n "$cherry" ]; then
    plus=$(printf '%s\n' "$cherry" | grep -c '^+' || true)
    if [ "$plus" = "0" ]; then
      printf 'merged\n'
      return 0
    fi
  fi

  printf 'unknown\n'
}

# _hk_base_patch_ids <merge-base> <base> — patch-id of every commit the base
# gained since the merge base, one per line.
_hk_base_patch_ids() {
  local mb="$1" base="$2" sha
  while IFS= read -r sha; do
    [ -z "$sha" ] && continue
    git -C "$JIG_PROJECT" show "$sha" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1
  done < <(git -C "$JIG_PROJECT" rev-list "$mb..$base" 2>/dev/null)
}

# _hk_base_ref — the ref merges land on: origin/<base_branch> when it exists,
# else the local branch. Empty when neither resolves.
_hk_base_ref() {
  local base
  base=$(cfg git.base_branch main)
  _hk_resolve_ref "$base"
}

# _hk_resolve_ref <name> — print the first of <name> / origin/<name> that
# resolves to a commit, or nothing.
_hk_resolve_ref() {
  local name="$1"
  [ -n "$name" ] || return 0
  if git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/heads/$name" >/dev/null 2>&1; then
    printf '%s\n' "refs/heads/$name"
    return 0
  fi
  if git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/remotes/origin/$name" >/dev/null 2>&1; then
    printf '%s\n' "refs/remotes/origin/$name"
    return 0
  fi
  return 0
}

# --- purge -------------------------------------------------------------------

# _hk_trash_dest <task-id> — the trash path this task would be moved to,
# avoiding collision with an entry purged earlier the same day. Never
# overwrites and never merges into an existing entry (ADR-0006).
_hk_trash_dest() {
  local id="$1" day base dest n
  day=$(jig_today)
  base="$JIG_PROJECT/$JIG_AI_DIR/runtime/trash/$day/$id"
  dest="$base"
  n=2
  while [ -e "$dest" ]; do
    dest="$base-$n"
    n=$((n + 1))
  done
  printf '%s\n' "$dest"
}

# _hk_purge <task-id> — move the workspace to trash. Prints the destination.
# Phase one of ADR-0006: this function contains no `rm`.
_hk_purge() {
  local id="$1" dir dest expect
  # task_dir applies _task_valid_id, the single choke point for every path
  # built from a task id (RULES.md). ADR-0006's own text states a weaker
  # pattern that matches `..`; the implementation is the correct one and is
  # not restated here.
  dir=$(task_dir "$id")
  [ -d "$dir" ] || jig_die "housekeeping: not a directory: $dir"

  # Belt and braces: after resolution the path must still be a task workspace
  # inside this project's .ai/ tree.
  expect="$(cd "$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks" && pwd -P)"
  case "$(cd "$dir" && pwd -P)" in
    "$expect"/*) ;;
    *) jig_die "housekeeping: refusing to move a path outside $expect: $dir" ;;
  esac

  dest=$(_hk_trash_dest "$id")
  mkdir -p "$(dirname "$dest")"
  mv "$dir" "$dest"
  printf '%s\n' "$dest"
}

# _hk_trash_expire <dry> <ttl_days> — phase two of ADR-0006. The age comes
# from the <date> directory name, not from mtime, so moving a workspace into
# trash does not restart its clock.
_hk_trash_expire() {
  local dry="$1" ttl="$2" trash day entry age
  trash="$JIG_PROJECT/$JIG_AI_DIR/runtime/trash"
  [ -d "$trash" ] || return 0

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    day=$(basename "$entry")
    case "$day" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) continue ;;
    esac
    age=$(_hk_days_since "$day")
    [ "$age" -gt "$ttl" ] || continue

    case "$(cd "$entry" && pwd -P)" in
      "$(cd "$trash" && pwd -P)"/*) ;;
      *) jig_die "housekeeping: refusing to delete outside $trash: $entry" ;;
    esac

    if [ "$dry" = 1 ]; then
      printf 'would-delete trash/%s (%d days old)\n' "$day" "$age"
    else
      rm -rf "$entry"
      printf 'delete trash/%s (%d days old)\n' "$day" "$age"
      _hk_log "$(date -u +%Y-%m-%dT%H:%M:%SZ) trash=$day action=delete age=${age}d"
    fi
  done < <(find "$trash" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)
}

# --- reporting ---------------------------------------------------------------

# _hk_report <dry> <task> <status> <remote> <action> <flags> <dest> [facts]
# One stdout line for a human, one log line for the audit trail. The log
# records `via=` — the tier that decided — because "why was this deleted" has
# to be answerable from the log alone, months later.
#
# `facts` carries the purged task's own attributes and is logged, not printed:
# a purge is the last moment they exist anywhere, and the log is the only thing
# that outlives the workspace. It is empty for every non-purge decision, so a
# preserve line keeps repeating the same short shape on every run.
_hk_report() {
  local dry="$1" tid="$2" st="$3" remote="$4" action="$5" flags="$6" dest="$7"
  local facts="${8:-}"
  local shown="$action" rel=""

  if [ "$action" = "purge" ]; then
    rel=$(jig_relpath "$dest" "$JIG_PROJECT")
    [ "$dry" = 1 ] && shown="would-purge"
  fi

  local line="$tid status=$st remote=$remote via=$_HK_VIA action=$shown"
  [ -n "$rel" ] && line="$line dest=$rel"
  [ -n "$flags" ] && line="$line flags=$flags"
  printf '%s\n' "$line"

  [ "$dry" = 1 ] && return 0
  _hk_log "$(date -u +%Y-%m-%dT%H:%M:%SZ) task=$tid status=$st remote=$remote via=$_HK_VIA action=$shown${rel:+ dest=$rel}${flags:+ flags=$flags}${facts:+ $facts}"
}

_hk_log() {
  local runtime="$JIG_PROJECT/$JIG_AI_DIR/runtime"
  mkdir -p "$runtime"
  printf '%s\n' "$1" >> "$runtime/housekeeping.log"
}

# _hk_task_facts <id> — the attributes a purged task takes with it, as log
# fields: `class=`, `created=`, `consolidated=`. A value the state file does not
# carry is omitted entirely rather than defaulted, so a reader can tell "this
# task had no class" from "this line predates the field" — neither of which is
# a T0 (jig measure).
#
# Recording them here rather than in a series of its own is the whole storage
# decision: measurement is derived from evidence that already exists, and the
# purge is the one gate every workspace passes through on its way out.
_hk_task_facts() {
  local id="$1" class created consolidated out=""
  class=$(task_state_get "$id" class)
  created=$(task_state_get "$id" created_at)
  consolidated=$(task_state_get "$id" knowledge_consolidated)
  [ -z "$class" ] || out="class=$class"
  [ -z "$created" ] || out="${out:+$out }created=$created"
  [ -z "$consolidated" ] || out="${out:+$out }consolidated=$consolidated"
  printf '%s\n' "$out"
}

# --- age ---------------------------------------------------------------------

# _hk_task_age_days <id> — days since the task was last touched. `updated_at`
# is refreshed by every `jig task set`, so it measures "how long since anyone
# worked on this", which is what both TTLs are about.
_hk_task_age_days() {
  local id="$1" d
  d=$(task_state_get "$id" updated_at)
  [ -n "$d" ] || d=$(task_state_get "$id" created_at)
  _hk_days_since "$d"
}

# _hk_days_since <YYYY-MM-DD> — whole days elapsed, 0 when unparsable.
# Mirrors jig_file_age_days's BSD/GNU `date` portability trick.
_hk_days_since() {
  local d="$1" ts now
  [ -n "$d" ] || { printf '0\n'; return; }
  if ts=$(date -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null); then :; else
    ts=$(date -d "$d" +%s 2>/dev/null) || { printf '0\n'; return; }
  fi
  now=$(date +%s)
  printf '%d\n' $(( (now - ts) / 86400 ))
}
