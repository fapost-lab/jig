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
