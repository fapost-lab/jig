# Terminal output: the one place that decides whether a command's report is
# read by a person at a terminal or by a pipe, and the blocks a report is
# built from (adr-20261005-output-is-decorated-only-on-a-terminal). Sourced by
# the commands that print a report through it; sourcing it twice is harmless,
# since it only defines functions and constants.
#
# Two forms, decided once per process by out_init:
#
#   - plain: stdout is not a terminal — a pipe, a file, CI, an agent. Every
#     block prints exactly the bytes the command printed before this layer
#     existed, so logs, agents and the test suite's assertions see no change.
#   - terminal: stdout is a terminal. A command may then group and reorder
#     what it says (that is its own decision, asked through out_terminal), and
#     the blocks add colour unless NO_COLOR is set or TERM is dumb.
#
# Words carry the meaning in both forms; colour only reinforces it, because a
# monochrome terminal, a colour-blind reader and a copy into a chat all lose
# it. ASCII only: a console code page may not have anything else. No tput: it
# is an external program with its own terminfo (ADR-0002), and these few SGR
# codes are understood by every terminal Jig targets, Git Bash's included.
# shellcheck shell=bash

_OUT_TERMINAL=0
_OUT_COLOR=0

_OUT_RESET=$'\033[0m'
_OUT_BOLD=$'\033[1m'
_OUT_GREEN=$'\033[32m'
_OUT_YELLOW=$'\033[33m'
_OUT_RED_BOLD=$'\033[1;31m'
_OUT_CYAN=$'\033[36m'

# The width the level word is padded to: the widest word plus one space.
_OUT_PAD='      '

# out_init — decide the form for this process. Memoises into globals, so it is
# called as a plain command, never through $(...) (conventions/shell.md).
#
# JIG_TERMINAL overrides the measurement: 1 treats stdout as a terminal (the
# tests, Windows CI, a reader piping into `less -R`), 0 never does (an agent
# whose runtime hands commands a pseudo-terminal). Anything else measures.
out_init() {
  case "${JIG_TERMINAL:-}" in
    1) _OUT_TERMINAL=1 ;;
    0) _OUT_TERMINAL=0 ;;
    *)
      if [ -t 1 ]; then _OUT_TERMINAL=1; else _OUT_TERMINAL=0; fi
      ;;
  esac
  _OUT_COLOR=0
  if [ "$_OUT_TERMINAL" = 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then
    _OUT_COLOR=1
  fi
  return 0
}

# out_terminal — exit 0 when the report is read at a terminal: the question a
# command asks before it groups or reorders anything.
out_terminal() {
  [ "$_OUT_TERMINAL" = 1 ]
}

# _out_level_color <level> — the SGR prefix for a level word, empty for an
# unknown one.
_out_level_color() {
  case "$1" in
    ok) printf '%s' "$_OUT_GREEN" ;;
    warn) printf '%s' "$_OUT_YELLOW" ;;
    fail) printf '%s' "$_OUT_RED_BOLD" ;;
    ask) printf '%s' "$_OUT_CYAN" ;;
  esac
}

# out_status <level> <text> — one status line: the level word (ok, warn, fail,
# or ask for a question; the answer is typed after it) padded to six columns, then the text. Plain form: printf '%-6s%s\n'.
out_status() {
  local level="$1" text="$2" color
  if [ "$_OUT_COLOR" = 1 ]; then
    color=$(_out_level_color "$level")
    printf '%s%s%s%s%s\n' "$color" "$level" "$_OUT_RESET" "${_OUT_PAD:${#level}}" "$text"
  else
    printf '%-6s%s\n' "$level" "$text"
  fi
}

# out_detail <label> <text> — a line that belongs to the status line above it,
# indented under its text: "      fix: <what to do>".
out_detail() {
  if [ "$_OUT_COLOR" = 1 ]; then
    printf '%s%s%s:%s %s\n' "$_OUT_PAD" "$_OUT_BOLD" "$1" "$_OUT_RESET" "$2"
  else
    printf '%s%s: %s\n' "$_OUT_PAD" "$1" "$2"
  fi
}

# out_group <level> <summary> <name>... — many items of one level said once:
# "ok    13 passed: git, git identity, ...". Nothing is printed for no names.
out_group() {
  local level="$1" summary="$2" names="" n
  shift 2
  [ $# -gt 0 ] || return 0
  for n in "$@"; do
    if [ -n "$names" ]; then names="$names, $n"; else names=$n; fi
  done
  out_status "$level" "$summary: $names"
}

# out_gap — the blank line between two groups of blocks.
out_gap() {
  printf '\n'
}

# out_summary <text> — the closing line of a report.
out_summary() {
  if [ "$_OUT_COLOR" = 1 ]; then
    printf '%s%s%s\n' "$_OUT_BOLD" "$1" "$_OUT_RESET"
  else
    printf '%s\n' "$1"
  fi
}
