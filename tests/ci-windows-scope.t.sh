# Tests for `.github/scripts/ci-windows-scope.sh` (adr-20260924-windows-runs-on-a-pull-request-that-touches-platform-behaviour).
# shellcheck shell=bash
#
# The script decides `windows` or `skip` from a diff against a base commit,
# so every test builds its own fixture repo under the test's own tmp dir (via
# fixture_repo) and invokes "$JIG_HOME/.github/scripts/ci-windows-scope.sh"
# with that fixture as the working directory (cw_scope) — the same pattern
# tests/ci-scope.t.sh uses for ci-scope.sh. The script reads only git, so the
# fixture needs no jig files at all. Helpers below are prefixed cw_.
#
# Every assertion here is over ASCII text. The script deliberately matches no
# literal carriage return (its header says why), so this file needs none
# either, and the Windows shards read it the same as Linux does. The one test
# that needs a non-ASCII *file name* builds it with printf from octal escapes
# rather than writing the character here, and leaves through
# skip_unless_non_ascii_names where it cannot exist.

# --- fixture builders --------------------------------------------------------

# cw_scope <dir> [args...] — run the script under test against the fixture
# repo in <dir>, exactly the way the `scope` CI job invokes it.
cw_scope() {
  local dir="$1"
  shift
  (cd "$dir" && "$JIG_HOME/.github/scripts/ci-windows-scope.sh" "$@")
}

# cw_new_repo <dir> — a fresh git repo (one commit on main, via fixture_repo).
cw_new_repo() {
  mkdir -p "$1"
  (cd "$1" && fixture_repo)
}

# cw_write <dir> <path> <content> — write <content> (plus a trailing newline)
# to <path> inside <dir>, creating parent directories as needed.
cw_write() {
  local dir="$1" path="$2" content="$3"
  mkdir -p "$(dirname "$dir/$path")"
  printf '%s\n' "$content" > "$dir/$path"
}

# cw_commit <dir> <message> — stage everything, including deletions, and commit.
cw_commit() {
  local dir="$1" msg="$2"
  (cd "$dir" && git add -A && git commit -q -m "$msg")
}

# cw_head <dir> — the commit sha at the head of <dir>.
cw_head() {
  git -C "$1" rev-parse HEAD
}

# --- unmeasurable base: run Windows ------------------------------------------

test_ci_windows_scope_no_base_argument_runs_windows() {
  local repo="$PWD/repo"
  cw_new_repo "$repo"

  run cw_scope "$repo"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (no base commit)"
}

test_ci_windows_scope_base_all_zeros_runs_windows() {
  local repo="$PWD/repo"
  cw_new_repo "$repo"

  run cw_scope "$repo" "0000000000000000000000000000000000000000"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (new branch, nothing to compare with)"
}

test_ci_windows_scope_base_not_in_history_runs_windows() {
  local repo="$PWD/repo"
  cw_new_repo "$repo"

  run cw_scope "$repo" "ffffffffffffffffffffffffffffffffffffffff"
  assert_eq 0 "$RC"
  assert_contains "$OUT" \
    "windows (base ffffffffffffffffffffffffffffffffffffffff is not in the history)"
}

test_ci_windows_scope_no_changed_files_runs_windows() {
  local repo="$PWD/repo" head
  cw_new_repo "$repo"
  head=$(cw_head "$repo")

  run cw_scope "$repo" "$head"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (no changed files)"
}

# --- a change that decides nothing on Windows --------------------------------

test_ci_windows_scope_plain_script_change_is_skipped() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/foo.sh 'printf "%s\n" one'
  cw_write "$repo" tests/foo.t.sh 'assert_eq 1 1'
  cw_commit "$repo" "a change that says nothing about any platform"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip (2 changed files touch nothing Windows decides differently)"
}

# --- the content rules -------------------------------------------------------

test_ci_windows_scope_line_endings_run_windows_and_name_the_path() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/section.sh 'tr -d "\r" < infile'
  cw_commit "$repo" "handle a CRLF checkout"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (scripts/lib/section.sh touches"
}

test_ci_windows_scope_autocrlf_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/init.sh 'git config core.autocrlf false'
  cw_commit "$repo" "pin the checkout's line endings"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'autocrlf'"
}

test_ci_windows_scope_path_translation_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/upgrade.sh 'cygpath -w infile'
  cw_commit "$repo" "spell the path the way native git wants it"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'cygpath'"
}

test_ci_windows_scope_directory_link_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/task.sh 'jig_link_dir src dst'
  cw_commit "$repo" "link the workspace into the worktree"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'jig_link_'"
}

# A change that names the platform is reasoning about it, and that reasoning
# is exactly what nothing was running before this script existed.
test_ci_windows_scope_naming_the_platform_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/doctor.sh '# On Windows this probe costs a process start.'
  cw_commit "$repo" "explain the probe"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'Windows'"
}

# A removal counts: deleting the branch that handled CRLF is as much a change
# to line-ending behaviour as adding it.
test_ci_windows_scope_removed_line_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  cw_write "$repo" scripts/lib/section.sh 'crlf=1'
  cw_commit "$repo" "add the branch"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/section.sh 'true'
  cw_commit "$repo" "drop the branch"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'crlf'"
}

# The two lines a diff opens with name the file, and `+++ b/lib/junction.sh`
# would match the content rules on the strength of its own name. They are
# dropped, so a file named after a token but saying nothing about it is a skip.
test_ci_windows_scope_diff_header_does_not_match_itself() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/junction.sh 'echo hello'
  cw_commit "$repo" "a file whose name carries a token"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip (1 changed files touch nothing Windows decides differently)"
}

# --- the path rules ----------------------------------------------------------

test_ci_windows_scope_ci_change_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" .github/workflows/ci.yml "name: ci"
  cw_commit "$repo" "change CI"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (.github/workflows/ci.yml decides which platforms CI runs)"
}

# Only the workflows decide which platforms run. A script under .github/ that
# CI executes on ubuntu-latest alone — the release tag, the epic gate, the
# changelog gate — is ordinary code, read by the content rules like any other,
# and buys no Windows shards on its own.
test_ci_windows_scope_ubuntu_only_ci_script_is_skipped() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" .github/scripts/changelog-check.sh 'grep -c release docs/changelog.mdx'
  cw_commit "$repo" "change a gate that only ever runs on Linux"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip (1 changed files touch nothing Windows decides differently)"
}

# ... and the same script does reach Windows once its text says so.
test_ci_windows_scope_ci_script_naming_the_platform_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" .github/scripts/ci-scope.sh '# paths are spelled the MSYS way here'
  cw_commit "$repo" "teach the scope script about path spelling"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'MSYS'"
}

test_ci_windows_scope_powershell_file_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" install.ps1 "Write-Output ok"
  cw_commit "$repo" "change the Windows bootstrapper"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (install.ps1 is Windows-specific)"
}

test_ci_windows_scope_gitattributes_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" templates/gitattributes "* text=auto"
  cw_commit "$repo" "ship line-ending rules"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (templates/gitattributes is Windows-specific)"
}

test_ci_windows_scope_jig_cmd_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/jig.cmd "@echo off"
  cw_commit "$repo" "change the PowerShell entry point"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (scripts/jig.cmd is Windows-specific)"
}

# --- prose is read by people, not by a platform ------------------------------

# Documentation explaining CRLF changes no behaviour. ci-scope.sh would call
# such a change `light` anyway, so this only keeps the two scripts agreeing.
test_ci_windows_scope_documentation_about_line_endings_is_skipped() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" docs/install.mdx "A Windows checkout uses CRLF."
  cw_write "$repo" .ai/knowledge/adr/0037-windows.md "core.autocrlf=true"
  cw_write "$repo" README.md "Windows is supported through Git Bash."
  cw_commit "$repo" "write about Windows"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip (3 changed files touch nothing Windows decides differently)"
}

# Markdown is prose wherever it sits — a schema, a skill, a checklist that
# lives under .github/ beside the workflows. A person is its only reader.
test_ci_windows_scope_markdown_anywhere_is_prose() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" .github/WINDOWS_RELEASE_CHECKLIST.md "Install Git for Windows by hand."
  cw_write "$repo" schemas/verify-map.md "A CRLF checkout is out of scope here."
  cw_write "$repo" skills/jig-init/SKILL.md "Mention PowerShell for the Windows reader."
  cw_commit "$repo" "write prose about Windows in three more places"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip (3 changed files touch nothing Windows decides differently)"
}

# Documentation is decided by where a file is, not by its extension: a
# template is a shipped file whose line endings reach a user's project, and
# it happens to be Markdown.
test_ci_windows_scope_template_markdown_is_not_prose() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" templates/AGENTS.md "<!-- jig:begin -->"
  cw_write "$repo" scripts/lib/section.sh 'section_write file # keeps CRLF'
  cw_commit "$repo" "write the marked section back in the file's own endings"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (scripts/lib/section.sh touches 'CRLF')"
}

# --- the search must survive a large diff ------------------------------------

# Under `pipefail`, piping the search into a reader that stops before the end
# of its input (`head -n 1`, `grep -q`) kills the writer with SIGPIPE as soon
# as the output outgrows a pipe buffer; 141 fails the command substitution and
# a match that was already found reads back as "no match". That is the failure
# conventions/shell.md is written about, and this script had it: a diff of
# 20 000 lines, every one of them matching, classified as `skip`.
#
# Every line below matches, so `skip` here can only mean the search broke.
test_ci_windows_scope_large_diff_still_finds_the_match() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  mkdir -p "$repo/scripts/lib"
  awk 'BEGIN { for (i = 0; i < 20000; i++) print "# a windows line" }' \
    > "$repo/scripts/lib/big.sh"
  cw_commit "$repo" "a diff far larger than a pipe buffer"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (scripts/lib/big.sh touches 'windows')"
}

# `grep -m 1` stops after the first matching line, but `-o` prints every match
# found on it, so one comment naming two things at once returns two lines. The
# reason is one line, and the whole output is asserted to prove it: #72 and
# #83 both touch a line reading "Git Bash" and "MSYS" together.
test_ci_windows_scope_two_matches_on_one_line_report_one() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/common.sh '# Git Bash spells this the MSYS way'
  cw_commit "$repo" "name two platform facts in one line"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_eq "windows (scripts/lib/common.sh touches 'Git Bash')" "$OUT"
}

# --- POSIX file semantics the author names ------------------------------------

# The mirror of "a change that names the platform": an author writing `inode`
# is reasoning about file identity, which is what Windows does not give. This
# is what #88 turned on — it replaced `cp` onto a destination with a rename
# because `cp` keeps the inode of the script bash is executing.
test_ci_windows_scope_inode_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/upgrade.sh '# rename, so the destination gets a new inode'
  cw_commit "$repo" "replace installed files by renaming"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'inode'"
}

test_ci_windows_scope_hard_link_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" scripts/lib/knowledge.sh '# a hard link means the source is adopted'
  cw_commit "$repo" "refuse an adopted source"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'hard link'"
}

# The construct, not the comment: the rule must still fire when nobody wrote
# down why `stat` is called twice.
test_ci_windows_scope_stat_dialect_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  # shellcheck disable=SC2016
  cw_write "$repo" scripts/lib/knowledge.sh 'links=$(stat -c %h "$src") || links=$(stat -f %l "$src")'
  cw_commit "$repo" "count the links"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'stat -"
}

# --- a symlink shipped code makes, and one a test plants ----------------------

# In Git Bash `ln -s` copies and still exits 0, so a link an install or a
# worktree creates is silently a second copy on the user's machine.
test_ci_windows_scope_shipped_symlink_runs_windows() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  # shellcheck disable=SC2016
  cw_write "$repo" scripts/lib/task.sh 'ln -s "$owner" "$path/workspace"'
  cw_commit "$repo" "link the workspace into the worktree"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "windows (scripts/lib/task.sh touches 'ln -s')"
}

# The same token in a test buys nothing: a test that needs a real symlink
# leaves through skip_unless_symlinks, so the Windows shards would skip it.
test_ci_windows_scope_symlink_in_a_test_is_skipped() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  cw_write "$repo" tests/knowledge.t.sh 'ln -s ../README.md link.md'
  cw_commit "$repo" "plant a symlink fixture"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip (1 changed files touch nothing Windows decides differently)"
}

# The shipped-only search must take its first match the same way the rule
# above it does. It is a second search, run after the CONTENT one, so it is
# exactly where the truncation can fail to reach: without it a line matching
# twice prints a reason with a newline inside it. assert_eq over the whole
# output is what catches that; assert_contains on the token alone would pass
# on the broken code.
test_ci_windows_scope_two_shipped_matches_on_one_line_report_one() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  # shellcheck disable=SC2016
  cw_write "$repo" scripts/lib/task.sh 'ln -s "$a" "$b"; ln -s "$c" "$d"'
  cw_commit "$repo" "link two directories in one line"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_eq "windows (scripts/lib/task.sh touches 'ln -s')" "$OUT"
}

# --- the atomic-write idiom is deliberately not a signal ----------------------

# conventions/shell.md asks for `file.tmp.$$` then `mv`, and its reason is a
# crash mid-write, not a platform, so the idiom is not a signal. Measured over
# the 105 merged pull requests below #107: a rule on it would raise 9 that the
# other rules do not, and only #88 among them is platform-dependent, which #88
# says in the word `inode`. #88 and #17 are already caught for their own reason
# — hence seven, not eight — so the rule would catch nothing new and spend
# seven false runs of ~15 minutes. The seven that stay uncaught are #10, #20,
# #21, #61, #62, #65 and #66, named as a priced decision in the ADR.
test_ci_windows_scope_atomic_write_idiom_is_skipped() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  # shellcheck disable=SC2016
  cw_write "$repo" scripts/lib/task.sh 'tmp="$file.tmp.$$"; printf x > "$tmp"; mv "$tmp" "$file"'
  cw_commit "$repo" "write the state file atomically"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "skip (1 changed files touch nothing Windows decides differently)"
}

# A shipped file can match both sets. The shipped-only search runs second and
# only when the first found nothing, so the reason names the rule that holds
# everywhere — the precedence the script states beside SHIPPED.
test_ci_windows_scope_content_wins_over_shipped_on_one_file() {
  local repo="$PWD/repo" base
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  # shellcheck disable=SC2016
  cw_write "$repo" scripts/lib/task.sh 'ln -s "$a" "$b"  # junction on Windows'
  cw_commit "$repo" "link a directory, and say what Windows does instead"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_eq "windows (scripts/lib/task.sh touches 'junction')" "$OUT"
}

# --- a path git would otherwise quote -----------------------------------------

# With core.quotePath at its default, `git diff --name-only` prints a path
# holding a byte above 0x7F as "scripts/lib/caf\303\251.sh" — quoted, escaped
# and not a path. Every path rule then misses it and `git diff -- "$string"`
# selects nothing, so the file passed with its content never read: the one
# place this script answered `skip` about something it could not look at.
test_ci_windows_scope_non_ascii_path_is_read() {
  local repo="$PWD/repo" base name
  skip_unless_non_ascii_names
  cw_new_repo "$repo"
  base=$(cw_head "$repo")

  name=$(printf 'scripts/lib/caf\303\251.sh')
  cw_write "$repo" "$name" '# handle crlf here'
  cw_commit "$repo" "a platform-dependent change behind a non-ASCII name"

  run cw_scope "$repo" "$base"
  assert_eq 0 "$RC"
  assert_contains "$OUT" "touches 'crlf'"
}
