# Tests for `jig upgrade` (domains/install decision table, ADR-0003).
# shellcheck shell=bash

# _mk_source_v2 <dest> — a modified copy of $JIG_HOME: a changed profile
# script, a bumped version, and a brand-new skill (with a slash invocation,
# so the codex transform is exercised on install too).
_mk_source_v2() {
  local dest="$1"
  cp -R "$JIG_HOME"/. "$dest"/
  rm -rf "$dest/.git"
  printf '\n# v2 marker\n' >> "$dest/profiles/generic/verify.sh"
  mkdir -p "$dest/skills/jig-newthing"
  cat > "$dest/skills/jig-newthing/SKILL.md" <<'EOF'
---
name: jig-newthing
description: fixture skill added in source-v2
---
# jig-newthing
Run `/jig-newthing` to do the thing.
EOF
  local tmp_version="$dest/scripts/lib/version.sh.tmp"
  sed 's/^JIG_VERSION=.*/JIG_VERSION="9.9.9"/' "$dest/scripts/lib/version.sh" > "$tmp_version"
  mv "$tmp_version" "$dest/scripts/lib/version.sh"
}

test_upgrade_requires_initialised_project() {
  fixture_repo
  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

test_upgrade_from_without_value_dies() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig upgrade --from
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires a value"
}

test_upgrade_link_mode_is_noop_when_everything_already_linked() {
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "nothing to link"
  assert_not_contains "$OUT" "link .ai"
}

# Reproduces the gap: activating a profile in config.yaml after `init --link`
# left `jig upgrade` a pure no-op, so `jig verify`'s "run jig upgrade" hint
# was a dead end (domains/install).
test_upgrade_link_mode_creates_missing_profile_symlink() {
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles generic >/dev/null
  assert_no_file .ai/profiles/shell
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "link .ai/profiles/shell"

  assert_symlink .ai/profiles/shell
  case "$(readlink .ai/profiles/shell)" in
    /*) fail "symlink target is absolute: $(readlink .ai/profiles/shell)" ;;
  esac
  assert_file .ai/profiles/shell/verify.sh

  run jig verify --profile shell
  assert_eq 0 "$RC"

  # a non-symlink file in the way is a conflict, not an overwrite
  run jig verify --list --profile shell
  assert_contains "$OUT" "shell: installed"
}

test_upgrade_link_mode_reports_conflict_and_keeps_existing_file() {
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF
  mkdir -p .ai/profiles/shell
  echo "pre-existing, not a symlink" > .ai/profiles/shell/verify.sh

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-conflict .ai/profiles/shell"
  assert_no_file .ai/profiles/shell/profile.yaml
  assert_file_contains .ai/profiles/shell/verify.sh "pre-existing, not a symlink"
}

test_upgrade_dry_run_makes_no_changes() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2 "$src"
  cp .ai/manifest manifest.before.tmp

  run jig upgrade --from "$src" --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace .ai/profiles/generic/verify.sh"
  assert_contains "$OUT" "install .codex/skills/jig-newthing/SKILL.md"

  diff -q manifest.before.tmp .ai/manifest >/dev/null || fail "manifest changed during --dry-run"
  assert_no_file .codex/skills/jig-newthing
  assert_not_contains "$(cat .ai/profiles/generic/verify.sh)" "v2 marker"

  rm -rf "$src"
}

# Exercises every row of the domains/install decision table in one pass:
# replace, keep-modified, install, keep-conflict, delete, keep-orphaned-modified.
test_upgrade_decision_table_full() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2 "$src"

  # keep-modified: local edit to a file that is unchanged in source-v2.
  printf '\n# local edit\n' >> .ai/scripts/lib/config.sh

  # keep-orphaned-modified: local edit to a file removed in source-v2.
  printf '\n# local edit\n' >> .ai/scripts/lib/status.sh
  rm -f "$src/scripts/lib/status.sh"

  # delete: unmodified file removed in source-v2.
  rm -f "$src/profiles/generic/profile.yaml"

  # keep-conflict: a path the new skill would install, pre-created locally
  # with content that does not match the source and is not manifest-tracked.
  mkdir -p .claude/skills/jig-newthing
  echo "pre-existing, not from jig" > .claude/skills/jig-newthing/SKILL.md

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"

  assert_contains "$OUT" "replace .ai/profiles/generic/verify.sh"
  assert_contains "$OUT" "keep-modified .ai/scripts/lib/config.sh"
  assert_contains "$OUT" "keep-orphaned-modified .ai/scripts/lib/status.sh"
  assert_contains "$OUT" "delete .ai/profiles/generic/profile.yaml"
  assert_contains "$OUT" "keep-conflict .claude/skills/jig-newthing/SKILL.md"
  assert_contains "$OUT" "install .codex/skills/jig-newthing/SKILL.md"
  # a genuinely unchanged file (scripts/jig itself) must not be reported
  assert_not_contains "$OUT" "replace .ai/scripts/jig"

  assert_file_contains .ai/profiles/generic/verify.sh "v2 marker"
  assert_file_contains .ai/scripts/lib/config.sh "local edit"
  assert_file_contains .ai/scripts/lib/status.sh "local edit"
  assert_no_file .ai/profiles/generic/profile.yaml
  assert_file_contains .claude/skills/jig-newthing/SKILL.md "pre-existing, not from jig"
  # shellcheck disable=SC2016
  assert_file_contains .codex/skills/jig-newthing/SKILL.md '$jig-newthing'

  assert_file_contains .ai/manifest "jig.version: 9.9.9"

  local claude_tracked codex_tracked profile_tracked
  claude_tracked=$(grep -c ' \.claude/skills/jig-newthing/SKILL\.md$' .ai/manifest)
  assert_eq 0 "$claude_tracked"
  codex_tracked=$(grep -c ' \.codex/skills/jig-newthing/SKILL\.md$' .ai/manifest)
  assert_eq 1 "$codex_tracked"
  profile_tracked=$(grep -c ' \.ai/profiles/generic/profile\.yaml$' .ai/manifest)
  assert_eq 0 "$profile_tracked"

  # re-running upgrade against the same source is a no-op from here
  cp .ai/manifest manifest.after.tmp
  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "replace"
  assert_not_contains "$OUT" "install"
  assert_not_contains "$OUT" "delete"
  diff -q manifest.after.tmp .ai/manifest >/dev/null || fail "manifest changed on a no-op rerun"

  rm -rf "$src"
}

# The staged tree cmd_upgrade builds is derived from the *current*
# .ai/config.yaml, so activating a profile after init and re-running
# `jig upgrade` (copy mode) must install it — not just pick up drift in
# already-tracked files (domains/install).
test_upgrade_copy_mode_installs_newly_activated_profile() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  assert_no_file .ai/profiles/shell
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "install .ai/profiles/shell/profile.yaml"
  assert_contains "$OUT" "install .ai/profiles/shell/verify.sh"

  assert_file .ai/profiles/shell/profile.yaml
  assert_file .ai/profiles/shell/verify.sh

  local want got
  want=$(git -C "$JIG_HOME" hash-object profiles/shell/verify.sh)
  got=$(sed -n 's/^\(.*\) \.ai\/profiles\/shell\/verify\.sh$/\1/p' .ai/manifest)
  assert_eq "$want" "$got"

  run jig verify --profile shell
  assert_eq 0 "$RC"
}

# --- path traversal in config-driven profile/adapter names -----------------
# `jig upgrade` never takes --profile/--profiles flags; the only way a bad
# name reaches it is through .ai/config.yaml, in both copy and link mode.

test_upgrade_copy_mode_rejects_config_path_traversal_profile() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [.., generic]
adapters: [claude, codex]
EOF

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
  assert_no_file .ai/docs
  assert_no_file .ai/tests
}

test_upgrade_link_mode_rejects_config_path_traversal_profile() {
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [.., generic]
adapters: [claude, codex]
EOF

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
  assert_no_file .ai/docs
  assert_no_file .ai/tests
}

test_upgrade_copy_mode_rejects_config_path_traversal_adapter() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [generic]
adapters: [.., claude]
EOF

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid adapter name"
}

test_upgrade_propagates_changed_knowledge_template() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2 "$src"
  printf '\n<!-- v2 template marker -->\n' >> "$src/templates/knowledge/feature.md"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace .ai/templates/knowledge/feature.md"
  assert_file_contains .ai/templates/knowledge/feature.md "v2 template marker"

  rm -rf "$src"
}

test_upgrade_missing_from_falls_back_to_manifest_source() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  # from inside the installed copy's own tree, jig_source_root cannot find a
  # source checkout, so upgrade must fall back to the manifest's jig.source.
  run jig_installed upgrade
  assert_eq 0 "$RC"
}

# Regression for `upgrade_pending` (stale-install-check task): `status` and
# `verify` treat an unresolvable source root as "unknown, skip the check"
# (see tests/status.t.sh, tests/verify.t.sh), but that graceful degradation
# lives entirely in upgrade_pending — a direct `jig upgrade` with no --from
# and a deleted source checkout must still die exactly as before.
test_upgrade_still_dies_without_from_when_source_root_gone() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-del.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" >/dev/null
  rm -rf "$src"

  run jig_installed upgrade
  assert_eq 1 "$RC"
  assert_contains "$OUT" "cannot determine the framework source root"
}

# New shared guidance must ship through real skills in both adapters/modes.
_sdd_assert_reference_links() {
  local runtime
  for runtime in .claude .codex; do
    assert_file "$runtime/skills/jig-task/references/requirements-and-planning.md"
    assert_file "$runtime/skills/jig-task/references/handoff.md"
    assert_file "$runtime/skills/jig-task/references/ui-states.md"
    assert_file "$runtime/skills/jig-analyze/references/ambiguity.md"
    assert_file "$runtime/skills/jig-review/references/change-scope.md"
    assert_file "$runtime/skills/jig-review/../jig-task/references/ui-states.md"
    assert_file "$runtime/skills/jig-implement/../jig-review/references/change-scope.md"
  done
}

test_sdd_upgrade_adds_references_and_preserves_modified_consumers() {
  fixture_repo
  local old_source="$PWD/old-source" dir
  mkdir "$old_source"
  for dir in scripts skills templates adapters profiles; do
    cp -R "$JIG_HOME/$dir" "$old_source/$dir"
  done
  rm "$old_source/skills/jig-task/references/requirements-and-planning.md" \
    "$old_source/skills/jig-task/references/handoff.md" \
    "$old_source/skills/jig-task/references/ui-states.md" \
    "$old_source/skills/jig-analyze/references/ambiguity.md" \
    "$old_source/skills/jig-review/references/change-scope.md"
  jig init --from "$old_source" >/dev/null
  echo 'User-owned review instruction' >> .codex/skills/jig-review/SKILL.md
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  _sdd_assert_reference_links
  assert_file_contains .codex/skills/jig-review/SKILL.md 'User-owned review instruction'
  assert_file_contains .ai/manifest '.codex/skills/jig-task/references/ui-states.md'
}

test_sdd_upgrade_link_mode_exposes_references_in_both_adapters() {
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  rm .codex/skills/jig-task
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_symlink .codex/skills/jig-task
  _sdd_assert_reference_links
}
