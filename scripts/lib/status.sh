# cmd_status — version, init/manifest state, drift, pending knowledge
# proposals, active tasks, housekeeping age (ARCHITECTURE.md, Scripts layout). Sourced by
# scripts/jig; defines cmd_status.
# Read-only: never writes anything, with one exception — `--html` writes the
# status page, .ai/runtime/status.html, and nothing else (_status_html).
# shellcheck shell=bash

cmd_status() {
  local html=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --html) html=1; shift ;;
      *) jig_die "status: unknown argument: $1 (usage: jig status [--html])" ;;
    esac
  done
  jig_require_repo
  _status_load
  if [ "$html" = 1 ]; then
    _status_html
    return 0
  fi
  _status_report
}

# _status_load — source the peers whose answers this report consumes
# (ARCHITECTURE.md, Scripts layout: reporting commands are the exception).
_status_load() {
  # shellcheck source=lib/manifest.sh
  . "$JIG_LIB/manifest.sh"
  # shellcheck source=lib/upgrade.sh
  . "$JIG_LIB/upgrade.sh"
  # shellcheck source=lib/frontmatter.sh
  . "$JIG_LIB/frontmatter.sh"
  # shellcheck source=lib/knowledge.sh
  . "$JIG_LIB/knowledge.sh"
  # shellcheck source=lib/spec.sh
  . "$JIG_LIB/spec.sh"
  # shellcheck source=lib/task.sh
  . "$JIG_LIB/task.sh"
}

# _status_report — the plain-text report `jig status` prints.
_status_report() {
  printf '%s\n' "jig $JIG_VERSION"

  if [ ! -f "$JIG_PROJECT/$JIG_AI_DIR/config.yaml" ]; then
    printf '%s\n' "initialised: no"
    printf '%s\n' "hint: run \`jig init\` to bootstrap this project"
    return 0
  fi
  printf '%s\n' "initialised: yes"
  _status_config_local
  _status_agent_git

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
  local specs
  specs=$(spec_count)
  if [ "$specs" -gt 0 ]; then
    printf 'specs: %s (jig spec list)\n' "$specs"
    spec_epic_status
  else
    printf 'specs: none\n'
  fi

  local found=0 state_file line worktrees default_base blocking bcount receipt_changed autopilot_note
  _STATUS_FINISHED=0
  worktrees=$(_task_worktrees)
  default_base=$(cfg git.base_branch main)
  for state_file in "$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"/*/state; do
    [ -f "$state_file" ] || continue
    _status_task_facts "$state_file" "$worktrees" || continue
    found=1
    line="task $_ST_ID class=$_ST_CLASS status=$_ST_STATUS"
    [ -z "$_ST_WT" ] || line="$line $_ST_WT_NOTE"
    # Same rule as `jig task list`: the base only where it is not the project's.
    if [ -n "$_ST_BASE" ] && [ "$_ST_BASE" != "$default_base" ]; then
      line="$line base=$_ST_BASE"
    fi
    if [ "$_ST_PAUSED" = "true" ]; then
      if [ -n "$_ST_REASON" ]; then
        line="$line paused ($_ST_REASON)"
      else
        line="$line paused"
      fi
    fi
    # Same predicate every gate uses (_task_blocking_findings, task.sh):
    # reporting never recomputes a peer's answer (ARCHITECTURE.md, Scripts
    # layout).
    blocking=$(_task_blocking_findings "$_ST_ID")
    bcount=$(_task_count_lines "$blocking")
    [ "$bcount" -eq 0 ] || line="$line blocking=$bcount"
    # Same predicate every gate uses (_task_receipt_changed, task.sh): a
    # receipt that exists but no longer matches the reviewed state. A task
    # with no receipt at all is not flagged here — that is "not reviewed yet",
    # not "stale" (design.md §5).
    receipt_changed=$(_task_receipt_changed "$_ST_ID")
    [ -z "$receipt_changed" ] || line="$line review=stale"
    # Same predicate `jig task autopilot report` prints (_task_autopilot_note,
    # task.sh): a run mid-flight (`on`) or waiting on a human (`stopped`).
    # `done`, and a task that never ran one, add nothing (design.md, autopilot).
    autopilot_note=$(_task_autopilot_note "$_ST_ID")
    [ -z "$autopilot_note" ] || line="$line $autopilot_note"
    printf '%s\n' "$line"
  done
  [ "$found" = 1 ] || printf '%s\n' "no active tasks"
  [ "$_STATUS_FINISHED" -gt 0 ] && printf '(%d finished; jig task list --all)\n' "$_STATUS_FINISHED"

  printf 'current task: %s\n' "$(_status_current_task)"
  printf 'housekeeping: %s\n' "$(_status_housekeeping_age)"

  # Tasks the last housekeeping run flagged (_status_hk_count).
  local nc kept wrong
  nc=$(_status_hk_count needs-consolidation)
  if [ "$nc" != "0" ]; then
    printf '%s\n' "needs consolidation: $nc task(s) (see .ai/runtime/housekeeping.log)"
  fi
  # A finished task whose worktree could not be removed is hidden from the
  # task listing above, so this line is the only place it surfaces. The
  # worktree usually holds work nobody committed (ADR-0029).
  kept=$(_status_hk_count worktree-kept)
  if [ "$kept" != "0" ]; then
    printf '%s\n' "worktrees kept: $kept task(s) (see .ai/runtime/housekeeping.log)"
  fi
  # Work that landed somewhere other than the task's base: kept, and only a
  # person can say where it should have gone (ADR-0039).
  wrong=$(_status_hk_count wrong-base)
  if [ "$wrong" != "0" ]; then
    printf '%s\n' "wrong base: $wrong task(s) (see .ai/runtime/housekeeping.log)"
  fi

  _status_session_hook
  _status_instructions
}

# _status_task_facts <state-file> <worktrees> — read one task's state into
# the _ST_* globals both the text report and the page show. Returns 1, after
# counting it in _STATUS_FINISHED, for a finished task: finished work is
# counted, not listed, so on a long-lived branch it does not crowd out the
# tasks actually in flight (same rule as `jig task list`, see _task_is_live).
# <worktrees> is a `_task_worktrees` listing: a task started in its own
# worktree is still listed where it was filed, and git says where its branch
# is checked out (ADR-0029).
_status_task_facts() {
  local state_file="$1" worktrees="$2"
  _ST_ID=$(sed -n 's/^task_id:[[:space:]]*//p' "$state_file" | head -n 1)
  _ST_CLASS=$(sed -n 's/^class:[[:space:]]*//p' "$state_file" | head -n 1)
  _ST_STATUS=$(sed -n 's/^status:[[:space:]]*//p' "$state_file" | head -n 1)
  case "$_ST_STATUS" in
    active | ready) ;;
    *) _STATUS_FINISHED=$((_STATUS_FINISHED + 1)); return 1 ;;
  esac
  _ST_PAUSED=$(sed -n 's/^paused:[[:space:]]*//p' "$state_file" | head -n 1)
  _ST_REASON=""
  if [ "$_ST_PAUSED" = "true" ]; then
    _ST_REASON=$(sed -n 's/^paused_reason:[[:space:]]*//p' "$state_file" | head -n 1)
  fi
  _ST_WT="" _ST_WT_NOTE=""
  _ST_BRANCH=$(sed -n 's/^branch:[[:space:]]*//p' "$state_file" | head -n 1)
  if [ -n "$_ST_BRANCH" ]; then
    _ST_WT=$(_task_worktree_for "$_ST_BRANCH" "$worktrees")
    [ -z "$_ST_WT" ] || _ST_WT_NOTE=$(_task_worktree_note "$_ST_WT")
  fi
  _ST_BASE=$(sed -n 's/^base_branch:[[:space:]]*//p' "$state_file" | head -n 1)
  return 0
}

# _status_current_task — the workspace whose branch matches the checkout
# (ADR-0008). Three outcomes (design.md §2): exactly one candidate prints its
# id, none prints "none", several print "ambiguous (a, b)" built from
# task_current's own stderr (one line per candidate, id is the first field)
# rather than re-deriving the candidate list here.
_status_current_task() {
  local current cur_rc=0 cur_err_file ids
  cur_err_file=$(mktemp "${TMPDIR:-/tmp}/jig-status-current.XXXXXX")
  current=$(task_current 2>"$cur_err_file") || cur_rc=$?
  case "$cur_rc" in
    0)
      printf '%s\n' "$current"
      ;;
    2)
      ids=$(awk '{ if (NR > 1) printf ", "; printf "%s", $1 }' "$cur_err_file")
      printf 'ambiguous (%s)\n' "$ids"
      ;;
    *)
      printf 'none\n'
      ;;
  esac
  rm -f "$cur_err_file"
}

# _status_housekeeping_age — "<n> days ago" since the last housekeeping run,
# or "never".
_status_housekeeping_age() {
  local hk_file="$JIG_PROJECT/$JIG_AI_DIR/runtime/last-housekeeping"
  if [ -f "$hk_file" ]; then
    printf '%s\n' "$(jig_file_age_days "$hk_file") days ago"
  else
    printf '%s\n' "never"
  fi
}

# _status_hk_count <flag> — distinct tasks the last housekeeping run flagged
# with <flag>, 0 when housekeeping has never logged. Housekeeping exits 3 for
# these, but nothing keeps that exit code around, and a flag nobody sees is the
# manual discipline the framework exists to remove (RULES.md, Scope invariants).
#
# Counted from the last `--- run` marker onwards, and by distinct task id.
# Both halves matter: the log is append-only, so scanning all of it reports
# a task flagged on three consecutive days as three tasks, and keeps
# reporting one that was consolidated months ago.
_status_hk_count() {
  local hk_log="$JIG_PROJECT/$JIG_AI_DIR/runtime/housekeeping.log"
  if [ -f "$hk_log" ]; then
    _status_flagged "$hk_log" "$1"
  else
    printf '0\n'
  fi
}

# --- the status page (`jig status --html`) ---------------------------------------
#
# One self-contained HTML file for a person who does not live in a terminal
# (.ai/specs/autopilot/, Phase 5): inline CSS, no script, no external asset,
# so it opens from disk with the network off, and it follows the reader's
# light or dark preference. It is a snapshot, rewritten whole on every run
# under one fixed name, and it says when it was made.
#
# Everything on it is an answer this report already consumes — the same
# helpers the text report and the completion gates call — and every value is
# escaped with _status_h, because task ids, finding locations, spec titles and
# paths are text people wrote.

# Script-global: the EXIT trap runs after _status_html has returned.
_STATUS_HTML_TMP=""

# _status_html — write .ai/runtime/status.html and print its path. Refuses on
# a project that is not initialised: the page would create .ai/ in a
# repository that never asked for it.
_status_html() {
  [ -f "$JIG_PROJECT/$JIG_AI_DIR/config.yaml" ] \
    || jig_die "status --html: project is not initialised; run: jig init"
  local dir="$JIG_PROJECT/$JIG_AI_DIR/runtime" out
  out="$dir/status.html"
  mkdir -p "$dir" || jig_die "status --html: cannot create $dir"
  _STATUS_HTML_TMP="$out.tmp.$$"
  trap 'if [ -n "${_STATUS_HTML_TMP:-}" ]; then rm -f "$_STATUS_HTML_TMP"; fi' EXIT INT TERM
  _status_html_page > "$_STATUS_HTML_TMP"
  mv "$_STATUS_HTML_TMP" "$out" || jig_die "status --html: cannot write $out"
  _STATUS_HTML_TMP=""
  printf '%s\n' "$out"
}

# _status_h <text> — <text> escaped for HTML text and attribute values.
# sed, not ${var//&/...}: from bash 5.2 an `&` in that replacement means the
# matched text (patsub_replacement), so the same line escapes differently on
# macOS's bash 3.2 and a Linux bash.
_status_h() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

# _status_html_item <label> <value> <attention: 0|1> — one summary entry.
_status_html_item() {
  local cls="item"
  [ "$3" = 0 ] || cls="item attention"
  printf '<div class="%s"><dt>%s</dt><dd>%s</dd></div>\n' "$cls" "$(_status_h "$1")" "$(_status_h "$2")"
}

# _status_html_count <label> <n> — a summary entry that needs attention
# when <n> is not 0.
_status_html_count() {
  if [ "$2" = 0 ]; then
    _status_html_item "$1" "none" 0
  else
    _status_html_item "$1" "$2" 1
  fi
}

_status_html_page() {
  local project generated report
  project=$(basename "$JIG_PROJECT")
  generated=$(date '+%Y-%m-%d %H:%M')
  # The whole text report, as `jig status` prints it, so the page never shows
  # less than the terminal does. errexit is set again inside the
  # substitution, which does not inherit it.
  report=$(set -e; _status_report)

  cat <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
HTML
  printf '<title>Jig status: %s</title>\n' "$(_status_h "$project")"
  cat <<'HTML'
<style>
:root {
  --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0; --panel: #f6f8fa;
  --ok-bg: #dafbe1; --ok-fg: #116329; --bad-bg: #ffebe9; --bad-fg: #a40e26;
  --warn-bg: #fff8c5; --warn-fg: #7d4e00;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --line: #3d444d; --panel: #151b23;
    --ok-bg: #12361f; --ok-fg: #7ee2a8; --bad-bg: #3c1618; --bad-fg: #ffa198;
    --warn-bg: #3a2c05; --warn-fg: #e3b341;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg);
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 48px; }
h1 { font-size: 1.6rem; margin: 0 0 4px; }
h2 { font-size: 1.15rem; margin: 32px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
p { margin: 0 0 8px; }
.muted { color: var(--muted); }
code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 0.9em; }
dl.summary { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 10px; margin: 0; }
.item { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; }
.item dt { color: var(--muted); font-size: 0.85rem; }
.item dd { margin: 2px 0 0; font-weight: 600; overflow-wrap: anywhere; }
.item.attention { background: var(--warn-bg); border-color: var(--warn-fg); }
.item.attention dd { color: var(--warn-fg); }
.scroll { overflow-x: auto; border: 1px solid var(--line); border-radius: 8px; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; vertical-align: top; padding: 8px 10px; border-bottom: 1px solid var(--line); }
th { background: var(--panel); font-size: 0.85rem; color: var(--muted); font-weight: 600; white-space: nowrap; }
tr:last-child td { border-bottom: 0; }
td.path { overflow-wrap: anywhere; min-width: 12rem; }
td.id code { white-space: nowrap; }
.badge { display: inline-block; padding: 1px 8px; border-radius: 999px; font-size: 0.85rem;
  background: var(--panel); border: 1px solid var(--line); white-space: nowrap; }
.badge.ok { background: var(--ok-bg); color: var(--ok-fg); border-color: transparent; }
.badge.bad { background: var(--bad-bg); color: var(--bad-fg); border-color: transparent; }
.badge.warn { background: var(--warn-bg); color: var(--warn-fg); border-color: transparent; }
ul.findings { margin: 0; padding-left: 18px; }
ul.findings li { color: var(--bad-fg); }
.empty { padding: 14px; background: var(--panel); border: 1px dashed var(--line); border-radius: 8px; color: var(--muted); }
details { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; }
summary { cursor: pointer; }
pre { margin: 10px 0 0; white-space: pre-wrap; overflow-wrap: anywhere; }
</style>
</head>
<body>
<main>
HTML
  printf '<h1>Jig status</h1>\n'
  printf '<p class="muted">Project <strong>%s</strong> · generated %s · jig %s</p>\n' \
    "$(_status_h "$project")" "$(_status_h "$generated")" "$(_status_h "$JIG_VERSION")"
  printf '<p class="muted">A snapshot: run <code>jig status --html</code> again to refresh it.</p>\n'

  _status_html_summary
  _status_html_tasks
  _status_html_specs

  printf '<section id="report">\n<h2>Full report</h2>\n'
  printf '<details><summary>What <code>jig status</code> prints</summary>\n<pre>%s</pre>\n</details>\n</section>\n' \
    "$(_status_h "$report")"
  printf '</main>\n</body>\n</html>\n'
}

# _status_html_summary — the counts the text report prints as single lines.
_status_html_summary() {
  printf '<section id="summary">\n<h2>At a glance</h2>\n<dl class="summary">\n'
  _status_html_item "Current task" "$(_status_current_task)" 0
  _status_html_count "Knowledge awaiting decision" "$(km_proposed_count)"
  _status_html_count "Linked sources changed" "$(km_changed_sources_count)"
  _status_html_count "Needs consolidation" "$(_status_hk_count needs-consolidation)"
  _status_html_count "Worktrees kept" "$(_status_hk_count worktree-kept)"
  _status_html_count "Landed on the wrong base" "$(_status_hk_count wrong-base)"
  _status_html_item "Housekeeping last ran" "$(_status_housekeeping_age)" 0
  printf '</dl>\n</section>\n'
}

# _status_html_tasks — one row per live task: the same facts as the text
# report's task lines, with the blocking findings' own lines
# (_task_blocking_findings) and the receipt as `task receipt --check` answers
# it (task_receipt_check), none included.
_status_html_tasks() {
  local found=0 state_file worktrees blocking bline receipt cls
  _STATUS_FINISHED=0
  worktrees=$(_task_worktrees)
  printf '<section id="tasks">\n<h2>Tasks</h2>\n'
  for state_file in "$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"/*/state; do
    [ -f "$state_file" ] || continue
    _status_task_facts "$state_file" "$worktrees" || continue
    if [ "$found" = 0 ]; then
      found=1
      printf '<div class="scroll"><table>\n'
      printf '<thead><tr><th>Task</th><th>Class</th><th>Status</th><th>Base</th><th>Worktree</th><th>Review receipt</th><th>Blocking findings</th></tr></thead>\n<tbody>\n'
    fi
    printf '<tr><td class="id"><code>%s</code></td><td>%s</td><td>%s' \
      "$(_status_h "$_ST_ID")" "$(_status_h "${_ST_CLASS:--}")" "$(_status_h "$_ST_STATUS")"
    if [ "$_ST_PAUSED" = "true" ]; then
      printf ' <span class="badge warn">paused</span>'
      [ -z "$_ST_REASON" ] || printf ' <span class="muted">%s</span>' "$(_status_h "$_ST_REASON")"
    fi
    printf '</td><td>%s</td>' "$(_status_h "$(jig_task_base "$_ST_ID")")"
    if [ -n "$_ST_WT" ]; then
      printf '<td class="path"><code>%s</code><br><span class="muted">%s uncommitted</span></td>' \
        "$(_status_h "$_ST_WT")" "$(_status_h "${_ST_WT_NOTE##* uncommitted=}")"
    else
      printf '<td class="muted">-</td>'
    fi
    # task_receipt_check exits 1 for stale and for a T4 with none; its line
    # is the answer either way.
    receipt=$(task_receipt_check "$_ST_ID" || true)
    receipt=${receipt#receipt: }
    case "$receipt" in
      current) cls="ok" ;;
      stale* | *required*) cls="bad" ;;
      *) cls="" ;;
    esac
    printf '<td><span class="badge%s">%s</span></td>' "${cls:+ $cls}" "$(_status_h "$receipt")"
    blocking=$(_task_blocking_findings "$_ST_ID")
    if [ -z "$blocking" ]; then
      printf '<td class="muted">none</td></tr>\n'
    else
      printf '<td><ul class="findings">'
      while IFS= read -r bline; do
        [ -n "$bline" ] || continue
        printf '<li><code>%s</code></li>' "$(_status_h "$bline")"
      done < <(printf '%s\n' "$blocking")
      printf '</ul><span class="muted">details: <code>jig task findings %s</code></span></td></tr>\n' \
        "$(_status_h "$_ST_ID")"
    fi
  done
  if [ "$found" = 1 ]; then
    printf '</tbody>\n</table></div>\n'
  else
    printf '<p class="empty">No active tasks.</p>\n'
  fi
  if [ "$_STATUS_FINISHED" -gt 0 ]; then
    printf '<p class="muted">%d finished, not listed (<code>jig task list --all</code>).</p>\n' "$_STATUS_FINISHED"
  fi
  printf '</section>\n'
}

# _status_html_specs — `spec list`'s rows (spec_list_rows) and the open epics
# `jig status` names (spec_epic_status).
_status_html_specs() {
  local rows id title state epics eline
  printf '<section id="specs">\n<h2>Specifications</h2>\n'
  rows=$(spec_list_rows)
  if [ -z "$rows" ]; then
    printf '<p class="empty">No specifications.</p>\n</section>\n'
    return 0
  fi
  printf '<div class="scroll"><table>\n'
  printf '<thead><tr><th>Spec</th><th>Title</th><th>Progress</th></tr></thead>\n<tbody>\n'
  while IFS="$(printf '\t')" read -r id title state; do
    [ -n "$id" ] || continue
    printf '<tr><td><code>%s</code></td><td>%s</td><td>%s</td></tr>\n' \
      "$(_status_h "$id")" "$(_status_h "$title")" "$(_status_h "$state")"
  done < <(printf '%s\n' "$rows")
  printf '</tbody>\n</table></div>\n'
  epics=$(spec_epic_status)
  if [ -n "$epics" ]; then
    printf '<ul>\n'
    while IFS= read -r eline; do
      [ -n "$eline" ] || continue
      printf '<li>%s</li>\n' "$(_status_h "$eline")"
    done < <(printf '%s\n' "$epics")
    printf '</ul>\n'
  fi
  printf '</section>\n'
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
  if [ -f "$file" ]; then
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
  fi

  # A JIG_CFG_LOCAL_ONLY_KEYS key (config.sh) set in the *project's* committed
  # config.yaml is never read there: `cfg` answers only from the local file
  # and the default for it. A silent no-op is the worst outcome for a value
  # someone deliberately wrote, so it is named here even when there is no
  # local file at all.
  local pkey pvalue t
  t=$(printf '\t')
  # shellcheck disable=SC2034 # pvalue: read shape must match
  # jig_config_project_ignored's two columns; the message names the key only.
  while IFS="$t" read -r pkey pvalue; do
    [ -n "$pkey" ] || continue
    printf 'config.local: %s in %s is ignored (set it in %s)\n' \
      "$pkey" "$JIG_AI_DIR/config.yaml" "$JIG_AI_DIR/config.local.yaml"
  done < <(jig_config_project_ignored)
}

# _status_agent_git — one line naming the review queue `agent.git`'s level
# (config.sh) leaves for the human, always printed: the level is `none` by
# default, and "none" is exactly the state this line exists to make visible
# alongside every other level (design.md, .ai/specs/autopilot/).
_status_agent_git() {
  local level queue
  if level=$(jig_agent_git); then
    case "$level" in
      none) queue="uncommitted files" ;;
      commit) queue="unpushed commits" ;;
      push) queue="pushed branches without a pull request" ;;
      pr) queue="open pull requests" ;;
    esac
    printf 'agent.git: %s (review queue: %s)\n' "$level" "$queue"
  else
    printf 'agent.git: invalid value %s (expected none|commit|push|pr)\n' "$level"
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
