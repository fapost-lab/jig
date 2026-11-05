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

test_fm_get_block_and_fm_list_block_read_a_block_fetched_once() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
domains:
  - core
  - ui
---
EOF
  # shellcheck disable=SC2016 # the $ vars are for the bash -c fm_harness runs, not this shell
  fm_harness 'block=$(fm_block doc.md); fm_get_block "$block" id; fm_get_block "$block" status; fm_list_block "$block" domains'
  assert_eq 0 "$RC"
  assert_eq "feature-x
active
core
ui" "$OUT"
}

test_fm_get_and_fm_list_agree_with_their_block_forms() {
  cat > doc.md <<'EOF'
---
id: feature-x
type: feature
status: active
paths:
  - "src/**"
  - "README.md"
---
EOF
  fm_harness 'fm_get doc.md id'
  first_id="$OUT"
  fm_harness 'fm_list doc.md paths'
  first_paths="$OUT"
  # shellcheck disable=SC2016 # the $ vars are for the bash -c fm_harness runs, not this shell
  fm_harness 'block=$(fm_block doc.md); fm_get_block "$block" id'
  assert_eq 0 "$RC"
  assert_eq "$first_id" "$OUT"
  # shellcheck disable=SC2016 # the $ vars are for the bash -c fm_harness runs, not this shell
  fm_harness 'block=$(fm_block doc.md); fm_list_block "$block" paths'
  assert_eq 0 "$RC"
  assert_eq "$first_paths" "$OUT"
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

# --- the readers answer without a process, and answer the same -----------------
#
# These pin the corners of the grammar the sed and awk readers answered, so that
# `jig context`, which reads every document in-process, resolves what it always did.

test_fm_get_cuts_a_value_at_its_first_hash_with_or_without_a_space() {
  printf -- '---\nspaced: value  # note\ntight: a#b\n---\n' > doc.md
  fm_harness 'fm_get doc.md spaced; fm_get doc.md tight'
  assert_eq 0 "$RC"
  assert_eq 'value
a' "$OUT"
}

test_fm_get_strips_one_pair_of_quotes_and_keeps_a_lone_quote() {
  printf -- '---\npair: "two words"\nlone: "\n---\n' > doc.md
  fm_harness 'fm_get doc.md pair; fm_get doc.md lone'
  assert_eq 0 "$RC"
  assert_eq 'two words
"' "$OUT"
}

test_fm_get_reads_the_first_of_a_repeated_key() {
  printf -- '---\nid: one\nid: two\n---\n' > doc.md
  fm_harness 'fm_get doc.md id'
  assert_eq 'one' "$OUT"
}

test_fm_get_does_not_read_a_key_that_only_ends_in_the_name() {
  printf -- '---\nmy_id: wrong\n  id: indented\n---\n' > doc.md
  fm_harness 'fm_get doc.md id'
  assert_eq '' "$OUT"
}

test_fm_list_inline_keeps_a_hash_and_drops_an_empty_item() {
  printf -- '---\npaths: [ "a/*", b#c , , d, ]tail\n---\n' > doc.md
  fm_harness 'fm_list doc.md paths'
  assert_eq 'a/*
b#c
d' "$OUT"
}

test_fm_list_inline_wins_over_a_block_list_under_the_same_key() {
  printf -- '---\npaths:\n  - block\npaths: [inline]\n---\n' > doc.md
  fm_harness 'fm_list doc.md paths'
  assert_eq 'inline' "$OUT"
}

test_fm_list_inline_never_closed_is_empty() {
  printf -- '---\npaths: [a, b\n---\n' > doc.md
  fm_harness 'fm_list doc.md paths'
  assert_eq '' "$OUT"
}

test_fm_list_block_ends_an_item_at_its_hash_and_stops_at_the_first_other_line() {
  printf -- '---\ndomains: # note\n  - x # why\n  - "y z"\n  -  w  \n  -nope\n  - after\n---\n' > doc.md
  fm_harness 'fm_list doc.md domains'
  assert_eq 'x
y z
w' "$OUT"
}

test_fm_has_sees_a_closing_delimiter_with_no_newline_after_it() {
  printf -- '---\nid: x\n---' > doc.md
  fm_harness 'fm_has doc.md && fm_get doc.md id'
  assert_eq 0 "$RC"
  assert_eq 'x' "$OUT"
}

test_fm_read_v_refuses_what_never_closes_and_leaves_the_variable_empty() {
  printf -- '---\nid: x\n' > doc.md
  # shellcheck disable=SC2016 # expanded by the harness's own bash
  fm_harness 'b=stale; fm_read_v b doc.md; printf "%s|%s" "$?" "$b"'
  assert_eq '1|' "$OUT"
}

test_fm_block_still_prints_what_never_closes() {
  printf -- '---\nid: x\n' > doc.md
  fm_harness 'fm_block doc.md'
  assert_eq 'id: x' "$OUT"
}

test_fm_v_readers_set_any_variable_the_caller_names() {
  printf -- '---\nid: x\npaths: [p]\n---\n' > doc.md
  # Whatever a reader calls its own locals, a caller's name must reach the caller.
  # shellcheck disable=SC2016 # expanded by the harness's own bash
  fm_harness 'fm_read_v block doc.md; fm_get_block_v val "$block" id; fm_list_block_v items "$block" paths; printf "%s %s" "$val" "$items"'
  assert_eq 'x p' "$OUT"
}

test_fm_readers_take_a_document_whose_lines_end_in_crlf() {
  printf -- '---\r\nid: x\r\nstatus: active\r\npaths:\r\n  - src/**\r\n---\r\nbody\r\n' > doc.md
  fm_harness 'fm_has doc.md && fm_get doc.md id; fm_get doc.md status; fm_list doc.md paths'
  assert_eq 0 "$RC"
  assert_eq 'x
active
src/**' "$OUT"
}

test_fm_block_joins_a_block_with_no_lines_to_nothing() {
  printf -- '---\n---\n' > doc.md
  # shellcheck disable=SC2016 # expanded by the harness's own bash
  # Under `set -u`, as jig runs: an empty array's expansion is an error on bash 3.2.
  fm_harness 'set -u; fm_has doc.md && fm_block doc.md; printf "[%s]" "$?"'
  assert_eq '[0]' "$OUT"
}

test_fm_block_keeps_blank_lines_inside_and_drops_them_at_the_end() {
  printf -- '---\n\nid: x\n\nnote: y\n\n\n---\n' > doc.md
  # shellcheck disable=SC2016 # expanded by the harness's own bash
  fm_harness 'b=$(fm_block doc.md); printf "[%s]" "$b"; fm_read_v r doc.md; printf "[%s]" "$r"'
  assert_eq '[
id: x

note: y][
id: x

note: y]' "$OUT"
}
