# Where a project's checks run (adr-20261001-checks-run-where-the-project-runs;
# domains/verify). Sourced by verify.sh; defines runenv_resolve.
#
# `jig verify` decides once, before any profile starts, whether the project's
# commands run on this machine or through a command prefix that reaches the
# environment the project actually lives in (`docker compose exec -T -w <dir>
# <service>`). The answer comes from one local-only key, `run.exec`:
#
#   auto      (default) the detectors below; no detector and no sign that the
#             project lives in a container means the host
#   host      this machine, signs not consulted
#   <prefix>  plain words put in front of every command a profile runs
#
# A sign without a detector is a refusal, never a quiet run on the host: a
# Laravel app on Sail whose `.env` says DB_HOST=mysql gave a wrong verdict
# from the host's PHP against a database that does not resolve there.
#
# With CI set, `auto` neither detects nor refuses: CI describes its own
# environment, and a project's existing pipeline must not change under it.
# bash 3.2 compatible.
# shellcheck shell=bash

RUNENV_EXEC=""
RUNENV_WHERE=""
RUNENV_UP=""
RUNENV_REFUSAL=""

# _runenv_compose_file — the project's compose file, relative to JIG_PROJECT,
# in the order docker compose itself looks for one; nothing when there is none.
_runenv_compose_file() {
  local f
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [ -f "$JIG_PROJECT/$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 0
}

# _runenv_compose_read <file> — what the detectors need from a compose file:
# `S<TAB><service>` for every top-level service, `M<TAB><service><TAB>
# <target>` for every short-syntax volume that mounts the project root
# (`.:/x`, `./:/x`, quoted or not, with or without a mode), and
# `U<TAB><service>` for a volume that seems to mount it in a form this reader
# does not take apart — the long syntax (`source: .`), `$PWD`, or a flow list.
# A reader of the subset compose files are written in, not a YAML parser: what
# it cannot read becomes a sign rather than a detection, the cautious side.
# Line ends are CRLF-tolerant: a Windows checkout of the file reads the same.
_runenv_compose_read() {
  awk -v q="'" '
    function strip(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function unquote(s) {
      s = strip(s)
      if (s ~ ("^[\"" q "]")) s = substr(s, 2)
      if (s ~ ("[\"" q "]$")) s = substr(s, 1, length(s) - 1)
      return s
    }
    { sub(/\r$/, "") }
    /^[ \t]*(#|$)/ { next }
    {
      match($0, /^ */); ind = RLENGTH
      line = substr($0, ind + 1)
      if (ind == 0) {
        insvc = (line ~ /^services:[ \t]*(#.*)?$/); svcind = -1; svc = ""; keyind = -1; invol = 0
        next
      }
      if (!insvc) next
      if (svcind < 0) svcind = ind
      if (ind < svcind) next
      if (ind == svcind) {
        svc = line; sub(/:.*$/, "", svc); svc = unquote(svc)
        print "S\t" svc
        keyind = -1; invol = 0
        next
      }
      if (keyind < 0) keyind = ind
      if (ind == keyind && line !~ /^- /) {
        invol = (line ~ /^volumes:/)
        if (invol && line ~ /^volumes:[ \t]*\[/ && line ~ /(["\[, ]\.\/?:|PWD)/) print "U\t" svc
        next
      }
      if (ind < keyind || !invol) next
      if (line ~ /^- /) {
        v = unquote(substr(line, 3))
        n = split(v, p, ":")
        if ((p[1] == "." || p[1] == "./") && n >= 2 && p[2] != "") { print "M\t" svc "\t" p[2]; next }
        if (p[1] ~ /PWD/) { print "U\t" svc; next }
        line = v
      }
      sub(/^- /, "", line)
      if (line ~ /^source:/) {
        v = line; sub(/^source:/, "", v); v = unquote(v)
        if (v == "." || v == "./" || v ~ /PWD/) print "U\t" svc
      }
    }
  ' "$1"
}

# _runenv_dotenv <key> — the value of <key> in the project's .env, quotes
# stripped; the last assignment wins, as in a shell. Nothing when unset.
_runenv_dotenv() {
  [ -f "$JIG_PROJECT/.env" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$JIG_PROJECT/.env" \
    | sed -n '$p' | tr -d '\r' | sed "s/^[\"']//; s/[\"']\$//"
}

# _runenv_detect — set RUNENV_EXEC, RUNENV_WHERE and RUNENV_UP from the first
# detector that recognises the project; exit 1 when none does. Order: Laravel
# Sail, then a docker compose service that mounts the project root.
_runenv_detect() {
  local file data svc target mounts unread n
  file=$(_runenv_compose_file)
  [ -n "$file" ] || return 1
  data=$(_runenv_compose_read "$JIG_PROJECT/$file")
  mounts=$(printf '%s\n' "$data" | sed -n 's/^M	//p')
  unread=$(printf '%s\n' "$data" | sed -n 's/^U	//p')
  [ -n "$mounts" ] || return 1

  # Sail: its own launcher is installed and the service it runs commands in
  # (APP_SERVICE, laravel.test unless .env names another) mounts the project.
  # Sail runs them as its `sail` user; root would leave root-owned files in
  # the mounted tree.
  if [ -f "$JIG_PROJECT/vendor/bin/sail" ]; then
    svc=$(_runenv_dotenv APP_SERVICE)
    [ -n "$svc" ] || svc=laravel.test
    target=$(printf '%s\n' "$mounts" | awk -F '\t' -v s="$svc" '$1 == s && !f { print $2; f = 1 }')
    if [ -n "$target" ]; then
      RUNENV_EXEC="docker compose exec -T -u sail -w $target $svc"
      RUNENV_WHERE="$RUNENV_EXEC (Laravel Sail, detected)"
      RUNENV_UP="./vendor/bin/sail up -d"
      return 0
    fi
  fi

  # One service, read in full: a second one, or a mount of the project this
  # reader could not take apart, leaves the choice to a person.
  [ -z "$unread" ] || return 1
  n=$(printf '%s\n' "$mounts" | cut -f1 | sort -u | grep -c .)
  [ "$n" -eq 1 ] || return 1
  mounts=$(printf '%s\n' "$mounts" | sed -n '1p')
  svc=$(printf '%s\n' "$mounts" | cut -f1)
  target=$(printf '%s\n' "$mounts" | cut -f2)
  RUNENV_EXEC="docker compose exec -T -w $target $svc"
  RUNENV_WHERE="$RUNENV_EXEC (docker compose service $svc, detected)"
  RUNENV_UP="docker compose up -d"
  return 0
}

# _runenv_signs — the reasons to believe the project lives in a container that
# no detector recognised, joined with "; "; nothing when there are none. A
# compose file alone is not one: a database in a container beside an app on
# the host is an ordinary setup that runs its checks on the host today.
_runenv_signs() {
  local file data services mounts unread n db signs=""
  file=$(_runenv_compose_file)
  if [ -n "$file" ]; then
    data=$(_runenv_compose_read "$JIG_PROJECT/$file")
    services=$(printf '%s\n' "$data" | sed -n 's/^S	//p')
    mounts=$(printf '%s\n' "$data" | sed -n 's/^M	//p' | cut -f1 | sort -u)
    unread=$(printf '%s\n' "$data" | sed -n 's/^U	//p' | sort -u)
    n=$(printf '%s\n' "$mounts" | grep -c . || true)
    if [ "$n" -gt 1 ]; then
      signs="$signs; $n services in $file mount the project ($(printf '%s\n' "$mounts" | paste -sd, -))"
    fi
    if [ -n "$unread" ]; then
      signs="$signs; $(printf '%s\n' "$unread" | paste -sd, -) in $file mounts the project in a form jig does not read (long syntax, \$PWD or a flow list)"
    fi
    db=$(_runenv_dotenv DB_HOST)
    if [ -n "$db" ] && jig_has_line "$db" "$services"; then
      signs="$signs; .env sets DB_HOST=$db, a service in $file"
    fi
  fi
  if [ -d "$JIG_PROJECT/.devcontainer" ] || [ -f "$JIG_PROJECT/.devcontainer.json" ]; then
    signs="$signs; a devcontainer is defined"
  fi
  [ ! -d "$JIG_PROJECT/.ddev" ] || signs="$signs; a DDEV project (.ddev/)"
  [ ! -f "$JIG_PROJECT/.lando.yml" ] || signs="$signs; a Lando project (.lando.yml)"
  printf '%s\n' "${signs#; }"
}

# _runenv_probe — exit 0 when the environment answers and shows this
# checkout; otherwise set RUNENV_REFUSAL and exit 1. One command for both
# questions: it fails when the container is not running or docker is not
# there, and its output is the environment's own `.git`. In a linked
# worktree `.git` is a file naming this worktree, so an environment that
# mounted the main checkout instead would show different text — and its
# verdict would be about other code. A main checkout is not compared: a
# container need not mount `.git` at all.
_runenv_probe() {
  local err out rc=0 mine last
  local -a pre
  read -r -a pre <<EOF
$RUNENV_EXEC
EOF
  # Without a file for its error output the probe still runs, and only the
  # refusal loses the environment's own words.
  if err=$(mktemp "${TMPDIR:-/tmp}/jig-runenv.XXXXXX"); then
    jig_cleanup_add "$err"
  else
    err=/dev/null
  fi
  out=$( cd "$JIG_PROJECT" && "${pre[@]}" sh -c 'cat .git 2>/dev/null; exit 0' </dev/null 2>"$err" ) || rc=$?
  last=""
  if [ "$err" != /dev/null ]; then
    last=$(sed '/^[[:space:]]*$/d' "$err" | sed -n '$p')
    rm -f "$err"
  fi
  if [ "$rc" -ne 0 ]; then
    RUNENV_REFUSAL="the environment is not running ($RUNENV_WHERE)${last:+: $last}"
    if [ -n "$RUNENV_UP" ]; then
      RUNENV_REFUSAL="$RUNENV_REFUSAL; start it with: $RUNENV_UP"
    else
      RUNENV_REFUSAL="$RUNENV_REFUSAL; start it, then run jig verify again"
    fi
    return 1
  fi
  if [ -f "$JIG_PROJECT/.git" ]; then
    mine=$(tr -d '\r' < "$JIG_PROJECT/.git")
    out=$(printf '%s\n' "$out" | tr -d '\r')
    if [ "$out" != "$mine" ]; then
      RUNENV_REFUSAL="the environment does not see this checkout ($RUNENV_WHERE): it mounts another copy of the project, so its verdict would be about other code; give this worktree an environment of its own, or run jig verify in the checkout the environment mounts"
      return 1
    fi
  fi
  return 0
}

# runenv_resolve — decide where the project's checks run. Sets RUNENV_EXEC
# (empty for the host), RUNENV_WHERE (what to tell a person), RUNENV_UP (how
# to start the environment, when known) and RUNENV_REFUSAL (non-empty: do not
# run anything, and say this). Needs cfg (config.sh) and JIG_PROJECT.
runenv_resolve() {
  local value signs
  RUNENV_EXEC=""
  RUNENV_WHERE="host"
  RUNENV_UP=""
  RUNENV_REFUSAL=""
  value=$(cfg run.exec auto)
  case "$value" in
    host)
      RUNENV_WHERE="host (run.exec: host)"
      return 0
      ;;
    auto)
      if [ -n "${CI:-}" ]; then
        RUNENV_WHERE="host (CI is set)"
        return 0
      fi
      if ! _runenv_detect; then
        signs=$(_runenv_signs)
        if [ -n "$signs" ]; then
          RUNENV_REFUSAL="this project looks like it runs in a container ($signs), and jig does not know how to run its checks there — run the jig-setup skill, or set the command prefix yourself: jig config set run.exec '<prefix>' --local (run.exec host runs them on this machine)"
        fi
        return 0
      fi
      ;;
    *)
      RUNENV_EXEC="$value"
      RUNENV_WHERE="$value (run.exec)"
      ;;
  esac
  _runenv_probe || true
  return 0
}
