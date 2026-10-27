#!/usr/bin/env bash
# red-main.sh — the `red-main` job in .github/workflows/ci.yml: tells the
# owner when `ci` fails on main, through a GitHub issue, so that GitHub's own
# notification (mail, app) carries the news. No secret is needed: the job's
# GITHUB_TOKEN may write issues.
#
# Why it exists: after #318 main went red three times in a row — two pushes
# and a nightly run — and nobody noticed, so 0.36.0 was never tagged while the
# documentation already described it. A red run on main was visible only to
# whoever opened the Actions page.
#
# One open issue labelled `red-main` stands for "main is red":
#
#   - a red run with no such issue opens one, with the run's link and the jobs
#     that failed;
#   - a red run while one is open comments on it, so a repeat is one more
#     notification in the same thread rather than a new issue each time;
#   - a green full run while one is open comments with its link and closes it;
#   - a green light run leaves it open: the scope decided to test nothing, so
#     its green says nothing about what broke main;
#   - a green run with none open does nothing.
#
# Red means a job named in the arguments ended as `failure` or `cancelled`.
# The job passes `ci-ok`, whose verdict already gathers every job of the
# suite, and `release`, which is where a red main costs a release.
#
# Input, from the environment (set by the job from `github`):
#   GH_TOKEN  the workflow token (read by gh)
#   GH_REPO   owner/name (read by gh)
#   RUN_ID    github.run_id: the failed jobs are read from this run
#   RUN_URL   the run's page, linked from every message
#   EVENT     github.event_name
#   SHA       github.sha
#   FULL      scope's `full` output ('true' when the whole suite ran)
# Arguments: one <job>=<result> per job in the `needs` list of red-main.
# Exit 0 when the issue says what the run found; non-zero when gh failed, so
# a broken alert is a red job rather than silence.
set -eu
set -o pipefail

RM_LABEL="red-main"
# The message body; global because the EXIT trap removes it.
RM_BODY=""

_rm_die() { printf 'red-main: %s\n' "$*" >&2; exit 1; }

# _rm_failed_jobs <job=result>... — the names of the run's jobs that failed,
# one per line. Read from the API, which names every matrix share; when it
# cannot answer, the failed jobs among the arguments stand in.
_rm_failed_jobs() {
  local names="" pair
  if [ -n "${RUN_ID:-}" ]; then
    names=$(gh api "repos/{owner}/{repo}/actions/runs/$RUN_ID/jobs" --paginate \
      --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "cancelled") | .name' \
      2>/dev/null) || names=""
  fi
  if [ -z "$names" ]; then
    for pair in "$@"; do
      case "${pair#*=}" in
        failure | cancelled) names="$names${names:+
}${pair%%=*}" ;;
      esac
    done
  fi
  printf '%s\n' "$names"
}

main() {
  local pair job red=0 open run_url="${RUN_URL:-}" sha="${SHA:-}" event="${EVENT:-}"

  [ $# -gt 0 ] || _rm_die "no job results were reported"
  for pair in "$@"; do
    if [ -z "${pair%%=*}" ] || [ "${pair%%=*}" = "$pair" ]; then
      _rm_die "malformed result '$pair' (want <job>=<result>)"
    fi
    case "${pair#*=}" in failure | cancelled) red=1 ;; esac
  done

  open=$(gh issue list --label "$RM_LABEL" --state open --limit 1 \
    --json number --jq '.[0].number // empty') || _rm_die "cannot list the open $RM_LABEL issues"

  RM_BODY=$(mktemp)
  trap 'rm -f "$RM_BODY"' EXIT

  if [ "$red" -eq 0 ]; then
    if [ -z "$open" ]; then
      echo "red-main: main is green and no issue is open"
      return 0
    fi
    if [ "${FULL:-}" != true ]; then
      echo "red-main: a light run tested nothing; #$open stays open"
      return 0
    fi
    gh issue close "$open" --comment "Green again: $run_url ($event, ${sha:0:12})."
    echo "red-main: main is green again; closed #$open"
    return 0
  fi

  {
    printf 'The ci workflow failed on main (%s, %s).\n\n' "$event" "${sha:0:12}"
    printf 'Run: %s\n\n' "$run_url"
    printf 'Failed jobs:\n'
    while IFS= read -r job; do
      if [ -n "$job" ]; then printf -- '- %s\n' "$job"; fi
    done < <(_rm_failed_jobs "$@")
    printf '\nNothing is released while main is red. This issue closes itself on the next green run of main.\n'
  } > "$RM_BODY"

  if [ -n "$open" ]; then
    gh issue comment "$open" --body-file "$RM_BODY"
    echo "red-main: main is still red; commented on #$open"
    return 0
  fi

  # The label may not exist yet; creating it twice is refused, which is fine.
  gh label create "$RM_LABEL" --color B60205 \
    --description "The ci workflow is failing on main" >/dev/null 2>&1 || true
  gh issue create --title "main is red: the ci workflow failed" \
    --label "$RM_LABEL" --body-file "$RM_BODY"
  echo "red-main: main is red; opened an issue"
}

main "$@"
