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

# _unbump_source <dest> — give a source made by _mk_source_v2 the running
# version back, so the running code carries out the upgrade itself instead of
# handing it to the source's newer dispatcher. The tests that are about the old
# code doing the work need exactly that.
_unbump_source() {
  local tmp_version="$1/scripts/lib/version.sh.tmp"
  cp "$JIG_HOME/scripts/lib/version.sh" "$tmp_version"
  mv "$tmp_version" "$1/scripts/lib/version.sh"
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
  # The freshly linked shell profile finds no linter and no test runner here,
  # so every check skips and the run says it checked nothing, exit 3
  # (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass). What
  # this test is about — that the symlink was made and is usable — is the
  # RESULT line, not the exit code.
  assert_eq 3 "$RC"
  assert_contains "$OUT" "RESULT shell: skip"

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
  _unbump_source "$src"
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

  # Upgrade installed the profile; give its smoke run an applicable check.
  # Without this runner the result depends on whether the host has shellcheck:
  # a profile that skips every check correctly returns 3, not a false pass.
  mkdir -p tests
  cat > tests/run.sh <<'EOF'
#!/usr/bin/env sh
test -f .ai/profiles/shell/verify.sh
EOF
  chmod +x tests/run.sh
  run jig verify --profile shell
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "shell: tests/run.sh: pass"
  assert_contains "$OUT" "RESULT shell: pass"
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

  # An upgrade is a unit of work (adr-20260930-an-upgrade-is-a-unit-of-work):
  # it left this checkout on its own branch, with the change staged, not on
  # main. Commit and merge it back, the way its own "next" line says to, so
  # main is clean again — spec new now finds the reinstalled template on its
  # own, no --from needed.
  local branch
  branch=$(git symbolic-ref --short HEAD)
  git commit -q -F .ai/runtime/upgrade/message
  git checkout -q main
  git merge -q --ff-only "$branch"
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

# --- what the project's own config.yaml does not mention ----------------------

test_upgrade_names_config_keys_the_project_file_does_not_mention() {
  fixture_jig_repo
  grep -v 'verify.full_run' .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml
  local before
  before=$(cat .ai/config.yaml)

  run jig upgrade
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/config.yaml does not mention 1 key(s) this version reads, each on its default: verify.full_run"
  # shellcheck disable=SC2016  # a literal backticked command name
  assert_contains "$OUT" 'hint: `jig config keys` lists them'
  # The whole point: an upgrade says what changed underneath and changes
  # nothing in the team's file (ADR-0024).
  assert_eq "$before" "$(cat .ai/config.yaml)" "upgrade touched .ai/config.yaml"
}

test_upgrade_says_nothing_about_config_keys_when_the_file_mentions_them_all() {
  fixture_jig_repo
  run jig upgrade
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "does not mention"
}

test_upgrade_dry_run_says_nothing_about_config_keys() {
  fixture_jig_repo
  grep -v 'verify.full_run' .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml

  run jig upgrade --dry-run
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "does not mention"
}

# --- an interrupted run, and the two sides of the hash comparison ------------

# Reproduces the reported case (external review M8, reproduced twice): files
# are placed one at a time and the manifest is written once at the end, so an
# interruption leaves the new bytes on disk against the recorded old hash.
# Until the decision table compared the disk with the stage, the repeat read
# every file the interrupted run had placed as one the user had edited and
# said so for ever — `keep-modified` on every later run, permanent drift in
# `jig status`, and an install that never finished.
#
# The interruption is a real one: the destination directory of a file the new
# source changes cannot be written, so the run dies inside the placement loop
# with earlier paths already placed.
test_upgrade_finishes_a_run_interrupted_midway() {
  skip_unless_readonly_dirs
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2 "$src"
  # Sorts after .ai/** and .claude/**, so those are placed before the run dies.
  printf '\n# v2 marker\n' >> "$src/skills/jig-verify/SKILL.md"

  chmod 500 .codex/skills/jig-verify
  run jig upgrade --from "$src"
  chmod 700 .codex/skills/jig-verify
  assert_eq 1 "$RC"
  assert_contains "$OUT" "could not write"
  # The state an interruption leaves: placed on disk, old hash in the manifest.
  assert_file_contains .ai/profiles/generic/verify.sh "v2 marker"
  local placed_hash
  placed_hash=$(git hash-object --no-filters .ai/profiles/generic/verify.sh)
  assert_not_contains "$(cat .ai/manifest)" "$placed_hash"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "already-placed .ai/profiles/generic/verify.sh"
  assert_not_contains "$OUT" "keep-modified .ai/profiles/generic/verify.sh"
  assert_contains "$OUT" "replace .codex/skills/jig-verify/SKILL.md"
  assert_contains "$OUT" "manifest updated"

  # Once reconciled it stays reconciled, and says nothing more about it.
  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "already-placed"
  assert_not_contains "$OUT" "keep-modified .ai/profiles/generic/verify.sh"

  # The drift the bug produced: files jig itself had placed, reported for ever
  # as ones somebody edited. (`pending` is not asserted here: this fixture's
  # status measures the install against $JIG_HOME, not against $src.)
  run jig status
  assert_contains "$OUT" "drift: 0 modified, 0 missing"

  run jig upgrade --from "$src" --dry-run
  assert_not_contains "$OUT" "keep-modified"
  assert_not_contains "$OUT" "replace .ai/profiles/generic/verify.sh"

  rm -rf "$src"
}

# The other half of the same interruption, and the one the reported case hit:
# a path the new version installs for the first time. Placed but not yet in the
# manifest, it used to read as `keep-conflict` — somebody else's file at a
# framework path — which no later run ever revisits, so the path never became
# framework-owned and was never updated again.
test_upgrade_adopts_a_path_an_interrupted_run_installed() {
  skip_unless_readonly_dirs
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2 "$src"
  printf '\n# v2 marker\n' >> "$src/skills/jig-verify/SKILL.md"

  chmod 500 .codex/skills/jig-verify
  run jig upgrade --from "$src"
  chmod 700 .codex/skills/jig-verify
  assert_eq 1 "$RC"
  # jig-newthing is new in source-v2 and sorts before jig-verify, so the
  # interrupted run installed it and never recorded it.
  assert_file .claude/skills/jig-newthing/SKILL.md
  assert_not_contains "$(cat .ai/manifest)" ".claude/skills/jig-newthing/SKILL.md"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "already-placed .claude/skills/jig-newthing/SKILL.md"
  assert_not_contains "$OUT" "keep-conflict .claude/skills/jig-newthing/SKILL.md"
  assert_file_contains .ai/manifest ".claude/skills/jig-newthing/SKILL.md"

  rm -rf "$src"
}

# The second way the same `keep-modified` state is reached, with no
# interruption at all: `git hash-object` applies the repository's clean filters
# to a path inside it, while the staging tree in $TMPDIR is outside any
# repository and is hashed as it stands. The two sides of the comparison were
# computed differently, so a filtered framework path was replaced on every run
# and then read as modified for ever.
test_upgrade_hashes_both_sides_alike_under_clean_filters() {
  fixture_repo
  printf '.ai/profiles/** filter=jigtest\n' > .gitattributes
  git config filter.jigtest.clean 'sed "s/^/# /"'
  git add .gitattributes
  git commit -q -m "clean filter over the framework's profiles"
  jig init --from "$JIG_HOME" >/dev/null
  # init appends to the tracked .gitattributes; an upgrade starts from a
  # committed tree.
  git add -A && git commit -q -m "jig init"

  # The filter has to bite, or this test proves nothing.
  local filtered raw
  filtered=$(git hash-object .ai/profiles/generic/verify.sh)
  raw=$(git hash-object --no-filters .ai/profiles/generic/verify.sh)
  [ "$filtered" != "$raw" ] || skip "clean filters do not change hashes here"

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "replace .ai/profiles/"
  assert_not_contains "$OUT" "keep-modified .ai/profiles/"

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "keep-modified .ai/profiles/"

  run jig status
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 0 pending"
}

# The same divergence by its other mechanism, and the one --no-filters does not
# answer: the object format. In a SHA-256 repository the project's files hash to
# 64 hex digits and a staging tree outside it to 40, so every framework path
# compared unequal — the first run replaced all of them and wrote SHA-1 hashes
# into a SHA-256 manifest, and from the second run on the whole install read as
# modified and never updated again.
test_upgrade_hashes_both_sides_alike_in_a_sha256_repository() {
  skip_unless_sha256_repos
  git init -q --object-format=sha256 .
  git symbolic-ref HEAD refs/heads/main
  printf '# fixture\n' > README.md
  git add README.md
  git commit -q -m init
  jig init --from "$JIG_HOME" >/dev/null

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 placed"
  assert_not_contains "$OUT" "replace .ai/scripts/"

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "keep-modified .ai/scripts/"

  run jig status
  assert_contains "$OUT" "drift: 0 modified, 0 missing, 0 pending"
}

# The run asks the install it just made whether anything is still missing, and
# names it (finding F1, from a live case: a run printed "55 placed, 49 kept,
# 2 removed; manifest updated" and left .ai/templates/AGENTS.md unplaced, found
# a day later in `jig doctor` as "1 pending item(s) although the version is the
# same").
#
# The check has to be the newly installed dispatcher, as a subprocess, and this
# test is the reason: an upgrade is carried out by the code of the version being
# replaced, and that code stages only what it knows about. Here the source
# stages one path this running code does not, exactly as 0.16.0 staged
# .ai/templates/AGENTS.md and 0.15.1 did not. Asking upgrade_pending in this
# process would ask the old decision table, which is satisfied by construction
# and would stay silent.
test_upgrade_names_what_is_still_not_installed() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null

  # A complete run says nothing about leftovers.
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "still not installed"

  local src anchor
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-next.XXXXXX")
  _mk_source_v2 "$src"
  _unbump_source "$src"
  # The literal source line, $source and all: it is grepped for, not evaluated.
  # shellcheck disable=SC2016
  anchor='cp -p "$source/templates/AGENTS.md" "$stage/.ai/templates/AGENTS.md"'
  grep -qF "$anchor" "$src/scripts/lib/upgrade.sh" \
    || fail "the staging line this test patches is gone; rewrite the test"
  # The next version stages one more path than the running code does.
  awk -v anchor="$anchor" '
    { print }
    index($0, anchor) { print "  cp -p \"$source/templates/AGENTS.md\" \"$stage/.ai/templates/NEWTHING.md\"" }
  ' "$src/scripts/lib/upgrade.sh" > "$src/scripts/lib/upgrade.sh.tmp"
  mv "$src/scripts/lib/upgrade.sh.tmp" "$src/scripts/lib/upgrade.sh"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_no_file .ai/templates/NEWTHING.md
  assert_contains "$OUT" "1 item(s) still not installed"
  # Indented: quoted from another run, and not to be mistaken for this run's
  # own report lines by a reader or by anything reading line starts.
  assert_contains "$OUT" "  install .ai/templates/NEWTHING.md"
  assert_contains "$OUT" "not committed, because the install is not complete"

  # And the run the message asks for finishes the job — done by the project's
  # own dispatcher, which is now the newer code, the way the check itself asked
  # that code whether anything was left.
  run jig_installed upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_file .ai/templates/NEWTHING.md
  assert_not_contains "$OUT" "still not installed"

  rm -rf "$src"
}

# The marked section's record lives in the manifest header, which is written at
# the end of the run, so an interruption leaves it with the same hole a file has:
# the region already holds the source's text while the header still records the
# older hash. Read as an edit, it would never be replaced again.
#
# The interruption is constructed rather than provoked, because the section is
# written at one fixed point near the end of the run: the manifest is put back
# to what it was before, which is exactly the state a run interrupted after
# writing the section and before writing the manifest leaves behind.
test_upgrade_reconciles_a_section_an_interrupted_run_had_written() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2_section "$src"
  cp .ai/manifest manifest.before.tmp

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace AGENTS.md (Jig section)"
  assert_file_contains AGENTS.md "A brand new sentence from source-v2."

  # The manifest write is undone: the section is the source's, the record is old.
  cp manifest.before.tmp .ai/manifest

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "already-placed AGENTS.md (Jig section)"
  assert_not_contains "$OUT" "keep-modified AGENTS.md (Jig section)"
  assert_contains "$OUT" "manifest updated"
  # And it stuck: a third run has nothing left to say about the section.
  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "already-placed AGENTS.md (Jig section)"
  assert_not_contains "$OUT" "keep-modified AGENTS.md (Jig section)"

  rm -rf "$src"
}

# A reconciliation is the one outcome that changes the manifest while writing no
# file, so it has to count as applied: `_upgrade_records_source` otherwise
# refuses the write, and a repeat of a run interrupted after its *last*
# placement would find every path already placed, write nothing, report
# `manifest unchanged` and stay stuck — the defect, reached by the fix.
#
# Every other already-placed test also has a genuine `replace` in the same run,
# which satisfies that count on its own; this one isolates the term. The source
# passed is deliberately not the recorded one, which is when the count decides.
test_upgrade_writes_the_manifest_for_a_reconciliation_alone() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src2.XXXXXX")
  _mk_source_v2 "$src"
  cp .ai/manifest manifest.before.tmp

  # A complete run: after it, nothing is left to place from $src.
  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace .ai/profiles/generic/verify.sh"

  # Undo only the manifest write, leaving the files of the run in place.
  cp manifest.before.tmp .ai/manifest

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 placed"
  assert_contains "$OUT" "already-placed .ai/profiles/generic/verify.sh"
  assert_contains "$OUT" "manifest updated"
  assert_file_contains .ai/manifest "jig.version: 9.9.9"

  # Nothing is left over: the next run is quiet and the install is not adrift.
  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "already-placed"
  assert_not_contains "$OUT" "keep-modified"
  run jig status
  assert_contains "$OUT" "drift: 0 modified, 0 missing"

  rm -rf "$src"
}

# Link mode keeps the same record in the same header, so it needs the same
# reconciliation — and it must not pay for it with the recorded source. A
# link-mode run that created no link leaves the project running the scripts it
# ran before, so naming the checkout it was offered would send the next plain
# `jig upgrade` to read from a checkout no link points at (adr-20260922). The
# record is kept; the source is not moved.
test_upgrade_link_mode_reconciles_a_section_without_moving_the_source() {
  skip_unless_symlinks
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-link.XXXXXX")
  src=$(cd "$src" && pwd) # $TMPDIR can end in a slash; the manifest records a clean path
  _mk_source_v2_section "$src"
  cp .ai/manifest manifest.before.tmp

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "replace AGENTS.md (Jig section)"

  # The state an interruption leaves: section written, header not.
  cp manifest.before.tmp .ai/manifest

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "already-placed AGENTS.md (Jig section)"
  assert_contains "$OUT" "manifest updated"
  # The record was kept...
  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "already-placed AGENTS.md (Jig section)"
  # ...and the source was not moved onto a checkout nothing links to.
  assert_file_contains .ai/manifest "jig.source: $JIG_HOME"

  rm -rf "$src"
}

# --- the upgrade as a unit of work (adr-20260930-an-upgrade-is-a-unit-of-work) ---

# _unit_project — an installed project with its install committed on main, the
# way a real one stands before an upgrade.
_unit_project() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  git add -A
  git commit -q -m "jig init"
}

# _unit_source — a newer source (9.9.9) in a fresh directory; prints its path.
_unit_source() {
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-src-unit.XXXXXX")
  src=$(cd "$src" && pwd)
  _mk_source_v2 "$src"
  printf '%s\n' "$src"
}

test_upgrade_refuses_a_dirty_tree_and_changes_nothing() {
  _unit_project
  local src head
  src=$(_unit_source)
  printf '\n# local edit\n' >> README.md
  head=$(git rev-parse HEAD)

  run jig upgrade --from "$src"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "uncommitted changes"
  assert_contains "$OUT" "git stash"
  assert_contains "$OUT" "nothing was changed"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  assert_eq "$head" "$(git rev-parse HEAD)"
  assert_no_file .ai/skills/jig-newthing
  [ -z "$(git diff --cached --name-only)" ] || fail "the refusal staged something"
  assert_file_contains .ai/manifest "jig.source: $JIG_HOME"

  rm -rf "$src"
}

# A clean tree, and the person standing on a task's branch: the upgrade gets a
# branch of its own cut from main, and one commit on it.
test_upgrade_commits_once_on_its_own_branch_cut_from_the_base() {
  _unit_project
  jig config set --local agent.git commit >/dev/null
  local src main_head
  src=$(_unit_source)
  main_head=$(git rev-parse main)
  git checkout -q -b task/elsewhere
  printf 'task work\n' > task.txt
  git add task.txt
  git commit -q -m "task work"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "working on branch jig/upgrade-9.9.9, cut from main"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "git checkout task/elsewhere"
  assert_eq "jig/upgrade-9.9.9" "$(git symbolic-ref --short HEAD)"
  assert_eq "$main_head" "$(git rev-parse HEAD~1)"
  assert_no_file task.txt "the upgrade branch carries the task's work"
  assert_eq "1" "$(git rev-list --count main..HEAD)"
  assert_contains "$(git log -1 --format=%s)" "Upgrade Jig "
  assert_contains "$(git log -1 --format=%s)" " -> 9.9.9"
  assert_contains "$(git log -1 --format=%B)" "Manual steps:"
  assert_contains "$(git log -1 --format=%B)" "https://jig.fapost.in/upgrading"
  assert_eq "" "$(git status --porcelain | grep -v '^??' || true)"
  assert_file_contains .ai/manifest "jig.version: 9.9.9"

  rm -rf "$src"
}

# agent.git none: the change is staged, and one command commits it. A repeat on
# the upgrade's own branch, with that change still uncommitted, is allowed:
# that is how an interrupted upgrade is finished.
test_upgrade_at_agent_git_none_stages_and_a_repeat_on_its_branch_runs() {
  _unit_project
  local src
  src=$(_unit_source)

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "git commit -F .ai/runtime/upgrade/message"
  assert_file .ai/runtime/upgrade/message
  assert_eq "jig/upgrade-9.9.9" "$(git symbolic-ref --short HEAD)"
  assert_eq "0" "$(git rev-list --count main..HEAD)"
  [ -n "$(git diff --cached --name-only)" ] || fail "nothing was staged"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "uncommitted changes"
  assert_eq "jig/upgrade-9.9.9" "$(git symbolic-ref --short HEAD)"

  rm -rf "$src"
}

test_upgrade_with_nothing_to_change_goes_back_and_drops_its_branch() {
  _unit_project
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "nothing changed; back on main"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  [ -z "$(git branch --list 'jig/upgrade-*')" ] \
    || fail "the empty upgrade branch was left behind"
}

test_upgrade_without_branch_per_task_commits_on_the_current_branch() {
  _unit_project
  sed 's/^git\.branch_per_task: true/git.branch_per_task: false/' .ai/config.yaml > config.tmp
  mv config.tmp .ai/config.yaml
  git commit -q -am "one branch"
  jig config set --local agent.git pr >/dev/null
  local src
  src=$(_unit_source)

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "working on branch"
  assert_not_contains "$OUT" "pushed"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  assert_contains "$(git log -1 --format=%s)" " -> 9.9.9"

  rm -rf "$src"
}

# Older code hands the upgrade to the source's newer dispatcher; code as new as
# the source does the work itself.
test_upgrade_hands_itself_to_newer_code() {
  _unit_project
  local src
  src=$(_unit_source)
  printf '\nprintf "NEW-DISPATCHER\\n" >&2\n' >> "$src/scripts/lib/version.sh"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "; handing the upgrade to 9.9.9 from $src"
  assert_contains "$OUT" "NEW-DISPATCHER"
  assert_file_contains .ai/manifest "jig.version: 9.9.9"

  rm -rf "$src"
}

test_upgrade_does_not_hand_off_to_code_no_newer_than_itself() {
  _unit_project
  local src
  src=$(_unit_source)
  _unbump_source "$src"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "handing the upgrade"

  rm -rf "$src"
}

test_upgrade_handed_off_and_still_older_says_self_update() {
  _unit_project
  local src
  src=$(_unit_source)

  JIG_UPGRADE_HANDED_OFF=0.0.1 run jig upgrade --from "$src"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig self-update"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"

  rm -rf "$src"
}

test_upgrade_stops_under_autocrlf_without_lf_pinned() {
  _unit_project
  git config core.autocrlf true
  git rm -q --cached .gitattributes
  rm .gitattributes
  git commit -q -m "no attributes"

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "core.autocrlf is true"
  assert_contains "$OUT" ".ai/scripts/** text eol=lf"
}

test_upgrade_runs_under_autocrlf_with_lf_pinned() {
  _unit_project
  git config core.autocrlf true

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "core.autocrlf"
}

test_upgrade_stops_while_a_session_works_in_this_checkout() {
  _unit_project
  mkdir -p .ai/runtime/working
  printf 'command: task show other\n' > .ai/runtime/working/other-session

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "a session is working in this checkout (other-session"
  assert_contains "$OUT" ".ai/runtime/working/other-session"

  rm .ai/runtime/working/other-session
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "a session is working"
}

test_upgrade_stops_while_verify_runs_in_this_checkout() {
  _unit_project
  mkdir -p .ai/runtime/verify/busy
  printf 'checkout: %s\npid: %s\n' "$PWD" "$$" > .ai/runtime/verify/busy/run

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "\`jig verify\` is running in this checkout"

  rm -rf .ai/runtime/verify/busy
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
}

# A dry run is read-only and is what status, verify and doctor run: it never
# refuses, it only says what a real run would do.
test_upgrade_dry_run_on_a_dirty_tree_only_notes_it() {
  _unit_project
  printf '\n# local edit\n' >> README.md

  run jig upgrade --dry-run --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "note: a real upgrade would stop: the working tree has uncommitted changes"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"

  run jig status
  assert_not_contains "$OUT" "note: a real upgrade"
}

# At agent.git pr the branch is pushed by the steps `task ship` takes; with no
# forge CLI usable here, the pull request is left to the person, and said so.
test_upgrade_at_agent_git_pr_pushes_its_branch() {
  _unit_project
  local src remote
  remote=$(mktemp -d "${TMPDIR:-/tmp}/jig-remote.XXXXXX")
  git init -q --bare "$remote"
  git remote add origin "$remote"
  git push -q origin main
  jig config set --local agent.git pr >/dev/null
  src=$(_unit_source)

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pushed jig/upgrade-9.9.9"
  git -C "$remote" show-ref --verify --quiet refs/heads/jig/upgrade-9.9.9 \
    || fail "the upgrade branch did not reach origin"

  rm -rf "$src" "$remote"
}

# An upgrade to this version already waiting on its own branch is not started
# a second time on another one: that could only become a second pull request.
test_upgrade_refuses_a_second_branch_for_an_unmerged_upgrade() {
  _unit_project
  local src
  src=$(_unit_source)
  git checkout -q -b jig/upgrade-9.9.9
  git commit -q --allow-empty -m "earlier upgrade, not merged"
  git checkout -q main

  run jig upgrade --from "$src"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "already on branch jig/upgrade-9.9.9, which has not been merged into main"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  [ -z "$(git branch --list 'jig/upgrade-9.9.9-*')" ] || fail "a second upgrade branch was cut"

  rm -rf "$src"
}

# The base already current and the person on a task branch that is not: the
# way forward is the base, and the run says so instead of leaving them to loop.
test_upgrade_with_nothing_to_change_names_the_base_to_merge() {
  _unit_project
  git checkout -q -b task/behind

  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "nothing changed; back on task/behind"
  assert_contains "$OUT" "git merge main"
}

test_upgrade_refuses_when_the_base_branch_exists_nowhere() {
  _unit_project
  sed 's/^git\.base_branch: main/git.base_branch: trunk/' .ai/config.yaml > config.tmp
  mv config.tmp .ai/config.yaml
  git commit -q -am "trunk"

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no branch trunk here or on origin"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_upgrade_refuses_an_invalid_agent_git_before_touching_anything() {
  _unit_project
  printf 'agent.git: sometimes\n' > .ai/config.local.yaml

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid agent.git: sometimes"
  assert_contains "$OUT" "nothing was changed"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

# A pull request squashed by the forge leaves the local upgrade branch behind as
# no ancestor of the base; the base's manifest says the upgrade landed anyway.
test_upgrade_reads_a_squashed_upgrade_branch_as_landed() {
  _unit_project
  git checkout -q -b jig/upgrade-7.7.7
  git commit -q --allow-empty -m "the upgrade, as its branch had it"
  git checkout -q main
  sed 's/^jig\.version: .*/jig.version: 7.7.7/' .ai/manifest > manifest.tmp
  mv manifest.tmp .ai/manifest
  git commit -q -am "the upgrade, squashed"
  local src
  src=$(_unit_source)
  sed 's/^JIG_VERSION=.*/JIG_VERSION="7.7.7"/' "$src/scripts/lib/version.sh" > "$src/v.tmp"
  mv "$src/v.tmp" "$src/scripts/lib/version.sh"

  run jig upgrade --from "$src"
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "has not been merged"
  assert_contains "$OUT" "working on branch jig/upgrade-7.7.7-2"

  rm -rf "$src"
}

test_upgrade_says_nothing_changed_when_its_branch_cannot_be_made() {
  _unit_project
  git branch jig/upgrade-"$(sed -n 's/^JIG_VERSION="\(.*\)"/\1/p' "$JIG_HOME/scripts/lib/version.sh")"/blocker

  run jig upgrade --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "could not create branch"
  assert_contains "$OUT" "nothing was changed"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}
