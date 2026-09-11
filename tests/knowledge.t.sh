# Tests for `jig knowledge check` (schemas/frontmatter.md, ADR-0004).
# shellcheck shell=bash

# km_setup [require_frontmatter] — fresh repo with .ai/knowledge/ ready.
km_setup() {
  local require="${1:-true}"
  fixture_repo
  mkdir -p .ai/knowledge/adr .ai/knowledge/features
  cat > .ai/config.yaml <<EOF
profiles: [generic]
knowledge.require_frontmatter: ${require}
EOF
}

# --- missing frontmatter -----------------------------------------------------

test_missing_frontmatter_fails_when_required() {
  km_setup true
  cat > .ai/knowledge/features/nofm.md <<'EOF'
# No frontmatter
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/nofm.md: missing frontmatter"
}

test_missing_frontmatter_warns_when_not_required() {
  km_setup false
  cat > .ai/knowledge/features/nofm.md <<'EOF'
# No frontmatter
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "WARN .ai/knowledge/features/nofm.md: missing frontmatter"
  assert_not_contains "$OUT" "FAIL .ai/knowledge/features/nofm.md"
}

# --- id / type / status -------------------------------------------------------

test_valid_frontmatter_passes_clean() {
  km_setup
  cat > .ai/knowledge/features/good.md <<'EOF'
---
id: feature-good
type: feature
status: active
domains: [core]
summary: "A good document."
---
# Good
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge check: 1 documents, 0 failures, 0 warnings"
}

test_invalid_id_fails() {
  km_setup
  cat > .ai/knowledge/features/bad.md <<'EOF'
---
id: Not_Valid!
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/bad.md: missing or invalid id"
}

test_invalid_type_fails() {
  km_setup
  cat > .ai/knowledge/features/bad.md <<'EOF'
---
id: feature-bad
type: nonsense
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/bad.md: missing or invalid type"
}

test_invalid_status_for_feature_fails() {
  km_setup
  cat > .ai/knowledge/features/bad.md <<'EOF'
---
id: feature-bad
type: feature
status: accepted
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/bad.md: missing or invalid status"
}

test_valid_status_for_adr_passes() {
  km_setup
  cat > .ai/knowledge/adr/0001-decision.md <<'EOF'
---
id: adr-0001-decision
type: adr
status: superseded
date: 2026-01-01
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_duplicate_id_fails() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-dup
type: feature
status: active
domains: [core]
---
EOF
  cat > .ai/knowledge/features/b.md <<'EOF'
---
id: feature-dup
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "duplicate id: feature-dup"
}

# --- ADR file naming -----------------------------------------------------------

test_adr_filename_not_matching_pattern_fails() {
  km_setup
  cat > .ai/knowledge/adr/decision.md <<'EOF'
---
id: adr-decision
type: adr
status: accepted
date: 2026-01-01
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/adr/decision.md: ADR file name must match NNNN-<slug>.md"
}

test_adr_filename_matching_pattern_passes() {
  km_setup
  cat > .ai/knowledge/adr/0001-decision.md <<'EOF'
---
id: adr-0001-decision
type: adr
status: accepted
date: 2026-01-01
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_duplicate_adr_number_fails() {
  km_setup
  cat > .ai/knowledge/adr/0001-first.md <<'EOF'
---
id: adr-0001-first
type: adr
status: accepted
date: 2026-01-01
domains: [core]
---
EOF
  cat > .ai/knowledge/adr/0001-second.md <<'EOF'
---
id: adr-0001-second
type: adr
status: accepted
date: 2026-01-01
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "duplicate ADR number: 0001"
}

test_non_adr_type_under_adr_dir_fails() {
  km_setup
  cat > .ai/knowledge/adr/0001-not-adr.md <<'EOF'
---
id: feature-not-adr
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/adr/0001-not-adr.md: document under adr/ must have type: adr"
}

test_adr_missing_date_fails() {
  km_setup
  cat > .ai/knowledge/adr/0001-nodate.md <<'EOF'
---
id: adr-0001-nodate
type: adr
status: accepted
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/adr/0001-nodate.md: missing or invalid date"
}

test_adr_invalid_date_format_fails() {
  km_setup
  cat > .ai/knowledge/adr/0001-baddate.md <<'EOF'
---
id: adr-0001-baddate
type: adr
status: accepted
date: 01/01/2026
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/adr/0001-baddate.md: missing or invalid date"
}

test_malformed_reviewed_at_fails() {
  km_setup
  cat > .ai/knowledge/features/bad.md <<'EOF'
---
id: feature-bad
type: feature
status: active
domains: [core]
reviewed_at: 01/01/2026
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/bad.md: invalid reviewed_at: 01/01/2026 (expected YYYY-MM-DD)"
}

# --- links ---------------------------------------------------------------------

test_broken_relative_link_fails() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
See [missing](./nowhere.md) for details.
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/a.md: broken link: ./nowhere.md"
}

test_valid_relative_link_passes() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
See [b](./b.md#section) for details.
EOF
  cat > .ai/knowledge/features/b.md <<'EOF'
---
id: feature-b
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_external_and_anchor_links_are_skipped() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
[web](https://example.com/x), [mail](mailto:a@b.c), [anchor](#top).
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_global_doc_broken_link_still_fails() {
  km_setup
  cat > .ai/knowledge/GLOSSARY.md <<'EOF'
# Glossary
See [missing](./nowhere.md).
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/GLOSSARY.md: broken link: ./nowhere.md"
}

# --- supersedes ------------------------------------------------------------------

test_supersedes_unknown_id_fails() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
supersedes: feature-ghost
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "supersedes unknown id: feature-ghost"
}

test_supersedes_known_id_passes() {
  km_setup
  cat > .ai/knowledge/features/old.md <<'EOF'
---
id: feature-old
type: feature
status: deprecated
domains: [core]
---
EOF
  cat > .ai/knowledge/features/new.md <<'EOF'
---
id: feature-new
type: feature
status: active
domains: [core]
supersedes: feature-old
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

# --- paths / domains ---------------------------------------------------------------

test_paths_glob_matching_nothing_warns() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "does/not/exist/**"
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "WARN .ai/knowledge/features/a.md: paths glob matches no file: does/not/exist/**"
}

test_paths_glob_matching_something_no_warning() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "README.md"
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "paths glob matches no file"
}

test_missing_domains_and_paths_warns() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "WARN .ai/knowledge/features/a.md: document has neither domains nor paths"
}

test_domains_only_avoids_warning() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "neither domains nor paths"
}

# --- global docs exemption ----------------------------------------------------

test_global_docs_exempt_from_frontmatter_checks() {
  km_setup
  cat > .ai/knowledge/GLOSSARY.md <<'EOF'
# Glossary
No frontmatter, and that's fine.
EOF
  cat > .ai/knowledge/ARCHITECTURE.md <<'EOF'
# Architecture
EOF
  cat > .ai/knowledge/RULES.md <<'EOF'
# Rules
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "GLOSSARY"
  assert_not_contains "$OUT" "ARCHITECTURE"
  assert_not_contains "$OUT" "RULES"
  assert_contains "$OUT" "knowledge check: 3 documents, 0 failures, 0 warnings"
}

# --- list grammar: inline, block, quoted items --------------------------------

test_inline_and_block_lists_with_quoted_items_both_work() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: ["core", scripts]
paths:
  - "README.md"
  - "does/not/exist/**"
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "neither domains nor paths"
  assert_not_contains "$OUT" "paths glob matches no file: README.md"
  assert_contains "$OUT" "paths glob matches no file: does/not/exist/**"
}

# --- comment after a scalar value ----------------------------------------------

test_comment_after_scalar_value_is_ignored() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a   # a trailing comment
type: feature
status: active  # another comment
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

# --- --quiet -------------------------------------------------------------------

test_quiet_suppresses_warnings_and_summary_but_not_failures() {
  km_setup
  cat > .ai/knowledge/features/warn.md <<'EOF'
---
id: feature-warn
type: feature
status: active
---
EOF
  cat > .ai/knowledge/features/fail.md <<'EOF'
---
id: Not Valid
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check --quiet
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/fail.md: missing or invalid id"
  assert_not_contains "$OUT" "WARN"
  assert_not_contains "$OUT" "knowledge check:"
}

# --- exit codes ------------------------------------------------------------------

test_exit_code_zero_on_clean_repository() {
  km_setup
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_exit_code_one_on_any_failure() {
  km_setup
  cat > .ai/knowledge/features/bad.md <<'EOF'
---
id: not valid id
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
}

# --- CLI plumbing ----------------------------------------------------------------

test_unknown_subcommand_dies_with_usage() {
  km_setup
  run jig knowledge bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig knowledge check"
}

test_unknown_flag_dies_with_usage() {
  km_setup
  run jig knowledge check --nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig knowledge check"
}

test_check_without_init_dies() {
  fixture_repo
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

# --- knowledge new -------------------------------------------------------------

test_new_feature_creates_file_and_prints_repo_relative_path() {
  km_setup
  run jig knowledge new feature my-feature
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/features/my-feature.md" "$OUT"
  assert_file .ai/knowledge/features/my-feature.md
  assert_file_contains .ai/knowledge/features/my-feature.md "id: feature-my-feature"
}

test_new_convention_creates_file_at_conventions_path() {
  km_setup
  run jig knowledge new convention my-convention
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/conventions/my-convention.md" "$OUT"
  assert_file_contains .ai/knowledge/conventions/my-convention.md "id: convention-my-convention"
}

test_new_adr_fills_id_date_and_heading() {
  km_setup
  run jig knowledge new adr my-decision
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/adr/0001-my-decision.md" "$OUT"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "id: adr-0001-my-decision"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "date: $(date +%Y-%m-%d)"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "# ADR-0001: <Decision in one sentence>"
}

test_new_adr_numbering_is_highest_existing_plus_one_and_does_not_fill_gaps() {
  km_setup
  cat > .ai/knowledge/adr/0001-first.md <<'EOF'
---
id: adr-0001-first
type: adr
status: accepted
date: 2026-01-01
---
EOF
  cat > .ai/knowledge/adr/0003-third.md <<'EOF'
---
id: adr-0003-third
type: adr
status: accepted
date: 2026-01-01
---
EOF
  run jig knowledge new adr fourth
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/adr/0004-fourth.md" "$OUT"
}

test_new_with_domains_and_paths_writes_block_lists_paths_quoted_domains_not() {
  km_setup
  run jig knowledge new feature widget --domains "core, ui" --paths "src/widget/**, README.md"
  assert_eq 0 "$RC"
  local content
  content=$(cat .ai/knowledge/features/widget.md)
  assert_contains "$content" "  - core"
  assert_contains "$content" "  - ui"
  assert_contains "$content" '  - "src/widget/**"'
  assert_contains "$content" "  - README.md"
}

test_new_refuses_to_overwrite_existing_document() {
  km_setup
  jig knowledge new feature dup >/dev/null
  run jig knowledge new feature dup
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: document already exists: .ai/knowledge/features/dup.md"
  assert_no_file .ai/knowledge/features/dup.md.tmp
}

test_new_rejects_invalid_type() {
  km_setup
  run jig knowledge new bogus slug
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: unknown type 'bogus' (expected one of: feature adr convention domain glossary rule)"
}

test_new_rejects_path_traversal_slug() {
  km_setup
  run jig knowledge new feature ../evil
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: invalid name '../evil': expected [a-z0-9-], no leading or trailing '-'"
}

test_new_rejects_invalid_slug_characters() {
  km_setup
  run jig knowledge new feature Bad_Slug
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: invalid name 'Bad_Slug': expected [a-z0-9-], no leading or trailing '-'"
}

test_new_requires_type_and_slug() {
  km_setup
  run jig knowledge new feature
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig knowledge new <feature|adr|convention> <slug>"
}

test_new_rejects_unknown_argument() {
  km_setup
  run jig knowledge new feature widget --status active
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge new: unknown argument: --status"
}

# --- knowledge new: --proposed flag ---------------------------------------------

test_new_feature_proposed_sets_status_proposed() {
  km_setup
  run jig knowledge new feature my-feature --proposed
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/features/my-feature.md" "$OUT"
  assert_file .ai/knowledge/features/my-feature.md
  assert_file_contains .ai/knowledge/features/my-feature.md "id: feature-my-feature"
  assert_file_contains .ai/knowledge/features/my-feature.md "status: proposed"
}

test_new_adr_proposed_sets_status_proposed_not_accepted() {
  km_setup
  run jig knowledge new adr my-decision --proposed
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/adr/0001-my-decision.md" "$OUT"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "id: adr-0001-my-decision"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "status: proposed"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "date: $(date +%Y-%m-%d)"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "# ADR-0001: <Decision in one sentence>"
  local content
  content=$(cat .ai/knowledge/adr/0001-my-decision.md)
  assert_not_contains "$content" "status: accepted"
}

test_new_feature_proposed_with_domains_and_paths_writes_same_lists_as_unflagged() {
  km_setup
  run jig knowledge new feature widget --domains "core, ui" --paths "src/widget/**, README.md" --proposed
  assert_eq 0 "$RC"
  local content
  content=$(cat .ai/knowledge/features/widget.md)
  assert_contains "$content" "status: proposed"
  assert_contains "$content" "  - core"
  assert_contains "$content" "  - ui"
  assert_contains "$content" '  - "src/widget/**"'
  assert_contains "$content" "  - README.md"
}

test_new_feature_proposed_flag_before_options_also_works() {
  km_setup
  run jig knowledge new feature widget --proposed --domains "core, ui" --paths "src/widget/**, README.md"
  assert_eq 0 "$RC"
  local content
  content=$(cat .ai/knowledge/features/widget.md)
  assert_contains "$content" "status: proposed"
  assert_contains "$content" "  - core"
  assert_contains "$content" "  - ui"
  assert_contains "$content" '  - "src/widget/**"'
  assert_contains "$content" "  - README.md"
}

test_new_rule_proposed_sets_status_proposed_with_default_domains() {
  km_setup
  run jig knowledge new rule payments --proposed
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/domains/payments/RULES.md" "$OUT"
  assert_file_contains .ai/knowledge/domains/payments/RULES.md "id: rule-payments"
  assert_file_contains .ai/knowledge/domains/payments/RULES.md "status: proposed"
  local content
  content=$(cat .ai/knowledge/domains/payments/RULES.md)
  assert_contains "$content" "  - payments"
}

test_new_without_proposed_flag_status_comes_from_template() {
  km_setup
  run jig knowledge new feature untouched
  assert_eq 0 "$RC"
  assert_file_contains .ai/knowledge/features/untouched.md "status: active"

  run jig knowledge new adr untouched-decision
  assert_eq 0 "$RC"
  assert_file_contains .ai/knowledge/adr/0001-untouched-decision.md "status: accepted"
}

test_new_feature_proposed_is_listed_checked_and_promoted_by_accept() {
  km_setup
  run jig knowledge new feature widget --proposed --domains core
  assert_eq 0 "$RC"

  run jig knowledge proposed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "proposed:  feature-widget  (feature)  .ai/knowledge/features/widget.md"

  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 failures"

  run jig knowledge accept feature-widget
  assert_eq 0 "$RC"
  assert_contains "$OUT" "accepted   .ai/knowledge/features/widget.md  (status: active)"
  assert_file_contains .ai/knowledge/features/widget.md "status: active"
}

test_new_adr_proposed_is_listed_checked_and_promoted_to_accepted() {
  km_setup
  run jig knowledge new adr my-decision --proposed --domains core
  assert_eq 0 "$RC"

  run jig knowledge proposed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "proposed:  adr-0001-my-decision  (adr)  .ai/knowledge/adr/0001-my-decision.md"

  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 failures"

  run jig knowledge accept adr-0001-my-decision
  assert_eq 0 "$RC"
  assert_contains "$OUT" "accepted   .ai/knowledge/adr/0001-my-decision.md  (status: accepted)"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "status: accepted"
}

# jig context resolve must never surface a document created with --proposed,
# under selectors that would match it once it is active (ADR-0016).
test_new_feature_proposed_not_resolved_by_context_until_accepted() {
  km_setup
  # Progressive context requires the three mandatory globals (ADR-0021).
  for global in GLOSSARY ARCHITECTURE RULES; do
    printf '# %s\n' "$global" > ".ai/knowledge/$global.md"
  done
  run jig knowledge new feature ctxtest --proposed --domains core
  assert_eq 0 "$RC"

  run jig context resolve --no-task --domains core --catalog
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "required:  .ai/knowledge/features/ctxtest.md"
  assert_not_contains "$OUT" "catalog:   .ai/knowledge/features/ctxtest.md"

  run jig knowledge accept feature-ctxtest
  assert_eq 0 "$RC"

  run jig context resolve --no-task --domains core --catalog
  assert_eq 0 "$RC"
  assert_contains "$OUT" "catalog:   .ai/knowledge/features/ctxtest.md"
}

# --- knowledge new: refused --domains/--paths items leave no leftover file -----

test_new_refuses_domains_item_with_hash_and_leaves_no_leftover_file() {
  km_setup
  run jig knowledge new feature widget --domains "bad#value"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge new: invalid --domains value: bad#value"
  assert_no_file .ai/knowledge/features/widget.md
  local leftovers
  leftovers=$(find .ai/knowledge/features -maxdepth 1 -type f)
  assert_eq "" "$leftovers" "no leftover file in .ai/knowledge/features/"
}

test_new_proposed_refuses_domains_item_with_hash_and_leaves_no_leftover_file() {
  km_setup
  run jig knowledge new feature widget --proposed --domains "bad#value"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge new: invalid --domains value: bad#value"
  assert_no_file .ai/knowledge/features/widget.md
  local leftovers
  leftovers=$(find .ai/knowledge/features -maxdepth 1 -type f)
  assert_eq "" "$leftovers" "no leftover file in .ai/knowledge/features/"
}

test_new_refuses_paths_item_with_hash_and_leaves_no_leftover_file() {
  km_setup
  run jig knowledge new feature widget --paths "bad#glob"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge new: invalid --paths value: bad#glob"
  assert_no_file .ai/knowledge/features/widget.md
  local leftovers
  leftovers=$(find .ai/knowledge/features -maxdepth 1 -type f)
  assert_eq "" "$leftovers" "no leftover file in .ai/knowledge/features/"
}

test_new_proposed_refuses_paths_item_with_hash_and_leaves_no_leftover_file() {
  km_setup
  run jig knowledge new feature widget --proposed --paths "bad#glob"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge new: invalid --paths value: bad#glob"
  assert_no_file .ai/knowledge/features/widget.md
  local leftovers
  leftovers=$(find .ai/knowledge/features -maxdepth 1 -type f)
  assert_eq "" "$leftovers" "no leftover file in .ai/knowledge/features/"
}

test_new_unwritable_directory_fails_with_message_and_leaves_nothing() {
  # Before the build file, `cp` wrote straight to the document's path, and a
  # failing `cp` ended the command under `set -e` with no message of its own.
  km_setup
  mkdir -p .ai/knowledge/features
  chmod 555 .ai/knowledge/features

  run jig knowledge new feature widget --proposed
  chmod 755 .ai/knowledge/features
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge new: could not write .ai/knowledge/features/widget.md"
  local leftovers
  leftovers=$(find .ai/knowledge/features -maxdepth 1 -type f)
  assert_eq "" "$leftovers" "no leftover file in .ai/knowledge/features/"
}

# --- knowledge paths add|remove -------------------------------------------------

test_paths_add_adds_glob_to_frontmatter() {
  km_setup
  jig knowledge new feature widget >/dev/null
  run jig knowledge paths add feature-widget "src/widget/**"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "added      .ai/knowledge/features/widget.md  src/widget/**"
  local content
  content=$(cat .ai/knowledge/features/widget.md)
  assert_contains "$content" '  - "src/widget/**"'
}

test_paths_add_second_identical_add_reports_unchanged() {
  km_setup
  jig knowledge new feature widget >/dev/null
  jig knowledge paths add feature-widget "src/widget/**" >/dev/null
  run jig knowledge paths add feature-widget "src/widget/**"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unchanged  .ai/knowledge/features/widget.md  src/widget/** (already listed)"
}

test_paths_remove_drops_one_glob_and_keeps_the_other() {
  km_setup
  jig knowledge new feature widget >/dev/null
  jig knowledge paths add feature-widget "src/widget/**" >/dev/null
  jig knowledge paths add feature-widget "src/other/**" >/dev/null
  run jig knowledge paths remove feature-widget "src/widget/**"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "removed    .ai/knowledge/features/widget.md  src/widget/**"
  local content
  content=$(cat .ai/knowledge/features/widget.md)
  assert_not_contains "$content" "src/widget/**"
  assert_contains "$content" "src/other/**"
}

test_paths_remove_absent_glob_reports_unchanged() {
  km_setup
  jig knowledge new feature widget >/dev/null
  run jig knowledge paths remove feature-widget "does/not/exist/**"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unchanged  .ai/knowledge/features/widget.md  does/not/exist/** (not listed)"
}

test_paths_edit_unknown_id_dies() {
  km_setup
  run jig knowledge paths add no-such-id "src/**"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: no document with id: no-such-id"
}

# --- knowledge paths (report) ---------------------------------------------------

# km_run_stdin <input> <cmd...> — like `run`, but feeds <input> on stdin.
km_run_stdin() {
  local input="$1"
  shift
  set +e
  OUT=$(printf '%s' "$input" | "$@" 2>&1)
  RC=$?
  set -e
  export OUT RC
}

test_paths_report_uncovered_groups_by_directory_with_file_count() {
  km_setup
  mkdir -p src/widget
  touch src/widget/a.sh src/widget/b.sh
  km_run_stdin "src/widget/a.sh
src/widget/b.sh
" jig knowledge paths --files -
  assert_eq 0 "$RC"
  assert_contains "$OUT" "uncovered: src/widget/  (2 files)"
  assert_contains "$OUT" "knowledge paths: 1 uncovered directories, 0 unmatched globs"
}

test_paths_report_single_uncovered_file_uses_singular_word() {
  km_setup
  touch onlyfile.sh
  km_run_stdin "onlyfile.sh
" jig knowledge paths --files -
  assert_eq 0 "$RC"
  assert_contains "$OUT" "uncovered: ./  (1 file)"
}

test_paths_report_excludes_ai_directory_files_from_uncovered() {
  km_setup
  km_run_stdin ".ai/config.yaml
" jig knowledge paths --files -
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "uncovered:"
  assert_contains "$OUT" "knowledge paths: 0 uncovered directories, 0 unmatched globs"
}

test_paths_report_unmatched_glob_names_document_and_glob() {
  km_setup
  jig knowledge new feature ghost --paths "does/not/exist/**" >/dev/null
  km_run_stdin "" jig knowledge paths --files -
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unmatched: .ai/knowledge/features/ghost.md  (does/not/exist/**)"
  assert_contains "$OUT" "knowledge paths: 0 uncovered directories, 1 unmatched globs"
}

test_paths_report_files_stdin_reads_dash() {
  km_setup
  mkdir -p src/thing
  touch src/thing/x.sh
  km_run_stdin "src/thing/x.sh
" jig knowledge paths --files -
  assert_eq 0 "$RC"
  assert_contains "$OUT" "uncovered: src/thing/  (1 file)"
}

test_paths_report_default_picks_up_untracked_files_from_git() {
  km_setup
  mkdir -p src/widget
  touch src/widget/a.sh
  run jig knowledge paths
  assert_eq 0 "$RC"
  assert_contains "$OUT" "uncovered: src/widget/  (1 file)"
}

test_paths_report_unknown_task_dies() {
  km_setup
  run jig knowledge paths --task no-such-task
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge paths: unknown task: no-such-task"
}

test_paths_report_with_valid_task_succeeds() {
  km_setup
  jig task new mytask >/dev/null
  run jig knowledge paths --task mytask
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge paths: 0 uncovered directories, 0 unmatched globs"
}

# --- knowledge stale -------------------------------------------------------------

test_stale_reports_orphaned_when_reviewed_document_lost_its_code() {
  km_setup
  cat > .ai/knowledge/features/ghost.md <<'EOF'
---
id: feature-ghost
type: feature
status: active
reviewed_at: 2020-01-01
paths:
  - "does/not/exist/**"
---
EOF
  run jig knowledge stale
  assert_eq 0 "$RC"
  assert_contains "$OUT" "orphaned:   .ai/knowledge/features/ghost.md  (reviewed 2020-01-01, no file matches: does/not/exist/**)"
  assert_contains "$OUT" "knowledge stale: 1 documents with paths, 0 stale, 0 unreviewed, 1 orphaned, 0 planned"
}

test_stale_reports_planned_when_document_never_matched_code() {
  km_setup
  cat > .ai/knowledge/features/ahead.md <<'EOF'
---
id: feature-ahead
type: feature
status: active
paths:
  - "not/written/yet/**"
---
EOF
  run jig knowledge stale
  assert_eq 0 "$RC"
  assert_contains "$OUT" "planned:    .ai/knowledge/features/ahead.md  (no file matches yet: not/written/yet/**)"
  assert_not_contains "$OUT" "orphaned:"
  assert_contains "$OUT" "knowledge stale: 1 documents with paths, 0 stale, 0 unreviewed, 0 orphaned, 1 planned"
}

test_stale_strict_ignores_planned_but_fails_on_orphaned() {
  km_setup
  cat > .ai/knowledge/features/ahead.md <<'EOF'
---
id: feature-ahead
type: feature
status: active
paths:
  - "not/written/yet/**"
---
EOF
  run jig knowledge stale --strict
  assert_eq 0 "$RC" "planned alone must not fail --strict"

  cat > .ai/knowledge/features/ghost.md <<'EOF'
---
id: feature-ghost
type: feature
status: active
reviewed_at: 2020-01-01
paths:
  - "does/not/exist/**"
---
EOF
  run jig knowledge stale --strict
  assert_eq 1 "$RC" "orphaned must fail --strict"
}

test_stale_reports_unreviewed_when_never_reviewed() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "README.md"
---
EOF
  run jig knowledge stale
  assert_eq 0 "$RC"
  assert_contains "$OUT" "unreviewed: .ai/knowledge/features/a.md  (never reconciled with the code)"
  assert_contains "$OUT" "knowledge stale: 1 documents with paths, 0 stale, 1 unreviewed, 0 orphaned, 0 planned"
}

test_stale_reports_stale_when_reviewed_before_code_changed() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "tracked.sh"
reviewed_at: 2020-01-01
---
EOF
  printf '#!/bin/sh\n' > tracked.sh
  git add tracked.sh
  git commit -q -m "add tracked.sh"

  run jig knowledge stale
  assert_eq 0 "$RC"
  assert_contains "$OUT" "stale:      .ai/knowledge/features/a.md  (reviewed 2020-01-01, code changed"
  assert_contains "$OUT" "knowledge stale: 1 documents with paths, 1 stale, 0 unreviewed, 0 orphaned, 0 planned"
}

test_stale_skips_documents_with_historical_status() {
  km_setup
  cat > .ai/knowledge/features/old.md <<'EOF'
---
id: feature-old
type: feature
status: deprecated
paths:
  - "does/not/exist/**"
---
EOF
  run jig knowledge stale
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "feature-old"
  assert_contains "$OUT" "knowledge stale: 0 documents with paths, 0 stale, 0 unreviewed, 0 orphaned, 0 planned"
}

test_stale_skips_documents_without_paths() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge stale
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge stale: 0 documents with paths, 0 stale, 0 unreviewed, 0 orphaned, 0 planned"
}

test_stale_without_strict_exits_zero_despite_findings() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
reviewed_at: 2020-01-01
paths:
  - "does/not/exist/**"
---
EOF
  run jig knowledge stale
  assert_eq 0 "$RC"
  assert_contains "$OUT" "orphaned:"
}

test_stale_strict_exits_nonzero_on_finding() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "README.md"
---
EOF
  run jig knowledge stale --strict
  assert_eq 1 "$RC"
}

test_stale_strict_exits_zero_when_clean() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "README.md"
reviewed_at: 2099-01-01
---
EOF
  run jig knowledge stale --strict
  assert_eq 0 "$RC"
}

# --- knowledge reviewed ------------------------------------------------------------

test_reviewed_stamps_today_by_default() {
  km_setup
  jig knowledge new feature widget >/dev/null
  run jig knowledge reviewed feature-widget
  assert_eq 0 "$RC"
  local today
  today=$(date +%Y-%m-%d)
  assert_contains "$OUT" "reviewed   .ai/knowledge/features/widget.md  $today"
  assert_file_contains .ai/knowledge/features/widget.md "reviewed_at: $today"
}

test_reviewed_accepts_explicit_date() {
  km_setup
  jig knowledge new feature widget >/dev/null
  run jig knowledge reviewed feature-widget --date 2026-01-15
  assert_eq 0 "$RC"
  assert_contains "$OUT" "reviewed   .ai/knowledge/features/widget.md  2026-01-15"
  assert_file_contains .ai/knowledge/features/widget.md "reviewed_at: 2026-01-15"
}

test_reviewed_rejects_malformed_date() {
  km_setup
  jig knowledge new feature widget >/dev/null
  run jig knowledge reviewed feature-widget --date 01/15/2026
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge reviewed: invalid date '01/15/2026' (expected YYYY-MM-DD)"
}

test_reviewed_unknown_id_dies() {
  km_setup
  run jig knowledge reviewed no-such-id
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: no document with id: no-such-id"
}

# --- self-check: the framework's own knowledge base ----------------------------

test_real_repository_knowledge_passes_with_no_failures() {
  fixture_repo
  mkdir -p .ai
  cp -R "$JIG_HOME/.ai/knowledge" .ai/knowledge
  cp "$JIG_HOME/templates/config.yaml" .ai/config.yaml
  for d in skills scripts adapters templates tests schemas docs; do
    [ -d "$JIG_HOME/$d" ] && cp -R "$JIG_HOME/$d" "./$d"
  done
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "FAIL "
}

# --- knowledge new: domain packs -----------------------------------------------

test_new_domain_creates_overview_with_default_domains() {
  km_setup
  run jig knowledge new domain payments
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/domains/payments/OVERVIEW.md" "$OUT"
  assert_file_contains .ai/knowledge/domains/payments/OVERVIEW.md "id: domain-payments"
  local content
  content=$(cat .ai/knowledge/domains/payments/OVERVIEW.md)
  assert_contains "$content" "  - payments"
}

test_new_rule_creates_rules_with_default_domains() {
  km_setup
  run jig knowledge new rule payments
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/domains/payments/RULES.md" "$OUT"
  assert_file_contains .ai/knowledge/domains/payments/RULES.md "id: rule-payments"
  local content
  content=$(cat .ai/knowledge/domains/payments/RULES.md)
  assert_contains "$content" "  - payments"
}

test_new_glossary_creates_glossary_with_default_domains() {
  km_setup
  run jig knowledge new glossary payments
  assert_eq 0 "$RC"
  assert_eq ".ai/knowledge/domains/payments/GLOSSARY.md" "$OUT"
  assert_file_contains .ai/knowledge/domains/payments/GLOSSARY.md "id: glossary-payments"
  local content
  content=$(cat .ai/knowledge/domains/payments/GLOSSARY.md)
  assert_contains "$content" "  - payments"
}

test_new_domain_rejects_invalid_domain_name() {
  km_setup
  run jig knowledge new domain "Bad Name"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: invalid domain"
  assert_no_file ".ai/knowledge/domains/Bad Name/OVERVIEW.md"
}

test_new_rule_rejects_path_traversal_domain_name() {
  km_setup
  run jig knowledge new rule "../escape"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: invalid domain"
}

# --- domain pack files are not exempt as global (regression) -------------------

test_domain_pack_rules_file_is_not_exempt_as_global() {
  km_setup
  mkdir -p .ai/knowledge/domains/payments
  cat > .ai/knowledge/domains/payments/RULES.md <<'EOF'
---
type: rule
status: active
domains: [payments]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/domains/payments/RULES.md: missing or invalid id"
}

test_domain_pack_glossary_file_is_not_exempt_as_global() {
  km_setup
  mkdir -p .ai/knowledge/domains/payments
  cat > .ai/knowledge/domains/payments/GLOSSARY.md <<'EOF'
---
type: glossary
status: active
domains: [payments]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/domains/payments/GLOSSARY.md: missing or invalid id"
}

test_real_global_rules_file_still_exempt_from_frontmatter_checks() {
  km_setup
  cat > .ai/knowledge/RULES.md <<'EOF'
# Rules
No frontmatter here, and this must not be flagged.
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "RULES.md"
}

# --- domain pack placement must agree with its own domains ---------------------

test_domain_pack_file_not_declaring_its_own_domain_fails() {
  km_setup
  mkdir -p .ai/knowledge/domains/payments
  cat > .ai/knowledge/domains/payments/OVERVIEW.md <<'EOF'
---
id: domain-payments
type: domain
status: active
domains: [other]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/domains/payments/OVERVIEW.md: filed under domains/payments/ but does not declare domain: payments"
}

# --- load validation -------------------------------------------------------------

test_load_invalid_value_fails() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
load: sometimes
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/a.md: invalid load: sometimes (expected always, domain or matched)"
}

test_load_valid_values_pass() {
  km_setup
  cat > .ai/knowledge/features/always.md <<'EOF'
---
id: feature-always
type: feature
status: active
domains: [core]
load: always
---
EOF
  cat > .ai/knowledge/features/domain.md <<'EOF'
---
id: feature-domain
type: feature
status: active
domains: [core]
load: domain
---
EOF
  cat > .ai/knowledge/features/matched.md <<'EOF'
---
id: feature-matched
type: feature
status: active
domains: [core]
load: matched
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_load_absent_passes() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

# --- topics validation -----------------------------------------------------------

test_topics_invalid_value_fails() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
topics: [Bad_Topic]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "FAIL .ai/knowledge/features/a.md: invalid topic: Bad_Topic"
}

test_topics_valid_values_pass() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
topics: [refunds, order-flow]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

# --- requires validation -----------------------------------------------------------

test_requires_unknown_id_fails() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
requires: [feature-ghost]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires unknown id: feature-ghost"
}

test_requires_inactive_document_fails() {
  km_setup
  cat > .ai/knowledge/features/old.md <<'EOF'
---
id: feature-old
type: feature
status: deprecated
domains: [core]
---
EOF
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
requires: [feature-old]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires inactive document: feature-old (status: deprecated)"
}

test_requires_two_node_cycle_fails_both() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
requires: [feature-b]
---
EOF
  cat > .ai/knowledge/features/b.md <<'EOF'
---
id: feature-b
type: feature
status: active
domains: [core]
requires: [feature-a]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires cycle through: feature-a"
  assert_contains "$OUT" "requires cycle through: feature-b"
}

# --- status: proposed / knowledge accept ----------------------------------------

test_check_passes_proposed_feature_and_adr() {
  km_setup
  cat > .ai/knowledge/features/prop.md <<'EOF'
---
id: feature-prop
type: feature
status: proposed
domains: [core]
---
EOF
  cat > .ai/knowledge/adr/0001-prop.md <<'EOF'
---
id: adr-0001-prop
type: adr
status: proposed
date: 2026-01-01
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge check: 2 documents, 0 failures, 0 warnings"
}

# --- summary -------------------------------------------------------------------

test_summary_sets_the_field_and_clears_the_warning() {
  km_setup
  jig knowledge new feature thing --domains core >/dev/null

  run jig knowledge summary feature-thing "What the thing is for."
  assert_eq 0 "$RC"
  assert_contains "$OUT" "summary    .ai/knowledge/features/thing.md"

  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "no summary"
  assert_contains "$(cat .ai/knowledge/features/thing.md)" "summary: What the thing is for."
}

test_summary_refuses_empty_text() {
  km_setup
  jig knowledge new feature thing --domains core >/dev/null
  run jig knowledge summary feature-thing ""
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge summary: text may not be empty"
}

test_summary_refuses_hash_which_the_reader_would_strip() {
  km_setup
  jig knowledge new feature thing --domains core >/dev/null
  run jig knowledge summary feature-thing "Counts # of retries."
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge summary: text may not contain '#'"
}

test_summary_unknown_id_dies() {
  km_setup
  run jig knowledge summary feature-nope "x"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: no document with id:"
}

test_summary_requires_id_and_text() {
  km_setup
  run jig knowledge summary feature-thing
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig knowledge summary <id> <text>"
}

test_summary_rejects_extra_argument() {
  km_setup
  jig knowledge new feature thing --domains core >/dev/null
  run jig knowledge summary feature-thing "a" "b"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge summary: unknown argument: b"
}

test_accept_promotes_proposed_feature_to_active() {
  km_setup
  jig knowledge new feature smoke --proposed >/dev/null

  run jig knowledge accept feature-smoke
  assert_eq 0 "$RC"
  assert_contains "$OUT" "accepted   .ai/knowledge/features/smoke.md  (status: active)"
  assert_contains "$OUT" "knowledge accept: 1 accepted"
  assert_file_contains .ai/knowledge/features/smoke.md "status: active"
}

test_accept_promotes_proposed_adr_to_accepted_not_active() {
  km_setup
  jig knowledge new adr my-decision --proposed >/dev/null

  run jig knowledge accept adr-0001-my-decision
  assert_eq 0 "$RC"
  assert_contains "$OUT" "accepted   .ai/knowledge/adr/0001-my-decision.md  (status: accepted)"
  assert_contains "$OUT" "knowledge accept: 1 accepted"
  assert_file_contains .ai/knowledge/adr/0001-my-decision.md "status: accepted"
}

test_accept_twice_fails_on_second_call() {
  km_setup
  jig knowledge new feature smoke --proposed >/dev/null
  jig knowledge accept feature-smoke >/dev/null

  run jig knowledge accept feature-smoke
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: knowledge: not a proposed document: feature-smoke (status: active)"
}

test_accept_refuses_superseded_document() {
  km_setup
  jig knowledge new feature old >/dev/null
  sed 's/^status: active/status: superseded/' .ai/knowledge/features/old.md \
    > .ai/knowledge/features/old.md.new
  mv .ai/knowledge/features/old.md.new .ai/knowledge/features/old.md

  run jig knowledge accept feature-old
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: knowledge: not a proposed document: feature-old (status: superseded)"
}

test_accept_no_status_reports_status_none() {
  km_setup
  cat > .ai/knowledge/features/nostat.md <<'EOF'
---
id: feature-nostat
type: feature
domains: [core]
---
EOF
  run jig knowledge accept feature-nostat
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: knowledge: not a proposed document: feature-nostat (status: none)"
}

test_accept_unknown_id_dies() {
  km_setup
  run jig knowledge accept no-such-id
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: no document with id: no-such-id"
}

test_accept_requires_id_argument() {
  km_setup
  run jig knowledge accept
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig knowledge accept <id>"
}

# --- knowledge accept: multiple ids ---------------------------------------------

test_accept_multi_id_applies_all() {
  km_setup
  jig knowledge new feature one --proposed >/dev/null
  jig knowledge new feature two --proposed >/dev/null

  run jig knowledge accept feature-one feature-two
  assert_eq 0 "$RC"
  assert_contains "$OUT" "accepted   .ai/knowledge/features/one.md  (status: active)"
  assert_contains "$OUT" "accepted   .ai/knowledge/features/two.md  (status: active)"
  assert_contains "$OUT" "knowledge accept: 2 accepted"
  assert_file_contains .ai/knowledge/features/one.md "status: active"
  assert_file_contains .ai/knowledge/features/two.md "status: active"
}

test_accept_multi_id_with_bad_id_changes_nothing() {
  km_setup
  jig knowledge new feature one --proposed >/dev/null
  jig knowledge new feature two --proposed >/dev/null

  run jig knowledge accept feature-one feature-two no-such-id
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: no document with id: no-such-id"
  assert_file_contains .ai/knowledge/features/one.md "status: proposed"
  assert_file_contains .ai/knowledge/features/two.md "status: proposed"
}

test_accept_multi_id_with_non_proposed_id_changes_nothing() {
  km_setup
  jig knowledge new feature one --proposed >/dev/null
  jig knowledge new feature two >/dev/null
  # feature-two is left at its default status: active, not proposed.

  run jig knowledge accept feature-one feature-two
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: knowledge: not a proposed document: feature-two (status: active)"
  assert_file_contains .ai/knowledge/features/one.md "status: proposed"
}

test_accept_duplicate_id_counts_document_once() {
  km_setup
  jig knowledge new feature x --proposed >/dev/null

  run jig knowledge accept feature-x feature-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge accept: 1 accepted"
  assert_file_contains .ai/knowledge/features/x.md "status: active"
}

# --- knowledge reject ------------------------------------------------------------

test_reject_sets_status_rejected() {
  km_setup
  jig knowledge new feature smoke --proposed >/dev/null

  run jig knowledge reject feature-smoke
  assert_eq 0 "$RC"
  assert_contains "$OUT" "rejected   .ai/knowledge/features/smoke.md  (status: rejected)"
  assert_contains "$OUT" "knowledge reject: 1 rejected"
  assert_file_contains .ai/knowledge/features/smoke.md "status: rejected"
  assert_file .ai/knowledge/features/smoke.md
}

test_reject_refuses_active_document() {
  km_setup
  jig knowledge new feature smoke >/dev/null

  run jig knowledge reject feature-smoke
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: knowledge: not a proposed document: feature-smoke (status: active)"
  assert_file_contains .ai/knowledge/features/smoke.md "status: active"
}

test_reject_refuses_accepted_adr() {
  km_setup
  jig knowledge new adr my-decision >/dev/null

  run jig knowledge reject adr-0001-my-decision
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: knowledge: not a proposed document: adr-0001-my-decision (status: accepted)"
}

test_reject_requires_id_argument() {
  km_setup
  run jig knowledge reject
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig knowledge reject <id>"
}

test_reject_unknown_id_dies() {
  km_setup
  run jig knowledge reject no-such-id
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: no document with id: no-such-id"
}

# --- knowledge reject: multiple ids ---------------------------------------------

test_reject_multi_id_applies_all() {
  km_setup
  jig knowledge new feature one --proposed >/dev/null
  jig knowledge new feature two --proposed >/dev/null

  run jig knowledge reject feature-one feature-two
  assert_eq 0 "$RC"
  assert_contains "$OUT" "rejected   .ai/knowledge/features/one.md  (status: rejected)"
  assert_contains "$OUT" "rejected   .ai/knowledge/features/two.md  (status: rejected)"
  assert_contains "$OUT" "knowledge reject: 2 rejected"
  assert_file_contains .ai/knowledge/features/one.md "status: rejected"
  assert_file_contains .ai/knowledge/features/two.md "status: rejected"
}

test_reject_multi_id_with_bad_id_changes_nothing() {
  km_setup
  jig knowledge new feature one --proposed >/dev/null

  run jig knowledge reject feature-one no-such-id
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge: no document with id: no-such-id"
  assert_file_contains .ai/knowledge/features/one.md "status: proposed"
}

test_reject_multi_id_with_non_proposed_id_changes_nothing() {
  km_setup
  jig knowledge new feature one --proposed >/dev/null
  jig knowledge new feature two >/dev/null
  # feature-two is left at its default status: active, not proposed.

  run jig knowledge reject feature-one feature-two
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: knowledge: not a proposed document: feature-two (status: active)"
  assert_file_contains .ai/knowledge/features/one.md "status: proposed"
}

test_reject_duplicate_id_counts_document_once() {
  km_setup
  jig knowledge new feature x --proposed >/dev/null

  run jig knowledge reject feature-x feature-x
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge reject: 1 rejected"
  assert_file_contains .ai/knowledge/features/x.md "status: rejected"
}

test_reject_domain_pack_warns_about_slot() {
  km_setup
  jig knowledge new domain payments --proposed >/dev/null

  run jig knowledge reject domain-payments
  assert_eq 0 "$RC"
  assert_contains "$OUT" "rejected   .ai/knowledge/domains/payments/OVERVIEW.md  (status: rejected)"
  assert_contains "$OUT" "keeps its domain's only slot"
  assert_file_contains .ai/knowledge/domains/payments/OVERVIEW.md "status: rejected"
}

# --- knowledge check: rejected status --------------------------------------------

test_check_passes_rejected_non_adr_document() {
  km_setup
  cat > .ai/knowledge/features/rej.md <<'EOF'
---
id: feature-rej
type: feature
status: rejected
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge check: 1 documents, 0 failures, 0 warnings"
}

test_check_fails_unquoted_scalar_that_yaml_reads_as_a_mapping() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
summary: Terms: resolution, selector
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unquoted 'summary' reads as a nested mapping in YAML"
}

test_check_passes_quoted_scalar_containing_colon_space() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
summary: "Terms: resolution, selector"
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "0 failures"
}

test_check_ignores_colon_inside_a_block_list_item() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
summary: plain
paths:
  - "src/**: weird but quoted"
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_summary_written_by_the_command_survives_a_check() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge summary feature-a "Terms: resolution, selector"
  assert_eq 0 "$RC"
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_rejected_document_does_not_resolve_via_context() {
  km_setup
  # Progressive context requires the three mandatory globals (ADR-0021).
  for global in GLOSSARY ARCHITECTURE RULES; do
    printf '# %s\n' "$global" > ".ai/knowledge/$global.md"
  done
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: rejected
load: always
domains: [core]
---
EOF
  run jig context resolve --domains core --catalog
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "required:  .ai/knowledge/features/a.md"
  assert_not_contains "$OUT" "catalog:   .ai/knowledge/features/a.md"

  run jig context resolve --domains core --catalog --all
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/a.md  (load: always)"
}

# --- knowledge proposed ------------------------------------------------------------

test_proposed_lists_exactly_proposed_documents() {
  km_setup
  cat > .ai/knowledge/features/prop.md <<'EOF'
---
id: feature-prop
type: feature
status: proposed
summary: A proposed feature.
domains: [core]
---
EOF
  cat > .ai/knowledge/features/active.md <<'EOF'
---
id: feature-active
type: feature
status: active
summary: An active feature.
domains: [core]
---
EOF
  cat > .ai/knowledge/adr/0001-old.md <<'EOF'
---
id: adr-0001-old
type: adr
status: rejected
date: 2026-01-01
domains: [core]
---
EOF
  run jig knowledge proposed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "proposed:  feature-prop  (feature)  .ai/knowledge/features/prop.md  A proposed feature."
  assert_not_contains "$OUT" "feature-active"
  assert_not_contains "$OUT" "adr-0001-old"
  assert_contains "$OUT" "knowledge proposed: 1 proposed"
}

test_proposed_on_clean_tree_reports_none() {
  km_setup
  run jig knowledge proposed
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge proposed: nothing proposed"
}

# --- knowledge check: missing summary warning -------------------------------------

test_check_warns_missing_summary_on_active_document() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_contains "$OUT" "WARN .ai/knowledge/features/a.md: no summary; it reads as (no summary) in the context catalog"
}

test_check_no_summary_warning_when_summary_present() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
summary: "Does a thing."
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "no summary; it reads as"
}

test_check_no_summary_warning_for_unresolvable_status() {
  km_setup
  cat > .ai/knowledge/features/old.md <<'EOF'
---
id: feature-old
type: feature
status: superseded
domains: [core]
---
EOF
  cat > .ai/knowledge/features/prop.md <<'EOF'
---
id: feature-prop
type: feature
status: proposed
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "no summary; it reads as"
}

# --- knowledge inventory -----------------------------------------------------------

test_inventory_names_tracked_root_files_and_ignores_untracked() {
  km_setup
  printf '{}' > composer.json
  git add composer.json
  git commit -q -m "add composer.json"
  printf '{}' > package.json

  run jig knowledge inventory
  assert_eq 0 "$RC"
  # Root files are named, not counted: this is where manifests live, and recognising
  # what one means is the agent's judgement, not the command's.
  assert_contains "$OUT" "root:          composer.json"
  # Untracked: inventory reports tracked files throughout, with no exception for the
  # root, so an ignored or forgotten manifest does not read as part of the project.
  assert_not_contains "$OUT" "package.json"
  # And the root produces no tree group of its own.
  assert_not_contains "$OUT" "tree:          (root)"
}

test_inventory_instructions_lines_for_agents_and_claude_md_root_and_nested() {
  km_setup
  printf '# agents\n' > AGENTS.md
  printf '# claude\n' > CLAUDE.md
  mkdir -p sub
  printf '# sub agents\n' > sub/AGENTS.md
  printf '# notes\n' > NOTES.md
  git add AGENTS.md CLAUDE.md sub/AGENTS.md NOTES.md
  git commit -q -m "add instruction files"

  run jig knowledge inventory
  assert_eq 0 "$RC"
  assert_contains "$OUT" "instructions:  AGENTS.md"
  assert_contains "$OUT" "instructions:  CLAUDE.md"
  assert_contains "$OUT" "instructions:  sub/AGENTS.md"
  assert_not_contains "$OUT" "instructions:  NOTES.md"
}

test_inventory_tree_groups_directories_and_counts_singular_and_plural() {
  km_setup
  mkdir -p src/widget src/other lib
  printf 'a\n' > src/widget/a.php
  printf 'b\n' > src/widget/b.php
  printf 'c\n' > src/other/c.php
  printf 'd\n' > lib/only.php
  git add src lib
  git commit -q -m "add tree files"

  run jig knowledge inventory
  assert_eq 0 "$RC"
  assert_contains "$OUT" "tree:          src  (3 files)"
  assert_contains "$OUT" "tree:          lib  (1 file)"
  # README.md from the fixture is a root file, so it is named rather than grouped.
  assert_contains "$OUT" "root:          README.md"
  assert_not_contains "$OUT" "tree:          (root)"
}

test_inventory_scope_restricts_and_prefixes_labels() {
  km_setup
  mkdir -p scripts/lib other
  printf 'x\n' > scripts/top.sh
  printf 'y\n' > scripts/lib/a.sh
  printf 'z\n' > scripts/lib/b.sh
  printf 'w\n' > other/file.sh
  git add scripts other
  git commit -q -m "add scoped files"

  run jig knowledge inventory --scope scripts
  assert_eq 0 "$RC"
  assert_contains "$OUT" "root:          scripts/top.sh"
  assert_contains "$OUT" "tree:          scripts/lib  (2 files)"
  assert_not_contains "$OUT" "other/file.sh"
  assert_not_contains "$OUT" "tree:          other"
}

test_inventory_scope_absolute_path_dies() {
  km_setup
  run jig knowledge inventory --scope /etc
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--scope must be repository-relative:"
}

test_inventory_scope_dotdot_dies() {
  km_setup
  run jig knowledge inventory --scope "../escape"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "may not contain '..'"
}

test_inventory_scope_invalid_character_dies() {
  km_setup
  run jig knowledge inventory --scope "sc ripts"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid --scope"

  run jig knowledge inventory --scope "a;b"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "invalid --scope"
}

test_inventory_scope_nonexistent_directory_dies() {
  km_setup
  run jig knowledge inventory --scope does/not/exist
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no such directory:"
}

test_inventory_scope_requires_value() {
  km_setup
  run jig knowledge inventory --scope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "--scope requires a value"
}

test_inventory_unknown_flag_dies() {
  km_setup
  run jig knowledge inventory --bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge inventory: unknown argument: --bogus"
}

# --- knowledge usage --------------------------------------------------------------

test_knowledge_no_subcommand_usage_includes_accept_and_inventory() {
  km_setup
  run jig knowledge
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig knowledge proposed"
  assert_contains "$OUT" "jig knowledge accept <id>"
  assert_contains "$OUT" "jig knowledge reject <id>"
  assert_contains "$OUT" "jig knowledge inventory [--scope <dir>]"
}

test_knowledge_usage_shows_proposed_flag_on_both_new_lines() {
  km_setup
  run jig knowledge
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig knowledge new <feature|adr|convention> <slug> [--domains a,b] [--paths g,g] [--proposed]"
  assert_contains "$OUT" "jig knowledge new <domain|glossary|rule> <domain> [--paths g,g] [--proposed]"

  run jig knowledge new feature
  assert_eq 1 "$RC"
  assert_contains "$OUT" "[--proposed]"
}

test_requires_valid_chain_passes_clean() {
  km_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
domains: [core]
requires: [feature-b]
---
EOF
  cat > .ai/knowledge/features/b.md <<'EOF'
---
id: feature-b
type: feature
status: active
domains: [core]
requires: [feature-c]
---
EOF
  cat > .ai/knowledge/features/c.md <<'EOF'
---
id: feature-c
type: feature
status: active
domains: [core]
---
EOF
  run jig knowledge check
  assert_eq 0 "$RC"
}

test_sdd_stages_writer_preserves_metadata_body_and_is_idempotent() {
  km_setup
  cat > .ai/knowledge/features/stages.md <<'DOC'
---
id: feature-stages
type: feature
status: active
domains: [payments]
summary: Stage guidance.
---
Body stays intact.
DOC
  run jig knowledge stages add feature-stages implement
  assert_eq 0 "$RC"
  run jig knowledge stages add feature-stages implement
  assert_eq 0 "$RC"
  assert_eq 1 "$(grep -c '  - implement' .ai/knowledge/features/stages.md)"
  run jig knowledge check
  assert_eq 0 "$RC"
  run jig knowledge stages remove feature-stages implement
  assert_eq 0 "$RC"
  run jig knowledge stages remove feature-stages implement
  assert_eq 0 "$RC"
  assert_file_contains .ai/knowledge/features/stages.md 'stages: \[\]'
  assert_file_contains .ai/knowledge/features/stages.md 'Body stays intact.'
}

test_sdd_stages_invalid_metadata_and_writer_inputs_fail() {
  km_setup
  cat > .ai/knowledge/features/stages.md <<'DOC'
---
id: feature-stages
type: feature
status: active
domains: [payments]
stages: [deploy]
---
DOC
  run jig knowledge check
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'invalid stage: deploy'
  run jig knowledge stages add feature-stages deploy
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'invalid stage: deploy'
  run jig knowledge stages add unknown implement
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'no document with id'
  run jig knowledge stages set feature-stages implement
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'invalid operation'
  run jig knowledge stages add
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'usage:'
}

# --- knowledge changed (ADR-0022 precedent: the base is stated, never guessed) -

# A committed baseline plus one knowledge document already in history, so a
# test can distinguish "created since the base" from "was already there".
kmc_setup() {
  km_setup
  printf -- '---\nid: adr-0001-base\ntype: adr\nstatus: accepted\n---\n# base\n' \
    > .ai/knowledge/adr/0001-base.md
  git add -A
  git commit -q -m "knowledge baseline"
}

test_knowledge_changed_reports_a_created_document() {
  # The case the command exists for: a document written during consolidation
  # is still untracked, so `git diff` alone cannot see it.
  kmc_setup
  printf -- '---\nid: adr-0002-new\ntype: adr\nstatus: accepted\n---\n# new\n' \
    > .ai/knowledge/adr/0002-new.md

  run jig knowledge changed --base HEAD
  assert_eq 0 "$RC"
  assert_contains "$OUT" "created    .ai/knowledge/adr/0002-new.md"
  assert_contains "$OUT" "1 created, 0 modified, 0 renamed, 0 deleted"
}

test_knowledge_changed_reports_a_modified_document() {
  kmc_setup
  printf '\nAmended.\n' >> .ai/knowledge/adr/0001-base.md

  run jig knowledge changed --base HEAD
  assert_contains "$OUT" "modified   .ai/knowledge/adr/0001-base.md"
  assert_contains "$OUT" "0 created, 1 modified, 0 renamed, 0 deleted"
}

test_knowledge_changed_reports_a_deleted_document() {
  kmc_setup
  rm .ai/knowledge/adr/0001-base.md

  run jig knowledge changed --base HEAD
  assert_contains "$OUT" "deleted    .ai/knowledge/adr/0001-base.md"
  assert_contains "$OUT" "0 created, 0 modified, 0 renamed, 1 deleted"
}

test_knowledge_changed_reports_a_changed_global_document() {
  # jig_knowledge_docs deliberately omits the three global documents; this
  # report must not, because a consolidation that edits RULES.md is exactly
  # what it is for.
  kmc_setup
  printf '# Rules\n\n- something\n' > .ai/knowledge/RULES.md
  git add -A && git commit -q -m "add rules"
  printf -- '- another\n' >> .ai/knowledge/RULES.md

  run jig knowledge changed --base HEAD
  assert_contains "$OUT" "modified   .ai/knowledge/RULES.md"
}

test_knowledge_changed_ignores_non_knowledge_changes() {
  kmc_setup
  printf 'code\n' > somewhere.sh
  mkdir -p .ai/knowledge/features
  printf 'not markdown\n' > .ai/knowledge/features/notes.txt

  run jig knowledge changed --base HEAD
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "somewhere.sh"
  assert_not_contains "$OUT" "notes.txt"
  assert_contains "$OUT" "0 created, 0 modified, 0 renamed, 0 deleted"
}

test_knowledge_changed_requires_a_base() {
  kmc_setup
  run jig knowledge changed
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig knowledge changed"
}

test_knowledge_changed_names_itself_when_the_base_is_bad() {
  # The shared validator used to hardcode "task changes" in its message, which
  # would have told the user about a command they never ran.
  kmc_setup
  run jig knowledge changed --base no-such-ref
  assert_eq 1 "$RC"
  assert_contains "$OUT" "knowledge changed: cannot resolve commit"
  assert_not_contains "$OUT" "task changes"
}

test_knowledge_changed_takes_the_base_from_a_task() {
  kmc_setup
  jig task new T-1 >/dev/null
  # A filed task has no base_commit, so it cannot supply one.
  run jig knowledge changed --task T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no base_commit"
}

test_knowledge_changed_unknown_task_dies() {
  kmc_setup
  run jig knowledge changed --task nope
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task"
}

test_knowledge_changed_reports_a_rename_as_a_rename() {
  # A rename arrives from git as "<status>\t<old>\t<new>". Splitting on the
  # first tab alone printed both paths on one line and called it a
  # modification. For a knowledge document the filename carries the id, so the
  # rename usually *is* the change.
  kmc_setup
  git mv .ai/knowledge/adr/0001-base.md .ai/knowledge/adr/0001-renamed.md

  run jig knowledge changed --base HEAD
  assert_eq 0 "$RC"
  assert_contains "$OUT" "renamed    .ai/knowledge/adr/0001-base.md -> .ai/knowledge/adr/0001-renamed.md"
  assert_contains "$OUT" "0 created, 0 modified, 1 renamed, 0 deleted"
}

test_knowledge_changed_counts_a_file_once_when_both_layers_see_it() {
  # The tracked diff and the untracked listing are not disjoint: a file removed
  # from the index but left in the worktree is "deleted" to one and untracked
  # to the other, and was reported as created AND deleted — one file, two lines.
  kmc_setup
  git rm -q --cached .ai/knowledge/adr/0001-base.md

  run jig knowledge changed --base HEAD
  assert_contains "$OUT" "deleted    .ai/knowledge/adr/0001-base.md"
  assert_not_contains "$OUT" "created    .ai/knowledge/adr/0001-base.md"
  assert_contains "$OUT" "0 created, 0 modified, 0 renamed, 1 deleted"
}
