# Reader/writer for .ai/manifest (SPEC §6.2, ADR-0003). Sourced by
# scripts/lib/init.sh, scripts/lib/upgrade.sh and scripts/lib/status.sh.
# Assumes JIG_PROJECT and JIG_AI_DIR are already set (jig_require_repo).
# shellcheck shell=bash

# manifest_file
# Absolute path of the manifest for the current project.
manifest_file() {
  printf '%s/%s/manifest\n' "$JIG_PROJECT" "$JIG_AI_DIR"
}

# manifest_exists
manifest_exists() {
  [ -f "$(manifest_file)" ]
}

# manifest_header_get <key>
# Prints the value of a `key: value` header line (the lines above the `---`
# separator), or nothing when absent.
manifest_header_get() {
  local key="$1" file line
  file=$(manifest_file)
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    [ "$line" = "---" ] && break
    case "$line" in
      "$key":*)
        line="${line#*:}"
        # strip at most one leading space, matching the writer's "key: value"
        case "$line" in " "*) line="${line# }" ;; esac
        printf '%s\n' "$line"
        return 0
        ;;
    esac
  done < "$file"
}

# manifest_paths
# Prints every path tracked in the manifest body, one per line.
manifest_paths() {
  local file line in_body=0
  file=$(manifest_file)
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    if [ "$in_body" = 1 ]; then
      [ -n "$line" ] && printf '%s\n' "${line#* }"
    elif [ "$line" = "---" ]; then
      in_body=1
    fi
  done < "$file"
}

# manifest_hash_of <path>
# Prints the manifest hash recorded for <path> (relative to JIG_PROJECT), or
# nothing when the path is not tracked.
manifest_hash_of() {
  local target="$1" file line in_body=0 hash path
  file=$(manifest_file)
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    if [ "$in_body" = 1 ]; then
      [ -z "$line" ] && continue
      hash="${line%% *}"
      path="${line#* }"
      if [ "$path" = "$target" ]; then
        printf '%s\n' "$hash"
        return 0
      fi
    elif [ "$line" = "---" ]; then
      in_body=1
    fi
  done < "$file"
}

# manifest_write_entries <version> <source> <adapters> <mode>
# Internal primitive: reads already-computed "<hash> <path>" lines from
# stdin and writes the whole manifest atomically (temp file + mv). Used by
# manifest_write below and directly by upgrade, which must preserve the
# existing hash of locally modified files instead of recomputing it.
#
# When <source> is the project itself (self-install/dogfooding, typically
# with --link), the absolute path is machine-specific and would break the
# manifest for anyone else who clones the project. Record "." instead;
# manifest_source resolves it back to JIG_PROJECT on read. Compared through
# `pwd -P` (physical paths) rather than as raw strings: JIG_PROJECT comes
# from `git rev-parse --show-toplevel`, which resolves symlinks, while
# <source> may not have been (e.g. a TMPDIR under a symlinked /var on
# macOS) even though both name the same directory.
manifest_write_entries() {
  local version="$1" source="$2" adapters="$3" mode="$4" file tmp
  local source_real project_real
  source_real=$(cd "$source" 2>/dev/null && pwd -P) || source_real="$source"
  project_real=$(cd "$JIG_PROJECT" 2>/dev/null && pwd -P) || project_real="$JIG_PROJECT"
  [ "$source_real" = "$project_real" ] && source="."
  file=$(manifest_file)
  tmp="$file.tmp.$$"
  mkdir -p "$(dirname "$file")"
  {
    # shellcheck disable=SC2016
    printf '# jig manifest. Do not edit by hand; maintained by `jig init` and `jig upgrade`.\n'
    printf 'jig.version: %s\n' "$version"
    printf 'jig.source: %s\n' "$source"
    printf 'jig.mode: %s\n' "$mode"
    printf 'installed_at: %s\n' "$(jig_today)"
    printf 'adapters: [%s]\n' "$adapters"
    printf -- '---\n'
    sort -k2,2
  } > "$tmp"
  mv "$tmp" "$file"
}

# manifest_source
# Prints the manifest's jig.source header, resolving "." (written when the
# project installed itself as its own source) back to JIG_PROJECT.
manifest_source() {
  local src
  src=$(manifest_header_get jig.source)
  if [ "$src" = "." ]; then
    printf '%s\n' "$JIG_PROJECT"
  else
    printf '%s\n' "$src"
  fi
}

# manifest_write <version> <source> <adapters> <mode> [path...]
# Computes the hash of each given path (relative to JIG_PROJECT, hashed as it
# stands on disk right now) and writes the whole manifest atomically. Mode
# "link" is normally called with no paths (header only, no hash lines).
manifest_write() {
  local version="$1" source="$2" adapters="$3" mode="$4"
  shift 4
  local path
  {
    for path in "$@"; do
      printf '%s %s\n' "$(jig_hash "$JIG_PROJECT/$path")" "$path"
    done
  } | manifest_write_entries "$version" "$source" "$adapters" "$mode"
}
