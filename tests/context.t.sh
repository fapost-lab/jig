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

# --- status filtering: allowlist (status: proposed / unknown values) -------------------

test_context_status_proposed_not_matched_unless_all() {
  ctx_setup
  cat > .ai/knowledge/features/prop.md <<'EOF'
---
id: feature-prop
type: feature
status: proposed
paths:
  - "x.php"
---
EOF
  run jig context --files x.php
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "prop.md"

  run jig context --files x.php --all
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/features/prop.md"
}

test_context_resolve_status_proposed_not_required_or_catalog_unless_all() {
  ctx_setup
  cat > .ai/knowledge/features/prop.md <<'EOF'
---
id: feature-prop
type: feature
status: proposed
load: always
domains: [payments]
---
EOF
  run jig context resolve --domains payments --catalog
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "required:  .ai/knowledge/features/prop.md"
  assert_not_contains "$OUT" "catalog:   .ai/knowledge/features/prop.md"

  run jig context resolve --domains payments --catalog --all
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/prop.md  (load: always)"
}

test_context_status_unknown_value_not_resolved_unless_all() {
  ctx_setup
  # Behaviour change: the old denylist (superseded|deprecated|rejected) let any
  # other value through as if active. The allowlist rejects it too.
  cat > .ai/knowledge/features/weird.md <<'EOF'
---
id: feature-weird
type: feature
status: banana
paths:
  - "x.php"
---
EOF
  run jig context --files x.php
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "weird.md"

  run jig context --files x.php --all
  assert_eq 0 "$RC"
  assert_contains "$OUT" "matched:   .ai/knowledge/features/weird.md"

  run jig context resolve --files x.php
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "weird.md"
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
  # --no-branch on purpose: ambiguity needs two tasks on one branch, which
  # branch-per-task (the default) prevents. The behaviour under test — context
  # omits the workspace rather than guessing — still matters wherever
  # branch-per-task is off.
  jig task new T-1 --no-branch >/dev/null
  jig task new T-2 --no-branch >/dev/null

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

# --- resolve: load policy --------------------------------------------------------------

test_context_resolve_load_always_required_with_no_selectors() {
  ctx_setup
  cat > .ai/knowledge/features/always.md <<'EOF'
---
id: feature-always
type: feature
status: active
load: always
---
EOF
  run jig context resolve
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/always.md  (load: always)"
}

test_context_resolve_load_domain_matches_domains_selector() {
  ctx_setup
  mkdir -p .ai/knowledge/domains/payments
  cat > .ai/knowledge/domains/payments/RULES.md <<'EOF'
---
id: rule-payments
type: rule
status: active
domains: [payments]
load: domain
---
EOF
  run jig context resolve --domains payments
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/domains/payments/RULES.md  (domains: payments)"

  run jig context resolve
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "domains/payments/RULES.md"
}

test_context_resolve_matched_by_paths_glob() {
  ctx_setup
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
paths:
  - "src/Checkout/**"
---
EOF
  run jig context resolve --files src/Checkout/Order.php
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/checkout.md  (paths: src/Checkout/**)"
}

test_context_resolve_active_and_accepted_still_resolve() {
  ctx_setup
  cat > .ai/knowledge/features/active.md <<'EOF'
---
id: feature-active
type: feature
status: active
load: always
---
EOF
  cat > .ai/knowledge/adr/0001-accepted.md <<'EOF'
---
id: adr-0001-accepted
type: adr
status: accepted
date: 2026-01-01
load: always
---
EOF
  run jig context resolve
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/active.md  (load: always)"
  assert_contains "$OUT" "required:  .ai/knowledge/adr/0001-accepted.md  (load: always)"
}

test_context_resolve_matched_by_topics() {
  ctx_setup
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
topics: [refunds]
---
EOF
  run jig context resolve --topics refunds
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/checkout.md  (topics: refunds)"
}

# --- resolve: catalog (domain-only match is not required) -----------------------------

test_context_resolve_domain_only_match_goes_to_catalog_not_required() {
  ctx_setup
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
domains: [payments]
summary: "How checkout builds an order."
---
EOF
  run jig context resolve --domains payments
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "required:  .ai/knowledge/features/checkout.md"

  run jig context resolve --domains payments --catalog
  assert_eq 0 "$RC"
  assert_contains "$OUT" "catalog:   .ai/knowledge/features/checkout.md  [feature-checkout] How checkout builds an order."
}

test_context_resolve_catalog_no_summary_shows_placeholder() {
  ctx_setup
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
domains: [payments]
---
EOF
  run jig context resolve --domains payments --catalog
  assert_eq 0 "$RC"
  assert_contains "$OUT" "catalog:   .ai/knowledge/features/checkout.md  [feature-checkout] (no summary)"
}

test_context_resolve_without_catalog_flag_prints_no_catalog_line() {
  ctx_setup
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
domains: [payments]
---
EOF
  run jig context resolve --domains payments
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "catalog:"
}

# --- resolve: globals, required and workspace labels together -------------------------

test_context_resolve_prints_global_required_and_workspace_labels() {
  ctx_setup
  jig task new T-1 >/dev/null
  mkdir -p .ai/knowledge/domains/payments
  cat > .ai/knowledge/domains/payments/RULES.md <<'EOF'
---
id: rule-payments
type: rule
status: active
domains: [payments]
load: always
---
EOF
  run jig context resolve --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "global:    .ai/knowledge/GLOSSARY.md"
  assert_contains "$OUT" "required:  .ai/knowledge/domains/payments/RULES.md  (load: always)"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/task.md"
}

# --- resolve: transitive requires -------------------------------------------------------

test_context_resolve_transitive_requires_two_step_chain() {
  ctx_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
load: always
requires: [feature-b]
---
EOF
  cat > .ai/knowledge/features/b.md <<'EOF'
---
id: feature-b
type: feature
status: active
requires: [feature-c]
---
EOF
  cat > .ai/knowledge/features/c.md <<'EOF'
---
id: feature-c
type: feature
status: active
---
EOF
  run jig context resolve
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/a.md  (load: always)"
  assert_contains "$OUT" "required:  .ai/knowledge/features/b.md  (requires: feature-a)"
  assert_contains "$OUT" "required:  .ai/knowledge/features/c.md  (requires: feature-b)"
}

test_context_resolve_requires_unknown_document_is_fatal() {
  ctx_setup
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
load: always
requires: [feature-ghost]
---
EOF
  run jig context resolve
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires unknown or inactive document:"
  assert_contains "$OUT" "run: jig knowledge check"
}

test_context_resolve_requires_inactive_document_is_fatal() {
  ctx_setup
  cat > .ai/knowledge/features/old.md <<'EOF'
---
id: feature-old
type: feature
status: deprecated
---
EOF
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
load: always
requires: [feature-old]
---
EOF
  run jig context resolve
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires unknown or inactive document: feature-old"
  assert_contains "$OUT" "run: jig knowledge check"
}

test_context_resolve_requires_proposed_document_is_fatal() {
  ctx_setup
  cat > .ai/knowledge/features/old.md <<'EOF'
---
id: feature-old
type: feature
status: proposed
---
EOF
  cat > .ai/knowledge/features/a.md <<'EOF'
---
id: feature-a
type: feature
status: active
load: always
requires: [feature-old]
---
EOF
  run jig context resolve
  assert_eq 1 "$RC"
  assert_contains "$OUT" "requires unknown or inactive document: feature-old"
  assert_contains "$OUT" "run: jig knowledge check"
}

# --- resolve: --ids ----------------------------------------------------------------------

test_context_resolve_ids_promotes_catalog_document_to_required() {
  ctx_setup
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
domains: [payments]
---
EOF
  run jig context resolve --ids feature-checkout
  assert_eq 0 "$RC"
  assert_contains "$OUT" "required:  .ai/knowledge/features/checkout.md  (id: feature-checkout)"
}

test_context_resolve_unknown_id_dies() {
  ctx_setup
  run jig context resolve --ids no-such-id
  assert_eq 1 "$RC"
  assert_contains "$OUT" "jig: error: context: no active document with id: no-such-id"
}

# --- context ledger: guard / pending / acknowledge --------------------------------------

test_context_guard_ledger_round_trip() {
  ctx_setup
  jig task new T-1 >/dev/null
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
load: always
---
EOF
  run jig context guard --task T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "context guard: 4 of 4 document(s) not acknowledged:"
  assert_contains "$OUT" "  .ai/knowledge/features/checkout.md"
  assert_contains "$OUT" "read them, then: jig context acknowledge --task T-1 --files <list>"

  run bash -c '"$JIG_BIN" context pending --task T-1 | "$JIG_BIN" context acknowledge --task T-1 --files -'
  assert_eq 0 "$RC"

  run jig context guard --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "context guard: ok (4 document(s) acknowledged)"
}

test_context_guard_reacknowledges_after_document_changes() {
  ctx_setup
  jig task new T-1 >/dev/null
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
load: always
---
EOF
  run bash -c '"$JIG_BIN" context pending --task T-1 | "$JIG_BIN" context acknowledge --task T-1 --files -'
  assert_eq 0 "$RC"
  run jig context guard --task T-1
  assert_eq 0 "$RC"

  printf 'extra line\n' >> .ai/knowledge/features/checkout.md

  run jig context guard --task T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "context guard: 1 of 4 document(s) not acknowledged:"
  assert_contains "$OUT" "  .ai/knowledge/features/checkout.md"
  assert_not_contains "$OUT" "GLOSSARY.md"
}

test_context_ledger_file_format_and_location() {
  ctx_setup
  jig task new T-1 >/dev/null
  cat > .ai/knowledge/features/checkout.md <<'EOF'
---
id: feature-checkout
type: feature
status: active
load: always
---
EOF
  run bash -c '"$JIG_BIN" context pending --task T-1 | "$JIG_BIN" context acknowledge --task T-1 --files -'
  assert_eq 0 "$RC"

  assert_file .ai/workspace/tasks/T-1/context
  local expected_hash line
  expected_hash=$(git hash-object .ai/knowledge/features/checkout.md)
  line=$(grep "features/checkout.md" .ai/workspace/tasks/T-1/context)
  assert_eq "$(printf '%s\t%s' "$expected_hash" ".ai/knowledge/features/checkout.md")" "$line"

  local sorted
  sorted=$(sort .ai/workspace/tasks/T-1/context)
  assert_eq "$sorted" "$(cat .ai/workspace/tasks/T-1/context)"
}

test_context_workspace_artifacts_never_tracked_by_ledger() {
  ctx_setup
  jig task new T-1 >/dev/null
  printf '# discovery\n' > .ai/workspace/tasks/T-1/discovery.md

  run jig context resolve --task T-1
  assert_eq 0 "$RC"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/task.md"
  assert_contains "$OUT" "workspace: .ai/workspace/tasks/T-1/discovery.md"

  run jig context pending --task T-1
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "task.md"
  assert_not_contains "$OUT" "discovery.md"
}

test_context_guard_and_pending_with_no_live_task() {
  ctx_setup
  jig task new T-1 >/dev/null
  jig task pause T-1 --reason "testing" >/dev/null

  run jig context guard
  assert_eq 0 "$RC"
  assert_eq "context guard: no task workspace; nothing tracked" "$OUT"

  run jig context pending
  assert_eq 0 "$RC"
  assert_eq "" "$OUT"
}

# --- acknowledge: path validation --------------------------------------------------------

test_context_acknowledge_rejects_absolute_path() {
  ctx_setup
  jig task new T-1 >/dev/null
  run jig context acknowledge --task T-1 --files /etc/passwd
  assert_eq 1 "$RC"
  assert_contains "$OUT" "context acknowledge: path must be repository-relative:"
}

test_context_acknowledge_rejects_dotdot_path() {
  ctx_setup
  jig task new T-1 >/dev/null
  run jig context acknowledge --task T-1 --files "../escape.md"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "path may not contain '..'"
}

test_context_acknowledge_rejects_path_outside_knowledge_dir() {
  ctx_setup
  jig task new T-1 >/dev/null
  run jig context acknowledge --task T-1 --files "README.md"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a knowledge document:"
}

test_context_acknowledge_rejects_nonexistent_document() {
  ctx_setup
  jig task new T-1 >/dev/null
  run jig context acknowledge --task T-1 --files ".ai/knowledge/features/ghost.md"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no such document:"
}

test_context_acknowledge_requires_task() {
  ctx_setup
  run jig context acknowledge --files x
  assert_eq 1 "$RC"
  assert_contains "$OUT" "context acknowledge: --task is required"
}

test_context_acknowledge_requires_files() {
  ctx_setup
  jig task new T-1 >/dev/null
  run jig context acknowledge --task T-1
  assert_eq 1 "$RC"
  assert_contains "$OUT" "context acknowledge: --files is required"
}

# --- CLI plumbing: subcommands ------------------------------------------------------------

test_context_unknown_subcommand_dies_with_usage() {
  ctx_setup
  run jig context bogus
  assert_eq 1 "$RC"
  assert_contains "$OUT" "usage: jig context"
}

sdd_stage_setup() {
  ctx_setup
  jig task new stage-task --class T3 --domains payments >/dev/null
  cat > .ai/knowledge/features/staged.md <<'DOC'
---
id: feature-staged
type: feature
status: active
domains: [payments]
load: matched
stages: [implement]
summary: Implementation guidance.
requires: [feature-dependency]
---
Stage body.
DOC
  cat > .ai/knowledge/features/dependency.md <<'DOC'
---
id: feature-dependency
type: feature
status: active
domains: [other]
summary: Dependency.
---
Dependency body.
DOC
}

test_sdd_stage_promotes_only_entered_catalog_and_closes_requires() {
  sdd_stage_setup
  run jig context resolve --task stage-task --stage implement --files - < /dev/null
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'stage: implement; domain: payments'
  assert_contains "$OUT" 'requires: feature-staged'
  run jig context resolve --task stage-task --stage design --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'features/staged.md'
  run jig context resolve --no-task --stage implement --domains other --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'features/staged.md'
  run jig context resolve --no-task --stage implement --files - < /dev/null
  assert_not_contains "$OUT" 'features/staged.md'
}

test_sdd_stage_never_hides_path_topic_always_domain_or_explicit_ids() {
  sdd_stage_setup
  cat > .ai/knowledge/features/binding.md <<'DOC'
---
id: feature-binding
type: feature
status: active
paths: [bound.txt]
topics: [money]
stages: [verify]
---
Binding.
DOC
  run jig context resolve --task stage-task --stage design --files bound.txt
  assert_eq 0 "$RC"
  assert_contains "$OUT" 'paths: bound.txt'
  run jig context resolve --task stage-task --stage design --topics money --files - < /dev/null
  assert_contains "$OUT" 'topics: money'
  run jig context resolve --task stage-task --stage design --ids feature-staged --files - < /dev/null
  assert_contains "$OUT" 'id: feature-staged'
  cat > .ai/knowledge/features/always.md <<'DOC'
---
id: feature-always
type: feature
status: active
load: always
stages: [verify]
---
Always.
DOC
  cat > .ai/knowledge/features/domain.md <<'DOC'
---
id: feature-domain
type: feature
status: active
load: domain
domains: [payments]
stages: [verify]
---
Domain.
DOC
  run jig context resolve --task stage-task --stage design --files - < /dev/null
  assert_contains "$OUT" 'load: always'
  assert_contains "$OUT" 'features/domain.md'
}

test_sdd_stage_change_uses_hash_ledger_without_rereading_unchanged() {
  sdd_stage_setup
  local global
  for global in GLOSSARY ARCHITECTURE RULES; do
    jig context acknowledge --task stage-task --files ".ai/knowledge/$global.md" >/dev/null
  done
  run jig context guard --task stage-task --stage design --files - < /dev/null
  assert_eq 0 "$RC"
  run jig context guard --task stage-task --stage implement --files - < /dev/null
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'features/staged.md'
  jig context acknowledge --task stage-task --files .ai/knowledge/features/staged.md,.ai/knowledge/features/dependency.md >/dev/null
  run jig context guard --task stage-task --stage implement --files - < /dev/null
  assert_eq 0 "$RC"
  echo changed >> .ai/knowledge/features/staged.md
  run jig context pending --task stage-task --stage implement --files - < /dev/null
  assert_eq '.ai/knowledge/features/staged.md' "$OUT"
}

test_sdd_stage_missing_dependencies_and_globals_fail_even_taskless() {
  sdd_stage_setup
  rm .ai/knowledge/features/dependency.md
  local sub
  for sub in resolve pending guard; do
    run jig context "$sub" --no-task --stage implement --domains payments --files - < /dev/null
    assert_eq 1 "$RC"
    assert_contains "$OUT" 'requires unknown or inactive'
    run jig context "$sub" --no-task --ids no-such-id --files - < /dev/null
    assert_eq 1 "$RC"
    assert_contains "$OUT" 'no active document'
  done
  rm .ai/knowledge/RULES.md
  for sub in resolve pending guard; do
    run jig context "$sub" --no-task --files - < /dev/null
    assert_eq 1 "$RC"
    assert_contains "$OUT" 'missing or unreadable mandatory global'
  done
}

test_sdd_stage_excludes_proposed_and_rejected() {
  sdd_stage_setup
  sed 's/status: active/status: proposed/' .ai/knowledge/features/staged.md > proposed.tmp
  mv proposed.tmp .ai/knowledge/features/staged.md
  run jig context resolve --task stage-task --stage implement --catalog --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'features/staged.md'
  jig knowledge reject feature-staged >/dev/null
  run jig context resolve --task stage-task --stage implement --catalog --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'features/staged.md'
}

test_sdd_taskless_research_bypasses_ambiguous_and_single_task() {
  sdd_stage_setup
  local before
  before=$(cat .ai/workspace/tasks/stage-task/state)
  run jig context resolve --no-task --stage implement --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'workspace:'
  assert_not_contains "$OUT" 'features/staged.md'
  jig task new another >/dev/null
  run jig context resolve --no-task --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'multiple'
  assert_not_contains "$OUT" 'stage-task'
  run jig context --no-task --files - < /dev/null
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" 'workspace:'
  run jig context guard --no-task --files - < /dev/null
  assert_contains "$OUT" 'no task workspace; nothing tracked'
  assert_eq "$before" "$(cat .ai/workspace/tasks/stage-task/state)"
}

test_sdd_stage_and_taskless_argument_validation() {
  sdd_stage_setup
  run jig context resolve --stage nonsense
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'invalid stage'
  run jig context resolve --stage
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'requires a value'
  run jig context --stage implement
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'use jig context resolve'
  run jig context resolve --no-task --task stage-task
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'conflicts'
  run jig context --task stage-task --no-task
  assert_eq 1 "$RC"
  assert_contains "$OUT" 'conflicts'
}
