# Tests for `jig spec` (specifications under .ai/specs/, the jig-idea skill).
# shellcheck shell=bash

# --- spec list: empty state --------------------------------------------------

test_spec_list_no_specs_dir_is_empty() {
  fixture_repo
  run jig spec list
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

# --- spec list: a complete spec ----------------------------------------------

test_spec_list_complete_spec_reports_title_and_roadmap_counts() {
  fixture_repo
  mkdir -p .ai/specs/idea-flow
  cat > .ai/specs/idea-flow/spec.md <<'EOF'
# Flow Idea

Some body text.

# Ignored Second Heading
EOF
  cat > .ai/specs/idea-flow/roadmap.md <<'EOF'
1. Wave one
2. Wave two
- [x] `T-1` shipped task
- [X] `T-2` shipped task, capital X
- [ ] `T-3` - filed task
- [ ] fog: uncertain direction
- [ ] plain unchecked item
EOF

  run jig spec list
  assert_eq 0 "$RC"
  # Numbered "Wave" lines are not checkboxes and are not counted; done=2
  # (one lower-case x, one capital X), filed=1 (backticked id followed by a
  # dash separator), fog=1, and the plain unchecked item counts toward the
  # total but not filed/fog.
  assert_eq "idea-flow   Flow Idea   roadmap 2/5 done, 1 filed, fog 1" "$OUT"
}

# --- spec list: filed detection needs a dash after the backticked id --------
# An unchecked item is "filed" only when a backticked task id is followed by
# whitespace, a dash separator ("—", "-" or "--"), and whitespace. A
# backticked command name with no dash-separated goal (or one that is not a
# valid id at all, e.g. it contains spaces) is a plain planned item instead.

test_spec_list_filed_requires_dash_separator_after_backtick_id() {
  fixture_repo
  mkdir -p .ai/specs/idea-a
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md
  cat > .ai/specs/idea-a/roadmap.md <<'EOF'
- [ ] `t2` — goal one
- [ ] `t3` - goal two
- [ ] `jig-consolidate` checks the item
- [ ] `jig spec remove` with flags
EOF

  run jig spec list
  assert_eq 0 "$RC"
  # t2 (em dash) and t3 (hyphen) are filed; jig-consolidate has no dash
  # separator and jig spec remove is not a valid backticked id (it contains
  # spaces) — both count as plain unchecked items instead.
  assert_eq "idea-a   Idea A   roadmap 0/4 done, 2 filed, fog 0" "$OUT"
}

# --- spec list: id/title column padding --------------------------------------

test_spec_list_pads_id_and_title_columns_to_the_widest() {
  fixture_repo
  mkdir -p .ai/specs/id1 .ai/specs/i
  cat > .ai/specs/id1/spec.md <<'EOF'
# AAAA
EOF
  cat > .ai/specs/id1/roadmap.md <<'EOF'
- [x] `T-1` done
EOF
  cat > .ai/specs/i/spec.md <<'EOF'
# BB
EOF
  cat > .ai/specs/i/roadmap.md <<'EOF'
- [x] one
- [X] two
EOF

  run jig spec list
  assert_eq 0 "$RC"
  # wi = max(len("id1")=3, len("i")=1) = 3; wt = max(len("AAAA")=4, len("BB")=2) = 4.
  # "i" pads to "i  " (3) and "BB" pads to "BB  " (4); "id1" and "AAAA" need
  # no padding since they already are the widest. Columns are separated by
  # exactly 3 literal spaces on top of that padding.
  assert_contains "$OUT" "id1   AAAA   roadmap 1/1 done, 0 filed, fog 0"
  assert_contains "$OUT" "i     BB     roadmap 2/2 done, 0 filed, fog 0"
}

# --- spec list: incomplete specs ---------------------------------------------

test_spec_list_no_roadmap_reports_incomplete() {
  fixture_repo
  mkdir -p .ai/specs/idea-a
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md

  run jig spec list
  assert_eq 0 "$RC"
  assert_eq "idea-a   Idea A   incomplete (no roadmap.md)" "$OUT"
}

test_spec_list_no_spec_md_reports_dash_title_and_incomplete() {
  fixture_repo
  mkdir -p .ai/specs/idea-a
  printf '%s\n' '- [ ] item' > .ai/specs/idea-a/roadmap.md

  run jig spec list
  assert_eq 0 "$RC"
  assert_eq "idea-a   -   incomplete (no spec.md)" "$OUT"
}

test_spec_list_neither_file_reports_both_missing() {
  fixture_repo
  mkdir -p .ai/specs/idea-a

  run jig spec list
  assert_eq 0 "$RC"
  assert_eq "idea-a   -   incomplete (no spec.md, roadmap.md)" "$OUT"
}

# --- spec list: id validity and non-directory entries ------------------------

test_spec_list_skips_invalid_ids_and_plain_files() {
  fixture_repo
  mkdir -p .ai/specs/idea-a
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md
  printf '%s\n' '- [x] done' > .ai/specs/idea-a/roadmap.md
  mkdir -p .ai/specs/.hidden
  mkdir -p .ai/specs/-x
  printf 'not a spec dir\n' > .ai/specs/readme.txt

  run jig spec list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "idea-a"
  assert_not_contains "$OUT" ".hidden"
  assert_not_contains "$OUT" "-x"
  assert_not_contains "$OUT" "readme"
  local lines
  lines=$(printf '%s\n' "$OUT" | grep -c .)
  assert_eq "1" "$lines" "expected exactly one spec row"
}

# --- spec new: happy path -----------------------------------------------------

test_spec_new_creates_files_from_templates_and_lists() {
  fixture_jig_repo
  run jig spec new idea-x
  assert_eq 0 "$RC"
  assert_eq ".ai/specs/idea-x/spec.md
.ai/specs/idea-x/roadmap.md" "$OUT"

  assert_file .ai/specs/idea-x/spec.md
  assert_file .ai/specs/idea-x/roadmap.md
  cmp -s .ai/specs/idea-x/spec.md .ai/templates/spec/spec.md \
    || fail "spec.md is not a byte copy of the template"
  cmp -s .ai/specs/idea-x/roadmap.md .ai/templates/spec/roadmap.md \
    || fail "roadmap.md is not a byte copy of the template"

  run jig spec list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "idea-x"
}

# --- spec new: invalid ids ----------------------------------------------------

test_spec_new_rejects_invalid_ids() {
  fixture_jig_repo
  local id
  for id in "My idea" ".x" "-x" "a/b"; do
    run jig spec new "$id"
    assert_eq 1 "$RC" "expected failure for id [$id]"
    assert_contains "$OUT" "spec new: invalid spec id: $id" "wrong message for id [$id]"
  done
  assert_no_file .ai/specs/My
  assert_no_file .ai/specs/.x
  assert_no_file .ai/specs/-x
  assert_no_file .ai/specs/a
  # Nothing at all under .ai/specs: every id above was refused before mkdir.
  assert_no_file .ai/specs
}

# id validation runs before the init check, so an invalid id in an
# uninitialised repo is refused for its shape, not for the missing project.
test_spec_new_invalid_id_checked_before_init() {
  fixture_repo
  run jig spec new "-x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid spec id"
  assert_not_contains "$OUT" "not initialised"
}

# --- spec new: existing spec ---------------------------------------------------

test_spec_new_refuses_existing_spec_and_leaves_it_untouched() {
  fixture_jig_repo
  run jig spec new idea-x
  assert_eq 0 "$RC"
  printf 'custom content\n' > .ai/specs/idea-x/spec.md
  printf 'custom roadmap\n' > .ai/specs/idea-x/roadmap.md

  run jig spec new idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec new: spec already exists: .ai/specs/idea-x"

  assert_eq "custom content" "$(cat .ai/specs/idea-x/spec.md)"
  assert_eq "custom roadmap" "$(cat .ai/specs/idea-x/roadmap.md)"
}

# --- spec new: uninitialised repo ----------------------------------------------

test_spec_new_requires_initialised_project() {
  fixture_repo
  run jig spec new idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
  assert_no_file .ai/specs
}

# --- spec new: argument handling ------------------------------------------------

test_spec_new_missing_id_fails() {
  fixture_jig_repo
  run jig spec new
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec new: missing spec id"
}

test_spec_new_rejects_extra_argument() {
  fixture_jig_repo
  run jig spec new idea-x extra
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec new: unexpected argument: extra"
  assert_no_file .ai/specs/idea-x
}

# --- spec new: fallback to the framework checkout -------------------------------
# A project initialised before spec templates existed (or one where the
# installed copy was removed) still resolves the templates from the running
# jig's own source checkout (spec_template, mirrors km_template's fallback).

test_spec_new_falls_back_to_framework_checkout_when_installed_template_missing() {
  fixture_jig_repo
  rm -rf .ai/templates/spec
  run jig spec new idea-x
  assert_eq 0 "$RC"
  assert_file .ai/specs/idea-x/spec.md
  assert_file .ai/specs/idea-x/roadmap.md
  cmp -s .ai/specs/idea-x/spec.md "$JIG_HOME/templates/spec/spec.md" \
    || fail "spec.md was not instantiated from the framework checkout"
  cmp -s .ai/specs/idea-x/roadmap.md "$JIG_HOME/templates/spec/roadmap.md" \
    || fail "roadmap.md was not instantiated from the framework checkout"
}

# When neither the installed copy nor a resolvable framework checkout has the
# template, spec new dies naming the missing file and points at `jig upgrade`
# rather than silently falling through (jig_installed runs from a copy with
# no source checkout to fall back to, mirroring
# test_upgrade_missing_from_falls_back_to_manifest_source's setup).
test_spec_new_dies_when_no_template_is_resolvable() {
  fixture_jig_repo
  rm -rf .ai/templates/spec
  run jig_installed spec new idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec new: no template spec.md; run: jig upgrade"
  assert_no_file .ai/specs/idea-x
}

# A failed template copy (e.g. an unreadable template) must not leave a
# half-created spec directory behind, and a retry after the fix must work.
# Runs through the installed dispatcher (as test_spec_new_dies_when_no_template_is_resolvable
# does) so no framework-checkout fallback can mask the forced failure.
test_spec_new_rolls_back_and_dies_when_a_template_copy_fails() {
  fixture_jig_repo
  if [ "$(id -u)" -eq 0 ]; then
    # chmod 000 does not block a root reader, so the copy this test forces to
    # fail would succeed instead; nothing meaningful to assert as root.
    printf 'skip: running as root, chmod 000 does not block reads\n'
    return 0
  fi
  chmod 000 .ai/templates/spec/roadmap.md

  run jig_installed spec new partial
  chmod 644 .ai/templates/spec/roadmap.md
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec new: could not copy the templates into .ai/specs/partial"
  assert_no_file .ai/specs/partial

  run jig_installed spec new partial
  assert_eq 0 "$RC"
  assert_file .ai/specs/partial/spec.md
  assert_file .ai/specs/partial/roadmap.md
}

# --- subcommand handling ------------------------------------------------------

test_spec_list_rejects_extra_argument() {
  fixture_repo
  run jig spec list extra
  assert_eq 1 "$RC"
}

test_spec_without_subcommand_fails() {
  fixture_repo
  run jig spec
  [ "$RC" -ne 0 ] || fail "expected non-zero exit, got 0"
  assert_contains "$OUT" "usage: jig spec new <id> | jig spec list"
}

test_spec_unknown_subcommand_fails_naming_it() {
  fixture_repo
  run jig spec frobnicate
  [ "$RC" -ne 0 ] || fail "expected non-zero exit, got 0"
  assert_contains "$OUT" "unknown subcommand: frobnicate"
}

test_spec_help_exits_zero() {
  fixture_repo
  run jig spec --help
  assert_eq 0 "$RC"
  assert_contains "$OUT" "usage: jig spec new <id> | jig spec list"
}

# --- specs are not knowledge --------------------------------------------------
# A spec is a plan outside .ai/knowledge/ (spec.sh header comment); it must
# never surface through the knowledge machinery an agent's context is built
# from.

test_spec_is_not_knowledge() {
  fixture_jig_repo
  mkdir -p .ai/specs/idea-a
  printf '%s\n' '# Idea A' > .ai/specs/idea-a/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/idea-a/roadmap.md

  run jig knowledge check
  assert_eq 0 "$RC"

  run jig context resolve --no-task --catalog --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" ".ai/specs"
}
