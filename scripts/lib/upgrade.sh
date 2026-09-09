# cmd_upgrade — update framework-owned files from a source checkout without
# touching files the user changed (SPEC §32 decision table, ADR-0003).
# Sourced by scripts/jig; defines cmd_upgrade.
# shellcheck shell=bash

# Unconditional report output (one line per non-trivial action, copy or link
# mode alike), suppressed only by this command's own --quiet flag.
# Deliberately NOT jig_log/JIG_QUIET, see scripts/lib/init.sh's _init_out for
# why. Relies on bash's dynamic scope: `quiet` is cmd_upgrade's local
# variable, seen by every helper it calls (directly or transitively).
_upgrade_out() { [ "${quiet:-0}" = 1 ] || printf '%s\n' "$*"; }

# --- staging: build the tree the source would install right now -----------

# _upgrade_build_staged <source> <stage> <profiles> <adapters>
# Populates <stage> with exactly the framework-owned files the given source
# checkout would install for the given active profiles/adapters, mirroring
# the manifest path layout (.ai/scripts/**, .ai/profiles/<p>/**,
# <skills_dir>/<skill>/**). Not conflict-aware: plain overwrite into a
# scratch directory, so it is safe to always rebuild from scratch.
_upgrade_build_staged() {
  local source="$1" stage="$2" profiles="$3" adapters="$4" f p a skill_dir
  local src_pdir stage_pdir adir
  mkdir -p "$stage/.ai/scripts" "$stage/.ai/profiles" "$stage/.ai/templates/knowledge"

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    mkdir -p "$(dirname "$stage/.ai/scripts/$f")"
    cp -p "$source/scripts/$f" "$stage/.ai/scripts/$f"
  done < <(cd "$source/scripts" && find . -type f | sed 's|^\./||')

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    mkdir -p "$(dirname "$stage/.ai/templates/knowledge/$f")"
    cp -p "$source/templates/knowledge/$f" "$stage/.ai/templates/knowledge/$f"
  done < <(cd "$source/templates/knowledge" && find . -type f | sed 's|^\./||')

  for p in $profiles; do
    src_pdir=$(profiles_dir "$source/profiles" "$p")
    [ -d "$src_pdir" ] || continue
    stage_pdir=$(profiles_dir "$stage/.ai/profiles" "$p")
    mkdir -p "$stage_pdir"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      mkdir -p "$(dirname "$stage_pdir/$f")"
      cp -p "$src_pdir/$f" "$stage_pdir/$f"
    done < <(cd "$src_pdir" && find . -type f | sed 's|^\./||')
  done

  for a in $adapters; do
    adir=$(adapters_dir "$source/adapters" "$a")
    [ -f "$adir/adapter.sh" ] || continue
    for skill_dir in "$source"/skills/*/; do
      [ -d "$skill_dir" ] || continue
      skill_dir="${skill_dir%/}"
      "adapter_${a}_install_skill" "$skill_dir" "$stage" > /dev/null
    done
  done
}

# --- shared helpers (both modes) --------------------------------------------

# _upgrade_source_version <source> — the framework version a source checkout
# declares in scripts/lib/version.sh, falling back to the running
# dispatcher's own $JIG_VERSION when it cannot be read. Mirrors init.sh's
# _init_source_version.
_upgrade_source_version() {
  local version
  version=$(sed -n 's/^JIG_VERSION="\(.*\)"/\1/p' "$1/scripts/lib/version.sh" | head -n 1)
  [ -n "$version" ] || version="$JIG_VERSION"
  printf '%s\n' "$version"
}

# _upgrade_csv <words> — space-separated words joined as "a, b, c" for the
# manifest's `adapters: [...]` header line.
_upgrade_csv() {
  local w out=""
  for w in $1; do
    if [ -z "$out" ]; then out="$w"; else out="$out, $w"; fi
  done
  printf '%s\n' "$out"
}

# --- decision table (SPEC §32) ---------------------------------------------

# _upgrade_process_path <rel> <stage-dir> <dry-run>
# Applies one row of the upgrade decision table to a single framework-owned
# path and appends the resulting manifest line ("<hash> <path>") to the
# caller's `new_entries` variable (dynamic scope; cmd_upgrade declares it
# local). Prints one report line per non-trivial action.
_upgrade_process_path() {
  local rel="$1" stage="$2" dry_run="$3"
  local staged_abs="$stage/$rel" staged_exists local_abs local_exists
  local local_hash manifest_hash in_manifest action staged_hash

  if [ -f "$staged_abs" ]; then staged_exists=1; else staged_exists=0; fi
  manifest_hash=$(manifest_hash_of "$rel")
  if [ -n "$manifest_hash" ]; then in_manifest=1; else in_manifest=0; fi
  local_abs="$JIG_PROJECT/$rel"
  if [ -f "$local_abs" ]; then
    local_exists=1
    local_hash=$(jig_hash "$local_abs")
  else
    local_exists=0
    local_hash=""
  fi

  if [ "$staged_exists" = 1 ] && [ "$in_manifest" = 1 ]; then
    if [ "$local_exists" = 0 ]; then
      action=install # tracked but missing locally: reinstall
    elif [ "$local_hash" = "$manifest_hash" ]; then
      action=replace
    else
      action=keep-modified
    fi
  elif [ "$staged_exists" = 1 ] && [ "$in_manifest" = 0 ]; then
    if [ "$local_exists" = 0 ]; then
      action=install
    else
      action=keep-conflict
    fi
  elif [ "$staged_exists" = 0 ] && [ "$in_manifest" = 1 ]; then
    if [ "$local_exists" = 0 ] || [ "$local_hash" = "$manifest_hash" ]; then
      action=delete
    else
      action=keep-orphaned-modified
    fi
  else
    return 0 # not in new version and not tracked: not in the union, unreachable
  fi

  case "$action" in
    replace)
      staged_hash=$(jig_hash "$staged_abs")
      if [ "$staged_hash" != "$local_hash" ]; then
        if [ "$dry_run" != 1 ]; then
          mkdir -p "$(dirname "$local_abs")"
          cp -p "$staged_abs" "$local_abs"
        fi
        _upgrade_out "replace $rel"
      fi
      new_entries="$new_entries
$staged_hash $rel"
      ;;
    install)
      staged_hash=$(jig_hash "$staged_abs")
      if [ "$dry_run" != 1 ]; then
        mkdir -p "$(dirname "$local_abs")"
        cp -p "$staged_abs" "$local_abs"
      fi
      _upgrade_out "install $rel"
      new_entries="$new_entries
$staged_hash $rel"
      ;;
    keep-modified)
      _upgrade_out "keep-modified $rel"
      new_entries="$new_entries
$manifest_hash $rel"
      ;;
    keep-conflict)
      _upgrade_out "keep-conflict $rel"
      ;;
    keep-orphaned-modified)
      _upgrade_out "keep-orphaned-modified $rel"
      new_entries="$new_entries
$manifest_hash $rel"
      ;;
    delete)
      if [ "$dry_run" != 1 ]; then
        rm -f "$local_abs"
      fi
      _upgrade_out "delete $rel"
      ;;
  esac
}

# --- link mode ---------------------------------------------------------------

# _upgrade_link_one <target-abs> <link-abs> <dry-run>
# Places one relative symlink through init.sh's _init_place_symlink
# (dynamic scope: kept_count/created_count/conflict_count/conflict_paths are
# _upgrade_link's locals — same pattern _upgrade_process_path uses for
# new_entries) and reports the outcome, one line per non-trivial action,
# the same way the copy-mode decision table does.
_upgrade_link_one() {
  local target_abs="$1" link_abs="$2" dry_run="$3" rel before_created before_conflict
  rel=$(jig_relpath "$link_abs" "$JIG_PROJECT")
  before_created=$created_count
  before_conflict=$conflict_count
  _init_place_symlink "$target_abs" "$link_abs" "$dry_run"
  if [ "$created_count" != "$before_created" ]; then
    _upgrade_out "link $rel"
  elif [ "$conflict_count" != "$before_conflict" ]; then
    _upgrade_out "keep-conflict $rel"
  fi
}

# _upgrade_link <source> <active-profiles> <active-adapters> <dry-run>
# Link mode's "upgrade": rather than the no-op it used to be, ensure every
# framework-owned item for the *current* config is linked — .ai/scripts,
# each active profile, each active adapter's skills — exactly the way
# `jig init --link` places them (SPEC §32). Sources init.sh for
# _init_place_symlink/_init_relpath so the two relative-symlink code paths
# never diverge; sourcing a command library only defines its functions, it
# does not run cmd_init.
_upgrade_link() {
  local source="$1" active_profiles="$2" active_adapters="$3" dry_run="$4"
  # shellcheck source=lib/init.sh
  . "$JIG_LIB/init.sh"

  # conflict_paths is required by _init_place_symlink's dynamic-scope
  # contract (it appends to it unconditionally) even though this caller
  # never reads the list back — _upgrade_link_one already reports each
  # conflict immediately, one line per path, as it happens.
  # shellcheck disable=SC2034
  local created_count=0 kept_count=0 conflict_count=0 conflict_paths=""
  local p a skill_dir sname sdir pdir adir dest_pdir

  _upgrade_link_one "$(cd "$source/scripts" && pwd)" "$JIG_PROJECT/.ai/scripts" "$dry_run"
  _upgrade_link_one "$(cd "$source/templates/knowledge" && pwd)" \
    "$JIG_PROJECT/.ai/templates/knowledge" "$dry_run"

  for p in $active_profiles; do
    pdir=$(profiles_dir "$source/profiles" "$p")
    [ -d "$pdir" ] || continue
    dest_pdir=$(profiles_dir "$JIG_PROJECT/.ai/profiles" "$p")
    _upgrade_link_one "$(cd "$pdir" && pwd)" "$dest_pdir" "$dry_run"
  done

  for a in $active_adapters; do
    adir=$(adapters_dir "$source/adapters" "$a")
    [ -f "$adir/adapter.sh" ] || continue
    sdir=$("adapter_${a}_skills_dir")
    for skill_dir in "$source"/skills/*/; do
      [ -d "$skill_dir" ] || continue
      skill_dir="${skill_dir%/}"
      sname=$(basename "$skill_dir")
      _upgrade_link_one "$skill_dir" "$JIG_PROJECT/$sdir/$sname" "$dry_run"
    done
  done

  if [ "$created_count" = 0 ] && [ "$conflict_count" = 0 ]; then
    _upgrade_out "link mode: nothing to link ($kept_count already linked)"
  fi

  if [ "$dry_run" != 1 ]; then
    local version adapters_manifest
    version=$(_upgrade_source_version "$source")
    adapters_manifest=$(_upgrade_csv "$active_adapters")
    manifest_write "$version" "$source" "$adapters_manifest" "link"
  fi
}

# --- cmd_upgrade -------------------------------------------------------------

# Staging directory / union-of-paths temp file for the current cmd_upgrade
# run. Script-global (not `local`) so the EXIT/INT/TERM cleanup trap below
# still sees them if the process dies mid-run — same pattern as
# scripts/lib/knowledge.sh's KM_*_FILE variables.
_UPGRADE_STAGE=""
_UPGRADE_UNION_FILE=""

cmd_upgrade() {
  local from="" dry_run=0 quiet=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) [ $# -ge 2 ] || jig_die "upgrade: --from requires a value"; from="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --quiet) quiet=1; shift ;;
      *) jig_die "upgrade: unknown argument: $1" ;;
    esac
  done
  jig_require_init
  # shellcheck source=lib/manifest.sh
  . "$JIG_LIB/manifest.sh"
  # shellcheck source=lib/profiles.sh
  . "$JIG_LIB/profiles.sh"

  trap '[ -n "$_UPGRADE_STAGE" ] && rm -rf "$_UPGRADE_STAGE"
        [ -n "$_UPGRADE_UNION_FILE" ] && rm -f "$_UPGRADE_UNION_FILE"' EXIT INT TERM

  local source
  if [ -n "$from" ]; then
    [ -d "$from" ] || jig_die "upgrade: --from directory does not exist: $from"
    source=$(cd "$from" && pwd)
  else
    source=$(jig_source_root)
    [ -n "$source" ] || source=$(manifest_source)
  fi
  [ -n "$source" ] && [ -d "$source" ] \
    || jig_die "upgrade: cannot determine the framework source root; pass --from <dir>"
  jig_is_source_root "$source" \
    || jig_die "upgrade: not a framework source root (missing skills/, templates/ or scripts/jig): $source"

  # Source every adapter known to the source checkout (not just the ones
  # active in config) so manifest paths owned by a since-deactivated adapter
  # are still recognised as framework-owned and can be deleted.
  local adapter_dir a
  for adapter_dir in "$source"/adapters/*/; do
    [ -d "$adapter_dir" ] || continue
    [ -f "$adapter_dir/adapter.sh" ] || continue
    # shellcheck disable=SC1090,SC1091
    . "$adapter_dir/adapter.sh"
  done

  local active_profiles active_adapters
  active_profiles=$(cfg_list profiles generic)
  active_adapters=$(cfg_list adapters "claude codex")

  local mode
  mode=$(manifest_header_get jig.mode)
  if [ "$mode" = "link" ]; then
    _upgrade_link "$source" "$active_profiles" "$active_adapters" "$dry_run"
    return 0
  fi

  _UPGRADE_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/jig-upgrade-stage.XXXXXX")
  _upgrade_build_staged "$source" "$_UPGRADE_STAGE" "$active_profiles" "$active_adapters"

  _UPGRADE_UNION_FILE=$(mktemp "${TMPDIR:-/tmp}/jig-upgrade-union.XXXXXX")
  { (cd "$_UPGRADE_STAGE" && find . -type f | sed 's|^\./||'); manifest_paths; } | sort -u > "$_UPGRADE_UNION_FILE"

  local new_entries="" rel
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    _upgrade_process_path "$rel" "$_UPGRADE_STAGE" "$dry_run"
  done < "$_UPGRADE_UNION_FILE"
  rm -f "$_UPGRADE_UNION_FILE"
  _UPGRADE_UNION_FILE=""
  rm -rf "$_UPGRADE_STAGE"
  _UPGRADE_STAGE=""

  if [ "$dry_run" != 1 ]; then
    local version adapters_manifest
    version=$(_upgrade_source_version "$source")
    adapters_manifest=$(_upgrade_csv "$active_adapters")
    printf '%s\n' "$new_entries" | sed '/^$/d' \
      | manifest_write_entries "$version" "$source" "$adapters_manifest" "copy"
  fi
}
