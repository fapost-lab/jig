# Tests for `jig spec` (specifications under .ai/specs/, the jig-idea skill).
# shellcheck shell=bash
# shellcheck disable=SC2016 # single-quoted fixture text deliberately keeps its backticks literal

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
  assert_contains "$OUT" "usage: jig spec new <id> | jig spec list | jig spec done <task-id> | jig spec remove <id> [--dry-run] [--abandon-unstarted]"
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
  assert_contains "$OUT" "usage: jig spec new <id> | jig spec list | jig spec done <task-id> | jig spec remove <id> [--dry-run] [--abandon-unstarted]"
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

# --- spec done: argument handling and preconditions ---------------------------

test_spec_done_requires_initialised_project() {
  fixture_repo
  run jig spec "done" T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

test_spec_done_missing_task_id_fails() {
  fixture_jig_repo
  run jig spec "done"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec done: missing task id"
}

test_spec_done_rejects_extra_argument() {
  fixture_jig_repo
  run jig spec "done" T-1 extra
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec done: unexpected argument: extra"
}

test_spec_done_invalid_task_id_fails() {
  fixture_jig_repo
  run jig spec "done" -bad
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec done: invalid task id: -bad"
}

test_spec_done_unknown_task_fails() {
  fixture_jig_repo
  run jig spec "done" ghost
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec done: unknown task: ghost (no .ai/workspace/tasks/ghost/task.md)"
}

# --- spec done: the Spec: line ------------------------------------------------

test_spec_done_task_without_spec_line_is_a_noop() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_eq "spec done: T-1 is not linked to a spec" "$OUT"
}

test_spec_done_spec_line_with_dot_leading_id_does_not_link() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  printf 'Spec: .ai/specs/.bad/\n' >> .ai/workspace/tasks/T-1/task.md
  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_eq "spec done: T-1 is not linked to a spec" "$OUT"
}

test_spec_done_spec_line_with_dash_leading_id_does_not_link() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  printf 'Spec: .ai/specs/-bad/\n' >> .ai/workspace/tasks/T-1/task.md
  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_eq "spec done: T-1 is not linked to a spec" "$OUT"
}

test_spec_done_malformed_spec_line_does_not_link() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  printf 'Spec: .ai/specs/alpha/ something else\n' >> .ai/workspace/tasks/T-1/task.md
  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_eq "spec done: T-1 is not linked to a spec" "$OUT"
}

test_spec_done_recognizes_all_dash_variants_before_phase() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '%s\n' '- [ ] `T-em` — item' '- [ ] `T-hyphen` — item' '- [ ] `T-dbl` — item' \
    > .ai/specs/alpha/roadmap.md

  jig task new T-em >/dev/null
  printf 'Spec: .ai/specs/alpha/ — Phase 1\n' >> .ai/workspace/tasks/T-em/task.md
  jig task new T-hyphen >/dev/null
  printf 'Spec: .ai/specs/alpha/ - Phase 1\n' >> .ai/workspace/tasks/T-hyphen/task.md
  jig task new T-dbl >/dev/null
  printf 'Spec: .ai/specs/alpha/ -- Phase 1\n' >> .ai/workspace/tasks/T-dbl/task.md

  local id
  for id in T-em T-hyphen T-dbl; do
    run jig spec "done" "$id"
    assert_eq 0 "$RC" "dash variant failed for $id"
    assert_contains "$OUT" "spec done: $id checked in .ai/specs/alpha/roadmap.md" "dash variant not recognized for $id"
  done
}

test_spec_done_two_conflicting_spec_lines_fails() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha .ai/specs/beta
  {
    printf 'Spec: .ai/specs/alpha/\n'
    printf 'Spec: .ai/specs/beta/\n'
  } >> .ai/workspace/tasks/T-1/task.md

  run jig spec "done" T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec done: T-1 links to more than one spec in its task.md"
}

# --- spec done: the linked spec must exist and have a roadmap -----------------

test_spec_done_missing_spec_directory_fails() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  printf 'Spec: .ai/specs/ghost-spec/\n' >> .ai/workspace/tasks/T-1/task.md

  run jig spec "done" T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec done: T-1 links to .ai/specs/ghost-spec/, which does not exist"
}

test_spec_done_missing_roadmap_fails() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md

  run jig spec "done" T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec done: no roadmap.md in .ai/specs/alpha/"
}

# --- spec done: marking roadmap items ------------------------------------------

test_spec_done_checks_matching_item_and_prints_it_indented() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/ — Phase 1\n' >> .ai/workspace/tasks/T-1/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
1. Wave one
- [ ] `T-1` — implement thing
- [ ] `T-2` — other thing
EOF

  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "spec done: T-1 checked in .ai/specs/alpha/roadmap.md"
  # The marked line is echoed back indented by two spaces (sed 's/^/  /').
  assert_contains "$OUT" "  - [x] \`T-1\` — implement thing"
  assert_not_contains "$OUT" "[x] \`T-2\`"

  grep -q '^- \[x\] `T-1` — implement thing$' .ai/specs/alpha/roadmap.md \
    || fail "T-1's item was not checked"
  grep -q '^- \[ \] `T-2` — other thing$' .ai/specs/alpha/roadmap.md \
    || fail "T-2's unrelated item was changed"

  [ -z "$(find .ai/specs/alpha -maxdepth 1 -name 'roadmap.md.tmp.*')" ] \
    || fail "leftover tmp file after a successful spec done"
}

# The id is compared as an exact string, not a glob/regex: a "." in an id
# must not act as "any character" and accidentally match a decoy item whose
# backticked head differs only in that position.
test_spec_done_dot_in_task_id_matches_literally() {
  fixture_jig_repo
  jig task new t.one >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/t.one/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `tXone` — decoy that would match if "." were a wildcard
- [ ] `t.one` — the real item
EOF

  run jig spec "done" t.one
  assert_eq 0 "$RC"
  assert_contains "$OUT" "spec done: t.one checked in .ai/specs/alpha/roadmap.md"

  grep -q '^- \[ \] `tXone` — decoy that would match if "\." were a wildcard$' .ai/specs/alpha/roadmap.md \
    || fail "decoy item was checked: '.' was treated as a wildcard"
  grep -q '^- \[x\] `t\.one` — the real item$' .ai/specs/alpha/roadmap.md \
    || fail "the real item was not checked"
}

test_spec_done_checks_every_item_naming_the_task_in_one_call() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `T-1` — first item
- [ ] `T-1` — second item
- [ ] `T-2` — other
EOF

  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_eq "2" "$(grep -c '^- \[x\] `T-1`' .ai/specs/alpha/roadmap.md)" "expected both T-1 items checked"
  grep -q '^- \[ \] `T-2` — other$' .ai/specs/alpha/roadmap.md \
    || fail "unrelated item was changed"
}

# Only the matched lines change; the write is atomic (temp file, then rename).
test_spec_done_only_matched_lines_change_and_write_is_atomic() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
# Roadmap

1. Wave one

- [ ] `T-1` — target item
- [ ] `T-2` — untouched item
- [x] `T-3` — already done
EOF

  run jig spec "done" T-1
  assert_eq 0 "$RC"

  cat > roadmap.expected <<'EOF'
# Roadmap

1. Wave one

- [x] `T-1` — target item
- [ ] `T-2` — untouched item
- [x] `T-3` — already done
EOF
  cmp -s .ai/specs/alpha/roadmap.md roadmap.expected \
    || fail "roadmap.md differs from expected after spec done"
  [ -z "$(find .ai/specs/alpha -maxdepth 1 -name 'roadmap.md.tmp.*')" ] \
    || fail "leftover tmp file after a successful spec done"
}

test_spec_done_already_checked_item_is_a_noop() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  printf -- '- [x] `T-1` — done already\n' > .ai/specs/alpha/roadmap.md
  cp .ai/specs/alpha/roadmap.md roadmap.before

  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_eq "spec done: T-1 already done in .ai/specs/alpha/roadmap.md" "$OUT"
  cmp -s .ai/specs/alpha/roadmap.md roadmap.before \
    || fail "roadmap.md was changed although every matching item was already checked"
  [ -z "$(find .ai/specs/alpha -maxdepth 1 -name 'roadmap.md.tmp.*')" ] \
    || fail "leftover tmp file when every matching item was already checked"
}

test_spec_done_no_matching_item_fails_and_leaves_roadmap_unchanged() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `T-2` — unrelated item
EOF
  cp .ai/specs/alpha/roadmap.md roadmap.before

  run jig spec "done" T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no item in .ai/specs/alpha/roadmap.md names T-1"
  assert_contains "$OUT" "the roadmap and the task disagree"
  cmp -s .ai/specs/alpha/roadmap.md roadmap.before \
    || fail "roadmap.md was changed although no item named the task"
  [ -z "$(find .ai/specs/alpha -maxdepth 1 -name 'roadmap.md.tmp.*')" ] \
    || fail "leftover tmp file when no item named the task"
}

# --- spec remove: argument handling and preconditions --------------------------

test_spec_remove_missing_id_fails() {
  fixture_jig_repo
  run jig spec remove
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec remove: missing spec id"
}

test_spec_remove_invalid_id_fails() {
  fixture_jig_repo
  run jig spec remove ".bad"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec remove: invalid spec id: .bad"
}

test_spec_remove_unknown_flag_fails() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  run jig spec remove alpha --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec remove: unknown argument: --bogus"
  assert_dir .ai/specs/alpha
}

test_spec_remove_rejects_extra_positional_argument() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  run jig spec remove alpha beta
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec remove: unexpected argument: beta"
  assert_dir .ai/specs/alpha
}

test_spec_remove_requires_initialised_project() {
  fixture_repo
  run jig spec remove alpha
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

test_spec_remove_missing_spec_directory_fails() {
  fixture_jig_repo
  run jig spec remove ghost
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec remove: no such spec: .ai/specs/ghost"
}

# A symlink at .ai/specs/<id> that resolves outside .ai/specs must never be
# handed to `mv`: refuse it instead of trashing a path elsewhere.
test_spec_remove_refuses_a_symlink_resolving_outside_specs() {
  fixture_jig_repo
  mkdir -p outside/evil-target .ai/specs
  ln -s "$(cd outside/evil-target && pwd -P)" .ai/specs/evil

  run jig spec remove evil
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec remove: refusing to move a path outside .ai/specs:"
  assert_symlink .ai/specs/evil
  assert_dir outside/evil-target
}

# --- spec remove: closed tasks are left alone -----------------------------------

test_spec_remove_keeps_consolidated_task_untouched() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  cat >> .ai/workspace/tasks/T-1/task.md <<'EOF'
Spec: .ai/specs/alpha/ — Phase 1
EOF
  jig task set T-1 knowledge_consolidated true >/dev/null
  jig task set T-1 status consolidated >/dev/null
  cp .ai/workspace/tasks/T-1/task.md task.before

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "kept           T-1 (consolidated)"
  cmp -s .ai/workspace/tasks/T-1/task.md task.before \
    || fail "a consolidated task's task.md was modified"
  assert_eq "consolidated" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)"
}

test_spec_remove_keeps_abandoned_task_untouched() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  cat >> .ai/workspace/tasks/T-1/task.md <<'EOF'
Spec: .ai/specs/alpha/
EOF
  jig task abandon T-1 >/dev/null
  cp .ai/workspace/tasks/T-1/task.md task.before

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "kept           T-1 (abandoned)"
  cmp -s .ai/workspace/tasks/T-1/task.md task.before \
    || fail "an abandoned task's task.md was modified"
}

test_spec_remove_conflicting_spec_line_is_kept_and_untouched() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha .ai/specs/beta
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  printf '# Beta\n' > .ai/specs/beta/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/beta/roadmap.md
  jig task new T-1 >/dev/null
  cat >> .ai/workspace/tasks/T-1/task.md <<'EOF'
Spec: .ai/specs/alpha/
Spec: .ai/specs/beta/
EOF
  cp .ai/workspace/tasks/T-1/task.md task.before

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "kept           T-1 (links to more than one spec)"
  cmp -s .ai/workspace/tasks/T-1/task.md task.before \
    || fail "a task with a conflicting Spec: line was modified"
}

# --- spec remove: unlinking open tasks ------------------------------------------

test_spec_remove_unlinks_open_task_and_leaves_other_lines_untouched() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  cat > .ai/workspace/tasks/T-1/task.md <<'EOF'
# T-1

## Goal

Spec: .ai/specs/alpha/ — Phase 1

## Scope
EOF

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unlinked       T-1"

  cat > task.expected <<'EOF'
# T-1

## Goal


## Scope
EOF
  cmp -s .ai/workspace/tasks/T-1/task.md task.expected \
    || fail "unlink changed more than the Spec: line"
  assert_eq "active" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)"
}

test_spec_remove_without_abandon_flag_only_unlinks_unstarted_task() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unlinked       T-1"
  assert_not_contains "$OUT" "abandoned"
  assert_eq "active" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)"
}

test_spec_remove_abandon_unstarted_abandons_a_filed_only_task() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md

  run jig spec remove alpha --abandon-unstarted
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unlinked       T-1"
  assert_contains "$OUT" "abandoned      T-1 (not started)"
  # Abandon is reported before unlink: the `Spec:` line is what finds the
  # task, so abandoning first (and unlinking only after it succeeds) is what
  # keeps a failed abandon retryable.
  assert_contains "$OUT" "abandoned      T-1 (not started)
unlinked       T-1"
  assert_eq "abandoned" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)"
}

test_spec_remove_abandon_unstarted_never_abandons_a_started_task() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  git checkout -q main
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md

  run jig spec remove alpha --abandon-unstarted
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unlinked       T-1"
  assert_not_contains "$OUT" "abandoned"
  assert_eq "active" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)"
}

# --- spec remove: roadmap ids with no local workspace ---------------------------

test_spec_remove_reports_roadmap_id_with_no_local_workspace() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `ghost-task` — item' > .ai/specs/alpha/roadmap.md

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not-here       ghost-task (named in the roadmap, no workspace in this checkout)"
}

# A symlinked workspace belongs to a different checkout (ADR-0029) and must
# be skipped entirely: not reported as kept/unlinked, its task.md never
# touched. Because it is skipped, its roadmap item is reported the same way
# as a task with no local workspace at all.
test_spec_remove_skips_symlinked_workspace() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md

  mkdir -p ../elsewhere-tasks/T-1
  cat > ../elsewhere-tasks/T-1/task.md <<'EOF'
# T-1

Spec: .ai/specs/alpha/
EOF
  mkdir -p .ai/workspace/tasks
  ln -s "$(cd ../elsewhere-tasks/T-1 && pwd -P)" .ai/workspace/tasks/T-1
  cp ../elsewhere-tasks/T-1/task.md linked.before

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not-here       T-1 (named in the roadmap, no workspace in this checkout)"
  assert_not_contains "$OUT" "unlinked       T-1"
  assert_not_contains "$OUT" "kept           T-1"
  cmp -s ../elsewhere-tasks/T-1/task.md linked.before \
    || fail "a symlinked workspace's task.md was modified"
}

# --- spec remove: moving the spec directory to trash ----------------------------

test_spec_remove_moves_spec_to_trash_and_a_second_removal_appends_a_suffix() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\nmarker-one\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/alpha/roadmap.md
  local today dest
  today=$(date +%Y-%m-%d)
  dest=".ai/runtime/trash/$today/spec-alpha"

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "moved          .ai/specs/alpha -> $dest"
  assert_no_file .ai/specs/alpha
  assert_dir "$dest"
  assert_file "$dest/spec.md"
  assert_contains "$(cat "$dest/spec.md")" "marker-one"

  # Recreate a spec by the same id, same day: the second removal must not
  # collide with the first entry already in trash.
  mkdir -p .ai/specs/alpha
  printf '# Alpha again\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/alpha/roadmap.md

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_contains "$OUT" "moved          .ai/specs/alpha -> $dest-2"
  assert_dir "$dest-2"
}

# --- spec remove: --dry-run changes nothing -------------------------------------

test_spec_remove_dry_run_reports_the_plan_and_changes_nothing() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `T-kept` — item
- [ ] `T-unlink` — item
- [ ] `T-abandon` — item
- [ ] `ghost` — item
EOF

  jig task new T-kept >/dev/null
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-kept/task.md
  jig task set T-kept knowledge_consolidated true >/dev/null
  jig task set T-kept status consolidated >/dev/null

  jig task new T-unlink >/dev/null
  jig task start T-unlink >/dev/null
  git checkout -q main
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-unlink/task.md

  jig task new T-abandon >/dev/null
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-abandon/task.md

  cp -R .ai snapshot-ai

  run jig spec remove alpha --dry-run --abandon-unstarted
  assert_eq 0 "$RC"
  assert_contains "$OUT" "kept           T-kept (consolidated)"
  assert_contains "$OUT" "would-unlink   T-unlink"
  assert_contains "$OUT" "would-unlink   T-abandon"
  assert_contains "$OUT" "would-abandon  T-abandon (not started)"
  assert_not_contains "$OUT" "would-abandon  T-unlink"
  # would-abandon is reported before would-unlink for the same task, matching
  # the real (non-dry-run) order.
  assert_contains "$OUT" "would-abandon  T-abandon (not started)
would-unlink   T-abandon"
  assert_contains "$OUT" "not-here       ghost (named in the roadmap, no workspace in this checkout)"
  assert_contains "$OUT" "would-move     .ai/specs/alpha -> .ai/runtime/trash/$(date +%Y-%m-%d)/spec-alpha"

  diff -r .ai snapshot-ai >/dev/null || fail "--dry-run changed something under .ai"
  assert_dir .ai/specs/alpha
}

# --- spec remove: happy path, several task states in one call -------------------

test_spec_remove_happy_path_reports_and_applies_every_task_state() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `T-kept` — item
- [ ] `T-unlink-only` — item
- [ ] `T-abandon` — item
- [ ] `ghost` — item
EOF

  jig task new T-kept >/dev/null
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-kept/task.md
  jig task set T-kept knowledge_consolidated true >/dev/null
  jig task set T-kept status consolidated >/dev/null
  cp .ai/workspace/tasks/T-kept/task.md kept.before

  jig task new T-unlink-only >/dev/null
  jig task start T-unlink-only >/dev/null
  git checkout -q main
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-unlink-only/task.md

  jig task new T-abandon >/dev/null
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-abandon/task.md

  run jig spec remove alpha --abandon-unstarted
  assert_eq 0 "$RC"
  assert_contains "$OUT" "kept           T-kept (consolidated)"
  assert_contains "$OUT" "unlinked       T-unlink-only"
  assert_contains "$OUT" "unlinked       T-abandon"
  assert_contains "$OUT" "abandoned      T-abandon (not started)"
  assert_not_contains "$OUT" "abandoned      T-unlink-only"
  # abandoned is reported before unlinked for the same task.
  assert_contains "$OUT" "abandoned      T-abandon (not started)
unlinked       T-abandon"
  assert_contains "$OUT" "not-here       ghost (named in the roadmap, no workspace in this checkout)"
  assert_contains "$OUT" "moved          .ai/specs/alpha -> .ai/runtime/trash/$(date +%Y-%m-%d)/spec-alpha"

  cmp -s .ai/workspace/tasks/T-kept/task.md kept.before \
    || fail "kept task's task.md was modified"
  assert_not_contains "$(cat .ai/workspace/tasks/T-unlink-only/task.md)" "Spec:"
  assert_not_contains "$(cat .ai/workspace/tasks/T-abandon/task.md)" "Spec:"
  assert_eq "consolidated" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-kept/state)"
  assert_eq "active" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-unlink-only/state)"
  assert_eq "abandoned" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-abandon/state)"
  assert_no_file .ai/specs/alpha
  assert_dir ".ai/runtime/trash/$(date +%Y-%m-%d)/spec-alpha"
}

# --- spec remove: a failed abandon is retryable, never becomes a silent unlink --
# When `task abandon` itself fails, spec remove must die before the Spec:
# line is dropped: abandon runs before unlink so a failed abandon can never
# turn into an unlink nothing can find again. Forced here with a read-only
# workspace directory, which makes `_task_rewrite_state`'s own temp-file
# write fail (chmod 000 on the state file would not: root aside, the
# permission that blocks *creating* state.tmp.$$ belongs to the directory).

test_spec_remove_abandon_failure_leaves_the_spec_line_and_is_retryable() {
  fixture_jig_repo
  if [ "$(id -u)" -eq 0 ]; then
    # A read-only directory does not block a root writer, so the abandon
    # this test forces to fail would succeed instead.
    printf 'skip: running as root, a read-only directory does not block writes\n'
    return 0
  fi
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf '%s\n' '- [ ] `T-1` — item' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md

  chmod 555 .ai/workspace/tasks/T-1
  run jig spec remove alpha --abandon-unstarted
  chmod 755 .ai/workspace/tasks/T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec remove: could not abandon T-1; the spec was not moved"
  assert_file_contains .ai/workspace/tasks/T-1/task.md "Spec: .ai/specs/alpha/"
  assert_eq "active" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)"
  assert_dir .ai/specs/alpha

  # Retried once the directory is writable again: the Spec: line still finds
  # the task, and this time it goes through.
  run jig spec remove alpha --abandon-unstarted
  assert_eq 0 "$RC"
  assert_contains "$OUT" "abandoned      T-1 (not started)"
  assert_eq "abandoned" "$(sed -n 's/^status:[[:space:]]*//p' .ai/workspace/tasks/T-1/state)"
  assert_no_file .ai/specs/alpha
}

# --- spec remove: conflict detection compares spec ids literally --------------
# spec_links_to compares a spec id as an exact string. A grep pattern would
# have let "." in an id like "a.b" match any character, so a task linking to
# two entirely unrelated specs such as "axb" and "ayb" would have been
# wrongly reported as conflicting over "a.b".

test_spec_remove_conflict_detection_does_not_pattern_match_a_dot_in_the_id() {
  fixture_jig_repo
  mkdir -p .ai/specs/a.b .ai/specs/axb .ai/specs/ayb
  printf '# A.B\n' > .ai/specs/a.b/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/a.b/roadmap.md
  printf '# AXB\n' > .ai/specs/axb/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/axb/roadmap.md
  printf '# AYB\n' > .ai/specs/ayb/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/ayb/roadmap.md
  jig task new T-decoy >/dev/null
  cat >> .ai/workspace/tasks/T-decoy/task.md <<'EOF'
Spec: .ai/specs/axb/
Spec: .ai/specs/ayb/
EOF

  run jig spec remove a.b
  assert_eq 0 "$RC"
  # Neither of T-decoy's two links names a.b, so it is not part of this
  # removal at all: not kept, not unlinked, not mentioned.
  assert_not_contains "$OUT" "T-decoy"
}

test_spec_remove_conflict_detection_still_matches_a_real_conflicting_link() {
  fixture_jig_repo
  mkdir -p .ai/specs/a.b .ai/specs/other
  printf '# A.B\n' > .ai/specs/a.b/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/a.b/roadmap.md
  printf '# Other\n' > .ai/specs/other/spec.md
  printf '%s\n' '- [ ] item' > .ai/specs/other/roadmap.md
  jig task new T-conflict >/dev/null
  cat >> .ai/workspace/tasks/T-conflict/task.md <<'EOF'
Spec: .ai/specs/a.b/
Spec: .ai/specs/other/
EOF
  cp .ai/workspace/tasks/T-conflict/task.md task.before

  run jig spec remove a.b
  assert_eq 0 "$RC"
  assert_contains "$OUT" "kept           T-conflict (links to more than one spec)"
  cmp -s .ai/workspace/tasks/T-conflict/task.md task.before \
    || fail "a task with a conflicting Spec: line was modified"
}

# --- spec remove: roadmap ids with an invalid leading character are skipped ----
# spec_roadmap_ids applies the same grammar as jig_valid_id: an id starting
# with "." or "-" is not addressable by anything and must not be reported at
# all, not even as "not-here".

test_spec_remove_roadmap_ids_skip_leading_dot_or_dash() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `-bad` — x
- [ ] `.bad` — x
- [ ] `T-9` — x
EOF

  run jig spec remove alpha
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "-bad"
  assert_not_contains "$OUT" ".bad"
  assert_contains "$OUT" "not-here       T-9 (named in the roadmap, no workspace in this checkout)"
}
