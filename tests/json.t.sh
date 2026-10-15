#!/bin/sh
# tests/json.t.sh — the JSON layer (scripts/lib/json.sh;
# adr-20261015-a-read-is-one-json-envelope; schemas/json.md).
#
# What is pinned here is the envelope every `--json` read prints and the
# string escaping every value goes through. The shape of each command's
# `data` is pinned in that command's own test file.
# shellcheck shell=bash
# The scripts these tests write are single-quoted on purpose: their expansions
# happen when the written script runs, not here.
# shellcheck disable=SC2016

# _json_script <file> <body> — a bash script that loads common.sh and json.sh
# the way the dispatcher does, then runs <body>.
_json_script() {
  {
    printf '#!/usr/bin/env bash\nset -eu\nset -o pipefail\n'
    printf '. "%s/scripts/lib/common.sh"\n' "$JIG_HOME"
    printf '. "%s/scripts/lib/json.sh"\n' "$JIG_HOME"
    printf '%s\n' "$2"
  } > "$1"
}

# _json_run_script <file> — run it, stdout in OUT, stderr in ERR, status in RC.
# Through files, as run() is (tests/lib/assert.sh).
_json_run_script() {
  set +e
  bash "$1" > out.txt 2> err.txt
  RC=$?
  set -e
  OUT=$(cat out.txt)
  ERR=$(cat err.txt)
}

# _json_no_time <envelope> — the envelope with its generated_at value replaced
# by T, after checking it has the documented form.
_json_no_time() {
  local at
  at=$(printf '%s\n' "$1" | sed -n 's/.*"generated_at":"\([^"]*\)".*/\1/p')
  case "$at" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) fail "generated_at is not a UTC timestamp: [$at] in $1" ;;
  esac
  printf '%s\n' "$1" | sed 's/"generated_at":"[^"]*"/"generated_at":"T"/'
}

# --- strings -----------------------------------------------------------------

test_json_quote_escapes_quotes_backslashes_and_control_bytes() {
  _json_script q.sh '
for v in "plain" "say \"hi\"" "C:\\temp\\new" "$(printf "a\nb\tc\rd")" "$(printf "x\001y\033z\037")" "ü & é"; do
  json_quote "$v"
  printf "%s\n" "$_JSON"
done'
  _json_run_script q.sh
  assert_eq 0 "$RC"
  assert_eq "$(cat <<'EOF'
"plain"
"say \"hi\""
"C:\\temp\\new"
"a\nb\tc\rd"
"x\u0001y\u001bz\u001f"
"ü & é"
EOF
)" "$OUT"
}

test_json_scalars_say_null_for_what_is_not_known() {
  _json_script s.sh '
json_str_or_null ""; printf "%s " "$_JSON"
json_str_or_null "x"; printf "%s " "$_JSON"
json_int_or_null ""; printf "%s " "$_JSON"
json_int_or_null "2"; printf "%s " "$_JSON"
json_int_or_null "08"; printf "%s " "$_JSON"
json_int_or_null "-1"; printf "%s " "$_JSON"
json_bool true; printf "%s " "$_JSON"
json_bool ""; printf "%s\n" "$_JSON"'
  _json_run_script s.sh
  assert_eq 0 "$RC"
  assert_eq 'null "x" null 2 8 null true false' "$OUT"
}

# --- the envelope ------------------------------------------------------------

test_json_run_wraps_the_producer_output_in_one_envelope_line() {
  _json_script e.sh '
produce() { printf "warned\n" >&2; printf "{\"n\":%s}\n" "$1"; }
json_run produce 3'
  _json_run_script e.sh
  assert_eq 0 "$RC"
  assert_eq '{"schema":1,"revision":null,"generated_at":"T","data":{"n":3}}' "$(_json_no_time "$OUT")"
  # One line on stdout, and what the producer said to a person stays on stderr.
  assert_eq 1 "$(wc -l < out.txt | tr -d ' ')"
  assert_eq "warned" "$ERR"
}

test_json_run_reports_a_refusal_as_an_error_instead_of_data() {
  _json_script r.sh '
produce() { jig_die "task list: invalid status: \"x\""; }
json_run produce'
  _json_run_script r.sh
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":null,"generated_at":"T","error":{"code":"failed","message":"task list: invalid status: \"x\""}}' "$(_json_no_time "$OUT")"
  assert_contains "$ERR" 'jig: error: task list: invalid status: "x"'
}

test_json_run_keeps_a_multiline_refusal_whole() {
  _json_script m.sh '
produce() { jig_die "$(printf "first line\nsecond line")"; }
json_run produce'
  _json_run_script m.sh
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"message":"first line\nsecond line"'
}

# The producer runs under set -e even though json_run must survive its
# failure: a failed command stops it, and nothing it printed before that is
# passed off as data.
test_json_run_stops_the_producer_at_its_first_failure() {
  _json_script f.sh '
produce() { printf "{\"half\":"; false; printf "1}\n"; }
json_run produce'
  _json_run_script f.sh
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":null,"generated_at":"T","error":{"code":"failed","message":"exited with status 1"}}' "$(_json_no_time "$OUT")"
}

test_json_run_refuses_a_producer_that_printed_nothing() {
  _json_script n.sh '
produce() { :; }
json_run produce'
  _json_run_script n.sh
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":null,"generated_at":"T","error":{"code":"failed","message":"printed no data"}}' "$(_json_no_time "$OUT")"
}

test_json_run_leaves_no_temporary_files() {
  mkdir tmp
  _json_script t.sh '
produce() { printf "1\n"; }
json_run produce'
  set +e
  TMPDIR="$PWD/tmp" bash t.sh > out.txt 2> err.txt
  RC=$?
  set -e
  assert_eq 0 "$RC"
  assert_eq "" "$(ls tmp)"
}
