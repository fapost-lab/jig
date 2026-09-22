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
  # The copy this test forces to fail succeeds wherever chmod 000 does not
  # block reads: as root, and in Git Bash on NTFS.
  skip_unless_unreadable_files
  fixture_jig_repo
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
  assert_contains "$OUT" "usage: jig spec new <id> | jig spec list | jig spec plan <id> --phase <n> [--format text|tsv] | jig spec done <task-id> | jig spec close <id> [--leftovers-handled] | jig spec remove <id> [--dry-run] [--abandon-unstarted] | jig spec epic <id> [--release patch|minor|major | --finish [--leftovers-handled] | --reopen] | jig spec ship <id> [--message-file <file>] [--title <t>] [--body-file <file>]"
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
  assert_contains "$OUT" "usage: jig spec new <id> | jig spec list | jig spec plan <id> --phase <n> [--format text|tsv] | jig spec done <task-id> | jig spec close <id> [--leftovers-handled] | jig spec remove <id> [--dry-run] [--abandon-unstarted] | jig spec epic <id> [--release patch|minor|major | --finish [--leftovers-handled] | --reopen] | jig spec ship <id> [--message-file <file>] [--title <t>] [--body-file <file>]"
}

# `help` (no dashes) is the subcommand form, same as `--help`/`-h`.
test_spec_help_subcommand_exits_zero() {
  fixture_repo
  run jig spec help
  assert_eq 0 "$RC"
  assert_contains "$OUT" "usage: jig spec new <id> | jig spec list | jig spec plan <id> --phase <n> [--format text|tsv] | jig spec done <task-id> | jig spec close <id> [--leftovers-handled] | jig spec remove <id> [--dry-run] [--abandon-unstarted] | jig spec epic <id> [--release patch|minor|major | --finish [--leftovers-handled] | --reopen] | jig spec ship <id> [--message-file <file>] [--title <t>] [--body-file <file>]"
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

# --- spec done: the "roadmap complete" hint (ADR-0035 as amended) -------------
# Printed once no planned (non-fog) item is left unchecked, pointing at
# `spec close` for a spec with no epic and at `spec epic --finish` for one
# with an open Epic: line. Fog alone never keeps a roadmap "incomplete".

test_spec_done_complete_hint_without_epic_when_only_fog_is_left() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `T-1` — last item
- [ ] fog: leftover direction
EOF

  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "spec done: alpha roadmap complete; close it with \`jig spec close alpha\`"
}

test_spec_done_complete_hint_names_epic_finish_when_an_epic_is_declared() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
Destination: ship it.

Epic: epic/alpha

- [ ] `T-1` — last item
EOF

  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "spec done: alpha roadmap complete; close it with \`jig spec epic alpha --finish\` on epic/alpha"
}

test_spec_done_complete_hint_absent_while_a_planned_item_is_unchecked() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
- [ ] `T-1` — first item
- [ ] `T-2` — still open item
EOF

  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "roadmap complete"
}

test_spec_done_complete_hint_absent_when_already_done() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  mkdir -p .ai/specs/alpha
  printf 'Spec: .ai/specs/alpha/\n' >> .ai/workspace/tasks/T-1/task.md
  printf -- '- [ ] `T-1` — only item\n' > .ai/specs/alpha/roadmap.md
  jig spec "done" T-1 >/dev/null

  run jig spec "done" T-1
  assert_eq 0 "$RC"
  assert_eq "spec done: T-1 already done in .ai/specs/alpha/roadmap.md" "$OUT"
  assert_not_contains "$OUT" "roadmap complete"
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
  plant_dir_link "$(cd outside/evil-target && pwd -P)" .ai/specs/evil

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
  # The way a task worktree borrows a workspace (ADR-0029): a symbolic link,
  # or a junction where symbolic links cannot be made.
  plant_dir_link "$(cd ../elsewhere-tasks/T-1 && pwd -P)" .ai/workspace/tasks/T-1
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
  # The abandon this test forces to fail succeeds wherever a read-only
  # directory does not block writes: as root, and in Git Bash on NTFS.
  skip_unless_readonly_dirs
  fixture_jig_repo
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

# --- spec close (ADR-0035 as amended) ------------------------------------------
# Removes a spec whose work is done, in the change that finished it. Its
# leftover gate (spec_leftovers) is exercised here too, since `spec close`
# and `spec epic --finish` share the same underlying spec_close_dir.

test_spec_close_missing_id_fails() {
  fixture_jig_repo
  run jig spec close
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec close: missing spec id"
}

test_spec_close_invalid_id_fails() {
  fixture_jig_repo
  run jig spec close ".bad"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec close: invalid spec id: .bad"
}

test_spec_close_invalid_id_checked_before_init() {
  fixture_repo
  run jig spec close "-bad"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid spec id"
  assert_not_contains "$OUT" "not initialised"
}

test_spec_close_rejects_unexpected_argument() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  run jig spec close alpha extra
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec close: unexpected argument: extra"
  assert_dir .ai/specs/alpha
}

test_spec_close_requires_initialised_project() {
  fixture_repo
  run jig spec close alpha
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

test_spec_close_missing_spec_directory_fails() {
  fixture_jig_repo
  run jig spec close ghost
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec close: no such spec: .ai/specs/ghost"
}

test_spec_close_refuses_a_spec_built_on_an_open_epic() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf 'Destination: ship it.\n\nEpic: epic/alpha\n' > .ai/specs/alpha/roadmap.md

  run jig spec close alpha
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec close: alpha is built on an epic; close it with \`jig spec epic alpha --finish\` on the epic"
  assert_dir .ai/specs/alpha
}

# Two conflicting Epic: lines (jig_spec_epic exits 2): still refused as
# "built on an epic" rather than a separate conflict message — spec close
# only needs to know whether an epic is involved, not which one.
test_spec_close_refuses_a_spec_with_conflicting_epic_lines() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf 'Epic: epic/a\nEpic: epic/b\n' > .ai/specs/alpha/roadmap.md

  run jig spec close alpha
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec close: alpha is built on an epic; close it with \`jig spec epic alpha --finish\` on the epic"
  assert_dir .ai/specs/alpha
}

# spec_leftovers (AC-01): unchecked roadmap items, fog included, and the
# spec's own Open questions / Assumptions left untested bullets; the
# template's `<placeholder>` bullets are never leftovers, and bullets under
# any other heading (e.g. Decisions) are never counted.
test_spec_close_lists_leftovers_including_fog_and_skips_placeholders() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  cat > .ai/specs/alpha/roadmap.md <<'EOF'
# Roadmap

Destination: ship it.

## Phase 1

- [ ] `T-1` — do the thing
- [ ] plain item not filed
- [ ] fog: something uncertain
- [x] `T-0` — already done
- [ ] <placeholder item>
EOF
  cat > .ai/specs/alpha/spec.md <<'EOF'
# Alpha

## Decisions

- Not a leftover — decided already.

## Open questions

- Real open question — what depends on it.
- <placeholder question> — what depends on it.

## Assumptions left untested

- Real assumption — untested.
- <placeholder assumption>
EOF

  run jig spec close alpha
  assert_eq 1 "$RC"
  assert_contains "$OUT" "  item: \`T-1\` — do the thing"
  assert_contains "$OUT" "  item: plain item not filed"
  assert_contains "$OUT" "  item: fog: something uncertain"
  assert_contains "$OUT" "  question: Real open question — what depends on it."
  assert_contains "$OUT" "  assumption: Real assumption — untested."
  assert_not_contains "$OUT" "placeholder item"
  assert_not_contains "$OUT" "placeholder question"
  assert_not_contains "$OUT" "placeholder assumption"
  assert_not_contains "$OUT" "Not a leftover"
  assert_not_contains "$OUT" "T-0"
  assert_contains "$OUT" "spec close: .ai/specs/alpha still holds what knowledge does not (above); move each one to another spec or task, or drop it, then run again with --leftovers-handled"
  assert_dir .ai/specs/alpha
}

test_spec_close_leftovers_handled_removes_the_spec_and_leaves_task_spec_lines_untouched() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf -- '- [ ] `T-1` — item\n' > .ai/specs/alpha/roadmap.md
  jig task new T-1 >/dev/null
  cat >> .ai/workspace/tasks/T-1/task.md <<'EOF'
Spec: .ai/specs/alpha/ — Phase 1
EOF
  cp .ai/workspace/tasks/T-1/task.md task.before
  local today dest
  today=$(date +%Y-%m-%d)
  dest=".ai/runtime/trash/$today/spec-alpha"

  run jig spec close alpha --leftovers-handled
  assert_eq 0 "$RC"
  assert_contains "$OUT" "removed: .ai/specs/alpha -> $dest"
  assert_contains "$OUT" "commit the removal together with the change that finished the spec"
  assert_no_file .ai/specs/alpha
  assert_dir "$dest"
  assert_file "$dest/roadmap.md"
  cmp -s .ai/workspace/tasks/T-1/task.md task.before \
    || fail "spec close touched the task's Spec: line"
}

test_spec_close_without_leftovers_succeeds_without_the_flag() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha
  printf '# Alpha\n' > .ai/specs/alpha/spec.md
  printf -- '- [x] `T-1` — done already\n' > .ai/specs/alpha/roadmap.md

  run jig spec close alpha
  assert_eq 0 "$RC"
  assert_no_file .ai/specs/alpha
}

# An empty spec directory (neither file present) has nothing to lose either:
# spec_leftovers tolerates both files missing, and there is no roadmap to
# read an Epic: line from.
test_spec_close_succeeds_on_an_empty_spec_directory() {
  fixture_jig_repo
  mkdir -p .ai/specs/alpha

  run jig spec close alpha
  assert_eq 0 "$RC"
  assert_no_file .ai/specs/alpha
}

# --- spec epic (ADR-0040) ------------------------------------------------------
# The epic branch a spec released once, at the end, is released from. Every
# scenario needs a clean tree (git checkout/branch refuse a dirty one), so the
# setup mirrors task.t.sh's task_setup_clean: commit everything `jig init`
# left untracked before doing any git plumbing of our own.

epic_setup() {
  fixture_jig_repo
  git add -A
  git commit -q -m "jig init snapshot"
}

# epic_ready_to_finish <id> — a spec with an open epic, created and checked
# out, ready for `--finish`: the roadmap's Epic: line has reached main and the
# branch exists locally, exactly what `spec epic <id>` twice in a row builds.
epic_ready_to_finish() {
  local id="$1"
  epic_setup
  jig spec new "$id" >/dev/null
  git add -A
  git commit -q -m "add spec $id"
  jig spec epic "$id" >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic "$id" >/dev/null
  git checkout -q "epic/$id"
}

# --- spec epic: argument handling ----------------------------------------------

test_spec_epic_missing_id_fails() {
  fixture_jig_repo
  run jig spec epic
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: missing spec id"
}

test_spec_epic_invalid_id_fails() {
  fixture_jig_repo
  run jig spec epic "-bad"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: invalid spec id: -bad"
}

test_spec_epic_invalid_id_checked_before_init() {
  fixture_repo
  run jig spec epic "-bad"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid spec id"
  assert_not_contains "$OUT" "not initialised"
}

test_spec_epic_requires_initialised_project() {
  fixture_repo
  run jig spec epic idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

test_spec_epic_unknown_spec_fails() {
  fixture_jig_repo
  run jig spec epic no-such-spec
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no such spec, or it has no roadmap: .ai/specs/no-such-spec/roadmap.md"
}

test_spec_epic_rejects_unexpected_argument() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x --wat
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unexpected argument: --wat"
}

test_spec_epic_finish_and_reopen_exclude_each_other() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x --finish --reopen
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--finish and --reopen exclude each other"

  run jig spec epic idea-x --reopen --finish
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--finish and --reopen exclude each other"
}

test_spec_epic_two_conflicting_epic_lines_fails() {
  epic_setup
  jig spec new idea-x >/dev/null
  printf 'Epic: epic/a\nEpic: epic/b\n' >> .ai/specs/idea-x/roadmap.md
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "declares more than one epic; keep one Epic: line"
}

# --- spec epic: declare --------------------------------------------------------

test_spec_epic_declares_the_line_and_stops() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/specs/idea-x/roadmap.md: Epic: epic/idea-x"
  assert_contains "$OUT" "commit .ai/specs/idea-x/roadmap.md and merge it into main"
  assert_contains "$OUT" 'run `jig spec epic idea-x` again to cut epic/idea-x'
  grep -qx 'Epic: epic/idea-x' .ai/specs/idea-x/roadmap.md \
    || fail "Epic: line missing from the roadmap"
  # Right after Destination:, with a blank line between them.
  awk '/^Destination:/{getline a; getline b; if (a == "" && b == "Epic: epic/idea-x") found=1} END{exit !found}' \
    .ai/specs/idea-x/roadmap.md || fail "Epic: line not placed after Destination: with a blank line"
  # The branch is not cut yet: the line has to reach main first.
  if git rev-parse --verify --quiet epic/idea-x >/dev/null; then
    fail "branch created before the Epic: line reached main"
  fi
}

test_spec_epic_declare_puts_the_line_after_a_wrapped_destination() {
  # A destination sentence wraps over several lines; the Epic: line must not
  # land inside it (found declaring knowledge-adoption's epic, 2026-09-16).
  epic_setup
  jig spec new idea-x >/dev/null
  printf '# Roadmap\n\nDestination: one sentence\nthat wraps\nover three lines.\n\n## Phase 1\n' \
    > .ai/specs/idea-x/roadmap.md
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_eq "$(printf '# Roadmap\n\nDestination: one sentence\nthat wraps\nover three lines.\n\nEpic: epic/idea-x\n\n## Phase 1')" \
    "$(cat .ai/specs/idea-x/roadmap.md)"
}

test_spec_epic_declare_after_a_destination_that_ends_the_file() {
  epic_setup
  jig spec new idea-x >/dev/null
  printf '# Roadmap\n\nDestination: the last\nparagraph.\n' > .ai/specs/idea-x/roadmap.md
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_eq "$(printf '# Roadmap\n\nDestination: the last\nparagraph.\n\nEpic: epic/idea-x')" \
    "$(cat .ai/specs/idea-x/roadmap.md)"
}

test_spec_epic_roadmap_without_destination_dies() {
  epic_setup
  mkdir -p .ai/specs/bare
  printf '# Bare\n' > .ai/specs/bare/spec.md
  printf 'Nothing here.\n' > .ai/specs/bare/roadmap.md
  git add -A
  git commit -q -m "add bare spec"

  run jig spec epic bare
  assert_eq 1 "$RC"
  assert_contains "$OUT" "has no Destination: line to put the Epic: line after"
  assert_not_contains "$(cat .ai/specs/bare/roadmap.md)" "Epic:"
}

test_spec_epic_refuses_before_the_line_reaches_main() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  # Declares the line in the working copy only — deliberately left uncommitted.
  jig spec epic idea-x >/dev/null

  run jig spec epic idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the Epic: line of .ai/specs/idea-x/roadmap.md is not on main yet; merge it into main first"
}

test_spec_epic_creates_branch_on_freshest_main_without_checkout() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  local sha
  sha=$(git rev-parse main)

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" "created: epic/idea-x at $sha"
  assert_contains "$OUT" 'push it with `git push -u origin epic/idea-x`'
  assert_eq "$sha" "$(git rev-parse epic/idea-x)"
  # No checkout: still on main.
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_spec_epic_repeat_after_creation_says_exists() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_eq "exists: epic/idea-x" "$OUT"
}

test_spec_epic_exists_only_on_origin_is_found_via_fetch() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null

  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git push -q origin main epic/idea-x
  git branch -D epic/idea-x

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_eq "exists: epic/idea-x" "$OUT"
}

# `--finish` removes the spec now; there is no command left that writes a
# legacy "— finished" line. Simulated by editing the roadmap directly, the
# way an older jig (or a hand edit) would have left it.
epic_legacy_finish_line() {
  local id="$1" branch="$2"
  sed "s|^Epic: $branch\$|Epic: $branch — finished|" ".ai/specs/$id/roadmap.md" > roadmap.tmp
  mv roadmap.tmp ".ai/specs/$id/roadmap.md"
}

test_spec_epic_declare_on_finished_epic_suggests_reopen() {
  epic_ready_to_finish idea-x
  epic_legacy_finish_line idea-x epic/idea-x
  git checkout -q main

  run jig spec epic idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: .ai/specs/idea-x/roadmap.md marks epic epic/idea-x finished, as an older jig did; a finished epic's spec is removed now — delete the spec, or drop \"— finished\" to reopen it"
}

# --- spec epic --finish --------------------------------------------------------

test_spec_epic_finish_no_epic_declared_dies() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x --finish
  assert_eq 1 "$RC"
  assert_contains "$OUT" "declares no epic"
}

test_spec_epic_finish_requires_being_on_the_epic_branch() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null

  run jig spec epic idea-x --finish
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--finish runs on epic/idea-x; switch to it first"
}

test_spec_epic_finish_requires_main_merged_in() {
  epic_ready_to_finish idea-x
  git checkout -q main
  printf 'new\n' > new.txt
  git add new.txt
  git commit -q -m "new work on main"
  git checkout -q epic/idea-x

  run jig spec epic idea-x --finish
  assert_eq 1 "$RC"
  assert_contains "$OUT" "epic/idea-x does not contain the latest main; merge main into it first"
}

# The template roadmap ships with unfinished items in both phases (leftovers,
# section 2 of the design); --finish now refuses instead of only warning,
# exactly like `spec close`.
test_spec_epic_finish_refuses_leftovers_without_flag() {
  epic_ready_to_finish idea-x

  run jig spec epic idea-x --finish
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: .ai/specs/idea-x still holds what knowledge does not (above); move each one to another spec or task, or drop it, then run again with --leftovers-handled"
  assert_contains "$OUT" "  item: \`<task-id>\`"
  assert_contains "$OUT" "  item: fog:"
  assert_dir .ai/specs/idea-x
}

test_spec_epic_finish_with_leftovers_handled_removes_the_spec_directory() {
  epic_ready_to_finish idea-x
  local today dest
  today=$(date +%Y-%m-%d)
  dest=".ai/runtime/trash/$today/spec-idea-x"

  run jig spec epic idea-x --finish --leftovers-handled
  assert_eq 0 "$RC"
  assert_contains "$OUT" "removed: .ai/specs/idea-x -> $dest"
  assert_contains "$OUT" "commit the removal with the version bump, then open the pull request from epic/idea-x into main"
  assert_no_file .ai/specs/idea-x
  assert_dir "$dest"
  assert_file "$dest/roadmap.md"
}

# A legacy "— finished" line (section 4 of the design): --finish still
# refuses it, pointing at dropping the line rather than at --reopen (which
# only restores a spec that this jig's own --finish removed).
test_spec_epic_finish_legacy_finished_line_dies() {
  epic_ready_to_finish idea-x
  epic_legacy_finish_line idea-x epic/idea-x

  run jig spec epic idea-x --finish
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'spec epic: .ai/specs/idea-x/roadmap.md marks epic epic/idea-x finished, as an older jig did; drop "— finished" from the line, then run --finish again'
  assert_dir .ai/specs/idea-x
}

test_spec_epic_finish_leftovers_handled_without_finish_dies() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"

  run jig spec epic idea-x --leftovers-handled
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: --leftovers-handled goes with --finish"
  assert_no_file .ai/runtime/trash
}

# --- spec epic --reopen --------------------------------------------------------

# --reopen restores from git, never rewrites a line in place: the spec is
# gone from the working tree after --finish, so it has to be re-created.

test_spec_epic_reopen_restores_from_head_when_removal_is_uncommitted() {
  epic_ready_to_finish idea-x
  jig spec epic idea-x --finish --leftovers-handled >/dev/null 2>&1
  local sha
  sha=$(git rev-parse --short HEAD)

  run jig spec epic idea-x --reopen
  assert_eq 0 "$RC"
  assert_contains "$OUT" "restored: .ai/specs/idea-x from $sha"
  assert_contains "$OUT" "fix it with ordinary tasks, then run \`jig spec epic idea-x --finish\` again"
  assert_file .ai/specs/idea-x/roadmap.md
  assert_file .ai/specs/idea-x/spec.md
  grep -qx 'Epic: epic/idea-x' .ai/specs/idea-x/roadmap.md \
    || fail "restored roadmap lost its open Epic: line"
  git diff --cached --quiet || fail "reopen staged something; the index must stay untouched"
}

# A committed removal, with an unrelated commit landing on the epic
# afterwards: the deletion commit found by --diff-filter=D must still be the
# one that removed the spec, not the later unrelated one.
test_spec_epic_reopen_restores_from_history_after_a_later_unrelated_commit() {
  epic_ready_to_finish idea-x
  jig spec epic idea-x --finish --leftovers-handled >/dev/null 2>&1
  git add -A
  git commit -q -m "finish epic idea-x"
  local del_sha
  del_sha=$(git rev-parse HEAD)
  printf 'unrelated\n' > unrelated.txt
  git add unrelated.txt
  git commit -q -m "unrelated work on the epic"

  run jig spec epic idea-x --reopen
  assert_eq 0 "$RC"
  assert_contains "$OUT" "restored: .ai/specs/idea-x from $(git rev-parse --short "$del_sha^")"
  assert_file .ai/specs/idea-x/roadmap.md
  grep -qx 'Epic: epic/idea-x' .ai/specs/idea-x/roadmap.md \
    || fail "restored roadmap lost its open Epic: line"
  git diff --cached --quiet || fail "reopen staged something; the index must stay untouched"
}

test_spec_epic_reopen_refuses_when_the_spec_is_present() {
  epic_ready_to_finish idea-x

  run jig spec epic idea-x --reopen
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: .ai/specs/idea-x is here; --reopen restores a spec that --finish removed"
}

test_spec_epic_reopen_requires_being_on_the_epic() {
  epic_ready_to_finish idea-x
  jig spec epic idea-x --finish --leftovers-handled >/dev/null 2>&1
  git add -A
  git commit -q -m "finish epic idea-x"
  git checkout -q -b other-branch

  run jig spec epic idea-x --reopen
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: --reopen runs on epic/idea-x; switch to it first"
}

test_spec_epic_reopen_no_removed_spec_in_history_dies() {
  epic_setup

  run jig spec epic never-existed --reopen
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec epic: no removed spec never-existed in the history of this branch"
}

# --- spec list: epic states (ADR-0040) -----------------------------------------

test_spec_list_on_the_epic_shows_progress_with_suffix() {
  epic_ready_to_finish idea-x

  run jig spec list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "(on epic/idea-x)"
}

test_spec_list_off_the_epic_says_progress_is_on_the_epic() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null
  # Stays on main: the branch exists, but progress is read on the epic.

  run jig spec list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "epic/idea-x — progress is on the epic"
}

test_spec_list_epic_branch_missing() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  # The Epic: line has reached main, but the branch itself was never cut.

  run jig spec list
  assert_eq 0 "$RC"
  assert_contains "$OUT" "epic/idea-x — branch missing"
}

test_spec_list_after_epic_finish_no_longer_lists_the_spec() {
  epic_ready_to_finish idea-x
  jig spec epic idea-x --finish --leftovers-handled >/dev/null 2>&1
  # Still on the epic branch: --finish removed the spec directory outright,
  # so there is nothing left for `spec list` to report at all.

  run jig spec list
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

# --- spec_phase_counts / spec_phase_rows (schemas/spec.md) --------------------
#
# The roadmap counted by section: a `## Phase <n> — <title>` heading opens a
# phase, listed even with no items; every other `##` section, and anything
# before the first heading, is counted under `-` and listed only when it has
# items. `spec_progress` is their sum, so `jig spec list`'s total cannot
# disagree with the per-phase breakdown the status page shows.

# spec_phase_counts_of <roadmap.md> — call spec_phase_counts directly, the
# same way housekeeping.t.sh's hk_decide calls a pure function: source the
# libraries in a subshell and let its own stdout/exit code answer.
spec_phase_counts_of() {
  bash -c '
    set -eu
    JIG_LIB="$JIG_HOME/scripts/lib"
    . "$JIG_LIB/version.sh"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    . "$JIG_LIB/spec.sh"
    spec_phase_counts "$1"
  ' _ "$1"
}

# spec_mixed_roadmap <file> — a roadmap with a preamble item, a non-phase
# "## Waves" section (plus a numbered list, never counted) and two phases.
spec_mixed_roadmap() {
  {
    printf -- '- [ ] `T-0` - preamble filed item\n'
    printf -- '- [ ] plain preamble item\n'
    printf '\n'
    printf '## Waves\n'
    printf '1. Wave one\n'
    printf '2. Wave two\n'
    printf '\n'
    printf -- '- [ ] `T-9` - waves section filed item\n'
    printf -- '- [x] waves done item\n'
    printf '\n'
    printf '## Phase 1 — Design\n'
    printf -- '- [x] `T-1` - phase1 done task\n'
    printf -- '- [ ] fog: uncertain direction\n'
    printf '\n'
    printf '## Phase 2 — Build\n'
    printf -- '- [ ] `T-2` - phase2 filed task\n'
    printf -- '- [x] plain phase2 done item\n'
  } > "$1"
}

test_spec_phase_counts_mixed_preamble_waves_and_phases() {
  mkdir -p roadmap-fixture
  spec_mixed_roadmap roadmap-fixture/roadmap.md

  local tab out expected
  tab=$(printf '\t')
  out=$(spec_phase_counts_of roadmap-fixture/roadmap.md)
  expected="-${tab}-${tab}0${tab}2${tab}1${tab}0
-${tab}Waves${tab}1${tab}2${tab}1${tab}0
1${tab}Design${tab}1${tab}2${tab}0${tab}1
2${tab}Build${tab}1${tab}2${tab}1${tab}0"

  assert_eq "$expected" "$out"
}

test_spec_list_output_unchanged_for_a_roadmap_mixing_phases_and_non_phase_sections() {
  fixture_jig_repo
  mkdir -p .ai/specs/mixed
  {
    printf '# Mixed Sections\n'
    printf '\n'
    printf 'Body text.\n'
  } > .ai/specs/mixed/spec.md
  spec_mixed_roadmap .ai/specs/mixed/roadmap.md

  run jig spec list
  assert_eq 0 "$RC"
  # The sum across every section: done=0+1+1+1=3, total=2+2+2+2=8,
  # filed=1+1+0+1=3, fog=0+0+1+0=1 -- unchanged from before spec_phase_counts
  # split the roadmap into per-section rows.
  assert_eq "mixed   Mixed Sections   roadmap 3/8 done, 3 filed, fog 1" "$OUT"
}

# --- the live status page (jig_status_page_touch, common.sh) ------------------

test_spec_status_page_new_spec_appears_on_the_page() {
  fixture_jig_repo
  jig status --html >/dev/null
  jig spec new my-idea >/dev/null
  assert_file_contains .ai/runtime/status.html "<code>my-idea</code>"
}

# --- spec plan (a phase run's waves) --------------------------------------------
# Which tasks of a phase may start: the waves are one numbered list over the
# whole roadmap, and wave N opens only once every item of every earlier wave
# has merged. Merged comes from what is already answered — a checked item, a
# closed task, the newest housekeeping run — never from a network call.

# plan_spec <id> — a spec whose roadmap is read from stdin.
plan_spec() {
  mkdir -p ".ai/specs/$1"
  printf '# %s\n' "$1" > ".ai/specs/$1/spec.md"
  cat > ".ai/specs/$1/roadmap.md"
}

# plan_roadmap — two phases, four waves: a checked item, a filed task, an
# unfiled item, fog, an item a later phase shares a wave with, and one item in
# no wave at all.
plan_roadmap() {
  cat <<'RM'
# Roadmap — Plan

Destination: things happen.

## Phase 1 — First

- [x] `T-done` — Shipped thing — already merged
- [ ] `T-a` — Alpha work — goal
- [ ] Beta work — not filed yet (after: `T-a` — needs it)
- [ ] fog: Gamma area — unclear

## Phase 2 — Second

- [ ] `T-c` — Charlie — goal
- [ ] Delta — goal
- [ ] Echo — goal, in no wave

## Waves

1. Shipped thing; `T-a`; beta WORK
2. Gamma area; Charlie
3. Delta
RM
}

test_spec_plan_argument_errors() {
  fixture_jig_repo
  plan_roadmap | plan_spec alpha

  run jig spec plan
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: missing spec id"
  run jig spec plan alpha
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: missing --phase <n>"
  run jig spec plan alpha --phase
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: --phase requires a value"
  run jig spec plan alpha --phase one
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: --phase takes a phase number: one"
  run jig spec plan alpha --phase 1 --format json
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: --format is text or tsv: json"
  run jig spec plan alpha --phase 1 --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: unknown argument: --bogus"
  run jig spec plan alpha beta --phase 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: unexpected argument: beta"
  run jig spec plan -- --phase 1
  assert_eq 1 "$RC"
  run jig spec plan .bad --phase 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: invalid spec id: .bad"
  run jig spec plan nope --phase 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: no such spec, or it has no roadmap: .ai/specs/nope/roadmap.md"
  run jig spec plan alpha --phase 7
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: .ai/specs/alpha/roadmap.md has no Phase 7"
}

test_spec_plan_refuses_a_roadmap_without_waves() {
  fixture_jig_repo
  printf '%s\n' '## Phase 1 — Only' '' '- [ ] `T-a` — Alpha — goal' | plan_spec alpha
  run jig spec plan alpha --phase 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'spec plan: .ai/specs/alpha/roadmap.md has no `## Waves` list'
}

test_spec_plan_first_wave_open_later_phase_waits_on_it() {
  fixture_jig_repo
  plan_roadmap | plan_spec alpha
  jig task new T-a >/dev/null

  local tab
  tab=$(printf '\t')
  run jig spec plan alpha --phase 1 --format tsv
  assert_eq 0 "$RC"
  # Wave 1: the checked item is done, the filed task with a workspace that
  # was never started may start, the unfiled item has to be filed first. Fog
  # sits in wave 2, which waits on wave 1.
  assert_eq "wave${tab}1${tab}open
item${tab}1${tab}T-done${tab}done${tab}roadmap${tab}false${tab}-${tab}done${tab}Shipped thing
item${tab}1${tab}T-a${tab}not-started${tab}no${tab}false${tab}-${tab}start${tab}Alpha work
item${tab}1${tab}-${tab}not-filed${tab}no${tab}false${tab}-${tab}file${tab}Beta work
wave${tab}2${tab}waiting
item${tab}2${tab}-${tab}fog${tab}no${tab}false${tab}-${tab}wait${tab}Gamma area
blocker${tab}1${tab}T-a${tab}not-started${tab}Alpha work
blocker${tab}1${tab}-${tab}not-filed${tab}Beta work" "$OUT"

  # Phase 2 is spread over waves 2 and 3, and one of its items is in no wave:
  # it is listed, and it never starts.
  run jig spec plan alpha --phase 2 --format tsv
  assert_eq 0 "$RC"
  assert_eq "wave${tab}2${tab}waiting
item${tab}2${tab}T-c${tab}no-workspace${tab}no${tab}false${tab}-${tab}wait${tab}Charlie
wave${tab}3${tab}waiting
item${tab}3${tab}-${tab}not-filed${tab}no${tab}false${tab}-${tab}wait${tab}Delta
item${tab}-${tab}-${tab}not-filed${tab}no${tab}false${tab}-${tab}unscheduled${tab}Echo
blocker${tab}1${tab}T-a${tab}not-started${tab}Alpha work
blocker${tab}1${tab}-${tab}not-filed${tab}Beta work" "$OUT"
}

test_spec_plan_text_form_names_what_may_start_and_what_to_file() {
  fixture_jig_repo
  plan_roadmap | plan_spec alpha
  jig task new T-a >/dev/null

  run jig spec plan alpha --phase 1
  assert_eq 0 "$RC"
  assert_eq "Phase 1 — First
roadmap: .ai/specs/alpha/roadmap.md
wave 1 — open
  T-done  done         done   Shipped thing
  T-a     not started  start  Alpha work
  -       not filed    file   Beta work
wave 2 — waiting
  -       fog          wait   Gamma area
waiting on earlier waves:
  wave 1  T-a  not started  Alpha work
  wave 1  -    not filed    Beta work
may start now: T-a
to file first: Beta work" "$OUT"
}

# Every way this checkout already knows a task merged opens the next wave:
# its item checked, its task closed (ADR-0030 closes only after landing), or
# the newest housekeeping run reporting remote=merged — an older run is not
# read.
test_spec_plan_merged_from_roadmap_closed_task_and_newest_housekeeping_run() {
  fixture_jig_repo
  plan_spec alpha <<'RM'
## Phase 1 — First

- [ ] `T-a` — Alpha — goal
- [ ] `T-b` — Bravo — goal
- [ ] `T-c` — Charlie — goal
- [ ] `T-d` — Delta — goal

## Waves

1. Alpha; Bravo; Charlie
2. Delta
RM
  local t
  for t in T-a T-b T-c T-d; do jig task new "$t" >/dev/null; done
  jig task set T-a status ready >/dev/null
  jig task set T-a knowledge_consolidated true >/dev/null
  jig task set T-a status consolidated >/dev/null
  jig task set T-b status ready >/dev/null
  mkdir -p .ai/runtime
  {
    printf -- '--- run 2026-09-20T10:00:00Z forge=none\n'
    printf '2026-09-20T10:00:01Z task=T-c status=active remote=merged via=ancestry action=preserve\n'
    printf -- '--- run 2026-09-21T10:00:00Z forge=none\n'
    printf '2026-09-21T10:00:01Z task=T-b status=ready remote=merged via=ancestry action=preserve flags=needs-consolidation\n'
    printf '2026-09-21T10:00:01Z task=T-c status=active remote=unknown via=ancestry action=preserve\n'
  } > .ai/runtime/housekeeping.log

  local tab
  tab=$(printf '\t')
  run jig spec plan alpha --phase 1 --format tsv
  assert_eq 0 "$RC"
  assert_contains "$OUT" "item${tab}1${tab}T-a${tab}consolidated${tab}closed${tab}false${tab}-${tab}done${tab}Alpha"
  assert_contains "$OUT" "item${tab}1${tab}T-b${tab}ready${tab}housekeeping${tab}false${tab}-${tab}done${tab}Bravo"
  # T-c merged only in an older run: not merged, so wave 2 waits on it.
  assert_contains "$OUT" "item${tab}1${tab}T-c${tab}not-started${tab}no${tab}false${tab}-${tab}start${tab}Charlie"
  assert_contains "$OUT" "wave${tab}2${tab}waiting"
  assert_contains "$OUT" "blocker${tab}1${tab}T-c${tab}not-started${tab}Charlie"

  # Once T-c's item is checked, wave 2 opens.
  sed 's/^- \[ \] `T-c`/- [x] `T-c`/' .ai/specs/alpha/roadmap.md > roadmap.tmp
  mv roadmap.tmp .ai/specs/alpha/roadmap.md
  run jig spec plan alpha --phase 1 --format tsv
  assert_eq 0 "$RC"
  assert_contains "$OUT" "wave${tab}1${tab}merged"
  assert_contains "$OUT" "wave${tab}2${tab}open"
  assert_contains "$OUT" "item${tab}2${tab}T-d${tab}not-started${tab}no${tab}false${tab}-${tab}start${tab}Delta"
  assert_not_contains "$OUT" "blocker"
}

test_spec_plan_reports_running_paused_autopilot_and_abandoned_tasks() {
  epic_setup
  plan_spec alpha <<'RM'
## Phase 1 — First

- [ ] `T-a` — Alpha — goal
- [ ] `T-b` — Bravo — goal
- [ ] `T-c` — Charlie — goal

## Waves

1. Alpha; Bravo; Charlie
RM
  git add -A
  git commit -q -m "spec"
  jig task new T-a >/dev/null
  jig task start T-a >/dev/null
  git checkout -q main
  jig task new T-b >/dev/null
  jig task start T-b >/dev/null
  git checkout -q main
  jig task pause T-b >/dev/null
  jig task autopilot T-b start >/dev/null
  jig task new T-c >/dev/null
  jig task abandon T-c >/dev/null

  local tab
  tab=$(printf '\t')
  run jig spec plan alpha --phase 1 --format tsv
  assert_eq 0 "$RC"
  assert_contains "$OUT" "item${tab}1${tab}T-a${tab}active${tab}no${tab}false${tab}-${tab}running${tab}Alpha"
  assert_contains "$OUT" "item${tab}1${tab}T-b${tab}active${tab}no${tab}true${tab}on${tab}running${tab}Bravo"
  assert_contains "$OUT" "item${tab}1${tab}T-c${tab}abandoned${tab}no${tab}false${tab}-${tab}abandoned${tab}Charlie"

  run jig spec plan alpha --phase 1
  assert_contains "$OUT" "active, paused, autopilot on"
}

# A wave entry names an item by its title — ignoring case, backticks and
# runs of spaces — or by its task id. What names nothing, several items, or an
# item another entry names too is reported, never guessed; a wave with such
# an entry is never merged, so it holds every wave after it.
test_spec_plan_reports_unmatched_ambiguous_and_repeated_entries() {
  fixture_jig_repo
  plan_spec alpha <<'RM'
## Phase 1 — First

- [x] Twin — one
- [x] Twin — two
- [x] `T-r` — Repeated — goal
- [ ] `T-z` — Zulu — wrapped
  onto a second line

## Phase 2 — Second

- [ ] `T-l` — Later — goal

## Waves

1. twin; Nothing like it; Repeated
2. `T-r`; T-z
3. Later
RM
  local tab
  tab=$(printf '\t')
  run jig spec plan alpha --phase 2 --format tsv
  assert_eq 0 "$RC"
  assert_eq "wave${tab}3${tab}waiting
item${tab}3${tab}T-l${tab}no-workspace${tab}no${tab}false${tab}-${tab}wait${tab}Later
blocker${tab}2${tab}T-z${tab}no-workspace${tab}Zulu
problem${tab}1${tab}ambiguous${tab}twin
problem${tab}1${tab}unmatched${tab}Nothing like it
problem${tab}1${tab}repeated${tab}Repeated
problem${tab}2${tab}repeated${tab}\`T-r\`" "$OUT"

  run jig spec plan alpha --phase 1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "not in any wave:"
  assert_contains "$OUT" 'problem: wave 1 entry "twin" names more than one roadmap item'
  assert_contains "$OUT" 'problem: wave 1 entry "Nothing like it" names no roadmap item'
  assert_contains "$OUT" 'problem: wave 2 entry "`T-r`" names an item another wave entry names too'
}

# Off the epic, the roadmap is the epic's — progress is made there
# (ADR-0040) — read from its ref without a fetch, and the output names it.
test_spec_plan_reads_an_open_epic_roadmap_from_its_branch() {
  epic_setup
  jig spec new idea-x >/dev/null
  git add -A
  git commit -q -m "add spec idea-x"
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null
  git checkout -q epic/idea-x
  printf '%s\n' '## Phase 1 — On the epic' '' '- [ ] `T-e` — Epic item — goal' '' '## Waves' '' '1. Epic item' \
    >> .ai/specs/idea-x/roadmap.md
  git add -A
  git commit -q -m "progress on the epic"
  git checkout -q main

  run jig spec plan idea-x --phase 1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "roadmap: epic/idea-x"
  assert_contains "$OUT" "Epic item"

  # On the epic, its own copy is read.
  git checkout -q epic/idea-x
  run jig spec plan idea-x --phase 1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "roadmap: .ai/specs/idea-x/roadmap.md"
}

test_spec_plan_epic_without_a_branch_here_fails() {
  fixture_jig_repo
  printf '%s\n' 'Destination: x.' '' 'Epic: epic/gone' '' '## Phase 1 — A' '' '## Waves' | plan_spec alpha
  run jig spec plan alpha --phase 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: alpha is built on epic/gone, which this checkout has no branch of; fetch it first"
}

test_spec_plan_epic_with_a_name_git_rejects_fails_naming_it() {
  fixture_jig_repo
  printf '%s\n' 'Destination: x.' '' 'Epic: bad..branch' '' '## Phase 1 — A' '' '## Waves' | plan_spec alpha
  run jig spec plan alpha --phase 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec plan: git rejects the epic branch name bad..branch in .ai/specs/alpha/roadmap.md"
}

test_spec_plan_is_read_only() {
  fixture_jig_repo
  plan_roadmap | plan_spec alpha
  jig task new T-a >/dev/null
  local before after
  before=$(cat .ai/specs/alpha/roadmap.md .ai/workspace/tasks/T-a/state)
  jig spec plan alpha --phase 1 >/dev/null
  jig spec plan alpha --phase 1 --format tsv >/dev/null
  after=$(cat .ai/specs/alpha/roadmap.md .ai/workspace/tasks/T-a/state)
  assert_eq "$before" "$after"
}

# --- spec ship (adr-20260922-spec-work-ships-by-the-agent-git-level) -----------

# sship_cfg_local <key> <value> — set a key in .ai/config.local.yaml, where
# agent.git is read from (ADR-0038). Mirrors task.t.sh's ship_cfg_local;
# duplicated because each test file sources only itself.
sship_cfg_local() {
  local file=".ai/config.local.yaml"
  touch "$file"
  if grep -q "^$1:" "$file"; then
    sed "s|^$1:.*|$1: $2|" "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  else
    printf '%s: %s\n' "$1" "$2" >> "$file"
  fi
}

# sship_cfg <key> <value> — rewrite one line of the project's config.yaml.
sship_cfg() {
  sed "s|^$1:.*|$1: $2|" .ai/config.yaml > .ai/config.yaml.tmp
  mv .ai/config.yaml.tmp .ai/config.yaml
}

# sship_origin — a bare `origin` holding every branch this repository has now.
sship_origin() {
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git fetch -q origin
}

# sship_stub_gh <existing-url-or-empty> — a fake, authenticated `gh`: `pr list`
# prints <existing-url> or `null`, `pr create` records its arguments, one per
# line, in gh-create.argv and prints a made-up URL. As task.t.sh's ship_stub_gh.
sship_stub_gh() {
  local existing="${1:-}"
  mkdir -p stub-bin
  cat > stub-bin/gh <<STUB
#!/usr/bin/env bash
case "\$1" in
  auth) exit 0 ;;
  pr)
    shift
    case "\$1" in
      list) if [ -n "$existing" ]; then printf '%s\n' "$existing"; else printf 'null\n'; fi ;;
      create) shift; printf '%s\n' "\$@" > gh-create.argv; printf 'https://github.com/example/example/pull/42\n' ;;
    esac
    ;;
esac
STUB
  chmod +x stub-bin/gh
  sship_cfg forge github
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# sship_declared <id> — a spec with its Epic: line written, not committed, and
# staged, on main: what `jig-idea` has at hand when it ships a declaration.
sship_declared() {
  epic_setup
  jig spec new "$1" >/dev/null
  jig spec epic "$1" >/dev/null
  git add ".ai/specs/$1"
  printf 'Declare %s\n\nThe spec and its epic.\n' "$1" > msg.txt
}

# sship_cut <id> — the Epic: line on main and on origin, the epic cut here and
# not pushed yet; checkout on main.
sship_cut() {
  epic_setup
  jig spec new "$1" >/dev/null
  jig spec epic "$1" >/dev/null
  git add -A
  git commit -q -m "declare epic"
  sship_origin
  jig spec epic "$1" >/dev/null 2>&1
}

# sship_finished <id> — on the epic, pushed, with the spec removed by
# `--finish`, the removal and a version bump staged.
sship_finished() {
  epic_ready_to_finish "$1"
  sship_origin
  jig spec epic "$1" --finish --leftovers-handled >/dev/null 2>&1
  printf '1.0.0\n' > VERSION
  git add -A ".ai/specs/$1" VERSION
  printf 'Release %s\n\nThe epic, finished.\n' "$1" > msg.txt
}

test_spec_ship_none_level_exits_3_and_changes_nothing() {
  sship_declared idea-x

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 3 "$RC"
  assert_contains "$OUT" "spec ship: agent.git is none in this clone"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
  assert_contains "$(git status --porcelain -- .ai/specs/idea-x)" "A  .ai/specs/idea-x/roadmap.md"
}

test_spec_ship_ignores_agent_git_in_the_project_config() {
  sship_declared idea-x
  printf 'agent.git: pr\n' >> .ai/config.yaml

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 3 "$RC"
}

test_spec_ship_invalid_agent_git_dies() {
  sship_declared idea-x
  sship_cfg_local agent.git yolo

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec ship: invalid agent.git: yolo (expected none|commit|push|pr)"
}

test_spec_ship_unknown_spec_dies() {
  epic_setup
  sship_cfg_local agent.git pr
  run jig spec ship nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no spec nope here, and none removed in the history of this branch"
}

test_spec_ship_declare_at_commit_switches_off_main_and_commits() {
  sship_declared idea-x
  sship_cfg_local agent.git commit
  local main_sha
  main_sha=$(git rev-parse main)

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "mode: declare"
  assert_contains "$OUT" "switched to spec/idea-x"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "stopped at commit: push is the human's"
  assert_eq "spec/idea-x" "$(git symbolic-ref --short HEAD)"
  assert_eq "$main_sha" "$(git rev-parse main)" "nothing may be committed to main"
  assert_eq "Declare idea-x" "$(git log -1 --format=%s)"
}

test_spec_ship_declare_requires_a_message_file() {
  sship_declared idea-x
  sship_cfg_local agent.git commit

  run jig spec ship idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "declaring commits; --message-file is required"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_spec_ship_declare_refuses_staged_paths_outside_the_spec() {
  sship_declared idea-x
  sship_cfg_local agent.git commit
  printf 'other\n' > other.txt
  git add other.txt

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "a declaration commits only .ai/specs/idea-x/; staged outside it:"
  assert_contains "$OUT" "other.txt"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_spec_ship_refuses_staged_workspace_paths() {
  sship_declared idea-x
  sship_cfg_local agent.git commit
  mkdir -p .ai/workspace/tasks/T-1
  printf 'x\n' > .ai/workspace/tasks/T-1/notes.md
  git add -f .ai/workspace/tasks/T-1/notes.md

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "staged changes under .ai/workspace/ or .ai/runtime/ are not shippable"
}

test_spec_ship_declare_refuses_when_its_branch_exists() {
  sship_declared idea-x
  sship_cfg_local agent.git commit
  git branch spec/idea-x

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec/idea-x exists already; switch to it and run again"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_spec_ship_declare_at_pr_pushes_and_opens_the_pr_into_main() {
  sship_declared idea-x
  sship_origin
  sship_stub_gh ""
  sship_cfg_local agent.git pr

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "mode: declare"
  assert_contains "$OUT" "pushed spec/idea-x"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/42"
  assert_contains "$OUT" 'once spec/idea-x is merged into main, run `jig spec epic idea-x` to cut epic/idea-x'
  git --git-dir=origin.git rev-parse --verify --quiet refs/heads/spec/idea-x >/dev/null \
    || fail "spec/idea-x was not pushed"
  local argv
  argv=$(cat gh-create.argv)
  assert_contains "$argv" "$(printf -- '--base\nmain')"
  assert_contains "$argv" "$(printf -- '--head\nspec/idea-x')"
  assert_contains "$argv" "$(printf -- '--title\nDeclare idea-x')"
}

test_spec_ship_epic_at_push_pushes_the_cut_epic() {
  sship_cut idea-x
  sship_cfg_local agent.git push

  run jig spec ship idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" "mode: epic"
  assert_contains "$OUT" "pushed epic/idea-x"
  assert_eq "$(git rev-parse epic/idea-x)" "$(git --git-dir=origin.git rev-parse refs/heads/epic/idea-x)"
  assert_eq "main" "$(git symbolic-ref --short HEAD)"
}

test_spec_ship_epic_at_commit_leaves_the_push_to_the_human() {
  sship_cut idea-x
  sship_cfg_local agent.git commit

  run jig spec ship idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" "stopped at commit: pushing epic/idea-x is the human's"
  if git --git-dir=origin.git rev-parse --verify --quiet refs/heads/epic/idea-x >/dev/null; then
    fail "epic/idea-x was pushed at agent.git: commit"
  fi
}

test_spec_ship_epic_refuses_what_is_staged() {
  sship_cut idea-x
  sship_cfg_local agent.git push
  printf 'x\n' > x.txt
  git add x.txt

  run jig spec ship idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "pushing epic/idea-x commits nothing, and something is staged"
}

test_spec_ship_epic_never_forces_a_push_origin_moved_past() {
  sship_cut idea-x
  sship_cfg_local agent.git push
  jig spec ship idea-x >/dev/null
  git clone -q origin.git other
  (cd other && git checkout -q epic/idea-x && printf 'theirs\n' > t.txt && git add t.txt \
    && git commit -q -m theirs && git push -q origin epic/idea-x)
  git checkout -q epic/idea-x
  printf 'ours\n' > o.txt
  git add o.txt
  git commit -q -m ours

  run jig spec ship idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "spec ship: git push failed"
}

test_spec_ship_final_at_pr_commits_pushes_and_opens_the_pr_into_main() {
  sship_finished idea-x
  sship_stub_gh ""
  sship_cfg_local agent.git pr

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "mode: final"
  assert_contains "$OUT" "committed "
  assert_contains "$OUT" "pushed epic/idea-x"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/42"
  assert_eq "" "$(git ls-files -- .ai/specs/idea-x)"
  local argv
  argv=$(cat gh-create.argv)
  assert_contains "$argv" "$(printf -- '--base\nmain')"
  assert_contains "$argv" "$(printf -- '--head\nepic/idea-x')"
  assert_contains "$argv" "$(printf -- '--title\nRelease idea-x')"
}

test_spec_ship_final_reports_an_open_pr_instead_of_a_second() {
  sship_finished idea-x
  sship_stub_gh "https://github.com/example/example/pull/7"
  sship_cfg_local agent.git pr

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr https://github.com/example/example/pull/7 (already open)"
  assert_no_file gh-create.argv
}

test_spec_ship_final_refuses_an_unstaged_removal() {
  sship_finished idea-x
  sship_cfg_local agent.git commit
  git reset -q -- .ai/specs/idea-x

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "the removal of .ai/specs/idea-x/ is not staged"
}

test_spec_ship_final_refuses_an_epic_without_the_latest_main() {
  sship_finished idea-x
  sship_cfg_local agent.git commit
  git stash -q
  git checkout -q main
  printf 'new\n' > new.txt
  git add new.txt
  git commit -q -m "new work on main"
  git checkout -q epic/idea-x
  git stash pop -q

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "epic/idea-x does not contain the latest main; merge main into it first"
}

test_spec_ship_final_runs_only_on_the_epic() {
  sship_finished idea-x
  sship_cfg_local agent.git commit
  git commit -q -m "finish"
  git checkout -q main
  git merge -q --no-ff -m "release" epic/idea-x

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "shipped from epic/idea-x — switch to it first"
}

# --- spec epic: the next step by agent.git -------------------------------------

test_spec_epic_declare_names_spec_ship_when_the_agent_commits() {
  epic_setup
  jig spec new idea-x >/dev/null
  sship_cfg_local agent.git pr

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'stage .ai/specs/idea-x/ and run `jig spec ship idea-x` (agent.git: pr — it commits, pushes and opens the pull request into main)'
  assert_not_contains "$OUT" "commit .ai/specs/idea-x/roadmap.md and merge it"
}

test_spec_epic_cut_names_spec_ship_when_the_agent_pushes() {
  epic_setup
  jig spec new idea-x >/dev/null
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  sship_cfg_local agent.git push

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'push it with `jig spec ship idea-x`'
}

test_spec_epic_cut_at_commit_leaves_the_push_to_the_human() {
  epic_setup
  jig spec new idea-x >/dev/null
  jig spec epic idea-x >/dev/null
  git add -A
  git commit -q -m "declare epic"
  sship_cfg_local agent.git commit

  run jig spec epic idea-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'push it with `git push -u origin epic/idea-x` — yours at agent.git: commit'
}

test_spec_epic_finish_names_spec_ship_and_what_stays_the_humans() {
  epic_ready_to_finish idea-x
  sship_cfg_local agent.git push

  run jig spec epic idea-x --finish --leftovers-handled
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'run `jig spec ship idea-x` (agent.git: push — it commits and pushes epic/idea-x; the pull request into main is yours)'
}

# --- the Release: line -----------------------------------------------------------

test_spec_epic_release_is_written_under_the_epic_line() {
  epic_setup
  jig spec new idea-x >/dev/null

  run jig spec epic idea-x --release minor
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/specs/idea-x/roadmap.md: Release: minor"
  awk '/^Epic: epic\/idea-x$/{getline r; if (r == "Release: minor") found=1} END{exit !found}' \
    .ai/specs/idea-x/roadmap.md || fail "Release: line not right under the Epic: line"
}

test_spec_epic_release_rejects_an_unknown_level() {
  epic_setup
  jig spec new idea-x >/dev/null

  run jig spec epic idea-x --release huge
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid release level: huge (expected patch|minor|major)"
  assert_not_contains "$(cat .ai/specs/idea-x/roadmap.md)" "Epic:"
}

test_spec_epic_release_only_when_declaring() {
  epic_setup
  jig spec new idea-x >/dev/null
  jig spec epic idea-x >/dev/null

  run jig spec epic idea-x --release major
  assert_eq 1 "$RC"
  assert_contains "$OUT" "declares epic/idea-x already; the release level is recorded when the epic is declared"

  run jig spec epic idea-x --finish --release major
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--release goes with declaring the epic"
}

test_spec_epic_refuses_an_invalid_release_line() {
  epic_setup
  jig spec new idea-x >/dev/null
  jig spec epic idea-x >/dev/null
  printf 'Release: minor, probably\n' >> .ai/specs/idea-x/roadmap.md

  run jig spec epic idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "records an invalid release level: minor, probably (expected Release: patch|minor|major)"
}

test_spec_epic_refuses_two_release_levels() {
  epic_setup
  jig spec new idea-x >/dev/null
  jig spec epic idea-x --release minor >/dev/null
  printf 'Release: major\n' >> .ai/specs/idea-x/roadmap.md

  run jig spec epic idea-x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "records more than one release level; keep one Release: line"
}

test_spec_epic_finish_reports_the_recorded_release() {
  epic_setup
  jig spec new idea-x >/dev/null
  jig spec epic idea-x --release minor >/dev/null
  git add -A
  git commit -q -m "declare epic"
  jig spec epic idea-x >/dev/null 2>&1
  git checkout -q epic/idea-x

  run jig spec epic idea-x --finish --leftovers-handled
  assert_eq 0 "$RC"
  assert_contains "$OUT" "release: minor"
}

test_spec_epic_finish_without_a_release_line_says_so() {
  epic_ready_to_finish idea-x

  run jig spec epic idea-x --finish --leftovers-handled
  assert_eq 0 "$RC"
  assert_contains "$OUT" "release: not recorded"
}

test_spec_ship_refuses_an_invalid_release_line() {
  sship_declared idea-x
  sship_cfg_local agent.git commit
  printf 'Release: soon\n' >> .ai/specs/idea-x/roadmap.md

  run jig spec ship idea-x --message-file msg.txt
  assert_eq 1 "$RC"
  assert_contains "$OUT" "records an invalid release level: soon"
}
