#!/usr/bin/env bash
# main-green-check.sh — refuse a pull request that releases a version while CI
# on main is red. Run by the `changelog` job of .github/workflows/ci.yml, in
# the root of the checkout, after changelog-check.sh.
#
# Why: a version is released by the `release` job on main, and that job runs
# only when every job of main's run passed (ADR-0034). 0.36.0 was declared by
# #319 and never tagged: main was already red on Windows, so the run after the
# merge skipped `release`, and the documentation site, built from main, showed
# a version nobody could install. A pull request that raises JIG_VERSION into
# a red main is a release that will not happen, so it is refused until main is
# fixed.
#
# It turns itself on only when the pull request changes JIG_VERSION against
# its base; every other pull request passes without asking GitHub anything.
# Not, as changelog-check.sh does, whenever the declared version has no tag:
# after a release is declared and main goes red, that is every pull request,
# the one that repairs main included, and the check would lock main red. The
# pull request that changes the version is the one that declares a release.
#
# What counts is the latest *completed* run of the `ci` workflow on main —
# push, nightly or manual alike. A run still in progress is not waited for and
# does not refuse: its answer is unknown, a refusal on it would clear only by
# someone re-running this job by hand, and the code this pull request carries
# is tested by its own run, Windows included (ci-windows-scope.sh runs the
# Windows shards on any change to JIG_VERSION). A light run counts as a run: on
# a push, ci-scope.sh measures from the last successful run, so a light run
# can only follow a green one.
#
# The check answers when the pull request's CI runs, not when it merges: a main
# that turns red after this job passed does not stop the merge. That is the
# residual risk, and the `release` job skipping on main is where it surfaces.
#
# Unmeasurable refuses: when GitHub cannot be asked, the job fails with the
# reason, and a re-run of it answers again.
#
# Environment: GITHUB_REPOSITORY (owner/name; set by Actions) and GH_TOKEN for
# `gh`.
#
# Usage: .github/scripts/main-green-check.sh <base-commit>
set -eu
set -o pipefail

_main_green_die() { printf 'main-green-check: error: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"
# shellcheck source=../../scripts/lib/common.sh
. "$LIB_DIR/common.sh"

# version_at <commit> — the JIG_VERSION scripts/lib/version.sh declares at
# <commit>, read with the same shape jig_declared_version accepts; empty when
# the file or the line is not there.
version_at() {
  local text
  text=$(git show "$1:scripts/lib/version.sh" 2>/dev/null) || return 0
  printf '%s\n' "$text" | sed -n 's/^JIG_VERSION="\([^" ]\{1,\}\)"[[:space:]]*$/\1/p'
}

main() {
  local base="${1:-}" repo version before slug answer conclusion url
  [ $# -eq 1 ] && [ -n "$base" ] \
    || _main_green_die "usage: main-green-check.sh <base-commit>"

  repo=$(git rev-parse --show-toplevel 2>/dev/null) \
    || _main_green_die "not inside a git repository"
  version=$(jig_declared_version "$repo") \
    || _main_green_die "cannot read a single JIG_VERSION=\"...\" line from scripts/lib/version.sh"

  # actions/checkout fetches one commit, so the base is fetched when it is
  # missing. A base that cannot be read refuses: unmeasurable is not a pass.
  git -C "$repo" cat-file -e "$base^{commit}" 2>/dev/null \
    || git -C "$repo" fetch -q --depth=1 origin "$base" 2>/dev/null \
    || _main_green_die "cannot read the base commit $base"
  before=$(cd "$repo" && version_at "$base")

  if [ "$before" = "$version" ]; then
    printf 'main-green-check: JIG_VERSION stays %s, this pull request releases nothing\n' "$version"
    return 0
  fi

  slug="${GITHUB_REPOSITORY:-}"
  [ -n "$slug" ] || _main_green_die "GITHUB_REPOSITORY is not set; cannot ask GitHub about main"

  # One line, `<conclusion> <url>`, or nothing when main has no completed run.
  answer=$(gh api -X GET "repos/$slug/actions/workflows/ci.yml/runs" \
    -f branch=main -f status=completed -f per_page=1 \
    --jq '.workflow_runs[0] // empty | "\(.conclusion) \(.html_url)"' 2>/dev/null) \
    || _main_green_die "cannot read the CI runs of main; re-run this job"

  if [ -z "$answer" ]; then
    printf 'main-green-check: main has no completed ci run yet, nothing to wait for\n'
    return 0
  fi
  conclusion=${answer%% *}
  url=${answer#* }

  [ "$conclusion" = success ] \
    || _main_green_die "main is red ($conclusion): $url; fix it first. This pull request releases $version, and a red main gets no tag."

  printf 'main-green-check: main is green (%s), %s can be released\n' "$url" "$version"
}

main "$@"
