# cmd_status — version, init/manifest state, drift, active tasks,
# housekeeping age (SPEC §29). Sourced by scripts/jig; defines cmd_status.
# Read-only: never writes anything.
# shellcheck shell=bash

cmd_status() {
  jig_require_repo
  # shellcheck source=lib/manifest.sh
  . "$JIG_LIB/manifest.sh"

  printf '%s\n' "jig $JIG_VERSION"

  if [ ! -f "$JIG_PROJECT/$JIG_AI_DIR/config.yaml" ]; then
    printf '%s\n' "initialised: no"
    printf '%s\n' "hint: run \`jig init\` to bootstrap this project"
    return 0
  fi
  printf '%s\n' "initialised: yes"

  if manifest_exists; then
    printf '%s\n' "manifest: version=$(manifest_header_get jig.version) mode=$(manifest_header_get jig.mode) source=$(manifest_source)"
  else
    printf '%s\n' "manifest: missing"
  fi

  local modified="" missing="" mcount=0 xcount=0 rel mhash lhash
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    mhash=$(manifest_hash_of "$rel")
    if [ -f "$JIG_PROJECT/$rel" ]; then
      lhash=$(jig_hash "$JIG_PROJECT/$rel")
      if [ "$lhash" != "$mhash" ]; then
        modified="$modified
$rel"
        mcount=$((mcount + 1))
      fi
    else
      missing="$missing
$rel"
      xcount=$((xcount + 1))
    fi
  done < <(manifest_paths)

  printf '%s\n' "drift: $mcount modified, $xcount missing"
  if [ "$mcount" -gt 0 ]; then
    printf '%s\n' "modified:"
    printf '%s\n' "$modified" | sed '/^$/d; s/^/  /'
  fi
  if [ "$xcount" -gt 0 ]; then
    printf '%s\n' "missing:"
    printf '%s\n' "$missing" | sed '/^$/d; s/^/  /'
  fi

  local found=0 finished=0 state_file tid class st paused reason line
  for state_file in "$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"/*/state; do
    [ -f "$state_file" ] || continue
    tid=$(sed -n 's/^task_id:[[:space:]]*//p' "$state_file" | head -n 1)
    class=$(sed -n 's/^class:[[:space:]]*//p' "$state_file" | head -n 1)
    st=$(sed -n 's/^status:[[:space:]]*//p' "$state_file" | head -n 1)
    # Finished work is counted, not listed: on a long-lived branch it would
    # otherwise crowd out the tasks actually in flight (same rule as
    # `jig task list`, see _task_is_live).
    case "$st" in
      active | ready) ;;
      *) finished=$((finished + 1)); continue ;;
    esac
    found=1
    paused=$(sed -n 's/^paused:[[:space:]]*//p' "$state_file" | head -n 1)
    line="task $tid class=$class status=$st"
    if [ "$paused" = "true" ]; then
      reason=$(sed -n 's/^paused_reason:[[:space:]]*//p' "$state_file" | head -n 1)
      if [ -n "$reason" ]; then
        line="$line paused ($reason)"
      else
        line="$line paused"
      fi
    fi
    printf '%s\n' "$line"
  done
  [ "$found" = 1 ] || printf '%s\n' "no active tasks"
  [ "$finished" -gt 0 ] && printf '(%d finished; jig task list --all)\n' "$finished"

  # Current task: the workspace whose branch matches the checkout (ADR-0008).
  # Three outcomes (design.md §2): exactly one candidate prints its id, none
  # prints "none", several print "ambiguous (a, b)" built from task_current's
  # own stderr (one line per candidate, id is the first field) rather than
  # re-deriving the candidate list here.
  # shellcheck source=lib/task.sh
  . "$JIG_LIB/task.sh"
  local current cur_rc=0 cur_err_file ids
  cur_err_file=$(mktemp "${TMPDIR:-/tmp}/jig-status-current.XXXXXX")
  current=$(task_current 2>"$cur_err_file") || cur_rc=$?
  case "$cur_rc" in
    0)
      printf 'current task: %s\n' "$current"
      ;;
    2)
      ids=$(awk '{ if (NR > 1) printf ", "; printf "%s", $1 }' "$cur_err_file")
      printf 'current task: ambiguous (%s)\n' "$ids"
      ;;
    *)
      printf 'current task: none\n'
      ;;
  esac
  rm -f "$cur_err_file"

  local hk_file="$JIG_PROJECT/$JIG_AI_DIR/runtime/last-housekeeping"
  if [ -f "$hk_file" ]; then
    printf '%s\n' "housekeeping: $(jig_file_age_days "$hk_file") days ago"
  else
    printf '%s\n' "housekeeping: never"
  fi
}
