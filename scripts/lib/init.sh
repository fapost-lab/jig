# cmd_init — idempotent project bootstrap (domains/install, ADR-0003).
# Sourced by scripts/jig; defines cmd_init. Never overwrites an existing
# file (RULES.md invariant); safe to run more than once.
# shellcheck shell=bash

# --- small local helpers (init-only; not part of the public library surface) -

# Unconditional report output for cmd_init's own summary (created/kept/
# conflict counts), suppressed only by this command's own --quiet flag.
# Deliberately NOT jig_log/JIG_QUIET: this is the command's primary output,
# not optional verbosity, and JIG_QUIET may already be set process-wide
# (e.g. by the test runner) independently of whether --quiet was passed here.
# Relies on bash's dynamic scope: `quiet` is cmd_init's local variable.
_init_out() { [ "${quiet:-0}" = 1 ] || printf '%s\n' "$*"; }

# Space-separated words, comma/whitespace separated input, dedup, order kept.
_init_dedup_words() {
  local w result=""
  for w in $1; do
    case " $result " in
      *" $w "*) ;;
      *) result="$result $w" ;;
    esac
  done
  printf '%s\n' "${result# }"
}

_init_csv_words() {
  printf '%s' "$1" | tr ',' ' ' | tr -s '[:space:]' ' '
}

_init_words_to_csv() {
  local w out=""
  for w in $1; do
    if [ -z "$out" ]; then out="$w"; else out="$out, $w"; fi
  done
  printf '%s\n' "$out"
}

# Rewrite the `<key>: [...]` line of an existing, project-owned
# .ai/config.yaml in place (atomic tmp+mv, per shell conventions). Used only
# when an explicit --profiles/--adapters flag disagrees with what the config
# already says (domains/install: init takes profiles/adapters from the config
# on a flag-less re-run, but an explicit flag still wins and updates the
# config).
# Every other line, including comments, is left untouched.
_init_update_config_list() {
  local file="$1" key="$2" words="$3" bracket tmp
  bracket="[$(_init_words_to_csv "$words")]"
  tmp="$file.tmp.$$"
  sed "s/^${key}:.*/${key}: ${bracket}/" "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Relative path from directory <from> to path <to> (both absolute, no
# trailing slash required). Pure string computation, no filesystem access,
# so it also works for symlink targets that do not exist yet.
_init_relpath() {
  awk -v from="$1" -v to="$2" '
    BEGIN {
      n1 = split(from, a, "/")
      n2 = split(to, b, "/")
      i = 1
      while (i <= n1 && i <= n2 && a[i] == b[i]) i++
      up = ""
      for (j = i; j <= n1; j++) if (a[j] != "") up = up "../"
      down = ""
      for (j = i; j <= n2; j++) if (b[j] != "") down = down b[j] "/"
      result = up down
      sub(/\/$/, "", result)
      if (result == "") result = "."
      print result
    }
  '
}

# The framework version of a source checkout, read from its own
# version.sh rather than trusting the running dispatcher's $JIG_VERSION
# (which may belong to a different checkout than --from).
_init_source_version() {
  sed -n 's/^JIG_VERSION="\(.*\)"/\1/p' "$1/scripts/lib/version.sh" | head -n 1
}

# Ensure the directory that will hold <file-path> exists, cheaply.
#
# Takes the file path rather than its directory so the caller needs no
# `$(dirname ...)`: a command substitution forks even when it runs a shell
# function, and this is called once per installed file. The directory is cut
# with parameter expansion, and `mkdir -p` runs only when it differs from the
# previous call's — placement walks a depth-first `find` listing, so files of
# one directory arrive together and nearly every repeat collapses.
#
# An install places ~72 files and a spawn costs ~3 ms here, so this is a
# measurable share of `jig init`, not a micro-optimisation.
#
# The memo assumes nothing removes a destination directory during a run.
# Nothing does today; a future step that prunes stale directories would have
# to reset _INIT_LAST_DIR, or this silently skips the mkdir the next write
# needs.
_INIT_LAST_DIR=""
_init_mkdir_for() {
  local dir
  case "$1" in
    */*) dir="${1%/*}" ;;
    *) return 0 ;;
  esac
  if [ "$dir" != "$_INIT_LAST_DIR" ]; then
    mkdir -p "$dir"
    _INIT_LAST_DIR="$dir"
  fi
}

# Place a project-owned file (config.yaml, knowledge templates, AGENTS.md)
# only if it does not already exist. Never compares content: these files are
# owned by the project after creation (domains/install) and are never touched
# again by init or upgrade.
_init_place_if_absent() {
  local src="$1" dest="$2"
  if [ -f "$dest" ]; then
    kept_count=$((kept_count + 1))
  else
    _init_mkdir_for "$dest"
    cp "$src" "$dest"
    created_count=$((created_count + 1))
  fi
}

# Place a framework-owned file: create if absent, silently keep if the
# existing file is byte-identical to the source, report+keep as a conflict
# otherwise (domains/install: the install/replace/keep-modified/delete decision
# table). Conflicting files are
# intentionally NOT added to framework_paths, so the manifest never claims
# ownership of a file it did not install.
_init_copy_framework_file() {
  local src="$1" dest="$2" rel
  rel=$(jig_relpath "$dest" "$JIG_PROJECT")
  if [ -f "$dest" ]; then
    # `cmp -s` rather than comparing two `jig_hash` calls: the question is
    # "are these bytes identical", which needs no hash, and `git hash-object`
    # costs ~13 ms per call here — two of them per file, on every re-run of
    # `init` over ~72 files.
    if cmp -s "$src" "$dest"; then
      kept_count=$((kept_count + 1))
      framework_paths="$framework_paths
$rel"
    else
      conflict_count=$((conflict_count + 1))
      conflict_paths="$conflict_paths
$rel"
    fi
  else
    _init_mkdir_for "$dest"
    cp -p "$src" "$dest"
    created_count=$((created_count + 1))
    framework_paths="$framework_paths
$rel"
  fi
}

# Copy every file under <src-dir> into <dest-dir>, through the
# conflict-aware placement above.
_init_copy_tree() {
  local src="$1" dest="$2" f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    _init_copy_framework_file "$src/$f" "$dest/$f"
  done < <(cd "$src" && find . -type f | sed 's|^\./||')
}

# Staging directory for one skill install (see _init_install_skill_staged
# below). Script-global (not `local`) so the EXIT/INT/TERM cleanup trap set
# in cmd_init still sees the in-progress path if the process dies mid-copy
# (e.g. jig_die from a conflicting write) — same pattern as
# scripts/lib/knowledge.sh's KM_*_FILE variables. Re-entrant: cmd_init calls
# this helper once per skill per adapter, and each call owns the variable
# only for its own duration, resetting it to empty before returning.
_INIT_STAGE=""

# Scratch directory for the batched manifest hashing (see step 8). Script-
# global for the same reason as _INIT_STAGE: the EXIT trap must still see it.
_INIT_HASH_TMP=""

# Install one skill through one adapter, staged first so the same
# conflict-aware placement helper can be used (adapters only know how to
# write into a project root; they are not conflict-aware themselves).
_init_install_skill_staged() {
  local adapter_name="$1" skill_src="$2" rel
  _INIT_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/jig-init-stage.XXXXXX")
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    _init_copy_framework_file "$_INIT_STAGE/$rel" "$JIG_PROJECT/$rel"
  done < <("adapter_${adapter_name}_install_skill" "$skill_src" "$_INIT_STAGE")
  rm -rf "$_INIT_STAGE"
  _INIT_STAGE=""
}

# Place a relative symlink at <link-abs> pointing at <target-abs>. Idempotent:
# an existing symlink that already resolves to the right relative target is
# kept silently; anything else already at that path is a conflict, never
# overwritten. Optional third argument <dry-run>: when "1", counts/reports
# what would happen but performs no filesystem write (used by `jig upgrade`
# --dry-run in link mode; cmd_init never passes it, so its own calls are
# unaffected). Relies on the caller's dynamic-scope locals kept_count,
# created_count, conflict_count, conflict_paths — same pattern as
# _init_copy_framework_file.
_init_place_symlink() {
  local target_abs="$1" link_abs="$2" dry_run="${3:-0}" rel target_rel current
  rel=$(jig_relpath "$link_abs" "$JIG_PROJECT")
  target_rel=$(_init_relpath "$(dirname "$link_abs")" "$target_abs")
  if [ -L "$link_abs" ]; then
    current=$(readlink "$link_abs")
    if [ "$current" = "$target_rel" ]; then
      kept_count=$((kept_count + 1))
    else
      conflict_count=$((conflict_count + 1))
      conflict_paths="$conflict_paths
$rel"
    fi
  elif [ -e "$link_abs" ]; then
    conflict_count=$((conflict_count + 1))
    conflict_paths="$conflict_paths
$rel"
  else
    if [ "$dry_run" != 1 ]; then
      _init_mkdir_for "$link_abs"
      ln -s "$target_rel" "$link_abs"
    fi
    created_count=$((created_count + 1))
  fi
}

# Extend this run's `framework_paths` (every path this run created or found
# byte-identical to source) with any path the existing manifest already
# tracks that this run did not (re)write but which still exists locally —
# most notably a file init just reported as `conflict` because the user
# modified it (domains/install; ADR-0003: init never overwrites user changes), or a
# file belonging to a profile/adapter no longer selected. Without this, a
# path init did not touch this run would simply be missing from the
# manifest it rewrites (see _init_copy_framework_file: conflicting paths are
# deliberately excluded from framework_paths). A path that no longer exists
# locally and was not reinstalled this run is left out, i.e. dropped.
# Dynamic scope: framework_paths is cmd_init's local, same pattern
# _init_copy_framework_file uses.
_init_merge_manifest_paths() {
  local old_rel
  while IFS= read -r old_rel; do
    [ -z "$old_rel" ] && continue
    printf '%s\n' "$framework_paths" | grep -qxF "$old_rel" && continue
    [ -f "$JIG_PROJECT/$old_rel" ] && framework_paths="$framework_paths
$old_rel"
  done < <(manifest_paths)
}

# --- cmd_init ----------------------------------------------------------------

cmd_init() {
  local from="" link=0 link_given=0 adapters_csv="" profiles_csv="" quiet=0
  local adapters_given=0 profiles_given=0 session_hook=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --from) [ $# -ge 2 ] || jig_die "init: --from requires a value"; from="$2"; shift 2 ;;
      --link) link=1; link_given=1; shift ;;
      --adapters) [ $# -ge 2 ] || jig_die "init: --adapters requires a value"; adapters_csv="$2"; adapters_given=1; shift 2 ;;
      --profiles) [ $# -ge 2 ] || jig_die "init: --profiles requires a value"; profiles_csv="$2"; profiles_given=1; shift 2 ;;
      --quiet) quiet=1; shift ;;
      --session-hook) session_hook=1; shift ;;
      *) jig_die "init: unknown argument: $1" ;;
    esac
  done
  jig_require_repo
  # shellcheck source=lib/manifest.sh
  . "$JIG_LIB/manifest.sh"

  # Cleanup net for _init_install_skill_staged's staging directory: fires on
  # a mid-install jig_die (e.g. a conflicting write) as well as on interrupt.
  trap '[ -n "$_INIT_STAGE" ] && rm -rf "$_INIT_STAGE"; [ -n "$_INIT_HASH_TMP" ] && rm -rf "$_INIT_HASH_TMP"' EXIT INT TERM

  local source
  if [ -n "$from" ]; then
    [ -d "$from" ] || jig_die "init: --from directory does not exist: $from"
    source=$(cd "$from" && pwd)
  else
    source=$(jig_source_root)
  fi
  [ -n "$source" ] || jig_die "init: cannot determine the framework source root; pass --from <dir>"
  jig_is_source_root "$source" \
    || jig_die "init: not a framework source root (missing skills/, templates/ or scripts/jig): $source"

  # On a re-run, mode (copy/link) sticks to whatever the manifest already
  # says unless --link is given explicitly (domains/install: init is idempotent;
  # switching a project between copy and link is an explicit choice, never
  # inferred). A first run (no manifest yet) keeps the flag's default (copy).
  if [ "$link_given" = 0 ] && manifest_exists; then
    if [ "$(manifest_header_get jig.mode)" = "link" ]; then link=1; else link=0; fi
  fi

  # Profiles/adapters: an explicit flag always wins. Otherwise, on a re-run
  # against an existing .ai/config.yaml, take the current selection from the
  # config (domains/install) rather than silently falling back to the flag
  # defaults; cfg_list's own default covers the first-run, no-config case.
  local profiles_words adapters_words
  if [ "$profiles_given" = 1 ]; then
    profiles_words=$(_init_dedup_words "generic $(_init_csv_words "$profiles_csv")")
  else
    profiles_words=$(_init_dedup_words "generic $(cfg_list profiles generic)")
  fi
  if [ "$adapters_given" = 1 ]; then
    adapters_words=$(_init_dedup_words "$(_init_csv_words "$adapters_csv")")
  else
    adapters_words=$(_init_dedup_words "$(cfg_list adapters "claude codex")")
  fi

  # shellcheck source=lib/profiles.sh
  . "$JIG_LIB/profiles.sh"

  # Validate every profile/adapter name — from --profiles/--adapters or
  # from .ai/config.yaml on a flag-less re-run — before any filesystem
  # read or write happens below (RULES.md invariant; mirrors task_dir).
  # Without this, a name is only caught much later at profiles_dir /
  # adapters_dir in the copy/link step (7.), by which point config.yaml
  # and the knowledge templates have already been written; worse, a name
  # containing '/' (e.g. "../x") reaches the config.yaml `sed` below and
  # breaks its `s/.../.../` substitution instead of failing cleanly.
  local pw aw
  for pw in $profiles_words; do
    _profiles_valid_name "$pw" || jig_die "invalid profile name: $pw"
  done
  for aw in $adapters_words; do
    _adapters_valid_name "$aw" || jig_die "invalid adapter name: $aw"
  done

  # Suggest profiles the target project looks like it needs but the
  # selection above does not include (domains/install). Advisory only:
  # never changes what gets installed, so init stays non-interactive and
  # predictable.
  local detected_words suggested_words="" w
  detected_words=$(profiles_detect "$source/profiles")
  for w in $detected_words; do
    case " $profiles_words " in
      *" $w "*) ;;
      *) suggested_words="$suggested_words $w" ;;
    esac
  done
  suggested_words="${suggested_words# }"
  if [ -n "$suggested_words" ]; then
    _init_out "suggested profiles: $suggested_words (run again with --profiles ${suggested_words// /,} or edit .ai/config.yaml)"
  fi

  local created_count=0 kept_count=0 conflict_count=0
  local conflict_paths="" framework_paths=""

  # 2. directories -------------------------------------------------------
  mkdir -p "$JIG_PROJECT/.ai"
  mkdir -p "$JIG_PROJECT/.ai/knowledge/features" \
           "$JIG_PROJECT/.ai/knowledge/conventions" \
           "$JIG_PROJECT/.ai/knowledge/adr"
  local d
  for d in features conventions adr; do
    # Only place .gitkeep when the directory would otherwise be empty (and
    # thus untracked by git); a directory that already has real content
    # (including a re-run where .gitkeep itself was placed before) needs no
    # placeholder.
    if [ -z "$(find "$JIG_PROJECT/.ai/knowledge/$d" -mindepth 1 -print -quit)" ]; then
      : > "$JIG_PROJECT/.ai/knowledge/$d/.gitkeep"
    fi
  done
  mkdir -p "$JIG_PROJECT/.ai/workspace/tasks" "$JIG_PROJECT/.ai/runtime"

  # 3. .ai/config.yaml -----------------------------------------------------
  local cfg_dest="$JIG_PROJECT/.ai/config.yaml"
  if [ -f "$cfg_dest" ]; then
    kept_count=$((kept_count + 1))
    # The config itself is otherwise never touched (domains/install) — this is the
    # one exception: an explicit flag that disagrees with what is already
    # configured updates just that one line, so the flag and the config
    # cannot silently diverge.
    if [ "$profiles_given" = 1 ] \
       && [ "$profiles_words" != "$(_init_dedup_words "generic $(cfg_list profiles generic)")" ]; then
      _init_update_config_list "$cfg_dest" profiles "$profiles_words"
    fi
    if [ "$adapters_given" = 1 ] \
       && [ "$adapters_words" != "$(_init_dedup_words "$(cfg_list adapters "claude codex")")" ]; then
      _init_update_config_list "$cfg_dest" adapters "$adapters_words"
    fi
  else
    local profiles_bracket adapters_bracket tmp_cfg
    profiles_bracket="[$(_init_words_to_csv "$profiles_words")]"
    adapters_bracket="[$(_init_words_to_csv "$adapters_words")]"
    tmp_cfg="$cfg_dest.tmp.$$"
    sed -e "s/^profiles:.*/profiles: $profiles_bracket/" \
        -e "s/^adapters:.*/adapters: $adapters_bracket/" \
        "$source/templates/config.yaml" > "$tmp_cfg"
    mv "$tmp_cfg" "$cfg_dest"
    created_count=$((created_count + 1))
  fi

  # 4. knowledge templates ---------------------------------------------------
  local kf
  for kf in GLOSSARY.md ARCHITECTURE.md RULES.md; do
    _init_place_if_absent "$source/templates/knowledge/$kf" "$JIG_PROJECT/.ai/knowledge/$kf"
  done

  # 5. AGENTS.md + adapter instructions --------------------------------------
  _init_place_if_absent "$source/templates/AGENTS.md" "$JIG_PROJECT/AGENTS.md"

  local a adir
  for a in $adapters_words; do
    adir=$(adapters_dir "$source/adapters" "$a")
    [ -f "$adir/adapter.sh" ] \
      || jig_die "init: unknown adapter '$a' (missing $adir/adapter.sh)"
    # shellcheck disable=SC1090
    . "$adir/adapter.sh"
  done
  for a in $adapters_words; do
    if [ -n "$("adapter_${a}_install_instructions" "$JIG_PROJECT" "$source/templates")" ]; then
      created_count=$((created_count + 1))
    fi
  done

  # 6. .gitignore -------------------------------------------------------------
  local gi_dest="$JIG_PROJECT/.gitignore" gi_line gi_added=0
  [ -f "$gi_dest" ] || : > "$gi_dest"
  while IFS= read -r gi_line; do
    case "$gi_line" in
      ''|'#'*) continue ;;
    esac
    grep -qxF "$gi_line" "$gi_dest" || { printf '%s\n' "$gi_line" >> "$gi_dest"; gi_added=1; }
  done < "$source/templates/gitignore"
  [ "$gi_added" = 1 ] && created_count=$((created_count + 1))

  # 7. framework-owned files: scripts, profiles, skills ----------------------
  local p skill_dir sname sdir pdir dest_pdir
  if [ "$link" = 1 ]; then
    _init_place_symlink "$(cd "$source/scripts" && pwd)" "$JIG_PROJECT/.ai/scripts"
    _init_place_symlink "$(cd "$source/templates/knowledge" && pwd)" \
      "$JIG_PROJECT/.ai/templates/knowledge"
    _init_place_symlink "$(cd "$source/templates/scheduler" && pwd)" \
      "$JIG_PROJECT/.ai/templates/scheduler"
    for p in $profiles_words; do
      pdir=$(profiles_dir "$source/profiles" "$p")
      [ -d "$pdir" ] \
        || jig_die "init: profile '$p' not found in source: $pdir"
      mkdir -p "$JIG_PROJECT/.ai/profiles"
      dest_pdir=$(profiles_dir "$JIG_PROJECT/.ai/profiles" "$p")
      _init_place_symlink "$(cd "$pdir" && pwd)" "$dest_pdir"
    done
    # Link mode points straight at the source skill directories; codex's
    # `/jig-` -> `$jig-` transform is a copy-time rewrite and does not apply
    # here. This is a known limitation of --link:
    # a linked codex skill still reads `/jig-*` in its SKILL.md.
    for skill_dir in "$source"/skills/*/; do
      [ -d "$skill_dir" ] || continue
      skill_dir="${skill_dir%/}"
      sname=$(basename "$skill_dir")
      for a in $adapters_words; do
        sdir=$("adapter_${a}_skills_dir")
        mkdir -p "$JIG_PROJECT/$sdir"
        _init_place_symlink "$skill_dir" "$JIG_PROJECT/$sdir/$sname"
      done
    done
  else
    _init_copy_tree "$source/scripts" "$JIG_PROJECT/.ai/scripts"
    # Document templates are framework-owned: `jig knowledge new` instantiates
    # them, so a project that never sees the framework checkout still has
    # them, and `upgrade` can carry improvements forward. The three global
    # documents are seeded into .ai/knowledge/ instead (step 4) and become
    # project-owned the moment they are written (ADR-0003).
    _init_copy_tree "$source/templates/knowledge" \
      "$JIG_PROJECT/.ai/templates/knowledge"
    # Scheduler examples are framework-owned too: they are copied so a project
    # without the source checkout can still read them, and never activated —
    # the framework does not implement a scheduler (RULES.md, Scope invariants).
    _init_copy_tree "$source/templates/scheduler" \
      "$JIG_PROJECT/.ai/templates/scheduler"
    for p in $profiles_words; do
      pdir=$(profiles_dir "$source/profiles" "$p")
      [ -d "$pdir" ] \
        || jig_die "init: profile '$p' not found in source: $pdir"
      dest_pdir=$(profiles_dir "$JIG_PROJECT/.ai/profiles" "$p")
      _init_copy_tree "$pdir" "$dest_pdir"
    done
    for skill_dir in "$source"/skills/*/; do
      [ -d "$skill_dir" ] || continue
      skill_dir="${skill_dir%/}"
      for a in $adapters_words; do
        _init_install_skill_staged "$a" "$skill_dir"
      done
    done
  fi

  # 8. manifest -----------------------------------------------------------
  local version
  version=$(_init_source_version "$source")
  [ -n "$version" ] || version="$JIG_VERSION"
  local adapters_manifest
  adapters_manifest=$(_init_words_to_csv "$adapters_words")
  if [ "$link" = 1 ]; then
    manifest_write "$version" "$source" "$adapters_manifest" "link"
  else
    # Never drop the manifest entry of a framework-owned path that still
    # exists locally, even if this run did not (re)write it (domains/install).
    _init_merge_manifest_paths

    # A path the manifest already tracked keeps its existing hash unchanged
    # — regardless of whether the local file now matches source or was
    # modified, so a re-run over a user-modified file cannot turn real
    # `modified` drift into a false `conflict`. Only a path with no prior
    # entry (first install, or a path reinstalled after local deletion)
    # gets a freshly computed hash. Uses manifest_write_entries, which
    # writes precomputed hash/path pairs verbatim instead of recomputing
    # them from disk.
    # Paths whose hash the manifest already knows are reused; the rest are
    # hashed in ONE `git hash-object --stdin-paths` call rather than one call
    # per file. On a first install that is every path — ~72 git startups at
    # ~13 ms each, which measured as the single largest cost of `jig init`.
    # Batch output is byte-identical to per-file hashing (verified), and
    # `paste` re-pairs it with the paths in the order they were sent.
    # Absolute paths are built by plain concatenation, never by `sed`: the
    # project root comes from `git rev-parse --show-toplevel`, so it is an
    # arbitrary user path, and an `&` in a sed replacement means "the text
    # that matched". A project under `R&D/` silently lost that segment from
    # every path, and the run then died inside git with a raw error, having
    # already copied the framework in and written a manifest with an empty
    # body — an install no `upgrade` could recognise.
    #
    # Every entry is assembled in a file first and handed to
    # manifest_write_entries only once it is complete, so a failure anywhere
    # in the batch leaves the previous manifest untouched instead of
    # replacing it with a truncated one.
    local rel hash
    _INIT_HASH_TMP=$(mktemp -d "${TMPDIR:-/tmp}/jig-init-hash.XXXXXX")
    local need_file="$_INIT_HASH_TMP/rel" abs_file="$_INIT_HASH_TMP/abs"
    local hash_file="$_INIT_HASH_TMP/hash" entries="$_INIT_HASH_TMP/entries"
    : > "$need_file"; : > "$abs_file"; : > "$entries"

    while IFS= read -r rel; do
      [ -z "$rel" ] && continue
      hash=$(manifest_hash_of "$rel")
      if [ -n "$hash" ]; then
        printf '%s %s\n' "$hash" "$rel" >> "$entries"
      else
        printf '%s\n' "$rel" >> "$need_file"
        printf '%s/%s\n' "$JIG_PROJECT" "$rel" >> "$abs_file"
      fi
    done < <(printf '%s\n' "$framework_paths" | sed '/^$/d' | sort -u)

    if [ -s "$need_file" ]; then
      # One git startup for the whole install instead of one per path.
      # `--stdin-paths` reads one path per line and prints hashes in the same
      # order, so `paste` re-pairs them; a path containing a newline would
      # desync that, which the newline-delimited framework_paths accumulator
      # already rules out.
      git hash-object --stdin-paths < "$abs_file" > "$hash_file" \
        || jig_die "init: could not hash installed files"
      paste -d' ' "$hash_file" "$need_file" >> "$entries"
    fi

    manifest_write_entries "$version" "$source" "$adapters_manifest" "copy" \
      < "$entries"
    rm -rf "$_INIT_HASH_TMP"
    _INIT_HASH_TMP=''
  fi

  # 8a. session hook, on explicit request only --------------------------------
  # Opt-in because the hook starts a background process at every session start,
  # which is more than placing a file. The adapter decides whether it can do it
  # safely and declines with exit 2 otherwise — an existing config file, or a
  # runtime with no session hook at all. The created file is project-owned: it
  # is not recorded in the manifest and `upgrade` never touches it, so removing
  # the hook makes it stay removed (ADR-0024).
  local hook_path hook_rc
  if [ "$session_hook" = 1 ]; then
    for a in $adapters_words; do
      if ! command -v "adapter_${a}_install_session_hook" >/dev/null 2>&1; then
        continue
      fi
      hook_rc=0
      hook_path=$("adapter_${a}_install_session_hook" "$JIG_PROJECT") || hook_rc=$?
      if [ "$hook_rc" = 0 ] && [ -n "$hook_path" ]; then
        created_count=$((created_count + 1))
        _init_out "created $hook_path"
      fi
    done
  fi

  # 8b. scheduling advisory --------------------------------------------------
  # Old spec guidance said init should "offer to configure scheduled
  # housekeeping" (ADR-0024). It advises instead, for the same reason as the
  # suggested profiles above: a prompt would give init its first stdin
  # dependency and break it in CI and in an agent session. Adopting a
  # trigger is the user's action (ADR-0024, RULES.md, Scope invariants).
  local hint hint_rc
  for a in $adapters_words; do
    if ! command -v "adapter_${a}_session_hook_hint" >/dev/null 2>&1; then
      continue
    fi
    hint_rc=0
    # Exit 2 ("this runtime has no session hook") still carries text worth
    # printing once here, unlike in `status` — it tells the reader why they
    # will never see a hook line for that runtime.
    hint=$("adapter_${a}_session_hook_hint" "$JIG_PROJECT") || hint_rc=$?
    if [ "$hint_rc" != 0 ] && [ "$hint_rc" != 2 ]; then
      hint=""
    fi
    if [ -n "$hint" ]; then
      _init_out ""
      if [ "${quiet:-0}" != 1 ]; then
        printf '%s\n' "$hint"
      fi
    fi
  done

  # 9. summary --------------------------------------------------------------
  _init_out ""
  _init_out "jig init: $created_count created, $kept_count kept, $conflict_count conflict(s)"
  if [ "$conflict_count" -gt 0 ]; then
    _init_out "conflicts (kept existing content, did not overwrite):"
    if [ "${quiet:-0}" != 1 ]; then
      printf '%s\n' "$conflict_paths" | sed '/^$/d; s/^/  /'
    fi
  fi
  _init_out "next: run the jig-init skill to populate knowledge; see .ai/scripts/jig status"
}
