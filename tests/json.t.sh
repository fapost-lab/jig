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
    # Not the project of a `jig verify` this run may be under: a script sets
    # its own (_json_rev_script), or has none and reads revision 0.
    printf 'unset JIG_PROJECT\n'
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
  assert_eq '{"schema":1,"revision":0,"generated_at":"T","data":{"n":3}}' "$(_json_no_time "$OUT")"
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
  assert_eq '{"schema":1,"revision":0,"generated_at":"T","error":{"code":"failed","message":"task list: invalid status: \"x\""}}' "$(_json_no_time "$OUT")"
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

# --- failure codes -----------------------------------------------------------

# A refusal names its code with jig_fail; the person reads the same text as
# from jig_die, with no trace of the code on stderr.
test_json_run_reports_the_code_a_refusal_names() {
  _json_script c.sh '
produce() { jig_fail usage "task list: unknown argument: --nope"; }
json_run produce'
  _json_run_script c.sh
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":0,"generated_at":"T","error":{"code":"usage","message":"task list: unknown argument: --nope"}}' "$(_json_no_time "$OUT")"
  assert_eq "jig: error: task list: unknown argument: --nope" "$ERR"
}

# Outside a producer jig_fail prints exactly what jig_die does: the text form
# of every command is unchanged by the codes.
test_jig_fail_outside_json_prints_only_the_message() {
  _json_script p.sh 'jig_fail not-initialised "project is not initialised; run: jig init"'
  _json_run_script p.sh
  assert_eq 1 "$RC"
  assert_eq "" "$OUT"
  assert_eq "jig: error: project is not initialised; run: jig init" "$ERR"
}

# The code belongs to the message the envelope reports: a coded refusal whose
# message was swallowed inside $(...) does not lend its code to the plain
# refusal that follows, and a visible one is replaced by the caller's own.
test_json_run_pairs_the_code_with_the_reported_message() {
  _json_script s.sh '
inner() { jig_fail not-a-repository "not inside a git repository"; }
produce() { x=$(inner 2>/dev/null) || jig_die "status: something else"; }
json_run produce'
  _json_run_script s.sh
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"failed","message":"status: something else"}}'
  _json_script v.sh '
inner() { jig_fail not-a-repository "not inside a git repository"; }
produce() { x=$(inner) || jig_fail usage "status: outer"; }
json_run produce'
  _json_run_script v.sh
  assert_eq 1 "$RC"
  assert_contains "$OUT" '"error":{"code":"usage","message":"status: outer"}}'
  assert_eq "$(printf 'jig: error: not inside a git repository\njig: error: status: outer')" "$ERR"
}

# Only a code jig_fail could name is reported; anything else is failed. A
# refusal printed by hand, or by a child jig, carries no code either.
test_json_run_falls_back_to_failed_for_what_is_not_a_code() {
  _json_script b.sh '
produce() { jig_fail "Not A Code" "bad"; }
json_run produce'
  _json_run_script b.sh
  assert_contains "$OUT" '"error":{"code":"failed","message":"bad"}}'
  _json_script u.sh '
produce() { jig_fail Usage "capital"; }
json_run produce'
  _json_run_script u.sh
  assert_contains "$OUT" '"error":{"code":"failed","message":"capital"}}'
  _json_script h.sh '
produce() { printf "jig: error: by hand\n" >&2; exit 1; }
json_run produce'
  _json_run_script h.sh
  assert_contains "$OUT" '"error":{"code":"failed","message":"by hand"}}'
  _json_script k.sh '
produce() { bash -c ". \"$JIG_LIB_UNDER_TEST/common.sh\"; jig_fail usage child" || exit 1; }
json_run produce'
  set +e
  JIG_LIB_UNDER_TEST="$JIG_HOME/scripts/lib" bash k.sh > out.txt 2> err.txt
  RC=$?
  set -e
  assert_eq 1 "$RC"
  assert_contains "$(cat out.txt)" '"error":{"code":"failed","message":"child"}}'
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
  assert_eq '{"schema":1,"revision":0,"generated_at":"T","error":{"code":"failed","message":"exited with status 1"}}' "$(_json_no_time "$OUT")"
}

test_json_run_refuses_a_producer_that_printed_nothing() {
  _json_script n.sh '
produce() { :; }
json_run produce'
  _json_run_script n.sh
  assert_eq 1 "$RC"
  assert_eq '{"schema":1,"revision":0,"generated_at":"T","error":{"code":"failed","message":"printed no data"}}' "$(_json_no_time "$OUT")"
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

# --- the clone's revision (adr-20261016-the-clone-revision-is-a-claimed-name) --
#
# jig_revision_read / jig_revision_bump (common.sh) and the funnel every writer
# calls, jig_record_changed. What must hold: every Jig write raises it, a read
# never does, no increment is lost to a concurrent writer, every worktree of a
# clone shares it, and a `--json` read takes it before the data.

# _json_rev_script <file> <body> — _json_script with config.sh loaded and
# JIG_PROJECT set to the directory the script runs in, as the dispatcher does.
_json_rev_script() {
  _json_script "$1" '. "$JIG_HOME/scripts/lib/config.sh"
JIG_PROJECT=$(pwd -P)
'"$2"
}

test_json_revision_is_zero_before_the_first_write_then_counts_each_one() {
  _json_rev_script r.sh '
jig_revision_read
jig_revision_bump
jig_revision_read
jig_revision_bump
jig_revision_read'
  local t0 first second
  t0=$(date +%s)
  _json_run_script r.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  assert_eq 0 "$(printf '%s\n' "$OUT" | sed -n 1p)"
  first=$(printf '%s\n' "$OUT" | sed -n 2p)
  second=$(printf '%s\n' "$OUT" | sed -n 3p)
  # The first write seeds with the time, so a counter lost with .ai/runtime
  # starts again above any value a consumer may still hold.
  [ "$first" -ge "$t0" ] || fail "seed $first is below the time $t0"
  assert_eq "$((first + 1))" "$second"
  assert_eq "$(printf '%s\n%s' "$first" "$second")" "$(ls .ai/runtime/revision)"
}

test_json_revision_starts_again_above_the_lost_one() {
  mkdir -p .ai/runtime/revision
  : > .ai/runtime/revision/5
  _json_rev_script r.sh '
jig_revision_read
rm -r .ai/runtime/revision
jig_revision_read
jig_revision_bump
jig_revision_read'
  _json_run_script r.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq 5 "$(printf '%s\n' "$OUT" | sed -n 1p)"
  assert_eq 0 "$(printf '%s\n' "$OUT" | sed -n 2p)"
  [ "$(printf '%s\n' "$OUT" | sed -n 3p)" -gt 5 ] || fail "the counter came round again: $OUT"
}

# Two names at once — two first writes in two seconds, or a leftover; the highest one
# is the revision, and the next write raises that one.
test_json_revision_reads_the_highest_of_two_names() {
  mkdir -p .ai/runtime/revision
  : > .ai/runtime/revision/7
  : > .ai/runtime/revision/12
  _json_rev_script r.sh '
jig_revision_read
jig_revision_bump
jig_revision_read'
  _json_run_script r.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq "$(printf '12\n13')" "$OUT"
}

# Leftovers — a claim whose clearing failed, a file of the first version, a
# name that is not a number — never change what is read, and the next raise
# clears the numbered ones below it.
test_json_revision_reads_past_stale_leftovers_and_clears_them() {
  mkdir -p .ai/runtime/revision/10 .ai/runtime/revision/11 .ai/runtime/revision/40 .ai/runtime/revision/45
  : > .ai/runtime/revision/20
  : > .ai/runtime/revision/notes
  _json_rev_script r.sh '
jig_revision_read
jig_revision_bump
jig_revision_read'
  _json_run_script r.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  assert_eq "$(printf '45\n46')" "$OUT"
  # Cleared only more than 16 below the claim: 10, 11 and the file 20 go,
  # 40 stays.
  assert_eq "$(printf '40\n45\n46\nnotes')" "$(ls .ai/runtime/revision)"
  # A claim is a file now (adr-20261023-a-claim-is-an-exclusive-create); the
  # directories an earlier version claimed are read and cleared as they are.
  assert_file .ai/runtime/revision/46
}

# A writer that read <n>, stalled while others claimed far past it and cleared
# the low names, would create <n+1> again — below the counter, counting
# nothing. Clearing <n+1> took a claim more than 16 above it, so a claim that
# finds the highest name that far above itself withdraws and claims again.
test_json_revision_catches_a_claim_made_stale_by_a_stall() {
  mkdir -p .ai/runtime/revision/120
  _json_rev_script s.sh '
eval "$(declare -f _jig_revision_scan | sed "1s/_jig_revision_scan/_jig_real_scan/")"
stalled=1
_jig_revision_scan() {
  if [ -n "$stalled" ]; then stalled=""; _JIG_REV=100; _JIG_REV_OLD=""; return 0; fi
  _jig_real_scan "$@"
}
jig_revision_bump
jig_revision_read'
  _json_run_script s.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  assert_eq 121 "$OUT"
  assert_eq "$(printf '120\n121')" "$(ls .ai/runtime/revision)"
}

# The same for a writer that found the directory empty and stalled before it
# seeded with the time, while the counter ran ahead of the clock.
test_json_revision_catches_a_seed_made_stale_by_a_stall() {
  local ahead
  ahead=$(( $(date +%s) + 1000 ))
  mkdir -p ".ai/runtime/revision/$ahead"
  _json_rev_script s.sh '
eval "$(declare -f _jig_revision_scan | sed "1s/_jig_revision_scan/_jig_real_scan/")"
stalled=1
_jig_revision_scan() {
  if [ -n "$stalled" ]; then stalled=""; _JIG_REV=""; _JIG_REV_OLD=""; return 0; fi
  _jig_real_scan "$@"
}
jig_revision_bump
jig_revision_read'
  _json_run_script s.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$ERR"
  assert_eq "$((ahead + 1))" "$OUT"
  assert_eq "$(printf '%s\n%s' "$ahead" "$((ahead + 1))")" "$(ls .ai/runtime/revision)"
}

# json_uutils_mkdir — put first on PATH a `mkdir` that answers as uutils' does at its
# worst: success though the directory is already there. Ubuntu 25.10 and later
# ship it, and two racing `mkdir`s both succeeded 110 times in 300 on
# ubuntu:26.04; this makes that race the rule, so a claim made by `mkdir` fails
# every time (adr-20261023-a-claim-is-an-exclusive-create).
json_uutils_mkdir() {
  local real
  real=$(command -v mkdir)
  mkdir -p uubin
  printf '#!/bin/sh\nexec "%s" -p "$@"\n' "$real" > uubin/mkdir
  chmod +x uubin/mkdir
  PATH="$PWD/uubin:$PATH"
}

test_json_revision_loses_no_increment_where_mkdir_excludes_nobody() {
  json_uutils_mkdir
  mkdir -p .ai/runtime/revision
  : > .ai/runtime/revision/100
  _json_rev_script w.sh '
i=0
while [ "$i" -lt 20 ]; do jig_revision_bump; i=$((i + 1)); done'
  bash w.sh 2> w1.err &
  local p1=$!
  bash w.sh 2> w2.err &
  local p2=$!
  wait "$p1" || fail "writer 1 failed: $(cat w1.err)"
  wait "$p2" || fail "writer 2 failed: $(cat w2.err)"
  _json_rev_script r.sh 'jig_revision_read'
  _json_run_script r.sh
  assert_eq 140 "$OUT"
}

# mkdir is the claim: of two writers that saw the same value one creates the
# next name and the other reads again. Nothing is lost, nothing waits. It
# starts from a file, the counter of the first, rename-based version — which
# lost increments here on Windows CI, where Git Bash emulates rename.
test_json_revision_loses_no_increment_to_concurrent_writers() {
  mkdir -p .ai/runtime/revision
  : > .ai/runtime/revision/100
  _json_rev_script w.sh '
i=0
while [ "$i" -lt 30 ]; do jig_revision_bump; i=$((i + 1)); done'
  bash w.sh 2> w1.err &
  local p1=$!
  bash w.sh 2> w2.err &
  local p2=$!
  bash w.sh 2> w3.err &
  local p3=$!
  wait "$p1" || fail "writer 1 failed: $(cat w1.err)"
  wait "$p2" || fail "writer 2 failed: $(cat w2.err)"
  wait "$p3" || fail "writer 3 failed: $(cat w3.err)"
  assert_eq "" "$(cat w1.err w2.err w3.err)"
  # The count, as a reader sees it: leftovers below it are clutter the design
  # accepts, not part of the answer.
  _json_rev_script r.sh 'jig_revision_read'
  _json_run_script r.sh
  assert_eq 190 "$OUT"
}

# jig_revision_claim (adr-20261019-the-queue-is-one-file-written-against-a-revision):
# a claim stands only when nobody wrote since the revision the caller read.
test_json_revision_claim_stands_only_on_the_revision_read() {
  mkdir -p .ai/runtime/revision/100
  _json_rev_script c.sh '
for e in 99 100 100; do
  rc=0; jig_revision_claim "$e" || rc=$?
  printf "%s:%s " "$e" "$rc"
done
jig_revision_read'
  _json_run_script c.sh
  assert_eq 0 "$RC" "$ERR"
  # 99: stale (100 is above it); 100: claims 101; 100 again: 101 is taken.
  assert_eq "99:1 100:0 100:1 101" "$OUT"
  # The stale claim of 100 was withdrawn: nothing but what was there and 101.
  assert_eq "$(printf '100\n101')" "$(ls .ai/runtime/revision)"
}

# _json_mkdir_log — script text that records, in mk.log, each revision name a
# claim is asked to create: a stale call must not create one even for a moment,
# which the names left afterwards cannot show (a name made and withdrawn again
# leaves nothing behind).
_json_mkdir_log='
eval "$(declare -f jig_claim_file | sed "1s/jig_claim_file/_jig_real_claim/")"
jig_claim_file() {
  case "${1:-}" in
    */revision/[0-9]*) printf "%s\n" "${1##*/}" >> mk.log ;;
  esac
  _jig_real_claim "$@"
}
'

# A cleared name created again, and a counter lost with .ai/runtime, are stale too.
test_json_revision_claim_is_stale_when_the_read_revision_is_gone() {
  mkdir -p .ai/runtime/revision/300
  _json_rev_script c.sh "$_json_mkdir_log"'
rc=0; jig_revision_claim 250 || rc=$?; printf "%s " "$rc"
rc=0; jig_revision_claim 300 || rc=$?; printf "%s\n" "$rc"'
  _json_run_script c.sh
  assert_eq "1 0" "$OUT"
  assert_eq "$(printf '300\n301')" "$(ls .ai/runtime/revision)"
  # The stale 250 asked for no name at all: only 300's claim of 301 did.
  assert_eq 301 "$(cat mk.log)"
  # A revision above the clone's claims nothing — not even a 401 withdrawn
  # again: the counter never goes up past a name nobody counted, nor down.
  rm -f mk.log
  _json_rev_script f.sh "$_json_mkdir_log"'
rc=0; jig_revision_claim 400 || rc=$?; printf "%s\n" "$rc"
jig_revision_read'
  _json_run_script f.sh
  assert_eq "$(printf '1\n301')" "$OUT"
  assert_eq "$(printf '300\n301')" "$(ls .ai/runtime/revision)"
  assert_no_file mk.log
  rm -rf .ai/runtime/revision
  _json_rev_script l.sh '
rc=0; jig_revision_claim 301 || rc=$?; printf "%s " "$rc"
rc=0; jig_revision_claim 0 || rc=$?; printf "%s\n" "$rc"
jig_revision_read'
  local t0
  t0=$(date +%s)
  _json_run_script l.sh
  assert_eq "1 0" "$(printf '%s\n' "$OUT" | sed -n 1p)"
  # Revision 0 claims the time, the seed a first raise would make.
  [ "$(printf '%s\n' "$OUT" | sed -n 2p)" -ge "$t0" ] || fail "claim of 0 did not seed with the time: $OUT"
  # And 0 is stale once anything was written.
  _json_rev_script z.sh 'rc=0; jig_revision_claim 0 || rc=$?; printf "%s\n" "$rc"; ls .ai/runtime/revision | wc -l | tr -d " "'
  _json_run_script z.sh
  assert_eq "$(printf '1\n1')" "$OUT"
}

# Two writers holding 0 claim different seconds, so mkdir alone does not keep
# the second out: one that claimed <now-1> between this call's empty scan and
# its mkdir of <now> has already landed. A claim of 0 therefore stands only
# alone; this one is stale, and stays as the highest name rather than lowering
# the revision by its withdrawal.
test_json_revision_claim_of_zero_stands_only_alone() {
  _json_rev_script z.sh '
date() {
  local now
  now=$(command date +%s)
  command mkdir "$(jig_revision_dir)/$((now - 1))"
  printf "%s\n" "$now"
}
rc=0; jig_revision_claim 0 || rc=$?; printf "%s\n" "$rc"
jig_revision_read'
  _json_run_script z.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq 1 "$(printf '%s\n' "$OUT" | sed -n 1p)"
  local now
  now=$(printf '%s\n' "$OUT" | sed -n 2p)
  assert_eq "$(printf '%s\n%s' "$((now - 1))" "$now")" "$(ls .ai/runtime/revision)"
}

# One counter per clone, in its main checkout: a write in a worktree is seen
# from the main checkout, and the worktree keeps no counter of its own.
test_json_revision_is_shared_by_every_worktree_of_the_clone() {
  fixture_repo
  git worktree add -q -b side ../wt
  _json_rev_script r.sh '
jig_revision_bump
jig_revision_read'
  cp r.sh ../wt/r.sh
  local main side
  (cd ../wt && bash r.sh > ../wt.out 2> ../wt.err) || fail "worktree run failed: $(cat ../wt.err)"
  side=$(cat ../wt.out)
  _json_run_script r.sh
  assert_eq 0 "$RC" "$ERR"
  main=$OUT
  assert_eq "$((side + 1))" "$main"
  assert_no_file ../wt/.ai/runtime/revision
}

# Not writable (a sandboxed worktree may not write the main checkout): the
# write already landed, so the command goes on, and says what was not counted.
test_json_revision_that_cannot_be_raised_warns_and_does_not_fail() {
  skip_unless_readonly_dirs
  mkdir -p .ai/runtime
  chmod a-w .ai/runtime
  _json_rev_script r.sh '
jig_revision_bump
printf "went on\n"'
  _json_run_script r.sh
  chmod u+w .ai/runtime
  assert_eq 0 "$RC"
  assert_eq "went on" "$OUT"
  assert_contains "$ERR" "jig: warning: could not raise the clone revision"
}

# Taken before the producer runs: a write that lands during the read must not
# be covered by the revision the envelope reports.
test_json_run_reports_the_revision_taken_before_the_data() {
  mkdir -p .ai/runtime/revision
  : > .ai/runtime/revision/41
  _json_rev_script e.sh '
produce() { jig_revision_bump; printf "{}\n"; }
json_run produce
jig_revision_read'
  _json_run_script e.sh
  assert_eq 0 "$RC" "$ERR"
  assert_eq '{"schema":1,"revision":41,"generated_at":"T","data":{}}' "$(_json_no_time "$(printf '%s\n' "$OUT" | sed -n 1p)")"
  assert_eq 42 "$(printf '%s\n' "$OUT" | sed -n 2p)"
}

# _json_rev — REV <- the revision `jig task list --json` reports.
_json_rev() {
  REV=$(jig task list --json 2>/dev/null | sed -n 's/^{"schema":1,"revision":\([0-9][0-9]*\),.*/\1/p')
  [ -n "$REV" ] || fail "no revision in the task list"
}

# _json_raised <what> — the revision rose since the last _json_rev/_json_raised.
_json_raised() {
  local before="$REV"
  _json_rev
  [ "$REV" -gt "$before" ] || fail "$1 did not raise the revision ($before -> $REV)"
}

# _json_kept <what> — the revision did not move.
_json_kept() {
  local before="$REV"
  _json_rev
  assert_eq "$before" "$REV" "$1 raised the revision"
}

test_json_revision_rises_with_every_jig_write_and_not_with_a_read() {
  fixture_jig_repo
  _json_rev
  assert_eq 0 "$REV"

  jig spec new idea-x >/dev/null 2>&1 || fail "spec new failed"
  _json_raised "spec new"
  jig task new t-1 --class T3 >/dev/null || fail "task new failed"
  _json_raised "task new"
  printf 'the design\n' | jig task artifact write t-1 design --from - >/dev/null
  _json_raised "task artifact write"
  printf 'more\n' | jig task artifact append t-1 design --from - >/dev/null
  _json_raised "task artifact append"
  jig task gate t-1 approved >/dev/null
  _json_raised "task gate"
  jig task set t-1 domains task >/dev/null
  _json_raised "task set"
  jig task pause t-1 --reason "later" >/dev/null 2>&1
  _json_raised "task pause"
  jig task resume t-1 >/dev/null 2>&1
  _json_raised "task resume"
  jig task autopilot t-1 start >/dev/null 2>&1
  _json_raised "task autopilot start"
  jig task finding add t-1 --severity P2 --where - --summary "a nit" >/dev/null
  _json_raised "task finding add"
  jig task finding set t-1 F1 fixed >/dev/null
  _json_raised "task finding set"
  printf '# Roadmap\n\n## Phase 1 — First\n\n- [ ] `t-1` — the task\n' > .ai/specs/idea-x/roadmap.md
  _json_kept "a file written by hand"
  jig spec link idea-x t-1 >/dev/null 2>&1 || fail "spec link failed"
  _json_raised "spec link"
  jig knowledge new convention c-1 --proposed >/dev/null 2>&1 || fail "knowledge new failed"
  _json_raised "knowledge new"
  jig knowledge reject convention-c-1 >/dev/null 2>&1 || fail "knowledge reject failed"
  _json_raised "knowledge reject"
  jig config set agent.git pr --local >/dev/null 2>&1 || fail "config set failed"
  _json_raised "config set"
  jig config unset agent.git --local >/dev/null 2>&1 || fail "config unset failed"
  _json_raised "config unset"
  jig queue set t-1 --priority 1 >/dev/null 2>&1 || fail "queue set failed"
  _json_raised "queue set"

  jig task list >/dev/null
  jig task show t-1 >/dev/null
  jig task findings t-1 >/dev/null
  jig spec list >/dev/null
  jig queue >/dev/null
  jig knowledge proposed >/dev/null 2>&1 || true
  _json_kept "a read"
}

test_json_revision_rises_once_with_a_housekeeping_run() {
  fixture_jig_repo
  jig task new t-1 >/dev/null
  _json_rev
  jig housekeeping >/dev/null 2>&1 || true
  _json_raised "housekeeping"
  jig housekeeping --dry-run >/dev/null 2>&1 || true
  _json_kept "housekeeping --dry-run"
}

# `jig status --json` reports the knowledge counts a full report saves
# (.ai/runtime/status-counts): new counts raise the revision, the same ones
# again do not, however often the page is redrawn.
test_json_revision_rises_when_the_saved_knowledge_counts_change() {
  fixture_jig_repo
  jig status --html >/dev/null 2>&1 || fail "status --html failed"
  assert_file .ai/runtime/status-counts
  _json_rev
  jig status --html >/dev/null 2>&1
  _json_kept "a redraw with the same counts"
  mkdir -p .ai/knowledge/features
  printf -- '---\nid: feature-by-hand\ntype: feature\nstatus: proposed\nsummary: x\n---\n# By hand\n' \
    > .ai/knowledge/features/by-hand.md
  _json_kept "a document written by hand"
  jig status --html >/dev/null 2>&1
  _json_raised "new saved counts"
}

# _json_unrecorded_writers <file>... — every function in <file>s that moves a
# file into place (`mv`) without recording the change: neither calling
# jig_record_changed nor a function that does, however deep. Every record Jig
# writes is a temporary file and an `mv` (conventions/shell.md), so this is
# where a writer that forgot the revision shows.
_json_unrecorded_writers() {
  awk '
    /^[A-Za-z_][A-Za-z_0-9]*\(\) *\{/ { fn = $1; sub(/\(\).*/, "", fn); names[++n] = fn; next }
    /^}/ { fn = ""; next }
    fn == "" { next }
    /^[ \t]*#/ { next }
    {
      body[fn] = body[fn] "\n" $0
      if ($0 ~ /(^|[;&|!{( \t])mv[ \t]/) moves[fn] = 1
    }
    END {
      rec["jig_record_changed"] = 1
      do {
        grew = 0
        for (i = 1; i <= n; i++) {
          f = names[i]
          if (f in rec) continue
          for (g in rec) {
            if (match(body[f], "(^|[^A-Za-z_0-9])" g "([^A-Za-z_0-9]|$)")) { rec[f] = 1; grew = 1; break }
          }
        }
      } while (grew)
      for (i = 1; i <= n; i++) if ((names[i] in moves) && !(names[i] in rec)) print names[i]
    }
  ' "$@"
}

test_json_no_jig_writer_misses_the_revision() {
  local lib="$JIG_HOME/scripts/lib" found
  found=$(_json_unrecorded_writers "$lib/config.sh" "$lib/forgecache.sh" "$lib/frontmatter.sh" "$lib/task.sh" "$lib/spec.sh" "$lib/knowledge.sh" "$lib/queue.sh")
  # The two that move something which is not a record yet: a partial restore
  # going to trash, and the build file knowledge new publishes and records.
  assert_eq "$(printf 'spec_trash_partial\nkm_source_link_body')" "$found" \
    "a writer that moves a record into place without jig_record_changed"
  # Housekeeping writes its log line by line; one raise when the run ends.
  assert_contains "$(cat "$lib/housekeeping.sh")" "jig_on_exit 'jig_revision_bump'"
}

# The guard above sees what it is for: a planted writer, and one that records
# through a helper two calls away.
test_json_unrecorded_writer_guard_sees_a_planted_writer() {
  cat > planted.sh <<'SH'
jig_record_changed() {
  :
}
_save() {
  mv "$1.tmp" "$1"
}
_noted() {
  mv "$1.tmp" "$1"
  _note
}
_note() {
  _deeper
}
_deeper() {
  jig_record_changed
}
_quiet() {
  # mv in a comment is not a write
  :
}
SH
  assert_eq "_save" "$(_json_unrecorded_writers planted.sh)"
}
