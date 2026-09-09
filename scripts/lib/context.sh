# cmd_context — relevant knowledge for a task (SPEC §26; ADR-0004; ADR-0008).
# Sourced by scripts/jig; defines cmd_context. Deterministic: no LLM, no
# judgement calls beyond the matching rules below. bash 3.2 compatible: no
# associative arrays, no ${var,,}, no mapfile.
# shellcheck shell=bash

# Global files, in the fixed order they are reported, when present.
_CTX_GLOBAL_FILES="GLOSSARY.md ARCHITECTURE.md RULES.md"

# Workspace artifacts other than task.md, in the fixed order they are
# reported, when present (SPEC §14).
_CTX_WORKSPACE_ARTIFACTS="discovery.md spec.md design.md plan.md review.md verification.md"

cmd_context() {
  jig_require_init
  # shellcheck source=lib/frontmatter.sh
  . "$JIG_LIB/frontmatter.sh"
  # shellcheck source=lib/task.sh
  . "$JIG_LIB/task.sh"

  local task_id="" files_arg="" files_stdin=0 domains_arg="" show_all=0 format="list"
  while [ $# -gt 0 ]; do
    case "$1" in
      --task) [ $# -ge 2 ] || jig_die "context: --task requires a value"; task_id="$2"; shift 2 ;;
      --files)
        [ $# -ge 2 ] || jig_die "context: --files requires a value"
        if [ "$2" = "-" ]; then files_stdin=1; else files_arg="$2"; fi
        shift 2
        ;;
      --domains) [ $# -ge 2 ] || jig_die "context: --domains requires a value"; domains_arg="$2"; shift 2 ;;
      --all) show_all=1; shift ;;
      --format)
        [ $# -ge 2 ] || jig_die "context: --format requires a value"
        case "$2" in
          list | paths) format="$2" ;;
          *) jig_die "context: invalid --format: $2 (want list or paths)" ;;
        esac
        shift 2
        ;;
      *) jig_die "context: unknown argument: $1" ;;
    esac
  done

  # --- task resolution --------------------------------------------------------
  # An explicit --task must name a real workspace (the caller made a
  # deliberate choice); the implicit `task current` lookup fails silently on
  # "no candidate" — a normal outcome, not an error (SPEC §26: "If nothing
  # matched, only global + workspace are returned"). On "several candidates"
  # (exit 2, design.md §2) the workspace section is omitted too — picking one
  # would risk loading the wrong task's artifacts — but this time it is not
  # silent: task_current's own stderr (one line per candidate) is forwarded
  # so the caller can see why.
  if [ -n "$task_id" ]; then
    [ -f "$(task_dir "$task_id")/state" ] || jig_die "context: unknown task: $task_id"
  else
    local tc_rc=0 tc_err_file
    tc_err_file=$(mktemp "${TMPDIR:-/tmp}/jig-context-current.XXXXXX")
    task_id=$(task_current 2>"$tc_err_file") || tc_rc=$?
    [ "$tc_rc" -eq 2 ] && cat "$tc_err_file" >&2
    [ "$tc_rc" -eq 0 ] || task_id=""
    rm -f "$tc_err_file"
  fi

  # --- files --------------------------------------------------------------------
  local files
  if [ "$files_stdin" -eq 1 ]; then
    files=$(cat)
  elif [ -n "$files_arg" ]; then
    files=$(printf '%s' "$files_arg" | tr ',' '\n')
  else
    files=$(jig_git_touched_files)
  fi

  # --- domains --------------------------------------------------------------------
  local domains=""
  if [ -n "$domains_arg" ]; then
    domains=$(printf '%s' "$domains_arg" | tr ',' ' ')
  elif [ -n "$task_id" ]; then
    local task_domains
    task_domains=$(task_state_get "$task_id" domains)
    [ -n "$task_domains" ] && domains=$(printf '%s' "$task_domains" | tr ',' ' ')
  fi

  # --- rows: label<TAB>path<TAB>reason, in report order --------------------------
  local t rows=""
  t=$(printf '\t')

  local g
  for g in $_CTX_GLOBAL_FILES; do
    [ -f "$JIG_PROJECT/$JIG_AI_DIR/knowledge/$g" ] || continue
    rows="$rows
global${t}${JIG_AI_DIR}/knowledge/${g}${t}"
  done

  local matched
  matched=$(_ctx_matched_docs "$files" "$domains" "$show_all")
  if [ -n "$matched" ]; then
    rows="$rows
$(printf '%s\n' "$matched" | sed "s/^/matched${t}/")"
  fi

  if [ -n "$task_id" ]; then
    local wdir="$JIG_AI_DIR/workspace/tasks/$task_id" wf
    if [ -f "$JIG_PROJECT/$wdir/task.md" ]; then
      rows="$rows
workspace${t}${wdir}/task.md${t}"
    fi
    for wf in $_CTX_WORKSPACE_ARTIFACTS; do
      [ -f "$JIG_PROJECT/$wdir/$wf" ] || continue
      rows="$rows
workspace${t}${wdir}/${wf}${t}"
    done
  fi

  rows=$(printf '%s\n' "$rows" | sed '/^$/d')

  # --- render --------------------------------------------------------------------
  [ -z "$rows" ] && return 0

  if [ "$format" = "paths" ]; then
    printf '%s\n' "$rows" | cut -f2
    return 0
  fi

  local label path reason
  while IFS="$t" read -r label path reason; do
    [ -n "$label" ] || continue
    if [ -n "$reason" ]; then
      printf '%-10s %s  (%s)\n' "$label:" "$path" "$reason"
    else
      printf '%-10s %s\n' "$label:" "$path"
    fi
  done < <(printf '%s\n' "$rows")
}

# --- knowledge matching -------------------------------------------------------------

# _ctx_path_matches_any <glob> <files-newline-list> — exit 0 when <glob>
# matches at least one line of <files>.
_ctx_path_matches_any() {
  local glob="$1" files="$2" pattern file
  pattern=$(jig_glob_pattern "$glob")
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # shellcheck disable=SC2254
    case "$file" in
      $pattern) return 0 ;;
    esac
  done < <(printf '%s\n' "$files")
  return 1
}

# _ctx_domain_matches_any <domain> <space-separated wanted domains>
_ctx_domain_matches_any() {
  local d="$1" domains="$2" want
  for want in $domains; do
    [ "$d" = "$want" ] && return 0
  done
  return 1
}

# _ctx_doc_reason <doc> <files> <domains> — print "paths: <glob>" or
# "domains: <domain>" for the first matching entry (frontmatter order,
# paths checked before domains) and exit 0; exit 1 and print nothing when
# neither matches.
_ctx_doc_reason() {
  local doc="$1" files="$2" domains="$3" glob dom

  if [ -n "$files" ]; then
    while IFS= read -r glob; do
      [ -n "$glob" ] || continue
      if _ctx_path_matches_any "$glob" "$files"; then
        printf 'paths: %s\n' "$glob"
        return 0
      fi
    done < <(fm_list "$doc" paths)
  fi

  if [ -n "$domains" ]; then
    while IFS= read -r dom; do
      [ -n "$dom" ] || continue
      if _ctx_domain_matches_any "$dom" "$domains"; then
        printf 'domains: %s\n' "$dom"
        return 0
      fi
    done < <(fm_list "$doc" domains)
  fi

  return 1
}

# _ctx_matched_docs <files> <domains> <show_all> — "<relpath><TAB><reason>"
# lines, one per matching document, sorted by path.
_ctx_matched_docs() {
  local files="$1" domains="$2" show_all="$3"
  local t doc status reason relpath out=""
  t=$(printf '\t')

  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    fm_has "$doc" || continue

    if [ "$show_all" -ne 1 ]; then
      status=$(fm_get "$doc" status)
      case "$status" in
        superseded | deprecated | rejected) continue ;;
      esac
    fi

    reason=$(_ctx_doc_reason "$doc" "$files" "$domains") || continue
    relpath=$(jig_relpath "$doc" "$JIG_PROJECT")
    out="$out
${relpath}${t}${reason}"
  done < <(find "$JIG_PROJECT/$JIG_AI_DIR/knowledge/features" \
                "$JIG_PROJECT/$JIG_AI_DIR/knowledge/adr" \
                "$JIG_PROJECT/$JIG_AI_DIR/knowledge/conventions" \
                -type f -name '*.md' 2>/dev/null)

  printf '%s\n' "$out" | sed '/^$/d' | sort
}
