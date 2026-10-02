# Tests for the host runtime check: scripts/lib/hostruntime.sh, and its two
# readers, `jig doctor` and `jig verify --explain`
# (adr-20261001-checks-run-where-the-project-runs; domains/verify).
# shellcheck shell=bash
#
# No test needs PHP, node or Python: stubs on PATH answer for the host's
# runtime. Every test clears CI: with CI set the host is where the checks run
# anyway, but a runner's own variables must not steer a detector.
# Snippets run by `bash -c` expand their variables inside, not here.
# shellcheck disable=SC2016

# _hr_check <host> <constraint> <mode> — the exit code of the comparison, 0
# meets, 1 does not, 2 cannot compare.
_hr_check() {
  local rc=0
  bash -c '
    JIG_LIB="$1/scripts/lib"; . "$JIG_LIB/version.sh"; . "$JIG_LIB/hostruntime.sh"
    _hr_satisfies "$2" "$3" "$4"' _ "$JIG_HOME" "$1" "$2" "$3" || rc=$?
  printf '%s\n' "$rc"
}

_hr_expect() {
  local got
  got=$(_hr_check "$2" "$3" "$4")
  assert_eq "$1" "$got" "$2 against '$3' ($4)"
}

test_hostruntime_caret_and_ranges_for_composer() {
  _hr_expect 1 8.2.12 '^8.4' composer
  _hr_expect 0 8.4.1 '^8.4' composer
  _hr_expect 1 9.0.0 '^8.4' composer
  _hr_expect 0 8.3.0 '>=8.2 <8.5' composer
  _hr_expect 1 8.5.0 '>=8.2 <8.5' composer
  _hr_expect 1 8.5.0 '>=8.2,<8.5' composer
  _hr_expect 0 8.2.0 '^8.4 || ^8.2' composer
  _hr_expect 1 7.4.0 '^8.4 | ^8.2' composer
  _hr_expect 0 8.2.9 '8.2.*' composer
  _hr_expect 1 8.3.0 '8.2.*' composer
  _hr_expect 0 0.2.5 '^0.2.3' composer
  _hr_expect 1 0.3.0 '^0.2.3' composer
}

test_hostruntime_tilde_differs_between_composer_and_npm() {
  _hr_expect 0 3.12.0 '~3.11' composer
  _hr_expect 1 3.12.0 '~3.11' npm
  _hr_expect 0 3.11.9 '~3.11' npm
  _hr_expect 1 3.12.0 '~3.11.2' composer
}

test_hostruntime_engines_node_and_python_version_forms() {
  _hr_expect 0 20.1.0 '>=20' npm
  _hr_expect 1 18.0.0 '>=20' npm
  _hr_expect 1 18.0.0 '>= 20' npm
  _hr_expect 0 20.0.0 '*' npm
  _hr_expect 0 3.12.3 3.12 prefix
  _hr_expect 1 3.11.3 3.12 prefix
  _hr_expect 0 3.12.3 3.12.3 prefix
  _hr_expect 1 3.12.4 3.12.3 prefix
}

test_hostruntime_forms_it_cannot_judge_are_never_ok() {
  _hr_expect 2 8.4.0 '8.1 - 8.5' composer
  _hr_expect 2 8.4.0 '^8.4@dev' composer
  _hr_expect 2 8.4.0 'dev-main' composer
  _hr_expect 2 20.0.0 '>20' npm
  _hr_expect 2 8.4.0 '' composer
  # One alternative it can read and meets is enough; one it cannot read does
  # not turn a definite "no" into "ok".
  _hr_expect 0 8.4.0 '^8.4 || dev-main' composer
  _hr_expect 2 8.1.0 '^8.4 || dev-main' composer
}

# _hr_project <php-constraint> — a repository whose composer.json requires PHP.
_hr_project() {
  unset CI
  fixture_jig_repo
  printf '{\n  "name": "a/b",\n  "require": {\n    "php": "%s",\n    "ext-json": "*"\n  },\n  "require-dev": {"php": "^7"},\n  "config": {"platform": {"php": "8.1"}}\n}\n' "$1" > composer.json
}

# _hr_stub <tool> <version-output> — a stub on PATH answering the one question
# jig asks of it.
_hr_stub() {
  mkdir -p stub-bin
  printf '#!/bin/sh\nprintf "%%s" "%s"\n' "$2" > "stub-bin/$1"
  chmod +x "stub-bin/$1"
}

test_hostruntime_doctor_warns_when_the_host_php_is_older() {
  _hr_project '^8.4'
  _hr_stub php 8.2.12
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" doctor
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "warn  host php: php 8.2.12 on this machine does not meet ^8.4 (composer.json require.php)"
  assert_contains "$OUT" "jig config set run.exec"
}

test_hostruntime_doctor_ok_when_the_host_php_meets_it() {
  _hr_project '>=8.2 <8.5'
  _hr_stub php 8.4.1
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" doctor
  assert_contains "$OUT" "ok    host php: php 8.4.1 meets >=8.2 <8.5"
  assert_not_contains "$OUT" "warn  host php"
}

test_hostruntime_doctor_says_could_not_compare_for_an_unreadable_form() {
  _hr_project '8.1 - 8.5'
  _hr_stub php 8.4.1
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" doctor
  assert_contains "$OUT" "warn  host php: could not compare"
  assert_not_contains "$OUT" "ok    host php"
}

test_hostruntime_doctor_says_could_not_compare_when_the_runtime_does_not_answer() {
  _hr_project '^8.4'
  printf '#!/bin/sh\nexit 127\n' > stub-bin-php
  mkdir -p stub-bin
  mv stub-bin-php stub-bin/php
  chmod +x stub-bin/php
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" doctor
  assert_contains "$OUT" "warn  host php: could not compare: php is not available on this machine"
}

test_hostruntime_doctor_is_silent_without_a_requirement() {
  unset CI
  fixture_jig_repo
  run jig doctor
  assert_not_contains "$OUT" "host php"
  assert_not_contains "$OUT" "host node"
  assert_not_contains "$OUT" "host python"
}

test_hostruntime_doctor_does_not_ask_the_host_when_checks_run_elsewhere() {
  _hr_project '^8.4'
  _hr_stub php 8.2.12
  jig config set run.exec 'env' --local >/dev/null
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" doctor
  assert_not_contains "$OUT" "host php"
}

test_hostruntime_doctor_reads_node_and_python_requirements() {
  unset CI
  fixture_jig_repo
  printf '{"name":"x","engines":{"node":">=20"}}\n' > package.json
  printf '3.12\n' > .python-version
  _hr_stub node v18.19.0
  _hr_stub python3 "Python 3.12.3"
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" doctor
  assert_contains "$OUT" "warn  host node: node 18.19.0 on this machine does not meet >=20 (package.json engines.node)"
  assert_contains "$OUT" "ok    host python: python 3.12.3 meets 3.12 (.python-version)"
}

test_hostruntime_verify_explain_warns_on_the_host() {
  _hr_project '^8.4'
  _hr_stub php 8.2.12
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" verify --explain --profile generic
  assert_contains "$OUT" "verify: checks run in host"
  assert_contains "$OUT" "verify: warning: host php: php 8.2.12 on this machine does not meet ^8.4"
}

test_hostruntime_verify_explain_is_quiet_when_it_meets() {
  _hr_project '^8.4'
  _hr_stub php 8.4.0
  run env PATH="$PWD/stub-bin:$PATH" "$JIG_BIN" verify --explain --profile generic
  assert_not_contains "$OUT" "warning: host php"
}
