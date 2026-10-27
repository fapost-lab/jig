#!/usr/bin/env bash
# ci-reuse.sh — decide whether a push to main may skip the suite because a
# pull request's run already tested the very tree main now has
# (adr-20261027-main-is-not-retested-when-a-pull-request-tested-its-tree).
# Run by the `scope` job of .github/workflows/ci.yml, in the root of a full
# checkout of the pushed commit, on a push to main whose scope is full.
#
# Why: a release cost four runs of the whole suite — the task's pull request,
# its merge into main, the release pull request, its merge — and two of them
# tested a tree that had just been tested.
#
# Prints one line:
#
#   - reuse (<run url> ...): a successful run of `ci` on a pull request tested
#     this tree, the whole suite on every platform. The suite is skipped and
#     the run goes on to `release`;
#   - test (<why>): anything else. The suite runs as it always did.
#
# The pull request is the one GitHub records as having made HEAD: into main,
# with HEAD as its merge commit, so a direct push never reuses. Its runs are
# found by its head commit P: a run does not say which pull request it ran
# for once that pull request merged (`pull_requests` is empty then). So a run
# of the same commit P for a second, open pull request into another branch —
# an epic — would count too, though it tested a merge onto that branch. That
# needs one branch proposed into main and into an epic at the same commit;
# the ADR names it as residual risk.
#
# What a pull request's run tested is GitHub's merge of its head P into the
# tip of main at the time, B: `refs/pull/N/merge`. That ref is gone once the
# pull request merges, and the run's own `head_sha` is P, not the merge. So
# the tree is reached by an argument instead: main only moves forward (the
# branch rule refuses a non-fast-forward push), and the run came before this
# push, so B is <before> or an ancestor of it. When <before> is an ancestor
# of P, so is B, GitHub's merge of the two is P's own tree, and when that tree
# is HEAD's, the run tested what main now holds. A pull request that was not
# up to date with main when it merged fails the ancestry test, and main tests
# everything — which is exactly the case where main's tree is new.
#
# The run counts only when it was full: `knowledge` skipped (the scope was
# full), no other job skipped but those in CR_PR_SKIPS, which never run on a
# pull request into main, and at least one Windows Git Bash share passed —
# a pull request that skipped Windows covers Linux and macOS only, and main
# releases for Windows too. The name prefix below is the second copy of the
# `test-windows` job's name; tests/ci-workflow.t.sh holds the two together,
# and a rename that slipped past it would only make main test everything.
#
# Unmeasurable is never a reason to skip: a missing <before>, a commit that
# cannot be read, a GitHub API that does not answer — each prints `test`.
#
# Environment: GITHUB_REPOSITORY (owner/name; set by Actions) and GH_TOKEN for
# `gh`.
#
# Usage: .github/scripts/ci-reuse.sh <before>
#   <before>  github.event.before: the tip of main before this push.
set -eu
set -o pipefail

CR_WINDOWS_PREFIX="windows-latest (Git Bash) "
# The jobs of ci.yml that a pull request into main always skips: their `if:`
# asks for a push or the nightly run on main, or for an epic's head branch.
# tests/ci-reuse.t.sh holds every job of ci.yml to this list or to the list
# of jobs a full pull-request run runs, so a new job is a decision made here.
CR_PR_SKIPS="release epic-pr red-main"

_cr_line() {
  printf '%s (%s)\n' "$1" "$2"
  exit 0
}

# _cr_have <sha> — make <sha> readable locally, fetching it when the
# checkout does not have it (a squash-merged branch, a deleted one).
_cr_have() {
  git cat-file -e "$1^{commit}" 2>/dev/null && return 0
  git fetch -q --depth=1 origin "$1" 2>/dev/null || return 1
  git cat-file -e "$1^{commit}" 2>/dev/null
}

# _cr_full <run-id> — whether the run tested the whole suite, Windows
# included, judged from its jobs. Status 1 when it did not or the jobs cannot
# be read; the reason goes to stdout.
_cr_full() {
  local jobs line conclusion name knowledge="" windows=0
  jobs=$(gh api -X GET "repos/$CR_SLUG/actions/runs/$1/jobs" -f per_page=100 \
    --jq '.jobs[] | "\(.conclusion) \(.name)"' 2>/dev/null) || {
    echo "its jobs cannot be read"
    return 1
  }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    conclusion=${line%% *}
    name=${line#* }
    if [ "$name" = knowledge ]; then
      knowledge=$conclusion
      continue
    fi
    case " $CR_PR_SKIPS " in *" $name "*) continue ;; esac
    if [ "$conclusion" != success ]; then
      echo "job '$name' ended as '$conclusion'"
      return 1
    fi
    case "$name" in "$CR_WINDOWS_PREFIX"*) windows=$((windows + 1)) ;; esac
  done <<EOF
$jobs
EOF
  if [ "$knowledge" != skipped ]; then
    echo "its scope was light"
    return 1
  fi
  if [ "$windows" -eq 0 ]; then
    echo "it skipped the Windows Git Bash shares"
    return 1
  fi
  return 0
}

main() {
  local before="${1:-}" head tree heads runs id sha url why seen=0
  [ $# -le 1 ] || { printf 'usage: ci-reuse.sh <before>\n' >&2; exit 2; }

  case "$before" in
    '') _cr_line test "no commit before the push" ;;
    *[!0]*) ;;
    *) _cr_line test "new branch, nothing before the push" ;;
  esac
  git cat-file -e "$before^{commit}" 2>/dev/null || _cr_line test "$before is not in the history"
  head=$(git rev-parse HEAD 2>/dev/null) || _cr_line test "cannot read HEAD"
  tree=$(git rev-parse 'HEAD^{tree}' 2>/dev/null) || _cr_line test "cannot read the tree of HEAD"

  CR_SLUG="${GITHUB_REPOSITORY:-}"
  [ -n "$CR_SLUG" ] || _cr_line test "GITHUB_REPOSITORY is not set; cannot ask GitHub"

  # The pull request into main whose merge is HEAD; a direct push has none.
  heads=$(gh api "repos/$CR_SLUG/commits/$head/pulls" \
    --jq ".[] | select(.base.ref == \"main\" and .merge_commit_sha == \"$head\") | .head.sha" \
    2>/dev/null) || _cr_line test "cannot read the pull request that made $head"
  [ -n "$heads" ] || _cr_line test "no pull request into main was merged as $head"

  runs=""
  for sha in $heads; do
    runs="$runs$(gh api -X GET "repos/$CR_SLUG/actions/workflows/ci.yml/runs" \
      -f event=pull_request -f status=success -f head_sha="$sha" \
      --jq '.workflow_runs[] | "\(.id) \(.head_sha) \(.html_url)"' 2>/dev/null)
" || _cr_line test "cannot read the pull-request runs of ci"
  done

  while read -r id sha url; do
    [ -n "${url:-}" ] || continue
    _cr_have "$sha" || continue
    [ "$(git rev-parse "$sha^{tree}" 2>/dev/null)" = "$tree" ] || continue
    seen=1
    if ! git merge-base --is-ancestor "$before" "$sha" 2>/dev/null; then
      echo "skipping $url: its branch did not contain main's tip $before" >&2
      continue
    fi
    if why=$(_cr_full "$id"); then
      _cr_line reuse "$url tested tree $tree on every platform"
    fi
    echo "skipping $url: $why" >&2
  done <<EOF
$runs
EOF

  if [ "$seen" -eq 1 ]; then
    _cr_line test "no full green pull-request run tested tree $tree on top of $before"
  fi
  _cr_line test "no green run of the pull request has tree $tree"
}

main "$@"
