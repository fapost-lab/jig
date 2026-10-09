# Tests for Telegram messages on autopilot events (scripts/lib/notify.sh;
# adr-20261009-autopilot-stops-reach-telegram).
#
# A stub `curl` first on PATH stands in for Telegram: it records its argv, its
# stdin (where the URL with the token must be) and the text file it was handed,
# then answers with a canned response. The sender is detached, so a test waits
# for the task's `notify` file — the sender's last act — by wall clock.
# shellcheck shell=bash

NT_TOKEN='123456:AAbbCC_dd-EEff'

# nt_setup [unattended] — an installed repository with task T-1 on an
# autopilot run, the token and chat id set, and the stub curl first on PATH.
nt_setup() {
  fixture_jig_repo
  jig task new T-1 >/dev/null
  jig task start T-1 >/dev/null
  NT_STUB=$(_run_out .stub)
  mkdir -p "$NT_STUB/bin"
  _nt_write_stub "$NT_STUB"
  PATH="$NT_STUB/bin:$PATH"
  export PATH NT_STUB
  {
    printf 'notify.telegram.token: %s\n' "$NT_TOKEN"
    printf 'notify.telegram.chat_id: -100123\n'
  } >> .ai/config.local.yaml
  [ "${1:-}" != unattended ] || printf 'autopilot.unattended: true\n' >> .ai/config.local.yaml
  jig task autopilot T-1 start >/dev/null
}

# _nt_write_stub <dir> — <dir>/bin/curl. Answers with <dir>/response (default
# `{"ok":true}`) and the HTTP code in <dir>/code (default 200), after sleeping
# <dir>/sleep seconds when that file exists.
_nt_write_stub() {
  cat > "$1/bin/curl" <<STUB
#!/bin/sh
d='$1'
out=""
: > "\$d/argv"
while [ \$# -gt 0 ]; do
  printf '%s\n' "\$1" >> "\$d/argv"
  case "\$1" in
    -o) out=\$2; printf '%s\n' "\$2" >> "\$d/argv"; shift 2; continue ;;
    --data-urlencode)
      case "\$2" in text@*) cp "\${2#text@}" "\$d/text" ;; esac
      printf '%s\n' "\$2" >> "\$d/argv"; shift 2; continue ;;
  esac
  shift
done
cat > "\$d/stdin"
ps -o pgid= -p \$\$ | tr -d ' ' > "\$d/pgid"
[ ! -f "\$d/stderr" ] || cat "\$d/stderr" >&2
[ ! -f "\$d/sleep" ] || sleep "\$(cat "\$d/sleep")"
if [ -f "\$d/response" ]; then cat "\$d/response" > "\$out"; else printf '{"ok":true,"result":{}}' > "\$out"; fi
if [ -f "\$d/code" ]; then cat "\$d/code"; else printf 200; fi
[ ! -f "\$d/exit" ] || { n=\$(cat "\$d/calls" 2>/dev/null || printf 0); printf '%s\n' \$((n + 1)) > "\$d/calls"; exit "\$(cat "\$d/exit")"; }
n=\$(cat "\$d/calls" 2>/dev/null || printf 0)
printf '%s\n' \$((n + 1)) > "\$d/calls"
STUB
  chmod +x "$1/bin/curl"
}

# nt_wait [<text>] — wait for the sender to record its outcome, one that
# contains <text> when given. A deadline sized for a loaded machine
# (conventions/shell.md, Testing): a passing test leaves at the first poll that
# sees it.
nt_wait() {
  local f=.ai/workspace/tasks/T-1/notify deadline=$((SECONDS + 60))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$f" ]; then
      case "$(cat "$f")" in *"${1:-}"*) return 0 ;; esac
    fi
    sleep 0.1
  done
  fail "the sender recorded nothing${1:+ with [$1]} in $f"
}

# nt_quiet — nothing was sent: the command has returned, and with the cheap
# checks in the command itself no sender was started at all.
nt_quiet() {
  sleep 1
  assert_no_file "$NT_STUB/calls" "curl was called"
  assert_no_file .ai/workspace/tasks/T-1/notify "a send was recorded"
}

test_notify_stop_sends_three_lines_with_the_token_only_on_stdin() {
  nt_setup
  printf '# Login redirect loses the return URL\n' > .ai/workspace/tasks/T-1/task.md
  git remote add origin git@github.com:example/shop.git
  run jig task autopilot T-1 stop --reason 'Needs you: Google or GitHub as the OAuth provider?'
  assert_eq 0 "$RC"
  assert_eq "autopilot: stopped" "$OUT"
  nt_wait
  assert_eq "$(printf '⏸ shop · T-1\nLogin redirect loses the return URL\nNeeds you: Google or GitHub as the OAuth provider?')" \
    "$(cat "$NT_STUB/text")"
  assert_file_contains "$NT_STUB/stdin" "https://api.telegram.org/bot$NT_TOKEN/sendMessage"
  assert_not_contains "$(cat "$NT_STUB/argv")" "$NT_TOKEN"
  assert_contains "$(cat "$NT_STUB/argv")" "chat_id=-100123"
  assert_file_contains .ai/workspace/tasks/T-1/notify "$(printf '\tstop\tok')"
  # The sender's outcome is beside the journal, never in it.
  assert_eq 2 "$(wc -l < .ai/workspace/tasks/T-1/autopilot | tr -d ' ')"
  # Nothing of the sender's is left behind in the workspace.
  assert_eq "" "$(find .ai/workspace/tasks/T-1 -name 'notify.*')"
}

test_notify_an_unattended_stop_is_marked_as_nothing_to_answer() {
  nt_setup unattended
  run jig task autopilot T-1 repair --reason one
  run jig task autopilot T-1 repair --reason two
  run jig task autopilot T-1 repair --reason 'tests still red'
  assert_eq 3 "$RC"
  nt_wait
  assert_contains "$(sed -n 1p "$NT_STUB/text")" "⛔"
  assert_contains "$(cat "$NT_STUB/text")" "repair limit reached (2): tests still red"
  assert_eq 1 "$(cat "$NT_STUB/calls")"
}

test_notify_approve_and_decide_send_in_an_unattended_run() {
  nt_setup unattended
  run jig task autopilot T-1 decide --reason 'Kept the old endpoint: easier to undo'
  assert_eq 0 "$RC"
  nt_wait
  assert_contains "$(sed -n 1p "$NT_STUB/text")" "🤖"
  assert_contains "$(cat "$NT_STUB/text")" "Kept the old endpoint: easier to undo"
}

test_notify_start_stage_repair_and_resume_send_nothing() {
  nt_setup
  jig task autopilot T-1 stage implement >/dev/null
  jig task autopilot T-1 repair --reason 'a red test' >/dev/null
  nt_quiet
}

test_notify_end_sends_its_text_and_the_pull_request() {
  nt_setup
  printf 'pr_url: https://github.com/example/shop/pull/7\n' >> .ai/workspace/tasks/T-1/state
  run jig task autopilot T-1 end --reason 'not merged: CI failed'
  assert_eq 0 "$RC"
  nt_wait
  assert_contains "$(sed -n 1p "$NT_STUB/text")" "✅"
  assert_contains "$(cat "$NT_STUB/text")" "not merged: CI failed"
  assert_eq "https://github.com/example/shop/pull/7" "$(tail -n 1 "$NT_STUB/text")"
  assert_file_contains .ai/workspace/tasks/T-1/autopilot "$(printf '\tend\tnot merged: CI failed')"
}

test_notify_end_without_a_reason_never_claims_a_merge() {
  nt_setup
  run jig task autopilot T-1 end
  assert_eq 0 "$RC"
  nt_wait
  assert_eq "Run ended" "$(tail -n 1 "$NT_STUB/text")"
}

test_notify_end_refuses_a_reason_with_a_line_break() {
  nt_setup
  run jig task autopilot T-1 end --reason "$(printf 'a\nb')"
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task autopilot end: --reason must be a single line with no tab"
  run jig task autopilot T-1 end --reason
  assert_eq 1 "$RC"
  assert_contains "$OUT" "task autopilot end: --reason requires a value"
}

test_notify_cuts_a_russian_description_by_characters_and_keeps_quotes() {
  nt_setup
  local long='Длинное описание задачи, которое заметно длиннее восьмидесяти символов и потому будет обрезано'
  printf '# %s\n' "$long" > .ai/workspace/tasks/T-1/task.md
  local reason='He said "yes" & a\b=c; 100% done'
  run jig task autopilot T-1 stop --reason "$reason"
  nt_wait
  local desc
  desc=$(sed -n 2p "$NT_STUB/text")
  assert_eq "Длинное описание задачи, которое заметно длиннее восьмидесяти символов и потому …" "$desc"
  # Valid UTF-8: the line survives a strict decode when iconv is there.
  if command -v iconv >/dev/null 2>&1; then
    printf '%s' "$desc" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || fail "cut produced invalid UTF-8"
  fi
  assert_eq "$reason" "$(sed -n 3p "$NT_STUB/text")"
}

test_notify_description_skips_the_templates_comment() {
  nt_setup
  # The file `jig task new` wrote: heading = id, Goal = the template comment.
  run jig task autopilot T-1 stop --reason r
  nt_wait
  assert_eq "r" "$(sed -n 2p "$NT_STUB/text")"
  assert_not_contains "$(cat "$NT_STUB/text")" "<!--"

  # A goal written below the comment, with the comment kept.
  rm -f .ai/workspace/tasks/T-1/notify
  printf '# T-1\n\n## Goal\n\n<!-- One paragraph:\nwhat must be true. -->\nKeep the return URL. More.\n\n## Scope\n' \
    > .ai/workspace/tasks/T-1/task.md
  jig task autopilot T-1 resume --answer 'go on' >/dev/null
  run jig task autopilot T-1 stop --reason r
  nt_wait
  assert_eq "Keep the return URL." "$(sed -n 2p "$NT_STUB/text")"
}

test_notify_the_sender_runs_in_a_process_group_of_its_own() {
  nt_setup
  run jig task autopilot T-1 stop --reason r
  nt_wait
  local mine
  mine=$(ps -o pgid= -p $$ | tr -d ' ')
  [ -s "$NT_STUB/pgid" ] || fail "the stub recorded no process group"
  [ "$(cat "$NT_STUB/pgid")" != "$mine" ] || fail "the sender shares the command's process group $mine"
}

test_notify_the_token_never_reaches_the_failure_record() {
  nt_setup
  printf 'curl: (7) Failed to connect to api.telegram.org/bot%s/sendMessage\n' "$NT_TOKEN" > "$NT_STUB/stderr"
  printf 7 > "$NT_STUB/exit"
  printf '' > "$NT_STUB/code"
  run jig task autopilot T-1 stop --reason r
  nt_wait failed
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/notify)" "$NT_TOKEN"
  assert_file_contains .ai/workspace/tasks/T-1/notify "bot\*\*\*\*\*\*\*\*/sendMessage"
  run jig status
  assert_contains "$OUT" "notify: Telegram messages are failing: curl: (7)"
  assert_not_contains "$OUT" "$NT_TOKEN"
}

test_notify_status_follows_the_latest_send_across_tasks() {
  nt_setup
  mkdir -p .ai/workspace/tasks/T-2
  printf '2026-01-01T00:00:00Z\tstop\tfailed: old\n' > .ai/workspace/tasks/T-1/notify
  printf '2026-01-01T00:00:05Z\tend\tok\n' > .ai/workspace/tasks/T-2/notify
  run jig status
  assert_not_contains "$OUT" "notify:"
  printf '2026-01-01T00:00:09Z\tstop\tfailed: new\n' > .ai/workspace/tasks/T-1/notify
  run jig status
  assert_contains "$OUT" "notify: Telegram messages are failing: new (task T-1, 2026-01-01T00:00:09Z)"
  # A failure and a success in the same second: the failure is shown.
  printf '2026-01-01T00:00:09Z\tend\tok\n' > .ai/workspace/tasks/T-2/notify
  run jig status
  assert_contains "$OUT" "notify: Telegram messages are failing: new"
}

test_notify_description_falls_back_to_the_goal_and_project_to_the_clone() {
  nt_setup
  printf '# T-1\n\n## Goal\n\nMake the login keep\nthe return URL. Then more.\n\n## Boundary\n\nx\n' \
    > .ai/workspace/tasks/T-1/task.md
  run jig task autopilot T-1 stop --reason r
  nt_wait
  assert_eq "Make the login keep the return URL." "$(sed -n 2p "$NT_STUB/text")"
  assert_eq "⏸ $(basename "$(pwd -P)") · T-1" "$(sed -n 1p "$NT_STUB/text")"
}

test_notify_returns_without_waiting_for_the_send() {
  nt_setup
  printf '8\n' > "$NT_STUB/sleep"
  local t0=$SECONDS
  run jig task autopilot T-1 stop --reason r
  assert_eq 0 "$RC"
  [ $((SECONDS - t0)) -lt 5 ] || fail "stop waited for the send: $((SECONDS - t0)) s"
}

test_notify_sends_nothing_without_a_token_or_chat_id() {
  nt_setup
  jig config unset notify.telegram.token --local >/dev/null
  run jig task autopilot T-1 stop --reason r
  assert_eq "autopilot: stopped" "$OUT"
  nt_quiet
}

test_notify_sends_nothing_without_a_chat_id() {
  nt_setup
  jig config unset notify.telegram.chat_id --local >/dev/null
  run jig task autopilot T-1 stop --reason r
  nt_quiet
}

test_notify_sends_nothing_when_autopilot_messages_are_off() {
  nt_setup
  jig config set notify.autopilot false --local >/dev/null
  run jig task autopilot T-1 stop --reason r
  assert_eq "autopilot: stopped" "$OUT"
  nt_quiet
}

test_notify_sends_nothing_without_curl() {
  nt_setup
  rm -f "$NT_STUB/bin/curl"
  local bin t p
  bin=$(_run_out .nocurl)
  mkdir -p "$bin"
  for t in bash sh git sed awk grep find mktemp cat cp mv rm mkdir sort tr head tail \
           wc chmod ls date dirname basename cmp paste stat readlink diff env cut \
           uname sleep tee touch xargs id hostname ps od expr printf test; do
    p=$(env -i PATH="$PATH" /bin/sh -c "command -v $t" 2>/dev/null) || continue
    case "$p" in
      /*) printf '#!/bin/sh\nexec %s "$@"\n' "$p" > "$bin/$t"; chmod +x "$bin/$t" ;;
    esac
  done
  PATH="$bin" run bash .ai/scripts/jig task autopilot T-1 stop --reason r
  assert_eq 0 "$RC"
  assert_eq "autopilot: stopped" "$OUT"
  nt_quiet
}

test_notify_ignores_a_token_in_the_project_file_and_status_names_it() {
  nt_setup
  jig config unset notify.telegram.token --local >/dev/null
  printf 'notify.telegram.token: %s\n' "$NT_TOKEN" >> .ai/config.yaml
  run jig task autopilot T-1 stop --reason r
  nt_quiet
  run jig status
  assert_contains "$OUT" "config.local: notify.telegram.token in .ai/config.yaml is ignored"
  assert_contains "$OUT" "revoke it with @BotFather"
  assert_not_contains "$OUT" "$NT_TOKEN"
}

test_notify_a_failed_send_is_reported_until_a_later_one_succeeds() {
  nt_setup
  printf '{"ok":false,"error_code":401,"description":"Unauthorized"}' > "$NT_STUB/response"
  printf 401 > "$NT_STUB/code"
  run jig task autopilot T-1 stop --reason r
  nt_wait
  assert_file_contains .ai/workspace/tasks/T-1/notify "failed: HTTP 401: Unauthorized"
  run jig status
  assert_contains "$OUT" "notify: Telegram messages are failing: HTTP 401: Unauthorized (task T-1,"
  # The journal holds the run's events only.
  assert_not_contains "$(cat .ai/workspace/tasks/T-1/autopilot)" "Unauthorized"

  # The next send succeeds, a second later so its line is the latest.
  rm -f "$NT_STUB/response" "$NT_STUB/code"
  sleep 1
  jig task autopilot T-1 resume --answer 'go on' >/dev/null
  run jig task autopilot T-1 stop --reason again
  nt_wait "$(printf '\tstop\tok')"
  run jig status
  assert_not_contains "$OUT" "notify:"
}

test_notify_a_token_of_the_wrong_shape_is_never_sent() {
  nt_setup
  jig config unset notify.telegram.token --local >/dev/null
  printf 'notify.telegram.token: abc"def\n' >> .ai/config.local.yaml
  run jig task autopilot T-1 stop --reason r
  nt_wait
  assert_no_file "$NT_STUB/calls" "curl was called with a malformed token"
  assert_file_contains .ai/workspace/tasks/T-1/notify "failed: notify.telegram.token is not a bot token"
}

test_notify_the_token_is_masked_wherever_it_would_be_printed() {
  nt_setup
  run jig config show --local
  assert_contains "$OUT" "notify.telegram.token: ********"
  assert_not_contains "$OUT" "$NT_TOKEN"
  run jig status
  assert_contains "$OUT" "config.local: notify.telegram.token=********"
  assert_not_contains "$OUT" "$NT_TOKEN"
  run jig config set notify.autopilot true --local --dry-run
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "$NT_TOKEN"
  run jig config unset notify.autopilot --local --dry-run
  assert_eq 0 "$RC"
  assert_contains "$OUT" "notify.telegram.token: ********"
  assert_not_contains "$OUT" "$NT_TOKEN"
  # A line cfg reads as the token although it is spelt differently.
  jig config unset notify.telegram.token --local >/dev/null
  printf 'notify_telegram_token: %s\n' "$NT_TOKEN" >> .ai/config.local.yaml
  run jig config show --local
  assert_not_contains "$OUT" "$NT_TOKEN"
}

test_notify_config_set_refuses_the_token_and_checks_the_rest() {
  nt_setup
  run jig config set notify.telegram.token "$NT_TOKEN" --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "config set: notify.telegram.token: refused: a bot token is never set on a command line"
  assert_not_contains "$OUT" "$NT_TOKEN"
  run jig config set notify.telegram.chat_id 12x --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not a chat id"
  run jig config set notify.telegram.chat_id @my_channel --local
  assert_eq 0 "$RC"
  run jig config set notify.telegram.chat_id -100200 --local
  assert_eq 0 "$RC"
  run jig config set notify.autopilot maybe --local
  assert_eq 1 "$RC"
  assert_contains "$OUT" "not true or false"
}
