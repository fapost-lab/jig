# Tests for `jig init` (domains/install, ADR-0003). Runs the real dispatcher from
# the framework source checkout ($JIG_HOME) against a fixture repository.
# shellcheck shell=bash

test_init_suggests_detected_profile_but_only_installs_selection() {
  fixture_repo
  printf '{}\n' > composer.json

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "suggested profiles: php (run again with --profiles php or edit .ai/config.yaml)"

  local cfg_profiles
  cfg_profiles=$(sed -n 's/^profiles: //p' .ai/config.yaml)
  assert_eq "[generic]" "$cfg_profiles"
  assert_no_file .ai/profiles/php
}

test_init_no_suggestion_when_selection_already_covers_detection() {
  fixture_repo
  printf '{}\n' > composer.json

  run jig init --from "$JIG_HOME" --profiles php
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "suggested profiles:"
  assert_file .ai/profiles/php/profile.yaml
}

test_init_creates_expected_layout() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"

  assert_file AGENTS.md
  assert_file CLAUDE.md
  assert_file_contains CLAUDE.md "@AGENTS.md"
  assert_file .ai/config.yaml
  assert_file .ai/manifest
  assert_file .ai/knowledge/GLOSSARY.md
  assert_file .ai/knowledge/ARCHITECTURE.md
  assert_file .ai/knowledge/RULES.md
  assert_file .ai/knowledge/features/.gitkeep
  assert_file .ai/knowledge/conventions/.gitkeep
  assert_file .ai/knowledge/adr/.gitkeep
  assert_dir .ai/workspace/tasks
  assert_dir .ai/runtime

  assert_file .ai/scripts/jig
  [ -x .ai/scripts/jig ] || fail "installed dispatcher is not executable"
  assert_file .ai/profiles/generic/verify.sh
  [ -x .ai/profiles/generic/verify.sh ] || fail "installed verify.sh is not executable"

  assert_file .claude/skills/jig-init/SKILL.md
  assert_file .codex/skills/jig-init/SKILL.md

  assert_file .gitignore
  assert_file_contains .gitignore ".ai/workspace/"
  assert_file_contains .gitignore ".ai/runtime/"

  assert_contains "$OUT" "next:"
}

test_init_installs_document_templates_in_copy_mode() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"

  assert_file .ai/templates/knowledge/feature.md
  assert_file .ai/templates/knowledge/adr.md
  assert_file .ai/templates/knowledge/convention.md
  [ ! -L .ai/templates/knowledge/feature.md ] \
    || fail "expected a regular file, not a symlink: .ai/templates/knowledge/feature.md"

  assert_file_contains .ai/manifest ".ai/templates/knowledge/feature.md"
  assert_file_contains .ai/manifest ".ai/templates/knowledge/adr.md"
  assert_file_contains .ai/manifest ".ai/templates/knowledge/convention.md"
}

test_init_link_mode_symlinks_templates_knowledge_directory() {
  fixture_repo
  run jig init --from "$JIG_HOME" --link
  assert_eq 0 "$RC"

  assert_symlink .ai/templates/knowledge
  assert_file .ai/templates/knowledge/feature.md
  assert_file .ai/templates/knowledge/adr.md
  assert_file .ai/templates/knowledge/convention.md
}

test_init_gitkeep_only_placed_in_empty_dirs() {
  fixture_repo
  mkdir -p .ai/knowledge/adr
  printf '# adr\n' > .ai/knowledge/adr/0001-x.md

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"

  assert_no_file .ai/knowledge/adr/.gitkeep
  assert_file .ai/knowledge/features/.gitkeep
  assert_file .ai/knowledge/conventions/.gitkeep
}

test_init_manifest_format_and_hashes() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"

  assert_file_contains .ai/manifest "jig.version:"
  assert_file_contains .ai/manifest "jig.source: $JIG_HOME"
  assert_file_contains .ai/manifest "jig.mode: copy"
  assert_file_contains .ai/manifest "installed_at:"
  assert_file_contains .ai/manifest "---"

  local adapters_line
  adapters_line=$(sed -n 's/^adapters: //p' .ai/manifest)
  assert_eq "[claude, codex]" "$adapters_line"

  local want got
  want=$(git -C "$JIG_HOME" hash-object scripts/jig)
  got=$(sed -n 's/^\(.*\) \.ai\/scripts\/jig$/\1/p' .ai/manifest)
  assert_eq "$want" "$got"
}

test_init_self_install_writes_dot_source() {
  fixture_repo
  # Make the fixture repository itself a framework source root, and run its
  # own dispatcher with no --from so it self-detects (dogfooding/--link).
  cp -R "$JIG_HOME/scripts" "$JIG_HOME/skills" "$JIG_HOME/templates" \
        "$JIG_HOME/profiles" "$JIG_HOME/adapters" .

  run ./scripts/jig init --link
  assert_eq 0 "$RC"

  local source_line
  source_line=$(sed -n 's/^jig\.source: //p' .ai/manifest)
  assert_eq "." "$source_line"

  run ./scripts/jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "initialised: yes"
  assert_contains "$OUT" "source=$(pwd -P)"
}

test_init_is_idempotent() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  cp .ai/manifest manifest.before.tmp

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 created"
  assert_contains "$OUT" "0 conflict(s)"
  diff -q manifest.before.tmp .ai/manifest >/dev/null || fail "manifest changed on a no-op rerun"
}


# --- re-run picks up the config, not the flag defaults (domains/install) ----------

test_init_rerun_picks_up_profiles_from_config_copy_mode() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  assert_no_file .ai/profiles/shell
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_file .ai/profiles/shell/verify.sh

  # config is not touched when no flag disagrees with it
  local cfg_profiles
  cfg_profiles=$(sed -n 's/^profiles: //p' .ai/config.yaml)
  assert_eq "[generic, shell]" "$cfg_profiles"
}

test_init_rerun_picks_up_profiles_from_config_link_mode() {
  fixture_repo
  jig init --from "$JIG_HOME" --link --profiles generic >/dev/null
  assert_no_file .ai/profiles/shell
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, shell]
adapters: [claude, codex]
EOF

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_symlink .ai/profiles/shell
  # mode sticks to what the manifest already says, no --link needed
  assert_file_contains .ai/manifest "jig.mode: link"
}

test_init_explicit_profiles_flag_overrides_and_rewrites_config() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null

  run jig init --from "$JIG_HOME" --profiles generic,shell
  assert_eq 0 "$RC"
  assert_file .ai/profiles/shell/verify.sh

  local cfg_profiles
  cfg_profiles=$(sed -n 's/^profiles: //p' .ai/config.yaml)
  assert_eq "[generic, shell]" "$cfg_profiles"
}

test_init_explicit_adapters_flag_overrides_and_rewrites_config() {
  fixture_repo
  jig init --from "$JIG_HOME" --adapters claude >/dev/null

  run jig init --from "$JIG_HOME" --adapters claude,codex
  assert_eq 0 "$RC"
  assert_file .codex/skills/jig-init/SKILL.md

  local cfg_adapters
  cfg_adapters=$(sed -n 's/^adapters: //p' .ai/config.yaml)
  assert_eq "[claude, codex]" "$cfg_adapters"
}

test_init_conflict_is_kept_and_not_tracked() {
  fixture_repo
  mkdir -p .ai/scripts
  printf '#!/bin/sh\necho hacked\n' > .ai/scripts/jig

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "conflict"
  assert_contains "$OUT" ".ai/scripts/jig"
  assert_file_contains .ai/scripts/jig "hacked"
  # Match a whole manifest path, not a substring: a manifest line is
  # "<hash> <path>", and `.ai/scripts/jig` is a prefix of its own siblings
  # (`.ai/scripts/jig-session-hook`), which a substring test cannot tell
  # apart from the entry this asserts is absent.
  if grep -q ' \.ai/scripts/jig$' .ai/manifest; then
    fail "conflicted path .ai/scripts/jig is listed in the manifest"
  fi
}

# Reproduces the bug: a re-run of `jig init` used to rewrite the manifest
# from only the paths it touched this run, silently dropping the entry for
# any tracked path it reported as `conflict` (a user-modified file) — real
# `modified` drift then read back as `0 modified`, and a later `jig upgrade`
# no longer had the original hash to compare against, so it reported
# `keep-conflict` instead of `keep-modified` (domains/install).
test_init_rerun_preserves_manifest_entry_for_modified_file() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null

  printf '\n# local edit\n' >> .ai/scripts/lib/common.sh

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 1 modified"

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "conflict"
  assert_contains "$OUT" ".ai/scripts/lib/common.sh"
  assert_file_contains .ai/scripts/lib/common.sh "local edit"

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 1 modified"

  run jig upgrade --from "$JIG_HOME" --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "keep-modified .ai/scripts/lib/common.sh"
  assert_not_contains "$OUT" "keep-conflict .ai/scripts/lib/common.sh"
}

# A re-run must reinstall a tracked file the user deleted locally, and the
# manifest must keep tracking it afterwards (domains/install: a tracked file
# that is absent is installed and kept on the manifest).
test_init_rerun_reinstalls_deleted_tracked_file() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null

  rm -f .ai/scripts/lib/common.sh

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_file .ai/scripts/lib/common.sh
  assert_file_contains .ai/manifest ".ai/scripts/lib/common.sh"

  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "drift: 0 modified, 0 missing"
}

test_init_gitignore_merges_without_duplicating() {
  fixture_repo
  printf '.ai/workspace/\nnode_modules/\n' > .gitignore

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_file_contains .gitignore "node_modules/"
  assert_file_contains .gitignore ".ai/runtime/"

  local count
  count=$(grep -c '^\.ai/workspace/$' .gitignore)
  assert_eq 1 "$count"
}

test_init_respects_adapters_flag() {
  fixture_repo
  run jig init --from "$JIG_HOME" --adapters claude
  assert_eq 0 "$RC"

  assert_file .claude/skills/jig-init/SKILL.md
  assert_no_file .codex

  local cfg_adapters
  cfg_adapters=$(sed -n 's/^adapters: //p' .ai/config.yaml)
  assert_eq "[claude]" "$cfg_adapters"
}

test_init_from_without_value_dies() {
  fixture_repo
  run jig init --from
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires a value"
}

test_init_adapters_without_value_dies() {
  fixture_repo
  run jig init --from "$JIG_HOME" --adapters
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires a value"
}

test_init_profiles_without_value_dies() {
  fixture_repo
  run jig init --from "$JIG_HOME" --profiles
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires a value"
}

test_init_unknown_profile_dies() {
  fixture_repo
  run jig init --from "$JIG_HOME" --profiles does-not-exist
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not found in source"
}

# --- path traversal in profile/adapter names (profile-name-validation task) -
# Reproduces the bug: `jig init --profiles ..` used to walk
# <source>/profiles/.. (i.e. the whole framework checkout root, which is
# $JIG_HOME here) and copy it into the project's .ai/ tree. docs/ and
# tests/ live at $JIG_HOME's top level and must never land under .ai/.

test_init_rejects_path_traversal_profiles_flag() {
  fixture_repo
  run jig init --from "$JIG_HOME" --profiles ..
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
  assert_no_file .ai/docs
  assert_no_file .ai/tests
}

test_init_rejects_path_traversal_profiles_flag_subpath() {
  fixture_repo
  run jig init --from "$JIG_HOME" --profiles ../x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
  assert_no_file .ai/docs
  assert_no_file .ai/tests
}

test_init_rejects_path_traversal_adapters_flag() {
  fixture_repo
  run jig init --from "$JIG_HOME" --adapters ..
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid adapter name"
}

# The same unvalidated names are reachable through .ai/config.yaml on a
# flag-less re-run, not just via --profiles/--adapters.
test_init_config_profiles_reject_path_traversal() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles generic >/dev/null
  cat > .ai/config.yaml <<'EOF'
profiles: [.., generic]
adapters: [claude, codex]
EOF

  run jig init --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid profile name"
  assert_no_file .ai/docs
  assert_no_file .ai/tests
}

test_init_requires_git_repository() {
  run jig init --from "$JIG_HOME"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "git repository"
}

test_init_via_installed_copy_without_from_dies() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig_installed init
  assert_eq 1 "$RC"
  assert_contains "$OUT" "cannot determine the framework source root"
}

test_init_link_mode_creates_relative_symlinks() {
  fixture_repo
  run jig init --from "$JIG_HOME" --link
  assert_eq 0 "$RC"

  assert_symlink .ai/scripts
  case "$(readlink .ai/scripts)" in
    /*) fail "symlink target is absolute: $(readlink .ai/scripts)" ;;
  esac
  assert_symlink .ai/profiles/generic
  assert_symlink .claude/skills/jig-init
  assert_symlink .codex/skills/jig-init

  # the linked tree must actually resolve and work
  assert_file .ai/scripts/lib/common.sh
  run jig_installed status
  assert_eq 0 "$RC"

  assert_file_contains .ai/manifest "jig.mode: link"
  local body
  body=$(sed -n '/^---$/,$p' .ai/manifest | tail -n +2)
  assert_eq "" "$body"
}

test_init_link_mode_is_idempotent() {
  fixture_repo
  jig init --from "$JIG_HOME" --link >/dev/null
  run jig init --from "$JIG_HOME" --link
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 created"
  assert_contains "$OUT" "0 conflict(s)"
}

test_init_codex_transform_end_to_end() {
  fixture_repo
  local src
  src=$(mktemp -d "${TMPDIR:-/tmp}/jig-fixture-src.XXXXXX")
  cp -R "$JIG_HOME"/. "$src"/
  rm -rf "$src/.git"
  mkdir -p "$src/skills/jig-demo"
  cat > "$src/skills/jig-demo/SKILL.md" <<'EOF'
---
name: jig-demo
description: fixture skill for the codex transform test
---
# jig-demo
Run `/jig-demo` to start.
EOF

  run jig init --from "$src" --adapters claude,codex --profiles generic
  assert_eq 0 "$RC"
  # shellcheck disable=SC2016
  assert_file_contains .claude/skills/jig-demo/SKILL.md '`/jig-demo`'
  local codex_content
  codex_content=$(cat .codex/skills/jig-demo/SKILL.md)
  # shellcheck disable=SC2016
  assert_contains "$codex_content" '$jig-demo'
  assert_not_contains "$codex_content" '/jig-demo'

  rm -rf "$src"
}

test_init_installs_scheduler_templates_in_copy_mode() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_file .ai/templates/scheduler/README.md
  assert_file .ai/templates/scheduler/cron.txt
  assert_file .ai/templates/scheduler/launchd.plist
  assert_file .ai/templates/scheduler/systemd.timer
  assert_file .ai/scripts/jig-session-hook
  assert_file_contains .ai/manifest ".ai/templates/scheduler/cron.txt"
}

test_init_link_mode_symlinks_templates_scheduler_directory() {
  fixture_repo
  run jig init --from "$JIG_HOME" --link
  assert_eq 0 "$RC"
  assert_symlink .ai/templates/scheduler
  assert_file .ai/templates/scheduler/README.md
}

test_init_prints_the_session_hook_advisory_without_installing_it() {
  # domains/housekeeping / ADR-0024: the adapter offers the entry, the user installs it.
  # init must stay non-interactive and must not touch .claude/settings.json.
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/scripts/jig-session-hook"
  assert_contains "$OUT" "Codex has no session-start hook"
  assert_no_file .claude/settings.json
}

test_init_leaves_an_existing_settings_json_untouched() {
  fixture_repo
  mkdir -p .claude
  printf '{ "mine": true }\n' > .claude/settings.json
  local before
  before=$(cat .claude/settings.json)

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_eq "$before" "$(cat .claude/settings.json)" "init modified a project-owned file"
}

test_init_session_hook_flag_installs_the_hook() {
  fixture_repo
  run jig init --from "$JIG_HOME" --session-hook
  assert_eq 0 "$RC"
  assert_file_contains .claude/settings.json "jig-session-hook"
  assert_contains "$OUT" "created .claude/settings.json"

  # Installed means the advisory goes quiet and status agrees.
  assert_not_contains "$OUT" "not triggered automatically"
  run jig status
  assert_contains "$OUT" "session hook (claude): installed"
}

test_init_without_the_flag_installs_nothing() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_no_file .claude/settings.json
  assert_contains "$OUT" "not triggered automatically"
}

test_init_session_hook_never_touches_an_existing_settings_file() {
  fixture_repo
  mkdir -p .claude
  printf '{\n  "mine": true\n}\n' > .claude/settings.json
  local before
  before=$(cat .claude/settings.json)

  run jig init --from "$JIG_HOME" --session-hook
  assert_eq 0 "$RC"
  assert_eq "$before" "$(cat .claude/settings.json)" "init edited a project-owned file"
  # Declining is not a failure, and the user still gets told what to add.
  assert_contains "$OUT" "not triggered automatically"
}

test_init_session_hook_is_idempotent() {
  fixture_repo
  jig init --from "$JIG_HOME" --session-hook >/dev/null
  local before
  before=$(cat .claude/settings.json)

  run jig init --from "$JIG_HOME" --session-hook
  assert_eq 0 "$RC"
  assert_eq "$before" "$(cat .claude/settings.json)"
}

test_init_session_hook_file_is_project_owned() {
  # Not in the manifest, so `upgrade` never replaces or restores it: a user
  # who deletes the hook stays without it (ADR-0024).
  fixture_repo
  jig init --from "$JIG_HOME" --session-hook >/dev/null
  assert_not_contains "$(cat .ai/manifest)" "settings.json"

  rm .claude/settings.json
  run jig upgrade --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_no_file .claude/settings.json
}

test_init_rejects_session_hook_with_a_value() {
  fixture_repo
  run jig init --from "$JIG_HOME" --session-hook=yes
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown argument"
}

test_init_works_under_a_project_path_with_shell_metacharacters() {
  # The project root comes from `git rev-parse --show-toplevel`, so it is an
  # arbitrary user path. Prefixing it onto relative paths with `sed` once
  # corrupted every entry — `&` in a sed replacement means "the text that
  # matched" — and left a manifest with an empty body next to a fully copied
  # framework, an install `upgrade` could no longer recognise. Real paths hit
  # this: R&D, AT&T, "Smith & Co".
  mkdir -p 'R&D & Co'
  cd 'R&D & Co' || fail 'cannot enter the fixture directory'
  fixture_repo

  run jig init --from "$JIG_HOME"
  assert_eq 0 "$RC"
  assert_file .ai/manifest

  # Every recorded hash must match the file it names, and the body must not
  # be empty — the corruption showed up as both.
  local entries bad=0 line h p
  entries=$(sed -n '/^---$/,$p' .ai/manifest | tail -n +2 | grep -c .)
  [ "$entries" -gt 10 ] || fail "manifest body has only $entries entries"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    h="${line%% *}"
    p="${line#* }"
    [ "$(git hash-object "$p")" = "$h" ] || bad=$((bad + 1))
  done < <(sed -n '/^---$/,$p' .ai/manifest | tail -n +2)
  assert_eq 0 "$bad" "manifest entries whose hash does not match the file"
}
