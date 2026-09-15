# cmd_spec — specifications under .ai/specs/<id>/ (the jig-idea skill).
# Sourced by scripts/jig; defines cmd_spec.
#
# A specification is a plan, not knowledge: it lives outside .ai/knowledge/,
# carries no status, and everything reported here is derived from its files —
# the first heading of spec.md and the checkboxes of roadmap.md.
# Read-only: never writes anything.
# shellcheck shell=bash

cmd_spec() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    new) spec_new "$@" ;;
    list) spec_list "$@" ;;
    -h | --help)
      printf '%s\n' "usage: jig spec new <id> | jig spec list" >&2
      return 0
      ;;
    '')
      printf '%s\n' "usage: jig spec new <id> | jig spec list" >&2
      exit 1
      ;;
    *) jig_die "spec: unknown subcommand: $sub (usage: jig spec new <id> | jig spec list)" ;;
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
      state=$(spec_progress "$root/$id/roadmap.md")
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
