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
  _status_config_local

  if manifest_exists; then
    local proj_version
    proj_version=$(manifest_header_get jig.version)
    printf '%s\n' "manifest: version=$proj_version mode=$(manifest_header_get jig.mode) source=$(manifest_source)"
    _status_framework_versions "$proj_version"
  else
    printf '%s\n' "manifest: missing"
  fi

  # Drift: one pass over the manifest, then one git process for every file
  # still on disk (jig_hash_list). A manifest_hash_of and a jig_hash per path
  # cost 1.5 s on a 72-file install — the manifest reread for every path, and
  # a git startup for every hash. Both lists stay in manifest order.
  local modified="" missing="" mcount=0 xcount=0 line rel mhash lhash drift_tmp
  drift_tmp=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-drift.XXXXXX")
  : > "$drift_tmp/present"
  : > "$drift_tmp/rel"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    mhash=${line%% *}
    rel=${line#* }
    if [ -f "$JIG_PROJECT/$rel" ]; then
      printf '%s %s\n' "$mhash" "$rel" >> "$drift_tmp/present"
      printf '%s\n' "$rel" >> "$drift_tmp/rel"
    else
      missing="$missing
$rel"
      xcount=$((xcount + 1))
    fi
  done < <(manifest_entries)
  jig_hash_list "$JIG_PROJECT" "$drift_tmp/rel" > "$drift_tmp/hashes" \
    || jig_die "status: could not hash the installed files"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    lhash=${line%% *}
    line=${line#* }
    mhash=${line%% *}
    rel=${line#* }
    if [ "$lhash" != "$mhash" ]; then
      modified="$modified
$rel"
      mcount=$((mcount + 1))
    fi
  done < <(paste -d' ' "$drift_tmp/hashes" "$drift_tmp/present")
  rm -rf "$drift_tmp"

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

  # An accepted stub hands agents whatever its source says now. A source edited
  # after acceptance is still read — a merged edit went through the team's own
  # review — but a human has not approved it for agents, and without this line
  # `proposals: none` would be the only thing anyone saw (ADR-0036 as amended).
  local sources_changed
  sources_changed=$(km_changed_sources_count)
  if [ "$sources_changed" -gt 0 ]; then
    printf 'sources changed: %s (jig knowledge sources)\n' "$sources_changed"
  fi

  # Specifications (jig-idea). A spec is a plan outside .ai/knowledge/, so no
  # `jig context` call ever surfaces it; this line is how an agent starting a
  # session learns that one exists. Counted, not listed: `jig spec list` lists.
  # shellcheck source=lib/spec.sh
  . "$JIG_LIB/spec.sh"
  local specs
  specs=$(spec_count)
  if [ "$specs" -gt 0 ]; then
    printf 'specs: %s (jig spec list)\n' "$specs"
    spec_epic_status
  else
    printf 'specs: none\n'
  fi

  # shellcheck source=lib/task.sh
  . "$JIG_LIB/task.sh"
  local found=0 finished=0 state_file tid class st paused reason line branch base_branch default_base worktrees wt
  worktrees=$(_task_worktrees)
  default_base=$(cfg git.base_branch main)
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
    # A task started in its own worktree is still listed here, where it was
    # filed; git says where its branch is checked out (ADR-0029).
    branch=$(sed -n 's/^branch:[[:space:]]*//p' "$state_file" | head -n 1)
    if [ -n "$branch" ]; then
      wt=$(_task_worktree_for "$branch" "$worktrees")
      [ -z "$wt" ] || line="$line $(_task_worktree_note "$wt")"
    fi
    # Same rule as `jig task list`: the base only where it is not the project's.
    base_branch=$(sed -n 's/^base_branch:[[:space:]]*//p' "$state_file" | head -n 1)
    if [ -n "$base_branch" ] && [ "$base_branch" != "$default_base" ]; then
      line="$line base=$base_branch"
    fi
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
  local hk_log="$JIG_PROJECT/$JIG_AI_DIR/runtime/housekeeping.log" nc kept wrong
  if [ -f "$hk_log" ]; then
    nc=$(_status_flagged "$hk_log" needs-consolidation)
    if [ "$nc" != "0" ]; then
      printf '%s\n' "needs consolidation: $nc task(s) (see .ai/runtime/housekeeping.log)"
    fi
    # A finished task whose worktree could not be removed is hidden from the
    # task listing above, so this line is the only place it surfaces. The
    # worktree usually holds work nobody committed (ADR-0029).
    kept=$(_status_flagged "$hk_log" worktree-kept)
    if [ "$kept" != "0" ]; then
      printf '%s\n' "worktrees kept: $kept task(s) (see .ai/runtime/housekeeping.log)"
    fi
    # Work that landed somewhere other than the task's base: kept, and only a
    # person can say where it should have gone (ADR-0039).
    wrong=$(_status_flagged "$hk_log" wrong-base)
    if [ "$wrong" != "0" ]; then
      printf '%s\n' "wrong base: $wrong task(s) (see .ai/runtime/housekeeping.log)"
    fi
  fi

  _status_session_hook
  _status_instructions
}

# _status_framework_versions <project-version> — compares the project's
# installed framework version (from .ai/manifest) against the framework
# version of whatever `jig` the current PATH selects, and prints exactly one
# line, plus a directional hint on mismatch (design.md §3-4).
#
# Read-only and offline, and it runs nothing: the global version is the one
# its checkout declares in scripts/lib/version.sh (jig_declared_version), not
# the output of executing it, so a broken or hanging global checkout cannot
# hang `status` (design.md §3, decided 2026-09-14).
#
# "Unavailable" is never printed with a hint, since there is nothing to act
# on. It covers both a PATH with no framework `jig` and a checkout whose
# version file cannot be read; a CI runner or a colleague who only cloned the
# project has no global install, and a hint there would repeat on every run.
# In link mode the global executable can be the very checkout this dispatcher
# runs from — a normal "current", not a missing global (common.sh,
# jig_global_executable).
_status_framework_versions() {
  local project="$1" global_exe global
  if ! global_exe=$(jig_global_executable) \
     || ! global=$(jig_declared_version "${global_exe%/scripts/jig}"); then
    printf '%s\n' "framework versions: project=$project global=unavailable"
    return 0
  fi
  if [ "$project" = "$global" ]; then
    printf '%s\n' "framework versions: project=$project global=$global current"
    return 0
  fi
  printf '%s\n' "framework versions: project=$project global=$global mismatch"
  if jig_release_version "v$global" >/dev/null 2>&1 && jig_release_version "v$project" >/dev/null 2>&1; then
    if jig_version_newer "$global" "$project"; then
      printf '%s\n' "hint: the global framework is newer; run \`jig upgrade --dry-run\`"
      return 0
    fi
    if jig_version_newer "$project" "$global"; then
      printf '%s\n' "hint: the project is newer than the global framework; run \`jig self-update\`"
      return 0
    fi
  fi
  # Not both orderable as release versions (e.g. a "dev" branch checkout), or
  # some other non-directional disagreement: no basis to name a direction.
  printf '%s\n' "hint: run \`jig self-update\`, then \`jig upgrade --dry-run\`"
}

# _status_flagged <log> <flag> — distinct tasks the last housekeeping run
# flagged with <flag>.
_status_flagged() {
  awk -v flag="$2" '
    # split("", seen) clears the array portably; `delete seen` is an
    # extension not every awk on a supported machine has.
    /^--- run /            { split("", seen); n = 0; next }
    $0 ~ ("flags=[^ ]*" flag) {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^task=/ && !($i in seen)) { seen[$i] = 1; n++ }
      }
    }
    END { print n + 0 }
  ' "$1"
}

# What .ai/config.local.yaml changes, and why a value in it does nothing
# (ADR-0038). Silent when there is no local file anywhere. The answers come
# from config.sh, so this report and cfg cannot disagree about a key.
_status_config_local() {
  local file own key value kind
  file=$(jig_config_local_file)
  own="$JIG_PROJECT/$JIG_AI_DIR/config.local.yaml"
  if [ "$own" != "$file" ] && [ -f "$own" ]; then
    printf 'config.local: ignored %s (a worktree reads %s)\n' "$own" "$file"
  fi
  [ -f "$file" ] || return 0
  while IFS="$(printf '\t')" read -r key value kind; do
    if [ "$kind" = local ]; then
      printf 'config.local: %s=%s\n' "$key" "$value"
    else
      printf 'config.local: ignored %s (not a local key)\n' "$key"
    fi
  done < <(jig_config_local_entries)
  if ! jig_config_local_ignored; then
    printf 'config.local: %s is not ignored by git and can be committed (fix: jig init)\n' \
      "$JIG_AI_DIR/config.local.yaml"
  fi
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

# Whether the instruction file each installed runtime reads carries Jig's
# workflow. A project that had its own AGENTS.md or CLAUDE.md before `init`
# keeps it (ADR-0003), and then the agent never hears of `jig-task`; this line
# is how that stops being silent. The adapter answers (an empty hint means
# connected), for the same reason as the session hook line above, and the line
# is omitted when the source checkout holding the adapters is gone.
_status_instructions() {
  local source a adir hint file
  source=$(manifest_source 2>/dev/null) || return 0
  [ -n "$source" ] || return 0
  [ -d "$source/adapters" ] || return 0
  # shellcheck source=lib/profiles.sh
  . "$JIG_LIB/profiles.sh"

  for a in $(cfg_list adapters "claude codex"); do
    adir=$(adapters_dir "$source/adapters" "$a") || continue
    [ -f "$adir/adapter.sh" ] || continue
    # shellcheck disable=SC1090
    . "$adir/adapter.sh"
    command -v "adapter_${a}_instructions_hint" >/dev/null 2>&1 || continue
    hint=$("adapter_${a}_instructions_hint" "$JIG_PROJECT") || hint=""
    if [ -n "$hint" ]; then
      file=$("adapter_${a}_instructions_file")
      printf 'instructions (%s): no Jig section in %s (run the jig-init skill)\n' "$a" "$file"
    else
      printf 'instructions (%s): ok\n' "$a"
    fi
  done
}
