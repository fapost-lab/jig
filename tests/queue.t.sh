# Tests for `jig queue` (scripts/lib/queue.sh): one queue per clone, written
# only by this command and checked against the clone revision its caller read
# (adr-20261019-the-queue-is-one-file-written-against-a-revision).
# shellcheck shell=bash
# shellcheck disable=SC2016 # single-quoted fixture text deliberately keeps its backticks literal

# _q_setup [ids...] — an installed project with a filed task for each id.
_q_setup() {
  local id
  fixture_jig_repo
  for id in "$@"; do
    fixture_task "$id" "task/$id" active
  done
}

# _q_epic <spec> <task>... — a spec whose roadmap declares an open epic, and
# tasks linked to it by their Spec: line.
_q_epic() {
  local spec="$1" id
  shift
  mkdir -p ".ai/specs/$spec"
  printf '# %s\n' "$spec" > ".ai/specs/$spec/spec.md"
  printf '# Roadmap\n\nEpic: epic/%s\n\n## Phase 1 — One\n' "$spec" > ".ai/specs/$spec/roadmap.md"
  for id in "$@"; do
    fixture_task "$id" "task/$id" active
    printf '# %s\n\nSpec: .ai/specs/%s/ — Phase 1\n' "$id" "$spec" > ".ai/workspace/tasks/$id/task.md"
  done
}

# _q_items — the item lines of the queue file, as `<ref> <level> <position> <priority>`.
_q_items() {
  awk -F '\t' '$1 == "item" { print $2, $3, $4, $5 }' .ai/runtime/queue
}

# _q_json <args...> — run `jig queue <args> --json`; stdout in OUT, stderr in
# ERR, status in RC.
_q_json() {
  set +e
  jig queue "$@" --json > q.out 2> q.err
  RC=$?
  set -e
  OUT=$(cat q.out)
  ERR=$(cat q.err)
}

# _q_rev — REV <- the clone's revision, as a read reports it.
_q_rev() {
  REV=$(jig task list --json 2>/dev/null | sed -n 's/^{"schema":1,"revision":\([0-9][0-9]*\),.*/\1/p')
  [ -n "$REV" ] || fail "no revision in the task list"
}

# _q_code — the error.code of the envelope in OUT.
_q_code() {
  printf '%s\n' "$OUT" | sed -n 's/.*"error":{"code":"\([^"]*\)".*/\1/p'
}

# --- the listing -----------------------------------------------------------------

test_queue_is_empty_before_any_write() {
  _q_setup a
  run jig queue
  assert_eq 0 "$RC" "$OUT"
  assert_eq "queue: empty" "$OUT"
  run jig queue list
  assert_eq "queue: empty" "$OUT"
  assert_no_file .ai/runtime/queue
}

test_queue_list_shows_order_priority_and_what_waits() {
  _q_setup a b
  _q_epic big t1 t2
  jig queue set a --priority 1 >/dev/null
  jig queue set epic:big --priority 0 >/dev/null
  jig queue move t2 --bottom >/dev/null
  jig queue move t1 --top >/dev/null
  jig queue depend b --on a --reason "needs the format" >/dev/null
  run jig queue
  assert_eq 0 "$RC" "$OUT"
  assert_eq "$(printf '%s\n' \
    'task:a  P1' \
    'epic:big  P0' \
    '  task:t1  -' \
    '  task:t2  -' \
    'task:b  -' \
    '    waits for task:a: needs the format')" "$OUT"
}

test_queue_list_names_an_epic_whose_tasks_are_queued_without_it() {
  _q_setup
  _q_epic big t1
  jig queue move t1 --top >/dev/null
  run jig queue
  assert_eq "$(printf '%s\n' 'epic:big  (not queued)' '  task:t1  -')" "$OUT"
}

# --- the listing as JSON -----------------------------------------------------------

# _q_data — the envelope in OUT with its generated_at blanked.
_q_data() {
  printf '%s\n' "$OUT" | sed 's/"generated_at":"[^"]*"/"generated_at":"T"/'
}

test_queue_list_json_of_an_empty_queue() {
  _q_setup a
  _q_rev
  _q_json list
  assert_eq 0 "$RC" "$ERR"
  assert_eq "{\"schema\":1,\"revision\":$REV,\"generated_at\":\"T\",\"data\":{\"items\":[]}}" "$(_q_data)"
  # Bare `jig queue --json` is the listing too.
  _q_json
  assert_eq "{\"schema\":1,\"revision\":$REV,\"generated_at\":\"T\",\"data\":{\"items\":[]}}" "$(_q_data)"
  assert_no_file .ai/runtime/queue
}

# The whole shape: the top level by position, then each epic's level, every
# item the object a write answers with, dependencies ordered by `on`.
test_queue_list_json_is_every_item_in_the_writers_order() {
  _q_setup a b
  _q_epic big t1 t2
  jig queue set a --priority 1 >/dev/null
  jig queue set epic:big --priority 0 >/dev/null
  jig queue move t2 --bottom >/dev/null
  jig queue move t1 --top >/dev/null
  jig queue depend b --on epic:big --reason 'say "why"' >/dev/null
  jig queue depend b --on a --reason "needs the format" >/dev/null
  _q_rev
  _q_json list
  assert_eq 0 "$RC" "$ERR"
  local items
  items=$(printf '%s,' \
    '{"ref":"task:a","kind":"task","id":"a","level":null,"position":100,"priority":1,"depends_on":[]}' \
    '{"ref":"epic:big","kind":"epic","id":"big","level":null,"position":200,"priority":0,"depends_on":[]}' \
    '{"ref":"task:b","kind":"task","id":"b","level":null,"position":300,"priority":null,"depends_on":[{"on":"epic:big","reason":"say \"why\""},{"on":"task:a","reason":"needs the format"}]}' \
    '{"ref":"task:t1","kind":"task","id":"t1","level":"epic:big","position":50,"priority":null,"depends_on":[]}' \
    '{"ref":"task:t2","kind":"task","id":"t2","level":"epic:big","position":100,"priority":null,"depends_on":[]}')
  assert_eq "{\"schema\":1,\"revision\":$REV,\"generated_at\":\"T\",\"data\":{\"items\":[${items%,}]}}" "$(_q_data)"
}

# One item shape: what the listing prints for an item is byte for byte what
# the write that touched it answered.
test_queue_list_json_item_is_the_object_a_write_answers_with() {
  _q_setup a b
  _q_epic big t1
  jig queue depend t1 --on b --reason "b first" >/dev/null
  _q_json set t1 --priority 3
  assert_eq 0 "$RC" "$ERR"
  local written
  written=$(printf '%s\n' "$OUT" | sed 's/.*"item":\(.*\)}}$/\1/')
  _q_json list
  assert_contains "$OUT" "$written"
}

# A line of a kind the reader does not know (the pause requests to come) is
# left out of the JSON, which stays one valid value.
test_queue_list_json_ignores_lines_of_a_kind_it_does_not_know() {
  _q_setup a
  printf '# jig queue 1\nrequest\ttask:a\tpause\tlater "now"\nitem\ttask:a\t-\t100\t-\nfuture\tx\n' > .ai/runtime/queue
  _q_json list
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"data":{"items":[{"ref":"task:a","kind":"task","id":"a","level":null,"position":100,"priority":null,"depends_on":[]}]}}'
  assert_not_contains "$OUT" "request"
  assert_not_contains "$OUT" "future"
}

test_queue_list_json_refuses_another_format_version() {
  _q_setup a
  printf '# jig queue 2\nitem\ttask:a\t-\t100\t-\tnew-field\n' > .ai/runtime/queue
  _q_json list
  assert_eq 1 "$RC"
  assert_eq failed "$(_q_code)"
  assert_contains "$OUT" "in another format than this jig reads"
}

# A read writes nothing: the revision it reports is the one after it.
test_queue_list_json_raises_no_revision() {
  _q_setup a
  jig queue set a --priority 1 >/dev/null
  _q_rev
  local before=$REV
  _q_json list
  assert_contains "$OUT" "\"revision\":$before,"
  _q_rev
  assert_eq "$before" "$REV" "a JSON listing raised the revision"
}

# The queue is the clone's: a worktree reads the main checkout's file, with
# the same revision a task list there reports.
test_queue_list_json_from_a_worktree_reads_the_clones_queue() {
  _q_setup
  _q_epic big
  git add -A >/dev/null
  git commit -q -m "spec"
  jig queue set epic:big --priority 3 >/dev/null
  _q_rev
  local wt="$JIG_TEST_TMP.wtjson"
  git worktree add -q -b side-json "$wt"
  (cd "$wt" && jig queue list --json > "$wt.out" 2>&1) || fail "worktree read failed: $(cat "$wt.out")"
  assert_contains "$(cat "$wt.out")" "\"revision\":$REV,"
  assert_contains "$(cat "$wt.out")" '"items":[{"ref":"epic:big","kind":"epic","id":"big","level":null,"position":100,"priority":3,"depends_on":[]}]'
}

# --- the file ---------------------------------------------------------------------

test_queue_file_lives_in_runtime_in_its_one_format() {
  _q_setup a b
  jig queue set a --priority 2 >/dev/null
  jig queue depend b --on a --reason "after a" >/dev/null
  assert_eq "$(printf '# jig queue 1 — written by `jig queue` only; do not edit by hand\nitem\ttask:a\t-\t100\t2\nitem\ttask:b\t-\t200\t-\ndep\ttask:b\ttask:a\tafter a')" \
    "$(cat .ai/runtime/queue)"
  # Not under git: .ai/runtime is ignored in every project.
  assert_eq "" "$(git status --porcelain --untracked-files=all .ai/runtime)"
}

test_queue_keeps_the_lines_of_a_kind_it_does_not_know() {
  _q_setup a b
  printf '# jig queue 1\nitem\ttask:a\t-\t100\t-\nhold\ttask:a\tlater\n' > .ai/runtime/queue
  jig queue set b --priority 4 >/dev/null
  assert_contains "$(cat .ai/runtime/queue)" "$(printf 'hold\ttask:a\tlater')"
  assert_eq "$(printf 'task:a - 100 -\ntask:b - 200 4')" "$(_q_items)"
}

test_queue_refuses_to_rewrite_another_format_version() {
  _q_setup a
  printf '# jig queue 2\nitem\ttask:a\t-\t100\t-\tnew-field\n' > .ai/runtime/queue
  local before
  before=$(cat .ai/runtime/queue)
  run jig queue set a --priority 1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "in another format than this jig writes"
  assert_eq "$before" "$(cat .ai/runtime/queue)"
  assert_eq "" "$(find .ai/runtime -name 'queue.tmp.*')"
}

# One queue per clone: a write from a worktree lands in the main checkout's
# file, and the worktree keeps none of its own.
test_queue_is_shared_by_every_worktree_of_the_clone() {
  _q_setup
  _q_epic big
  git add -A >/dev/null
  git commit -q -m "spec"
  # Beside the test's own directory, under its name: ../wt would be shared by
  # every test of the run, and another test's worktree there makes this one fail.
  local wt="$JIG_TEST_TMP.wt"
  git worktree add -q -b side "$wt"
  (cd "$wt" && jig queue set epic:big --priority 3 > "$wt.out" 2>&1) || fail "worktree write failed: $(cat "$wt.out")"
  assert_eq "epic:big - 100 3" "$(_q_items)"
  assert_no_file "$wt/.ai/runtime/queue"
}

# --- set ---------------------------------------------------------------------------

test_queue_set_adds_at_the_bottom_and_changes_only_the_priority() {
  _q_setup a b
  run jig queue set a --priority 0
  assert_eq 0 "$RC" "$OUT"
  assert_eq "queue: task:a at 100 on the top level, priority 0" "$OUT"
  jig queue set b --priority 5 >/dev/null
  jig queue set a --priority none >/dev/null
  assert_eq "$(printf 'task:a - 100 -\ntask:b - 200 5')" "$(_q_items)"
}

test_queue_set_refuses_what_is_not_a_priority() {
  _q_setup a
  local p
  for p in 6 -1 high 01; do
    _q_json set a --priority "$p"
    assert_eq 1 "$RC" "priority $p"
    assert_eq usage "$(_q_code)" "priority $p"
  done
  _q_json set a
  assert_eq usage "$(_q_code)"
  assert_no_file .ai/runtime/queue
}

# --- move --------------------------------------------------------------------------

test_queue_move_takes_the_gap_between_neighbours_and_moves_nothing_else() {
  _q_setup a b c
  jig queue move a --bottom >/dev/null
  jig queue move b --bottom >/dev/null
  jig queue move c --bottom >/dev/null
  assert_eq "$(printf 'task:a - 100 -\ntask:b - 200 -\ntask:c - 300 -')" "$(_q_items)"
  jig queue move c --after a >/dev/null
  assert_eq "$(printf 'task:a - 100 -\ntask:c - 150 -\ntask:b - 200 -')" "$(_q_items)"
  jig queue move b --before a >/dev/null
  assert_eq "$(printf 'task:b - 50 -\ntask:a - 100 -\ntask:c - 150 -')" "$(_q_items)"
  jig queue move a --top >/dev/null
  assert_eq "$(printf 'task:a - 25 -\ntask:b - 50 -\ntask:c - 150 -')" "$(_q_items)"
}

# No integer left between two neighbours: the one command respaces the level
# in its one write, so no consumer ever has to renumber with many commands.
test_queue_move_respaces_a_level_with_no_gap_in_the_same_write() {
  _q_setup a b c
  printf '# jig queue 1\nitem\ttask:a\t-\t100\t1\nitem\ttask:b\t-\t101\t-\nitem\ttask:c\t-\t500\t-\n' > .ai/runtime/queue
  jig queue move c --after a >/dev/null
  assert_eq "$(printf 'task:a - 100 1\ntask:c - 200 -\ntask:b - 300 -')" "$(_q_items)"
}

test_queue_move_refuses_an_anchor_it_cannot_place_against() {
  _q_setup a b
  _q_epic big t1
  jig queue move a --bottom >/dev/null
  jig queue move t1 --bottom >/dev/null
  _q_json move b --after nobody
  assert_eq not-found "$(_q_code)"
  _q_json move b --after c-not-queued
  assert_eq not-found "$(_q_code)"
  fixture_task idle task/idle active
  _q_json move b --after idle
  assert_eq not-found "$(_q_code)"
  assert_contains "$OUT" "task:idle is not in the queue"
  _q_json move a --after t1
  assert_eq usage "$(_q_code)"
  assert_contains "$OUT" "on another level"
  _q_json move a --after a
  assert_eq usage "$(_q_code)"
  _q_json move a --top --bottom
  assert_eq usage "$(_q_code)"
  _q_json move a
  assert_eq usage "$(_q_code)"
}

# --- epics as a level --------------------------------------------------------------

test_queue_puts_a_task_on_its_epics_level() {
  _q_setup loose
  _q_epic big t1 t2
  jig queue move t1 --bottom >/dev/null
  jig queue move epic:big --bottom >/dev/null
  jig queue move loose --top >/dev/null
  jig queue move t2 --before t1 >/dev/null
  assert_eq "$(printf 'task:loose - 50 -\nepic:big - 100 -\ntask:t2 epic:big 50 -\ntask:t1 epic:big 100 -')" "$(_q_items)"
}

# A finished epic no longer has tasks built on it: they are on the top level.
test_queue_puts_a_task_of_a_finished_epic_on_the_top_level() {
  _q_setup
  _q_epic big t1
  printf '# Roadmap\n\nEpic: epic/big — finished\n' > .ai/specs/big/roadmap.md
  jig queue move t1 --bottom >/dev/null
  assert_eq "task:t1 - 100 -" "$(_q_items)"
}

# The level is task start's answer (jig_task_epic): a record that makes it a
# guess is refused, as task start refuses it, and nothing is written.
test_queue_refuses_a_task_whose_epic_would_be_a_guess() {
  _q_setup
  _q_epic big t1
  _q_epic other t2
  printf '# t1\n\nSpec: .ai/specs/big/ — Phase 1\nSpec: .ai/specs/other/ — Phase 1\n' > .ai/workspace/tasks/t1/task.md
  _q_json move t1 --bottom
  assert_eq failed "$(_q_code)"
  assert_contains "$OUT" "more than one spec"
  printf '# Roadmap\n\nEpic: epic/other\nEpic: epic/else\n' > .ai/specs/other/roadmap.md
  _q_json move t2 --bottom
  assert_eq failed "$(_q_code)"
  assert_contains "$OUT" "more than one epic"
  assert_no_file .ai/runtime/queue
}

# A spec this checkout does not have is the ADR's accepted risk: the task goes
# on the top level, where task start would refuse to cut it.
test_queue_puts_a_task_of_a_spec_not_here_on_the_top_level() {
  _q_setup
  _q_epic big t1
  rm -rf .ai/specs/big
  jig queue move t1 --bottom >/dev/null
  assert_eq "task:t1 - 100 -" "$(_q_items)"
}

test_queue_refuses_a_reference_to_nothing() {
  _q_setup a
  mkdir -p .ai/specs/plain
  printf '# Roadmap\n' > .ai/specs/plain/roadmap.md
  _q_json set nobody --priority 1
  assert_eq not-found "$(_q_code)"
  _q_json set epic:plain --priority 1
  assert_eq not-found "$(_q_code)"
  assert_contains "$OUT" "declares no epic"
  _q_json set epic:missing --priority 1
  assert_eq not-found "$(_q_code)"
  _q_json set "../x" --priority 1
  assert_eq usage "$(_q_code)"
  _q_json set "spec:a" --priority 1
  assert_eq usage "$(_q_code)"
  assert_no_file .ai/runtime/queue
}

# --- dependencies ------------------------------------------------------------------

test_queue_depend_needs_a_reason_on_one_line() {
  _q_setup a b
  _q_json depend b --on a
  assert_eq usage "$(_q_code)"
  _q_json depend b --on a --reason "  "
  assert_eq usage "$(_q_code)"
  jig queue depend b --on a --reason "$(printf 'first\tline\nsecond')" >/dev/null
  assert_eq "$(printf 'dep\ttask:b\ttask:a\tfirst line second')" "$(grep '^dep' .ai/runtime/queue)"
  # Again: the reason is replaced, never a second line.
  jig queue depend b --on a --reason "the format" >/dev/null
  assert_eq "$(printf 'dep\ttask:b\ttask:a\tthe format')" "$(grep '^dep' .ai/runtime/queue)"
}

test_queue_depend_refuses_itself_and_a_cycle() {
  _q_setup a b c
  jig queue depend b --on a --reason "1" >/dev/null
  jig queue depend c --on b --reason "2" >/dev/null
  _q_json depend a --on c --reason "3"
  assert_eq usage "$(_q_code)"
  assert_contains "$OUT" "would close a cycle"
  _q_json depend a --on a --reason "4"
  assert_eq usage "$(_q_code)"
  assert_eq 2 "$(grep -c '^dep' .ai/runtime/queue)"
}

test_queue_undepend_and_remove() {
  _q_setup a b c
  jig queue depend b --on a --reason "1" >/dev/null
  jig queue depend c --on b --reason "2" >/dev/null
  run jig queue undepend b --on a
  assert_eq 0 "$RC" "$OUT"
  assert_eq "queue: task:b no longer waits for task:a" "$OUT"
  _q_json undepend b --on a
  assert_eq not-found "$(_q_code)"
  # Removing an item drops what it waits for; what waits for it stays.
  jig queue depend b --on a --reason "1" >/dev/null
  run jig queue remove b
  assert_eq "queue: task:b removed" "$OUT"
  assert_eq "task:c - 200 -" "$(_q_items)"
  assert_eq "$(printf 'dep\ttask:c\ttask:b\t2')" "$(grep '^dep' .ai/runtime/queue)"
  _q_json remove b
  assert_eq not-found "$(_q_code)"
}

# A task gone to trash, or a spec retired, must still be taken out of the queue.
test_queue_takes_out_an_item_whose_task_or_epic_is_gone() {
  _q_setup a b
  _q_epic big
  jig queue depend b --on a --reason "1" >/dev/null
  jig queue set epic:big --priority 1 >/dev/null
  rm -rf .ai/workspace/tasks/a .ai/workspace/tasks/b .ai/specs/big
  _q_json undepend b --on a
  assert_eq 0 "$RC" "$ERR"
  _q_json remove b
  assert_eq 0 "$RC" "$ERR"
  _q_json remove epic:big
  assert_eq 0 "$RC" "$ERR"
  assert_eq "" "$(_q_items)"
  _q_json remove "../x"
  assert_eq usage "$(_q_code)"
}

# --- writes against a revision ----------------------------------------------------

test_queue_write_answers_in_the_envelope() {
  _q_setup a b
  _q_epic big t1
  jig queue depend t1 --on b --reason "b first" >/dev/null
  jig queue set t1 --priority 2 >/dev/null
  _q_rev
  _q_json move t1 --top --revision "$REV"
  assert_eq 0 "$RC" "$ERR"
  assert_eq "{\"schema\":1,\"revision\":$REV,\"generated_at\":\"T\",\"data\":{\"ref\":\"task:t1\",\"item\":{\"ref\":\"task:t1\",\"kind\":\"task\",\"id\":\"t1\",\"level\":\"epic:big\",\"position\":100,\"priority\":2,\"depends_on\":[{\"on\":\"task:b\",\"reason\":\"b first\"}]}}}" \
    "$(printf '%s\n' "$OUT" | sed 's/"generated_at":"[^"]*"/"generated_at":"T"/')"
  _q_json remove a
  assert_eq 1 "$RC"
  assert_eq not-found "$(_q_code)"
  jig queue set a --priority 1 >/dev/null
  _q_json remove a
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"data":{"ref":"task:a","item":null}}'
}

# The write lands, then the revision rises past the claim it was made under, so
# a read that took the claim with the old queue sees a change again.
test_queue_write_raises_the_revision_past_its_claim() {
  _q_setup a
  _q_rev
  local before=$REV
  jig queue set a --priority 1 --revision "$before" >/dev/null || fail "write failed"
  _q_rev
  [ "$REV" -ge "$((before + 2))" ] || fail "revision $before -> $REV: not past the claim"
  jig queue >/dev/null
  local after=$REV
  _q_rev
  assert_eq "$after" "$REV" "a listing raised the revision"
}

test_queue_write_with_a_stale_revision_is_refused_and_changes_nothing() {
  _q_setup a b
  _q_rev
  local old=$REV
  jig queue set a --priority 1 >/dev/null
  local before
  before=$(cat .ai/runtime/queue)
  _q_rev
  local now=$REV
  _q_json set b --priority 2 --revision "$old"
  assert_eq 1 "$RC"
  assert_eq "{\"schema\":1,\"revision\":$now,\"generated_at\":\"T\",\"error\":{\"code\":\"stale-revision\",\"message\":\"queue: the clone changed since revision $old; read the queue again and retry\"}}" \
    "$(printf '%s\n' "$OUT" | sed 's/"generated_at":"[^"]*"/"generated_at":"T"/')"
  assert_eq "$before" "$(cat .ai/runtime/queue)"
  _q_rev
  assert_eq "$now" "$REV" "a refused write moved the revision"
  assert_eq "" "$(find .ai/runtime -name 'queue.tmp.*')"
  # Any Jig write since counts, not only a queue write.
  jig task set a domains task >/dev/null
  _q_json set b --priority 2 --revision "$now"
  assert_eq stale-revision "$(_q_code)"
  # And a person's text form says it too.
  run jig queue set b --priority 2 --revision "$now"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: queue: the clone changed since revision $now"
}

# Two consumers holding one revision: exactly one write lands, the other is
# told it is stale — the conflict a dashboard shows.
test_queue_two_writes_with_one_revision_land_once() {
  _q_setup a b
  jig queue set a --priority 1 >/dev/null
  _q_rev
  jig queue move b --top --revision "$REV" --json > w1.out 2>/dev/null &
  local p1=$!
  jig queue move a --top --revision "$REV" --json > w2.out 2>/dev/null &
  local p2=$!
  local r1=0 r2=0
  wait "$p1" || r1=$?
  wait "$p2" || r2=$?
  if [ "$r1" -eq 0 ]; then
    assert_eq 1 "$r2"
    assert_contains "$(cat w2.out)" '"code":"stale-revision"'
  else
    assert_eq 0 "$r2"
    assert_contains "$(cat w1.out)" '"code":"stale-revision"'
  fi
}

# A revision held from before `.ai/runtime` was lost names a clone that is gone.
test_queue_write_after_the_runtime_was_lost_is_refused() {
  _q_setup a
  jig queue set a --priority 1 >/dev/null
  _q_rev
  rm -rf .ai/runtime/revision .ai/runtime/queue
  _q_json set a --priority 2 --revision "$REV"
  assert_eq stale-revision "$(_q_code)"
  assert_no_file .ai/runtime/queue
  # Revision 0 is what a read reports now, and a write against it lands.
  _q_json set a --priority 2 --revision 0
  assert_eq 0 "$RC" "$ERR"
}

test_queue_refuses_what_is_not_a_revision() {
  _q_setup a
  local r
  for r in 08 -1 abc 1.5 ""; do
    _q_json set a --priority 1 --revision "$r"
    assert_eq usage "$(_q_code)" "revision [$r]"
  done
  _q_json set a --priority 1 --revision
  assert_eq usage "$(_q_code)"
  assert_no_file .ai/runtime/queue
}

test_queue_refuses_what_it_does_not_take() {
  _q_setup a
  _q_json bogus
  assert_eq usage "$(_q_code)"
  _q_json set a --priority 1 --before a
  assert_eq usage "$(_q_code)"
  _q_json list extra
  assert_eq usage "$(_q_code)"
  _q_json set
  assert_eq usage "$(_q_code)"
  _q_json set --priority 1
  assert_eq usage "$(_q_code)"
}

test_queue_outside_an_initialised_project_is_refused() {
  fixture_repo
  _q_json set a --priority 1
  assert_eq not-initialised "$(_q_code)"
}

# --- pause requests (adr-20261019-a-pause-request-is-honoured-at-the-stage-boundary)

# _q_request_line <id> — the request line of task <id>, its time replaced by T.
_q_request_line() {
  awk -F '\t' -v r="task:$1" '$1 == "request" && $2 == r { $4 = "T"; print }' OFS='\t' .ai/runtime/queue
}

test_queue_request_writes_one_line_beside_items_and_dependencies() {
  _q_setup a b
  jig queue set a --priority 2 >/dev/null
  jig queue depend b --on a --reason "after a" >/dev/null
  run jig queue request b pause --reason "$(printf 'lunch\tbreak')"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "queue: pause of task:b requested at "
  assert_eq "$(printf 'request\ttask:b\tpause\tT\tlunch break')" "$(_q_request_line b)"
  # When: UTC, to the second, so a consumer shows its age.
  awk -F '\t' '$1 == "request" { print $4 }' .ai/runtime/queue \
    | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || fail "not a UTC time"
  # In canonical order, after the dependencies; the task need not be queued.
  jig queue request task:a pause >/dev/null
  assert_eq "$(printf 'item\nitem\ndep\nrequest\nrequest')" "$(awk -F '\t' 'NR > 1 { print $1 }' .ai/runtime/queue)"
  assert_eq "$(printf 'request\ttask:a\tpause\tT\t')" "$(_q_request_line a)"
  # Every other write keeps the requests, and a remove of the item too.
  jig queue move a --bottom >/dev/null
  jig queue remove b >/dev/null
  assert_eq "$(printf 'request\ttask:b\tpause\tT\tlunch break')" "$(_q_request_line b)"
  assert_eq "$(printf 'task:a - 300 2')" "$(_q_items)"
}

test_queue_request_is_sticky_and_cancelled_only_by_cancel() {
  _q_setup a
  jig queue request a pause >/dev/null
  local first
  first=$(awk -F '\t' '$1 == "request" { print $4 }' .ai/runtime/queue)
  _q_json request a pause
  assert_eq 1 "$RC"
  assert_eq already-exists "$(_q_code)"
  assert_eq "$first" "$(awk -F '\t' '$1 == "request" { print $4 }' .ai/runtime/queue)"
  run jig queue cancel task:a pause
  assert_eq 0 "$RC" "$OUT"
  assert_eq "queue: pause request of task:a cancelled" "$OUT"
  assert_eq "" "$(_q_request_line a)"
  _q_json cancel a pause
  assert_eq 1 "$RC"
  assert_eq not-found "$(_q_code)"
  # A task gone to trash still has its request taken out.
  jig queue request a pause >/dev/null
  rm -rf .ai/workspace/tasks/a
  run jig queue cancel a pause
  assert_eq 0 "$RC" "$OUT"
}

test_queue_request_answers_in_the_envelope() {
  _q_setup a
  _q_rev
  _q_json request a pause --reason "standup" --revision "$REV"
  assert_eq 0 "$RC" "$ERR"
  local at
  at=$(awk -F '\t' '$1 == "request" { print $4 }' .ai/runtime/queue)
  assert_eq "{\"schema\":1,\"revision\":$REV,\"generated_at\":\"T\",\"data\":{\"ref\":\"task:a\",\"request\":{\"kind\":\"pause\",\"requested_at\":\"$at\",\"reason\":\"standup\"}}}" \
    "$(printf '%s\n' "$OUT" | sed 's/"generated_at":"[^"]*"/"generated_at":"T"/')"
  _q_json cancel a pause
  assert_eq 0 "$RC" "$ERR"
  assert_contains "$OUT" '"data":{"ref":"task:a","request":null}}'
  _q_json request a pause
  assert_contains "$OUT" '"reason":null}'
}

test_queue_request_refuses_by_the_tasks_state() {
  _q_setup a b c
  _q_epic big
  jig task pause a >/dev/null
  _q_json request a pause
  assert_eq 1 "$RC"
  assert_eq failed "$(_q_code)"
  assert_contains "$OUT" "task a is already paused"
  jig task abandon b >/dev/null 2>&1 || fail "abandon failed"
  _q_json request b pause
  assert_eq failed "$(_q_code)"
  assert_contains "$OUT" "task b is abandoned"
  _q_json request nobody pause
  assert_eq not-found "$(_q_code)"
  _q_json request epic:big pause
  assert_eq usage "$(_q_code)"
  _q_json cancel epic:big pause
  assert_eq usage "$(_q_code)"
  _q_json request c resume
  assert_eq usage "$(_q_code)"
  _q_json request c
  assert_eq usage "$(_q_code)"
  _q_json cancel c pause --reason x
  assert_eq usage "$(_q_code)"
  assert_no_file .ai/runtime/queue
}

test_queue_request_with_a_stale_revision_is_refused_and_changes_nothing() {
  _q_setup a b
  _q_rev
  local old=$REV
  jig queue request a pause >/dev/null
  local before
  before=$(cat .ai/runtime/queue)
  _q_json request b pause --revision "$old"
  assert_eq stale-revision "$(_q_code)"
  _q_json cancel a pause --revision "$old"
  assert_eq stale-revision "$(_q_code)"
  assert_eq "$before" "$(cat .ai/runtime/queue)"
}

test_queue_write_redraws_the_status_page() {
  _q_setup a
  jig status --html >/dev/null
  assert_not_contains "$(cat .ai/runtime/status.html)" "queue=1/1"
  jig queue set a --priority 2 >/dev/null
  assert_contains "$(cat .ai/runtime/status.html)" "queue=1/1 priority=2"
  jig queue set a --priority 3 --json >/dev/null
  assert_contains "$(cat .ai/runtime/status.html)" "queue=1/1 priority=3"
}
