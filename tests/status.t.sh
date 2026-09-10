# Tests for `jig status` (SPEC §29).
# shellcheck shell=bash

test_status_not_initialised() {
  fixture_repo
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "jig "
  assert_contains "$OUT" "initialised: no"
  assert_contains "$OUT" "jig init"
}

test_status_initialised_no_drift_no_tasks() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "initialised: yes"
  assert_contains "$OUT" "manifest: version="
  assert_contains "$OUT" "mode=copy"
  assert_contains "$OUT" "drift: 0 modified, 0 missing"
  assert_contains "$OUT" "no active tasks"
  assert_contains "$OUT" "housekeeping: never"
}

test_status_reports_drift() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  printf '\n# drift\n' >> .ai/scripts/lib/config.sh
  rm -f .ai/profiles/generic/profile.yaml

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 1 modified, 1 missing"
  assert_contains "$OUT" "modified:"
  assert_contains "$OUT" ".ai/scripts/lib/config.sh"
  assert_contains "$OUT" "missing:"
  assert_contains "$OUT" ".ai/profiles/generic/profile.yaml"
}

# --- proposals: knowledge awaiting a decision --------------------------------
# (ADR-0016) A `proposed` document is invisible to every agent until a human
# accepts it, so `jig status` is the only place its existence surfaces. The
# line sits between drift and the task lines (SPEC §29).

test_status_reports_no_proposals_by_default() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "proposals: none"
}

test_status_reports_proposal_count() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  jig knowledge new feature one >/dev/null
  jig knowledge new feature two >/dev/null
  sed 's/^status: active/status: proposed/' .ai/knowledge/features/one.md \
    > .ai/knowledge/features/one.md.new
  mv .ai/knowledge/features/one.md.new .ai/knowledge/features/one.md
  sed 's/^status: active/status: proposed/' .ai/knowledge/features/two.md \
    > .ai/knowledge/features/two.md.new
  mv .ai/knowledge/features/two.md.new .ai/knowledge/features/two.md

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "proposals: 2 awaiting decision (jig knowledge proposed)"
  assert_not_contains "$OUT" "proposals: none"
}

# The count printed by `jig status` and the listing printed by `jig knowledge
# proposed` are backed by the same km_is_proposed helper (see knowledge.sh);
# this pins that they never disagree about how many documents are proposed.
test_status_proposal_count_matches_knowledge_proposed_listing() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  jig knowledge new feature one >/dev/null
  jig knowledge new feature two >/dev/null
  jig knowledge new feature three >/dev/null
  sed 's/^status: active/status: proposed/' .ai/knowledge/features/one.md \
    > .ai/knowledge/features/one.md.new
  mv .ai/knowledge/features/one.md.new .ai/knowledge/features/one.md
  sed 's/^status: active/status: proposed/' .ai/knowledge/features/two.md \
    > .ai/knowledge/features/two.md.new
  mv .ai/knowledge/features/two.md.new .ai/knowledge/features/two.md
  # "three" stays active on purpose, so the count has to actually filter by
  # status rather than counting every document under .ai/knowledge/features.

  run jig status
  assert_eq 0 "$RC"
  local status_count
  status_count=$(printf '%s\n' "$OUT" | sed -n 's/^proposals: \([0-9]\{1,\}\) awaiting decision.*/\1/p')
  assert_eq "2" "$status_count" "status proposal count"

  run jig knowledge proposed
  assert_eq 0 "$RC"
  local listed_count
  listed_count=$(printf '%s\n' "$OUT" | grep -c '^proposed:  ')
  assert_eq "$status_count" "$listed_count" "status count vs knowledge proposed listing"
}

test_status_lists_active_tasks() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/workspace/tasks/TASK-1
  cat > .ai/workspace/tasks/TASK-1/state <<'EOF'
task_id: TASK-1
branch: feature/TASK-1
class: T2
status: active
knowledge_consolidated: false
created_at: 2026-09-08
updated_at: 2026-09-08
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active"
  assert_not_contains "$OUT" "no active tasks"
}

test_status_housekeeping_age() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig status
  assert_contains "$OUT" "housekeeping: never"

  : > .ai/runtime/last-housekeeping
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "housekeeping: 0 days ago"
}

test_status_via_installed_copy() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "initialised: yes"
  assert_contains "$OUT" "drift: 0 modified, 0 missing"
}

test_status_reports_current_task_ambiguous() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "current task: ambiguous ("
  assert_contains "$OUT" "T-1"
  assert_contains "$OUT" "T-2"
}

test_status_paused_task_line_shows_marker_and_reason() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/workspace/tasks/TASK-1
  cat > .ai/workspace/tasks/TASK-1/state <<'EOF'
task_id: TASK-1
branch: main
class: T2
status: active
knowledge_consolidated: false
paused: true
paused_at: 2026-09-01
paused_reason: waiting on API access
created_at: 2026-09-08
updated_at: 2026-09-08
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active paused (waiting on API access)"
}

test_status_paused_task_line_shows_marker_without_reason() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/workspace/tasks/TASK-1
  cat > .ai/workspace/tasks/TASK-1/state <<'EOF'
task_id: TASK-1
branch: main
class: T2
status: active
knowledge_consolidated: false
paused: true
paused_at: 2026-09-01
created_at: 2026-09-08
updated_at: 2026-09-08
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active paused"
  assert_not_contains "$OUT" "paused ("
}

test_status_reports_current_task_by_branch() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  run jig status
  assert_contains "$OUT" "current task: none"
  git checkout -q -b feature/x
  run jig task new T-1
  assert_eq 0 "$RC"
  run jig status
  assert_contains "$OUT" "current task: T-1"
  git checkout -q main
  run jig status
  assert_contains "$OUT" "current task: none"
}

# --- pending: framework-owned items an upgrade would install/link now ------
# (stale-install-check task) A skill (or profile/adapter file) added to the
# source is invisible to drift above, since drift only walks paths already
# recorded in .ai/manifest — and in link mode the manifest has no path lines
# at all. `jig status` must surface this instead of reporting a clean
# "drift: 0 modified, 0 missing" while a real gap sits unreported.
#
# jig_installed (not jig) is used throughout so the pending count reflects
# a controlled, disposable source copy ($src) via .ai/manifest's recorded
# `source:` header, rather than whatever this checkout's own working tree
# happens to look like right now (jig_source_root would auto-detect the
# live $JIG_HOME checkout when run as `jig`, sidestepping $src entirely).

test_status_reports_pending_after_skill_added_to_source() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" >/dev/null

  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 0 pending"

  mkdir -p "$src/skills/jig-newthing"
  cat > "$src/skills/jig-newthing/SKILL.md" <<'EOF'
---
name: jig-newthing
description: fixture skill added to the source after init
---
# jig-newthing
Run `/jig-newthing` to do the thing.
EOF

  # Two pending items: one per default adapter (claude, codex), each with
  # its own installed copy of the skill.
  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 2 pending"

  jig_installed upgrade >/dev/null

  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 0 pending"

  rm -rf "$src"
}

# Same reproduction in link mode: this is the exact bug report (a new skill
# under skills/ invisible until `jig upgrade` links it, with drift staying
# "0 modified, 0 missing" throughout since link mode's manifest carries no
# path lines to drift against at all).
test_status_link_mode_reports_pending_after_skill_added_to_source() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" --link >/dev/null

  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 0 pending"

  mkdir -p "$src/skills/jig-newthing"
  cat > "$src/skills/jig-newthing/SKILL.md" <<'EOF'
---
name: jig-newthing
description: fixture skill added to the source after init (link mode)
---
# jig-newthing
Run `/jig-newthing` to do the thing.
EOF

  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 2 pending"

  jig_installed upgrade >/dev/null

  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 0 pending"

  rm -rf "$src"
}

# A copy-mode install whose source checkout no longer exists on this
# machine is a normal state (SPEC §32), not an error: the pending count is
# unknown, so it is omitted from the line entirely rather than misreported
# as "0 pending" (which would read as "checked, nothing pending").
test_status_omits_pending_when_source_root_unknown() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-del.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" >/dev/null
  rm -rf "$src"

  run jig_installed status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing"
  assert_not_contains "$OUT" "pending"
}
