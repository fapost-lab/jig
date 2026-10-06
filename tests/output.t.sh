#!/bin/sh
# tests/output.t.sh — the shared output layer (scripts/lib/output.sh,
# adr-20261005-output-is-decorated-only-on-a-terminal).
#
# What these tests pin down is the machine contract: whatever is not a
# terminal gets the plain form, and the plain form of every block is the exact
# bytes a report printed before the layer existed. The terminal form is pinned
# too, so a command built on these blocks can rely on their shape.
# shellcheck shell=bash
# The tests set JIG_TERMINAL, NO_COLOR and TERM in a subshell for out_init,
# a sourced function, to read: shellcheck cannot see that use.
# shellcheck disable=SC2034

_output_lib() {
  # shellcheck source=../scripts/lib/output.sh
  . "$JIG_HOME/scripts/lib/output.sh"
}

ESC=$(printf '\033')

# _output_form — which form out_init chose, as one word on stdout.
_output_form() {
  if out_terminal; then printf 'terminal'; else printf 'plain'; fi
  printf ' color=%s\n' "$_OUT_COLOR"
}

# --- the decision ------------------------------------------------------------

test_output_a_file_gets_the_plain_form() {
  _output_lib
  ( unset JIG_TERMINAL NO_COLOR; TERM=xterm; out_init; _output_form ) > form.txt
  assert_eq "plain color=0" "$(cat form.txt)"
}

test_output_jig_terminal_1_forces_the_terminal_form_with_colour() {
  _output_lib
  ( unset NO_COLOR; TERM=xterm; JIG_TERMINAL=1; out_init; _output_form ) > form.txt
  assert_eq "terminal color=1" "$(cat form.txt)"
}

test_output_jig_terminal_0_forces_the_plain_form() {
  _output_lib
  ( unset NO_COLOR; TERM=xterm; JIG_TERMINAL=0; out_init; _output_form ) > form.txt
  assert_eq "plain color=0" "$(cat form.txt)"
}

# NO_COLOR takes the colour away, not the grouping: grouping is about how much
# is said, which a reader without colour needs as much as anyone.
test_output_no_color_keeps_the_terminal_form_without_colour() {
  _output_lib
  ( TERM=xterm; NO_COLOR=1; JIG_TERMINAL=1; out_init; _output_form ) > form.txt
  assert_eq "terminal color=0" "$(cat form.txt)"
}

test_output_an_empty_no_color_does_not_count() {
  _output_lib
  ( TERM=xterm; NO_COLOR=; JIG_TERMINAL=1; out_init; _output_form ) > form.txt
  assert_eq "terminal color=1" "$(cat form.txt)"
}

test_output_a_dumb_terminal_gets_no_colour() {
  _output_lib
  ( unset NO_COLOR; TERM=dumb; JIG_TERMINAL=1; out_init; _output_form ) > form.txt
  assert_eq "terminal color=0" "$(cat form.txt)"
}

# The measurement itself, without the override: a real pseudo-terminal from
# script(1). The BSD form (macOS) and the util-linux form take the command
# differently; Git Bash has neither, and there the override tests above are
# what runs.
test_output_a_real_terminal_gets_the_terminal_form() {
  local probe
  probe="unset JIG_TERMINAL; . '$JIG_HOME/scripts/lib/output.sh'; out_init; if out_terminal; then echo FORM=terminal; else echo FORM=plain; fi"
  if script -qec true /dev/null >/dev/null 2>&1 </dev/null; then
    script -qec "bash -c \"$probe\"" /dev/null </dev/null > tty.txt 2>&1 || true
  elif script -q /dev/null true >/dev/null 2>&1 </dev/null; then
    script -q /dev/null bash -c "$probe" </dev/null > tty.txt 2>&1 || true
  else
    skip "script(1) cannot make a pseudo-terminal here"
  fi
  assert_contains "$(tr -d '\r' < tty.txt)" "FORM=terminal"
}

# --- the plain form is today's bytes ------------------------------------------

test_output_plain_blocks_are_the_bytes_doctor_always_printed() {
  _output_lib
  (
    JIG_TERMINAL=0; out_init
    out_status ok "git: git version 2.48.1"
    out_status warn "global jig: not found on PATH"
    out_detail fix "jig init"
    out_status fail "upgrade check: cannot determine pending state"
    out_group ok "2 passed" "git" "git identity"
    out_gap
    out_summary "doctor: 1 ok, 1 warn, 1 fail"
  ) > plain.txt
  {
    printf '%-6s%s: %s\n' ok git "git version 2.48.1"
    printf '%-6s%s: %s\n' warn "global jig" "not found on PATH"
    printf '      fix: %s\n' "jig init"
    printf '%-6s%s: %s\n' fail "upgrade check" "cannot determine pending state"
    printf 'ok    2 passed: git, git identity\n'
    printf '\n'
    printf 'doctor: %d ok, %d warn, %d fail\n' 1 1 1
  } > expected.txt
  cmp expected.txt plain.txt || fail "plain blocks differ: $(diff expected.txt plain.txt)"
}

test_output_a_group_without_names_prints_nothing() {
  _output_lib
  ( JIG_TERMINAL=0; out_init; out_group ok "0 passed" ) > group.txt
  assert_eq "" "$(cat group.txt)"
}

# --- the terminal form ----------------------------------------------------------

test_output_colour_marks_the_level_word_and_keeps_the_alignment() {
  _output_lib
  (
    unset NO_COLOR; TERM=xterm; JIG_TERMINAL=1; out_init
    out_status ok "a: b"
    out_status warn "c: d"
    out_status fail "e: f"
    out_status ask "g?"
    out_detail fix "g"
    out_summary "h"
  ) > color.txt
  {
    printf '%s[32mok%s[0m    a: b\n' "$ESC" "$ESC"
    printf '%s[33mwarn%s[0m  c: d\n' "$ESC" "$ESC"
    printf '%s[1;31mfail%s[0m  e: f\n' "$ESC" "$ESC"
    printf '%s[36mask%s[0m   g?\n' "$ESC" "$ESC"
    printf '      %s[1mfix:%s[0m g\n' "$ESC" "$ESC"
    printf '%s[1mh%s[0m\n' "$ESC" "$ESC"
  } > expected.txt
  cmp expected.txt color.txt || fail "coloured blocks differ: $(diff expected.txt color.txt)"
}

# Colour is never the only carrier: without it the terminal form is the same
# words in the same columns, and no escape byte at all.
test_output_without_colour_the_terminal_form_has_no_escape() {
  _output_lib
  (
    NO_COLOR=1; JIG_TERMINAL=1; out_init
    out_status warn "c: d"
    out_detail fix "g"
    out_summary "h"
  ) > nocolor.txt
  assert_not_contains "$(cat nocolor.txt)" "$ESC"
  assert_contains "$(cat nocolor.txt)" "warn  c: d"
}

# --- sections ---------------------------------------------------------------------

test_output_section_blocks_are_ascii_without_a_utf8_locale() {
  _output_lib
  (
    LC_ALL=C; NO_COLOR=1; JIG_TERMINAL=1; out_init
    out_heading "jig 1.0 | demo" ok "nothing needs you"
    out_section "Tasks" "$(out_join "2 active" "1 finished")"
    out_row dim 4 T1 bold 8 t-a warn 0 "$(out_join worktree "3 uncommitted")"
    out_row dim 4 T2 bold 8 a-long-id plain 0 ""
    out_row dim 4 "$OUT_MARK" plain 0 "current task: none"
    printf '%s\n' "$OUT_MORE"
  ) > ascii.txt
  {
    printf 'jig 1.0 | demo%66s\n' "nothing needs you"
    printf '\n-- Tasks  (2 active | 1 finished) %s\n' "----------------------------------------------"
    printf '  T1  t-a     worktree | 3 uncommitted\n'
    printf '  T2  a-long-id\n'
    printf '  .   current task: none\n'
    printf '...\n'
  } > expected.txt
  cmp expected.txt ascii.txt || fail "ascii sections differ: $(diff expected.txt ascii.txt)"
}

# The plain form never draws anything but ASCII, whatever the locale says.
test_output_section_marks_are_utf8_only_on_a_utf8_terminal() {
  local n
  n=$(LC_ALL=en_US.UTF-8 bash -c 'x=$(printf "\302\267"); printf %s "${#x}"' 2>/dev/null)
  [ "$n" = 1 ] || skip "en_US.UTF-8 is not available here"
  _output_lib
  (
    unset LC_ALL LC_CTYPE; LANG=en_US.UTF-8; NO_COLOR=1; JIG_TERMINAL=1; out_init
    out_section "Install"
    printf '%s|%s|%s\n' "$(out_join a b)" "$OUT_MARK" "$OUT_MORE"
    JIG_TERMINAL=0; out_init
    out_section "Install"
    printf '%s|%s|%s\n' "$(out_join a b)" "$OUT_MARK" "$OUT_MORE"
    unset LANG; LC_CTYPE=en_US.UTF-8; JIG_TERMINAL=1; out_init
    printf '%s\n' "$OUT_MARK"
    # A locale this shell cannot take is not UTF-8, whatever its name says.
    LC_CTYPE=C; LC_CTYPE=xx_XX.UTF-8; out_init
    printf '%s\n' "$OUT_MARK"
  ) > marks.txt 2>/dev/null
  local r d
  r=$(printf '\342\224\200')
  d=$(printf '\302\267')
  assert_contains "$(cat marks.txt)" "$r$r Install $r$r$r"
  assert_contains "$(cat marks.txt)" "a $d b|$d|$(printf '\342\200\246')"
  assert_contains "$(cat marks.txt)" "-- Install ---"
  assert_contains "$(cat marks.txt)" "a | b|.|..."
  assert_eq "$d" "$(tail -n 2 marks.txt | sed -n 1p)"
  assert_eq "." "$(sed -n '$p' marks.txt)"
}

test_output_section_colours_the_title_and_dims_the_rule() {
  _output_lib
  (
    unset NO_COLOR; LC_ALL=C; TERM=xterm; JIG_TERMINAL=1; out_init
    out_heading "jig" warn "2 items need you"
    out_section "Tasks" "2 active"
    out_row ok 6 ok warn 0 "x"
  ) > color.txt
  assert_contains "$(cat color.txt)" "${ESC}[33m2 items need you${ESC}[0m"
  assert_contains "$(cat color.txt)" "${ESC}[2m--${ESC}[0m ${ESC}[1;36mTasks${ESC}[0m  (2 active) ${ESC}[2m---"
  assert_contains "$(cat color.txt)" "  ${ESC}[32mok${ESC}[0m    ${ESC}[33mx${ESC}[0m"
}
