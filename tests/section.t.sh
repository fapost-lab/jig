#!/bin/sh
# tests/section.t.sh — the marked instructions section parser
# (scripts/lib/section.sh, adr-20260924-jig-owns-a-marked-section-of-the-instructions).
#
# The safety of the whole feature rests on one thing these tests pin down:
# the text used for hashing, for comparing and for writing is the same text.
# A hash taken over different bytes than the comparison uses is exactly how an
# upgrade would overwrite somebody's edit while believing the section
# untouched, and CRLF is the way that happens in practice (ADR-0037).

_section_lib() {
  # shellcheck source=../scripts/lib/section.sh
  . "$JIG_HOME/scripts/lib/section.sh"
}

# A file with a well-formed pair: two lines of the project's own text on
# either side, so every test can also check that nothing outside moved.
_section_fixture() {
  printf '# Our own title\n\nIntro line.\n<!-- jig:begin -->\nframework line one\nframework line two\n<!-- jig:end -->\n\n## Our own rules\n\nUse tabs.\n' > "$1"
}

# --- state -------------------------------------------------------------------

test_section_state_ok() {
  _section_lib
  _section_fixture AGENTS.md
  assert_eq ok "$(jig_section_state AGENTS.md)"
}

test_section_state_absent_without_markers() {
  _section_lib
  printf '# Our own rules\n\nUse tabs.\n' > AGENTS.md
  assert_eq absent "$(jig_section_state AGENTS.md)"
}

test_section_state_absent_when_the_file_is_missing() {
  _section_lib
  assert_eq absent "$(jig_section_state AGENTS.md)"
}

test_section_state_malformed_with_two_begins() {
  _section_lib
  printf '<!-- jig:begin -->\na\n<!-- jig:begin -->\nb\n<!-- jig:end -->\n' > AGENTS.md
  assert_eq malformed "$(jig_section_state AGENTS.md)"
}

test_section_state_malformed_without_an_end() {
  _section_lib
  printf '<!-- jig:begin -->\na\n' > AGENTS.md
  assert_eq malformed "$(jig_section_state AGENTS.md)"
}

test_section_state_malformed_when_end_precedes_begin() {
  _section_lib
  printf '<!-- jig:end -->\na\n<!-- jig:begin -->\n' > AGENTS.md
  assert_eq malformed "$(jig_section_state AGENTS.md)"
}

test_section_state_ok_on_a_crlf_file() {
  _section_lib
  printf '<!-- jig:begin -->\r\na\r\n<!-- jig:end -->\r\n' > AGENTS.md
  assert_eq ok "$(jig_section_state AGENTS.md)"
}

# --- read and hash -----------------------------------------------------------

test_section_read_returns_only_the_region() {
  _section_lib
  _section_fixture AGENTS.md
  assert_eq "framework line one
framework line two" "$(jig_section_read AGENTS.md)"
}

# The recorded hash must not depend on what core.autocrlf did to the checkout,
# or a Windows clone would read as modified on its first upgrade and every
# improvement would stop there.
test_section_hash_is_the_same_for_crlf_and_lf() {
  _section_lib
  printf '<!-- jig:begin -->\na\nb\n<!-- jig:end -->\n' > lf.md
  printf '<!-- jig:begin -->\r\na\r\nb\r\n<!-- jig:end -->\r\n' > crlf.md
  assert_eq "$(jig_section_hash lf.md)" "$(jig_section_hash crlf.md)"
}

test_section_hash_changes_with_the_text() {
  _section_lib
  printf '<!-- jig:begin -->\na\n<!-- jig:end -->\n' > one.md
  printf '<!-- jig:begin -->\nb\n<!-- jig:end -->\n' > two.md
  if [ "$(jig_section_hash one.md)" = "$(jig_section_hash two.md)" ]; then
    fail "two different sections hashed the same"
  fi
}

# --- report state ------------------------------------------------------------

test_section_report_state_unmarked_without_a_record() {
  _section_lib
  _section_fixture AGENTS.md
  assert_eq unmarked "$(jig_section_report_state AGENTS.md "")"
}

test_section_report_state_unmarked_without_markers() {
  _section_lib
  printf '# Our own rules\n' > AGENTS.md
  assert_eq unmarked "$(jig_section_report_state AGENTS.md "deadbeef AGENTS.md")"
}

test_section_report_state_current_and_modified() {
  _section_lib
  _section_fixture AGENTS.md
  assert_eq current \
    "$(jig_section_report_state AGENTS.md "$(jig_section_hash AGENTS.md) AGENTS.md")"
  assert_eq modified "$(jig_section_report_state AGENTS.md "deadbeef AGENTS.md")"
}

# --- write -------------------------------------------------------------------

test_section_write_replaces_only_the_region() {
  _section_lib
  _section_fixture AGENTS.md
  printf 'brand new line\n' > new.txt
  jig_section_write AGENTS.md new.txt
  assert_eq "brand new line" "$(jig_section_read AGENTS.md)"
  assert_file_contains AGENTS.md "# Our own title"
  assert_file_contains AGENTS.md "Use tabs."
  assert_not_contains "$(cat AGENTS.md)" "framework line one"
  # The markers survive, or the next upgrade could never find the region.
  assert_eq ok "$(jig_section_state AGENTS.md)"
}

test_section_write_keeps_the_files_own_line_endings() {
  _section_lib
  printf 'own\r\n<!-- jig:begin -->\r\nold\r\n<!-- jig:end -->\r\ntail\r\n' > AGENTS.md
  printf 'new one\nnew two\n' > new.txt
  jig_section_write AGENTS.md new.txt
  # own / begin / new one / new two / end / tail — every one of the six lines
  # still ends CRLF. A mixed-ending file would show up as a diff over the
  # whole file on the reader's next commit, which is the visible half of the
  # damage; the invisible half is that the markers stop matching.
  assert_eq 6 "$(grep -c "$(printf '\r')$" AGENTS.md | tr -d ' ')"
  assert_eq 6 "$(wc -l < AGENTS.md | tr -d ' ')"
  assert_eq "new one
new two" "$(jig_section_read AGENTS.md)"
}

test_section_write_refuses_a_malformed_file() {
  _section_lib
  printf '<!-- jig:begin -->\na\n<!-- jig:begin -->\nb\n<!-- jig:end -->\n' > AGENTS.md
  cp AGENTS.md before.md
  printf 'new\n' > new.txt
  if jig_section_write AGENTS.md new.txt; then
    fail "jig_section_write accepted a malformed marker pair"
  fi
  assert_eq "$(cat before.md)" "$(cat AGENTS.md)"
}

test_section_write_refuses_an_unmarked_file() {
  _section_lib
  printf '# Our own rules\n' > AGENTS.md
  printf 'new\n' > new.txt
  if jig_section_write AGENTS.md new.txt; then
    fail "jig_section_write accepted a file with no markers"
  fi
  assert_eq "# Our own rules" "$(cat AGENTS.md)"
}

test_section_write_leaves_no_temp_file_behind() {
  _section_lib
  _section_fixture AGENTS.md
  printf 'new\n' > new.txt
  jig_section_write AGENTS.md new.txt
  assert_eq 0 "$(find . -name 'AGENTS.md.tmp.*' | wc -l | tr -d ' ')"
}

# A file whose last line has no newline: awk reads it as a record all the same,
# so the region must come out identical and the replacement must not swallow
# the last line of the project's own text.
test_section_handles_a_file_without_a_trailing_newline() {
  _section_lib
  printf '<!-- jig:begin -->\nold\n<!-- jig:end -->\ntail with no newline' > AGENTS.md
  assert_eq ok "$(jig_section_state AGENTS.md)"
  assert_eq old "$(jig_section_read AGENTS.md)"
  printf 'new\n' > new.txt
  jig_section_write AGENTS.md new.txt
  assert_eq new "$(jig_section_read AGENTS.md)"
  assert_file_contains AGENTS.md "tail with no newline"
}

# The hash must not move when only whitespace outside the region does, or a
# project would read as modified for a reason that is not its own.
test_section_hash_ignores_text_outside_the_region() {
  _section_lib
  printf 'head\n<!-- jig:begin -->\na\n<!-- jig:end -->\ntail\n' > one.md
  printf 'different head\n<!-- jig:begin -->\na\n<!-- jig:end -->\nother tail\n' > two.md
  assert_eq "$(jig_section_hash one.md)" "$(jig_section_hash two.md)"
}
