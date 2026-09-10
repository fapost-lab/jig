# cmd_verify — run active profiles' checks (ARCHITECTURE.md, Scripts layout;
# domains/verify). Sourced by
# scripts/jig; defines cmd_verify.
#
# Scope protocol (ADR-0013): with --changed, the changed-file list is computed
# once here and handed to each profile that declares `scope: [changed]` in its
# profile.yaml, through JIG_VERIFY_SCOPE and JIG_VERIFY_FILES. A profile that
# does not declare support is run unscoped and reported as such: a silently
# ignored scope would make `pass` mean something different per profile.
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
  local scope=0 base="" nfiles=0 scope_ok note
  JIG_VERIFY_TMP=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --changed) scope=1; shift ;;
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

  [ "$scope" = 1 ] || [ -z "$base" ] || jig_die "verify: --base requires --changed"

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
    trap 'rm -f "${JIG_VERIFY_TMP:-}"' EXIT INT TERM
    _verify_changed_files "$base" > "$JIG_VERIFY_TMP"
    nfiles=$(grep -c . < "$JIG_VERIFY_TMP" || true)
  fi

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

    # A profile without declared support is run with the scope variables
    # cleared, never merely unset by the caller's environment: an installed
    # verify.sh kept by `upgrade` as keep-modified must not read a scope it
    # was never written to honour.
    set +e
    if [ "$scope_ok" = 1 ]; then
      ( cd "$JIG_PROJECT" \
        && JIG_VERIFY_SCOPE=changed JIG_VERIFY_FILES="$JIG_VERIFY_TMP" \
           "$pdir/verify.sh" )
    else
      ( cd "$JIG_PROJECT" \
        && unset JIG_VERIFY_SCOPE JIG_VERIFY_FILES \
        && "$pdir/verify.sh" )
    fi
    rc=$?
    set -e

    case "$rc" in
      0) pass=$((pass + 1)); printf 'RESULT %s: pass%s\n' "$p" "$note" ;;
      2) skip=$((skip + 1)); printf 'RESULT %s: skip%s\n' "$p" "$note" ;;
      *) failn=$((failn + 1)); printf 'RESULT %s: fail%s\n' "$p" "$note" ;;
    esac
  done

  printf 'verify: %d profiles, %d pass, %d fail, %d skip\n' "$total" "$pass" "$failn" "$skip"
  [ "$failn" -eq 0 ]
}
