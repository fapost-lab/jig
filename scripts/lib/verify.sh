# cmd_verify — run active profiles' checks (ARCHITECTURE.md, Scripts layout;
# domains/verify). Sourced by
# scripts/jig; defines cmd_verify.
#
# Scope protocol (ADR-0013): with --changed, the changed-file list is computed
# once here and handed to each profile that declares `scope: [changed]` in its
# profile.yaml, through JIG_VERIFY_SCOPE and JIG_VERIFY_FILES. A profile that
# does not declare support is run unscoped and reported as such: a silently
# ignored scope would make `pass` mean something different per profile.
#
# CI-backed projects (ADR-0041): `verify.full_run: ci` in .ai/config.yaml is
# the project's claim that its CI runs the full set. A flag-less `jig verify`
# then narrows to what changed since the merge base with git.base_branch,
# unless CI is set or --full is given. A project map
# (.ai/verify/<profile>.map) is parsed here, never in a profile, and handed to
# profiles declaring `scope: [changed, map]` as JIG_VERIFY_MAPPED.
# bash 3.2 compatible: no associative arrays, no ${var,,}, no mapfile.
# shellcheck shell=bash

# --- scope helpers -----------------------------------------------------------

# _verify_changed_files [<base>] — repo-relative paths of files that differ
# from <base> (when given) or from HEAD, plus untracked files, one per line,
# sorted and deduplicated. Staged and unstaged changes both count: a project
# is verified in the state it is in, not in the state it was committed in.
_verify_changed_files() {
  local base="$1"
  if [ -n "$base" ]; then
    git -C "$JIG_PROJECT" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
      || jig_die "verify: not a commit: $base"
  fi
  {
    [ -z "$base" ] || git -C "$JIG_PROJECT" diff --name-only "$base" --
    git -C "$JIG_PROJECT" rev-parse --verify --quiet HEAD >/dev/null \
      && git -C "$JIG_PROJECT" diff --name-only HEAD --
    git -C "$JIG_PROJECT" ls-files --others --exclude-standard
  } 2>/dev/null | sed '/^$/d' | LC_ALL=C sort -u
}

# _verify_ref_label <ref> — how a base ref reads in the report:
# refs/remotes/origin/main -> origin/main, refs/heads/main -> main.
_verify_ref_label() {
  local ref="$1"
  ref=${ref#refs/remotes/}
  ref=${ref#refs/heads/}
  printf '%s\n' "$ref"
}

# _verify_map_check <map> — validate a project map before anything uses it.
# Prints `<line>: <reason>` for the first bad line and exits 1; exits 0 when
# every line is usable. A line is `<glob> <decision>...` where the decision is
# `-`, `ALL`, or one or more filters; `-` and `ALL` stand alone. Checked as a
# whole, not only the lines a run happens to match: a line that is wrong today
# narrows the wrong way the day a path starts matching it.
_verify_map_check() {
  local map="$1" line n=0 glob rest tok count special
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    # A map saved on Windows ends its lines in CR; the filter must not.
    line=${line//$'\r'/}
    line=${line%%#*}
    # Word splitting must not expand a glob against the working directory.
    set -f
    # shellcheck disable=SC2086
    set -- $line
    set +f
    [ $# -gt 0 ] || continue
    glob="$1"
    shift
    [ $# -gt 0 ] || { printf '%d: no decision for %s\n' "$n" "$glob"; return 1; }
    count=$#
    special=0
    for tok in "$@"; do
      case "$tok" in
        -|ALL) special=1 ;;
      esac
    done
    if [ "$special" = 1 ] && [ "$count" -gt 1 ]; then
      rest="$*"
      printf "%d: '-' and 'ALL' stand alone: %s\n" "$n" "$rest"
      return 1
    fi
  done < "$map"
  return 0
}

# _verify_map_apply <map> <files> — one `<path><TAB><decision>` line per path
# in <files>: the tokens of the first map line whose glob matches, or `?` when
# none does. Globs follow `detect`: `**` and `*` both match across `/`, and a
# glob is matched against the path string, never the filesystem. Run only on
# a map _verify_map_check accepted.
_verify_map_apply() {
  local map="$1" files="$2" path line glob decision found
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    found=0
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line//$'\r'/}
      line=${line%%#*}
      # Word splitting must not expand a glob against the working directory.
      set -f
      # shellcheck disable=SC2086
      set -- $line
      set +f
      [ $# -gt 0 ] || continue
      glob=${1//\*\*/*}
      shift
      # shellcheck disable=SC2254
      case "$path" in
        $glob) decision="$*"; found=1; break ;;
      esac
    done < "$map"
    [ "$found" = 1 ] || decision='?'
    printf '%s\t%s\n' "$path" "$decision"
  done < "$files"
}

cmd_verify() {
  jig_require_init
  # shellcheck source=lib/profiles.sh
  . "$JIG_LIB/profiles.sh"

  # Each --profile value is split on commas only (never on internal
  # whitespace) and every resulting token is validated immediately via
  # _profiles_valid_name. Splitting on generic whitespace instead of just
  # ',' would silently turn one malformed token containing a space (e.g.
  # "a b") into two well-formed single-word names, defeating validation
  # entirely; an entirely empty value (`--profile ''`) is checked up front
  # since piping an empty string through `tr`/`read` yields zero lines, not
  # one empty line, and would otherwise be dropped rather than rejected.
  local list_only=0 profile_given=0 profiles_words="" p pdir raw tok
  local scope=0 base="" nfiles=0 scope_ok note full=0 explicit=0 full_run
  local header="" base_branch base_ref mb map map_ok map_err
  JIG_VERIFY_TMP=""
  JIG_VERIFY_MAP_TMP=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --changed) scope=1; explicit=1; shift ;;
      --full) full=1; shift ;;
      --base)
        [ $# -ge 2 ] || jig_die "verify: --base requires a value"
        base="$2"
        shift 2
        ;;
      --profile)
        [ $# -ge 2 ] || jig_die "verify: --profile requires a value"
        profile_given=1
        raw="$2"
        [ -n "$raw" ] || jig_die "invalid profile name: $raw"
        while IFS= read -r tok; do
          tok=$(printf '%s' "$tok" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
          _profiles_valid_name "$tok" || jig_die "invalid profile name: $tok"
          case " $profiles_words " in
            *" $tok "*) ;;
            *) profiles_words="$profiles_words $tok" ;;
          esac
        done < <(printf '%s\n' "$raw" | tr ',' '\n')
        shift 2
        ;;
      --list) list_only=1; shift ;;
      *) jig_die "verify: unknown argument: $1" ;;
    esac
  done
  profiles_words="${profiles_words# }"

  [ "$profile_given" = 1 ] || profiles_words=$(profiles_active)

  local installed_dir
  installed_dir=$(profiles_installed_dir)

  if [ "$list_only" = 1 ]; then
    for p in $profiles_words; do
      pdir=$(profiles_dir "$installed_dir" "$p")
      if [ -d "$pdir" ]; then
        printf '%s: installed\n' "$p"
      else
        printf '%s: not installed\n' "$p"
      fi
    done
    return 0
  fi

  # --- mode -------------------------------------------------------------------
  # `verify.full_run` is a claim the project makes, so a value that is neither
  # answer is refused rather than read as one of them: a typo must not quietly
  # narrow every run, nor quietly stop narrowing.
  full_run=$(cfg verify.full_run local)
  case "$full_run" in
    local|ci) ;;
    *) jig_die "verify: invalid verify.full_run: $full_run (expected local or ci)" ;;
  esac

  if [ "$full" = 1 ] && { [ "$scope" = 1 ] || [ -n "$base" ]; }; then
    jig_die "verify: --full cannot be combined with --changed or --base"
  fi
  if [ -n "$base" ] && [ "$scope" = 0 ]; then
    [ "$full_run" = ci ] || jig_die "verify: --base requires --changed"
    explicit=1
  fi

  if [ "$full_run" = ci ] && [ "$scope" = 0 ] && [ "$explicit" = 0 ]; then
    # Explicit narrowing (--changed, --base) wins over CI; CI and --full win
    # over the configured default. Without the CI check, a project whose CI
    # calls `jig verify` would narrow the one run the key relies on.
    if [ "$full" = 1 ]; then
      header="verify: full run (--full)"
    elif [ -n "${CI:-}" ]; then
      header="verify: full run (CI is set)"
    else
      scope=1
      base_branch=$(cfg git.base_branch main)
      base_ref=$(jig_base_ref "$base_branch")
      mb=""
      if [ -n "$base_ref" ]; then
        mb=$(git -C "$JIG_PROJECT" merge-base "$base_ref" HEAD 2>/dev/null) || mb=""
      fi
      if [ -n "$mb" ]; then
        base="$mb"
        header=$(printf 'verify: scope changed since %s@%s (verify.full_run: ci, full set runs in CI)' \
          "$(_verify_ref_label "$base_ref")" "$(git -C "$JIG_PROJECT" rev-parse --short "$mb")")
      else
        header="verify: scope changed in the working tree only, no merge base with $base_branch (verify.full_run: ci, full set runs in CI)"
      fi
    fi
  elif [ "$full_run" = ci ] && [ "$scope" = 0 ] && [ -n "$base" ]; then
    scope=1
    header=$(printf 'verify: scope changed since %s (--base)' "$base")
  fi

  # --- staleness gate --------------------------------------------------------
  # A pass from a stale install is meaningless: refuse before running any
  # profile when the current config would still need `jig upgrade` to place
  # framework-owned files (a skill or profile added to the source but never
  # copied/linked in — the gap `jig status`'s drift count used to miss
  # entirely, since drift only covers paths already recorded in the
  # manifest). Skipped only for `--list`, handled above; not folded into the
  # `verify: %d profiles, ...` tally below, which counts profiles, not
  # framework files.
  # shellcheck source=lib/upgrade.sh
  . "$JIG_LIB/upgrade.sh"
  local fw_pending fw_pending_rc=0 fw_pending_n
  fw_pending=$(upgrade_pending) || fw_pending_rc=$?
  if [ "$fw_pending_rc" = 0 ]; then
    fw_pending_n=$(printf '%s\n' "$fw_pending" | grep -c . || true)
    if [ "$fw_pending_n" -gt 0 ]; then
      printf '%s\n' "$fw_pending"
      local fw_word='files'
      if [ "$fw_pending_n" = 1 ]; then fw_word='file'; fi
      printf 'FAIL framework: %d framework %s not installed (run jig upgrade)\n' \
        "$fw_pending_n" "$fw_word"
      return 1
    fi
  fi
  # fw_pending_rc != 0: pending state unknown (e.g. no source checkout on
  # this machine, domains/install) — proceed and verify the profiles normally.

  if [ "$scope" = 1 ]; then
    JIG_VERIFY_TMP=$(mktemp "${TMPDIR:-/tmp}/jig-verify-files.XXXXXX") \
      || jig_die "verify: cannot create temporary file"
    trap 'rm -f "${JIG_VERIFY_TMP:-}" "${JIG_VERIFY_MAP_TMP:-}"' EXIT INT TERM
    _verify_changed_files "$base" > "$JIG_VERIFY_TMP"
    nfiles=$(grep -c . < "$JIG_VERIFY_TMP" || true)
  fi

  [ -z "$header" ] || printf '%s\n' "$header"

  profiles_check_requires

  local total=0 pass=0 failn=0 skip=0 rc
  for p in $profiles_words; do
    total=$((total + 1))
    pdir=$(profiles_dir "$installed_dir" "$p")

    if [ ! -d "$pdir" ]; then
      printf 'FAIL %s: not installed (run jig upgrade)\n' "$p"
      failn=$((failn + 1))
      continue
    fi

    if [ ! -f "$pdir/verify.sh" ]; then
      printf 'SKIP %s: no verify.sh\n' "$p"
      skip=$((skip + 1))
      continue
    fi

    note=""
    scope_ok=0
    if [ "$scope" = 1 ]; then
      if profiles_supports "$pdir" changed; then
        scope_ok=1
        note=" (scope: changed, $nfiles files)"
      else
        note=" (scope ignored: profile declares no scope support, ran full set)"
      fi
    fi

    if [ "$scope_ok" = 1 ] && [ "$nfiles" -eq 0 ]; then
      skip=$((skip + 1))
      printf 'RESULT %s: skip (scope: changed, no changed files)\n' "$p"
      continue
    fi

    # The project map (ADR-0041): parsed here, once, so every profile reads
    # the same decisions. A broken map fails this profile without running it
    # — a line silently skipped would narrow the checks the wrong way.
    map_ok=0
    if [ "$scope_ok" = 1 ] && profiles_supports "$pdir" map; then
      map="$JIG_AI_DIR/verify/$p.map"
      if [ -f "$JIG_PROJECT/$map" ]; then
        if ! map_err=$(_verify_map_check "$JIG_PROJECT/$map"); then
          failn=$((failn + 1))
          printf 'RESULT %s: fail (map %s:%s)\n' "$p" "$map" "$map_err"
          continue
        fi
        JIG_VERIFY_MAP_TMP=$(mktemp "${TMPDIR:-/tmp}/jig-verify-map.XXXXXX") \
          || jig_die "verify: cannot create temporary file"
        _verify_map_apply "$JIG_PROJECT/$map" "$JIG_VERIFY_TMP" > "$JIG_VERIFY_MAP_TMP"
        map_ok=1
        note=" (scope: changed, $nfiles files, map $map)"
      fi
    fi

    # A profile without declared support is run with the scope variables
    # cleared, never merely unset by the caller's environment: an installed
    # verify.sh kept by `upgrade` as keep-modified must not read a scope it
    # was never written to honour.
    set +e
    # Run through `bash`, never exec the file directly: a profile committed
    # from Windows (or by any checkout that lost the executable bit, e.g.
    # `upgrade`'s keep-modified path copying a user file) has mode 100644,
    # and the result of a check must not depend on file mode.
    if [ "$map_ok" = 1 ]; then
      ( cd "$JIG_PROJECT" \
        && JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_VERIFY_TMP" \
           JIG_VERIFY_MAPPED="$JIG_VERIFY_MAP_TMP" \
           bash "$pdir/verify.sh" )
    elif [ "$scope_ok" = 1 ]; then
      ( cd "$JIG_PROJECT" \
        && unset JIG_VERIFY_MAPPED \
        && JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_VERIFY_TMP" \
           bash "$pdir/verify.sh" )
    else
      ( cd "$JIG_PROJECT" \
        && unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES JIG_VERIFY_MAPPED \
        && bash "$pdir/verify.sh" )
    fi
    rc=$?
    set -e
    if [ "$map_ok" = 1 ]; then
      rm -f "$JIG_VERIFY_MAP_TMP"
      JIG_VERIFY_MAP_TMP=""
    fi

    case "$rc" in
      0) pass=$((pass + 1)); printf 'RESULT %s: pass%s\n' "$p" "$note" ;;
      2) skip=$((skip + 1)); printf 'RESULT %s: skip%s\n' "$p" "$note" ;;
      *) failn=$((failn + 1)); printf 'RESULT %s: fail%s\n' "$p" "$note" ;;
    esac
  done

  printf 'verify: %d profiles, %d pass, %d fail, %d skip\n' "$total" "$pass" "$failn" "$skip"
  [ "$failn" -eq 0 ]
}
