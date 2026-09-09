# Tests for `jig context` (SPEC §26; ADR-0004; ADR-0008).
# shellcheck shell=bash

ctx_setup() {
  fixture_jig_repo
}

# --- --files: paths glob matching -----------------------------------------------

test_context_files_glob_double_star_any_depth() {
  ctx_setup
  cat > .ai/knowledge/features/flow.md <<'EOF'
---
id: feature-flow
type: feature
status: active
paths:
  - "src/Flow/**"
---
EOF
  run jig context --files src/Flow/A.php
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/features/flow.md  (paths: src/Flow/**)"
}

test_context_files_glob_single_segment_prefix() {
  ctx_setup
  cat > .ai/knowledge/features/trigger.md <<'EOF'
---
id: feature-trigger
type: feature
status: active
paths:
  - "app/Services/Trigger*"
---
EOF
  run jig context --files app/Services/TriggerService.php
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/features/trigger.md  (paths: app/Services/Trigger*)"

  # does not match a nested path: the glob has no ** and case's `*`
  # matching `/` does not change that the literal prefix must line up.
  run jig context --files app/Services/Other/TriggerService.php
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "trigger.md"
}

test_context_files_glob_any_depth_extension() {
  ctx_setup
  cat > .ai/knowledge/conventions/shellish.md <<'EOF'
---
id: convention-shellish
type: convention
status: active
paths:
  - "**/*.sh"
---
EOF
  run jig context --files scripts/lib/foo.sh
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/conventions/shellish.md  (paths: **/*.sh)"

  run jig context --files top.sh
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/conventions/shellish.md"
}

test_context_files_exact_match() {
  ctx_setup
  cat > .ai/knowledge/features/exact.md <<'EOF'
---
id: feature-exact
type: feature
status: active
paths:
  - "docs/SPEC.md"
---
EOF
  run jig context --files docs/SPEC.md
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/features/exact.md"

  run jig context --files docs/OTHER.md
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "exact.md"
}

test_context_files_csv_list() {
  ctx_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "a.php"
---
EOF
  cat > .ai/knowledge/features/b.md <<'EOF'
---
id: feature-b
type: feature
status: active
paths:
  - "b.php"
---
EOF
  run jig context --files a.php,b.php --format paths
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/knowledge/features/a.md"
  assert_contains "$OUT" ".ai/knowledge/features/b.md"
}

test_context_files_from_stdin() {
  ctx_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
paths:
  - "a.php"
---
EOF
  run bash -c 'printf "a.php\n" | "$JIG_BIN" context --files -'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "features/a.md"
}

test_context_matched_docs_sorted_by_path() {
  ctx_setup
  cat > .ai/knowledge/features/zzz.md <<'EOF'
---
id: feature-zzz
type: feature
status: active
paths:
  - "x.php"
---
EOF
  cat > .ai/knowledge/features/aaa.md <<'EOF'
---
id: feature-aaa
type: feature
status: active
paths:
  - "x.php"
---
EOF
  run jig context --files x.php --format paths
  assert_eq 0 "$RC"
  local first second
  first=$(printf '%s\n' "$OUT" | grep features | sed -n 1p)
  second=$(printf '%s\n' "$OUT" | grep features | sed -n 2p)
  assert_contains "$first" "aaa.md"
  assert_contains "$second" "zzz.md"
}

test_context_no_match_still_exits_0_with_only_global() {
  ctx_setup
  run jig context --files nonexistent/path.php
  assert_eq 0 "$RC"
  assert_contains "$OUT" "global:"
  assert_not_contains "$OUT" "matched:"
}

# --- domains ------------------------------------------------------------------------

test_context_domains_explicit() {
  ctx_setup
  cat > .ai/knowledge/adr/0007-x.md <<'EOF'
---
id: adr-0007-x
type: adr
status: accepted
date: 2026-01-01
domains: [triggers]
---
EOF
  run jig context --domains triggers
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/adr/0007-x.md  (domains: triggers)"
}

test_context_domains_from_task_state() {
  ctx_setup
  jig task new T-1 --domains triggers,flow >/dev/null
  cat > .ai/knowledge/adr/0007-x.md <<'EOF'
---
id: adr-0007-x
type: adr
status: accepted
date: 2026-01-01
domains: [triggers]
---
EOF
  run jig context --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/adr/0007-x.md  (domains: triggers)"
}

test_context_explicit_domains_override_task_domains() {
  ctx_setup
  jig task new T-1 --domains other >/dev/null
  cat > .ai/knowledge/adr/0007-x.md <<'EOF'
---
id: adr-0007-x
type: adr
status: accepted
date: 2026-01-01
domains: [triggers]
---
EOF
  run jig context --task T-1 --domains triggers
  assert_eq 0 "$RC"
  assert_contains "$OUT" "adr/0007-x.md"
}

test_context_no_domains_no_match_on_domains() {
  ctx_setup
  cat > .ai/knowledge/adr/0007-x.md <<'EOF'
---
id: adr-0007-x
type: adr
status: accepted
date: 2026-01-01
domains: [triggers]
---
EOF
  run jig context
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "0007-x.md"
}

# --- git-derived files ---------------------------------------------------------------

test_context_git_derived_union_of_committed_unstaged_untracked() {
  ctx_setup
  cat > .ai/knowledge/features/committed.md <<'EOF'
---
id: feature-committed
type: feature
status: active
paths:
  - "committed.php"
---
EOF
  cat > .ai/knowledge/features/modified.md <<'EOF'
---
id: feature-modified
type: feature
status: active
paths:
  - "README.md"
---
EOF
  cat > .ai/knowledge/features/untracked.md <<'EOF'
---
id: feature-untracked
type: feature
status: active
paths:
  - "new.php"
---
EOF
  git checkout -q -b feature
  printf '<?php\n' > committed.php
  git add committed.php
  git commit -q -m "add committed.php"
  printf 'unstaged change\n' >> README.md
  printf '<?php\n' > new.php

  run jig context --format paths
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/knowledge/features/committed.md"
  assert_contains "$OUT" ".ai/knowledge/features/modified.md"
  assert_contains "$OUT" ".ai/knowledge/features/untracked.md"
}

test_context_git_missing_base_branch_falls_back_to_working_tree_only() {
  ctx_setup
  cat > .ai/knowledge/features/committed.md <<'EOF'
---
id: feature-committed
type: feature
status: active
paths:
  - "committed.php"
---
EOF
  cat > .ai/knowledge/features/untracked.md <<'EOF'
---
id: feature-untracked
type: feature
status: active
paths:
  - "new.php"
---
EOF
  sed 's/^git\.base_branch:.*/git.base_branch: does-not-exist/' .ai/config.yaml > .ai/config.yaml.new
  mv .ai/config.yaml.new .ai/config.yaml

  git checkout -q -b feature
  printf '<?php\n' > committed.php
  git add committed.php
  git commit -q -m "add committed.php"
  printf '<?php\n' > new.php

  run jig context --format paths
  assert_eq 0 "$RC"
  # committed.php was only reachable through the merge-base diff, which is
  # skipped when the base branch does not exist.
  assert_not_contains "$OUT" "committed.md"
  assert_contains "$OUT" ".ai/knowledge/features/untracked.md"
}

# --- status filtering ------------------------------------------------------------------

test_context_skips_superseded_deprecated_rejected_unless_all() {
  ctx_setup
  cat > .ai/knowledge/features/old.md <<'EOF'
---
id: feature-old
type: feature
status: superseded
paths:
  - "x.php"
---
EOF
  cat > .ai/knowledge/adr/0001-old.md <<'EOF'
---
id: adr-0001-old
type: adr
status: rejected
date: 2026-01-01
paths:
  - "x.php"
---
EOF
  run jig context --files x.php
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "old.md"

  run jig context --files x.php --all
  assert_eq 0 "$RC"
  assert_contains "$OUT" "features/old.md"
  assert_contains "$OUT" "adr/0001-old.md"
}

test_context_active_status_always_shown() {
  ctx_setup
  cat > .ai/knowledge/features/active.md <<'EOF'
---
id: feature-active
type: feature
status: active
paths:
  - "x.php"
---
EOF
  run jig context --files x.php
  assert_eq 0 "$RC"
  assert_contains "$OUT" "features/active.md"
}

# --- --format paths ---------------------------------------------------------------------

test_context_format_paths_prints_only_paths_no_prefixes() {
  ctx_setup
  cat > .ai/knowledge/features/x.md <<'EOF'
---
id: feature-x
type: feature
status: active
paths:
  - "x.php"
---
EOF
  run jig context --files x.php --format paths
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "global:"
  assert_not_contains "$OUT" "matched:"
  assert_not_contains "$OUT" "("
  assert_contains "$OUT" ".ai/knowledge/GLOSSARY.md"
  assert_contains "$OUT" ".ai/knowledge/features/x.md"
}

# --- global files -----------------------------------------------------------------------

test_context_global_files_present() {
  ctx_setup
  run jig context
  assert_eq 0 "$RC"
  assert_contains "$OUT" "global:    .ai/knowledge/GLOSSARY.md"
  assert_contains "$OUT" "global:    .ai/knowledge/ARCHITECTURE.md"
  assert_contains "$OUT" "global:    .ai/knowledge/RULES.md"
}

test_context_global_files_absent_are_omitted() {
  ctx_setup
  rm .ai/knowledge/ARCHITECTURE.md
  run jig context
  assert_eq 0 "$RC"
  assert_contains "$OUT" "global:    .ai/knowledge/GLOSSARY.md"
  assert_not_contains "$OUT" "ARCHITECTURE.md"
}

# --- workspace listing -------------------------------------------------------------------

test_context_workspace_lists_task_md_only_by_default() {
  ctx_setup
  jig task new T-1 >/dev/null
  run jig context --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/task.md"
}

test_context_workspace_lists_existing_artifacts_in_order() {
  ctx_setup
  jig task new T-1 >/dev/null
  printf '# discovery\n' > .ai/workspace/tasks/T-1/discovery.md
  printf '# plan\n' > .ai/workspace/tasks/T-1/plan.md
  printf '# verification\n' > .ai/workspace/tasks/T-1/verification.md

  run jig context --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/task.md"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/discovery.md"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/plan.md"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/verification.md"
  assert_not_contains "$OUT" "spec.md"
  assert_not_contains "$OUT" "design.md"
  assert_not_contains "$OUT" "review.md"

  # task.md before discovery.md before plan.md before verification.md
  local l_task l_disc l_plan l_verif
  l_task=$(printf '%s\n' "$OUT" | grep -n "task.md" | cut -d: -f1)
  l_disc=$(printf '%s\n' "$OUT" | grep -n "discovery.md" | cut -d: -f1)
  l_plan=$(printf '%s\n' "$OUT" | grep -n "plan.md" | cut -d: -f1)
  l_verif=$(printf '%s\n' "$OUT" | grep -n "verification.md" | cut -d: -f1)
  [ "$l_task" -lt "$l_disc" ] || fail "task.md not before discovery.md"
  [ "$l_disc" -lt "$l_plan" ] || fail "discovery.md not before plan.md"
  [ "$l_plan" -lt "$l_verif" ] || fail "plan.md not before verification.md"
}

test_context_no_workspace_line_without_a_task() {
  ctx_setup
  run jig context
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "workspace:"
}

# --- task resolution ---------------------------------------------------------------------

test_context_resolves_task_via_current_branch() {
  ctx_setup
  jig task new T-1 >/dev/null
  run jig context
  assert_eq 0 "$RC"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/task.md"
}

test_context_no_current_task_is_silent_not_fatal() {
  ctx_setup
  jig task new T-1 >/dev/null
  git checkout -q -b other
  run jig context
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "workspace:"
}

test_context_task_explicit_overrides_current_branch_resolution() {
  ctx_setup
  jig task new T-1 >/dev/null
  git checkout -q -b other
  jig task new T-2 >/dev/null

  run jig context --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/task.md"
  assert_not_contains "$OUT" "T-2/task.md"
}

test_context_ambiguous_omits_workspace_warns_stderr_exits_0() {
  ctx_setup
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null

  run jig context
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "workspace:"
  assert_contains "$OUT" "T-1"
  assert_contains "$OUT" "T-2"
}

test_context_ambiguous_but_task_explicit_still_works() {
  ctx_setup
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null

  run jig context --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/task.md"
  assert_not_contains "$OUT" "T-2/task.md"
}

test_context_paused_task_excluded_leaves_one_candidate() {
  ctx_setup
  # T-1 sorts before T-2, so an implementation that forgot to exclude paused
  # tasks would still resolve deterministically here (tie-break by id) and
  # mask the bug. Pausing T-1 — the one that would otherwise win the
  # tie-break — makes the assertion actually exercise the exclusion.
  jig task new T-1 >/dev/null
  jig task new T-2 >/dev/null
  printf 'paused: true\n' >> .ai/workspace/tasks/T-1/state

  run jig context
  assert_eq 0 "$RC"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-2/task.md"
  assert_not_contains "$OUT" "T-1/task.md"
}

test_context_task_explicit_unknown_dies() {
  ctx_setup
  run jig context --task NOPE
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown task"
}

# --- CLI plumbing -----------------------------------------------------------------------

test_context_unknown_flag_dies() {
  ctx_setup
  run jig context --bogus
  assert_eq 1 "$RC"
}

test_context_invalid_format_dies() {
  ctx_setup
  run jig context --format bogus
  assert_eq 1 "$RC"
}

test_context_missing_value_for_files_dies() {
  ctx_setup
  run jig context --files
  assert_eq 1 "$RC"
}

test_context_without_init_dies() {
  fixture_repo
  run jig context
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not initialised"
}

test_context_includes_staged_files_without_base_branch() {
  fixture_repo
  run jig init --from "$JIG_HOME"
  git branch -m main trunk   # base branch "main" no longer exists
  mkdir -p .ai/knowledge/features src/Flow
  cat > .ai/knowledge/features/flow.md <<'MD'
---
id: feature-flow
type: feature
status: active
paths: ["src/Flow/**"]
---
# Flow
MD
  printf 'x\n' > src/Flow/A.php
  git add src/Flow/A.php
  run jig context --format paths
  assert_eq 0 "$RC"
  assert_contains "$OUT" ".ai/knowledge/features/flow.md"
}
