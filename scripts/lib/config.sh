# Reader for .ai/config.yaml — flat YAML subset (domains/install).
# Keys are `section.key: value`; lists are inline `[a, b]`; no nesting.
#
# Two layers (ADR-0038): .ai/config.local.yaml, gitignored and owned by the
# person whose clone it is, then .ai/config.yaml, committed and owned by the
# project. The local layer answers only for JIG_CFG_LOCAL_KEYS.
# shellcheck shell=bash

# Keys whose answer may differ between contributors without changing what the
# project does: they govern gitignored state on one machine, or a place on its
# disk. Everything else — base branch, profiles, forge — must be the same for
# every contributor and for CI, so a local value for it is ignored and
# reported by `jig status`. Adding a key here is a decision about that test,
# not a convenience; record it in schemas/config.md.
#
# `agent.git`, `agent.ci_timeout` and `autopilot.unattended` are also in
# JIG_CFG_LOCAL_ONLY_KEYS below: they answer *only* from this list, never
# falling back to the project layer the way every other key here does.
JIG_CFG_LOCAL_KEYS="housekeeping.cadence housekeeping.fetch housekeeping.trash_ttl housekeeping.abandoned_ttl housekeeping.stale_after git.worktree_root agent.git agent.ci_timeout autopilot.unattended"

# Keys whose project-layer value `cfg` never reads at all: only the local
# file and the default answer. A key belongs here, rather than merely in
# JIG_CFG_LOCAL_KEYS, when a value committed to .ai/config.yaml would hand
# every contributor the same thing a local key exists to keep personal —
# `agent.git` grants an agent git rights, and a project-wide grant would make
# every contributor's agent commit, whether that contributor agreed to it or
# not (spec: .ai/specs/autopilot/). `autopilot.unattended` lets a run ask
# nothing and `agent.ci_timeout` bounds how long a merge waits for CI: both
# decide what one person's agent does on their behalf, for the same reason
# (adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci).
# `jig_config_project_ignored` reports a project-layer value here so it does
# not silently do nothing.
JIG_CFG_LOCAL_ONLY_KEYS="agent.git agent.ci_timeout autopilot.unattended"

# Path of the config file for the current project (JIG_PROJECT must be set).
jig_config_file() { printf '%s/%s/config.yaml\n' "$JIG_PROJECT" "$JIG_AI_DIR"; }

# jig_config_clone_root — the main checkout of the clone JIG_PROJECT belongs
# to. A worktree answers with the checkout it was added from, so one local
# file serves every worktree of a clone, including one made after the file.
#
# Read from git's own files rather than `git rev-parse --git-common-dir`: cfg
# runs in a command substitution per key, where a cached answer does not
# survive, and the session hook promises no git on its idle path. A worktree's
# `.git` is a file naming its git directory, and that directory's `commondir`
# names the shared one. Anything else — a main checkout, a submodule (no
# commondir), a separate git dir or a bare repository (common dir not named
# .git) — answers JIG_PROJECT itself.
jig_config_clone_root() {
  local line="" gitdir root
  if [ -f "$JIG_PROJECT/.git" ]; then
    IFS= read -r line < "$JIG_PROJECT/.git" || [ -n "$line" ] || line=""
    gitdir=${line#gitdir: }
    if [ -n "$gitdir" ] && [ "$gitdir" != "$line" ]; then
      root=$(
        common="" here=""
        cd "$JIG_PROJECT" 2>/dev/null || exit 1
        cd "$gitdir" 2>/dev/null || exit 1
        [ -f commondir ] || exit 1
        IFS= read -r common < commondir || [ -n "$common" ] || exit 1
        cd "$common" 2>/dev/null || exit 1
        # No `case` here: bash 3.2 misparses its `)` inside `$( )`.
        here=$(pwd -P)
        [ "${here##*/}" = .git ] || exit 1
        cd .. && pwd -P
      ) && { printf '%s\n' "$root"; return 0; }
    fi
  fi
  printf '%s\n' "$JIG_PROJECT"
}

# Path of the local config file for the current clone.
jig_config_local_file() { printf '%s/%s/config.local.yaml\n' "$(jig_config_clone_root)" "$JIG_AI_DIR"; }

# jig_config_local_key <key> — exit 0 when <key> may be set in the local file.
jig_config_local_key() {
  case " $JIG_CFG_LOCAL_KEYS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# jig_config_local_only_key <key> — exit 0 when <key> answers only from the
# local file and the default: the project layer is never consulted for it
# (JIG_CFG_LOCAL_ONLY_KEYS).
jig_config_local_only_key() {
  case " $JIG_CFG_LOCAL_ONLY_KEYS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# jig_config_project_ignored — "<key><TAB><value>" for every local-only key
# that is nonetheless set in the project's .ai/config.yaml, where `cfg` never
# reads it. Reporting only, for `jig status` and `jig doctor`: nothing here
# changes what `cfg` answers.
jig_config_project_ignored() {
  local key value
  for key in $JIG_CFG_LOCAL_ONLY_KEYS; do
    value=$(_cfg_read "$(jig_config_file)" "$key")
    [ -n "$value" ] || continue
    printf '%s\t%s\n' "$key" "$value"
  done
}

# jig_config_local_ignored — exit 0 when git ignores the local file, so its
# settings cannot reach a commit. Only reporting commands ask: cfg reads the
# file either way (ADR-0038), and this costs a git process.
jig_config_local_ignored() {
  local root
  root=$(jig_config_clone_root)
  git -C "$root" check-ignore -q "$JIG_AI_DIR/config.local.yaml" 2>/dev/null
}

# jig_config_local_entries — one `<key><TAB><value><TAB>local|ignored` line per
# key set in the local file, in file order; nothing when there is no file.
# `ignored` is a key outside JIG_CFG_LOCAL_KEYS, including a misspelt one.
jig_config_local_entries() {
  local file key value
  file=$(jig_config_local_file)
  [ -f "$file" ] || return 0
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    value=$(_cfg_read "$file" "$key")
    [ -n "$value" ] || continue
    if jig_config_local_key "$key"; then
      printf '%s\t%s\tlocal\n' "$key" "$value"
    else
      printf '%s\t%s\tignored\n' "$key" "$value"
    fi
  done < <(sed -n 's/^\([A-Za-z0-9_.-]*\):.*/\1/p' "$file" | awk '!seen[$0]++')
}

# _cfg_read <file> <key> — the value of <key> in one file, or nothing.
# The first matching line wins; a trailing `# comment` is not part of it.
_cfg_read() {
  [ -f "$1" ] || return 0
  sed -n "s/^${2}:[[:space:]]*//p" "$1" | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//' | head -n 1
}

# cfg <key> [default] — print the scalar value of <key>: the local file when
# the key may be set there, then .ai/config.yaml, then the default. An empty
# value falls through to the next layer. A JIG_CFG_LOCAL_ONLY_KEYS key stops
# after the local file: its project layer is never read, by design (see the
# comment above that list).
cfg() {
  local key="$1" default="${2:-}" value=""
  if jig_config_local_key "$key"; then
    value=$(_cfg_read "$(jig_config_local_file)" "$key")
  fi
  if [ -z "$value" ] && ! jig_config_local_only_key "$key"; then
    value=$(_cfg_read "$(jig_config_file)" "$key")
  fi
  printf '%s\n' "${value:-$default}"
}

# cfg_list <key> [default-list] — print an inline list as space-separated words.
cfg_list() {
  cfg "$1" "${2:-}" | tr -d '[]' | tr ',' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

# cfg_bool <key> [default] — exit 0 when the value is true/yes/1.
cfg_bool() {
  case "$(cfg "$1" "${2:-false}")" in
    true|yes|1|on) return 0 ;;
    *) return 1 ;;
  esac
}

# jig_agent_git — print agent.git's level (none|commit|push|pr|merge,
# default none) and exit 0; for anything else, still print the value read (so a
# caller can report *what* was invalid) and exit 1. Never `jig_die`s itself:
# `jig status` must be able to report an invalid value without dying, the
# same reason `_hk_forge_init`/`jig_forge_kind` split validation from the die
# they do use in a command that may fairly refuse to run at all.
jig_agent_git() {
  local value
  value=$(cfg agent.git none)
  printf '%s\n' "$value"
  _cfg_agent_git_level "$value"
}

# _cfg_agent_git_level <value> — exit 0 when <value> is an agent.git level.
# Shared by the reader above and `jig config set`, so the two cannot disagree.
_cfg_agent_git_level() {
  case "$1" in
    none | commit | push | pr | merge) return 0 ;;
    *) return 1 ;;
  esac
}

# jig_ci_timeout — print agent.ci_timeout, the minutes a merge waits for the
# pull request's checks (default 30; 0 looks once and does not wait), and exit
# 0; for anything but a whole number, print the value read and exit 1, like
# jig_agent_git.
jig_ci_timeout() {
  local value
  value=$(cfg agent.ci_timeout 30)
  if ! _cfg_minutes "$value"; then
    printf '%s\n' "$value"
    return 1
  fi
  printf '%s\n' "$((10#$value))"
}

# _cfg_minutes <value> — exit 0 when <value> is a whole number of minutes
# agent.ci_timeout accepts: digits only, at most four of them.
_cfg_minutes() {
  case "$1" in
    '' | *[!0-9]* | ?????*) return 1 ;;
    *) return 0 ;;
  esac
}

# jig_unattended — exit 0 when this clone opted in to autopilot runs that ask
# nothing (`autopilot.unattended: true`, local-only). Read once by `task
# autopilot start`, which records the answer for the run, and by `spec ship`,
# whose epic finish has no run to record it in.
jig_unattended() {
  [ "$(cfg autopilot.unattended false)" = true ]
}

# jig_config_value_problem <key> <value> — print why <value> cannot be set for
# the local key <key>, and exit 1; print nothing and exit 0 when it can. The
# rules are the readers' own, so a value `jig config set` accepts is one every
# reader understands the way the person meant it:
# - housekeeping.cadence: whole days (`<n>d` or `<n>`), because the session
#   hook and `jig status` read it in days and treat anything else as 1d;
# - the other housekeeping durations: `<n>[dhms]`, `jig_duration_seconds`;
# - housekeeping.fetch and autopilot.unattended: `true` or `false` — cfg_bool
#   would take yes/1/on too, jig_unattended only `true`; the one spelling
#   both read alike;
# - agent.git and agent.ci_timeout: the checks of jig_agent_git and
#   jig_ci_timeout;
# - git.worktree_root: any path _cfg_read gives back unchanged.
# Nothing may hold a line break, a `#` (_cfg_read cuts a comment there) or
# surrounding blanks (it trims them).
jig_config_value_problem() {
  local key="$1" value="$2" nl cr
  nl=$(printf '\nx'); nl=${nl%x}
  cr=$(printf '\r')
  case "$value" in
    '') printf 'an empty value; leave the key out to use the default\n'; return 1 ;;
    *"$nl"* | *"$cr"*) printf 'a line break\n'; return 1 ;;
    *'#'*) printf "a '#', which the file reads as the start of a comment\n"; return 1 ;;
    [[:space:]]* | *[[:space:]]) printf 'leading or trailing blanks\n'; return 1 ;;
  esac
  case "$key" in
    housekeeping.cadence)
      case "${value%d}" in
        '' | *[!0-9]* | ?????????*) printf 'not a whole number of days (e.g. 1d, 3d)\n'; return 1 ;;
      esac
      ;;
    housekeeping.trash_ttl | housekeeping.abandoned_ttl | housekeeping.stale_after)
      case "${value%[dhms]}" in
        '' | *[!0-9]* | ?????????*) printf 'not a duration (e.g. 7d, 12h, 30m, 90s)\n'; return 1 ;;
      esac
      ;;
    housekeeping.fetch | autopilot.unattended)
      case "$value" in
        true | false) ;;
        *) printf 'not true or false\n'; return 1 ;;
      esac
      ;;
    agent.git)
      _cfg_agent_git_level "$value" \
        || { printf 'not a level: none, commit, push, pr or merge\n'; return 1; }
      ;;
    agent.ci_timeout)
      _cfg_minutes "$value" \
        || { printf 'not a whole number of minutes (0 to 9999)\n'; return 1; }
      ;;
    git.worktree_root)
      case "$value" in
        \"* | \'*) printf 'quoted; write the path without quotes\n'; return 1 ;;
      esac
      ;;
    *) printf 'not a local key\n'; return 1 ;;
  esac
  return 0
}

# --- jig config ---------------------------------------------------------------
# `jig config set <key> <value> [<key> <value>...] --local [--dry-run]` and
# `jig config show --local`. Writes only the clone's .ai/config.local.yaml,
# only keys in JIG_CFG_LOCAL_KEYS, only values the readers accept, and never
# .ai/config.yaml: that file is the team's, edited by hand and reviewed like
# code (ADR-0038).

# Referenced from the EXIT trap, so global (convention-shell).
_CONFIG_TMP=""

cmd_config() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    set) _config_set "$@" ;;
    show) _config_show "$@" ;;
    help | -h | --help)
      printf 'usage: jig config set <key> <value> [<key> <value>...] --local [--dry-run]\n'
      printf '       jig config show --local\n'
      printf 'local keys: %s\n' "$JIG_CFG_LOCAL_KEYS"
      ;;
    '') jig_die "config: missing subcommand (usage: jig config set|show ... --local)" ;;
    *) jig_die "config: unknown subcommand: $sub (usage: jig config set|show ... --local)" ;;
  esac
}

# _config_display_path <file> — <file> relative to the project when inside it.
_config_display_path() {
  case "$1" in
    "$JIG_PROJECT"/*) printf '%s\n' "${1#"$JIG_PROJECT"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

_config_refuse_project() {
  jig_die "config $1: only --local is supported: .ai/config.yaml is the team's file, edited by hand and reviewed like code; your own settings go in .ai/config.local.yaml (jig config $1 ... --local)"
}

# _config_warn_ignored <shown path> — the warning `jig status` prints.
_config_warn_ignored() {
  jig_config_local_ignored \
    || jig_warn "config: $1 is not ignored by git and can be committed (fix: jig init)"
}

_config_show() {
  local local_flag=0 file shown
  while [ $# -gt 0 ]; do
    case "$1" in
      --local) local_flag=1; shift ;;
      *) jig_die "config show: unknown argument: $1 (usage: jig config show --local)" ;;
    esac
  done
  [ "$local_flag" = 1 ] || _config_refuse_project show
  jig_require_repo
  file=$(jig_config_local_file)
  shown=$(_config_display_path "$file")
  if [ ! -f "$file" ]; then
    printf 'no local settings: %s does not exist\n' "$shown"
    return 0
  fi
  cat "$file"
}

# _config_apply <in> <out> <key> <value> — <in> with <key> set to <value>: the
# first `<key>:` line replaced, the one `cfg` reads, else a line appended.
# The value reaches awk through the environment, where a backslash in a path
# stays a backslash (`awk -v` would read it as an escape).
_config_apply() {
  JIG_CFG_KEY="$3" JIG_CFG_VALUE="$4" awk '
    BEGIN { k = ENVIRON["JIG_CFG_KEY"]; v = ENVIRON["JIG_CFG_VALUE"]; n = length(k) + 1 }
    !done && substr($0, 1, n) == k ":" { print k ": " v; done = 1; next }
    { print }
    END { if (!done) print k ": " v }
  ' "$1" > "$2"
}

_config_set() {
  local local_flag=0 dry=0 n=0 key value problem file dir shown i
  # The pairs, in order: an array, because a value is checked for line breaks
  # below and must reach that check intact.
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --local) local_flag=1; shift ;;
      --dry-run) dry=1; shift ;;
      --*) jig_die "config set: unknown flag: $1 (usage: jig config set <key> <value> [<key> <value>...] --local [--dry-run])" ;;
      *) args[n]="$1"; n=$((n + 1)); shift ;;
    esac
  done
  [ "$local_flag" = 1 ] || _config_refuse_project set
  if [ "$n" -eq 0 ] || [ $((n % 2)) -ne 0 ]; then
    jig_die "config set: expected <key> <value> pairs (usage: jig config set <key> <value> [<key> <value>...] --local [--dry-run])"
  fi

  # Every pair is checked before anything is written: one bad value leaves
  # the file as it was.
  i=0
  while [ "$i" -lt "$n" ]; do
    key=${args[i]}; value=${args[i + 1]}
    if ! jig_config_local_key "$key"; then
      jig_die "config set: $key is not a local key; the local file answers only for: $JIG_CFG_LOCAL_KEYS (anything else belongs to the team's .ai/config.yaml, edited by hand)"
    fi
    if ! problem=$(jig_config_value_problem "$key" "$value"); then
      jig_die "config set: $key: invalid value '$value': $problem"
    fi
    i=$((i + 2))
  done

  jig_require_repo
  file=$(jig_config_local_file)
  dir=${file%/*}
  shown=$(_config_display_path "$file")
  [ -d "$dir" ] || jig_die "config set: no $JIG_AI_DIR/ directory at ${dir%/*}; run jig init there first"

  _CONFIG_TMP="$file.tmp.$$"
  trap 'rm -f "$_CONFIG_TMP" "$_CONFIG_TMP.next"' EXIT
  if [ -f "$file" ]; then
    cat "$file" > "$_CONFIG_TMP"
  else
    printf '%s\n' \
      "# Your own Jig settings for this clone: gitignored, never committed." \
      "# Only local keys are read from here (jig config set --local)." > "$_CONFIG_TMP"
  fi
  i=0
  while [ "$i" -lt "$n" ]; do
    _config_apply "$_CONFIG_TMP" "$_CONFIG_TMP.next" "${args[i]}" "${args[i + 1]}"
    mv "$_CONFIG_TMP.next" "$_CONFIG_TMP"
    i=$((i + 2))
  done

  if [ "$dry" = 1 ]; then
    cat "$_CONFIG_TMP"
    rm -f "$_CONFIG_TMP"
    printf 'config: dry run, nothing written to %s\n' "$shown" >&2
    _config_warn_ignored "$shown"
    return 0
  fi
  mv "$_CONFIG_TMP" "$file"
  i=0
  while [ "$i" -lt "$n" ]; do
    printf 'config: %s: %s (%s)\n' "${args[i]}" "${args[i + 1]}" "$shown"
    i=$((i + 2))
  done
  _config_warn_ignored "$shown"
}
