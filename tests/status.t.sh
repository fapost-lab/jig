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

test_status_reports_agent_git_merge_queue() {
  fixture_jig_repo
  printf 'agent.git: merge\n' > .ai/config.local.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: merge (review queue: pull requests left open: red or silent CI, a draft, branch protection)"
}

# autopilot.unattended and agent.ci_timeout decide what one person's agent does
# for them, like agent.git: a project value is ignored, and said so.
test_status_warns_when_unattended_keys_are_set_in_project_config() {
  fixture_jig_repo
  printf 'autopilot.unattended: true\nagent.ci_timeout: 5\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "config.local: autopilot.unattended in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
  assert_contains "$OUT" \
    "config.local: agent.ci_timeout in .ai/config.yaml is ignored (set it in .ai/config.local.yaml)"
}

test_status_reports_agent_git_invalid_value() {
  fixture_jig_repo
  printf 'agent.git: yolo\n' > .ai/config.local.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "agent.git: invalid value yolo (expected none|commit|push|pr|merge)"
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
    # Everything but the two records a checkout keeps about itself: every
    # jig run rewrites them and they say nothing about the project
    # (adr-20260924-a-checkout-records-what-is-happening-in-it).
    find .ai -type f ! -path '.ai/runtime/checkout' ! -path '.ai/runtime/working/*' \
      2>/dev/null | LC_ALL=C sort | git hash-object --stdin-paths
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

# Connected is not the same as reachable: a section nothing updates goes stale
# where nobody looks, so `jig status` names that state separately
# (adr-20260924-jig-owns-a-marked-section-of-the-instructions).
test_status_instructions_reports_an_unmarked_section() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  grep -v 'jig:begin\|jig:end' AGENTS.md > AGENTS.md.new
  mv AGENTS.md.new AGENTS.md
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "instructions (codex): Jig section in AGENTS.md is not marked"
  assert_contains "$OUT" "upgrades cannot reach it"
}

test_status_instructions_reports_a_changed_section() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  sed 's/^## Read first$/## Read first (our version)/' AGENTS.md > AGENTS.md.new
  mv AGENTS.md.new AGENTS.md
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "instructions (codex): Jig section in AGENTS.md was changed here"
}

# --- autopilot (design.md under .ai/workspace/tasks/autopilot-run) -------------

test_status_marks_autopilot_on_for_a_running_task() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/workspace/tasks/TASK-1
  cat > .ai/workspace/tasks/TASK-1/state <<'EOF'
task_id: TASK-1
branch: feature/TASK-1
class: T2
status: active
knowledge_consolidated: false
autopilot: on
autopilot_repairs: 0
created_at: 2026-09-08
updated_at: 2026-09-08
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active autopilot=on"
}

test_status_marks_autopilot_stopped_for_a_stopped_run() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/workspace/tasks/TASK-1
  cat > .ai/workspace/tasks/TASK-1/state <<'EOF'
task_id: TASK-1
branch: feature/TASK-1
class: T2
status: active
knowledge_consolidated: false
autopilot: stopped
autopilot_repairs: 2
created_at: 2026-09-08
updated_at: 2026-09-08
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active autopilot=stopped"
}

test_status_omits_autopilot_marker_when_the_run_is_done() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  mkdir -p .ai/workspace/tasks/TASK-1
  cat > .ai/workspace/tasks/TASK-1/state <<'EOF'
task_id: TASK-1
branch: feature/TASK-1
class: T2
status: active
knowledge_consolidated: false
autopilot: done
autopilot_repairs: 0
created_at: 2026-09-08
updated_at: 2026-09-08
EOF

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active"
  assert_not_contains "$OUT" "autopilot="
}

test_status_omits_autopilot_marker_when_no_run_was_ever_started() {
  fixture_jig_repo
  jig task new TASK-1 --class T2 >/dev/null
  jig task start TASK-1 >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active"
  assert_not_contains "$OUT" "autopilot="
}

test_status_reflects_a_real_autopilot_run_through_start_and_stop() {
  fixture_jig_repo
  jig task new TASK-1 --class T2 >/dev/null
  jig task start TASK-1 >/dev/null
  jig task autopilot TASK-1 start >/dev/null

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "autopilot=on"

  jig task autopilot TASK-1 stop --reason "human gate" >/dev/null
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "autopilot=stopped"
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
  # The page, the counts its redraws reuse, and the record every jig run
  # leaves saying a session is working in this checkout
  # (adr-20260924-a-checkout-records-what-is-happening-in-it) — nothing else.
  assert_eq "checkout
status-counts
status.html" "$(ls .ai/runtime)" "nothing but the page, its counts and the checkout record"
  assert_eq "$before" "$(git status --porcelain --ignored | grep -v '^!! .ai/runtime/' || true)"

  # A second run replaces the page rather than adding another.
  run jig status --html
  assert_eq 0 "$RC"
  assert_eq "checkout
status-counts
status.html" "$(ls .ai/runtime)"
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
  # One inline script, with no attributes, and nothing it could load from.
  assert_eq 1 "$(printf '%s\n' "$page" | grep -c '<script')"
  assert_contains "$page" "<script>
(function () {"
  assert_not_contains "$page" "fetch("
  assert_not_contains "$page" "XMLHttpRequest"
  assert_not_contains "$page" "innerHTML"
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
  assert_contains "$page" '<section id="needs">'
  assert_contains "$page" '<section id="summary">'
  assert_contains "$page" '<section id="tasks">'
  assert_contains "$page" '<section id="specs">'
  assert_contains "$page" '<section id="report">'
  assert_contains "$page" '<p class="nothing">Nothing needs you right now.</p>'
  assert_contains "$page" "Nothing is running."
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
  assert_contains "$page" '<td class="id"><code>t2-unreviewed</code></td><td>T2</td><td>active</td><td><span class="muted">filed, not started</span></td><td class="muted">-</td>'
}

# --- the Base column: the Task Base, or nothing -------------------------------
#
# The base is recorded by `jig task start` (_task_start_base) and by nothing
# else, and it is not always `git.base_branch`: a task linked to a spec with an
# open epic is cut from the epic. The page used to substitute the project
# default for a task that had not started, which shows a guess as a fact and
# can be the wrong branch. The text page and `jig task list` never did.

test_status_html_base_column_is_empty_until_the_task_starts() {
  fixture_jig_repo
  fixture_task filed task/filed active "class:T1"
  fixture_task started task/started active "class:T1" "base_branch:main"
  fixture_task on-epic task/on-epic active "class:T1" "base_branch:epic/autopilot"
  # A filed task has no base at all, which fixture_task models by omission.
  sed '/^base_branch:/d' .ai/workspace/tasks/filed/state > .ai/workspace/tasks/filed/state.new
  mv .ai/workspace/tasks/filed/state.new .ai/workspace/tasks/filed/state

  run jig status --html
  assert_eq 0 "$RC"
  # One row per line (_status_html_task_row), so a row can be asserted whole.
  local page row
  page=$(cat .ai/runtime/status.html)
  row=$(printf '%s\n' "$page" | grep '<code>filed</code>') || fail "no row for filed"
  # The Base cell, then the Worktree cell: both empty, both muted.
  assert_contains "$row" '<td class="muted">-</td><td class="muted">-</td>'
  assert_not_contains "$row" '<td>main</td>'
  # A recorded base is still printed, the project's own included.
  row=$(printf '%s\n' "$page" | grep '<code>started</code>') || fail "no row for started"
  assert_contains "$row" '<td>main</td>'
  row=$(printf '%s\n' "$page" | grep '<code>on-epic</code>') || fail "no row for on-epic"
  assert_contains "$row" '<td>epic/autopilot</td>'
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
  assert_eq 1 "$(printf '%s\n' "$page" | grep -c '<script>')"
  assert_not_contains "$page" "<script>alert"
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

test_status_html_shows_the_autopilot_state_the_text_report_shows() {
  fixture_jig_repo
  jig task new TASK-1 --class T2 >/dev/null
  jig task start TASK-1 >/dev/null
  run jig status --html
  assert_not_contains "$(cat .ai/runtime/status.html)" ">autopilot"

  jig task autopilot TASK-1 start >/dev/null
  run jig status --html
  assert_eq 0 "$RC"
  assert_contains "$(cat .ai/runtime/status.html)" '<span class="badge">autopilot</span>'

  jig task autopilot TASK-1 stop --reason "human gate" >/dev/null
  run jig status --html
  assert_contains "$(cat .ai/runtime/status.html)" '<span class="badge warn">autopilot stopped</span>'
}

# --- the live status page (adr-20260924-the-status-page-keeps-the-readers-place)

# status_page_section <page> <id> — one <section> of the page, by its id.
status_page_section() {
  printf '%s\n' "$1" | awk -v id="$2" '
    index($0, "<section id=\"" id "\">") == 1 { on = 1 }
    on { print }
    on && $0 == "</section>" { exit }
  '
}

test_status_page_reloads_itself_and_orders_what_needs_you_first() {
  fixture_jig_repo
  run jig status --html
  assert_eq 0 "$RC"
  local page order
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" '<noscript><meta http-equiv="refresh" content="10"></noscript>'
  assert_eq 1 "$(printf '%s\n' "$page" | grep -c 'http-equiv="refresh"')"
  assert_contains "$page" "This page refreshes itself every 10 seconds while it is open"
  assert_contains "$page" "var every = 10 * 1000, quiet = 3000;"
  assert_not_contains "$page" "A snapshot"
  order=$(printf '%s\n' "$page" | sed -n 's/^<section id="\([a-z]*\)">$/\1/p' | tr '\n' ' ')
  assert_eq "needs tasks specs summary report " "$order"
}

test_status_page_keeps_the_readers_place_with_a_pause_hidden_without_script() {
  fixture_jig_repo
  run jig status --html
  assert_eq 0 "$RC"
  local page script
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" '<div id="autorefresh" class="autorefresh" hidden>'
  assert_contains "$page" '<button type="button" id="autorefresh-toggle"></button>'
  assert_contains "$page" '<details id="full-report"><summary>What <code>jig status</code> prints</summary>'
  # The script finds what it restores by id, so no id may be used twice.
  assert_eq "" "$(printf '%s\n' "$page" | grep -o ' id="[^"]*"' | sort | uniq -d)"
  # The script comes after the page it restores, and states only what it
  # keeps: the pause, the open <details> and the scroll offset, per tab.
  assert_eq "</main>" "$(printf '%s\n' "$page" | grep -n -e '^</main>$' -e '^<script>$' | head -n 1 | cut -d: -f2)"
  script=$(printf '%s\n' "$page" | sed -n '/^<script>$/,/^<\/script>$/p')
  assert_contains "$script" "sessionStorage"
  assert_not_contains "$script" "localStorage"
  assert_contains "$script" "location.reload()"
  assert_contains "$script" "document.hidden"
}

test_status_page_refresh_is_silent_and_creates_no_page() {
  fixture_jig_repo
  run jig status --refresh
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
  assert_no_file .ai/runtime/status.html
  assert_no_file .ai/runtime/status-counts
}

test_status_page_refresh_on_an_uninitialised_project_does_nothing() {
  fixture_repo
  run jig status --refresh
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
  assert_no_file .ai
}

test_status_page_names_a_zero_offset_utc_whatever_date_calls_it() {
  # Git Bash's `date` prints %Z as GMT under TZ=UTC; the page says UTC for
  # any +0000 offset and keeps every other zone's own name.
  run bash -c '
    . "$JIG_HOME/scripts/lib/status.sh"
    printf "2026-01-02 03:04 +0000 GMT\n" | _status_zone
    printf "2026-01-02 03:04 +0300 EEST\n" | _status_zone
  '
  assert_eq 0 "$RC"
  assert_eq "2026-01-02 03:04 UTC
2026-01-02 03:04 EEST" "$OUT"
}

test_status_page_refresh_reuses_the_cached_counts_and_says_how_old_they_are() {
  # The page shows times in the reader's zone; pin it.
  export TZ=UTC
  fixture_jig_repo
  jig status --html >/dev/null
  printf 'at: 2026-01-02T03:04:05Z\nproposals: 7\nsources_changed: 2\npending: 3\n' > .ai/runtime/status-counts
  run jig status --refresh
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" "counts from the last full <code>jig status</code> at 2026-01-02 03:04 UTC"
  assert_contains "$page" "Knowledge is waiting for your decision"
  assert_contains "$page" "7 document(s) proposed"
  assert_contains "$page" "2 file(s)"
  assert_contains "$page" "proposals: 7 awaiting decision"
  assert_contains "$page" "drift: 0 modified, 0 missing, 3 pending"
}

test_status_page_refresh_counts_once_when_there_is_no_cache() {
  fixture_jig_repo
  jig status --html >/dev/null
  rm .ai/runtime/status-counts
  run jig status --refresh
  assert_eq 0 "$RC"
  assert_file .ai/runtime/status-counts
  assert_file_contains .ai/runtime/status-counts "proposals: 0"
}

test_status_page_plain_status_refreshes_the_counts_only_once_the_page_exists() {
  fixture_jig_repo
  jig status >/dev/null
  assert_no_file .ai/runtime/status-counts "plain status writes nothing without a page"
  jig status --html >/dev/null
  printf 'at: 2000-01-01T00:00:00Z\nproposals: 9\nsources_changed: 0\npending: 0\n' > .ai/runtime/status-counts
  jig status >/dev/null
  assert_file_contains .ai/runtime/status-counts "proposals: 0"
  assert_not_contains "$(cat .ai/runtime/status-counts)" "2000-01-01"
}

test_status_page_shows_a_stopped_run_first_with_its_reason() {
  fixture_jig_repo
  jig task new run-1 --class T2 >/dev/null
  jig task start run-1 >/dev/null
  jig task new other --class T2 >/dev/null
  jig task autopilot run-1 start >/dev/null
  jig task autopilot run-1 stop --reason "which <db> to use & why" >/dev/null
  run jig status --html
  assert_eq 0 "$RC"
  local page needs
  page=$(cat .ai/runtime/status.html)
  needs=$(status_page_section "$page" needs)
  assert_contains "$needs" 'Autopilot stopped and is waiting for you <span class="badge warn">autopilot stopped</span>'
  assert_contains "$needs" "<code>run-1</code> · which &lt;db&gt; to use &amp; why (just now)"
  assert_contains "$needs" "Answer the agent in this task&#39;s session; it resumes the run."
  # Shown once: a stopped run is a card, not also a row under "Running now".
  assert_not_contains "$(status_page_section "$page" tasks)" "<code>run-1</code>"
}

# A task of a phase run has no session of its own: the coordinator started
# it, and the answer goes back there
# (adr-20260922-a-phase-run-is-coordinated).
test_status_page_sends_a_phase_runs_question_to_the_coordinator() {
  fixture_jig_repo
  jig task new run-1 --class T2 >/dev/null
  jig task start run-1 >/dev/null
  jig task autopilot run-1 start --phase alpha/1 >/dev/null
  jig task autopilot run-1 stop --reason "which index to add" >/dev/null
  run jig status --html
  assert_eq 0 "$RC"
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" 'A phase run is waiting for you <span class="badge warn">autopilot stopped</span>'
  assert_contains "$needs" "Answer in the coordinator&#39;s session; it resumes the task."
  assert_not_contains "$needs" "Answer the agent in this task&#39;s session"
}

# Several stops of one phase are one card: in a phase run the person is asked
# once, about the whole wave.
test_status_page_gathers_a_phases_stops_into_one_card() {
  fixture_jig_repo
  local t
  for t in run-1 run-2; do
    jig task new "$t" --class T2 >/dev/null
    jig task start "$t" >/dev/null
    jig task autopilot "$t" start --phase alpha/1 >/dev/null
    jig task autopilot "$t" stop --reason "question from $t" >/dev/null
  done
  run jig status --html
  local needs n
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  n=$(printf '%s\n' "$needs" | grep -c "A phase run is waiting for you" || true)
  assert_eq 1 "$n" "expected one card for the whole phase, got $n"
  assert_contains "$needs" "run-1 — question from run-1"
  assert_contains "$needs" "run-2 — question from run-2"
  assert_contains "$needs" "Answer in the coordinator&#39;s session; it resumes the tasks."
}

# The "Phase run" section: the waves and free slots are `spec plan`'s answer,
# the tasks are the page's own records.
test_status_page_shows_a_phase_run_with_its_waves_and_slots() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  cat > .ai/specs/alpha/roadmap.md <<'RM'
## Phase 1 — First

- [ ] `run-1` — Alpha — goal
- [ ] `run-2` — Bravo — goal

## Waves

1. Alpha; Bravo
RM
  jig task new run-1 --class T2 >/dev/null
  jig task start run-1 >/dev/null
  jig task new run-2 --class T2 >/dev/null
  jig task start run-2 >/dev/null
  jig task autopilot run-1 start --phase alpha/1 >/dev/null

  run jig status --html
  assert_eq 0 "$RC"
  local phase
  phase=$(status_page_section "$(cat .ai/runtime/status.html)" phase-run)
  assert_contains "$phase" "<h2>Phase run</h2>"
  assert_contains "$phase" "<code>alpha</code> · phase 1"
  assert_contains "$phase" "wave 1 open"
  assert_contains "$phase" "1 of 2 slots free"
  assert_contains "$phase" "<code>run-1</code>"
  # run-2 has no phase run of its own: it is not in this section.
  assert_not_contains "$phase" "<code>run-2</code>"

  # Consolidated work gives its slot back and joins the ship queue.
  jig task set run-1 knowledge_consolidated true >/dev/null
  run jig status --html
  phase=$(status_page_section "$(cat .ai/runtime/status.html)" phase-run)
  assert_contains "$phase" "2 of 2 slots free"
  assert_contains "$phase" "waiting to ship"
}

# No phase run, no section: the page does not grow one for every project.
test_status_page_has_no_phase_run_section_without_one() {
  fixture_jig_repo
  jig task new run-1 --class T2 >/dev/null
  jig task start run-1 >/dev/null
  jig task autopilot run-1 start >/dev/null
  run jig status --html
  assert_eq 0 "$RC"
  assert_not_contains "$(cat .ai/runtime/status.html)" "<h2>Phase run</h2>"
}

test_status_page_puts_a_stopped_run_before_a_design_at_its_gate() {
  fixture_jig_repo
  # Filed first, so the workspaces list it first.
  fixture_task a-gate task/a-gate active "class:T3"
  printf '# Design\n' > .ai/workspace/tasks/a-gate/design.md
  jig task new z-run --class T2 >/dev/null
  jig task start z-run >/dev/null
  jig task autopilot z-run start >/dev/null
  jig task autopilot z-run stop --reason "a question" >/dev/null
  run jig status --html
  local needs order
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  order=$(printf '%s\n' "$needs" | sed -n 's/.*<p><code>\([^<]*\)<.*/\1/p' | tr '\n' ' ')
  assert_eq "z-run a-gate " "$order"
}

test_status_page_shows_the_stage_and_repairs_of_a_running_autopilot() {
  fixture_jig_repo
  jig task new run-1 --class T2 >/dev/null
  jig task start run-1 >/dev/null
  jig task autopilot run-1 start >/dev/null
  run jig status --html
  assert_contains "$(cat .ai/runtime/status.html)" '<span class="badge">autopilot</span> starting'
  jig task autopilot run-1 stage implement >/dev/null
  jig task autopilot run-1 repair --reason "flaky test" >/dev/null
  # A stage reached minutes ago reads as such.
  printf '2026-01-01T00:00:00Z\tstage\tverify\n' >> .ai/workspace/tasks/run-1/autopilot
  run jig status --html
  local tasks
  tasks=$(status_page_section "$(cat .ai/runtime/status.html)" tasks)
  assert_contains "$tasks" '<span class="badge">autopilot</span> verify <span class="muted">for '
  assert_contains "$tasks" '<span class="muted">repairs 1/2</span>'
}

test_status_page_shows_a_design_waiting_at_its_gate_until_it_is_approved() {
  fixture_jig_repo
  jig task new big --class T3 >/dev/null
  jig task start big >/dev/null
  run jig status --html
  assert_not_contains "$(cat .ai/runtime/status.html)" "A design is waiting" "no design yet, nothing to decide"

  printf '# Design\n' > .ai/workspace/tasks/big/design.md
  run jig status --html
  assert_contains "$(status_page_section "$(cat .ai/runtime/status.html)" needs)" \
    "A design is waiting for your decision</h3><p><code>big</code>"

  jig task gate big approved >/dev/null
  local page
  page=$(cat .ai/runtime/status.html)
  assert_not_contains "$page" "A design is waiting"
  assert_contains "$page" '<span class="badge ok">design approved</span>'

  printf 'changed\n' >> .ai/workspace/tasks/big/design.md
  run jig status --html
  assert_contains "$(cat .ai/runtime/status.html)" "A design changed after you approved it"
}

test_status_page_shows_a_finished_task_waiting_for_the_readers_git_step() {
  fixture_jig_repo
  fixture_task done-1 task/done-1 ready "class:T2" "knowledge_consolidated:true"
  fixture_task early task/early ready "class:T2"
  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "Ready for your step in git</h3><p><code>done-1</code> · agent.git: none"
  assert_contains "$needs" "Review the changes and commit them"
  # `ready` before the knowledge decision is still the agent's to finish.
  assert_not_contains "$needs" "<code>early</code>"

  printf 'agent.git: push\n' > .ai/config.local.yaml
  run jig status --html
  assert_contains "$(cat .ai/runtime/status.html)" "Open a pull request for the task&#39;s branch"
}

test_status_page_links_a_pull_request_jig_opened_and_one_housekeeping_saw() {
  fixture_jig_repo
  fixture_task shipped task/shipped ready "class:T2" "knowledge_consolidated:true" \
    "pr_url:https://example.com/o/r/pull/7"
  fixture_task waiting task/waiting consolidated "class:T2"
  fixture_task landed task/landed ready "class:T2" "knowledge_consolidated:true" \
    "pr_url:https://example.com/o/r/pull/8"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-22T00:00:00Z task=waiting status=consolidated remote=open via=forge action=preserve\n'
    printf '2026-09-22T00:00:00Z task=landed status=ready remote=merged via=forge action=preserve flags=needs-consolidation\n'
  } > .ai/runtime/housekeeping.log
  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" '<code>shipped</code> · opened by jig task ship</p><p><a href="https://example.com/o/r/pull/7">https://example.com/o/r/pull/7</a></p>'
  assert_contains "$needs" "<code>waiting</code> · open as of housekeeping at "
  # The two cards differ in what they claim, because they know different
  # things. jig opened `shipped`'s pull request itself, so the present tense
  # and the imperative are earned. `waiting`'s state is borrowed from a
  # housekeeping run that may be a cadence old -- it is stated in the past, and
  # the first thing it asks for is a refresh, not a merge.
  assert_contains "$needs" "A pull request is waiting for review or merge</h3><p><code>shipped</code>"
  assert_contains "$needs" "A pull request was open at the last housekeeping run</h3><p><code>waiting</code>"
  assert_contains "$needs" "Run jig housekeeping to refresh, then review and merge what is still open."
  # Merged by housekeeping's last word: a task to close, not a pull request.
  assert_not_contains "$needs" "pull/8"
  assert_contains "$needs" "Merged: the task can be closed</h3><p><code>landed</code>"
  # Not the git step either: jig already opened the pull request.
  assert_not_contains "$needs" "Ready for your step in git</h3><p><code>shipped</code>"
}

test_status_page_shows_what_housekeeping_left_for_a_person() {
  fixture_jig_repo
  mkdir -p .ai/runtime
  {
    printf -- '--- run 2026-09-01T00:00:00Z forge=github\n'
    printf '2026-09-01T00:00:00Z task=old status=ready remote=merged via=forge action=preserve flags=needs-consolidation\n'
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-22T00:00:00Z task=wb status=ready remote=unknown via=forge action=preserve flags=wrong-base\n'
    printf '2026-09-22T00:00:00Z task=wk status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
    printf '2026-09-22T00:00:00Z task=cl status=active remote=closed via=forge action=preserve flags=abandoned?\n'
  } > .ai/runtime/housekeeping.log
  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "The work landed on a different branch than planned</h3><p><code>wb</code>"
  assert_contains "$needs" "A worktree was kept because it still holds work</h3><p><code>wk</code>"
  assert_contains "$needs" "The pull request was closed without merging</h3><p><code>cl</code>"
  # Only the last run counts.
  assert_not_contains "$needs" "<code>old</code>"
}

test_status_page_says_when_pull_request_data_is_stale() {
  export TZ=UTC
  fixture_jig_repo
  mkdir -p .ai/runtime
  printf -- '--- run 2020-01-01T00:00:00Z forge=github\n' > .ai/runtime/housekeeping.log
  run jig status --html
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" 'Pull request data from housekeeping at 2020-01-01 00:00 UTC <span class="badge warn">stale</span>'
  assert_contains "$page" "Pull request data is stale, so a pull request waiting for you may be missing here."

  printf -- '--- run %s forge=failed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .ai/runtime/housekeeping.log
  run jig status --html
  assert_contains "$(cat .ai/runtime/status.html)" '<span class="badge warn">stale</span>'

  printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .ai/runtime/housekeeping.log
  run jig status --html
  assert_not_contains "$(cat .ai/runtime/status.html)" "stale"

  printf -- '--- run %s forge=none\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .ai/runtime/housekeeping.log
  run jig status --html
  assert_contains "$(cat .ai/runtime/status.html)" "with no GitHub or GitLab to ask"

  rm .ai/runtime/housekeeping.log
  run jig status --html
  assert_contains "$(cat .ai/runtime/status.html)" "Housekeeping has not run yet"
}

test_status_page_orders_running_tasks_and_folds_paused_ones() {
  fixture_jig_repo
  fixture_task a-ready task/a-ready ready "class:T2"
  fixture_task b-filed "" active "class:T2"
  fixture_task c-active task/c-active active "class:T2"
  fixture_task d-auto task/d-auto active "class:T2" "autopilot:on"
  fixture_task e-paused task/e-paused active "class:T2" "paused:true" "paused_reason:on hold"
  run jig status --html
  local tasks ids
  tasks=$(status_page_section "$(cat .ai/runtime/status.html)" tasks)
  ids=$(printf '%s\n' "$tasks" | sed -n 's/^<tr><td class="id"><code>\([^<]*\)<.*/\1/p' | tr '\n' ' ')
  assert_eq "d-auto c-active a-ready b-filed e-paused " "$ids"
  assert_contains "$tasks" '<details id="paused"><summary>Paused</summary>'
  assert_contains "$tasks" '<span class="muted">not tracked outside autopilot</span>'
  assert_contains "$tasks" '<span class="muted">filed, not started</span>'
}

test_status_page_shows_spec_progress_by_phase() {
  fixture_jig_repo
  mkdir -p .ai/specs/idea-a
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md
  # shellcheck disable=SC2016 # backticked task ids, literal
  printf '%s\n' '# Roadmap' '' '## Phase 1 — First <step>' '' '- [x] one' '- [ ] `t-2` — two' \
    '' '## Phase 2 — Second' '' '- [ ] fog: three' '' '## Phase 3 — Empty' '' '## Waves' '' '1. one' \
    > .ai/specs/idea-a/roadmap.md
  run jig status --html
  local specs
  specs=$(status_page_section "$(cat .ai/runtime/status.html)" specs)
  assert_contains "$specs" "<tr><td><code>idea-a</code></td><td>Idea A</td><td>roadmap 1/3 done, 1 filed, fog 1</td></tr>"
  assert_contains "$specs" '<h3><code>idea-a</code> Idea A</h3>'
  assert_contains "$specs" '<tr><td>1</td><td>First &lt;step&gt;</td><td><span class="bar"><span style="width: 50%"></span></span>1/2 done</td><td>1</td><td>0</td></tr>'
  assert_contains "$specs" '<tr><td>2</td><td>Second</td><td><span class="bar"><span style="width: 0%"></span></span>0/1 done</td><td>0</td><td>1</td></tr>'
  assert_contains "$specs" '<tr><td>3</td><td>Empty</td>'
  assert_not_contains "$specs" "Waves"
}

test_status_page_reads_the_phases_of_an_open_epic_from_its_branch() {
  status_epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null
  git checkout -q epic/idea-x
  printf '%s\n' '' '## Phase 9 — On the epic' '' '- [x] done there' >> .ai/specs/idea-x/roadmap.md
  git add -A
  git commit -q -m "progress on the epic"
  git checkout -q main

  run jig status --html
  assert_eq 0 "$RC"
  local specs
  specs=$(status_page_section "$(cat .ai/runtime/status.html)" specs)
  assert_contains "$specs" '<p class="muted">From epic/idea-x.</p>'
  assert_contains "$specs" '<tr><td>9</td><td>On the epic</td>'
}

test_status_page_escapes_the_new_values_people_wrote() {
  fixture_jig_repo
  fixture_task esc task/esc ready "class:T2" "knowledge_consolidated:true" \
    'pr_url:javascript:alert("x")<b>'
  run jig status --html
  local page
  page=$(cat .ai/runtime/status.html)
  assert_not_contains "$page" '<b>'
  assert_not_contains "$page" 'href="javascript'
  assert_contains "$page" '<p><code>javascript:alert(&quot;x&quot;)&lt;b&gt;</code></p>'
}

test_status_page_open_uses_the_systems_opener() {
  fixture_jig_repo
  local bin="$JIG_TEST_TMP.bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho Darwin\n' > "$bin/uname"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s.opened"\n' "$JIG_TEST_TMP" > "$bin/open"
  chmod +x "$bin/uname" "$bin/open"
  PATH="$bin:$PATH" run jig status --open
  assert_eq 0 "$RC"
  assert_eq "$(pwd -P)/.ai/runtime/status.html" "$OUT"
  assert_eq "$(pwd -P)/.ai/runtime/status.html" "$(cat "$JIG_TEST_TMP.opened")"
}

test_status_page_open_from_git_bash_goes_through_cmd_start() {
  fixture_jig_repo
  local bin="$JIG_TEST_TMP.bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho MINGW64_NT-10.0\n' > "$bin/uname"
  printf '#!/bin/sh\necho "C:\\\\win\\\\status.html"\n' > "$bin/cygpath"
  # shellcheck disable=SC2016 # the stub expands these, not this shell
  printf '#!/bin/sh\nprintf "%%s|" "$@" > "%s.opened"; printf "%%s" "$MSYS2_ARG_CONV_EXCL" >> "%s.opened"\n' \
    "$JIG_TEST_TMP" "$JIG_TEST_TMP" > "$bin/cmd"
  chmod +x "$bin/uname" "$bin/cygpath" "$bin/cmd"
  PATH="$bin:$PATH" run jig status --open
  assert_eq 0 "$RC"
  assert_eq '/c|start||C:\win\status.html|*' "$(cat "$JIG_TEST_TMP.opened")"
}

test_status_page_open_without_a_browser_still_writes_the_page() {
  fixture_jig_repo
  local bin="$JIG_TEST_TMP.bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho Linux\n' > "$bin/uname"
  printf '#!/bin/sh\nexit 3\n' > "$bin/xdg-open"
  chmod +x "$bin/uname" "$bin/xdg-open"
  PATH="$bin:$PATH" run jig status --open
  assert_eq 0 "$RC"
  assert_file .ai/runtime/status.html
  assert_contains "$OUT" "$(pwd -P)/.ai/runtime/status.html"
  assert_contains "$OUT" "open this file in your browser: $(pwd -P)/.ai/runtime/status.html"
}

test_status_page_from_a_worktree_is_the_main_checkouts_page() {
  mkdir repo || return 1
  cd repo || return 1
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init snapshot"
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null
  local wt main
  main=$(pwd -P)
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  cd "$wt" || return 1
  run jig status --html
  assert_eq 0 "$RC"
  assert_eq "$main/.ai/runtime/status.html" "$OUT"
  assert_no_file "$wt/.ai/runtime/status.html"
  # The main checkout sees every task, not only the worktree's own.
  assert_contains "$(cat "$main/.ai/runtime/status.html")" "<code>T-2</code>"
}
