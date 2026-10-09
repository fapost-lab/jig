# shellcheck shell=bash
# Telegram messages on autopilot events (spec: notifications, phase 1;
# adr-20261009-autopilot-stops-reach-telegram).
#
# An autopilot run that stops, ends, or — unattended — approves its own design
# or decides for the person, sends one short plain-text message to the
# person's Telegram:
#
#   ⏸ <project> · <task-id>
#   <the task's short description>
#   <the journal's text>
#   <the pull request URL>            (end only, when the task has one)
#
# Sending never holds up or fails the command that triggered it: the cheap
# checks run here, everything else — reading git and task.md, curl — runs
# detached, in a process group of its own, with every descriptor on /dev/null.
# With a key missing, `notify.autopilot: false` or no curl, nothing is sent and
# nothing is printed.
#
# The bot token never reaches a command line: curl reads the URL that holds it
# from stdin (`--config -`), and the text goes form-encoded from a file
# (`--data-urlencode text@<file>`), never spliced into a config line. Nothing
# here prints the token; JIG_CFG_MASK (config.sh) is what every reader prints
# instead.
#
# The outcome of the latest send of a task is one line in `notify`, beside the
# run's journal and never in it: the journal is appended to by copy-and-`mv`
# with no lock, and a sender writing there at the moment the agent records the
# next event would lose one of the two lines.
#
# Requires task.sh (task_dir, task_state_get, _task_autopilot_mode) and
# config.sh (cfg, jig_config_clone_root, _cfg_chat_id, JIG_CFG_MASK).

# jig_notify_token_ok <token> — exit 0 when <token> has a bot token's shape,
# `<digits>:<letters, digits, _ and ->`. Checked before the token is written
# into curl's config, so a quote or a line break in a hand-edited file can
# never reach that line.
jig_notify_token_ok() {
  case "$1" in
    *[!A-Za-z0-9_:-]* | :* | *: | *:*:*) return 1 ;;
    *:*) ;;
    *) return 1 ;;
  esac
  case "${1%%:*}" in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

# jig_notify_autopilot <id> <event> <text> — send the message for one journal
# event, detached. Always exits 0 and prints nothing. Called right after the
# event was journaled, so a message never runs ahead of the record it reports.
jig_notify_autopilot() {
  local id="$1" event="$2" text="$3" token chat
  case "$event" in
    stop | end | approve | decide) ;;
    *) return 0 ;;
  esac
  case "$(cfg notify.autopilot true)" in
    false | no | 0 | off) return 0 ;;
  esac
  token=$(cfg notify.telegram.token "")
  chat=$(cfg notify.telegram.chat_id "")
  if [ -z "$token" ] || [ -z "$chat" ]; then return 0; fi
  command -v curl >/dev/null 2>&1 || return 0
  # `set -m` puts the sender in a process group of its own, so a runtime that
  # kills the command's group when the command returns does not take the
  # message with it. The braces end in `exit`, which runs the sender's own
  # cleanup list (bash 3.2 skips the EXIT trap of a subshell that runs off its
  # end).
  (
    set -m
    { _notify_send "$id" "$event" "$text" "$token" "$chat"; exit 0; } \
      </dev/null >/dev/null 2>&1 &
  ) </dev/null >/dev/null 2>&1
  return 0
}

# _notify_send <id> <event> <text> <token> <chat> — the detached half: build
# the message, send it, record the outcome. Never dies.
_notify_send() {
  set +e
  set +o pipefail
  local id="$1" event="$2" text="$3" token="$4" chat="$5" dir msg resp err code detail
  dir=$(task_dir "$id") || return 0
  [ -d "$dir" ] || return 0
  if ! jig_notify_token_ok "$token"; then
    _notify_record "$id" "$event" "failed: notify.telegram.token is not a bot token (<digits>:<letters>)"
    return 0
  fi
  if ! _cfg_chat_id "$chat"; then
    _notify_record "$id" "$event" "failed: notify.telegram.chat_id is not a chat id (digits, or @name)"
    return 0
  fi
  msg=$(mktemp "$dir/notify.text.XXXXXX") || return 0
  jig_cleanup_add "$msg"
  resp=$(mktemp "$dir/notify.resp.XXXXXX") || return 0
  jig_cleanup_add "$resp"
  err=$(mktemp "$dir/notify.err.XXXXXX") || return 0
  jig_cleanup_add "$err"
  _notify_message "$id" "$event" "$text" > "$msg"

  code=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
    | curl -q --config - -sS --max-time 10 --connect-timeout 5 \
        -o "$resp" -w '%{http_code}' \
        --data-urlencode "chat_id=$chat" \
        --data-urlencode "text@$msg" 2>"$err")
  if [ "$code" = 200 ] && grep -q '"ok":[[:space:]]*true' "$resp" 2>/dev/null; then
    _notify_record "$id" "$event" ok
    return 0
  fi
  detail=$(sed -n 's/.*"description":[[:space:]]*"\([^"]*\)".*/\1/p' "$resp" 2>/dev/null | sed -n 1p)
  [ -n "$detail" ] || detail=$(sed -n 1p "$err" 2>/dev/null)
  [ -n "$detail" ] || detail="HTTP ${code:-000}"
  case "$code" in
    '' | 000) ;;
    *) case "$detail" in "HTTP $code"*) ;; *) detail="HTTP $code: $detail" ;; esac ;;
  esac
  _notify_record "$id" "$event" "failed: $detail" "$token"
  return 0
}

# _notify_message <id> <event> <text> — the message text, lines joined by a
# newline, no trailing one: the mark with `<project> · <id>`, the task's short
# description (left out when there is none), the journal's text, and for `end`
# the pull request URL when the task has one.
_notify_message() {
  local id="$1" event="$2" text="$3" mark desc url
  case "$event" in
    stop)
      # Nothing waits for the person in an unattended run: `resume` is refused
      # there, so the mark must not ask for an answer nobody can give.
      if [ "$(_task_autopilot_mode "$id")" = unattended ]; then mark='⛔'; else mark='⏸'; fi
      ;;
    end) mark='✅' ;;
    *) mark='🤖' ;;
  esac
  if [ -z "$text" ] && [ "$event" = end ]; then text="Run ended"; fi
  printf '%s %s · %s' "$mark" "$(_notify_project)" "$id"
  desc=$(_notify_description "$id")
  [ -z "$desc" ] || printf '\n%s' "$(_notify_cut "$desc" 80)"
  [ -z "$text" ] || printf '\n%s' "$(_notify_cut "$text" 300)"
  if [ "$event" = end ]; then
    url=$(task_state_get "$id" pr_url)
    [ -z "$url" ] || printf '\n%s' "$url"
  fi
}

# _notify_project — the repository's name from origin's URL, the same in every
# clone and worktree; with no origin, the main clone's directory name (a
# worktree's directory is named after its task, not the project).
_notify_project() {
  local url
  url=$(git -C "$JIG_PROJECT" remote get-url origin 2>/dev/null)
  url=${url%/}
  url=${url%.git}
  url=${url##*/}
  url=${url##*:}
  if [ -z "$url" ]; then
    url=$(jig_config_clone_root)
    url=${url%/}
    url=${url##*/}
  fi
  printf '%s\n' "$url"
}

# _notify_description <id> — the heading of the task's task.md when it says
# more than the id, else the first sentence of its `## Goal`.
_notify_description() {
  local id="$1" file head goal
  file="$(task_dir "$id")/task.md"
  [ -f "$file" ] || return 0
  head=$(sed -n 's/^# //p' "$file" | sed -n 1p)
  head=$(printf '%s' "$head" | sed 's/[[:space:]]*$//')
  if [ -n "$head" ] && [ "$head" != "$id" ]; then
    printf '%s\n' "$head"
    return 0
  fi
  # The template's `<!-- ... -->` guidance is not a description: comments are
  # dropped, on one line or across several, before a word is kept.
  goal=$(awk '
    /^## / { if (inside) exit_now = 1; inside = ($0 ~ /^## Goal[[:space:]]*$/); next }
    exit_now || !inside { next }
    {
      line = $0
      while (1) {
        if (incomment) {
          e = index(line, "-->")
          if (e == 0) { line = ""; break }
          line = substr(line, e + 3); incomment = 0
        }
        b = index(line, "<!--")
        if (b == 0) break
        rest = substr(line, b + 4)
        e = index(rest, "-->")
        if (e == 0) { line = substr(line, 1, b - 1); incomment = 1; break }
        line = substr(line, 1, b - 1) substr(rest, e + 3)
      }
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "") { if (text != "" && !incomment && $0 !~ /-->/) exit_now = 1; next }
      text = (text == "" ? line : text " " line)
    }
    END { print text }
  ' "$file")
  case "$goal" in
    *". "*) goal="${goal%%. *}." ;;
  esac
  printf '%s\n' "$goal"
}

# _notify_cut <text> <n> — <text> cut to at most <n> characters, with `…` when
# anything was cut. Counted in characters, never bytes, and without relying on
# a UTF-8 locale being installed: under LC_ALL=C each byte is one position, and
# a UTF-8 continuation byte (0x80–0xBF) never starts a character. A cut in the
# middle of a character would hand Telegram invalid UTF-8, which it refuses.
_notify_cut() {
  local LC_ALL=C
  local s="$1" max="$2" i=0 n=0 len b
  # A character is at most four bytes: nothing past that can be kept.
  s=${s:0:$((max * 4 + 4))}
  len=${#s}
  while [ "$i" -lt "$len" ]; do
    b=${s:i:1}
    case "$b" in
      [$'\x80'-$'\xbf']) ;;
      *)
        n=$((n + 1))
        if [ "$n" -gt "$max" ]; then
          printf '%s…\n' "${s:0:i}"
          return 0
        fi
        ;;
    esac
    i=$((i + 1))
  done
  if [ "$len" -lt "${#1}" ]; then
    printf '%s…\n' "$s"
  else
    printf '%s\n' "$s"
  fi
}

# _notify_record <id> <event> <outcome> [<token>] — the task's `notify` file:
# one line, `<UTC time>\t<event>\t<ok | failed: why>`, the latest send only,
# replaced atomically. The reason is made one line with no tab, the token cut
# out of it, and kept to 200 characters.
_notify_record() {
  local id="$1" event="$2" outcome="$3" token="${4:-}" dir file tmp
  dir=$(task_dir "$id") || return 0
  [ -d "$dir" ] || return 0
  file="$dir/notify"
  outcome=$(printf '%s' "$outcome" | tr '\t\r\n' '   ')
  if [ -n "$token" ]; then
    outcome=${outcome//"$token"/$JIG_CFG_MASK}
  fi
  outcome=$(_notify_cut "$outcome" 200)
  tmp=$(mktemp "$dir/notify.tmp.XXXXXX") || return 0
  jig_cleanup_add "$tmp"
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$outcome" > "$tmp" \
    && mv "$tmp" "$file"
}

# jig_notify_failing — `<time>\t<task id>\t<why>` when the latest send of all
# tasks failed; nothing otherwise. A later success anywhere clears it, so a
# warning that stays is one that is still true. A directory whose name is not
# a valid id is skipped, never handed to a path builder.
jig_notify_failing() {
  local root f name line ts outcome best_ts="" best=""
  root="$JIG_PROJECT/$JIG_AI_DIR/workspace/tasks"
  [ -d "$root" ] || return 0
  for f in "$root"/*/notify; do
    [ -f "$f" ] || continue
    name=${f%/notify}
    name=${name##*/}
    jig_valid_id "$name" || continue
    IFS= read -r line < "$f" || [ -n "$line" ] || continue
    IFS=$'\t' read -r ts _ outcome <<EOF
$line
EOF
    [ -n "$ts" ] || continue
    # A tie in the same second goes to a failure: hiding one is the worse
    # mistake.
    if [ -z "$best_ts" ] || [[ "$ts" > "$best_ts" ]] \
      || { [ "$ts" = "$best_ts" ] && [ "${outcome#failed: }" != "$outcome" ]; }; then
      best_ts=$ts
      best="$name"$'\t'"$outcome"
    fi
  done
  [ -n "$best" ] || return 0
  case "${best#*$'\t'}" in
    "failed: "*) printf '%s\t%s\t%s\n' "$best_ts" "${best%%$'\t'*}" "${best#*$'\t'failed: }" ;;
  esac
  return 0
}
