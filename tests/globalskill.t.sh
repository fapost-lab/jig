# Tests for scripts/lib/globalskill.sh: jig-pr-review placed for the person
# (adr-20261112-the-pr-review-skill-is-installed-per-user).
# shellcheck shell=bash
#
# Every test has its own $HOME (tests/run.sh); a fake framework source root
# holds the one skill, and ~/.claude or ~/.codex is made only where a test
# says the runtime is there.

# gs_source — a minimal framework source root with jig-pr-review in it.
gs_source() {
  local src="$HOME/fw"
  mkdir -p "$src/skills/jig-pr-review/references"
  printf 'skill v1\n' > "$src/skills/jig-pr-review/SKILL.md"
  printf 'draft\n' > "$src/skills/jig-pr-review/references/draft.md"
  printf '%s\n' "$src"
}

gs_place() {
  # shellcheck source=../scripts/lib/globalskill.sh
  ( . "$JIG_HOME/scripts/lib/globalskill.sh" && jig_global_skill_place "$1" 1.2.3 )
}

test_globalskill_places_nothing_without_a_runtime() {
  local src
  src=$(gs_source)
  run gs_place "$src"
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
  assert_no_file "$HOME/.claude"
  assert_no_file "$HOME/.agents"
}

test_globalskill_links_into_the_checkout_for_claude_and_codex() {
  skip_unless_symlinks
  local src
  src=$(gs_source)
  mkdir -p "$HOME/.claude" "$HOME/.codex"
  run gs_place "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pr-review skill: linked $HOME/.claude/skills/jig-pr-review"
  assert_contains "$OUT" "pr-review skill: linked $HOME/.agents/skills/jig-pr-review"
  assert_symlink "$HOME/.claude/skills/jig-pr-review"
  assert_symlink "$HOME/.agents/skills/jig-pr-review"
  assert_eq "skill v1" "$(cat "$HOME/.claude/skills/jig-pr-review/SKILL.md")"

  # A repeat run keeps the link and says so.
  run gs_place "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr-review skill: linked $HOME/.claude/skills/jig-pr-review"
}

test_globalskill_copies_with_a_marker_where_links_cannot_be_made() {
  local src lndir
  src=$(gs_source)
  mkdir -p "$HOME/.claude"
  lndir=$(stub_ln_copy_dir)
  # shellcheck disable=SC2016 # expanded by the inner bash
  run env PATH="$lndir:$PATH" bash -c '. "$JIG_HOME/scripts/lib/globalskill.sh" && jig_global_skill_place "$1" 1.2.3' _ "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pr-review skill: copied $HOME/.claude/skills/jig-pr-review (1.2.3)"
  [ -L "$HOME/.claude/skills/jig-pr-review" ] && fail "a copy was expected, not a link"
  assert_file "$HOME/.claude/skills/jig-pr-review/SKILL.md"
  assert_file "$HOME/.claude/skills/jig-pr-review/references/draft.md"
  assert_file_contains "$HOME/.claude/skills/jig-pr-review/.jig-global" "version: 1.2.3"

  # The next release refreshes its own copy.
  printf 'skill v2\n' > "$src/skills/jig-pr-review/SKILL.md"
  # shellcheck disable=SC2016 # expanded by the inner bash
  run env PATH="$lndir:$PATH" bash -c '. "$JIG_HOME/scripts/lib/globalskill.sh" && jig_global_skill_place "$1" 1.3.0' _ "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_eq "skill v2" "$(cat "$HOME/.claude/skills/jig-pr-review/SKILL.md")"
  assert_file_contains "$HOME/.claude/skills/jig-pr-review/.jig-global" "version: 1.3.0"
}

test_globalskill_leaves_a_skill_of_the_persons_own_alone() {
  local src
  src=$(gs_source)
  mkdir -p "$HOME/.claude/skills/jig-pr-review"
  printf 'mine\n' > "$HOME/.claude/skills/jig-pr-review/SKILL.md"
  run gs_place "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "pr-review skill: left alone $HOME/.claude/skills/jig-pr-review (not installed by Jig)"
  assert_eq "mine" "$(cat "$HOME/.claude/skills/jig-pr-review/SKILL.md")"
}

test_globalskill_leaves_a_link_elsewhere_alone() {
  skip_unless_symlinks
  local src
  src=$(gs_source)
  mkdir -p "$HOME/.claude/skills" "$HOME/other"
  ln -s "$HOME/other" "$HOME/.claude/skills/jig-pr-review"
  run gs_place "$src"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "left alone $HOME/.claude/skills/jig-pr-review"
  assert_eq "$HOME/other" "$(readlink "$HOME/.claude/skills/jig-pr-review")"
}

test_globalskill_installed_names_only_jigs_own_copy() {
  skip_unless_symlinks
  local src
  src=$(gs_source)
  mkdir -p "$HOME/.claude"
  # shellcheck disable=SC2016 # expanded by the inner bash
  run bash -c '. "$JIG_HOME/scripts/lib/globalskill.sh" && jig_global_skill_installed "$1"' _ "$src"
  assert_eq 1 "$RC" "nothing placed yet"
  gs_place "$src" >/dev/null
  # shellcheck disable=SC2016 # expanded by the inner bash
  run bash -c '. "$JIG_HOME/scripts/lib/globalskill.sh" && jig_global_skill_installed "$1"' _ "$src"
  assert_eq 0 "$RC"
  assert_eq "$HOME/.claude/skills/jig-pr-review" "$OUT"
}

# Removing the skill is how a person turns it off: the record Jig left beside
# it outlives it, and no later run puts the skill back until the record goes
# too. Each runtime is its own choice.
test_globalskill_a_skill_the_person_removed_stays_removed() {
  skip_unless_symlinks
  local src
  src=$(gs_source)
  mkdir -p "$HOME/.claude" "$HOME/.codex"
  gs_place "$src" >/dev/null
  assert_file "$HOME/.claude/skills/.jig-pr-review.placed"
  assert_file "$HOME/.agents/skills/.jig-pr-review.placed"

  rm "$HOME/.claude/skills/jig-pr-review"
  run gs_place "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pr-review skill: removed by you, left out $HOME/.claude/skills/jig-pr-review (delete $HOME/.claude/skills/.jig-pr-review.placed to have it placed again)"
  assert_no_file "$HOME/.claude/skills/jig-pr-review"
  assert_contains "$OUT" "pr-review skill: linked $HOME/.agents/skills/jig-pr-review"

  # Deleting the record too asks for the skill back.
  rm "$HOME/.claude/skills/.jig-pr-review.placed"
  run gs_place "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "pr-review skill: linked $HOME/.claude/skills/jig-pr-review"
  assert_symlink "$HOME/.claude/skills/jig-pr-review"
  assert_file "$HOME/.claude/skills/.jig-pr-review.placed"
}

# A removed marked copy (where links cannot be made) stays removed as well.
test_globalskill_a_removed_copy_stays_removed() {
  local src lndir
  src=$(gs_source)
  mkdir -p "$HOME/.claude"
  lndir=$(stub_ln_copy_dir)
  # shellcheck disable=SC2016 # expanded by the inner bash
  run env PATH="$lndir:$PATH" bash -c '. "$JIG_HOME/scripts/lib/globalskill.sh" && jig_global_skill_place "$1" 1.2.3' _ "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_file "$HOME/.claude/skills/.jig-pr-review.placed"
  rm -rf "$HOME/.claude/skills/jig-pr-review"
  # shellcheck disable=SC2016 # expanded by the inner bash
  run env PATH="$lndir:$PATH" bash -c '. "$JIG_HOME/scripts/lib/globalskill.sh" && jig_global_skill_place "$1" 1.2.3' _ "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "removed by you, left out $HOME/.claude/skills/jig-pr-review"
  assert_no_file "$HOME/.claude/skills/jig-pr-review"
}

# A skill placed before records existed gets its record on the next run, so a
# person who removes it afterwards is heard; one of the person's own gets none.
test_globalskill_records_a_skill_placed_before_records_existed() {
  skip_unless_symlinks
  local src
  src=$(gs_source)
  mkdir -p "$HOME/.claude/skills" "$HOME/.codex" "$HOME/.agents/skills/jig-pr-review"
  ln -s "$src/skills/jig-pr-review" "$HOME/.claude/skills/jig-pr-review"
  run gs_place "$src"
  assert_eq 0 "$RC" "$OUT"
  assert_file "$HOME/.claude/skills/.jig-pr-review.placed"
  assert_no_file "$HOME/.agents/skills/.jig-pr-review.placed"
}
