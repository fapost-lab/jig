#!/usr/bin/env bash
# Verification for the swift profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (no check could run).
# Prints one line per check: "swift: <check>: pass|fail|skip (<note>)".
#
# Tools come from PATH only (adr-20260918-profiles-narrow-per-check-with-project-tools D2): swift build and swift test are
# both subcommands of the one `swift` binary, so there is no project
# environment to look in. Missing on a machine without an installed
# toolchain (e.g. Windows) is a skip, not a failure (D7).
#
# Narrowing (ADR-0041, adr-20260918-profiles-narrow-per-check-with-project-tools; D4 swift row): swift is never narrowed —
# `swift test --filter` selects by test name, not by changed file, so there
# is no reliable file-to-test mapping for either check. A scoped run still
# runs build and test in full and says `scope: not narrowable, ran full
# set`, with one exception: when every changed path is documentation
# (*.md, docs/**) or the project's map marks it `-` (D5: swift declares no
# filters, only `-` and `ALL`), nothing in the change can affect a build or
# a test, and both checks are skipped instead of run. A map decision other
# than `-` still forces the full run, whatever its own text says — this
# profile has no filter to honour it with.
set -eu
set -o pipefail

# shellcheck source=../../scripts/lib/profile.sh
. "$(dirname "$0")/../../scripts/lib/profile.sh"

jp_begin swift

if ! command -v swift >/dev/null 2>&1; then
  jp_skip "build" "swift not found on PATH"
  jp_skip "test" "swift not found on PATH"
  jp_end
fi

v=$(jp_version swift --version)

# _swift_builtin <path> — ALL for anything but documentation; nothing for a
# path that cannot affect a build or a test.
_swift_builtin() {
  case "$1" in
    *.md | docs/*) return 0 ;;
    *) printf 'ALL\n' ;;
  esac
  return 0
}

SWIFT_NOTE=""
SWIFT_SKIP=0
SWIFT_SKIP_REASON=""
if jp_scoped; then
  sel=$(jp_decide _swift_builtin)
  if [ -z "$sel" ]; then
    SWIFT_SKIP=1
    SWIFT_SKIP_REASON="scope: only documentation changed"
  else
    # Any non-empty decision forces the full run, `ALL` or otherwise: this
    # profile declares no filters (D5), so a map token this profile does
    # not recognise still means "something may be affected", not "nothing
    # is".
    SWIFT_NOTE=", scope: not narrowable, ran full set"
  fi
fi

if [ "$SWIFT_SKIP" = 1 ]; then
  jp_skip "build" "$SWIFT_SKIP_REASON"
  jp_skip "test" "$SWIFT_SKIP_REASON"
else
  jp_run "build" "$v$SWIFT_NOTE" swift build
  jp_run "test" "$v$SWIFT_NOTE" swift test
fi

jp_end
