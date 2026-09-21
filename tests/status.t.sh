# Tests for `jig status` (ARCHITECTURE.md, Scripts layout).
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

# --- config.local (ADR-0038) --------------------------------------------------

test_status_omits_config_local_lines_when_there_is_no_local_file() {
  fixture_jig_repo
  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "config.local:"
}

test_status_reports_local_config_keys_when_gitignored() {
  fixture_jig_repo
  cat > .ai/config.local.yaml <<'EOF'
housekeeping.cadence: 3d
git.base_branch: other
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config.local: housekeeping.cadence=3d"
  assert_contains "$OUT" "config.local: ignored git.base_branch (not a local key)"
  assert_not_contains "$OUT" "not ignored by git"
}

# verify.full_run is not in JIG_CFG_LOCAL_KEYS (config.sh, ADR-0038): a
# contributor cannot flip the CI-backed narrowing mode for themselves alone,
# and `jig status` must name it as ignored, like any other non-local key.
test_status_reports_verify_full_run_in_local_config_as_ignored() {
  fixture_jig_repo
  cat > .ai/config.local.yaml <<'EOF'
verify.full_run: ci
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "config.local: ignored verify.full_run (not a local key)"
}

# --- agent.git (design.md, .ai/specs/autopilot/) ------------------------------

test_status_reports_agent_git_none_by_default() {
  fixture_jig_repo
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: none (review queue: uncommitted files)"
}

test_status_reports_agent_git_commit_queue() {
  fixture_jig_repo
  printf 'agent.git: commit\n' > .ai/config.local.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: commit (review queue: unpushed commits)"
}

test_status_reports_agent_git_push_queue() {
  fixture_jig_repo
  printf 'agent.git: push\n' > .ai/config.local.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: push (review queue: pushed branches without a pull request)"
}

test_status_reports_agent_git_pr_queue() {
  fixture_jig_repo
  printf 'agent.git: pr\n' > .ai/config.local.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: pr (review queue: open pull requests)"
}

test_status_reports_agent_git_invalid_value() {
  fixture_jig_repo
  printf 'agent.git: yolo\n' > .ai/config.local.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: invalid value yolo (expected none|commit|push|pr)"
}

# A value committed to .ai/config.yaml would hand every contributor's agent
# the same git rights (JIG_CFG_LOCAL_ONLY_KEYS, config.sh); `jig status` must
# say so rather than silently do nothing.
test_status_warns_when_agent_git_is_set_in_project_config() {
  fixture_jig_repo
  printf 'agent.git: pr\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: agent.git in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
  # The effective level still comes from the default, not the ignored value.
  assert_contains "$OUT" "agent.git: none (review queue: uncommitted files)"
}

test_status_warns_when_agent_git_is_set_in_project_config_even_without_a_local_file() {
  fixture_jig_repo
  printf 'agent.git: commit\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: agent.git in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
}

test_status_warns_when_local_config_is_not_gitignored() {
  fixture_jig_repo
  printf 'housekeeping.cadence: 3d\n' > .ai/config.local.yaml
  grep -v 'config.local.yaml' .gitignore > .gitignore.tmp
  mv .gitignore.tmp .gitignore

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: .ai/config.local.yaml is not ignored by git and can be committed (fix: jig init)"
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
# line sits between drift and the task lines (ARCHITECTURE.md, Scripts layout).

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

# --- sources changed: a linked source edited after acceptance (linked-sources-
# reach-agents, amending ADR-0036) --------------------------------------------
# An accepted stub hands agents whatever its source says now; a source edited
# since acceptance is still read, but nobody has approved that text for
# agents yet. Without this line `proposals: none` would be the only signal
# `jig status` gives that something in .ai/knowledge/ needs a human.

test_status_omits_sources_changed_line_when_nothing_changed() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p docs
  printf 'line one\n' > docs/x.md
  git add docs/x.md
  git commit -q -m "add docs/x.md"
  jig knowledge new convention stub --source docs/x.md --proposed --domains a >/dev/null
  jig knowledge accept convention-stub >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "sources changed:"
}

test_status_reports_sources_changed_count() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p docs
  printf 'line one\n' > docs/x.md
  git add docs/x.md
  git commit -q -m "add docs/x.md"
  jig knowledge new convention stub --source docs/x.md --proposed --domains a >/dev/null
  jig knowledge accept convention-stub >/dev/null
  printf 'line two\n' >> docs/x.md

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "sources changed: 1 (jig knowledge sources)"
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

test_status_appends_blocking_count_for_a_task_with_an_open_p1_finding() {
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
  printf 'F1\tP1\topen\ta.sh:1\tsomething wrong\t2026-09-08\t\n' \
    > .ai/workspace/tasks/TASK-1/findings

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active blocking=1"
}

test_status_omits_blocking_when_findings_do_not_block() {
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
  printf 'F1\tP2\topen\ta.sh:1\tminor\t2026-09-08\t\n' \
    > .ai/workspace/tasks/TASK-1/findings

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active"
  assert_not_contains "$OUT" "blocking="
}

# review receipt (design.md, review-receipt) ---------------------------------

test_status_marks_review_stale_for_a_task_with_a_stale_receipt() {
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
  # A receipt whose tree cannot match anything real: any working tree makes
  # this stale, without depending on hashing the fixture's own files.
  cat > .ai/workspace/tasks/TASK-1/receipt <<'EOF'
stage: review
reviewed_at: 2026-09-08
tree: 0000000000000000000000000000000000000000
base_commit: 0000000000000000000000000000000000000000
head: 0000000000000000000000000000000000000000
design: -
findings: -
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active review=stale"
}

test_status_omits_review_stale_when_the_receipt_is_current() {
  fixture_jig_repo
  jig task new TASK-1 --class T2 >/dev/null
  jig task start TASK-1 >/dev/null
  jig task receipt TASK-1 --stage review >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active"
  assert_not_contains "$OUT" "review=stale"
}

test_status_omits_review_stale_when_there_is_no_receipt_at_all() {
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
  assert_not_contains "$OUT" "review=stale"
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
  # Two tasks on one branch, which branch-per-task otherwise prevents.
  sed 's|^git.branch_per_task:.*|git.branch_per_task: false|' .ai/config.yaml > c.tmp
  mv c.tmp .ai/config.yaml
  jig task new T-1 >/dev/null; jig task start T-1 >/dev/null
  jig task new T-2 >/dev/null; jig task start T-2 >/dev/null

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
  jig task new T-1 >/dev/null
  run jig task start T-1
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
  skip_unless_symlinks
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
# machine is a normal state (domains/install), not an error: the pending count is
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

# --- framework versions: project vs global (design.md §3-4) ----------------
#
# `jig status`'s "framework versions" line depends on `command -v jig`, so
# every test here must build its own PATH (domains/verify: "a test decides
# its own environment; it never inherits one") — otherwise it would see a
# maintainer's real ~/.local/bin/jig on a dev machine, or find none at all on
# a CI runner, and the same assertion would pass or fail depending on who ran
# it. `jig()` here calls "$JIG_BIN" directly, bypassing PATH entirely, so the
# fixture PATH only has to fool the *inner* `command -v jig` these tests
# exercise, via `run env PATH=... "$JIG_BIN" status`.

# _status_path_without_jig [prepend-dir] — the current PATH with every
# directory that contains an executable named `jig` removed (so neither a
# maintainer's real global install nor a stray unrelated `jig` reaches the
# command under test), optionally with <prepend-dir> placed first.
_status_path_without_jig() {
  local prepend="${1:-}" dir out="" IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] || continue
    [ -x "$dir/jig" ] && continue
    out="$out:$dir"
  done
  out="${out#:}"
  if [ -n "$prepend" ]; then
    printf '%s:%s\n' "$prepend" "$out"
  else
    printf '%s\n' "$out"
  fi
}

# _status_make_stub_global <root-dir> <bin-dir> <version-file> — a fixture
# "global framework": a directory shaped like a source checkout (skills/,
# templates/, scripts/jig — jig_is_source_root's test). Prints the directory
# a caller must put on PATH to reach it: <bin-dir>, symlinked to
# <root-dir>/scripts/jig the way the installer places it (design.md §1), when
# `ln -s` makes a real link here; <root-dir>/scripts directly when it does
# not (Windows Git Bash copies instead of linking, and jig_global_executable
# only ever recognises a path ending in /scripts/jig — install.sh's own PATH
# fallback exists for the same reason). <version-file> is written verbatim to
# scripts/lib/version.sh, so a caller can declare a well-formed
# `JIG_VERSION="X.Y.Z"` or a deliberately broken file.
#
# `status` reads that file and must never run the executable (design.md §3):
# the stub's scripts/jig leaves an `executed` marker and prints a version that
# disagrees with the file, so running it would show up either way.
_status_make_stub_global() {
  local root="$1" bin="$2" version_file="$3"
  mkdir -p "$root/skills" "$root/templates" "$root/scripts/lib" "$bin"
  printf '%s\n' "$version_file" > "$root/scripts/lib/version.sh"
  cat > "$root/scripts/jig" <<EOF
#!/bin/sh
: > "$root/executed"
printf 'jig 0.0.0-from-running\n'
EOF
  chmod +x "$root/scripts/jig"
  if ln -s "$root/scripts/jig" "$bin/jig" 2>/dev/null && [ -L "$bin/jig" ]; then
    printf '%s\n' "$bin"
  else
    rm -f "$bin/jig"
    printf '%s\n' "$root/scripts"
  fi
}

# The project's own installed version, read from the real JIG_VERSION rather
# than hardcoded, so this test does not drift the day the source bumps it.
_status_project_version() {
  sed -n 's/^JIG_VERSION="\(.*\)"/\1/p' "$JIG_HOME/scripts/lib/version.sh" | head -n 1
}

# git status --porcelain plus the content hash of every file under .ai,
# batched through one `git hash-object --stdin-paths` (shell conventions: no
# per-file loop). Used by AC-06 to prove `jig status` changed nothing.
_status_project_hash() {
  { git status --porcelain
    find .ai -type f 2>/dev/null | LC_ALL=C sort | git hash-object --stdin-paths
  }
}

test_status_framework_versions_current() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version stub_root stub_bin path_dir
  version=$(_status_project_version)
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" "JIG_VERSION=\"$version\"")

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=$version current"
  assert_not_contains "$OUT" "hint: "
  # Read, never run: a hanging global checkout must not be able to hang status.
  assert_no_file "$stub_root/executed" "status executed the global jig"

  rm -rf "$stub_root" "$stub_bin"
}

test_status_framework_versions_mismatch_global_newer() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version stub_root stub_bin path_dir
  version=$(_status_project_version)
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="9.0.0"')

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=9.0.0 mismatch"
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'hint: the global framework is newer; run `jig upgrade --dry-run`'

  rm -rf "$stub_root" "$stub_bin"
}

test_status_framework_versions_mismatch_project_newer() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version stub_root stub_bin path_dir
  version=$(_status_project_version)
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="0.0.1"')

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=0.0.1 mismatch"
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'hint: the project is newer than the global framework; run `jig self-update`'

  rm -rf "$stub_root" "$stub_bin"
}

test_status_framework_versions_non_release_global_gets_generic_hint() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version stub_root stub_bin path_dir
  version=$(_status_project_version)
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="dev"')

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=dev mismatch"
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'hint: run `jig self-update`, then `jig upgrade --dry-run`'

  rm -rf "$stub_root" "$stub_bin"
}

test_status_framework_versions_no_global_on_path() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version
  version=$(_status_project_version)

  run env PATH="$(_status_path_without_jig)" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=unavailable"
  assert_not_contains "$OUT" "hint: "
}

test_status_framework_versions_non_source_jig_is_unavailable() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version plain_bin
  version=$(_status_project_version)
  plain_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-plainbin.XXXXXX")
  cat > "$plain_bin/jig" <<'EOF'
#!/bin/sh
[ "$1" = version ] && printf 'jig 9.9.9\n'
EOF
  chmod +x "$plain_bin/jig"

  run env PATH="$(_status_path_without_jig "$plain_bin")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=unavailable"
  assert_not_contains "$OUT" "hint: "

  rm -rf "$plain_bin"
}

test_status_framework_versions_two_declared_versions_are_unavailable() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version stub_root stub_bin
  version=$(_status_project_version)
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  # Two declarations are not one version: jig_declared_version accepts exactly
  # one `JIG_VERSION="<version>"` line.
  _status_make_stub_global "$stub_root" "$stub_bin" "JIG_VERSION=\"$version\"
JIG_VERSION=\"9.9.9\""

  run env PATH="$(_status_path_without_jig "$stub_bin")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=unavailable"
  assert_not_contains "$OUT" "hint: "

  rm -rf "$stub_root" "$stub_bin"
}

test_status_framework_versions_malformed_version_file_is_unavailable() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version stub_root stub_bin
  version=$(_status_project_version)
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  # Unquoted: not the shape version.sh declares, so it is not read as a version.
  _status_make_stub_global "$stub_root" "$stub_bin" "JIG_VERSION=9.9.9"

  run env PATH="$(_status_path_without_jig "$stub_bin")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=unavailable"
  assert_not_contains "$OUT" "hint: "

  rm -rf "$stub_root" "$stub_bin"
}

# AC-11: in link mode the global executable can be the very checkout this
# project links against; that is a normal "current", not a missing global.
test_status_framework_versions_link_mode_reports_current() {
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  local version stub_bin
  version=$(_status_project_version)
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  ln -s "$JIG_HOME/scripts/jig" "$stub_bin/jig"

  run env PATH="$(_status_path_without_jig "$stub_bin")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "framework versions: project=$version global=$version current"

  rm -rf "$stub_bin"
}

# AC-06: mismatch guidance is purely diagnostic; it must never touch the project.
test_status_framework_versions_mismatch_causes_no_project_mutation() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local stub_root stub_bin path_dir before after
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="9.0.0"')

  before=$(_status_project_hash)
  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "mismatch"
  after=$(_status_project_hash)
  assert_eq "$before" "$after" "jig status must not mutate the project"

  rm -rf "$stub_root" "$stub_bin"
}

# --- session hook and housekeeping flags (domains/housekeeping; ARCHITECTURE.md, Scripts layout) ---------------------

test_status_session_hook_not_installed() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "session hook (claude): not installed"
}

test_status_session_hook_installed() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .claude
  printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": ".ai/scripts/jig-session-hook" } ] } ] } }\n' \
    > .claude/settings.json

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "session hook (claude): installed"
}

test_status_omits_runtimes_that_have_no_session_hook() {
  # Codex has none, so there is nothing to install and nothing to report: a
  # permanent "not installed" line would be noise nobody can clear.
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig status
  assert_not_contains "$OUT" "session hook (codex)"
}

test_status_reports_tasks_needing_consolidation() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/runtime
  printf '2026-09-10T00:00:00Z task=t1 status=active remote=merged via=ancestry action=preserve flags=needs-consolidation\n' \
    > .ai/runtime/housekeeping.log

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "needs consolidation: 1 task(s)"
}

test_status_silent_about_consolidation_when_nothing_is_flagged() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/runtime
  printf '2026-09-10T00:00:00Z task=t1 status=consolidated remote=merged via=ancestry action=purge\n' \
    > .ai/runtime/housekeeping.log

  run jig status
  assert_not_contains "$OUT" "needs consolidation"
}

# --- specs: specifications outside knowledge (jig-idea) ----------------------

test_status_reports_no_specs_by_default() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "specs: none"
}

test_status_reports_spec_count() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/specs/idea-a .ai/specs/idea-b
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/idea-a/roadmap.md
  printf '%s\n' '# Idea B' > .ai/specs/idea-b/spec.md
  # idea-b has no roadmap.md: an incomplete spec still counts.

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "specs: 2 (jig spec list)"
  assert_not_contains "$OUT" "specs: none"
}

test_status_does_not_count_invalid_id_spec_directories() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/specs/idea-a
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/idea-a/roadmap.md
  mkdir -p .ai/specs/.hidden

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "specs: 1 (jig spec list)"
}

# --- status: open epics (ADR-0040) ---------------------------------------------
# One line per spec with an open epic, right after the specs: line: how far
# behind the default branch it has fallen. A clean tree is needed throughout,
# for the same reason as spec.t.sh's epic_setup: `jig spec epic` checks out
# and branches.

status_epic_setup() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  git add -A
  git commit -q -m "jig init snapshot"
}

test_status_shows_open_epic_with_commits_behind() {
  status_epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null
  # Advance main two commits past the epic's fork point.
  printf 'a\n' > a.txt
  git add a.txt
  git commit -q -m "a"
  printf 'b\n' > b.txt
  git add b.txt
  git commit -q -m "b"

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "epic: idea-x on epic/idea-x, 2 commits behind main"
}

test_status_shows_epic_branch_missing() {
  status_epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  # The Epic: line reached main, but the branch itself was never cut.

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "epic: idea-x on epic/idea-x, branch missing"
}

test_status_finished_epic_has_no_epic_line() {
  status_epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null
  git checkout -q epic/idea-x
  jig spec epic idea-x --finish --leftovers-handled >/dev/null 2>&1

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "epic: idea-x"
}

test_status_no_epic_has_no_epic_line() {
  status_epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"

  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "epic:"
}

# --- task worktrees (ADR-0029) -------------------------------------------------

test_status_shows_where_a_task_started_in_a_worktree_is() {
  mkdir repo || return 1
  cd repo || return 1
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init snapshot"
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  printf 'a\n' > "$wt/a.txt"
  printf 'b\n' > "$wt/b.txt"

  run jig status
  assert_contains "$OUT" "task T-1 class= status=active worktree=$wt uncommitted=2"
  # It is not current here: its branch is checked out elsewhere.
  assert_contains "$OUT" "current task: none"
}

# --- instruction files (adapter_<a>_instructions_hint) ------------------------

test_status_instructions_ok_after_fresh_init() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig status
  assert_contains "$OUT" "instructions (claude): ok"
  assert_contains "$OUT" "instructions (codex): ok"
}

test_status_instructions_reports_a_kept_foreign_agents() {
  fixture_repo
  printf '# Our own rules\n' > AGENTS.md
  jig init --from "$JIG_HOME" >/dev/null
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "instructions (codex): no Jig section in AGENTS.md"
  assert_contains "$OUT" "instructions (claude): no Jig section in CLAUDE.md"
}

test_status_instructions_reports_a_missing_agents_md() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  rm AGENTS.md
  run jig status
  assert_contains "$OUT" "instructions (codex): no Jig section in AGENTS.md"
  assert_contains "$OUT" "instructions (claude): no Jig section in CLAUDE.md"
}

# --- the status page: `jig status --html` (.ai/specs/autopilot/, Phase 5) ------

test_status_rejects_an_unknown_argument() {
  fixture_jig_repo
  run jig status --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "status: unknown argument: --bogus"
}

test_status_html_refuses_an_uninitialised_project() {
  fixture_repo
  run jig status --html
  assert_eq 1 "$RC"
  assert_contains "$OUT" "status --html: project is not initialised; run: jig init"
  assert_no_file .ai
}

test_status_html_writes_one_file_prints_its_path_and_changes_nothing_else() {
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init snapshot"
  local before
  before=$(git status --porcelain --ignored)

  run jig status --html
  assert_eq 0 "$RC"
  assert_eq "$(pwd -P)/.ai/runtime/status.html" "$OUT"
  assert_file .ai/runtime/status.html
  assert_eq "status.html" "$(ls .ai/runtime)" "nothing but the page in .ai/runtime"
  assert_eq "$before" "$(git status --porcelain --ignored | grep -v '^!! .ai/runtime/' || true)"

  # A second run replaces the page rather than adding another.
  run jig status --html
  assert_eq 0 "$RC"
  assert_eq "status.html" "$(ls .ai/runtime)"
}

test_status_html_is_self_contained_and_follows_the_colour_scheme() {
  fixture_jig_repo
  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" "<!DOCTYPE html>"
  assert_contains "$page" '<meta charset="utf-8">'
  assert_contains "$page" "<style>"
  assert_contains "$page" "@media (prefers-color-scheme: dark)"
  assert_not_contains "$page" "http://"
  assert_not_contains "$page" "https://"
  assert_not_contains "$page" "src="
  assert_not_contains "$page" "href="
  assert_not_contains "$page" "<script"
  assert_not_contains "$page" "<link"
  assert_not_contains "$page" "<img"
  assert_not_contains "$page" "@import"
  assert_not_contains "$page" "url("
}

test_status_html_empty_project_shows_every_section_and_its_empty_state() {
  fixture_jig_repo
  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" '<section id="summary">'
  assert_contains "$page" '<section id="tasks">'
  assert_contains "$page" '<section id="specs">'
  assert_contains "$page" '<section id="report">'
  assert_contains "$page" "No active tasks."
  assert_contains "$page" "No specifications."
  assert_contains "$page" "<dt>Housekeeping last ran</dt><dd>never</dd>"
  assert_contains "$page" "<dt>Current task</dt><dd>none</dd>"
  # The whole text report is on the page too.
  assert_contains "$page" "initialised: yes"
  assert_contains "$page" "no active tasks"
}

test_status_html_shows_findings_lines_and_every_receipt_state() {
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init snapshot"
  jig task new blocked --class T2 >/dev/null
  jig task new reviewed --class T2 >/dev/null
  jig task start reviewed >/dev/null
  jig task receipt reviewed --stage review >/dev/null
  jig task new t4-unreviewed --class T4 >/dev/null
  jig task new t2-unreviewed --class T2 >/dev/null
  printf 'F1\tP1\topen\ta.sh:1\tsomething wrong\t2026-09-08\t\nF2\tP2\topen\tb.sh:2\tminor\t2026-09-08\t\nF3\tP0\tfixed\t-\tworse\t2026-09-08\t\n' \
    > .ai/workspace/tasks/blocked/findings
  cat > .ai/workspace/tasks/blocked/receipt <<'EOF2'
stage: review
reviewed_at: 2026-09-08
tree: 0000000000000000000000000000000000000000
base_commit: 0000000000000000000000000000000000000000
head: 0000000000000000000000000000000000000000
design: -
findings: -
EOF2

  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  # The blocking lines exactly as _task_blocking_findings prints them; a P2
  # does not block and is not listed.
  assert_contains "$page" "<li><code>F1 P1 open a.sh:1</code></li>"
  assert_contains "$page" "<li><code>F3 P0 fixed -</code></li>"
  assert_not_contains "$page" "F2 P2"
  assert_contains "$page" "jig task findings blocked"
  # Receipt states as `jig task receipt --check` answers them.
  assert_contains "$page" '<span class="badge bad">stale (tree, findings, reviewed 2026-09-08)</span>'
  assert_contains "$page" '<span class="badge ok">current</span>'
  assert_contains "$page" '<span class="badge bad">none (required for T4)</span>'
  assert_contains "$page" '<span class="badge">none</span>'
  assert_contains "$page" '<td class="id"><code>t2-unreviewed</code></td><td>T2</td><td>active</td><td>main</td>'
}

test_status_html_lists_many_tasks_and_counts_finished_ones() {
  fixture_jig_repo
  local i
  for i in 1 2 3 4 5 6 7 8; do
    fixture_task "live-$i" "task/live-$i" active "class:T1"
  done
  fixture_task done-1 task/done-1 consolidated
  fixture_task gone-1 task/gone-1 abandoned
  fixture_task waiting task/waiting active "paused:true" "paused_reason:waiting for review" "base_branch:epic/x"

  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  for i in 1 2 3 4 5 6 7 8; do
    assert_contains "$page" "<code>live-$i</code>"
  done
  assert_not_contains "$page" "<code>done-1</code>"
  assert_not_contains "$page" "<code>gone-1</code>"
  assert_contains "$page" "2 finished, not listed"
  assert_contains "$page" '<span class="badge warn">paused</span> <span class="muted">waiting for review</span>'
  assert_contains "$page" "<td>epic/x</td>"
}

test_status_html_shows_where_a_task_started_in_a_worktree_is() {
  mkdir repo || return 1
  cd repo || return 1
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init snapshot"
  jig task new T-1 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  printf 'a\n' > "$wt/a.txt"

  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" "<code>$wt</code><br><span class=\"muted\">1 uncommitted</span>"
}

test_status_html_shows_spec_progress_as_spec_list_answers_it() {
  fixture_jig_repo
  mkdir -p .ai/specs/idea-a .ai/specs/idea-b
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md
  # shellcheck disable=SC2016 # a backticked task id, literal
  printf '%s\n' '- [x] one' '- [ ] `live-1` — two' '- [ ] fog: three' > .ai/specs/idea-a/roadmap.md
  printf '%s\n' '# Idea B' > .ai/specs/idea-b/spec.md

  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" "<tr><td><code>idea-a</code></td><td>Idea A</td><td>roadmap 1/3 done, 1 filed, fog 1</td></tr>"
  assert_contains "$page" "<tr><td><code>idea-b</code></td><td>Idea B</td><td>incomplete (no roadmap.md)</td></tr>"
  assert_not_contains "$page" "No specifications."
}

test_status_html_summary_flags_what_needs_attention() {
  fixture_jig_repo
  mkdir -p .ai/runtime
  printf '2026-09-10T00:00:00Z task=t1 status=active remote=merged via=ancestry action=preserve flags=needs-consolidation\n' \
    > .ai/runtime/housekeeping.log

  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" '<div class="item attention"><dt>Needs consolidation</dt><dd>1</dd></div>'
  assert_contains "$page" '<div class="item"><dt>Worktrees kept</dt><dd>none</dd></div>'
  assert_contains "$page" '<div class="item"><dt>Knowledge awaiting decision</dt><dd>none</dd></div>'
}

test_status_html_escapes_every_value_people_wrote() {
  fixture_jig_repo
  fixture_task esc task/esc active "class:T2" "paused:true" "paused_reason:<b>wait</b> & see"
  printf 'F1\tP1\topen\t<script>alert(1)</script> & "q" '"'"'s\tx\t2026-09-08\t\n' \
    > .ai/workspace/tasks/esc/findings
  mkdir -p .ai/specs/idea
  printf '%s\n' '# <i>Idea</i> & "co"' > .ai/specs/idea/spec.md
  printf '%s\n' '- [ ] one' > .ai/specs/idea/roadmap.md

  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_not_contains "$page" "<script>"
  assert_not_contains "$page" "<b>wait</b>"
  assert_not_contains "$page" "<i>Idea</i>"
  assert_contains "$page" "F1 P1 open &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;q&quot; &#39;s"
  assert_contains "$page" "&lt;b&gt;wait&lt;/b&gt; &amp; see"
  assert_contains "$page" "&lt;i&gt;Idea&lt;/i&gt; &amp; &quot;co&quot;"
  # The embedded text report is escaped too: its task line carries the reason.
  assert_contains "$page" "paused (&lt;b&gt;wait&lt;/b&gt; &amp; see)"
}

test_status_html_leaves_plain_status_output_unchanged() {
  fixture_jig_repo
  fixture_task t1 task/t1 active "class:T2"
  run jig status
  local plain="$OUT"
  jig status --html >/dev/null
  run jig status
  assert_eq "$plain" "$OUT"
}

test_status_html_names_open_epics_as_status_does() {
  status_epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"

  run jig status --html
  assert_eq 0 "$RC"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" "<li>epic: idea-x on epic/idea-x, branch missing</li>"
  assert_contains "$page" "<td>epic/idea-x — branch missing</td>"
}
