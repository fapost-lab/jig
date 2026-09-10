# cmd_status — version, init/manifest state, drift, pending knowledge
# proposals, active tasks, housekeeping age (ARCHITECTURE.md, Scripts layout). Sourced by
# scripts/jig; defines cmd_status.
# Read-only: never writes anything.
# shellcheck shell=bash

cmd_status() {
  jig_require_repo
  # shellcheck source=lib/manifest.sh
  . "$JIG_LIB/manifest.sh"
  # shellcheck source=lib/upgrade.sh
  . "$JIG_LIB/upgrade.sh"
  # shellcheck source=lib/frontmatter.sh
  . "$JIG_LIB/frontmatter.sh"
  # shellcheck source=lib/knowledge.sh
  . "$JIG_LIB/knowledge.sh"

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

  # Pending: framework-owned items `jig upgrade` would install/link right
  # now (e.g. a skill added to the source since the last upgrade) — distinct
  # from drift above, which only covers paths already recorded in the
  # manifest. Omitted from the line entirely (rather than printed as "0
  # pending") when it cannot be determined, most commonly because this
  # install's source checkout no longer exists on this machine (domains/install):
  # that is a different, unknown state from "checked and found nothing
  # pending", and collapsing the two would misreport it as clean.
  local pending pending_rc=0 pcount
  pending=$(upgrade_pending) || pending_rc=$?
  if [ "$pending_rc" = 0 ]; then
    pcount=$(printf '%s\n' "$pending" | grep -c . || true)
    printf '%s\n' "drift: $mcount modified, $xcount missing, $pcount pending"
  else
    printf '%s\n' "drift: $mcount modified, $xcount missing"
  fi
  if [ "$mcount" -gt 0 ]; then
    printf '%s\n' "modified:"
    printf '%s\n' "$modified" | sed '/^$/d; s/^/  /'
  fi
  if [ "$xcount" -gt 0 ]; then
    printf '%s\n' "missing:"
    printf '%s\n' "$missing" | sed '/^$/d; s/^/  /'
  fi

  # Knowledge awaiting a decision. A proposed document is deliberately
  # invisible to every agent until a human accepts it (ADR-0016), and the
  # decision is deliberately allowed to outlive the session that proposed
  # (ADR-0018) — so the only thing that makes it discoverable later is this
  # line. Counted, not listed: `jig knowledge proposed` does the listing.
  local proposals
  proposals=$(km_proposed_count)
  if [ "$proposals" -gt 0 ]; then
    printf 'proposals: %s awaiting decision (jig knowledge proposed)\n' "$proposals"
  else
    printf 'proposals: none\n'
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

  # Tasks the last housekeeping run flagged. Housekeeping exits 3 for these,
  # but nothing keeps that exit code around, and a flag nobody sees is the
  # manual discipline the framework exists to remove (RULES.md, Scope invariants).
  #
  # Counted from the last `--- run` marker onwards, and by distinct task id.
  # Both halves matter: the log is append-only, so scanning all of it reports
  # a task flagged on three consecutive days as three tasks, and keeps
  # reporting one that was consolidated months ago.
  local hk_log="$JIG_PROJECT/$JIG_AI_DIR/runtime/housekeeping.log" nc
  if [ -f "$hk_log" ]; then
    nc=$(awk '
      # split("", seen) clears the array portably; `delete seen` is an
      # extension not every awk on a supported machine has.
      /^--- run /            { split("", seen); n = 0; next }
      /flags=[^ ]*needs-consolidation/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^task=/ && !($i in seen)) { seen[$i] = 1; n++ }
        }
      }
      END { print n + 0 }
    ' "$hk_log")
    if [ "$nc" != "0" ]; then
      printf '%s\n' "needs consolidation: $nc task(s) (see .ai/runtime/housekeeping.log)"
    fi
  fi

  _status_session_hook
}

# Whether the housekeeping trigger is wired up for the installed runtimes.
#
# Each adapter answers for its own runtime (the hint is empty when the trigger
# is in place), so no vendor-specific path or file format appears here —
# ARCHITECTURE.md keeps that knowledge in adapters. Like the `pending` line
# above, the whole line is omitted rather than guessed when the source
# checkout that holds the adapters is gone: "could not check" and "checked and
# found nothing" are different states.
_status_session_hook() {
  local source a adir hint
  source=$(manifest_source 2>/dev/null) || return 0
  [ -n "$source" ] || return 0
  [ -d "$source/adapters" ] || return 0
  # shellcheck source=lib/profiles.sh
  . "$JIG_LIB/profiles.sh"

  local rc
  for a in $(cfg_list adapters "claude codex"); do
    adir=$(adapters_dir "$source/adapters" "$a") || continue
    [ -f "$adir/adapter.sh" ] || continue
    # shellcheck disable=SC1090
    . "$adir/adapter.sh"
    command -v "adapter_${a}_session_hook_hint" >/dev/null 2>&1 || continue
    rc=0
    hint=$("adapter_${a}_session_hook_hint" "$JIG_PROJECT") || rc=$?
    # 2 is the skip code: this runtime has no session hook, so there is
    # nothing for the reader to install and nothing worth a line here.
    [ "$rc" = 2 ] && continue
    if [ -n "$hint" ]; then
      printf 'session hook (%s): not installed\n' "$a"
    else
      printf 'session hook (%s): installed\n' "$a"
    fi
  done
}
