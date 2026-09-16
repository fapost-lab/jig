# cmd_spec — specifications under .ai/specs/<id>/ (the jig-idea skill).
# Sourced by scripts/jig; defines cmd_spec.
#
# A specification is a plan, not knowledge: it lives outside .ai/knowledge/,
# carries no status, and everything reported here is derived from its files —
# the first heading of spec.md and the checkboxes of roadmap.md (ADR-0035).
#
# A task links to a spec through one `Spec: .ai/specs/<id>/ — Phase <n>` line in
# its task.md. `new` creates a spec, `done` checks a linked task's roadmap
# items, `remove` unlinks a spec's open tasks and moves the spec to trash,
# `epic` declares, cuts, finishes and reopens a spec's epic branch (ADR-0039);
# `list` only reads.
# shellcheck shell=bash

SPEC_USAGE="usage: jig spec new <id> | jig spec list | jig spec done <task-id> | jig spec remove <id> [--dry-run] [--abandon-unstarted] | jig spec epic <id> [--finish | --reopen]"

cmd_spec() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    new) spec_new "$@" ;;
    list) spec_list "$@" ;;
    done) spec_done "$@" ;;
    remove) spec_remove "$@" ;;
    epic) spec_epic "$@" ;;
    -h | --help)
      printf '%s\n' "$SPEC_USAGE" >&2
      return 0
      ;;
    '')
      printf '%s\n' "$SPEC_USAGE" >&2
      exit 1
      ;;
    *) jig_die "spec: unknown subcommand: $sub ($SPEC_USAGE)" ;;
  esac
}

# spec_template <file> — the template to instantiate: the copy installed under
# .ai/templates/spec/ first, the framework checkout as a fallback for a
# project initialised before spec templates were installed (as km_template).
spec_template() {
  local installed src
  installed="$JIG_PROJECT/$JIG_AI_DIR/templates/spec/$1"
  if [ -f "$installed" ]; then
    printf '%s\n' "$installed"
    return 0
  fi
  src=$(jig_source_root)
  if [ -n "$src" ] && [ -f "$src/templates/spec/$1" ]; then
    printf '%s\n' "$src/templates/spec/$1"
    return 0
  fi
  return 1
}

# spec_new <id> — create .ai/specs/<id>/ with spec.md and roadmap.md from the
# templates. The id is validated here, at the one place the path is built:
# a directory with an invalid name would be skipped by every listing, so a
# spec created under one would silently not exist.
spec_new() {
  [ $# -ge 1 ] || jig_die "spec new: missing spec id (usage: jig spec new <id>)"
  [ $# -eq 1 ] || jig_die "spec new: unexpected argument: $2"
  local id="$1" root dir spec_tpl roadmap_tpl f
  spec_valid_id "$id" \
    || jig_die "spec new: invalid spec id: $id (letters, digits, '.', '_', '-'; no leading dot or dash)"
  jig_require_init
  # Both templates are resolved before anything is created, so a missing one
  # leaves no empty directory behind.
  spec_tpl=$(spec_template spec.md) \
    || jig_die "spec new: no template spec.md; run: jig upgrade"
  roadmap_tpl=$(spec_template roadmap.md) \
    || jig_die "spec new: no template roadmap.md; run: jig upgrade"
  root=$(spec_dir)
  dir="$root/$id"
  [ ! -e "$dir" ] || jig_die "spec new: spec already exists: $JIG_AI_DIR/specs/$id"
  mkdir -p "$root" || jig_die "spec new: cannot create $JIG_AI_DIR/specs"
  # A plain mkdir is the existence check that cannot race: it fails if the
  # directory appeared since the test above.
  mkdir "$dir" 2>/dev/null || jig_die "spec new: spec already exists: $JIG_AI_DIR/specs/$id"
  # Both files are written under temporary names first, so a failed copy
  # leaves nothing half-created and a retry works. The cleanup removes only
  # the files this run named and then `rmdir`s the directory, which refuses
  # anything that is not empty — it cannot delete what someone else put there.
  if ! cp "$spec_tpl" "$dir/spec.md.tmp.$$" || ! cp "$roadmap_tpl" "$dir/roadmap.md.tmp.$$"; then
    rm -f "$dir/spec.md.tmp.$$" "$dir/roadmap.md.tmp.$$"
    rmdir "$dir" 2>/dev/null || true
    jig_die "spec new: could not copy the templates into $JIG_AI_DIR/specs/$id"
  fi
  for f in spec.md roadmap.md; do
    mv "$dir/$f.tmp.$$" "$dir/$f" || jig_die "spec new: could not write $JIG_AI_DIR/specs/$id/$f"
    printf '%s/specs/%s/%s\n' "$JIG_AI_DIR" "$id" "$f"
  done
}

spec_dir() {
  printf '%s/%s/specs\n' "$JIG_PROJECT" "$JIG_AI_DIR"
}

# spec_valid_id <id> — the same grammar as a task id, from the one place both
# read it (common.sh, jig_valid_id).
spec_valid_id() {
  jig_valid_id "$1"
}

# spec_ids — valid spec ids, one per line, in directory order. A directory
# whose name is not a valid id is skipped rather than reported: nothing can
# address it by id.
spec_ids() {
  local root d id
  root=$(spec_dir)
  [ -d "$root" ] || return 0
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    id=${d##*/}
    spec_valid_id "$id" || continue
    printf '%s\n' "$id"
  done
}

spec_count() {
  spec_ids | grep -c . || true
}

# spec_title <spec.md> — the text of the first level-one heading, or empty.
spec_title() {
  sed -n 's/^#[[:space:]]\{1,\}//p' "$1" | head -n 1
}

# spec_progress <roadmap.md> — "roadmap D/T done, F filed, fog G".
#
# An item is a checkbox line. Done is a checked one. Filed is an unchecked item
# whose text starts with a backticked task id followed by a dash — the id alone
# is not enough, because an item may just as well open with a backticked
# command name. Fog is an unchecked item whose text starts with `fog:`. Wave
# lines are a numbered list, not checkboxes, so they are never counted.
spec_progress() {
  awk '
    /^[[:space:]]*[-*][[:space:]]+\[[ xX]\]/ {
      total++
      if ($0 ~ /\[[xX]\]/) { done++; next }
      text = $0
      sub(/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]*/, "", text)
      # "—" is matched as its UTF-8 bytes, which every awk compares as-is.
      if (text ~ /^`[A-Za-z0-9._-]+`[[:space:]]+(—|-|--)[[:space:]]/) filed++
      else if (text ~ /^fog:/) fog++
    }
    END { printf "roadmap %d/%d done, %d filed, fog %d\n", done, total, filed, fog }
  ' "$1"
}

spec_list() {
  [ $# -eq 0 ] || jig_die "spec list: unexpected argument: $1"
  jig_require_repo
  local root id title state missing rows=""
  root=$(spec_dir)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    title="" missing=""
    if [ -f "$root/$id/spec.md" ]; then
      title=$(spec_title "$root/$id/spec.md")
    else
      missing="spec.md"
    fi
    [ -f "$root/$id/roadmap.md" ] || missing="${missing:+$missing, }roadmap.md"
    if [ -n "$missing" ]; then
      state="incomplete (no $missing)"
    else
      state=$(spec_list_state "$root/$id/roadmap.md")
    fi
    [ -n "$title" ] || title="-"
    # A tab cannot occur in any field: ids exclude it, and a heading is one
    # line whose tabs are folded to spaces here.
    title=$(printf '%s' "$title" | tr '\t' ' ')
    rows="$rows$id	$title	$state
"
  done < <(spec_ids)
  [ -n "$rows" ] || return 0
  printf '%s' "$rows" | awk -F '\t' '
    { id[NR] = $1; t[NR] = $2; s[NR] = $3
      if (length($1) > wi) wi = length($1)
      if (length($2) > wt) wt = length($2) }
    # The width is spliced into the format, not passed as `*`: not every awk
    # on a supported machine takes a dynamic width.
    END { fmt = "%-" wi "s   %-" wt "s   %s\n"
          for (i = 1; i <= NR; i++) printf fmt, id[i], t[i], s[i] }
  '
}

# spec_list_state <roadmap.md> — what `spec list` says about a spec's progress.
#
# The roadmap of a spec with an open epic is edited only on the epic, so its
# copy anywhere else is stale by design: off the epic the line names where
# progress is instead of showing old checkmarks as current. A finished epic's
# roadmap reaches the default branch with the epic, current again (ADR-0039).
spec_list_state() {
  local roadmap="$1" line branch here
  line=$(jig_spec_epic "$roadmap" 2>/dev/null) || line=""
  if [ -z "$line" ] || [ "${line##* }" = finished ]; then
    spec_progress "$roadmap"
    return 0
  fi
  branch=${line% *}
  here=$(git -C "$JIG_PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [ "$here" = "$branch" ]; then
    printf '%s (on %s)\n' "$(spec_progress "$roadmap")" "$branch"
  elif ! git check-ref-format --branch "$branch" >/dev/null 2>&1 \
       || [ -z "$(jig_base_ref "$branch")" ]; then
    printf '%s — branch missing\n' "$branch"
  else
    printf '%s — progress is on the epic\n' "$branch"
  fi
}

# spec_epic_status — one line per spec with an open epic, for `jig status`:
# where its work is, and how far the epic has fallen behind the default
# branch it is kept current with by merging (ADR-0039). Read-only; the refs
# are whatever this checkout last fetched.
spec_epic_status() {
  local root id line branch default base_ref epic_ref behind
  root=$(spec_dir)
  default=$(cfg git.base_branch main)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ -f "$root/$id/roadmap.md" ] || continue
    line=$(jig_spec_epic "$root/$id/roadmap.md" 2>/dev/null) || continue
    [ -n "$line" ] && [ "${line##* }" = open ] || continue
    branch=${line% *}
    epic_ref=""
    if git check-ref-format --branch "$branch" >/dev/null 2>&1; then
      epic_ref=$(jig_base_ref "$branch")
    fi
    if [ -z "$epic_ref" ]; then
      printf 'epic: %s on %s, branch missing\n' "$id" "$branch"
      continue
    fi
    base_ref=$(jig_base_ref "$default")
    if [ -z "$base_ref" ]; then
      printf 'epic: %s on %s\n' "$id" "$branch"
      continue
    fi
    behind=$(git -C "$JIG_PROJECT" rev-list --count "$epic_ref..$base_ref" 2>/dev/null) || behind=""
    if [ -n "$behind" ]; then
      printf 'epic: %s on %s, %s commits behind %s\n' "$id" "$branch" "$behind" "$default"
    else
      printf 'epic: %s on %s\n' "$id" "$branch"
    fi
  done < <(spec_ids)
}

# --- epic branches ---------------------------------------------------------------

# spec_epic <id> [--finish | --reopen] — the epic branch of a spec released
# once, at the end (ADR-0039).
#
# Without a flag: declare the epic with an `Epic: epic/<id>` line when the
# roadmap has none, and stop — the line has to reach the default branch before
# the epic is cut from it, or neither the epic nor a checkout of the default
# branch would know where the spec's tasks go. With the line on the freshest
# default branch, cut `epic/<id>` there, without a checkout; pushing it is the
# human's step. `--finish`, on the epic after the default branch was merged
# into it, closes the line before the final pull request; `--reopen` takes
# that back when review of the final pull request needs a fix.
spec_epic() {
  [ $# -ge 1 ] || jig_die "spec epic: missing spec id (usage: jig spec epic <id> [--finish | --reopen])"
  local id="$1" mode=declare
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --finish) [ "$mode" = declare ] || jig_die "spec epic: --finish and --reopen exclude each other"; mode=finish ;;
      --reopen) [ "$mode" = declare ] || jig_die "spec epic: --finish and --reopen exclude each other"; mode=reopen ;;
      *) jig_die "spec epic: unexpected argument: $1" ;;
    esac
    shift
  done
  spec_valid_id "$id" || jig_die "spec epic: invalid spec id: $id"
  jig_require_init
  local roadmap rel line rc=0
  roadmap="$(spec_dir)/$id/roadmap.md"
  rel="$JIG_AI_DIR/specs/$id/roadmap.md"
  [ -f "$roadmap" ] || jig_die "spec epic: no such spec, or it has no roadmap: $rel"
  line=$(jig_spec_epic "$roadmap") || rc=$?
  [ "$rc" -ne 2 ] || jig_die "spec epic: $rel declares more than one epic; keep one Epic: line"

  case "$mode" in
    declare) spec_epic_declare "$id" "$roadmap" "$rel" "$line" ;;
    finish) spec_epic_finish "$id" "$roadmap" "$rel" "$line" ;;
    reopen) spec_epic_reopen "$id" "$roadmap" "$rel" "$line" ;;
  esac
}

spec_epic_declare() {
  local id="$1" roadmap="$2" rel="$3" line="$4" branch default start commit on_default rc=0
  if [ -z "$line" ]; then
    branch="epic/$id"
    git check-ref-format --branch "$branch" >/dev/null 2>&1 \
      || jig_die "spec epic: git rejects the branch name: $branch"
    spec_epic_write "$roadmap" "declare" "$branch"
    printf '%s: Epic: %s\n' "$rel" "$branch"
    jig_info "spec epic: commit $rel and merge it into $(cfg git.base_branch main), then run \`jig spec epic $id\` again to cut $branch"
    return 0
  fi
  branch=${line% *}
  [ "${line##* }" = open ] || jig_die "spec epic: epic $branch is finished; \`jig spec epic $id --reopen\` on it takes that back"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 \
    || jig_die "spec epic: git rejects the branch name: $branch"
  if [ -n "$(jig_base_ref "$branch")" ]; then
    printf 'exists: %s\n' "$branch"
    return 0
  fi

  default=$(cfg git.base_branch main)
  jig_fetch_branches "spec epic" "$default"
  # Checked again after the fetch: the epic may have been pushed by somebody
  # else since this checkout last looked.
  jig_fetch_branches "spec epic" "$branch" 2>/dev/null
  if [ -n "$(jig_base_ref "$branch")" ]; then
    printf 'exists: %s\n' "$branch"
    return 0
  fi
  start=$(jig_fresh_base_ref "$default" "spec epic") || exit 1
  [ "$start" != HEAD ] || jig_die "spec epic: $default exists neither here nor on origin"
  commit=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "$start^{commit}" 2>/dev/null) \
    || jig_die "spec epic: cannot resolve $start"
  on_default=$(git -C "$JIG_PROJECT" show "$commit:$rel" 2>/dev/null | jig_spec_epic -) || rc=$?
  [ "$rc" -eq 0 ] && [ "$on_default" = "$branch open" ] \
    || jig_die "spec epic: the Epic: line of $rel is not on $default yet; merge it into $default first"
  git -C "$JIG_PROJECT" branch "$branch" "$commit" >/dev/null 2>&1 \
    || jig_die "spec epic: could not create $branch"
  printf 'created: %s at %s\n' "$branch" "$commit"
  jig_info "spec epic: push it with \`git push -u origin $branch\`"
}

spec_epic_finish() {
  local id="$1" roadmap="$2" rel="$3" line="$4" branch here default start open_items
  [ -n "$line" ] || jig_die "spec epic: $rel declares no epic"
  branch=${line% *}
  [ "${line##* }" = open ] || jig_die "spec epic: epic $branch is already finished"
  here=$(git -C "$JIG_PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ "$here" = "$branch" ] || jig_die "spec epic: --finish runs on $branch; switch to it first"
  default=$(cfg git.base_branch main)
  jig_fetch_branches "spec epic" "$default"
  start=$(jig_fresh_base_ref "$default" "spec epic") || exit 1
  if [ "$start" != HEAD ] \
     && ! git -C "$JIG_PROJECT" merge-base --is-ancestor "$start" HEAD 2>/dev/null; then
    jig_die "spec epic: $branch does not contain the latest $default; merge $default into it first"
  fi
  # Unchecked items are reported, not refused: a later phase may have been
  # set aside on purpose. Fog is never counted as unfinished work.
  open_items=$(awk '/^[[:space:]]*- \[ \] / && !/^[[:space:]]*- \[ \] fog:/' "$roadmap")
  if [ -n "$open_items" ]; then
    jig_warn "spec epic: $rel still has unchecked items:"
    printf '%s\n' "$open_items" | sed 's/^[[:space:]]*/  /' >&2
  fi
  spec_epic_write "$roadmap" finish "$branch"
  printf '%s: Epic: %s — finished\n' "$rel" "$branch"
  jig_info "spec epic: commit it with the version bump, then open the pull request from $branch into $default"
}

spec_epic_reopen() {
  local id="$1" roadmap="$2" rel="$3" line="$4" branch here
  [ -n "$line" ] || jig_die "spec epic: $rel declares no epic"
  branch=${line% *}
  [ "${line##* }" = finished ] || jig_die "spec epic: epic $branch is not finished"
  here=$(git -C "$JIG_PROJECT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ "$here" = "$branch" ] || jig_die "spec epic: --reopen runs on $branch; switch to it first"
  spec_epic_write "$roadmap" reopen "$branch"
  printf '%s: Epic: %s\n' "$rel" "$branch"
}

# spec_epic_write <roadmap> <declare|finish|reopen> <branch> — rewrite the
# Epic: line in place, atomically. `declare` puts it after the Destination:
# line and refuses a roadmap without one.
spec_epic_write() {
  local roadmap="$1" op="$2" branch="$3" tmp
  tmp="$roadmap.tmp.$$"
  awk -v op="$op" -v b="$branch" '
    function epic_line(l) { return l ~ /^Epic:[[:space:]]+[^[:space:]]+([[:space:]]+(—|-|--)[[:space:]]+finished)?[[:space:]]*$/ }
    op == "declare" {
      print
      if (!done && $0 ~ /^Destination:/) { print ""; print "Epic: " b; done = 1 }
      next
    }
    epic_line($0) { print (op == "finish" ? "Epic: " b " — finished" : "Epic: " b); next }
    { print }
    END { if (op == "declare" && !done) exit 3 }
  ' "$roadmap" > "$tmp" || {
    rm -f "$tmp"
    if [ "$op" = declare ]; then
      jig_die "spec epic: $roadmap has no Destination: line to put the Epic: line after"
    fi
    jig_die "spec epic: could not rewrite $roadmap"
  }
  mv "$tmp" "$roadmap" || jig_die "spec epic: could not write $roadmap"
}

# --- task links ----------------------------------------------------------------

# spec_task_dir <task-id> — a task workspace in this checkout. The one place
# spec.sh builds a path from a task id (RULES.md): spec.sh may not source
# task.sh, so it cannot reach task_dir, and checks the same grammar through
# jig_valid_id. Returns 1 for an invalid id instead of dying, because callers
# run it inside $(...), where jig_die would only leave the subshell.
spec_task_dir() {
  jig_valid_id "$1" || return 1
  printf '%s/%s/workspace/tasks/%s\n' "$JIG_PROJECT" "$JIG_AI_DIR" "$1"
}

# spec_task_state <task-dir> <key> — one key of a task's state file, or
# nothing. Read-only: `state` is written by `jig task` alone.
spec_task_state() {
  [ -f "$1/state" ] || return 0
  sed -n "s/^$2:[[:space:]]*//p" "$1/state" | head -n 1
}

# spec_done <task-id> — check the roadmap items that name a linked task.
#
# Called by jig-consolidate when the knowledge decision is recorded, before the
# commit, so the checkmark lands on the base branch in the same change as the
# work (ADR-0035 as amended). An item names the task when its text starts with
# the backticked id and a dash, the grammar `jig spec list` counts as filed.
spec_done() {
  [ $# -ge 1 ] || jig_die "spec done: missing task id (usage: jig spec done <task-id>)"
  [ $# -eq 1 ] || jig_die "spec done: unexpected argument: $2"
  local tid="$1" tdir sid roadmap tmp out rc=0
  jig_require_init
  tdir=$(spec_task_dir "$tid") || jig_die "spec done: invalid task id: $tid"
  [ -f "$tdir/task.md" ] || jig_die "spec done: unknown task: $tid (no $JIG_AI_DIR/workspace/tasks/$tid/task.md)"
  sid=$(jig_spec_link "$tdir/task.md") || rc=$?
  [ "$rc" = 0 ] || jig_die "spec done: $tid links to more than one spec in its task.md"
  if [ -z "$sid" ]; then
    printf 'spec done: %s is not linked to a spec\n' "$tid"
    return 0
  fi
  [ -d "$(spec_dir)/$sid" ] \
    || jig_die "spec done: $tid links to $JIG_AI_DIR/specs/$sid/, which does not exist"
  roadmap="$(spec_dir)/$sid/roadmap.md"
  [ -f "$roadmap" ] || jig_die "spec done: no roadmap.md in $JIG_AI_DIR/specs/$sid/"

  tmp="$roadmap.tmp.$$"
  rc=0
  # Exit 3: no item names the task. Exit 4: every item that does is checked.
  # The id is compared as a string, not a pattern: `.` is legal in an id.
  out=$(awk -v id="$tid" -v tmp="$tmp" '
    {
      line = $0
      if (line ~ /^[[:space:]]*[-*][[:space:]]+\[[ xX]\]/) {
        text = line
        sub(/^[[:space:]]*[-*][[:space:]]+\[[ xX]\][[:space:]]*/, "", text)
        head = "`" id "`"
        if (substr(text, 1, length(head)) == head &&
            substr(text, length(head) + 1) ~ /^[[:space:]]+(—|-|--)[[:space:]]/) {
          matched++
          if (line ~ /^[[:space:]]*[-*][[:space:]]+\[ \]/) {
            sub(/\[ \]/, "[x]", line)
            marked++
            print line
          }
        }
      }
      print line > tmp
    }
    END {
      close(tmp)
      if (matched == 0) exit 3
      if (marked == 0) exit 4
    }
  ' "$roadmap") || rc=$?
  case "$rc" in
    0)
      mv "$tmp" "$roadmap" || jig_die "spec done: could not write $JIG_AI_DIR/specs/$sid/roadmap.md"
      printf 'spec done: %s checked in %s/specs/%s/roadmap.md\n' "$tid" "$JIG_AI_DIR" "$sid"
      printf '%s\n' "$out" | sed 's/^/  /'
      ;;
    3)
      rm -f "$tmp"
      jig_die "spec done: no item in $JIG_AI_DIR/specs/$sid/roadmap.md names $tid; the roadmap and the task disagree"
      ;;
    4)
      rm -f "$tmp"
      printf 'spec done: %s already done in %s/specs/%s/roadmap.md\n' "$tid" "$JIG_AI_DIR" "$sid"
      ;;
    *)
      rm -f "$tmp"
      jig_die "spec done: could not read $JIG_AI_DIR/specs/$sid/roadmap.md"
      ;;
  esac
}

# spec_roadmap_ids <roadmap.md> — task ids named by unchecked items, one per
# line, each once.
spec_roadmap_ids() {
  awk '
    /^[[:space:]]*[-*][[:space:]]+\[ \]/ {
      text = $0
      sub(/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]*/, "", text)
      if (text ~ /^`[A-Za-z0-9._-]+`[[:space:]]+(—|-|--)[[:space:]]/) {
        id = substr(text, 2)
        sub(/`.*$/, "", id)
        # The same grammar as jig_valid_id: no leading dot or dash.
        if (id ~ /^[.-]/) next
        if (!(id in seen)) { seen[id] = 1; print id }
      }
    }
  ' "$1"
}

# spec_remove <id> [--dry-run] [--abandon-unstarted] — take a spec out of the
# project: unlink its open tasks in this checkout, optionally abandon the ones
# never started, and move the spec directory to trash.
#
# Tasks are found through their own `Spec:` lines, not the roadmap: the
# roadmap is shared and may not name a task filed here, while workspaces are
# local. Roadmap ids with no workspace here are reported, never guessed at.
# Workspace links are skipped, as housekeeping skips them: a workspace belongs
# to the checkout that filed it (ADR-0029).
#
# Abandoning goes through the dispatcher, `"$JIG_SELF" task abandon`, so a task
# `state` is still written by `jig task` alone. A started task is never
# abandoned: its branch may hold work.
spec_remove() {
  local sid="" dry=0 abandon=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1; shift ;;
      --abandon-unstarted) abandon=1; shift ;;
      -*) jig_die "spec remove: unknown argument: $1" ;;
      *)
        [ -z "$sid" ] || jig_die "spec remove: unexpected argument: $1"
        sid="$1"
        shift
        ;;
    esac
  done
  [ -n "$sid" ] || jig_die "spec remove: missing spec id (usage: jig spec remove <id> [--dry-run] [--abandon-unstarted])"
  spec_valid_id "$sid" || jig_die "spec remove: invalid spec id: $sid"
  jig_require_init

  local root dir expect real
  root=$(spec_dir)
  dir="$root/$sid"
  [ -d "$dir" ] || jig_die "spec remove: no such spec: $JIG_AI_DIR/specs/$sid"
  expect=$(cd "$root" && pwd -P) || jig_die "spec remove: cannot resolve $JIG_AI_DIR/specs"
  real=$(cd "$dir" && pwd -P) || jig_die "spec remove: cannot resolve $JIG_AI_DIR/specs/$sid"
  case "$real" in
    "$expect"/*) ;;
    *) jig_die "spec remove: refusing to move a path outside $JIG_AI_DIR/specs: $real" ;;
  esac

  # Collect every decision before changing anything.
  local tasks_root d tid link lrc st branch base plan="" local_ids=""
  tasks_root="$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"
  for d in "$tasks_root"/*/; do
    d=${d%/}
    [ -d "$d" ] || continue
    [ ! -L "$d" ] || continue
    tid=${d##*/}
    jig_valid_id "$tid" || continue
    local_ids="$local_ids $tid "
    [ -f "$d/task.md" ] || continue
    lrc=0
    link=$(jig_spec_link "$d/task.md") || lrc=$?
    if [ "$lrc" != 0 ]; then
      # A task that links to two specs cannot be unlinked by guessing which
      # line is meant; it is left alone and named when one of them is this
      # spec.
      if spec_links_to "$d/task.md" "$sid"; then
        plan="${plan}conflict $tid
"
      fi
      continue
    fi
    [ "$link" = "$sid" ] || continue
    st=$(spec_task_state "$d" status)
    case "$st" in
      consolidated | abandoned)
        plan="${plan}keep $tid $st
"
        continue
        ;;
    esac
    # Abandon comes before unlink: the `Spec:` line is what finds the task, so
    # removing it first would make a failed abandon impossible to retry — the
    # rerun would no longer see the task at all. An abandoned task that still
    # links is closed, and closed tasks keep their line.
    if [ "$abandon" = 1 ]; then
      branch=$(spec_task_state "$d" branch)
      base=$(spec_task_state "$d" base_commit)
      if [ -z "$branch" ] || [ -z "$base" ]; then
        plan="${plan}abandon $tid
"
      fi
    fi
    plan="${plan}unlink $tid
"
  done
  if [ -f "$dir/roadmap.md" ]; then
    while IFS= read -r tid; do
      [ -n "$tid" ] || continue
      case "$local_ids" in
        *" $tid "*) ;;
        *) plan="${plan}elsewhere $tid
" ;;
      esac
    done < <(spec_roadmap_ids "$dir/roadmap.md")
  fi

  local dest rel_dest action rest
  dest=$(jig_trash_dest "spec-$sid")
  rel_dest=${dest#"$JIG_PROJECT"/}

  while IFS=' ' read -r action tid rest; do
    [ -n "$action" ] || continue
    case "$action" in
      unlink)
        if [ "$dry" = 1 ]; then
          printf 'would-unlink   %s\n' "$tid"
          continue
        fi
        spec_unlink_task "$tasks_root/$tid/task.md" "$sid" \
          || jig_die "spec remove: could not unlink $tid; nothing else was changed after it"
        printf 'unlinked       %s\n' "$tid"
        ;;
      abandon)
        if [ "$dry" = 1 ]; then
          printf 'would-abandon  %s (not started)\n' "$tid"
          continue
        fi
        "$JIG_SELF" task abandon "$tid" >/dev/null \
          || jig_die "spec remove: could not abandon $tid; the spec was not moved"
        printf 'abandoned      %s (not started)\n' "$tid"
        ;;
      keep) printf 'kept           %s (%s)\n' "$tid" "$rest" ;;
      conflict) printf 'kept           %s (links to more than one spec)\n' "$tid" ;;
      elsewhere) printf 'not-here       %s (named in the roadmap, no workspace in this checkout)\n' "$tid" ;;
    esac
  done < <(printf '%s' "$plan")

  if [ "$dry" = 1 ]; then
    printf 'would-move     %s/specs/%s -> %s\n' "$JIG_AI_DIR" "$sid" "$rel_dest"
    return 0
  fi
  mkdir -p "${dest%/*}" || jig_die "spec remove: cannot create ${rel_dest%/*}"
  mv "$dir" "$dest" || jig_die "spec remove: could not move $JIG_AI_DIR/specs/$sid to $rel_dest"
  printf 'moved          %s/specs/%s -> %s\n' "$JIG_AI_DIR" "$sid" "$rel_dest"
}

# spec_links_to <task.md> <spec-id> — whether any `Spec:` line names exactly
# <spec-id>. The id is compared as a string: `.` is legal in an id, and as a
# pattern it would match `a.b` against `axb`.
spec_links_to() {
  awk -v sid="$2" '
    /^Spec: \.ai\/specs\// {
      id = $0
      sub(/^Spec: \.ai\/specs\//, "", id)
      sub(/\/.*$/, "", id)
      if (id == sid) { found = 1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# spec_unlink_task <task.md> <spec-id> — drop the task's `Spec:` lines that
# link to <spec-id>, and nothing else. Written atomically.
spec_unlink_task() {
  local file="$1" sid="$2" tmp
  tmp="$file.tmp.$$"
  if ! awk -v sid="$sid" '
    /^Spec: \.ai\/specs\// {
      id = $0
      sub(/^Spec: \.ai\/specs\//, "", id)
      sub(/\/.*$/, "", id)
      if (id == sid) next
    }
    { print }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$file"
}
