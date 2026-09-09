# jig knowledge — create, validate and maintain .ai/knowledge
# (schemas/frontmatter.md, ADR-0004, ADR-0010).
# bash 3.2 compatible: no associative arrays, no ${var,,}, no mapfile.
# shellcheck shell=bash

KM_USAGE="usage: jig knowledge check [--quiet]
       jig knowledge new <feature|adr|convention> <slug> [--domains a,b] [--paths g,g]
       jig knowledge new <domain|glossary|rule> <domain> [--paths g,g]
       jig knowledge paths [--task <id>] [--files <list>|-]
       jig knowledge paths add|remove <id> <glob>
       jig knowledge stale [--strict]
       jig knowledge reviewed <id> [--date YYYY-MM-DD]"

# Directory holding the project's knowledge; set once by cmd_knowledge so
# every subcommand and the path builder below agree on the root.
KM_DIR=""

cmd_knowledge() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    check | new | paths | stale | reviewed) ;;
    *) jig_die "$KM_USAGE" ;;
  esac

  jig_require_init
  # shellcheck source=lib/frontmatter.sh
  . "$JIG_LIB/frontmatter.sh"
  KM_DIR="$JIG_PROJECT/$JIG_AI_DIR/knowledge"

  case "$sub" in
    check) km_check "$@" ;;
    new) km_new "$@" ;;
    paths) km_paths "$@" ;;
    stale) km_stale "$@" ;;
    reviewed) km_reviewed "$@" ;;
  esac
}

# --- helpers -----------------------------------------------------------------

# km_glob_matches <glob> — exit 0 when the glob matches at least one path in
# the repository (excluding .git/).
km_glob_matches() {
  local glob="$1" pattern hit
  pattern=$(jig_glob_pattern "$glob")
  hit=$(find "$JIG_PROJECT" -path "$JIG_PROJECT/.git" -prune -o \
    -path "$JIG_PROJECT/$pattern" -print 2>/dev/null | head -n 1)
  [ -n "$hit" ]
}

# km_id_known <id> <ids_file> — exit 0 when <id> is a line in <ids_file>.
km_id_known() {
  [ -s "$2" ] && grep -qxF "$1" "$2"
}

# --- reporting -----------------------------------------------------------------

KM_FAILURES=0
KM_WARNINGS=0
KM_DOCS=0
KM_QUIET=0
KM_LIST_FILE=""
KM_IDS_FILE=""
KM_IDS_ALL_FILE=""
KM_ADR_NUMS_FILE=""
# Held by km_paths_report's EXIT trap, which fires after the function has
# returned — so it must not be `local` (convention-shell).
KM_UNCOVERED_FILE=""

km_fail() {
  KM_FAILURES=$((KM_FAILURES + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
}

km_warn() {
  KM_WARNINGS=$((KM_WARNINGS + 1))
  [ "$KM_QUIET" -eq 1 ] || printf 'WARN %s: %s\n' "$1" "$2"
}

# --- link checking -------------------------------------------------------------

# km_check_links <file> <relpath> — scan the body (after frontmatter) for
# `](relative/path)` targets and fail on any that resolve to a missing path.
km_check_links() {
  local file="$1" relpath="$2" start doc_dir target dir base resolved_dir
  start=$(fm_body_start "$file")
  doc_dir=$(dirname "$file")

  # NOTE: read from process substitution, not a pipe, so the loop body runs
  # in the current shell — a `cmd | while` pipe would run the loop in a
  # subshell and any km_fail counter increments would be lost on exit.
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      http://* | https://* | mailto:* | '#'* | /*) continue ;;
    esac
    target="${target%%#*}"
    [ -n "$target" ] || continue

    dir=$(dirname "$doc_dir/$target")
    base=$(basename "$target")
    resolved_dir=$(cd "$dir" 2>/dev/null && pwd) || resolved_dir=""
    if [ -z "$resolved_dir" ] || [ ! -e "$resolved_dir/$base" ]; then
      km_fail "$relpath" "broken link: $target"
    fi
  done < <(tail -n "+${start}" "$file" | grep -o -E '\]\([^)]+\)' | sed 's/^\](//; s/)$//')
}

# --- per-document checks --------------------------------------------------------

# km_check_doc <file> <relpath> <require_fm> <ids_file> <ids_all_file> <adr_nums_file>
km_check_doc() {
  local file="$1" relpath="$2" require_fm="$3" ids_file="$4" ids_all_file="$5" adr_nums_file="$6"
  local is_global has_fm
  is_global=0
  jig_knowledge_is_global "$file" && is_global=1

  has_fm=1
  fm_has "$file" || has_fm=0

  if [ "$is_global" -eq 0 ]; then
    if [ "$has_fm" -eq 0 ]; then
      if [ "$require_fm" -eq 1 ]; then
        km_fail "$relpath" "missing frontmatter"
      else
        km_warn "$relpath" "missing frontmatter"
      fi
    else
      km_check_doc_frontmatter "$file" "$relpath" "$ids_file" "$ids_all_file" "$adr_nums_file"
    fi
  fi

  km_check_links "$file" "$relpath"
}

# km_check_doc_frontmatter — id/type/status/adr/supersedes/domains/paths checks.
km_check_doc_frontmatter() {
  local file="$1" relpath="$2" ids_file="$3" ids_all_file="$4" adr_nums_file="$5"
  local id type status date supersedes domains paths_out reviewed
  local reldir under_adr base num slug

  id=$(fm_get "$file" id)
  type=$(fm_get "$file" type)
  status=$(fm_get "$file" status)

  case "$id" in
    '' | *[!a-z0-9-]*) km_fail "$relpath" "missing or invalid id" ;;
    *)
      if km_id_known "$id" "$ids_file"; then
        km_fail "$relpath" "duplicate id: $id"
      else
        printf '%s\n' "$id" >> "$ids_file"
      fi
      ;;
  esac

  case "$type" in
    feature | adr | convention | domain | glossary | rule) ;;
    *) km_fail "$relpath" "missing or invalid type" ;;
  esac

  case "$type" in
    feature | convention | domain | glossary | rule)
      case "$status" in
        active | deprecated | superseded) ;;
        *) km_fail "$relpath" "missing or invalid status" ;;
      esac
      ;;
    adr)
      case "$status" in
        accepted | superseded | deprecated | rejected) ;;
        *) km_fail "$relpath" "missing or invalid status" ;;
      esac
      ;;
    *)
      case "$status" in
        active | deprecated | superseded | accepted | rejected) ;;
        *) km_fail "$relpath" "missing or invalid status" ;;
      esac
      ;;
  esac

  # relpath is "<JIG_AI_DIR>/knowledge/<...>"; adr/ is a direct child of
  # .ai/knowledge/, so strip that prefix and check what remains.
  reldir="${relpath#"$JIG_AI_DIR"/knowledge/}"
  case "$reldir" in
    adr/*) under_adr=1 ;;
    *) under_adr=0 ;;
  esac

  if [ "$under_adr" -eq 1 ]; then
    base=$(basename "$file")
    case "$base" in
      [0-9][0-9][0-9][0-9]-*.md)
        num=$(printf '%s' "$base" | cut -c1-4)
        slug=$(printf '%s' "$base" | sed 's/^[0-9]\{4\}-//; s/\.md$//')
        case "$slug" in
          '' | *[!a-z0-9-]*) km_fail "$relpath" "ADR file name must match NNNN-<slug>.md" ;;
          *)
            if km_id_known "$num" "$adr_nums_file"; then
              km_fail "$relpath" "duplicate ADR number: $num"
            else
              printf '%s\n' "$num" >> "$adr_nums_file"
            fi
            ;;
        esac
        ;;
      *) km_fail "$relpath" "ADR file name must match NNNN-<slug>.md" ;;
    esac

    # Only flag a *valid-but-wrong* type here; an already-invalid type was
    # reported once by the type check above and does not need a second
    # (redundant) failure.
    case "$type" in
      feature | convention) km_fail "$relpath" "document under adr/ must have type: adr" ;;
    esac
  fi

  if [ "$type" = "adr" ]; then
    date=$(fm_get "$file" date)
    case "$date" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) km_fail "$relpath" "missing or invalid date" ;;
    esac
  fi

  reviewed=$(fm_get "$file" reviewed_at)
  if [ -n "$reviewed" ]; then
    case "$reviewed" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) km_fail "$relpath" "invalid reviewed_at: $reviewed (expected YYYY-MM-DD)" ;;
    esac
  fi

  supersedes=$(fm_get "$file" supersedes)
  if [ -n "$supersedes" ] && ! km_id_known "$supersedes" "$ids_all_file"; then
    km_fail "$relpath" "supersedes unknown id: $supersedes"
  fi

  domains=$(fm_list "$file" domains)
  paths_out=$(fm_list "$file" paths)
  if [ -z "$domains" ] && [ -z "$paths_out" ]; then
    km_warn "$relpath" "document has neither domains nor paths"
  fi

  if [ -n "$paths_out" ]; then
    # Process substitution, not a pipe: keeps the loop (and km_warn's counter
    # increment) in the current shell instead of a throwaway subshell.
    while IFS= read -r glob; do
      [ -n "$glob" ] || continue
      km_glob_matches "$glob" || km_warn "$relpath" "paths glob matches no file: $glob"
    done < <(printf '%s\n' "$paths_out")
  fi

  km_check_load "$file" "$relpath"
  km_check_topics "$file" "$relpath"
  km_check_domain_placement "$file" "$relpath" "$domains"
}

# km_check_load <file> <relpath> — `load` is optional and defaults to
# `matched`; an unknown value is a failure rather than a silent fallback,
# because falling back would quietly downgrade a document the author meant to
# be always required.
km_check_load() {
  local file="$1" relpath="$2" load
  load=$(fm_get "$file" load)
  [ -n "$load" ] || return 0
  case "$load" in
    always | domain | matched) ;;
    *) km_fail "$relpath" "invalid load: $load (expected always, domain or matched)" ;;
  esac
}

# km_check_topics <file> <relpath> — topics are tags, same shape as domains.
km_check_topics() {
  local file="$1" relpath="$2" topic
  while IFS= read -r topic; do
    [ -n "$topic" ] || continue
    case "$topic" in
      -* | *- | *[!a-z0-9-]*)
        km_fail "$relpath" "invalid topic: $topic (expected [a-z0-9-], no leading or trailing '-')" ;;
    esac
  done < <(fm_list "$file" topics)
}

# km_check_domain_placement <file> <relpath> <domains> — a document filed under
# domains/<d>/ must claim <d> in its `domains` list. The directory is for human
# navigation and never implies applicability (ADR-0004), so the two must agree
# explicitly or the document would be findable by eye and unreachable by
# resolution.
km_check_domain_placement() {
  local file="$1" relpath="$2" domains="$3" prefix rest dir
  prefix="$JIG_AI_DIR/knowledge/domains/"
  case "$relpath" in
    "$prefix"*) rest="${relpath#"$prefix"}" ;;
    *) return 0 ;;
  esac
  dir="${rest%%/*}"
  [ "$dir" = "$rest" ] && return 0
  printf '%s\n' "$domains" | grep -qxF -- "$dir" \
    || km_fail "$relpath" "filed under domains/$dir/ but does not declare domain: $dir"
}

# --- requires graph ------------------------------------------------------------
# Lines of the meta file collected by pass 1:
#   <id><TAB><relpath><TAB><status><TAB><req,req,...>

# km_meta_field <meta-file> <id> <n> — field <n> of the meta line for <id>,
# empty when no document declares that id.
km_meta_field() {
  awk -F '\t' -v want="$2" -v n="$3" '$1 == want { print $n; exit }' "$1"
}

# km_status_is_active <status> — a document that may be pulled in as a
# requirement. `accepted` is the ADR spelling of `active`; deprecated,
# superseded and rejected all mean "do not build on this".
km_status_is_active() {
  case "$1" in
    active | accepted) return 0 ;;
    *) return 1 ;;
  esac
}

# km_check_requires <meta-file> — validate the `requires` graph as a whole:
# every target exists, every target is active, and no cycle exists. No single
# document can check this, because a requirement may be declared anywhere and
# a cycle is a property of the graph.
#
# Cycles are found by topological peel rather than recursion: bash 3.2 has no
# associative arrays, and repeatedly settling the documents whose requirements
# are all settled needs no stack. Whatever cannot be peeled sits on a cycle.
km_check_requires() {
  local meta="$1" t id relpath status reqs req target_status
  [ -s "$meta" ] || return 0
  t=$(printf '\t')

  local settled unsettled next progress all_settled
  settled="${TMPDIR:-/tmp}/jig-knowledge-settled.$$"
  unsettled="${TMPDIR:-/tmp}/jig-knowledge-unsettled.$$"
  next="${TMPDIR:-/tmp}/jig-knowledge-next.$$"
  : > "$settled"
  : > "$unsettled"

  # Existence and lifecycle, one document at a time. The meta file is streamed
  # and queried at once; SC2094 reads that as a read/write overlap, but both
  # accesses are reads (km_meta_field only prints).
  # shellcheck disable=SC2094
  while IFS="$t" read -r id relpath status reqs; do
    [ -n "$id" ] || continue
    if [ -z "$reqs" ]; then
      printf '%s\n' "$id" >> "$settled"
      continue
    fi
    printf '%s%s%s%s%s\n' "$id" "$t" "$relpath" "$t" "$reqs" >> "$unsettled"
    while IFS= read -r req; do
      [ -n "$req" ] || continue
      target_status=$(km_meta_field "$meta" "$req" 3)
      if [ -z "$target_status" ]; then
        km_fail "$relpath" "requires unknown id: $req"
        # Already reported, and unresolvable: settling it keeps the peel below
        # from reporting the same document a second time as a cycle.
        printf '%s\n' "$req" >> "$settled"
      elif ! km_status_is_active "$target_status"; then
        km_fail "$relpath" "requires inactive document: $req (status: $target_status)"
      fi
    done < <(printf '%s\n' "$reqs" | tr ',' '\n')
  done < "$meta"

  # The peel. Reading from a file (not a pipe) keeps km_fail's counter in this
  # shell.
  progress=1
  while [ "$progress" -eq 1 ]; do
    progress=0
    : > "$next"
    while IFS="$t" read -r id relpath reqs; do
      [ -n "$id" ] || continue
      all_settled=1
      while IFS= read -r req; do
        [ -n "$req" ] || continue
        grep -qxF -- "$req" "$settled" || all_settled=0
      done < <(printf '%s\n' "$reqs" | tr ',' '\n')
      if [ "$all_settled" -eq 1 ]; then
        printf '%s\n' "$id" >> "$settled"
        progress=1
      else
        printf '%s%s%s%s%s\n' "$id" "$t" "$relpath" "$t" "$reqs" >> "$next"
      fi
    done < "$unsettled"
    cp "$next" "$unsettled"
  done

  while IFS="$t" read -r id relpath reqs; do
    [ -n "$id" ] || continue
    km_fail "$relpath" "requires cycle through: $id"
  done < "$unsettled"

  rm -f "$settled" "$unsettled" "$next"
}

# --- entry point -----------------------------------------------------------------

km_check() {
  KM_QUIET=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --quiet) KM_QUIET=1 ;;
      *) jig_die "usage: jig knowledge check [--quiet]" ;;
    esac
    shift
  done

  KM_FAILURES=0
  KM_WARNINGS=0
  KM_DOCS=0

  local require_fm=0
  cfg_bool knowledge.require_frontmatter true && require_fm=1

  local kdir="$KM_DIR"
  local file id relpath

  # NOTE: these hold mktemp paths and must stay script-global (not `local`):
  # the EXIT trap below fires after km_check has already returned, once its
  # `local` variables would be gone, so it needs names that are still bound.
  KM_LIST_FILE=$(mktemp "${TMPDIR:-/tmp}/jig-knowledge-list.XXXXXX")
  KM_IDS_FILE=$(mktemp "${TMPDIR:-/tmp}/jig-knowledge-ids.XXXXXX")
  KM_IDS_ALL_FILE=$(mktemp "${TMPDIR:-/tmp}/jig-knowledge-ids-all.XXXXXX")
  KM_ADR_NUMS_FILE=$(mktemp "${TMPDIR:-/tmp}/jig-knowledge-adr-nums.XXXXXX")
  KM_META_FILE=$(mktemp "${TMPDIR:-/tmp}/jig-knowledge-meta.XXXXXX")
  trap 'rm -f "$KM_LIST_FILE" "$KM_IDS_FILE" "$KM_IDS_ALL_FILE" "$KM_ADR_NUMS_FILE" "$KM_META_FILE"' EXIT INT TERM

  if [ -d "$kdir" ]; then
    find "$kdir" -type f -name '*.md' | sort > "$KM_LIST_FILE"
  fi

  # Pass 1: collect all declared ids up front, so `supersedes` can reference an
  # id defined in a document that sorts after the one referencing it, and the
  # `requires` graph can be walked in either direction.
  local t meta_status meta_reqs
  t=$(printf '\t')
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    jig_knowledge_is_global "$file" && continue
    fm_has "$file" || continue
    id=$(fm_get "$file" id)
    [ -n "$id" ] || continue
    printf '%s\n' "$id" >> "$KM_IDS_ALL_FILE"
    relpath=$(jig_relpath "$file" "$JIG_PROJECT")
    meta_status=$(fm_get "$file" status)
    meta_reqs=$(fm_list "$file" requires | sed '/^$/d' | tr '\n' ',' | sed 's/,$//')
    printf '%s%s%s%s%s%s%s\n' \
      "$id" "$t" "$relpath" "$t" "$meta_status" "$t" "$meta_reqs" >> "$KM_META_FILE"
  done < "$KM_LIST_FILE"

  # Pass 2: full validation.
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    KM_DOCS=$((KM_DOCS + 1))
    relpath=$(jig_relpath "$file" "$JIG_PROJECT")
    km_check_doc "$file" "$relpath" "$require_fm" "$KM_IDS_FILE" "$KM_IDS_ALL_FILE" "$KM_ADR_NUMS_FILE"
  done < "$KM_LIST_FILE"

  # Pass 3: the `requires` graph, which no single document can validate alone.
  km_check_requires "$KM_META_FILE"

  [ "$KM_QUIET" -eq 1 ] \
    || printf 'knowledge check: %d documents, %d failures, %d warnings\n' \
      "$KM_DOCS" "$KM_FAILURES" "$KM_WARNINGS"

  [ "$KM_FAILURES" -eq 0 ]
}

# --- document lookup -----------------------------------------------------------

# km_docs — every knowledge document that can carry frontmatter, sorted.
# One enumeration, shared with `context` (common.sh): the three global
# documents are excluded, everything else counts wherever it sits.
km_docs() { jig_knowledge_docs; }

# km_type_dir <type> — the subdirectory a document type lives in.
km_type_dir() {
  case "$1" in
    feature) printf 'features\n' ;;
    convention) printf 'conventions\n' ;;
    adr) printf 'adr\n' ;;
    *) jig_die "knowledge: unknown type '$1' (expected one of: $JIG_DOC_TYPES)" ;;
  esac
}

# km_doc_file <dir> <name> — path of a knowledge document. This is the single
# place a knowledge path is built from a caller-supplied name, so the name is
# validated here, before any read, write or `sed` that embeds it
# (RULES.md invariant, ADR-0008).
km_doc_file() {
  local dir="$1" name="$2"
  case "$dir" in
    features | conventions | adr) ;;
    *) jig_die "knowledge: unknown document directory: $dir" ;;
  esac
  case "$name" in
    '' | -* | *- | *[!a-z0-9-]*)
      jig_die "knowledge: invalid name '$name': expected [a-z0-9-], no leading or trailing '-'" ;;
  esac
  printf '%s/%s/%s.md\n' "$KM_DIR" "$dir" "$name"
}

# km_domain_dir <domain> — directory of a domain pack. The second place (with
# km_doc_file) where a knowledge path is built from a caller-supplied name, so
# the name is validated here, before any read, write or `sed` that embeds it
# (RULES.md invariant, ADR-0008).
km_domain_dir() {
  local domain="$1"
  case "$domain" in
    '' | -* | *- | *[!a-z0-9-]*)
      jig_die "knowledge: invalid domain '$domain': expected [a-z0-9-], no leading or trailing '-'" ;;
  esac
  printf '%s/domains/%s\n' "$KM_DIR" "$domain"
}

# km_domain_file <type> <domain> — path of one document of a domain pack. The
# file name is fixed by type, so a pack always has the same shape and a reader
# can find the rules of a domain without consulting an index.
km_domain_file() {
  local type="$1" domain="$2" base dir
  case "$type" in
    domain) base="OVERVIEW.md" ;;
    glossary) base="GLOSSARY.md" ;;
    rule) base="RULES.md" ;;
    *) jig_die "knowledge: type '$type' is not a domain document" ;;
  esac
  dir=$(km_domain_dir "$domain") || exit 1
  printf '%s/%s\n' "$dir" "$base"
}

# km_doc_by_id <id> — path of the document declaring <id>. Duplicate ids are
# a `knowledge check` failure, so the first match is the only match.
km_doc_by_id() {
  local want="$1" doc found=""
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    fm_has "$doc" || continue
    [ "$(fm_get "$doc" id)" = "$want" ] || continue
    found="$doc"
    break
  done < <(km_docs)
  [ -n "$found" ] || jig_die "knowledge: no document with id: $want"
  printf '%s\n' "$found"
}

# km_rel <file> — repo-relative path, the form every command prints.
km_rel() { jig_relpath "$1" "$JIG_PROJECT"; }

# km_files_word <count> — "1 file" / "3 files".
km_files_word() {
  if [ "$1" = 1 ]; then printf '1 file'; else printf '%s files' "$1"; fi
}

# --- new -----------------------------------------------------------------------

# km_next_adr — the next ADR number: highest existing + 1, four digits.
# Numbers are never reused, so this deliberately does not fill gaps (RULES.md).
km_next_adr() {
  local f base num max=0
  if [ -d "$KM_DIR/adr" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      base=$(basename "$f")
      case "$base" in
        [0-9][0-9][0-9][0-9]-*.md) ;;
        *) continue ;;
      esac
      # 10# keeps 0009 decimal; bare $((0009)) is an invalid octal literal.
      num=$((10#$(printf '%s' "$base" | cut -c1-4)))
      [ "$num" -gt "$max" ] && max="$num"
    done < <(find "$KM_DIR/adr" -type f -name '*.md')
  fi
  printf '%04d\n' $((max + 1))
}

# km_template_rel <type> — the template's path under templates/knowledge/.
#
# The three domain-pack templates live in a `domain/` subdirectory shaped like
# the pack itself, and not as `glossary.md` beside the global `GLOSSARY.md`:
# on a case-insensitive filesystem (macOS by default) those are one file, and
# writing one silently destroys the other.
km_template_rel() {
  case "$1" in
    domain) printf 'domain/OVERVIEW.md\n' ;;
    glossary) printf 'domain/GLOSSARY.md\n' ;;
    rule) printf 'domain/RULES.md\n' ;;
    *) printf '%s.md\n' "$1" ;;
  esac
}

# km_template <type> — the template to instantiate: the copy installed under
# .ai/templates/knowledge/ first, the framework checkout as a fallback for a
# project initialised before templates were installed.
km_template() {
  local type="$1" rel installed src
  rel=$(km_template_rel "$type")
  installed="$JIG_PROJECT/$JIG_AI_DIR/templates/knowledge/$rel"
  if [ -f "$installed" ]; then
    printf '%s\n' "$installed"
    return 0
  fi
  src=$(jig_source_root)
  if [ -n "$src" ] && [ -f "$src/templates/knowledge/$rel" ]; then
    printf '%s\n' "$src/templates/knowledge/$rel"
    return 0
  fi
  jig_die "knowledge: no template for type '$type'; run: jig upgrade"
}

# km_csv_lines <csv> — split "a, b" into one item per line.
km_csv_lines() {
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
}

km_new() {
  local type="" slug="" domains="" paths_in=""
  [ $# -ge 2 ] || jig_die "$KM_USAGE"
  type="$1"
  slug="$2"
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --domains) [ $# -ge 2 ] || jig_die "knowledge new: --domains requires a value"
        domains="$2"; shift 2 ;;
      --paths) [ $# -ge 2 ] || jig_die "knowledge new: --paths requires a value"
        paths_in="$2"; shift 2 ;;
      *) jig_die "knowledge new: unknown argument: $1" ;;
    esac
  done

  # The type is resolved to a path before the template is looked up, so an
  # unknown type is reported as an unknown type rather than as a missing
  # template.
  local dir template file id number rel tmp
  case "$type" in
    domain | glossary | rule)
      # For a domain document the slug *is* the domain: the pack lives under
      # domains/<domain>/ and the file name is fixed by type.
      file=$(km_domain_file "$type" "$slug") || exit 1
      id="$type-$slug"
      # A pack file that did not claim its own domain would fail
      # `knowledge check` immediately (km_check_domain_placement), so the
      # default is the only sensible one.
      [ -n "$domains" ] || domains="$slug"
      ;;
    adr)
      dir=$(km_type_dir "$type")
      number=$(km_next_adr)
      file=$(km_doc_file "$dir" "$number-$slug")
      id="adr-$number-$slug"
      ;;
    *)
      dir=$(km_type_dir "$type")
      file=$(km_doc_file "$dir" "$slug")
      id="$type-$slug"
      ;;
  esac
  template=$(km_template "$type")

  [ -e "$file" ] && jig_die "knowledge: document already exists: $(km_rel "$file")"

  mkdir -p "$(dirname "$file")"
  cp "$template" "$file"

  fm_set "$file" id "$id"
  if [ "$type" = adr ]; then
    fm_set "$file" date "$(jig_today)"
    # The heading placeholder carries the number too. `number` is four digits
    # by construction, so it is safe on the right-hand side of a substitution.
    tmp="$file.tmp.$$"
    sed "s/ADR-NNNN/ADR-$number/g" "$file" > "$tmp"
    mv "$tmp" "$file"
  fi
  # A rejected item (see _fm_valid_item) must not leave a half-filled document
  # behind: remove it and fail, so a retry starts from nothing.
  if [ -n "$domains" ] && ! km_csv_lines "$domains" | fm_list_set "$file" domains; then
    rm -f "$file"
    jig_die "knowledge new: invalid --domains value: $domains"
  fi
  if [ -n "$paths_in" ] && ! km_csv_lines "$paths_in" | fm_list_set "$file" paths; then
    rm -f "$file"
    jig_die "knowledge new: invalid --paths value: $paths_in"
  fi

  rel=$(km_rel "$file")
  printf '%s\n' "$rel"
}

# --- paths ---------------------------------------------------------------------

km_paths() {
  case "${1:-}" in
    add | remove) km_paths_edit "$@" ;;
    *) km_paths_report "$@" ;;
  esac
}

# km_paths_edit add|remove <id> <glob> — maintain one document's `paths`.
# The agent decides which glob belongs where; rewriting the frontmatter block
# is mechanical and therefore a script's job (ADR-0001).
km_paths_edit() {
  local op="$1"
  shift
  [ $# -eq 2 ] || jig_die "usage: jig knowledge paths $op <id> <glob>"
  local id="$1" glob="$2" file rel
  file=$(km_doc_by_id "$id")
  rel=$(km_rel "$file")

  # Membership is decided here rather than read off the writer's exit status:
  # a writer returns non-zero both for "the list already said that" and for a
  # failed write, and reporting a failed write as "unchanged" would be a lie.
  local listed=0
  fm_list "$file" paths | grep -qxF -- "$glob" && listed=1

  if [ "$op" = add ]; then
    if [ "$listed" -eq 1 ]; then
      printf 'unchanged  %s  %s (already listed)\n' "$rel" "$glob"
    else
      fm_list_add "$file" paths "$glob" \
        || jig_die "knowledge paths: failed to write $rel"
      printf 'added      %s  %s\n' "$rel" "$glob"
    fi
  else
    if [ "$listed" -eq 0 ]; then
      printf 'unchanged  %s  %s (not listed)\n' "$rel" "$glob"
    else
      fm_list_remove "$file" paths "$glob" \
        || jig_die "knowledge paths: failed to write $rel"
      printf 'removed    %s  %s\n' "$rel" "$glob"
    fi
  fi
}

# km_all_globs — every `paths` glob declared anywhere in the knowledge base.
km_all_globs() {
  local doc
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    fm_has "$doc" || continue
    fm_list "$doc" paths
  done < <(km_docs) | sed '/^$/d' | sort -u
}

# km_file_covered <file> <globs> — exit 0 when any glob matches the path.
km_file_covered() {
  local file="$1" globs="$2" glob pattern
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    pattern=$(jig_glob_pattern "$glob")
    # shellcheck disable=SC2254
    case "$file" in
      $pattern) return 0 ;;
    esac
  done < <(printf '%s\n' "$globs")
  return 1
}

# km_paths_report [--task <id>] [--files <list>|-]
#
# Two directions of the same question, "do `paths` still describe the code":
# files this task touched that no document claims, and globs that claim
# nothing. `--task` is accepted for symmetry with `jig context` and validates
# the task exists; the file set is git-derived either way, because a workspace
# belongs to its checkout and the checkout is on the task's branch (ADR-0008).
km_paths_report() {
  local task="" files_arg="" have_files=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --task) [ $# -ge 2 ] || jig_die "knowledge paths: --task requires a value"
        task="$2"; shift 2 ;;
      --files) [ $# -ge 2 ] || jig_die "knowledge paths: --files requires a value"
        files_arg="$2"; have_files=1; shift 2 ;;
      *) jig_die "$KM_USAGE" ;;
    esac
  done

  local files globs file
  # An explicit --task must name a real workspace, exactly as `jig context`
  # treats it: naming a task is a deliberate choice and a typo is an error.
  if [ -n "$task" ]; then
    # shellcheck source=lib/task.sh
    . "$JIG_LIB/task.sh"
    [ -f "$(task_dir "$task")/state" ] \
      || jig_die "knowledge paths: unknown task: $task"
  fi

  if [ "$have_files" -eq 1 ]; then
    if [ "$files_arg" = "-" ]; then
      files=$(cat)
    else
      files=$(printf '%s\n' "$files_arg" | tr ', ' '\n')
    fi
    files=$(printf '%s\n' "$files" | sed '/^$/d' | sort -u)
  else
    files=$(jig_git_touched_files)
  fi

  globs=$(km_all_globs)

  KM_UNCOVERED_FILE=$(mktemp "${TMPDIR:-/tmp}/jig-knowledge-uncovered.XXXXXX")
  trap 'rm -f "$KM_UNCOVERED_FILE"' EXIT INT TERM

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Knowledge and workspace files are not the subject of `paths`.
    case "$file" in "$JIG_AI_DIR"/*) continue ;; esac
    # A deleted path cannot be covered by a glob that must match the tree.
    [ -e "$JIG_PROJECT/$file" ] || continue
    km_file_covered "$file" "$globs" && continue
    # dirname of a root-level file is ".", which prints as "./" — the glob a
    # reader would write for it, not an empty path.
    printf '%s/\n' "$(dirname "$file")"
  done < <(printf '%s\n' "$files") > "$KM_UNCOVERED_FILE"

  local count line dir uncovered=0 unmatched=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    count=${line%% *}
    dir=${line#* }
    uncovered=$((uncovered + 1))
    printf 'uncovered: %s  (%s)\n' "$dir" "$(km_files_word "$count")"
  done < <(sort "$KM_UNCOVERED_FILE" | uniq -c | sed 's/^[[:space:]]*//')

  local doc rel glob
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    fm_has "$doc" || continue
    rel=$(km_rel "$doc")
    while IFS= read -r glob; do
      [ -n "$glob" ] || continue
      km_glob_matches "$glob" && continue
      unmatched=$((unmatched + 1))
      printf 'unmatched: %s  (%s)\n' "$rel" "$glob"
    done < <(fm_list "$doc" paths)
  done < <(km_docs)

  printf 'knowledge paths: %d uncovered directories, %d unmatched globs\n' \
    "$uncovered" "$unmatched"
}

# --- stale ---------------------------------------------------------------------

# km_date_num <YYYY-MM-DD> — comparable integer. String comparison of dates
# would depend on the collation locale; this does not.
km_date_num() { printf '%s' "$1" | tr -d '-'; }

# km_stale [--strict]
#
# Reports documents that have drifted away from the code they describe
# (ADR-0010). Historical documents — superseded, deprecated, rejected — are
# skipped: they describe the past on purpose. This is a report, not a gate:
# it exits 0 unless --strict is given, so `verify` does not start failing on
# knowledge that is merely aging.
km_stale() {
  local strict=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --strict) strict=1; shift ;;
      *) jig_die "usage: jig knowledge stale [--strict]" ;;
    esac
  done

  local doc rel status reviewed glob any_match last
  local docs=0 stale=0 unreviewed=0 orphaned=0 planned=0 first_unmatched

  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    fm_has "$doc" || continue
    status=$(fm_get "$doc" status)
    case "$status" in
      active | accepted) ;;
      *) continue ;;
    esac

    any_match=0
    first_unmatched=""
    set --
    while IFS= read -r glob; do
      [ -n "$glob" ] || continue
      if km_glob_matches "$glob"; then
        any_match=1
        set -- "$@" "$(jig_glob_pattern "$glob")"
      elif [ -z "$first_unmatched" ]; then
        first_unmatched="$glob"
      fi
    done < <(fm_list "$doc" paths)

    # A document without `paths` makes no claim about code and cannot drift.
    [ "$any_match" -eq 1 ] || [ -n "$first_unmatched" ] || continue

    docs=$((docs + 1))
    rel=$(km_rel "$doc")

    # Globs matching nothing mean one of two different things, and `reviewed_at`
    # tells them apart without a new field. Stamped once: the document did match
    # code, which has since moved or been deleted — real rot. Never stamped: it
    # never matched, so the code is not written yet. The T3 route decides at the
    # gate and implements afterwards (ADR-0009), so forward-looking documents are
    # normal here and must not be reported as rot.
    if [ "$any_match" -eq 0 ]; then
      reviewed=$(fm_get "$doc" reviewed_at)
      if [ -z "$reviewed" ]; then
        planned=$((planned + 1))
        printf 'planned:    %s  (no file matches yet: %s)\n' "$rel" "$first_unmatched"
      else
        orphaned=$((orphaned + 1))
        printf 'orphaned:   %s  (reviewed %s, no file matches: %s)\n' \
          "$rel" "$reviewed" "$first_unmatched"
      fi
      continue
    fi

    reviewed=$(fm_get "$doc" reviewed_at)
    if [ -z "$reviewed" ]; then
      unreviewed=$((unreviewed + 1))
      printf 'unreviewed: %s  (never reconciled with the code)\n' "$rel"
      continue
    fi

    last=$(git -C "$JIG_PROJECT" log -1 --date=short --format=%cd -- "$@" 2>/dev/null)
    [ -n "$last" ] || continue
    if [ "$(km_date_num "$last")" -gt "$(km_date_num "$reviewed")" ]; then
      stale=$((stale + 1))
      printf 'stale:      %s  (reviewed %s, code changed %s)\n' "$rel" "$reviewed" "$last"
    fi
  done < <(km_docs)

  printf 'knowledge stale: %d documents with paths, %d stale, %d unreviewed, %d orphaned, %d planned\n' \
    "$docs" "$stale" "$unreviewed" "$orphaned" "$planned"

  # `planned` is not a defect: the document is ahead of the code on purpose, so
  # --strict does not fail on it.
  [ "$strict" -eq 0 ] && return 0
  [ $((stale + unreviewed + orphaned)) -eq 0 ]
}

# --- reviewed ------------------------------------------------------------------

# km_reviewed <id> [--date YYYY-MM-DD] — stamp a document as reconciled with
# the code. `jig-consolidate` calls this for every document it touched; that
# is what keeps `reviewed_at` honest and `stale` meaningful.
km_reviewed() {
  local id="" date=""
  [ $# -ge 1 ] || jig_die "usage: jig knowledge reviewed <id> [--date YYYY-MM-DD]"
  id="$1"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --date) [ $# -ge 2 ] || jig_die "knowledge reviewed: --date requires a value"
        date="$2"; shift 2 ;;
      *) jig_die "knowledge reviewed: unknown argument: $1" ;;
    esac
  done

  [ -n "$date" ] || date=$(jig_today)
  case "$date" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) jig_die "knowledge reviewed: invalid date '$date' (expected YYYY-MM-DD)" ;;
  esac

  local file rel
  file=$(km_doc_by_id "$id")
  rel=$(km_rel "$file")
  fm_set "$file" reviewed_at "$date" \
    || jig_die "knowledge reviewed: failed to write $rel"
  printf 'reviewed   %s  %s\n' "$rel" "$date"
}
