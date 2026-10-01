#!/usr/bin/env bash
# ci-ok.sh — the verdict of the `ci-ok` job in .github/workflows/ci.yml, the
# one check a branch rule requires.
#
# A skipped job is two different things, and the old verdict counted both as a
# pass:
#
#   - decided: the job is conditional and `scope` (or the event) decided this
#     change does not need it. `knowledge` runs only when the scope is light,
#     `test` only when it is full, and so on. That is normal;
#   - undecided: by those same decisions the job should have run and did not —
#     a broken `if`, a runner that never started, a condition someone removed.
#     Nothing was checked, and nobody decided that.
#
# This script recomputes, from the outputs of `scope` and the event, which
# jobs must have run, and fails when one of them ended as anything but
# `success`. A job that need not have run may be `skipped` (or `success`);
# `failure` and `cancelled` fail either way.
#
# The expectations below mirror the `if:` of each job in ci.yml. They are the
# second copy of those conditions, on purpose: a verdict that read the same
# expression as the job would agree with it when it is wrong.
#
# Input, from the environment (set by the job from `github` and `needs`):
#   FULL      scope's `full` output ('true' or 'false')
#   WINDOWS   scope's `windows` output
#   EVENT     github.event_name
#   BASE_REF  github.base_ref   (pull requests only)
#   HEAD_REF  github.head_ref   (pull requests only)
# Arguments: one <job>=<result> per job in the `needs` list of ci-ok.
# Exit 0 when every job ended as it should, 1 otherwise.
set -eu
set -o pipefail

_ok_fail() { printf 'ci-ok: %s\n' "$*"; exit 1; }

main() {
  local pair job result expect failed=0
  local full="${FULL:-}" windows="${WINDOWS:-}" event="${EVENT:-}"
  local base="${BASE_REF:-}" head="${HEAD_REF:-}"

  [ $# -gt 0 ] || _ok_fail "no job results were reported"

  # Without scope's answer nothing can be expected, and a scope that did not
  # succeed is itself the failure.
  for pair in "$@"; do
    [ "${pair%%=*}" = scope ] || continue
    [ "${pair#*=}" = success ] || _ok_fail "scope ended as '${pair#*=}'; the scope of the change is unknown"
  done
  case "$full" in true | false) ;; *) _ok_fail "scope published no 'full' answer ('$full')" ;; esac

  for pair in "$@"; do
    job="${pair%%=*}"
    result="${pair#*=}"
    if [ -z "$job" ] || [ "$job" = "$pair" ]; then
      _ok_fail "malformed result '$pair' (want <job>=<result>)"
    fi

    case "$job" in
      scope) expect=run ;;
      knowledge)
        expect=skip
        if [ "$full" != true ]; then expect=run; fi
        ;;
      test | smoke-windows)
        expect=skip
        if [ "$full" = true ]; then expect=run; fi
        ;;
      test-windows)
        expect=skip
        if [ "$full" = true ] && [ "$windows" = true ]; then expect=run; fi
        ;;
      changelog)
        expect=skip
        if [ "$event" = pull_request ]; then expect=run; fi
        ;;
      epic-pr)
        if [ "$event" = pull_request ] && [ "$base" = main ]; then
          case "$head" in epic/*) expect=run ;; *) expect=skip ;; esac
        else
          expect=skip
        fi
        ;;
      *) _ok_fail "unknown job '$job': teach .github/scripts/ci-ok.sh what decides whether it runs" ;;
    esac

    case "$expect:$result" in
      run:success) ;;
      run:skipped) echo "ci-ok: '$job' was skipped, but the scope required it to run"; failed=1 ;;
      skip:success | skip:skipped) ;;
      *) echo "ci-ok: '$job' ended as '$result'"; failed=1 ;;
    esac
  done

  [ "$failed" -eq 0 ] || exit 1
  echo "ci-ok: every job that had to run passed"
}

main "$@"
