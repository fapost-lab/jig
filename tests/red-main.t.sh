# Tests for `.github/scripts/red-main.sh`, the `red-main` job's alert.
# shellcheck shell=bash
#
# No network: `gh` is a stub that logs its arguments to gh.log, keeps the last
# message body in gh.body, and answers from files the test writes — `open` is
# the number of the open red-main issue (none when absent), `jobs.txt` the failed
# job names the API returns, `api.fail` makes the API call fail.

# rm_stub_gh — put the stub on PATH for this test.
rm_stub_gh() {
  local dir="$PWD"
  mkdir -p stub-bin
  cat > stub-bin/gh <<STUB
#!/usr/bin/env bash
d="$dir"
printf '%s\n' "\$*" >> "\$d/gh.log"
case "\$1 \$2" in
  "issue list") if [ -f "\$d/open" ]; then cat "\$d/open"; fi ;;
  "api "*)
    if [ -f "\$d/api.fail" ]; then exit 1; fi
    if [ -f "\$d/jobs.txt" ]; then cat "\$d/jobs.txt"; fi
    ;;
  "issue comment" | "issue create")
    while [ \$# -gt 0 ]; do
      if [ "\$1" = --body-file ]; then cat "\$2" > "\$d/gh.body"; fi
      shift
    done
    ;;
esac
exit 0
STUB
  chmod +x stub-bin/gh
  : > gh.log
}

# rm_run <job=result>... — run the script the way the `red-main` job does.
rm_run() {
  run env FULL="${RM_FULL:-true}" PATH="$PWD/stub-bin:$PATH" RUN_ID=42 RUN_URL=https://example.test/runs/42 \
    EVENT=push SHA=0123456789abcdef0123 GH_REPO=example/example \
    "$JIG_HOME/.github/scripts/red-main.sh" "$@"
}

test_red_main_opens_an_issue_when_main_turns_red() {
  rm_stub_gh
  printf 'ubuntu-latest 2/2\nci-ok\n' > jobs.txt
  rm_run release=skipped ci-ok=failure
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gh.log "label create red-main"
  assert_file_contains gh.log "issue create --title main is red: the ci workflow failed --label red-main"
  assert_file_contains gh.body "https://example.test/runs/42"
  assert_file_contains gh.body "- ubuntu-latest 2/2"
  assert_file_contains gh.body "0123456789ab"
}

# A repeat of the same red state is one more comment, never a second issue.
test_red_main_comments_on_the_open_issue_when_main_stays_red() {
  rm_stub_gh
  printf '7\n' > open
  printf 'release\n' > jobs.txt
  rm_run release=failure ci-ok=success
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gh.log "issue comment 7 --body-file"
  assert_not_contains "$(cat gh.log)" "issue create"
  assert_file_contains gh.body "- release"
}

test_red_main_closes_the_open_issue_when_main_turns_green() {
  rm_stub_gh
  printf '7\n' > open
  rm_run release=success ci-ok=success
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gh.log "issue close 7 --comment Green again: https://example.test/runs/42"
}

# A light run skipped the suite: its green is not evidence that main healed.
test_red_main_leaves_the_issue_open_after_a_green_light_run() {
  rm_stub_gh
  printf '7\n' > open
  RM_FULL=false rm_run release=skipped ci-ok=success
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$(cat gh.log)" "issue close"
  assert_contains "$OUT" "#7 stays open"
}

test_red_main_does_nothing_on_green_with_no_issue_open() {
  rm_stub_gh
  rm_run release=skipped ci-ok=success
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$(cat gh.log)" "issue create"
  assert_not_contains "$(cat gh.log)" "issue close"
  assert_not_contains "$(cat gh.log)" "issue comment"
}

# A cancelled run on main released nothing either.
test_red_main_counts_a_cancelled_job_as_red() {
  rm_stub_gh
  rm_run release=skipped ci-ok=cancelled
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gh.log "issue create"
}

# Without the API the message still names what failed, from the arguments.
test_red_main_names_the_failed_jobs_from_its_arguments_when_the_api_fails() {
  rm_stub_gh
  : > api.fail
  rm_run release=failure ci-ok=success
  assert_eq 0 "$RC" "$OUT"
  assert_file_contains gh.body "- release"
  assert_not_contains "$(cat gh.body)" "- ci-ok"
}

test_red_main_refuses_a_malformed_result() {
  rm_stub_gh
  rm_run ci-ok
  assert_eq 1 "$RC"
  assert_contains "$OUT" "malformed result"
}

test_red_main_refuses_no_results() {
  rm_stub_gh
  rm_run
  assert_eq 1 "$RC"
  assert_contains "$OUT" "no job results"
}
