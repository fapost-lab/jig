# Tests for `jig measure` (SPEC §36, Phase 6).
#
# The whole report is a pure function of the repository, so every number below
# is asserted exactly — that is the property that lets a measurement command
# exist at all without an LLM (ADR-0001).
# shellcheck shell=bash

# A purge line as housekeeping writes it, appended straight to the log: these
# tests are about how `measure` reads the log, not about how it is produced
# (tests/housekeeping.t.sh owns that half).
m_purge_line() {
  mkdir -p .ai/runtime
  printf '2026-09-11T10:00:00Z task=%s status=%s remote=merged via=ancestry action=purge dest=.ai/runtime/trash/2026-09-11/%s%s\n' \
    "$1" "$2" "$1" "${3:+ $3}" >> .ai/runtime/housekeeping.log
}

# --- shape -------------------------------------------------------------------

test_measure_reports_every_section() {
  fixture_jig_repo

  run jig measure
  assert_eq 0 "$RC"
  assert_contains "$OUT" "knowledge:"
  assert_contains "$OUT" "process:"
  assert_contains "$OUT" "change:"
  assert_contains "$OUT" "blind spots:"
}

test_measure_names_what_it_cannot_measure() {
  # The blind spots belong in the output, not in a document beside it: every
  # number here is a proxy, and a reader who never opens the docs must still
  # be told that stage timing and cost are recorded nowhere.
  fixture_jig_repo

  run jig measure
  assert_contains "$OUT" "stage timing, session count, token and time cost are recorded nowhere"
}

test_measure_rejects_unknown_argument() {
  fixture_jig_repo

  run jig measure --everything
  assert_eq 1 "$RC"
  assert_contains "$OUT" "measure: unknown argument: --everything"
}

test_measure_requires_an_initialised_project() {
  fixture_repo

  run jig measure
  assert_eq 1 "$RC"
  assert_contains "$OUT" "project is not initialised"
}

# --- knowledge ---------------------------------------------------------------

# The count is asserted as a delta, not as an absolute: what a default install
# ships is the install domain's business and must not be able to break this test.
m_doc_count() { printf '%s\n' "$1" | sed -n 's/^knowledge:  \([0-9]*\) documents.*/\1/p'; }

test_measure_counts_knowledge_documents() {
  fixture_jig_repo
  run jig measure
  local before
  before=$(m_doc_count "$OUT")

  jig knowledge new feature alpha >/dev/null
  jig knowledge new feature beta >/dev/null

  run jig measure
  assert_eq "$((before + 2))" "$(m_doc_count "$OUT")"
  assert_contains "$OUT" "0 invalid,"
}

test_measure_counts_proposals_awaiting_decision() {
  # A proposed document reaches no agent until a human accepts it (ADR-0016),
  # so the count is the only thing that makes it visible in a report.
  fixture_jig_repo
  jig knowledge new feature alpha >/dev/null
  sed 's/^status: active/status: proposed/' .ai/knowledge/features/alpha.md \
    > .ai/knowledge/features/alpha.tmp
  mv .ai/knowledge/features/alpha.tmp .ai/knowledge/features/alpha.md

  run jig measure
  assert_contains "$OUT" "1 proposals awaiting decision"
}

test_measure_counts_unreviewed_knowledge() {
  fixture_jig_repo
  jig knowledge new feature alpha >/dev/null
  jig knowledge paths add feature-alpha "README.md" >/dev/null

  run jig measure
  assert_contains "$OUT" "1 with paths, 0 stale, 1 unreviewed"
}

# --- process -----------------------------------------------------------------

test_measure_reports_no_tasks() {
  fixture_jig_repo

  run jig measure
  assert_contains "$OUT" "process:    no task workspaces and no purge records"
  assert_not_contains "$OUT" "class: T0"
}

test_measure_counts_classes_and_outcomes() {
  fixture_jig_repo
  fixture_task one main active class:T1
  fixture_task two main consolidated class:T3
  fixture_task three main consolidated class:T3

  run jig measure
  assert_contains "$OUT" "process:    3 tasks (3 live, 0 recorded at purge)"
  assert_contains "$OUT" "class: T0 0, T1 1, T2 0, T3 2, T4 0, unclassified 0"
  assert_contains "$OUT" "outcome: consolidated 2, abandoned 0, active 1, ready 0, other 0"
}

test_measure_counts_a_task_without_a_class_as_unclassified() {
  # An unclassified task is an unknown, never a T0: the cheapest class must
  # not be inflated by work nobody classified.
  fixture_jig_repo
  fixture_task one main active

  run jig measure
  assert_contains "$OUT" "class: T0 0, T1 0, T2 0, T3 0, T4 0, unclassified 1"
}

# --- process: what survives the purge ----------------------------------------

test_measure_reads_purged_tasks_from_the_housekeeping_log() {
  # The workspace is designed to be destroyed (ADR-0006), so the purge line is
  # the only evidence a finished task ever existed.
  fixture_jig_repo
  m_purge_line gone consolidated "class=T2 created=2026-09-01 consolidated=true"

  run jig measure
  assert_contains "$OUT" "process:    1 tasks (0 live, 1 recorded at purge)"
  assert_contains "$OUT" "class: T0 0, T1 0, T2 1, T3 0, T4 0, unclassified 0"
  assert_contains "$OUT" "outcome: consolidated 1,"
}

test_measure_treats_a_purge_line_without_a_class_as_unclassified() {
  # Lines written before this phase carry no `class=`. A missing field is an
  # unknown, and reading it as a zero would silently invent T0 tasks.
  fixture_jig_repo
  m_purge_line old consolidated

  run jig measure
  assert_contains "$OUT" "class: T0 0, T1 0, T2 0, T3 0, T4 0, unclassified 1"
}

test_measure_prefers_a_live_workspace_over_a_purge_record() {
  # A task id can be reused after its workspace was erased; the workspace on
  # disk is the newer fact and the task must not be counted twice.
  fixture_jig_repo
  fixture_task reused main active class:T3
  m_purge_line reused consolidated "class=T2 created=2026-09-01 consolidated=true"

  run jig measure
  assert_contains "$OUT" "process:    1 tasks (1 live, 0 recorded at purge)"
  assert_contains "$OUT" "class: T0 0, T1 0, T2 0, T3 1, T4 0, unclassified 0"
}

test_measure_ignores_non_purge_log_lines() {
  fixture_jig_repo
  mkdir -p .ai/runtime
  printf -- '--- run 2026-09-11T10:00:00Z\n' >> .ai/runtime/housekeeping.log
  printf '2026-09-11T10:00:00Z task=kept status=active remote=unknown via=none action=preserve\n' \
    >> .ai/runtime/housekeeping.log

  run jig measure
  assert_contains "$OUT" "process:    no task workspaces and no purge records"
}

# --- change ------------------------------------------------------------------

test_measure_cannot_size_a_task_without_a_fork_point() {
  # Tasks predating ADR-0026, or created with --no-branch, have no base_commit
  # and are named as unmeasurable rather than dropped from the count.
  fixture_jig_repo
  fixture_task one main active class:T2

  run jig measure
  assert_contains "$OUT" "change:     measurable for 0 of 1 tasks (needs base_commit and a live branch)"
}

test_measure_sizes_a_task_from_its_fork_point() {
  fixture_jig_repo
  local base
  base=$(git rev-parse HEAD)
  git checkout -q -b task/sized
  printf 'a\nb\nc\n' > sized.txt
  git add sized.txt
  git commit -q -m "sized work"
  fixture_task sized "task/sized" active class:T2 "base_commit:$base"

  run jig measure
  assert_contains "$OUT" "change:     measurable for 1 of 1 tasks"
  assert_contains "$OUT" "T2: 1 task(s), median 1 commits, 1 files, 3 lines, 0d fork to tip"
}

test_measure_ignores_a_task_whose_branch_is_gone() {
  # A merged branch that was deleted leaves nothing to diff against, which is
  # the same blind spot ancestry has (ADR-0025).
  fixture_jig_repo
  local base
  base=$(git rev-parse HEAD)
  fixture_task sized "task/deleted" consolidated class:T2 "base_commit:$base"

  run jig measure
  assert_contains "$OUT" "change:     measurable for 0 of 1 tasks"
}

test_measure_reports_the_median_of_several_tasks() {
  # The lower median, deliberately: half a file is not a thing to print.
  fixture_jig_repo
  local base
  base=$(git rev-parse HEAD)
  local n
  for n in 1 2 3; do
    git checkout -q -b "task/m$n" "$base"
    printf 'x\n' > "m$n.txt"
    git add "m$n.txt"
    git commit -q -m "m$n first"
    if [ "$n" -gt 1 ]; then
      printf 'y\n' >> "m$n.txt"
      git add "m$n.txt"
      git commit -q -m "m$n second"
    fi
    fixture_task "m$n" "task/m$n" consolidated class:T3 "base_commit:$base"
  done

  run jig measure
  assert_contains "$OUT" "change:     measurable for 3 of 3 tasks"
  assert_contains "$OUT" "T3: 3 task(s), median 2 commits,"
}

# --- the seam between the two commands ---------------------------------------

test_measure_counts_a_task_housekeeping_actually_purged() {
  # The half neither command can prove alone: housekeeping writes the facts as
  # it destroys the workspace, and measure reads them back afterwards.
  fixture_jig_repo
  sed 's|^forge:.*|forge: none|' .ai/config.yaml > .ai/config.tmp
  mv .ai/config.tmp .ai/config.yaml
  sed 's|^housekeeping.fetch:.*|housekeeping.fetch: false|' .ai/config.yaml > .ai/config.tmp
  mv .ai/config.tmp .ai/config.yaml
  fixture_merge_repo
  fixture_task landed "ff-merged" consolidated class:T4 knowledge_consolidated:true

  jig housekeeping >/dev/null
  assert_no_file .ai/workspace/tasks/landed/state

  run jig measure
  assert_contains "$OUT" "process:    1 tasks (0 live, 1 recorded at purge)"
  assert_contains "$OUT" "class: T0 0, T1 0, T2 0, T3 0, T4 1, unclassified 0"
}
