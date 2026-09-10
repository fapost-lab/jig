# Tests for scripts/lib/frontmatter.sh (schemas/frontmatter.md grammar).
# shellcheck shell=bash

# Source the library once per test via a subshell harness so each test can
# call fm_* directly through `run bash -c '...'`.
fm_harness() {
  # fm_harness <script> — run <script> with frontmatter.sh sourced.
  run bash -c '. "$JIG_HOME/scripts/lib/frontmatter.sh"; '"$1"
}

test_fm_has_true_for_well_formed_frontmatter() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
---
# Body
EOF
  fm_harness 'fm_has doc.md'
  assert_eq 0 "$RC"
}

test_fm_has_false_when_no_frontmatter() {
  cat > doc.md <<'EOF'
# Just a heading, no frontmatter.
EOF
  fm_harness 'fm_has doc.md'
  assert_eq 1 "$RC"
}

test_fm_has_false_when_unclosed() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
EOF
  fm_harness 'fm_has doc.md'
  assert_eq 1 "$RC"
}

test_fm_block_extracts_only_lines_between_delimiters() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
---
# Body

Not part of the block, even a literal `---` line below.

---
EOF
  fm_harness 'fm_block doc.md'
  assert_eq 0 "$RC"
  assert_eq "id: feature-x
type: feature" "$OUT"
}

test_fm_get_strips_trailing_comment_and_whitespace() {
  cat > doc.md <<'EOF'
---
id: feature-x   # trailing comment
type: feature
status: active
---
EOF
  fm_harness 'fm_get doc.md id'
  assert_eq 0 "$RC"
  assert_eq "feature-x" "$OUT"
}

test_fm_get_strips_surrounding_double_quotes() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
date: "2026-01-01"
---
EOF
  fm_harness 'fm_get doc.md date'
  assert_eq "2026-01-01" "$OUT"
}

test_fm_get_empty_when_key_absent() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
---
EOF
  fm_harness 'fm_get doc.md supersedes'
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

test_fm_get_empty_when_key_is_a_list() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
domains: [core, scripts]
---
EOF
  fm_harness 'fm_get doc.md domains'
  assert_eq "" "$OUT"
}

test_fm_get_empty_without_frontmatter() {
  cat > doc.md <<'EOF'
# No frontmatter
id: not-really-a-key
EOF
  fm_harness 'fm_get doc.md id'
  assert_eq "" "$OUT"
}

test_fm_list_inline_form() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains: [core, scripts, "core-ext"]
---
EOF
  fm_harness 'fm_list doc.md domains'
  assert_eq "core
scripts
core-ext" "$OUT"
}

test_fm_list_block_form() {
  cat > doc.md <<'EOF'
---
id: feature-x
paths:
  - "src/Flow/**"
  - scripts/knowledge*
supersedes: feature-old
---
EOF
  fm_harness 'fm_list doc.md paths'
  assert_eq "src/Flow/**
scripts/knowledge*" "$OUT"
}

test_fm_list_empty_when_key_absent() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
---
EOF
  fm_harness 'fm_list doc.md domains'
  assert_eq "" "$OUT"
}

test_fm_list_empty_inline_brackets() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains: []
---
EOF
  fm_harness 'fm_list doc.md domains'
  assert_eq "" "$OUT"
}

test_fm_keys_lists_top_level_keys_in_order() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
domains: [core]
paths:
  - "src/**"
---
EOF
  fm_harness 'fm_keys doc.md'
  assert_eq "id
type
status
domains
paths" "$OUT"
}

test_fm_body_start_points_after_closing_delimiter() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
---
# Body starts here
EOF
  fm_harness 'fm_body_start doc.md'
  assert_eq "5" "$OUT"
  assert_eq "# Body starts here" "$(sed -n '5p' doc.md)"
}

test_fm_body_start_is_one_without_frontmatter() {
  cat > doc.md <<'EOF'
# Body starts on line 1
EOF
  fm_harness 'fm_body_start doc.md'
  assert_eq "1" "$OUT"
}

# --- writers: fm_set -----------------------------------------------------------

test_fm_set_replaces_existing_scalar() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
---
Body text.
EOF
  fm_harness 'fm_set doc.md status deprecated'
  assert_eq 0 "$RC"
  assert_file_contains doc.md "status: deprecated"
  assert_not_contains "$(cat doc.md)" "status: active"
  assert_file_contains doc.md "Body text."
}

test_fm_set_appends_absent_scalar_just_before_closing_delimiter() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
---
Body text.
EOF
  fm_harness 'fm_set doc.md status active'
  assert_eq 0 "$RC"
  local block last_key
  block=$(sed -n '/^---$/,/^---$/p' doc.md | sed '1d;$d')
  assert_contains "$block" "status: active"
  last_key=$(printf '%s\n' "$block" | tail -n 1)
  assert_eq "status: active" "$last_key"
  assert_file_contains doc.md "Body text."
}

test_fm_set_on_document_without_frontmatter_returns_1() {
  cat > doc.md <<'EOF'
# No frontmatter
EOF
  fm_harness 'fm_set doc.md status active'
  assert_eq 1 "$RC"
}

test_fm_set_quotes_a_scalar_containing_colon_space() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
---
Body text.
EOF
  fm_harness 'fm_set doc.md summary "Terms: a, b"'
  assert_eq 0 "$RC"
  assert_file_contains doc.md 'summary: "Terms: a, b"'
  fm_harness 'fm_get doc.md summary'
  assert_eq "Terms: a, b" "$OUT"
}

test_fm_set_leaves_a_plain_scalar_unquoted() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
---
Body text.
EOF
  fm_harness 'fm_set doc.md status active'
  assert_eq 0 "$RC"
  assert_file_contains doc.md "status: active"
  assert_not_contains "$(cat doc.md)" 'status: "active"'
}

test_fm_set_does_not_quote_a_date() {
  cat > doc.md <<'EOF'
---
id: adr-0001-x
type: adr
---
Body text.
EOF
  fm_harness 'fm_set doc.md date 2026-09-09'
  assert_eq 0 "$RC"
  assert_file_contains doc.md "date: 2026-09-09"
}

test_fm_set_quotes_a_scalar_with_a_leading_indicator() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
---
Body text.
EOF
  fm_harness 'fm_set doc.md summary "- not a list item"'
  assert_eq 0 "$RC"
  assert_file_contains doc.md 'summary: "- not a list item"'
  fm_harness 'fm_get doc.md summary'
  assert_eq "- not a list item" "$OUT"
}

test_fm_set_refuses_a_scalar_containing_hash_or_quote() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
---
Body text.
EOF
  fm_harness 'fm_set doc.md summary "has # hash"'
  assert_eq 1 "$RC"
  fm_harness 'fm_set doc.md summary "has \" quote"'
  assert_eq 1 "$RC"
  assert_not_contains "$(cat doc.md)" "summary:"
}

# --- writers: fm_list_set -------------------------------------------------------

test_fm_list_set_converts_inline_list_to_block_list() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains: [core, scripts]
---
Body.
EOF
  fm_harness 'printf "core\nnew\n" | fm_list_set doc.md domains'
  assert_eq 0 "$RC"
  local content
  content=$(cat doc.md)
  assert_contains "$content" "domains:
  - core
  - new"
  assert_not_contains "$content" "domains: [core, scripts]"
  assert_file_contains doc.md "Body."
}

test_fm_list_set_empties_list_to_brackets() {
  cat > doc.md <<'EOF'
---
id: feature-x
paths:
  - "src/**"
  - README.md
---
Body.
EOF
  fm_harness 'printf "" | fm_list_set doc.md paths'
  assert_eq 0 "$RC"
  assert_contains "$(cat doc.md)" "paths: []"
  assert_not_contains "$(cat doc.md)" "  - "
  assert_file_contains doc.md "Body."
}

test_fm_list_set_quotes_items_with_special_characters_only() {
  cat > doc.md <<'EOF'
---
id: feature-x
paths: []
---
EOF
  fm_harness 'printf "src/**\nplain\n" | fm_list_set doc.md paths'
  assert_eq 0 "$RC"
  local content
  content=$(cat doc.md)
  assert_contains "$content" '  - "src/**"'
  assert_contains "$content" "  - plain"
}

test_fm_list_set_preserves_body_untouched() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains: [core]
---
# Heading

Body paragraph that must survive.
EOF
  fm_harness 'printf "core\nui\n" | fm_list_set doc.md domains'
  assert_eq 0 "$RC"
  assert_file_contains doc.md "# Heading"
  assert_file_contains doc.md "Body paragraph that must survive."
}

# --- writers: fm_list_add / fm_list_remove --------------------------------------

test_fm_list_add_returns_1_when_item_already_present() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains: [core]
---
EOF
  fm_harness 'fm_list_add doc.md domains core'
  assert_eq 1 "$RC"
  assert_contains "$(cat doc.md)" "domains: [core]"
}

test_fm_list_add_appends_new_item() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains: [core]
---
EOF
  fm_harness 'fm_list_add doc.md domains ui'
  assert_eq 0 "$RC"
  local content
  content=$(cat doc.md)
  assert_contains "$content" "  - core"
  assert_contains "$content" "  - ui"
}

test_fm_list_remove_returns_1_when_item_absent() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains: [core]
---
EOF
  fm_harness 'fm_list_remove doc.md domains ghost'
  assert_eq 1 "$RC"
  assert_contains "$(cat doc.md)" "domains: [core]"
}

test_fm_list_remove_drops_item_and_keeps_others() {
  cat > doc.md <<'EOF'
---
id: feature-x
domains:
  - core
  - ui
---
EOF
  fm_harness 'fm_list_remove doc.md domains ui'
  assert_eq 0 "$RC"
  local content
  content=$(cat doc.md)
  assert_contains "$content" "  - core"
  assert_not_contains "$content" "  - ui"
}

# Removing the last item leaves `grep -v` with nothing to select. Its exit 1
# used to become the function's status under `pipefail`, so a removal that
# actually happened was reported as "nothing removed".
test_fm_list_remove_reports_success_when_it_empties_the_list() {
  cat > doc.md <<'EOF'
---
id: feature-x
paths:
  - "src/**"
---
EOF
  fm_harness 'fm_list_remove doc.md paths "src/**"'
  assert_eq 0 "$RC"
  local content
  content=$(cat doc.md)
  assert_contains "$content" "paths: []"
  assert_not_contains "$content" "src/**"
}

# --- _fm_quote_item --------------------------------------------------------------

test_fm_quote_item_quotes_only_items_with_syntax_characters() {
  fm_harness '_fm_quote_item "src/**"; printf "|"; _fm_quote_item "core"'
  assert_eq 0 "$RC"
  assert_eq '"src/**"|core' "$OUT"
}
