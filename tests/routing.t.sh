# Tests for tests/routing.sh — routing evals over the skill descriptions.
# shellcheck shell=bash

routing() { bash "$JIG_HOME/tests/routing.sh" "$@"; }

# _routing_skill <name> <description> — a skill in ./skills.
_routing_skill() {
  mkdir -p "skills/$1"
  printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n' "$1" "$2" "$1" > "skills/$1/SKILL.md"
}

# _routing_cases <name> — ./cases/<name>.cases from stdin.
_routing_cases() {
  mkdir -p cases
  cat > "cases/$1.cases"
}

# Two skills that each win their own prompts.
_routing_fixture() {
  _routing_skill alpha 'Review a change against the conventions. Use when the user says "review", "check this change".'
  _routing_skill beta 'Review the architecture: boundaries and dependency directions. Use when the user says "architecture review", "did we break a boundary".'
  _routing_cases alpha <<'EOF'
# alpha
+ review this change
- architecture review of the gateway
EOF
  _routing_cases beta <<'EOF'
+ architecture review of the gateway
+ did we break a boundary here

- check this change
EOF
}

# --- this repository ---------------------------------------------------------

test_routing_every_skill_wins_its_own_prompts() {
  run routing
  [ "$RC" -eq 0 ] || fail "routing evals failed:
$OUT"
  assert_contains "$OUT" " 0 failed"
  assert_not_contains "$OUT" "FAIL"
}

# The spec's test: a description that stops saying what the skill is for loses
# its prompts, and the check names the skill.
test_routing_vague_description_fails() {
  cp -R "$JIG_HOME/skills" skills
  awk '/^description:/ { print "description: Helps with the work in a project."; next } { print }' \
    "$JIG_HOME/skills/jig-analyze/SKILL.md" > skills/jig-analyze/SKILL.md
  run routing --skills skills
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'FAIL jig-analyze + "'
  assert_not_contains "$OUT" " 0 failed"
}

# --- scoring -----------------------------------------------------------------

test_routing_fixture_passes_and_reports_every_case() {
  _routing_fixture
  run routing --skills skills --cases cases
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" 'ok   alpha + "review this change"'
  assert_contains "$OUT" 'ok   beta - "check this change"'
  assert_contains "$OUT" "routing: 5 case(s) over 2 skill(s), 0 failed"
}

# "review" is in both descriptions; the quoted "architecture review" decides.
test_routing_quoted_phrase_outweighs_a_shared_word() {
  _routing_fixture
  run routing --skills skills --cases cases
  assert_contains "$OUT" 'ok   beta + "architecture review of the gateway"  (beta '
}

test_routing_matches_across_stop_words_and_word_forms() {
  _routing_fixture
  printf '+ reviewing the changes\n- boundaries\n' > cases/alpha.cases
  run routing --skills skills --cases cases
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" 'ok   alpha + "reviewing the changes"'
}

test_routing_a_tie_loses_a_must_case() {
  _routing_skill alpha 'Deploy the service.'
  _routing_skill beta 'Deploy the service.'
  printf '+ deploy the service\n- something else\n' | _routing_cases alpha
  printf '+ nothing matches\n- something else\n' | _routing_cases beta
  run routing --skills skills --cases cases
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'FAIL alpha + "deploy the service"  (alpha '
  assert_contains "$OUT" ' ties beta '
  assert_contains "$OUT" 'FAIL beta + "nothing matches"  (no skill scores)'
}

test_routing_must_not_fails_when_the_skill_wins() {
  _routing_fixture
  printf '+ review this change\n- review this change\n' > cases/alpha.cases
  run routing --skills skills --cases cases
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'FAIL alpha - "review this change"  (alpha '
  assert_contains "$OUT" ' wins)'
}

test_routing_must_not_fails_on_a_tie_for_the_lead() {
  _routing_skill alpha 'Deploy the service.'
  _routing_skill beta 'Deploy the service.'
  printf '+ nothing\n- deploy the service\n' | _routing_cases alpha
  printf '+ nothing\n- other\n' | _routing_cases beta
  run routing --skills skills --cases cases
  assert_contains "$OUT" 'FAIL alpha - "deploy the service"'
  assert_contains "$OUT" 'ties for the lead'
}

# Only the description is scored: a name that says it all does not rescue a
# description that says nothing.
test_routing_scores_the_description_not_the_name() {
  _routing_fixture
  _routing_skill deploy 'Helps with things.'
  printf '+ deploy\n- review this change\n' | _routing_cases deploy
  run routing --skills skills --cases cases
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'FAIL deploy + "deploy"  (no skill scores)'
}

# --- coverage ----------------------------------------------------------------

test_routing_skill_without_cases_fails() {
  _routing_fixture
  rm cases/beta.cases
  run routing --skills skills --cases cases
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL beta: no cases (cases/beta.cases)"
  assert_contains "$OUT" "coverage incomplete"
}

test_routing_skill_needs_a_must_and_a_must_not_case() {
  _routing_fixture
  printf '+ review this change\n' > cases/alpha.cases
  printf -- '- review this change\n' > cases/beta.cases
  run routing --skills skills --cases cases
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'FAIL alpha: no "-" case'
  assert_contains "$OUT" 'FAIL beta: no "+" case'
}

test_routing_cases_for_a_missing_skill_fail() {
  _routing_fixture
  printf '+ x\n- y\n' | _routing_cases gamma
  run routing --skills skills --cases cases
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL gamma: cases for a skill that does not exist"
}

# --- bad input ---------------------------------------------------------------

test_routing_malformed_case_line_is_bad_input() {
  _routing_fixture
  printf '+ review this change\nreview without a sign\n' > cases/alpha.cases
  run routing --skills skills --cases cases
  assert_eq 2 "$RC"
  assert_contains "$OUT" 'cases/alpha.cases:2: expected "+ <prompt>"'
}

test_routing_sign_without_a_prompt_is_bad_input() {
  _routing_fixture
  printf '+ review this change\n+   \n' > cases/alpha.cases
  run routing --skills skills --cases cases
  assert_eq 2 "$RC"
  assert_contains "$OUT" "cases/alpha.cases:2:"
}

test_routing_skill_without_description_is_bad_input() {
  _routing_fixture
  printf -- '---\nname: alpha\n---\n' > skills/alpha/SKILL.md
  run routing --skills skills --cases cases
  assert_eq 2 "$RC"
  assert_contains "$OUT" "no description in the frontmatter"
}

test_routing_tolerates_crlf_files() {
  _routing_fixture
  for f in skills/*/SKILL.md cases/*.cases; do
    awk '{ printf "%s\r\n", $0 }' "$f" > "$f.crlf" && mv "$f.crlf" "$f"
  done
  run routing --skills skills --cases cases
  assert_eq 0 "$RC" "$OUT"
}

test_routing_rejects_unknown_arguments() {
  run routing --bogus
  assert_eq 2 "$RC"
  assert_contains "$OUT" "unknown argument: --bogus"
  run routing --skills
  assert_eq 2 "$RC"
  assert_contains "$OUT" "--skills requires a value"
  run routing --skills missing-dir
  assert_eq 2 "$RC"
  assert_contains "$OUT" "no skills directory: missing-dir"
}

# The tab-separated hand-off to awk must not cut a description at a tab.
test_routing_scores_words_after_a_tab_in_a_description() {
  _routing_fixture
  _routing_skill alpha "$(printf 'Helps.\tReview a change against the conventions. Use when the user says "review", "check this change".')"
  run routing --skills skills --cases cases
  assert_eq 0 "$RC" "$OUT"
}
