#!/usr/bin/env bash
# ci-windows-scope.sh — decide whether a pull request needs the Windows shards
# (adr-20260924-windows-runs-on-a-pull-request-that-touches-platform-behaviour).
# Run by the `scope` job of .github/workflows/ci.yml in the root of the
# checkout, with the pull request's base commit. Other events never call it:
# main, the nightly run and a manual dispatch run Windows whatever changed.
#
# Prints one line, `windows` or `skip`, and why:
#
#   - windows: the change touches something whose behaviour differs on
#     Windows, by the rules below;
#   - skip: nothing in the change does. The full Windows suite still runs on
#     main after the merge and every night, so a miss costs a red main, not a
#     released defect — the same exposure this repository had before this
#     script existed.
#
# Why a signal at all: three shards are ~25 minutes on every pull request, and
# most changes here cannot behave differently on Windows. Measured over the 99
# pull requests merged before this one — every merged pull request numbered
# below #101, each diff rebuilt from its merge commit and fed to this script
# and to ci-scope.sh — 77 run the full suite today and 22 match these rules:
# 22% of all of them, 29% of the ones that would otherwise pay. The case this
# exists for, #93, matches.
#
# The rules are the Windows failure classes ADR-0037 found and named, not a
# guess at what might be fragile:
#
#   - line endings, because core.autocrlf=true is what a Windows checkout
#     gets by default (this is what broke #93);
#   - MSYS path translation, because git.exe and bash spell a path
#     differently and MSYS converts some arguments and not others;
#   - directory links, because a symlink falls back to an NTFS junction;
#   - a change that names Windows itself — an author writing `windows`,
#     `Git Bash`, `PowerShell` or ADR-0037 into code is reasoning about this
#     platform, and that reasoning is what nothing was running;
#   - the files that only exist for Windows, and .github/workflows/ — a
#     workflow is what decides which platforms run at all, so a change to one
#     is checked on them. Only the workflows: a script under .github/ that CI
#     executes on ubuntu-latest alone (the release tag, the epic gate, the
#     changelog gate) is ordinary code and is read by the content rules like
#     any other, and a checklist under .github/ is prose.
#
# The content rules read the diff's text, never a byte of it: a literal CR is
# deliberately not matched, because MSYS grep, sed and awk drop CR before the
# regular expression sees it (that is half of what #93's fix had to undo), so
# a script matching one would answer differently depending on where it ran.
# Every rule here is plain ASCII that greps the same on every platform. It
# costs nothing: over those 99 pull requests, matching a literal CR as well
# selected the same 22.
#
# The same discipline applies to how the search is run, and the first version
# of this script broke it: `grep … | head -n 1` under `pipefail` killed grep
# with SIGPIPE once a diff outgrew a pipe buffer, and the match it had already
# found read back as none — with a threshold set by a buffer size that MSYS
# picks differently. conventions/shell.md forbids exactly that, and
# tests/dispatcher.t.sh now scans this directory for it.
#
# It lives under .github/ rather than scripts/ because `jig init` copies
# scripts/ into every project, and this is this repository's CI only.
#
# Usage: .github/scripts/ci-windows-scope.sh <base-commit>
set -eu
set -o pipefail

# Tokens in an added or removed line that mean the change can behave
# differently on Windows. Matched case-insensitively as an extended regular
# expression; `\\r` is the two characters a script writes for a carriage
# return, not a carriage return.
CONTENT='\\r|\\015|crlf|autocrlf|eol=|text=auto|cygpath|MSYS|exec-path|junction|jig_link_|windows|git bash|powershell|ADR-0037|NTFS'

_decide() {
  printf '%s (%s)\n' "$1" "$2"
  exit 0
}

# _is_prose <path> — true for a file whose text is read by people, where the
# tokens above say nothing about behaviour.
#
# A template is checked first and is never prose: its bytes are copied into a
# user's project, so its line endings are behaviour even though it is Markdown
# (templates/AGENTS.md is the file #93 was about). Everything else that is
# Markdown is prose, wherever it sits — knowledge, specs, schemas, skills, the
# docs site, a checklist under .github/ — because a person is its only reader.
_is_prose() {
  case "$1" in
    templates/* | .ai/templates/*) return 1 ;;
    docs/* | .ai/knowledge/* | .ai/specs/* | schemas/* | skills/* | *.mdx) return 0 ;;
    *.md) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  local base="${1:-}" files hunks path hit
  [ $# -le 1 ] || { printf 'usage: ci-windows-scope.sh <base-commit>\n' >&2; exit 2; }

  # Unmeasurable is `windows`, the way an unmeasurable scope is `full`: the
  # script runs more than it must rather than claim a change is safe when it
  # could not look at it.
  case "$base" in
    '') _decide windows "no base commit" ;;
    *[!0]*) ;;
    *) _decide windows "new branch, nothing to compare with" ;;
  esac
  git cat-file -e "$base^{commit}" 2>/dev/null || _decide windows "base $base is not in the history"

  files=$(mktemp "${TMPDIR:-/tmp}/ci-windows-files.XXXXXX")
  hunks=$(mktemp "${TMPDIR:-/tmp}/ci-windows-hunks.XXXXXX")
  trap 'rm -f "$files" "$hunks"' EXIT

  git diff --name-only "$base" HEAD > "$files" 2>/dev/null || _decide windows "cannot diff $base"
  [ -s "$files" ] || _decide windows "no changed files"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      .github/workflows/*) _decide windows "$path decides which platforms CI runs" ;;
      *.ps1 | *jig.cmd | *gitattributes) _decide windows "$path is Windows-specific" ;;
    esac
  done < "$files"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    _is_prose "$path" && continue
    # -U0 so only changed lines are read; the two file headers a diff starts
    # with are dropped, or `+++ b/install.ps1` would match its own path rule
    # a second time and every diff of a file named after a token would match.
    #
    # The changed lines go to a file, and the search reads that file. Nothing
    # here pipes into a reader that can stop before the end of its input:
    # under `pipefail` such a reader kills its writer with SIGPIPE, and 141
    # becomes a failed command substitution that reads as "no match"
    # (conventions/shell.md). `grep -m 1` is safe precisely because its input
    # is a file and no process is writing into it — and it keeps the search
    # from walking a large diff after it already has its answer.
    #
    # Both greps in the pipeline read to the end. The pipeline exits non-zero
    # when nothing matched, which is an answer, not a failure, so it is
    # swallowed; `base` was checked above, so a failing `git diff` here would
    # mean the checkout is gone.
    git diff -U0 "$base" HEAD -- "$path" 2>/dev/null \
      | grep -E '^[+-]' \
      | grep -vE '^(\+\+\+|---)' \
      > "$hunks" || :
    hit=$(grep -m 1 -oEi "$CONTENT" "$hunks") || hit=""
    # -m 1 stops after the first matching *line*, and -o prints every match
    # on it, so the answer can still be several lines. Take the first the way
    # conventions/shell.md says to, with a parameter expansion rather than a
    # pipe into `head`.
    hit=${hit%%$'\n'*}
    [ -z "$hit" ] || _decide windows "$path touches '$hit'"
  done < "$files"

  _decide skip "$(wc -l < "$files" | tr -d ' ') changed files touch nothing Windows decides differently"
}

main "$@"
