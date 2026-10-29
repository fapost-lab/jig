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

# --- a directory worktree.share should name ----------------------------------

# status_share_repo <dir> — a separate repository at <dir>, as a package under
# edit is.
status_share_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
}

test_status_hints_a_directory_of_repositories_worktree_share_should_name() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  printf 'packages/\nvendor/\nlinked/\n' >> .gitignore
  status_share_repo packages/alpha
  # Two levels down, as composer --prefer-source leaves it: not a candidate.
  status_share_repo vendor/acme/lib
  # A `.git` file is a worktree, not a package.
  mkdir -p linked/tree
  printf 'gitdir: /nowhere\n' > linked/tree/.git
  # Not ignored: git sees it, and sharing it would strand a worktree.
  status_share_repo seen/one

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "hint: packages/ holds separate repositories a task worktree cannot reach; for a task that edits them: \`jig task bootstrap <id> --share packages\`; for every task: add \`worktree.share: [packages]\` to .ai/config.yaml"
  assert_not_contains "$OUT" "hint: vendor/"
  assert_not_contains "$OUT" "hint: linked/"
  assert_not_contains "$OUT" "hint: seen/"

  # A project that finishes its worktrees with its own command has taken this
  # on itself: no hint.
  cp .ai/config.yaml config.before
  printf 'worktree.setup: make worktree-setup\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "holds separate repositories"
  cp config.before .ai/config.yaml

  # Declared with the slash the docs show it with, as the bootstrap reads it.
  printf 'worktree.share: [packages/]\n' >> .ai/config.yaml
  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "holds separate repositories"
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

# autopilot.git (adr-20260921-agent-git-rights-are-a-local-setting, amended
# 2026-10-08): always named, with the key it comes from.
test_status_reports_the_autopilot_git_level_and_its_source() {
  fixture_jig_repo
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "autopilot.git: none (from agent.git)"

  printf 'agent.git: pr\nautopilot.git: merge\n' > .ai/config.local.yaml
  run jig status
  assert_contains "$OUT" "autopilot.git: merge (from autopilot.git)"

  printf 'autopilot.git: yolo\n' > .ai/config.local.yaml
  run jig status
  assert_contains "$OUT" "autopilot.git: invalid value yolo (expected none|commit|push|pr|merge)"
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

# A copy of the framework's scripts whose `jig context` only leaves a mark, so
# a test can tell whether a command resolved knowledge at all.
# It lives outside the project, so it is not part of the change under review;
# the mark is $TRIPWIRE/context-ran.
_status_context_tripwire() {
  TRIPWIRE=$(mktemp -d "${TMPDIR:-/tmp}/jig-tripwire.XXXXXX")
  cp -R "$JIG_HOME/scripts" "$TRIPWIRE/scripts"
  printf 'touch "%s/context-ran"\n' "$TRIPWIRE" > "$TRIPWIRE/scripts/lib/context.sh"
}

test_status_does_not_resolve_knowledge_for_the_receipt() {
  fixture_jig_repo
  jig task new TASK-1 --class T2 >/dev/null
  jig task start TASK-1 >/dev/null
  jig task receipt TASK-1 --stage review >/dev/null
  _status_context_tripwire

  run "$TRIPWIRE/scripts/jig" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "task TASK-1 class=T2 status=active"
  assert_not_contains "$OUT" "review=stale"
  assert_eq "no" "$([ -e "$TRIPWIRE/context-ran" ] && echo yes || echo no)"

  # The full check, the one the gates use, does resolve it and still says current.
  run "$TRIPWIRE/scripts/jig" task receipt TASK-1 --check
  assert_eq "yes" "$([ -e "$TRIPWIRE/context-ran" ] && echo yes || echo no)"
  rm -rf "$TRIPWIRE"
}

test_status_page_says_not_checked_where_it_did_not_look_at_the_knowledge() {
  fixture_jig_repo
  jig task new TASK-1 --class T2 >/dev/null
  jig task start TASK-1 >/dev/null
  jig task receipt TASK-1 --stage review >/dev/null

  run jig status --html
  assert_eq 0 "$RC"
  assert_contains "$(cat .ai/runtime/status.html)" "not checked"
  assert_not_contains "$(cat .ai/runtime/status.html)" ">current<"
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

# _st_upgrade_item <global-version> — `jig status --json` with a global jig
# of that version on PATH; OUT holds the JSON, ITEM the upgrade-available
# item or nothing (task status-json-upgrade-available).
_st_upgrade_item() {
  local stub_root stub_bin path_dir
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" "JIG_VERSION=\"$1\"")
  OUT=$(env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status --json 2>/dev/null)
  ITEM=$(printf '%s' "$OUT" | grep -o '{"kind":"upgrade-available"[^}]*}[^}]*}' || true)
  rm -rf "$stub_root" "$stub_bin"
}

# A program listing many projects learns from the JSON which need `jig
# upgrade`: the item names both versions, and only for an older project.
test_status_json_names_a_project_behind_this_machines_jig() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local version
  version=$(_status_project_version)
  _st_upgrade_item 9.0.0
  assert_contains "$ITEM" '"subject":{"type":"project"'
  assert_contains "$ITEM" "\"detail\":\"this project runs $version; this machine has 9.0.0\""
  assert_contains "$ITEM" '"todo":"jig upgrade"'
  assert_contains "$OUT" "\"versions\":{\"from\":\"$version\",\"to\":\"9.0.0\"}"

  _st_upgrade_item "$version"
  assert_eq "" "$ITEM" "an up-to-date project was told to upgrade"
  _st_upgrade_item 0.0.1
  assert_eq "" "$ITEM" "a project newer than this machine was told to upgrade"
  _st_upgrade_item dev
  assert_eq "" "$ITEM" "a non-release global named a direction"
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

# --- a new jig release (task status-says-a-newer-jig-exists) ----------------
#
# housekeeping's own daily check (_hk_check_latest_release, housekeeping.sh)
# writes .ai/runtime/latest-release; `jig status` only reads it and compares
# it to the global framework version, exactly like the framework-versions
# tests above — so these reuse the same stub-global fixtures, and write the
# file by hand rather than running housekeeping (its own wiring is proven in
# tests/housekeeping.t.sh).

test_status_new_release_hint_when_recorded_version_is_newer() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local stub_root stub_bin path_dir
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="0.1.0"')
  mkdir -p .ai/runtime
  printf 'latest=0.2.0\nchecked_at=2026-09-30T00:00:00Z\n' > .ai/runtime/latest-release

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'hint: jig v0.2.0 is out; run `jig self-update`, then `jig upgrade`'

  rm -rf "$stub_root" "$stub_bin"
}

test_status_no_new_release_hint_when_recorded_version_is_not_newer() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local stub_root stub_bin path_dir
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="0.2.0"')
  mkdir -p .ai/runtime
  printf 'latest=0.2.0\nchecked_at=2026-09-30T00:00:00Z\n' > .ai/runtime/latest-release

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "is out"

  rm -rf "$stub_root" "$stub_bin"
}

test_status_no_new_release_hint_without_a_file() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local stub_root stub_bin path_dir
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="0.1.0"')

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "is out"

  rm -rf "$stub_root" "$stub_bin"
}

test_status_no_new_release_hint_when_the_check_failed() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local stub_root stub_bin path_dir
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="0.1.0"')
  mkdir -p .ai/runtime
  printf 'failed\nchecked_at=2026-09-30T00:00:00Z\n' > .ai/runtime/latest-release

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "is out"

  rm -rf "$stub_root" "$stub_bin"
}

test_status_html_shows_a_card_for_a_new_release() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local stub_root stub_bin path_dir
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="0.1.0"')
  mkdir -p .ai/runtime
  printf 'latest=0.2.0\nchecked_at=2026-09-30T00:00:00Z\n' > .ai/runtime/latest-release

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status --html
  assert_eq 0 "$RC"
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "jig v0.2.0 is out"
  assert_contains "$needs" "jig self-update, then jig upgrade"

  rm -rf "$stub_root" "$stub_bin"
}

test_status_html_shows_no_card_when_no_new_release_is_recorded() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local stub_root stub_bin path_dir
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="0.2.0"')
  mkdir -p .ai/runtime
  printf 'latest=0.2.0\nchecked_at=2026-09-30T00:00:00Z\n' > .ai/runtime/latest-release

  run env PATH="$(_status_path_without_jig "$path_dir")" "$JIG_BIN" status --html
  assert_eq 0 "$RC"
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_not_contains "$needs" "is out"

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
  git checkout -q main
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
  git checkout -q main
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
  git checkout -q main
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
  git checkout -q main
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
  # The page, the counts its redraws reuse, the record every jig run leaves
  # saying a session is working in this checkout
  # (adr-20260924-a-checkout-records-what-is-happening-in-it), and the clone's
  # revision, which the first saved counts raise because `status --json`
  # reports them (adr-20261016-the-clone-revision-is-a-claimed-name) — nothing
  # else.
  assert_eq "checkout
revision
status-counts
status.html" "$(ls .ai/runtime)" "nothing but the page, its counts, the checkout record and the revision"
  assert_eq "$before" "$(git status --porcelain --ignored | grep -v '^!! .ai/runtime/' || true)"

  # A second run replaces the page rather than adding another.
  run jig status --html
  assert_eq 0 "$RC"
  assert_eq "checkout
revision
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
  # No global jig: one newer than this checkout would be something to do.
  PATH=$(_status_path_without_jig)
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
  assert_contains "$page" '<span class="badge">not checked (knowledge not resolved; jig task receipt reviewed --check)</span>'
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
  git checkout -q main
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
  # The badge, not the autopilot.git line every page carries.
  assert_not_contains "$(cat .ai/runtime/status.html)" "badge\">autopilot"
  assert_not_contains "$(cat .ai/runtime/status.html)" "badge warn\">autopilot"

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

# status_stop_ages_masked — stdin with each stop's age replaced by "<age>".
# A test stops a run and then draws the page; a loaded runner can take over a
# minute between the two, and "just now" then reads "1 min ago". The age is
# derived from the clock, so the tests check where it stands, not its value.
status_stop_ages_masked() {
  sed -E 's/stopped (just now|[0-9]+ min ago):/stopped <age>:/g'
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
  needs=$(status_page_section "$page" needs | status_stop_ages_masked)
  assert_contains "$needs" 'Autopilot stopped and is waiting for you <span class="badge warn">autopilot stopped</span>'
  # The age leads and the reason follows a colon: the reason is prose written
  # once, at the stop, and nothing rechecks it. Read with the age appended it
  # claims to be true now, and a card was still saying "no pull request" hours
  # after one existed.
  assert_contains "$needs" "<code>run-1</code> · stopped <age>: which &lt;db&gt; to use &amp; why"
  assert_not_contains "$needs" "which &lt;db&gt; to use &amp; why ("
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
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs | status_stop_ages_masked)
  n=$(printf '%s\n' "$needs" | grep -c "A phase run is waiting for you" || true)
  assert_eq 1 "$n" "expected one card for the whole phase, got $n"
  # Each line carries its own stop's age, because a wave's tasks stop at
  # different moments and each reason is prose from that moment.
  assert_contains "$needs" "run-1 — stopped <age>: question from run-1"
  assert_contains "$needs" "run-2 — stopped <age>: question from run-2"
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
  jig task receipt run-1 --stage review >/dev/null
  task_route_done run-1
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
  jig task new big --class T3 --goal "The goal." >/dev/null
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

# A stopped autopilot run is exactly the task that has just been shipped, so
# it is the likeliest of all to have a pull request. The card was collected at
# the end of the loop that builds this section, after the branch for a stopped
# run ends the iteration, and the page showed no pull request at all while
# telling the reader to go and open one.
test_status_page_links_the_pull_request_of_a_task_whose_autopilot_stopped() {
  fixture_jig_repo
  jig task new run-1 --class T2 >/dev/null
  jig task start run-1 >/dev/null
  jig task autopilot run-1 start >/dev/null
  jig task autopilot run-1 stop --reason "say which base to land on" >/dev/null
  # `task set` refuses pr_url: only `task ship` writes it, from the forge.
  printf 'pr_url: https://example.com/o/r/pull/9\n' >> .ai/workspace/tasks/run-1/state

  run jig status --html
  assert_eq 0 "$RC"
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "Autopilot stopped and is waiting for you"
  assert_contains "$needs" "A pull request is waiting for review or merge</h3><p><code>run-1</code>"
  assert_contains "$needs" '<a href="https://example.com/o/r/pull/9">https://example.com/o/r/pull/9</a>'
}

# The same for a stop held back for a phase run: that branch ends the
# iteration too.
test_status_page_links_the_pull_request_of_a_phase_runs_stopped_task() {
  fixture_jig_repo
  jig task new run-1 --class T2 >/dev/null
  jig task start run-1 >/dev/null
  jig task autopilot run-1 start --phase alpha/1 >/dev/null
  jig task autopilot run-1 stop --reason "say which base to land on" >/dev/null
  printf 'pr_url: https://example.com/o/r/pull/10\n' >> .ai/workspace/tasks/run-1/state

  run jig status --html
  assert_eq 0 "$RC"
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "A phase run is waiting for you"
  assert_contains "$needs" "A pull request is waiting for review or merge</h3><p><code>run-1</code>"
  assert_contains "$needs" '<a href="https://example.com/o/r/pull/10">https://example.com/o/r/pull/10</a>'
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

# --- a flag this disk disproves (hklog_flagged_ids) ------------------------
#
# The cut is the cost of asking again. A task's own status and a worktree's
# existence are read for nothing while the page is drawn, so a card they
# contradict is not built; what the forge saw costs a request the page never
# makes on the write path, and stays borrowed. Each test below carries both
# halves — what the recheck must drop, beside what it must leave alone — so a
# recheck taken out shows up as red rather than as a green that means nothing
# (conventions/detectors.md).

test_status_forgets_a_consolidation_flag_the_task_state_disproves() {
  fixture_jig_repo
  # Both were flagged by the same run, by the same line. Only one of them has
  # been closed since.
  fixture_task closed-since task/closed-since consolidated "class:T2"
  fixture_task open-still task/open-still active "class:T2"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=closed-since status=active remote=merged via=forge action=preserve flags=needs-consolidation\n'
    printf '2026-09-25T12:00:00Z task=open-still status=active remote=merged via=forge action=preserve flags=needs-consolidation\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  assert_eq 0 "$RC"
  local page needs
  page=$(cat .ai/runtime/status.html)
  needs=$(status_page_section "$page" needs)
  assert_not_contains "$needs" "Merged: the task can be closed</h3><p><code>closed-since</code>"
  assert_contains "$needs" "Merged: the task can be closed</h3><p><code>open-still</code>"
  # The counts name the same tasks as the cards, in both reports: a reader
  # sent to look for a second task would find nothing.
  assert_contains "$page" '<dt>Needs consolidation</dt><dd>1</dd>'
  run jig status
  assert_contains "$OUT" "needs consolidation: 1 task(s)"
}

test_status_card_for_an_archived_task_that_merged_says_to_unarchive_first() {
  fixture_jig_repo
  fixture_task shelved task/shelved archived "class:T2" "archived_from:active" "archived_reason:stale"
  fixture_task open-still task/open-still active "class:T2"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=shelved status=archived remote=merged via=forge action=preserve flags=needs-consolidation\n'
    printf '2026-09-25T12:00:00Z task=open-still status=active remote=merged via=forge action=preserve flags=needs-consolidation\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  assert_eq 0 "$RC"
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "<code>shelved</code>"
  assert_contains "$needs" "<code>open-still</code>"
  assert_contains "$needs" "It is archived: run jig task unarchive shelved, then tell the agent to close it (jig-consolidate)."
  assert_contains "$needs" "Tell the agent to close this task (jig-consolidate)."
  assert_not_contains "$needs" "unarchive open-still"
  run jig status
  assert_contains "$OUT" "needs consolidation: 2 task(s)"
}

test_status_forgets_a_worktree_flag_once_that_worktree_is_gone() {
  fixture_jig_repo
  local here
  here=$(pwd)
  mkdir -p .ai/runtime "$here/kept-tree"
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=still-there worktree=%s/kept-tree action=keep reason=uncommitted-changes\n' "$here"
    printf '2026-09-25T12:00:00Z task=still-there status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
    printf '2026-09-25T12:00:00Z task=deleted-by-hand worktree=%s/no-such-tree action=keep reason=uncommitted-changes\n' "$here"
    printf '2026-09-25T12:00:00Z task=deleted-by-hand status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  assert_eq 0 "$RC"
  local page needs
  page=$(cat .ai/runtime/status.html)
  needs=$(status_page_section "$page" needs)
  assert_contains "$needs" "A worktree was kept because it still holds work</h3><p><code>still-there</code>"
  assert_not_contains "$needs" "<code>deleted-by-hand</code>"
  assert_contains "$page" '<dt>Worktrees kept</dt><dd>1</dd>'
  run jig status
  assert_contains "$OUT" "worktrees kept: 1 task(s)"
}

test_status_forgets_a_closed_pull_request_flag_once_the_task_is_abandoned() {
  fixture_jig_repo
  # housekeeping_decide drops this flag for a task already abandoned
  # (abandoned:closed) — it would ask a question that has been answered. The
  # page said it anyway until the next run.
  fixture_task answered task/answered abandoned "class:T2"
  fixture_task unanswered task/unanswered active "class:T2"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=answered status=active remote=closed via=forge action=preserve flags=abandoned?\n'
    printf '2026-09-25T12:00:00Z task=unanswered status=active remote=closed via=forge action=preserve flags=abandoned?\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_not_contains "$needs" "The pull request was closed without merging</h3><p><code>answered</code>"
  assert_contains "$needs" "The pull request was closed without merging</h3><p><code>unanswered</code>"
}

test_status_treats_an_archived_task_as_answered_for_a_closed_pull_request_but_not_for_consolidation() {
  fixture_jig_repo
  # An archived task is out of the work, so "abandoned?" is answered; its merged
  # work still needs closing (adr-20261027-a-task-nobody-finished-is-archived-not-purged).
  fixture_task shelved task/shelved archived "class:T2" "archived_at:2026-10-01" "archived_reason:stale" "archived_from:active"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=shelved status=active remote=closed via=forge action=preserve flags=abandoned?\n'
    printf '2026-09-25T12:00:00Z task=shelved status=active remote=merged via=forge action=preserve flags=needs-consolidation\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_not_contains "$needs" "The pull request was closed without merging</h3><p><code>shelved</code>"
  assert_contains "$needs" "Merged: the task can be closed</h3><p><code>shelved</code>"
}

test_status_still_borrows_what_only_the_forge_knows() {
  fixture_jig_repo
  # Closed exactly like the task whose consolidation card disappears above,
  # and this card stays: where the work landed cannot be read off this disk.
  # The cut is the cost of the answer, not the kind of card.
  fixture_task landed-elsewhere task/landed-elsewhere consolidated "class:T2"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=landed-elsewhere status=ready remote=unknown via=forge action=preserve flags=wrong-base\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  local page needs
  page=$(cat .ai/runtime/status.html)
  needs=$(status_page_section "$page" needs)
  assert_contains "$needs" "The work landed on a different branch than planned</h3><p><code>landed-elsewhere</code>"
  # Still stamped with the run it was borrowed from.
  assert_contains "$needs" "<code>landed-elsewhere</code> · housekeeping at "
  assert_contains "$page" '<dt>Landed on the wrong base</dt><dd>1</dd>'
  run jig status
  assert_contains "$OUT" "wrong base: 1 task(s)"
}

test_status_keeps_a_flag_it_has_no_way_to_check() {
  fixture_jig_repo
  # A recheck may only contradict, never invent. No workspace for the first
  # task, and no `worktree=` line for the second: the page cannot tell, so it
  # goes on saying what the run said.
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=no-workspace status=ready remote=merged via=forge action=preserve flags=needs-consolidation\n'
    printf '2026-09-25T12:00:00Z task=no-path-logged status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "Merged: the task can be closed</h3><p><code>no-workspace</code>"
  assert_contains "$needs" "A worktree was kept because it still holds work</h3><p><code>no-path-logged</code>"
}

test_status_asks_you_to_close_the_pull_request_of_a_task_you_abandoned() {
  fixture_jig_repo
  # `task abandon` never touches the forge, so the pull request stays open and
  # the flag is right. The ask was not: it told the reader to merge work
  # nobody wants. `consolidated` beside it keeps the merge ask, which is the
  # half of this that must not move.
  fixture_task given-up task/given-up abandoned "class:T2"
  fixture_task closed-clean task/closed-clean consolidated "class:T2"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=given-up status=abandoned remote=open via=forge action=preserve\n'
    printf '2026-09-25T12:00:00Z task=closed-clean status=consolidated remote=open via=forge action=preserve\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  assert_eq 0 "$RC"
  local needs abandoned_card
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "A pull request was open for a task you abandoned</h3><p><code>given-up</code>"
  assert_contains "$needs" "close on the forge what is still open, or reopen the task"
  # The card that replaced the wrong one must not carry the wrong ask -- and
  # must not claim in the present tense what it borrowed: the page knows the
  # task was abandoned, not that the pull request is open right now. It is as
  # borrowed as the card below it and says so the same way.
  abandoned_card=$(printf '%s\n' "$needs" | grep 'task you abandoned')
  assert_not_contains "$abandoned_card" "review and merge"
  assert_not_contains "$abandoned_card" "Review it and merge it"
  assert_not_contains "$abandoned_card" "is still open for a task"
  assert_contains "$abandoned_card" "It may have been closed or merged since"
  # Still borrowed: only the forge knows the pull request is open.
  assert_contains "$needs" "<code>given-up</code> · open as of housekeeping at "
  # A closed task with an open pull request is not the same thing, and keeps
  # the merge ask.
  assert_contains "$needs" "A pull request was open at the last housekeeping run</h3><p><code>closed-clean</code>"
}

test_status_asks_nothing_about_a_bad_id_on_the_pull_request_path_either() {
  fixture_jig_repo
  # The sister of the guard in _hklog_recheck, and it needs its own stand:
  # that one is reached through `flags=`, this one through ` remote=open `,
  # and a test of the first says nothing about the second. Both readings here
  # -- pr_url and status -- run on ids that came out of the log.
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=../evil status=active remote=open via=forge action=preserve\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  assert_eq 0 "$RC"
  # run() folds stderr into OUT, so a refusal shows up here either way. An
  # unguarded read would take task_dir into jig_die, which redraws the page
  # in the middle of drawing it.
  assert_not_contains "$OUT" "invalid task id"
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "A pull request was open at the last housekeeping run"
}

test_status_asks_nothing_about_an_id_the_log_should_not_hold() {
  fixture_jig_repo
  # A report may not fail on a peer's data, and `task_dir` dies on an id like
  # this -- through jig_die, which redraws the page being drawn. The card is
  # kept and nothing is said on stderr.
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=../evil status=active remote=merged via=forge action=preserve flags=needs-consolidation\n'
  } > .ai/runtime/housekeeping.log

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "needs consolidation: 1 task(s)"
  # run() folds stderr into OUT, so this catches the refusal either way.
  assert_not_contains "$OUT" "invalid task id"
}

test_status_reads_a_kept_worktree_path_that_holds_spaces() {
  fixture_jig_repo
  # The log writes the path unquoted, so it cannot be read as a field. Read
  # that way this path comes back truncated, is not a directory, and the card
  # would vanish although the worktree is right there.
  local here
  here=$(pwd)
  mkdir -p .ai/runtime "$here/tree with spaces"
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=spaced worktree=%s/tree with spaces action=keep reason=uncommitted-changes\n' "$here"
    printf '2026-09-25T12:00:00Z task=spaced status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "A worktree was kept because it still holds work</h3><p><code>spaced</code>"
}

test_status_does_not_take_one_task_id_for_another_it_begins_with() {
  fixture_jig_repo
  # `task=wk` must not answer for `task=wk2`: the id is matched on the whole
  # field. Read as a substring, wk2 would borrow wk's live worktree and keep
  # a card its own deleted tree has disproved.
  local here
  here=$(pwd)
  mkdir -p .ai/runtime "$here/wk-tree"
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-25T12:00:00Z task=wk worktree=%s/wk-tree action=keep reason=uncommitted-changes\n' "$here"
    printf '2026-09-25T12:00:00Z task=wk status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
    printf '2026-09-25T12:00:00Z task=wk2 worktree=%s/wk2-tree action=keep reason=uncommitted-changes\n' "$here"
    printf '2026-09-25T12:00:00Z task=wk2 status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
  } > .ai/runtime/housekeeping.log

  run jig status --html
  local needs
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  assert_contains "$needs" "<code>wk</code>"
  assert_not_contains "$needs" "<code>wk2</code>"
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

test_status_counts_an_archived_task_apart_from_the_finished() {
  fixture_jig_repo
  fixture_task live-1 task/live-1 active "class:T1"
  fixture_task done-1 task/done-1 consolidated
  fixture_task old-1 task/old-1 archived "archived_at:2026-10-01" "archived_reason:stale" "archived_from:active"

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "(1 finished; jig task list --all)"
  assert_contains "$OUT" "archived: 1 (jig task list --status archived)"
  assert_not_contains "$OUT" "old-1"

  run jig status --html
  local page
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" '<details id="archived"><summary>Archive (1)</summary>'
  assert_contains "$page" "<code>old-1</code>"
  assert_contains "$page" "<td>2026-10-01</td><td>stale</td>"
  assert_contains "$page" "1 finished, not listed"
}

test_status_omits_the_archive_when_nothing_is_archived() {
  fixture_jig_repo
  fixture_task live-1 task/live-1 active "class:T1"

  run jig status
  assert_not_contains "$OUT" "archived:"
  run jig status --html
  assert_not_contains "$(cat .ai/runtime/status.html)" 'id="archived"'
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

# A closed task's unchecked item counts done on the page: the rule `spec plan`
# reads (spec_merged_task_ids), so a phase run's merged wave shows at once.
test_status_page_counts_a_closed_tasks_unchecked_item_done() {
  fixture_jig_repo
  mkdir -p .ai/specs/idea-m
  printf '%s\n' '# Idea M' > .ai/specs/idea-m/spec.md
  # shellcheck disable=SC2016 # backticked task ids, literal
  printf '%s\n' '# Roadmap' '' '## Phase 1 — First' '' '- [ ] `t-1` — merged' '- [ ] `t-2` — open' \
    > .ai/specs/idea-m/roadmap.md
  fixture_task t-1 task/t-1 consolidated
  run jig status --html
  local specs
  specs=$(status_page_section "$(cat .ai/runtime/status.html)" specs)
  assert_contains "$specs" '<tr><td>1</td><td>First</td><td><span class="bar"><span style="width: 50%"></span></span>1/2 done</td><td>1</td><td>0</td></tr>'
}

test_status_page_reads_the_phases_of_an_open_epic_from_its_branch() {
  status_epic_setup
  jig spec new idea-x >/dev/null
  git checkout -q main
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

# --- route depth (adr-20261002-route-depth-is-a-personal-choice) --------------

test_status_marks_a_lean_task_and_says_nothing_of_a_full_one() {
  fixture_jig_repo
  jig task new T-lean --class T2 --lean >/dev/null
  jig task new T-full --class T2 >/dev/null
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task T-lean class=T2 status=active depth=lean"
  assert_contains "$OUT" "task T-full class=T2 status=active"
  assert_not_contains "$OUT" "T-full class=T2 status=active depth"
}

test_status_marks_every_task_lean_under_a_lean_setting_unless_the_task_says_full() {
  fixture_jig_repo
  jig task new T-a --class T1 >/dev/null
  jig task new T-b --class T1 >/dev/null
  jig task set T-b route_depth full >/dev/null
  jig config set route.depth lean --local >/dev/null
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task T-a class=T1 status=active depth=lean"
  assert_not_contains "$OUT" "T-b class=T1 status=active depth"
}

test_status_html_badges_a_lean_task() {
  fixture_jig_repo
  jig task new T-lean --class T2 --lean >/dev/null
  run jig status --html
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(cat .ai/runtime/status.html)" '<td>T2 <span class="badge">lean</span></td>'
}

# --- the terminal form (adr-20261005-output-is-decorated-only-on-a-terminal) --

# _status_form_scenario <stub-root> <stub-bin> — a project whose report has a
# line of nearly every shape: a version mismatch and a newer release, local
# config in effect and ignored, drift, a task in flight, a paused one and a
# finished one. Prints the PATH to run it under; the caller removes the stubs.
_status_form_scenario() {
  local path_dir
  fixture_jig_repo
  path_dir=$(_status_make_stub_global "$1" "$2" 'JIG_VERSION="0.1.0"')
  mkdir -p .ai/runtime
  printf 'latest=0.2.0\nchecked_at=2026-09-30T00:00:00Z\n' > .ai/runtime/latest-release
  printf 'housekeeping.cadence: 3d\ngit.base_branch: other\n' > .ai/config.local.yaml
  printf 'edited\n' >> .claude/skills/jig-task/SKILL.md
  rm -f .codex/skills/jig-review/SKILL.md
  fixture_task t-a task/t-a active "class:T2"
  fixture_task t-b task/t-b active "class:T1" "paused:true" "paused_reason:waiting for a decision"
  fixture_task t-c task/t-c consolidated "class:T1"
  printf '2026-09-10T00:00:00Z task=t-n status=active remote=merged via=ancestry action=preserve flags=needs-consolidation\n' \
    > .ai/runtime/housekeeping.log
  _status_path_without_jig "$path_dir"
}

# The byte-for-byte proof: the expected text is the report as status printed
# it before the output layer, and the same test passes on the commit before it.
test_status_a_pipe_gets_the_report_byte_for_byte_as_before() {
  local stub_root stub_bin path v
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path=$(_status_form_scenario "$stub_root" "$stub_bin")
  v=$(_status_project_version)
  {
    printf 'jig %s\n' "$v"
    printf 'initialised: yes\n'
    printf 'config.local: housekeeping.cadence=3d\n'
    printf 'config.local: ignored git.base_branch (not a local key)\n'
    printf 'agent.git: none (review queue: uncommitted files)\n'
    printf 'autopilot.git: none (from agent.git)\n'
    printf 'manifest: version=%s mode=copy source=%s\n' "$v" "$JIG_HOME"
    printf 'framework versions: project=%s global=0.1.0 mismatch\n' "$v"
    # shellcheck disable=SC2016
    printf 'hint: the project is newer than the global framework; run `jig self-update`\n'
    # shellcheck disable=SC2016
    printf 'hint: jig v0.2.0 is out; run `jig self-update`, then `jig upgrade`\n'
    printf 'drift: 1 modified, 1 missing, 1 pending\n'
    printf 'modified:\n'
    printf '  .claude/skills/jig-task/SKILL.md\n'
    printf 'missing:\n'
    printf '  .codex/skills/jig-review/SKILL.md\n'
    printf 'proposals: none\n'
    printf 'specs: none\n'
    printf 'task t-a class=T2 status=active\n'
    printf 'task t-b class=T1 status=active paused (waiting for a decision)\n'
    printf '(1 finished; jig task list --all)\n'
    printf 'current task: none\n'
    printf 'sessions: not observable (no active runtime names its sessions here)\n'
    printf 'housekeeping: never\n'
    printf 'needs consolidation: 1 task(s) (see .ai/runtime/housekeeping.log)\n'
    printf 'session hook (claude): not installed\n'
    printf 'instructions (claude): ok\n'
    printf 'instructions (codex): ok\n'
  } > "$TMPDIR/expected.txt"
  env PATH="$path" "$JIG_BIN" status > "$TMPDIR/actual.txt" 2>&1
  assert_eq 0 "$?"
  cmp "$TMPDIR/expected.txt" "$TMPDIR/actual.txt" || fail "piped report changed: $(diff "$TMPDIR/expected.txt" "$TMPDIR/actual.txt")"
  rm -rf "$stub_root" "$stub_bin"
}

# _status_heading <left> <verdict> — the heading line as out_heading draws it
# without colour: the verdict on the right edge of 80 columns.
_status_heading() {
  printf '%s%*s\n' "$1" $((80 - ${#1})) "$2"
}

test_status_a_terminal_reads_in_sections() {
  local stub_root stub_bin path v name
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path=$(_status_form_scenario "$stub_root" "$stub_bin")
  v=$(_status_project_version)
  name=$(basename "$(pwd -P)")
  {
    _status_heading "jig $v | $name | copy mode" "7 items need you"
    printf '\n'
    printf -- '-- Needs you  (7) --------------------------------------------------------------\n'
    printf '  warn  config.local: ignored git.base_branch (not a local key)\n'
    printf '  warn  framework versions: project=%s global=0.1.0 mismatch\n' "$v"
    # shellcheck disable=SC2016
    printf '        hint: the project is newer than the global framework; run `jig self-update`\n'
    printf '  warn  jig v0.2.0 is out\n'
    # shellcheck disable=SC2016
    printf '        hint: run `jig self-update`, then `jig upgrade`\n'
    printf '  warn  drift: 1 modified, 1 missing, 1 pending\n'
    printf '        modified: .claude/skills/jig-task/SKILL.md\n'
    printf '        missing: .codex/skills/jig-review/SKILL.md\n'
    printf '  warn  task t-b class=T1 status=active paused (waiting for a decision)\n'
    printf '  warn  needs consolidation: 1 task(s)\n'
    printf '        see: .ai/runtime/housekeeping.log\n'
    printf '  warn  session hook (claude): not installed\n'
    printf '\n'
    printf -- '-- Install ---------------------------------------------------------------------\n'
    printf '  ok    hooks         instructions (claude, codex)\n'
    printf '  ok    housekeeping  never ran\n'
    printf '\n'
    printf -- '-- Settings  (config.local) ----------------------------------------------------\n'
    printf '  agent.git              none | review queue: uncommitted files\n'
    printf '  autopilot.git          none | from agent.git\n'
    printf '  housekeeping.cadence   3d\n'
    printf '\n'
    printf -- '-- Tasks  (2 active | 1 finished) ----------------------------------------------\n'
    printf '  T2  t-a\n'
    printf '  .   current task: none\n'
    printf '\n'
    printf -- '-- Knowledge & specs -----------------------------------------------------------\n'
    printf '  proposals   none\n'
    printf '  specs       none\n'
    printf '\n'
    printf -- '-- Recent activity here  (no records) ------------------------------------------\n'
    printf '  .     nothing here holds HEAD | sessions not observable\n'
  } > "$TMPDIR/expected.txt"
  env PATH="$path" LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status > "$TMPDIR/actual.txt" 2>&1
  assert_eq 0 "$?"
  cmp "$TMPDIR/expected.txt" "$TMPDIR/actual.txt" || fail "terminal report differs: $(diff "$TMPDIR/expected.txt" "$TMPDIR/actual.txt")"
  rm -rf "$stub_root" "$stub_bin"
}

test_status_a_terminal_says_nothing_needs_you_when_nothing_does() {
  fixture_jig_repo
  local v
  v=$(_status_project_version)
  mkdir -p .claude
  printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": ".ai/scripts/jig-session-hook" } ] } ] } }\n' \
    > .claude/settings.json
  run env PATH="$(_status_path_without_jig)" LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_eq "$(_status_heading "jig $v | $(basename "$(pwd -P)") | copy mode" "nothing needs you")" \
    "$(printf '%s\n' "$OUT" | sed -n 1p)"
  assert_not_contains "$OUT" "Needs you"
  assert_not_contains "$OUT" "warn  "
  assert_contains "$OUT" "-- Tasks  (no active tasks) ---"
  assert_contains "$OUT" "  ok    framework     $v (global jig unavailable)"
  assert_contains "$OUT" "  ok    drift         0 modified | 0 missing | "
  assert_contains "$OUT" "  ok    hooks         session hook (claude) | instructions (claude, codex)"
}

test_status_a_terminal_on_an_uninitialised_project_says_what_to_run() {
  fixture_repo
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  # shellcheck disable=SC2016
  assert_eq "$(_status_heading "jig $(_status_project_version) | $(basename "$(pwd -P)") | not initialised" "1 item needs you")
$(printf '\n-- Needs you  (1) --------------------------------------------------------------\n  warn  initialised: no\n        hint: run `jig init` to bootstrap this project')" "$OUT"
}

test_status_a_terminal_colours_the_sections() {
  local stub_root stub_bin path e
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  path=$(_status_form_scenario "$stub_root" "$stub_bin")
  fixture_task t-d task/t-d active "class:T4"
  e=$(printf '\033')
  run env -u NO_COLOR PATH="$path" LC_ALL=C TERM=xterm JIG_TERMINAL=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "${e}[33m7 items need you${e}[0m"
  assert_contains "$OUT" "${e}[2m--${e}[0m ${e}[1;36mNeeds you${e}[0m  (7) ${e}[2m---"
  assert_contains "$OUT" "  ${e}[33mwarn${e}[0m  jig v0.2.0 is out"
  assert_contains "$OUT" "  ${e}[32mok${e}[0m    housekeeping  never ran"
  assert_contains "$OUT" "  T2  ${e}[1mt-a${e}[0m"
  assert_contains "$OUT" "  ${e}[33mT4${e}[0m  ${e}[1mt-d${e}[0m"
  rm -rf "$stub_root" "$stub_bin"
}

test_status_a_terminal_colours_a_lower_class_dim_and_a_deviation_yellow() {
  local e
  fixture_jig_repo
  fixture_task t-a task/t-a active "class:T1" "base_branch:epic/x"
  e=$(printf '\033')
  run env -u NO_COLOR LC_ALL=C TERM=xterm JIG_TERMINAL=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "  ${e}[2mT1${e}[0m  ${e}[1mt-a${e}[0m"
  assert_contains "$OUT" "${e}[33mbase epic/x${e}[0m"
}

# A refusal comes before every warning, wherever the report printed it.
test_status_a_terminal_puts_an_invalid_agent_git_first() {
  fixture_jig_repo
  printf 'agent.git: sometimes\n' > .ai/config.local.yaml
  env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status > out.txt 2> err.txt
  RC=$?
  OUT=$(cat out.txt)
  ERR=$(cat err.txt)
  assert_eq 0 "$RC"
  assert_eq "  fail  agent.git: invalid value sometimes (expected none|commit|push|pr|merge)" \
    "$(printf '%s\n' "$OUT" | sed -n 4p)"
  # The refused key is all config.local holds: no Settings section, and the
  # report goes on to its end.
  assert_eq "" "$ERR"
  assert_not_contains "$OUT" "-- Settings"
  assert_contains "$OUT" "-- Recent activity here"
}

# The marks follow the locale as the C library reads it: LC_ALL, then
# LC_CTYPE, then LANG. Without a UTF-8 locale everything is ASCII.
# skip_unless_utf8_locale — skip when this machine cannot take en_US.UTF-8:
# out_init then rightly falls back to ASCII, and there is nothing to see.
skip_unless_utf8_locale() {
  local n
  n=$(LC_ALL=en_US.UTF-8 bash -c 'x=$(printf "\302\267"); printf %s "${#x}"' 2>/dev/null)
  [ "$n" = 1 ] || skip "en_US.UTF-8 is not available here"
}

test_status_a_terminal_draws_utf8_marks_only_in_a_utf8_locale() {
  local rule dot
  skip_unless_utf8_locale
  fixture_jig_repo
  rule=$(printf '\342\224\200')
  dot=$(printf '\302\267')
  run env -u LC_ALL -u LC_CTYPE LANG=en_US.UTF-8 JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "$rule$rule Install $rule$rule"
  assert_contains "$OUT" "0 modified $dot 0 missing"
  assert_contains "$OUT" "  $dot   current task: none"
  run env -u LC_ALL LC_CTYPE=C LANG=en_US.UTF-8 JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "-- Install --"
  assert_not_contains "$OUT" "$rule"
  assert_not_contains "$OUT" "$dot"
  run env LC_ALL=C LANG=en_US.UTF-8 JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_contains "$OUT" "0 modified | 0 missing"
  # A pipe never gets anything but the plain report, whatever the locale.
  run env LC_ALL=en_US.UTF-8 JIG_TERMINAL=0 "$JIG_BIN" status
  assert_not_contains "$OUT" "$rule"
  assert_contains "$OUT" "drift: 0 modified, 0 missing"
}

# Related keys are one row; agent.git says the queue it leaves.
test_status_a_terminal_folds_related_settings_into_one_row() {
  fixture_jig_repo
  printf 'agent.git: pr\nhousekeeping.cadence: 1d\nhousekeeping.fetch: true\nclaude.implement_model: sonnet\nclaude.review_model: opus\nautopilot.parallel: 2\n' \
    > .ai/config.local.yaml
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "-- Settings  (config.local) --"
  assert_contains "$OUT" "  agent.git            pr | review queue: open pull requests"
  assert_contains "$OUT" "  housekeeping         cadence 1d | fetch true"
  assert_contains "$OUT" "  claude               implement_model sonnet | review_model opus"
  assert_contains "$OUT" "  autopilot.parallel   2"
  assert_not_contains "$OUT" "agent.git=pr"
}

# A row of several keys too long for the section goes on under itself.
test_status_a_terminal_wraps_a_long_settings_row() {
  fixture_jig_repo
  printf 'housekeeping.cadence: 1d\nhousekeeping.fetch: true\nhousekeeping.trash_ttl: 0d\nhousekeeping.abandoned_ttl: 7d\nhousekeeping.stale_after: 30d\n' \
    > .ai/config.local.yaml
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  # The column is as wide as the longest label, autopilot.git.
  assert_contains "$OUT" "$(printf '  housekeeping    cadence 1d | fetch true | trash_ttl 0d | abandoned_ttl 7d\n                  stale_after 30d')"
}

# What the folded records look like in the report.
test_status_a_terminal_shows_the_activity_folded() {
  fixture_jig_repo
  fixture_task t-1 task/t-1 active "class:T1"
  fixture_task t-2 task/t-2 active "class:T1"
  fixture_task t-3 task/t-3 active "class:T1"
  mkdir -p .ai/runtime/working
  printf 'command: task show\n' > .ai/runtime/working/t-1
  printf 'command: task show\n' > .ai/runtime/working/t-2
  printf 'command: task show\n' > .ai/runtime/working/t-3
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "-- Recent activity here  (3 records, last "
  assert_contains "$OUT" "task show   2 tasks: t-"
  assert_contains "$OUT" "  .     nothing here holds HEAD | sessions not observable"
  assert_not_contains "$OUT" "working here"
}

# Records of work here, folded: the latest on its own row, the rest one row
# per command and hour, counted, with the first ids that fit.
test_status_a_terminal_folds_the_activity() {
  local f
  f=$(
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/output.sh"
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/status.sh"
    # shellcheck disable=SC2034 # read by out_init, a sourced function
    LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1
    out_init
    printf '%s\t%s\t%s\n' \
      "task a" "task show" "2h" \
      "task b" "task show" "1h" \
      "task c" "artifact append" "40s" \
      "task d" "task show" "1h" \
      "another session" "context" "3h" \
      "another session" "context" "3h" \
      "task e" "task show" "1h" \
      "task f" "task show" "1h" \
      "task g" "task set" "50m" \
      | _status_activity_fold
  )
  assert_eq "$(printf '40s\tc\tartifact append\t\n50m\tg\ttask set\t\n1h\t4 tasks\ttask show\tb, d, e, ...\n2h\ta\ttask show\t\n3h\t2 sessions\tcontext\t\n@oldest\t3h')" "$f"
}

test_status_a_terminal_fits_the_ids_it_names() {
  local f
  f=$(
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/output.sh"
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/status.sh"
    # shellcheck disable=SC2034 # read by out_init, a sourced function
    JIG_TERMINAL=0
    out_init
    _status_fit_ids 32 "composer-overlay, fix-guard, other, ..."; printf '%s\n' "$_STT_FIT"
    _status_fit_ids 25 "composer-overlay, fix-guard"; printf '%s\n' "$_STT_FIT"
    _status_fit_ids 27 "composer-overlay, fix-guard"; printf '%s\n' "$_STT_FIT"
    _status_fit_ids 5 "composer-overlay, fix-guard"; printf '%s\n' "$_STT_FIT"
    _status_fit_ids 80 "a, b"; printf '%s\n' "$_STT_FIT"
  )
  assert_eq "$(printf 'composer-overlay, fix-guard, ...\ncomposer-overlay, ...\ncomposer-overlay, fix-guard\n...\na, b')" "$f"
}

# Who holds HEAD is the rule a refusal uses (jig_checkout_occupants).
test_status_a_terminal_says_who_holds_head() {
  fixture_jig_repo
  git add -A >/dev/null
  git commit -q -m "jig init snapshot"
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null 2>&1
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "  .     task T-1 holds HEAD here | sessions not observable"
  assert_contains "$OUT" "-- Recent activity here  (no records) --"
}

# The readers inside jig: the status page carries the whole plain report, and
# it is drawn by `jig status --html`, by every command's redraw
# (jig_status_page_touch) and from a worktree. None of them may get the
# terminal form, whatever the person's JIG_TERMINAL says.
_status_assert_page_is_plain() {
  local page esc
  esc=$(printf '\033')
  page=$(cat "$1")
  assert_contains "$page" "task t-a class=T2 status=active"
  assert_contains "$page" "drift: 0 modified, 0 missing"
  assert_not_contains "$page" "Tasks  ("
  assert_not_contains "$page" "nothing needs you"
  assert_not_contains "$page" "$esc"
}

test_status_page_keeps_the_plain_report_for_a_terminal_reader() {
  fixture_jig_repo
  fixture_task t-a task/t-a active "class:T2"
  run env JIG_TERMINAL=1 TERM=xterm "$JIG_BIN" status --html
  assert_eq 0 "$RC"
  _status_assert_page_is_plain .ai/runtime/status.html
}

test_status_page_redraw_keeps_the_plain_report_for_a_terminal_reader() {
  fixture_jig_repo
  fixture_task t-a task/t-a active "class:T2"
  jig status --html >/dev/null
  run env JIG_TERMINAL=1 TERM=xterm "$JIG_BIN" task new t-d --class T1
  assert_eq 0 "$RC"
  assert_contains "$(cat .ai/runtime/status.html)" "task t-d class=T1 status=active"
  _status_assert_page_is_plain .ai/runtime/status.html
}

test_status_page_from_a_worktree_keeps_the_plain_report_for_a_terminal_reader() {
  mkdir repo || return 1
  cd repo || return 1
  fixture_jig_repo
  fixture_task t-a task/t-a active "class:T2"
  git add -A
  git commit -q -m "jig init snapshot"
  jig task new T-1 >/dev/null
  local wt main
  main=$(pwd -P)
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  cd "$wt" || return 1
  run env JIG_TERMINAL=1 TERM=xterm "$JIG_BIN" status --html
  assert_eq 0 "$RC"
  _status_assert_page_is_plain "$main/.ai/runtime/status.html"
}

# At a terminal the report is still taken in cmd_status' own shell, so the
# counts it took are the ones saved for the page's next redraw.
test_status_a_terminal_still_refreshes_the_pages_counts() {
  fixture_jig_repo
  jig status --html >/dev/null
  printf 'at: 2000-01-01T00:00:00Z\nproposals: 9\nsources_changed: 0\npending: 0\n' > .ai/runtime/status-counts
  run env JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_file_contains .ai/runtime/status-counts "proposals: 0"
  assert_not_contains "$(cat .ai/runtime/status-counts)" "2000-01-01"
}

# A section someone edited is kept by every upgrade: nothing for them to do.
test_status_a_terminal_counts_a_changed_section_as_fine() {
  fixture_jig_repo
  sed 's/^## Read first$/## Read first (our version)/' AGENTS.md > AGENTS.md.new
  mv AGENTS.md.new AGENTS.md
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "instructions changed here (claude, codex)"
  assert_not_contains "$OUT" "warn  instructions"
}

# A task line is judged by the words the line builder writes, never by a
# worktree path or a pause reason, which a person chose.
test_status_a_terminal_judges_a_task_by_its_own_words_only() {
  local f
  f=$(
    # shellcheck source=/dev/null
    . "$JIG_HOME/scripts/lib/status.sh"
    for l in \
      'task a class=T2 status=active' \
      'task a class=T2 status=active worktree=/x/is paused uncommitted=0' \
      'task a class=T2 status=active worktree=/x lowered=T3 uncommitted=0 autopilot=on' \
      'task a class=T2 status=active paused (see blocking=2 and review=stale)' \
      'task a class=T2 status=active paused' \
      'task a class=T2 status=active lowered=T3' \
      'task a class=T2 status=active worktree=/x uncommitted=1 blocking=2' \
      'task a class=T2 status=active review=stale autopilot=on' \
      'task a class=T2 status=active autopilot=stopped'; do
      if _status_task_needs "$l"; then printf 'need\n'; else printf 'fine\n'; fi
    done
  )
  assert_eq "$(printf 'fine\nfine\nfine\nneed\nneed\nneed\nneed\nneed\nneed')" "$f"
}

test_status_a_terminal_keeps_a_pause_reason_whole() {
  fixture_jig_repo
  fixture_task t-p task/t-p active "class:T1" "paused:true" "paused_reason:waiting (fix: CI)"
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "  warn  task t-p class=T1 status=active paused (waiting (fix: CI))"
  assert_not_contains "$OUT" "      fix: "
}


# --- tasks grouped by epic and spec ---------------------------------------------

# _status_groups_fixture — an epic whose progress is made on its branch, a spec
# without an epic, tasks of each, a task with no spec and one linked to a spec
# that is not here.
_status_groups_fixture() {
  fixture_jig_repo
  mkdir -p .ai/specs/rel .ai/specs/term
  printf '# Release 0.20.0\n' > .ai/specs/rel/spec.md
  printf '%s\n' '# Roadmap' '' 'Epic: epic/rel' '' '## Phase 1 — All' '' \
    '- [ ] one' '- [ ] two' '- [ ] three' '- [ ] four' '- [ ] five' > .ai/specs/rel/roadmap.md
  printf '# Terminal output people can read\n' > .ai/specs/term/spec.md
  printf '%s\n' '## Phase 1 — One' '' '- [x] a' '- [ ] b' '- [ ] c' '- [ ] d' '- [ ] e' \
    > .ai/specs/term/roadmap.md
  git add -A
  git commit -q -m "specs"
  git checkout -q -b epic/rel
  printf '%s\n' '# Roadmap' '' 'Epic: epic/rel' '' '## Phase 1 — All' '' \
    '- [x] one' '- [x] two' '- [x] three' '- [ ] four' '- [ ] five' > .ai/specs/rel/roadmap.md
  git commit -q -am "progress on the epic"
  git checkout -q main
  fixture_task a-loose task/a-loose active "class:T2"
  fixture_task b-rel task/b-rel active "class:T3"
  fixture_task c-term task/c-term active "class:T2"
  fixture_task d-rel task/d-rel active "class:T2"
  fixture_task e-gone task/e-gone active "class:T0"
  printf '\nSpec: .ai/specs/rel/ — Phase 1\n' >> .ai/workspace/tasks/b-rel/task.md
  printf '\nSpec: .ai/specs/term/\n' >> .ai/workspace/tasks/c-term/task.md
  printf '\nSpec: .ai/specs/rel/ — Phase 1\n' >> .ai/workspace/tasks/d-rel/task.md
  printf '\nSpec: .ai/specs/gone/\n' >> .ai/workspace/tasks/e-gone/task.md
}

# _status_tasks_section <report> — the Tasks section of a terminal report.
_status_tasks_section() {
  printf '%s\n' "$1" | awk '/^-- Tasks|^── Tasks/ { on = 1 } on && $0 == "" { on = 0; done = 1 } on && !done { print }'
}

test_status_a_terminal_groups_tasks_by_epic_and_spec() {
  _status_groups_fixture
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_eq "$(printf '%s\n' \
    '-- Tasks  (5 active) -----------------------------------------------------------' \
    '  Release 0.20.0  (epic | 3/5 done)' \
    '  |- T3  b-rel' \
    '  `- T2  d-rel' \
    '  Terminal output people can read  (spec | 1/5 done)' \
    '  `- T2  c-term' \
    '  Other tasks' \
    '  |- T2  a-loose' \
    '  `- T0  e-gone' \
    '  .   current task: none')" "$(_status_tasks_section "$OUT")"
}

test_status_a_terminal_draws_the_groups_tree_in_utf8_and_colour() {
  local e mid end dot
  skip_unless_utf8_locale
  _status_groups_fixture
  e=$(printf '\033')
  mid=$(printf '\342\224\234\342\224\200')
  end=$(printf '\342\224\224\342\224\200')
  dot=$(printf '\302\267')
  run env -u LC_ALL -u LC_CTYPE LANG=en_US.UTF-8 JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "  Release 0.20.0  (epic $dot 3/5 done)"
  assert_contains "$OUT" "  $mid T3  b-rel"
  assert_contains "$OUT" "  $end T2  d-rel"
  run env -u NO_COLOR LC_ALL=C TERM=xterm JIG_TERMINAL=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "  ${e}[1mRelease 0.20.0${e}[0m  ${e}[2m(epic | 3/5 done)${e}[0m"
  assert_contains "$OUT" "  ${e}[2m|-${e}[0m ${e}[33mT3${e}[0m  ${e}[1mb-rel${e}[0m"
  assert_contains "$OUT" "  ${e}[1mOther tasks${e}[0m"
}

# A task that needs the reader is under "Needs you", and a group left with
# none of its tasks is not drawn; with no task of a spec left, no group is.
test_status_a_terminal_draws_only_groups_that_have_rows() {
  _status_groups_fixture
  fixture_task c-term task/c-term active "class:T2" "paused:true"
  printf '\nSpec: .ai/specs/term/\n' >> .ai/workspace/tasks/c-term/task.md
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_not_contains "$(_status_tasks_section "$OUT")" "Terminal output"
  assert_contains "$OUT" "  warn  task c-term class=T2 status=active paused"
  rm .ai/workspace/tasks/b-rel/task.md .ai/workspace/tasks/d-rel/task.md
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_not_contains "$OUT" "Other tasks"
  assert_contains "$(_status_tasks_section "$OUT")" "$(printf '%s\n' '  T2  a-loose' '  T3  b-rel')"
}

# The plain report keeps its `task ...` lines, in their order, ungrouped.
test_status_a_pipe_does_not_group_tasks() {
  _status_groups_fixture
  run env JIG_TERMINAL=0 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "Other tasks"
  assert_not_contains "$OUT" "Release 0.20.0"
  assert_eq "$(printf '%s\n' \
    'task a-loose class=T2 status=active' 'task b-rel class=T3 status=active' \
    'task c-term class=T2 status=active' 'task d-rel class=T2 status=active' \
    'task e-gone class=T0 status=active')" "$(printf '%s\n' "$OUT" | grep '^task ')"
}

test_status_page_groups_running_tasks_by_epic_and_spec() {
  _status_groups_fixture
  run jig status --html
  assert_eq 0 "$RC"
  local tasks order
  tasks=$(status_page_section "$(cat .ai/runtime/status.html)" tasks)
  assert_contains "$tasks" '<h3><code>rel</code> Release 0.20.0 <span class="badge">epic</span> <span class="muted"><span class="bar"><span style="width: 60%"></span></span>3/5 done</span></h3>'
  assert_contains "$tasks" '<h3><code>term</code> Terminal output people can read <span class="badge">spec</span> <span class="muted"><span class="bar"><span style="width: 20%"></span></span>1/5 done</span></h3>'
  order=$(printf '%s\n' "$tasks" | sed -n \
    -e 's/^<h3><code>\([^<]*\)<.*/[\1]/p' -e 's/^<h3>Other tasks<\/h3>$/[other]/p' \
    -e 's/^<tr><td class="id"><code>\([^<]*\)<.*/\1/p' | tr '\n' ' ')
  assert_eq "[rel] b-rel d-rel [term] c-term [other] a-loose e-gone " "$order"
}

# An epic whose branch is not here has no progress to show, only its kind; a
# task linked to two specs belongs to neither.
test_status_a_terminal_groups_without_a_count_or_a_guess() {
  _status_groups_fixture
  git branch -q -D epic/rel
  printf '\nSpec: .ai/specs/rel/\n' >> .ai/workspace/tasks/c-term/task.md
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "$(printf '%s\n' '  Release 0.20.0  (epic)' '  |- T3  b-rel' '  `- T2  d-rel' \
    '  Other tasks' '  |- T2  a-loose' '  |- T2  c-term' '  `- T0  e-gone')"
  assert_not_contains "$OUT" "Terminal output people can read"
}

# --- tracker issue (adr-20261010-a-task-carries-its-tracker-issue) -------------

test_status_names_a_tasks_tracker_issue() {
  fixture_jig_repo
  printf 'task.issue_pattern: [A-Z]+-[0-9]+\n' >> .ai/config.yaml
  jig task new SRD-9-fix --class T1 >/dev/null
  jig task new other --class T1 >/dev/null
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "task SRD-9-fix class=T1 status=active issue=SRD-9"
  assert_contains "$OUT" "task other class=T1 status=active"
  assert_not_contains "$OUT" "task other class=T1 status=active issue"
}

# --- status --json: what needs the reader, as data ---------------------------
#
# The contract: schemas/json.md describes the shape these tests pin, and the
# page's "Needs you" is built from the same items (_status_attention), which
# the agreement test below proves.

# _st_json [args] — `jig status --json <args>` with stdout in OUT, stderr in
# ERR, generated_at replaced by T once its form is checked and revision by R
# (pinned by tests/json.t.sh, not here).
_st_json() {
  local out err at
  out=$(_run_out)
  err=$(_run_out .err)
  ( jig status --json "$@" ) >"$out" 2>"$err"
  RC=$?
  OUT=$(cat "$out")
  ERR=$(cat "$err")
  rm -f "$out" "$err"
  at=$(printf '%s\n' "$OUT" | sed -n 's/.*"generated_at":"\([^"]*\)".*/\1/p')
  case "$at" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) fail "generated_at is not a UTC timestamp: [$at] in $OUT" ;;
  esac
  case "$OUT" in
    '{"schema":1,"revision":'[0-9]*) ;;
    *) fail "revision is not an integer in $OUT" ;;
  esac
  OUT=$(printf '%s\n' "$OUT" | sed 's/"generated_at":"[^"]*"/"generated_at":"T"/; s/"revision":[^,]*,/"revision":R,/')
}

test_status_json_says_when_nothing_needs_you() {
  fixture_jig_repo
  # No global jig: one newer than this checkout would be something to do.
  PATH=$(_status_path_without_jig)
  mkdir -p .ai/runtime
  printf 'at: 2026-10-15T08:00:00Z\nproposals: 0\nsources_changed: 0\npending: 0\n' > .ai/runtime/status-counts
  _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_eq '{"schema":1,"revision":R,"generated_at":"T","data":{"attention":[],"housekeeping":null,"knowledge_counts_at":"2026-10-15T08:00:00Z"}}' "$OUT"
}

# Every field of an item, and of the data around it, pinned whole.
test_status_json_pins_an_item_with_every_field() {
  export TZ=UTC
  fixture_jig_repo
  fixture_task shipped task/shipped ready "class:T2" "knowledge_consolidated:true" \
    "pr_url:https://example.com/o/r/pull/7"
  fixture_task given-up task/given-up abandoned "class:T2"
  mkdir -p .ai/runtime
  printf 'at: 2026-10-15T08:00:00Z\nproposals: 2\nsources_changed: 0\npending: 0\n' > .ai/runtime/status-counts
  {
    printf -- '--- run 2026-10-01T09:30:00Z forge=github\n'
    printf '2026-10-01T09:30:00Z task=given-up status=abandoned remote=open via=forge action=preserve\n'
  } > .ai/runtime/housekeeping.log
  _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_eq '{"schema":1,"revision":R,"generated_at":"T","data":{"attention":[{"kind":"pull-request-waiting","subject":{"type":"task","id":"shipped"},"tasks":["shipped"],"title":"A pull request is waiting for review or merge","detail":"opened by jig task ship","todo":"Review it and merge it; jig merges one itself only at agent.git: merge, on green CI.","url":"https://example.com/o/r/pull/7"},{"kind":"pull-request-of-abandoned-task","subject":{"type":"task","id":"given-up"},"tasks":["given-up"],"title":"A pull request was open for a task you abandoned","detail":"open as of housekeeping at 2026-10-01 09:30 UTC","todo":"It may have been closed or merged since: jig last asked the forge then. Run jig housekeeping to refresh, then close on the forge what is still open, or reopen the task. Nothing here will merge it.","url":null},{"kind":"knowledge-proposed","subject":{"type":"project","id":null},"tasks":[],"title":"Knowledge is waiting for your decision","detail":"2 document(s) proposed","todo":"Ask the agent: what'"'"'s proposed? (jig-accept)","url":null}],"housekeeping":{"ran_at":"2026-10-01T09:30:00Z","forge":"github","stale":true},"knowledge_counts_at":"2026-10-15T08:00:00Z"}}' "$OUT"
}

# _st_json_cards <envelope> — each item of `jig status --json` drawn as the
# page draws a card (_status_card), one per line: the label is the task id,
# `phase <id>` for a phase and nothing for the project; the url is a link when
# it is https. Values are compared unescaped, so the fixture keeps them free
# of `"`, `<` and `>`.
_st_json_cards() {
  local item kind stype sid title detail todo url label line
  printf '%s\n' "$1" | sed 's/^.*"attention":\[{//; s/}\],"housekeeping".*$//; s/},{"kind"/\
"kind"/g' | while IFS= read -r item; do
    [ -n "$item" ] || continue
    kind=$(printf '%s\n' "$item" | sed -n 's/^"kind":"\([^"]*\)".*/\1/p')
    stype=$(printf '%s\n' "$item" | sed -n 's/.*"subject":{"type":"\([^"]*\)".*/\1/p')
    sid=$(printf '%s\n' "$item" | sed -n 's/.*"subject":{"type":"[^"]*","id":"\([^"]*\)"}.*/\1/p')
    title=$(printf '%s\n' "$item" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')
    detail=$(printf '%s\n' "$item" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
    todo=$(printf '%s\n' "$item" | sed -n 's/.*"todo":"\([^"]*\)".*/\1/p')
    url=$(printf '%s\n' "$item" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
    label=$sid
    [ "$stype" != phase ] || label="phase $sid"
    line="<div class=\"card\"><h3>$title</h3>"
    if [ -n "$label" ] || [ -n "$detail" ]; then
      line="$line<p>"
      [ -z "$label" ] || line="$line<code>$label</code>"
      [ -z "$label" ] || [ -z "$detail" ] || line="$line · "
      line="$line$detail</p>"
    fi
    case "$url" in
      https://*) line="$line<p><a href=\"$url\">$url</a></p>" ;;
      ?*) line="$line<p><code>$url</code></p>" ;;
    esac
    printf '%s<p class="todo">%s</p></div>\n' "$line" "$todo"
    printf '%s\n' "$kind" >> "$2"
  done
}

# The page and the data read one source: every kind of item, and the page's
# cards say exactly what the items say — title, subject, detail, what to do,
# link — in the same order, with the badge on the two stopped kinds.
test_status_json_and_the_page_name_the_same_items() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local t stub_root stub_bin path_dir p
  for t in ph-1 ph-2; do
    jig task new "$t" --class T2 >/dev/null
    jig task start "$t" >/dev/null 2>&1 || true
    jig task autopilot "$t" start --phase alpha/1 >/dev/null
    jig task autopilot "$t" stop --reason "question from $t" >/dev/null
  done
  jig task new solo --class T2 >/dev/null
  jig task autopilot solo start >/dev/null
  jig task autopilot solo stop --reason "a question & an answer" >/dev/null
  fixture_task gate-w task/gate-w active "class:T3"
  printf '# Design\n' > .ai/workspace/tasks/gate-w/design.md
  fixture_task gate-c task/gate-c active "class:T3"
  printf '# Design\n' > .ai/workspace/tasks/gate-c/design.md
  jig task gate gate-c approved >/dev/null
  printf 'changed\n' >> .ai/workspace/tasks/gate-c/design.md
  fixture_task done-1 task/done-1 ready "class:T2" "knowledge_consolidated:true"
  fixture_task shipped task/shipped ready "class:T2" "knowledge_consolidated:true" \
    "pr_url:https://example.com/o/r/pull/7"
  fixture_task waiting task/waiting consolidated "class:T2" "pr_url:https://example.com/o/r/pull/9"
  fixture_task given-up task/given-up abandoned "class:T2"
  fixture_task landed task/landed ready "class:T2"
  fixture_task elsewhere task/elsewhere active "class:T2"
  fixture_task unmerged task/unmerged active "class:T2"
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-22T00:00:00Z task=waiting status=consolidated remote=open via=forge action=preserve\n'
    printf '2026-09-22T00:00:00Z task=given-up status=abandoned remote=open via=forge action=preserve\n'
    printf '2026-09-22T00:00:00Z task=landed status=ready remote=merged via=forge action=preserve flags=needs-consolidation\n'
    printf '2026-09-22T00:00:00Z task=elsewhere status=active remote=unknown via=forge action=preserve flags=wrong-base\n'
    printf '2026-09-22T00:00:00Z task=unmerged status=active remote=closed via=forge action=preserve flags=abandoned?\n'
    printf '2026-09-22T00:00:00Z task=no-path-logged status=consolidated remote=merged via=forge action=preserve flags=worktree-kept\n'
  } > .ai/runtime/housekeeping.log
  # A newer jig is out than the one on PATH (test_status_html_shows_a_card_for_a_new_release).
  stub_root=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stub.XXXXXX")
  stub_bin=$(mktemp -d "${TMPDIR:-/tmp}/jig-status-stubbin.XXXXXX")
  # It is newer than this project's too, so the project is also behind it.
  path_dir=$(_status_make_stub_global "$stub_root" "$stub_bin" 'JIG_VERSION="9.0.0"')
  p=$(_status_path_without_jig "$path_dir")
  printf 'latest=9.1.0\nchecked_at=2026-09-30T00:00:00Z\n' > .ai/runtime/latest-release
  env PATH="$p" "$JIG_BIN" status --html >/dev/null
  printf 'at: 2026-10-15T08:00:00Z\nproposals: 2\nsources_changed: 1\npending: 0\n' > .ai/runtime/status-counts
  env PATH="$p" "$JIG_BIN" status --refresh
  OUT=$(env PATH="$p" "$JIG_BIN" status --json 2>/dev/null)
  rm -rf "$stub_root" "$stub_bin"

  local needs page_cards json_cards kinds
  needs=$(status_page_section "$(cat .ai/runtime/status.html)" needs)
  page_cards=$(printf '%s\n' "$needs" | grep '^<div class="card">' \
    | sed 's/ <span class="badge warn">autopilot stopped<\/span>//' \
    | sed "s/&#39;/'/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/\"/g; s/&amp;/\\&/g" \
    | status_stop_ages_masked)
  : > kinds.txt
  # The page and the JSON are drawn moments apart, and a stop's age can cross
  # a minute between them.
  json_cards=$(_st_json_cards "$OUT" kinds.txt | status_stop_ages_masked)
  kinds=$(tr '\n' ' ' < kinds.txt)
  assert_eq "release-available upgrade-available phase-stopped autopilot-stopped gate-changed gate-waiting git-step pull-request-waiting pull-request-was-open pull-request-of-abandoned-task needs-consolidation wrong-base closed-unmerged worktree-kept knowledge-proposed sources-changed " "$kinds"
  assert_eq "$page_cards" "$json_cards"
  # The badge is the stopped kinds' and only theirs.
  assert_eq 2 "$(printf '%s\n' "$needs" | grep -c '<span class="badge warn">autopilot stopped</span>')"
  assert_contains "$needs" 'A phase run is waiting for you <span class="badge warn">autopilot stopped</span>'
  assert_contains "$needs" 'Autopilot stopped and is waiting for you <span class="badge warn">autopilot stopped</span>'
  assert_contains "$OUT" '"subject":{"type":"phase","id":"alpha/1"},"tasks":["ph-1","ph-2"]'
  assert_contains "$OUT" '"subject":{"type":"project","id":null},"tasks":[]'
}

# A task worktree borrows the owner's workspaces (ADR-0029), and reads the
# owner's housekeeping log and counts as the page does: an agent working in a
# worktree is told what the person's page says.
test_status_json_in_a_worktree_reads_the_main_checkout() {
  fixture_jig_repo
  jig task new T-1 --class T2 >/dev/null
  local wt
  wt=$(jig task start T-1 --worktree 2>/dev/null)
  mkdir -p .ai/runtime
  {
    printf -- '--- run %s forge=github\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '2026-09-22T00:00:00Z task=T-1 status=active remote=closed via=forge action=preserve flags=abandoned?\n'
  } > .ai/runtime/housekeeping.log
  printf 'at: 2026-10-15T08:00:00Z\nproposals: 3\nsources_changed: 0\npending: 0\n' > .ai/runtime/status-counts
  local main
  main=$(jig status --json 2>/dev/null | sed 's/"generated_at":"[^"]*"//')
  OUT=$(cd "$wt" && jig status --json 2>/dev/null | sed 's/"generated_at":"[^"]*"//')
  assert_contains "$OUT" '"kind":"closed-unmerged","subject":{"type":"task","id":"T-1"}'
  assert_contains "$OUT" '"detail":"3 document(s) proposed"'
  assert_contains "$OUT" '"housekeeping":{"ran_at":"'
  assert_eq "$main" "$OUT"
  assert_no_file "$wt/.ai/runtime/status-counts"
}

test_status_json_reports_a_refusal_as_an_envelope() {
  fixture_jig_repo
  _st_json --nope
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":R,"generated_at":"T","error":{"code":"usage","message":"status --json: unknown argument: --nope (usage: jig status --json)"}}' "$OUT"
  assert_contains "$ERR" "jig: error: status --json: unknown argument: --nope"
  # --json may stand anywhere; beside a page mode it is refused, and the
  # refusal writes no page.
  _st_json --html
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"code":"usage","message":"status --json: unknown argument: --html'
  assert_no_file .ai/runtime/status.html
}

test_status_json_in_an_uninitialised_project_is_an_envelope() {
  fixture_repo
  _st_json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"not-initialised","message":"status --json: project is not initialised; run: jig init"}}'
  assert_no_file .ai
}

test_status_json_outside_git_is_an_envelope() {
  mkdir plain
  cd plain || return 1
  _st_json
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"not-a-repository","message":"not inside a git repository"}}'
  assert_not_contains "$OUT" '"data"'
}

# A read never asks the forge and writes nothing: no page, no counts.
test_status_json_never_reaches_the_network_and_writes_nothing() {
  fixture_jig_repo
  fixture_task shipped task/shipped ready "class:T2" "knowledge_consolidated:true" \
    "pr_url:https://github.com/example/example/pull/7"
  git remote add origin https://example.invalid/repo.git
  mkdir bin
  printf '#!/bin/sh\necho called >> "%s/gh.called"\nexit 1\n' "$PWD" > bin/gh
  chmod +x bin/gh
  local before
  # The dispatcher's own record of who is working here is the one write a
  # read may cause (convention json-output): it is not this command's.
  before=$(find .ai -type f ! -path .ai/runtime/checkout ! -path '.ai/runtime/working/*' | sort)
  PATH="$PWD/bin:$PATH" GIT_TRACE="$PWD/git.trace" _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"kind":"pull-request-waiting"'
  assert_no_file gh.called
  assert_no_file .ai/runtime/status.html
  assert_no_file .ai/runtime/status-counts
  assert_eq "$before" "$(find .ai -type f ! -path .ai/runtime/checkout ! -path '.ai/runtime/working/*' | sort)"
  assert_not_contains "$(cat git.trace)" "fetch"
  assert_not_contains "$(cat git.trace)" "ls-remote"
}

# The text report is not touched by --json existing: the same bytes as the
# plain report the page embeds.
test_status_json_leaves_the_text_report_unchanged() {
  fixture_jig_repo
  fixture_task done-1 task/done-1 ready "class:T2" "knowledge_consolidated:true"
  local before
  before=$(jig status 2>&1)
  _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_eq "$before" "$(jig status 2>&1)"
}

# --- the queue in the report (jig_queue_place, jig_pause_request) ------------------

# _stq_setup [ids...] — an installed project with a filed task for each id.
_stq_setup() {
  local id
  fixture_jig_repo
  for id in "$@"; do
    fixture_task "$id" "task/$id" active
  done
}

# _stq_epic <spec> <task>... — a spec whose roadmap declares an open epic, and
# tasks linked to it by their Spec: line.
_stq_epic() {
  local spec="$1" id
  shift
  mkdir -p ".ai/specs/$spec"
  printf '# %s\n' "$spec" > ".ai/specs/$spec/spec.md"
  printf '# Roadmap\n\nEpic: epic/%s\n\n## Phase 1 — One\n' "$spec" > ".ai/specs/$spec/roadmap.md"
  for id in "$@"; do
    fixture_task "$id" "task/$id" active
    printf '# %s\n\nSpec: .ai/specs/%s/ — Phase 1\n' "$id" "$spec" > ".ai/workspace/tasks/$id/task.md"
  done
}


# _stq_age_request <id> — make the pause request of <id> years old, so its age is
# counted in days and no test meets a minute boundary.
_stq_age_request() {
  awk -F '\t' -v r="task:$1" 'BEGIN { OFS = "\t" } $1 == "request" && $2 == r { $4 = "2020-01-01T00:00:00Z" } { print }' \
    .ai/runtime/queue > queue.tmp && mv queue.tmp .ai/runtime/queue
}

# _stq_task_block <id> — the `task <id>` line of the plain status report in OUT,
# with the indented lines under it.
_stq_task_block() {
  printf '%s\n' "$OUT" | awk -v t="task $1 " '
    index($0, t) == 1 { on = 1; print; next }
    on && /^  / { print; next }
    { on = 0 }
  '
}

test_status_queue_without_a_queue_shows_no_place() {
  _stq_setup a
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_eq "task a class= status=active" "$(_stq_task_block a)"
  run jig context --task a --files x
  assert_not_contains "$OUT" "queue:"
}

test_status_queue_shows_rank_priority_dependencies_and_a_pause_request() {
  _stq_setup a b c
  jig queue set a --priority 1 >/dev/null
  jig queue move b --bottom >/dev/null
  jig queue depend b --on a --reason "needs the format" >/dev/null
  jig queue depend b --on task:c --reason "reads it" >/dev/null
  jig queue request b pause --reason "standup" >/dev/null
  _stq_age_request b
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_eq "task a class= status=active queue=1/2 priority=1" "$(_stq_task_block a)"
  local block
  block=$(_stq_task_block b)
  assert_eq "task b class= status=active queue=2/2" "$(printf '%s\n' "$block" | sed -n 1p)"
  assert_eq "  waits for task:a: needs the format" "$(printf '%s\n' "$block" | sed -n 2p)"
  assert_eq "  waits for task:c: reads it" "$(printf '%s\n' "$block" | sed -n 3p)"
  printf '%s\n' "$block" | sed -n 4p | grep -Eq '^  pause requested [0-9]+ days ago: standup$' \
    || fail "no pause request line: $block"
  # A pause request of a task that is not queued shows too: c is only waited for.
  jig queue request c pause >/dev/null
  _stq_age_request c
  run jig status
  block=$(_stq_task_block c)
  printf '%s\n' "$block" | grep -Eq '^task c class= status=active$' || fail "c is queued: $block"
  printf '%s\n' "$block" | grep -Eq '^  pause requested [0-9]+ days ago$' || fail "no request of c: $block"
}

test_status_queue_ranks_a_task_within_its_epics_level() {
  _stq_setup a
  _stq_epic big t1 t2
  jig queue move a --top >/dev/null
  jig queue move t1 --bottom >/dev/null
  jig queue move t2 --top >/dev/null
  run jig status
  assert_contains "$OUT" "task t2 class= status=active queue=1/2"
  assert_contains "$OUT" "task t1 class= status=active queue=2/2"
  assert_contains "$OUT" "task a class= status=active queue=1/1"
}

test_status_queue_reads_no_queue_of_another_format_version() {
  _stq_setup a
  jig queue set a --priority 1 >/dev/null
  jig queue request a pause >/dev/null
  sed '1s/^# jig queue 1/# jig queue 2/' .ai/runtime/queue > queue.tmp && mv queue.tmp .ai/runtime/queue
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_eq "task a class= status=active" "$(_stq_task_block a)"
}

test_status_queue_terminal_shows_the_place_as_notes() {
  _stq_setup a b c
  jig queue set a --priority 2 >/dev/null
  jig queue depend b --on a --reason "after a" >/dev/null
  jig queue request b pause >/dev/null
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC" "$OUT"
  local row
  row=$(printf '%s\n' "$OUT" | grep ' a  ' | head -1)
  assert_contains "$row" "queue 1/2"
  assert_contains "$row" "priority 2"
  row=$(printf '%s\n' "$OUT" | grep ' b  ' | head -1)
  assert_contains "$row" "queue 2/2"
  assert_contains "$row" "waits for task:a: after a"
  assert_contains "$row" "pause requested"
  # A task that needs the reader carries what it waits for as a detail.
  jig task pause c >/dev/null
  jig queue depend c --on b --reason "after b" >/dev/null
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC" "$OUT"
  printf '%s\n' "$OUT" | grep -Eq '^ +queue: waits for task:b: after b$' || fail "no detail: $OUT"
}

# --- the queue's advice (next-advice-readers; adr-20261022-the-next-task-is-advised-from-the-queue) ---

# _status_next_queue — an installed project with two filed tasks and a queue.
_status_next_queue() {
  fixture_jig_repo
  fixture_task a task/a active "class:T1"
  fixture_task b task/b active "class:T1"
  jig queue set a --priority 1 >/dev/null
  jig queue set b --priority 2 >/dev/null
}

test_status_prints_the_queue_advice_when_a_queue_exists() {
  local want
  _status_next_queue
  run jig queue next
  assert_eq 0 "$RC" "$OUT"
  want=$(printf '%s\n' "$OUT" | sed -n 1p)
  assert_contains "$want" "next: task:a — "
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_eq 1 "$(printf '%s\n' "$OUT" | grep -c '^next: ')"
  assert_eq "$want" "$(printf '%s\n' "$OUT" | grep '^next: ')"
  # After the task lines, before the current task.
  assert_eq "next: " "$(printf '%s\n' "$OUT" | grep -A1 '^task b ' | sed -n 2p | cut -c1-6)"
}

test_status_prints_next_none_with_the_reason_when_nothing_is_advised() {
  fixture_jig_repo
  fixture_task a task/a active "class:T1"
  jig queue set a --priority 1 >/dev/null
  jig task pause a >/dev/null
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "next: none — every queued task is paused"
  assert_eq 1 "$(printf '%s\n' "$OUT" | grep -c '^next: ')"
}

test_status_has_no_advice_line_without_a_queue_file() {
  fixture_jig_repo
  fixture_task a task/a active "class:T1"
  [ ! -f .ai/runtime/queue ] || fail "the fixture has a queue"
  run jig status
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "next:"
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "next:"
}

test_status_terminal_shows_the_advice_among_the_tasks_and_not_under_needs() {
  _status_next_queue
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "next: task:a — "
  # Whatever else needs the reader (the fixture has no session hook), not this.
  assert_not_contains "$OUT" "warn  next:"
  assert_eq "" "$(printf '%s\n' "$OUT" | awk '/^-- /{s=$2} /next: task:a/ && s=="Needs"{print "needs"}')"
  # The row sits in the tasks section.
  assert_eq "Tasks" "$(printf '%s\n' "$OUT" | awk '/^-- /{s=$2} /next: task:a/{print s}')"
  # `next: none` is an answer too, never an item that needs the reader.
  jig task pause a >/dev/null
  jig task pause b >/dev/null
  run env LC_ALL=C JIG_TERMINAL=1 NO_COLOR=1 "$JIG_BIN" status
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "next: none — every queued task is paused"
  assert_eq "Tasks" "$(printf '%s\n' "$OUT" | awk '/^-- /{s=$2} /next: none/{print s}')"
  assert_not_contains "$OUT" "warn  next:"
}

test_status_html_shows_the_next_task_only_with_a_queue() {
  local page
  fixture_jig_repo
  fixture_task a task/a active "class:T1"
  run jig status --html
  assert_eq 0 "$RC" "$OUT"
  page=$(cat .ai/runtime/status.html)
  assert_not_contains "$page" "Next task"
  jig queue set a --priority 1 >/dev/null
  run jig status --html
  assert_eq 0 "$RC" "$OUT"
  page=$(cat .ai/runtime/status.html)
  assert_contains "$page" "<dt>Next task</dt><dd>task:a — "
}

test_status_json_is_unchanged_by_the_queue() {
  _status_next_queue
  run jig status --json
  assert_not_contains "$OUT" "next:"
}

# --- an upgrade's pull request (task upgrade-land) ----------------------------

# _st_upgrade_pr_repo — an installed project committed on main, no global jig
# on PATH, saved counts with nothing to decide, and a forge cache holding the
# lines given as arguments.
_st_upgrade_pr_repo() {
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init"
  PATH=$(_status_path_without_jig)
  mkdir -p .ai/runtime
  printf 'at: 2026-10-15T08:00:00Z\nproposals: 0\nsources_changed: 0\npending: 0\n' > .ai/runtime/status-counts
  printf '%s\n' "$@" > .ai/runtime/forge-cache
}

# An upgrade waiting for its merge is something a program keeps showing after
# a restart: read from the forge cache, never from the program's memory.
test_status_names_an_upgrade_pull_request_waiting_for_its_merge() {
  local t
  t=$(printf '\t')
  _st_upgrade_pr_repo "jig/upgrade-9.9.9${t}main${t}open${t}pending${t}2026-10-20T10:00:00Z${t}abc123${t}https://github.com/o/r/pull/12" \
    "task/other${t}main${t}open${t}green${t}2026-10-20T10:00:00Z${t}def456${t}https://github.com/o/r/pull/11"
  _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"attention":[{"kind":"upgrade-pull-request-waiting","subject":{"type":"project","id":null},"tasks":[],"title":"An upgrade of Jig waits for its pull request to be merged","detail":"jig/upgrade-9.9.9 into main, open as of 2026-10-20T10:00:00Z","todo":"Review and merge the pull request, then run jig upgrade --land to bring it here.","url":"https://github.com/o/r/pull/12","pull_request":{"branch":"jig/upgrade-9.9.9","base":"main","state":"open","fetched_at":"2026-10-20T10:00:00Z"},"versions":{"to":"9.9.9"}}]'

  run jig status
  assert_eq 0 "$RC"
  # shellcheck disable=SC2016
  assert_contains "$OUT" 'upgrade pull request: jig/upgrade-9.9.9 into main open as of 2026-10-20T10:00:00Z (https://github.com/o/r/pull/12); merge it, then run `jig upgrade --land`'
}

# Merged on the forge, but main here still records the old Jig: the item asks
# for `jig upgrade --land`. A cache line written before the head and url
# columns existed still reads, with no url.
test_status_names_a_merged_upgrade_not_brought_here() {
  local t version
  t=$(printf '\t')
  _st_upgrade_pr_repo "jig/upgrade-9.9.9-2${t}main${t}merged${t}-${t}2026-10-20T10:00:00Z"
  version=$(_status_project_version)
  _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '{"kind":"upgrade-pull-request-merged","subject":{"type":"project","id":null},"tasks":[],"title":"An upgrade of Jig was merged but is not here yet","detail":"jig/upgrade-9.9.9-2 merged into main as of 2026-10-20T10:00:00Z; main here is still at '"$version"'","todo":"jig upgrade --land","url":null,"pull_request":{"branch":"jig/upgrade-9.9.9-2","base":"main","state":"merged","fetched_at":"2026-10-20T10:00:00Z"},"versions":{"to":"9.9.9"}}'

  run jig status
  # shellcheck disable=SC2016
  assert_contains "$OUT" "upgrade pull request: jig/upgrade-9.9.9-2 merged into main as of 2026-10-20T10:00:00Z, main here is still at $version; run \`jig upgrade --land\`"

  # Once main here carries the version, the merged upgrade is history.
  sed 's/^jig\.version: .*/jig.version: 9.9.9/' .ai/manifest > manifest.tmp
  mv manifest.tmp .ai/manifest
  git commit -q -am "landed"
  _st_json
  assert_not_contains "$OUT" "upgrade-pull-request"
  run jig status
  assert_not_contains "$OUT" "upgrade pull request:"
}

# Only Jig's own upgrade branches into the base, and only their newest pull
# request: a closed one, one into another base and a branch of somebody
# else's make no item.
test_status_upgrade_pull_request_items_read_only_the_newest_into_the_base() {
  local t
  t=$(printf '\t')
  _st_upgrade_pr_repo "jig/upgrade-9.9.9${t}main${t}closed${t}-${t}2026-10-21T10:00:00Z${t}-${t}-" \
    "jig/upgrade-9.9.9${t}main${t}open${t}-${t}2026-10-20T10:00:00Z${t}-${t}-" \
    "jig/upgrade-8.8.8${t}develop${t}open${t}-${t}2026-10-20T10:00:00Z${t}-${t}-" \
    "my/upgrade-7.7.7${t}main${t}open${t}-${t}2026-10-20T10:00:00Z${t}-${t}-"
  _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_not_contains "$OUT" "upgrade-pull-request"
}

# While an upgrade waits on its pull request, `upgrade-available` is not said:
# a second `jig upgrade` would only cut a second branch for it (fapost-core
# #322 and #323).
test_status_json_holds_upgrade_available_back_while_an_upgrade_waits() {
  local t
  t=$(printf '\t')
  _st_upgrade_pr_repo "jig/upgrade-9.0.0${t}main${t}open${t}-${t}2026-10-20T10:00:00Z${t}-${t}https://github.com/o/r/pull/12"
  _st_upgrade_item 9.0.0
  assert_eq "" "$ITEM" "upgrade-available was offered beside the waiting upgrade"
  assert_contains "$OUT" '"kind":"upgrade-pull-request-waiting"'
  rm -f .ai/runtime/forge-cache
  _st_upgrade_item 9.0.0
  assert_contains "$ITEM" '"kind":"upgrade-available"'
}

# Right after `jig upgrade --land` the cache may still say open: a base here
# that already records the version makes no item. A branch name with no
# version reads as `"to": null`.
test_status_upgrade_waiting_is_quiet_once_the_base_has_its_version() {
  local t
  t=$(printf '\t')
  _st_upgrade_pr_repo "jig/upgrade-9.9.9${t}main${t}open${t}-${t}2026-10-20T10:00:00Z${t}-${t}-" \
    "jig/upgrade-later${t}main${t}open${t}-${t}2026-10-20T10:00:00Z${t}-${t}-"
  sed 's/^jig\.version: .*/jig.version: 9.9.9/' .ai/manifest > manifest.tmp
  mv manifest.tmp .ai/manifest
  git commit -q -am "landed"
  _st_json
  assert_eq 0 "$RC" "$ERR"
  assert_not_contains "$OUT" '"branch":"jig/upgrade-9.9.9"'
  assert_contains "$OUT" '"pull_request":{"branch":"jig/upgrade-later","base":"main","state":"open","fetched_at":"2026-10-20T10:00:00Z"},"versions":{"to":null}}'
}
