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
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 placed"
  assert_contains "$OUT" "manifest updated"
  assert_not_contains "$OUT" "link .ai"
}

# Reproduces the reported case (2026-09-22): `jig upgrade --from <another
# checkout>` in a link-mode project conflicts on every link, places nothing,
# and used to repoint jig.source at that checkout all the same — after which
# a plain `jig upgrade` would have read from a source no file came from.
test_upgrade_link_mode_keeps_manifest_when_every_link_conflicts() {
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-other.XXXXXX")
  src=$(cd "$src" && pwd) # $TMPDIR can end in a slash; the manifest records a clean path
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  cp .ai/manifest manifest.before.tmp

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-conflict .ai/scripts"
  assert_not_contains "$OUT" "link .ai/scripts"
  assert_contains "$OUT" "0 placed"
  assert_contains "$OUT" "manifest unchanged"
  assert_contains "$OUT" "jig init --link --from $src"
  diff -q manifest.before.tmp .ai/manifest >/dev/null \
    || fail "manifest changed although nothing was linked"
  assert_file_contains .ai/manifest "jig.source: $JIG_HOME"

  rm -rf "$src"
}

# The other half of the rule: the recorded source may always be written back,
# placed or not. In link mode the project runs that checkout's scripts
# directly, so jig.version has to keep following it — otherwise `jig status`
# reports a version mismatch that no `jig upgrade` can ever clear.
test_upgrade_link_mode_refreshes_version_of_the_recorded_source() {
  skip_unless_symlinks
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-same.XXXXXX")
  src=$(cd "$src" && pwd) # $TMPDIR can end in a slash; the manifest records a clean path
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --from "$src" --link >/dev/null
  local tmp_version="$src/scripts/lib/version.sh.tmp"
  sed 's/^JIG_VERSION=.*/JIG_VERSION="9.9.9"/' "$src/scripts/lib/version.sh" > "$tmp_version"
  mv "$tmp_version" "$src/scripts/lib/version.sh"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 placed"
  assert_contains "$OUT" "manifest updated"
  assert_file_contains .ai/manifest "jig.version: 9.9.9"
  assert_file_contains .ai/manifest "jig.source: $src"

  rm -rf "$src"
}

# Reproduces the gap: activating a profile in config.yaml after `init --link`
# left `jig upgrade` a pure no-op, so `jig verify`'s "run jig upgrade" hint
# was a dead end (domains/install).
test_upgrade_link_mode_creates_missing_profile_symlink() {
  skip_unless_symlinks
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
  skip_unless_symlinks
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

# Reproduces the Windows Git Bash gap: `ln -s` copies instead of linking, so
# a link-mode project must refuse rather than silently place a copy where the
# manifest expects a symlink (jig_link_detect, common.sh).
test_upgrade_link_mode_refuses_when_only_copying_links_are_available() {
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles generic >/dev/null
  assert_no_file .ai/profiles/shell
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF
  local before lndir
  before=$(git status --porcelain)
  lndir=$(stub_ln_copy_dir)
  export PATH="$lndir:$PATH"

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "installed in link mode, which needs symbolic links"
  assert_no_file .ai/profiles/shell
  assert_eq "$before" "$(git status --porcelain)" "a refused upgrade must change nothing"

  run jig upgrade --from "$JIG_HOME" --dry-run
  assert_eq 1 "$RC"
  assert_contains "$OUT" "installed in link mode, which needs symbolic links"
  assert_no_file .ai/profiles/shell
  assert_eq "$before" "$(git status --porcelain)" "a refused dry-run must change nothing"
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

# The same fork as link mode's, in copy mode: nothing installed, replaced or
# deleted means the project is still the install it was, so neither
# jig.source nor jig.version may move to the checkout it was offered.
test_upgrade_copy_mode_keeps_manifest_when_nothing_was_placed() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src before_version
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  src=$(cd "$src" && pwd) # $TMPDIR can end in a slash; the manifest records a clean path
  _mk_source_v2 "$src"
  before_version=$(sed -n 's/^jig\.version: //p' .ai/manifest)

  # Every path source-v2 would place is locally modified or occupied, so the
  # decision table ends with keep-modified/keep-conflict and nothing else.
  printf '\n# local edit\n' >> .ai/profiles/generic/verify.sh
  printf '\n# local edit\n' >> .ai/scripts/lib/version.sh
  mkdir -p .claude/skills/jig-newthing .codex/skills/jig-newthing
  echo "mine" > .claude/skills/jig-newthing/SKILL.md
  echo "mine" > .codex/skills/jig-newthing/SKILL.md
  cp .ai/manifest manifest.before.tmp

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 placed"
  assert_contains "$OUT" "manifest unchanged"
  assert_contains "$OUT" "jig init --from $src"
  assert_not_contains "$OUT" "jig init --link"
  diff -q manifest.before.tmp .ai/manifest >/dev/null \
    || fail "manifest changed although nothing was placed"
  assert_file_contains .ai/manifest "jig.source: $JIG_HOME"
  assert_file_contains .ai/manifest "jig.version: $before_version"

  rm -rf "$src"
}

# Moving a project onto another checkout stays possible: an upgrade that does
# place files from it records it, exactly as before.
test_upgrade_copy_mode_records_the_source_it_placed_from() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  src=$(cd "$src" && pwd) # $TMPDIR can end in a slash; the manifest records a clean path
  _mk_source_v2 "$src"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "manifest updated"
  assert_file_contains .ai/manifest "jig.source: $src"
  assert_file_contains .ai/manifest "jig.version: 9.9.9"

  rm -rf "$src"
}

# Reported 2026-09-23: an upgrade in a project installed in copy mode ended in
# `.ai/scripts/jig: line 112: key: No such file or directory`, a line the
# dispatcher it had just replaced does not contain. `cp` onto the destination
# rewrites it in place, keeping the inode, and the destination here is the very
# script bash is executing: once the file grew, bash read on from the offset it
# had reached and ran whatever the *new* bytes said there. The new dispatcher
# below is the installed one plus a trailing block, so a shell that reads past
# the end of the file it started lands exactly on it and says so.
test_upgrade_copy_mode_replaces_the_running_dispatcher_without_running_its_tail() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  src=$(cd "$src" && pwd)
  _mk_source_v2 "$src"
  cat >> "$src/scripts/jig" <<'EOF'

printf 'TAIL-EXECUTED\n'
exit 42
EOF

  run jig_installed upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "TAIL-EXECUTED"
  assert_contains "$OUT" "replace .ai/scripts/jig"

  rm -rf "$src"
}

# --- orphan deletion is scoped to `.ai/` and adapter skills dirs (_upgrade_deletable) ---

# The ordinary case the decision table above only exercises inside `.ai/`:
# a file this framework installed under an adapter's skills directory, later
# removed from the source, is still deleted once orphaned.
test_upgrade_deletes_orphaned_skill_under_claude_skills_dir() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-orphan.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  mkdir -p "$src/skills/jig-orphantest"
  cat > "$src/skills/jig-orphantest/SKILL.md" <<'EOF'
---
name: jig-orphantest
description: fixture skill removed again in the next source
---
# jig-orphantest
EOF
  jig init --from "$src" >/dev/null
  assert_file .claude/skills/jig-orphantest/SKILL.md

  rm -rf "$src/skills/jig-orphantest"
  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "delete .claude/skills/jig-orphantest/SKILL.md"
  assert_no_file .claude/skills/jig-orphantest/SKILL.md

  rm -rf "$src"
}

# A manifest entry outside `.ai/` and every adapter's skills directory is not
# proof the framework may delete it there — only that some earlier version of
# this file wrote the line. Kept, and reported `keep-outside`, not `delete`
# (scripts/lib/upgrade.sh, _upgrade_deletable).
test_upgrade_keeps_manifest_entry_outside_delete_roots() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null

  mkdir -p docs
  printf 'not framework-owned\n' > docs/x.md
  local hash
  hash=$(git hash-object docs/x.md)
  printf '%s docs/x.md\n' "$hash" >> .ai/manifest

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-outside docs/x.md"
  assert_not_contains "$OUT" "delete docs/x.md"
  assert_file docs/x.md
  assert_file_contains docs/x.md "not framework-owned"
  assert_file_contains .ai/manifest "docs/x.md"
}

# A `..` component makes a manifest path untrustworthy on its own terms,
# regardless of where it points — refused the same way even without a real
# file behind it (a project's manifest is not proof of what a path is).
test_upgrade_keeps_manifest_entry_with_path_traversal() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null

  printf '%s\n' "0000000000000000000000000000000000000000 ../x" >> .ai/manifest

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-outside ../x"
  assert_not_contains "$OUT" "delete ../x"
  assert_file_contains .ai/manifest "../x"
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
  skip_unless_symlinks
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

# --- spec templates: an install that predates them --------------------------
# Simulates a project initialised before `.ai/templates/spec/` existed: the
# installed copy and its manifest entries are removed by hand, the way a
# frozen/older install would look, then `jig upgrade` must pick it back up
# (mirrors test_upgrade_copy_mode_installs_newly_activated_profile).

test_upgrade_dry_run_reports_missing_spec_templates_as_pending() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  rm -rf .ai/templates/spec
  grep -v '\.ai/templates/spec/' .ai/manifest > .ai/manifest.tmp
  mv .ai/manifest.tmp .ai/manifest

  run jig upgrade --from "$JIG_HOME" --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "install .ai/templates/spec/spec.md"
  assert_contains "$OUT" "install .ai/templates/spec/roadmap.md"
  assert_no_file .ai/templates/spec/spec.md
}

test_upgrade_installs_spec_templates_for_a_pre_spec_install_copy_mode() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  rm -rf .ai/templates/spec
  grep -v '\.ai/templates/spec/' .ai/manifest > .ai/manifest.tmp
  mv .ai/manifest.tmp .ai/manifest

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "install .ai/templates/spec/spec.md"
  assert_contains "$OUT" "install .ai/templates/spec/roadmap.md"
  assert_file .ai/templates/spec/spec.md
  assert_file .ai/templates/spec/roadmap.md
  assert_file_contains .ai/manifest ".ai/templates/spec/spec.md"
  assert_file_contains .ai/manifest ".ai/templates/spec/roadmap.md"

  # spec new now finds the reinstalled template on its own, no --from needed.
  run jig spec new idea-x
  assert_eq 0 "$RC"
}

test_upgrade_link_mode_links_spec_templates_for_a_pre_spec_install() {
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  rm -f .ai/templates/spec

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "link .ai/templates/spec"
  assert_symlink .ai/templates/spec
  assert_file .ai/templates/spec/spec.md
  assert_file .ai/templates/spec/roadmap.md
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
    assert_file "$runtime/skills/jig-task/references/show-the-document.md"
    assert_file "$runtime/skills/jig-accept/../jig-task/references/show-the-document.md"
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
    "$old_source/skills/jig-task/references/show-the-document.md" \
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
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  rm .codex/skills/jig-task
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_symlink .codex/skills/jig-task
  _sdd_assert_reference_links
}

# --- the marked instructions section ------------------------------------------
# adr-20260924-jig-owns-a-marked-section-of-the-instructions. The same three
# outcomes as any other framework-owned path — replace, keep-modified,
# install — applied to the region between the markers instead of to a file.

# _mk_source_v2_section <dest> — source-v2 whose Jig section differs, which is
# the only thing that makes an upgrade of the section non-trivial.
_mk_source_v2_section() {
  local dest="$1" tmp
  _mk_source_v2 "$dest"
  tmp="$dest/templates/AGENTS.md.tmp"
  sed 's/^## Workflow$/## Workflow\n\nA brand new sentence from source-v2./' \
    "$dest/templates/AGENTS.md" > "$tmp"
  mv "$tmp" "$dest/templates/AGENTS.md"
}

test_upgrade_replaces_the_marked_instructions_section() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace AGENTS.md (Jig section)"
  assert_file_contains AGENTS.md "A brand new sentence from source-v2."
  # Everything outside the markers is the project's and must not move.
  assert_file_contains AGENTS.md "## Working rules"
  assert_file_contains .ai/manifest "instructions.section: "
}

test_upgrade_keeps_a_modified_instructions_section() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src before
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"

  # A human edits inside the markers: from here the section is theirs.
  sed 's/^## Read first$/## Read first (our version)/' AGENTS.md > AGENTS.md.new
  mv AGENTS.md.new AGENTS.md
  before=$(cat AGENTS.md)

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-modified AGENTS.md (Jig section)"
  assert_not_contains "$OUT" "replace AGENTS.md"
  assert_eq "$before" "$(cat AGENTS.md)"
}

test_upgrade_keeps_a_section_whose_markers_were_removed() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src before
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"

  grep -v 'jig:begin\|jig:end' AGENTS.md > AGENTS.md.new
  mv AGENTS.md.new AGENTS.md
  before=$(cat AGENTS.md)

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  # Removed on purpose stays removed, exactly as ADR-0024 concluded for a
  # deleted session-hook line.
  assert_contains "$OUT" "keep-modified AGENTS.md (Jig section)"
  assert_eq "$before" "$(cat AGENTS.md)"
}

test_upgrade_reports_an_unmarked_agents_md_and_writes_nothing() {
  fixture_repo
  printf '# Our own rules\n\nUse tabs.\n' > AGENTS.md
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-unmarked AGENTS.md"
  assert_eq "# Our own rules

Use tabs." "$(cat AGENTS.md)"
  assert_not_contains "$(cat .ai/manifest)" "instructions.section"
}

test_upgrade_reports_a_malformed_marker_pair() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src before
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"

  # A second begin marker: jig cannot tell which region is its own, so it
  # refuses rather than guessing.
  printf '<!-- jig:begin -->\n' >> AGENTS.md
  before=$(cat AGENTS.md)

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-malformed AGENTS.md (Jig section)"
  assert_eq "$before" "$(cat AGENTS.md)"
}

test_upgrade_reports_conflict_for_markers_it_did_not_write() {
  fixture_repo
  printf '# Our own rules\n' > AGENTS.md
  jig init --from "$JIG_HOME" >/dev/null
  local src before
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"

  # Markers appear after init recorded nothing: jig never wrote this, so it
  # does not adopt it behind the human's back.
  printf '<!-- jig:begin -->\nsomething\n<!-- jig:end -->\n' >> AGENTS.md
  before=$(cat AGENTS.md)

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-conflict AGENTS.md (Jig section)"
  assert_eq "$before" "$(cat AGENTS.md)"
}

test_upgrade_dry_run_leaves_the_section_alone() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src before
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"
  before=$(cat AGENTS.md)

  run jig upgrade --from "$src" --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace AGENTS.md (Jig section)"
  assert_eq "$before" "$(cat AGENTS.md)"
}

# A section update is pending work like any other, so `jig status` counts it
# and `jig verify` refuses a stale install because of it — which is why the
# report reuses the verb `replace` instead of inventing one.
test_upgrade_pending_includes_a_section_replace() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"

  run jig upgrade --from "$src" --dry-run
  assert_contains "$(printf '%s\n' "$OUT" | grep -E '^(install|link|replace) ')" \
    "replace AGENTS.md (Jig section)"
}

# And a project that keeps its own instructions is never blocked by that
# choice: keep-unmarked is deliberately outside the pending filter.
test_upgrade_pending_excludes_an_unmarked_section() {
  fixture_repo
  printf '# Our own rules\n' > AGENTS.md
  jig init --from "$JIG_HOME" >/dev/null

  run jig upgrade --from "$JIG_HOME" --dry-run
  assert_contains "$OUT" "keep-unmarked AGENTS.md"
  assert_eq "" "$(printf '%s\n' "$OUT" | grep -E '^(install|link|replace) ' || true)"
}

test_upgrade_installs_the_instructions_template_for_an_older_install() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  # An install made before the template was framework-owned.
  rm -f .ai/templates/AGENTS.md
  grep -v ' \.ai/templates/AGENTS\.md$' .ai/manifest > .ai/manifest.new
  mv .ai/manifest.new .ai/manifest

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "install .ai/templates/AGENTS.md"
  assert_file .ai/templates/AGENTS.md
}

# Link mode decides the section exactly as copy mode does — the record it rests
# on is a manifest header key, and link mode writes a header too. design.md §13
# asked for this explicitly, because "same function, both branches" is an
# argument, not evidence.
test_upgrade_link_mode_replaces_the_marked_instructions_section() {
  skip_unless_symlinks
  fixture_repo
  local src tmp
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-srclink.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  jig init --link --from "$src" >/dev/null
  assert_file_contains .ai/manifest "instructions.section: "

  tmp="$src/templates/AGENTS.md.tmp"
  sed 's/^## Workflow$/## Workflow\n\nA brand new sentence from source-v2./' \
    "$src/templates/AGENTS.md" > "$tmp"
  mv "$tmp" "$src/templates/AGENTS.md"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace AGENTS.md (Jig section)"
  assert_file_contains AGENTS.md "A brand new sentence from source-v2."
  assert_file_contains AGENTS.md "## Working rules"
}
