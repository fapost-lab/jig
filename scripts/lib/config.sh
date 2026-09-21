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
# `agent.git` is also in JIG_CFG_LOCAL_ONLY_KEYS below: it answers *only* from
# this list, never falling back to the project layer the way every other key
# here does.
JIG_CFG_LOCAL_KEYS="housekeeping.cadence housekeeping.fetch housekeeping.trash_ttl housekeeping.abandoned_ttl housekeeping.stale_after git.worktree_root agent.git"

# Keys whose project-layer value `cfg` never reads at all: only the local
# file and the default answer. A key belongs here, rather than merely in
# JIG_CFG_LOCAL_KEYS, when a value committed to .ai/config.yaml would hand
# every contributor the same thing a local key exists to keep personal —
# `agent.git` grants an agent git rights, and a project-wide grant would make
# every contributor's agent commit, whether that contributor agreed to it or
# not (spec: .ai/specs/autopilot/). `jig_config_project_ignored` reports a
# project-layer value here so it does not silently do nothing.
JIG_CFG_LOCAL_ONLY_KEYS="agent.git"

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

# jig_agent_git — print agent.git's level (none|commit|push|pr, default
# none) and exit 0; for anything else, still print the value read (so a
# caller can report *what* was invalid) and exit 1. Never `jig_die`s itself:
# `jig status` must be able to report an invalid value without dying, the
# same reason `_hk_forge_init`/`jig_forge_kind` split validation from the die
# they do use in a command that may fairly refuse to run at all.
jig_agent_git() {
  local value
  value=$(cfg agent.git none)
  case "$value" in
    none | commit | push | pr) printf '%s\n' "$value"; return 0 ;;
    *) printf '%s\n' "$value"; return 1 ;;
  esac
}
