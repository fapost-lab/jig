# Tests for scripts/jig dispatcher and shared libraries.
# shellcheck shell=bash

test_version_prints_semver() {
  run jig version
  assert_eq 0 "$RC"
  case "$OUT" in jig\ [0-9]*.[0-9]*.[0-9]*) ;; *) fail "bad version output: $OUT" ;; esac
}

test_help_lists_commands() {
  run jig help
  assert_eq 0 "$RC"
  assert_contains "$OUT" "housekeeping"
  assert_contains "$OUT" "knowledge check"
}

test_unknown_command_fails() {
  run jig frobnicate
  assert_eq 1 "$RC"
  assert_contains "$OUT" "unknown command"
}

test_symlinked_dispatcher_resolves_lib() {
  skip_unless_symlinks
  mkdir -p bin
  ln -s "$JIG_BIN" bin/jig
  run bin/jig version
  assert_eq 0 "$RC"
  assert_contains "$OUT" "jig "
}

test_cfg_reads_flat_yaml_subset() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
profiles: [generic, php]   # comment
housekeeping.trash_ttl: 7d
housekeeping.fetch: true
EOF
  # Exercise the library directly through a tiny harness.
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    printf "%s|%s|%s|%s|" "$(cfg housekeeping.trash_ttl)" "$(cfg_list profiles)" "$(cfg missing.key dflt)" "$(cfg profiles)"
    cfg_bool housekeeping.fetch && printf "T"
    if cfg_bool nope; then printf "X"; else printf "F"; fi
  '
  assert_eq 0 "$RC"
  assert_eq "7d|generic php|dflt|[generic, php]|TF" "$OUT"
}

# cfg_list was three `tr` and a `sed`; what it prints for every shape a list
# takes in the file is what that pipeline printed.
test_cfg_list_prints_what_the_pipeline_it_replaced_printed() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
plain: [generic, php]   # comment
tight: [a,b,c]
loose: [  a ,   b  ,c ]
bare: a b
commas: a, b
empty: []
holes: [a,,b, ]
inner: [a[b]c, d]
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    for key in plain tight loose bare commas empty holes inner absent; do
      was=$(cfg "$key" "x, y" | tr -d "[]" | tr "," " " | tr -s " " | sed "s/^ //; s/ \$//")
      now=$(cfg_list "$key" "x, y")
      [ "$was" = "$now" ] || printf "%s: was <%s> now <%s>\n" "$key" "$was" "$now"
      printf "%s=<%s> " "$key" "$now"
    done
  '
  assert_eq 0 "$RC"
  assert_eq "plain=<generic php> tight=<a b c> loose=<a b c> bare=<a b> commas=<a b> empty=<> holes=<a b> inner=<abc d> absent=<x y> " "$OUT"
}

# jig_relpath_from was an awk process per link of a link-mode install; the
# builtin walk answers what that awk answered, the odd paths included.
test_jig_relpath_from_answers_what_the_awk_it_replaced_answered() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"
    was() {
      awk -v from="$1" -v to="$2" "
        BEGIN {
          n1 = split(from, a, \"/\")
          n2 = split(to, b, \"/\")
          i = 1
          while (i <= n1 && i <= n2 && a[i] == b[i]) i++
          up = \"\"
          for (j = i; j <= n1; j++) if (a[j] != \"\") up = up \"../\"
          down = \"\"
          for (j = i; j <= n2; j++) if (b[j] != \"\") down = down b[j] \"/\"
          result = up down
          sub(/\\/\$/, \"\", result)
          if (result == \"\") result = \".\"
          print result
        }"
    }
    n=0
    while IFS="|" read -r from to; do
      n=$((n + 1))
      jig_relpath_from_v now "$from" "$to"
      [ "$(was "$from" "$to")" = "$now" ] || printf "<%s> -> <%s>: was <%s> now <%s>\n" "$from" "$to" "$(was "$from" "$to")" "$now"
      [ "$(jig_relpath_from "$from" "$to")" = "$now" ] || printf "<%s> -> <%s>: the wrapper differs\n" "$from" "$to"
    done <<EOF
/p/.ai|/src/scripts
/p/.claude/skills|/p/skills/jig-task
/p/a|/p/a
/p/a|/p/a/b/c
/p/a/b/c|/p/a
/p/a/|/p/a/b
/p/a|/p/a/
/p//a|/p/a/b
/p/a b/c|/p/a b/d e
/|/a
/a|/
a/b|a/c
a|b
/p/a|
|/p/a
|
EOF
    printf "%s cases " "$n"
    jig_relpath_from_v now /p/.ai/profiles /src/profiles/shell; printf "%s " "$now"
    jig_relpath_v now /p/.ai/scripts /p; printf "%s " "$now"
    jig_relpath_v now /p/.ai/scripts /p/; printf "%s " "$now"
    jig_relpath_v now /q/.ai/scripts /p; printf "%s " "$now"
    printf "%s" "$(jig_relpath /p/x/y /p)"
  '
  assert_eq 0 "$RC"
  assert_eq "16 cases ../../../src/profiles/shell .ai/scripts .ai/scripts /q/.ai/scripts x/y" "$OUT"
}

# jig_has_line is how a script asks "is this a line of that text" without
# piping printf into grep -q (conventions/shell.md, pipefail): whole lines,
# compared as strings, never as patterns.
test_jig_has_line_matches_whole_lines_as_strings() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"
    text=$(printf "alpha\nb*ta\ngamma")
    for probe in alpha "b*ta" gamma alph lpha "b?ta" beta ""; do
      if jig_has_line "$probe" "$text"; then printf "%s=1 " "$probe"; else printf "%s=0 " "$probe"; fi
    done
    jig_has_line x "" || printf "empty=0"
  '
  assert_eq 0 "$RC"
  assert_eq "alpha=1 b*ta=1 gamma=1 alph=0 lpha=0 b?ta=0 beta=0 =0 empty=0" "$OUT"
}

# No script pipes into a reader that can quit before the end of its input: the
# writer dies of SIGPIPE and pipefail turns a match into a failure — about
# once in a hundred runs when bash is writing line by line, and every single
# time once the output outgrows a pipe buffer. conventions/shell.md carries
# the rule and the cures.
#
# What decides is the stage that writes *into* the reader, not the one that
# starts the pipeline. That is where the EPIPE lands: the reader leaves, and
# the next write by the stage feeding it fails. Everything further upstream
# dies only if that stage does. So `printf … | sed … | head -n 1` is not the
# defect — eleven places in scripts/lib/ read a frontmatter key that way, and
# the sed has a couple of short lines left to write, not a buffer's worth, so
# it finishes and the printf behind it finishes with it.
#
# `sed` is therefore deliberately absent from the writer list: shell.md
# blesses `sed -n 's/^key: //p' file | head -n 1` by name. `grep` is on it
# because a grep over a diff is the case the rule cannot bound — nothing at
# the call site says how many lines will match. A `grep -m` reading a *file*
# is not a pipeline and is the cure, not the defect, so only a reader
# preceded by `|` is reported.
#
# The scan joins line continuations before matching, because a pipeline
# written across lines has no single line holding both halves. That is not a
# refinement. `.github/scripts/ci-windows-scope.sh` was written as
# `git diff … \` / `| grep … \` / `| head -n 1`, which dropped the match on
# any diff over a few thousand lines — and when this guard was widened in
# #101 for that very defect, the line-by-line scan walked past it and the
# widening was believed to have caught it. What the widening did pay for is
# `profiles/node/verify.sh`, where two greps over `package.json` piped into
# `head -n 1` on one line: one short line each, never seen to fail, and the
# cure — `grep -m 1` on the file — costs nothing and removes a question a
# reader would otherwise answer from the size of someone else's file.
#
# _pipe_guard_hits <dir>… — one line per pipeline found, `<file>:<line>:
# <joined text>`, the line being where the pipeline starts. No pipe of its
# own: `find … -exec … +` keeps this guard out of its own scan.
_pipe_guard_hits() {
  find "$@" -type f -exec awk '
    function flag(text) {
      if (text ~ /(printf|echo|grep|find|sort|git|awk)[^|#]*\|[[:space:]]*(grep -[a-zA-Z]*[qm]|head([[:space:]]|$))/)
        printf "%s:%d: %s\n", origin, start, text
    }
    # One awk reads every file `find` hands over, so a pipeline still being
    # joined when a file ends is flushed here rather than dropped — and it is
    # reported against the file it started in, which by now is not FILENAME.
    FNR == 1 { flag(buf); buf = "" }
    {
      line = $0
      # A comment runs to the end of its physical line, so a backslash there
      # continues nothing — and a pipeline in a header is an example.
      if (buf == "" && line ~ /^[[:space:]]*#/) next
      if (buf == "") { origin = FILENAME; start = FNR }
      # Only the line terminator is stripped, never trailing blanks: bash
      # continues a line on a backslash that ends it, and a backslash before
      # a space just escapes the space. A Windows checkout leaves the CR on
      # the record where MSYS awk has not already dropped it.
      sub(/\r$/, "", line)
      if (line ~ /\\$/) { sub(/\\$/, " ", line); buf = buf line; next }
      flag(buf line)
      buf = ""
    }
    END { flag(buf) }
  ' {} +

}
test_no_script_pipes_into_an_early_quitting_reader() {
  local hits
  hits=$(_pipe_guard_hits "$JIG_HOME/scripts" "$JIG_HOME/profiles" \
    "$JIG_HOME/adapters" "$JIG_HOME/.github/scripts")
  assert_eq "" "$hits"
}

# The guard above reads files that must stay clean, so it is green whether it
# sees anything or not — which is how a widening shipped in #101 without
# catching what it was written for. This one plants both shapes: the pipeline
# spread over lines it has to report, and the blessed one it must not.
test_pipe_guard_reads_a_pipeline_written_across_lines() {
  mkdir -p sample
  cat > sample/across.sh <<'EOF'
hit=$(git diff -U0 "$base" HEAD -- "$path" 2>/dev/null \
  | grep -E '^[+-]' \
  | grep -oEi "$CONTENT" \
  | head -n 1) || hit=""
EOF
  cat > sample/blessed.sh <<'EOF'
# An example in a comment is not code: printf '%s\n' "$x" | grep -q y
raw=$(printf '%s\n' "$block" \
  | sed -n "s/^${key}:[[:space:]]*//p" \
  | head -n 1)
EOF
  local hits
  hits=$(_pipe_guard_hits sample)
  assert_contains "$hits" "sample/across.sh:1:"
  assert_contains "$hits" "| head -n 1"
  assert_not_contains "$hits" "blessed"
  assert_eq 1 "$(printf '%s' "$hits" | grep -c .)"
}

# One awk call reads every file find hands over, and the directories scanned
# hold more than shell: profile.yaml, jig.cmd, jig-session-hook. A pipeline
# left half-joined at the end of one file must not vanish when the next file
# opens — which is what the guard did until the file after it decided the
# answer, in whatever order the filesystem returned them.
test_pipe_guard_keeps_a_file_whose_last_line_continues() {
  mkdir -p sample
  # The last line ends on a backslash, so the pipeline is still being joined
  # when the file runs out.
  cat > sample/dangling.sh <<'EOF'
hit=$(git diff -U0 "$b" HEAD \
  | grep -oEi "$C" \
  | head -n 1) || hit="" \
EOF
  cat > sample/zz-after.yaml <<'EOF'
name: after
EOF
  local alone both
  alone=$(_pipe_guard_hits sample/dangling.sh)
  both=$(_pipe_guard_hits sample/dangling.sh sample/zz-after.yaml)
  assert_contains "$alone" "sample/dangling.sh:1:"
  assert_eq "$alone" "$both" "a following file swallowed the pipeline"
}

# bash continues a line on a backslash that ends it. A backslash before a
# trailing space escapes the space and ends the command, so the reader below
# belongs to no pipeline and this file is clean. printf writes the fixture
# because the trailing space is the whole point and a heredoc would carry it
# into this file, where it would not survive an editor.
test_pipe_guard_does_not_continue_on_a_backslash_before_a_space() {
  mkdir -p sample
  printf 'echo one \\ \n  | head -n 1\n' > sample/escaped.sh
  local hits
  hits=$(_pipe_guard_hits sample/escaped.sh)
  assert_eq "" "$hits"
}

# No script assigns a locale variable where bash restores it in its own shell:
# `LC_ALL=C cmd` as a statement or a condition, as the prefix of a function
# call, or `local LC_ALL=C`. Homebrew's bash 5.3 on macOS restores the locale
# through libintl into CoreFoundation, which does not survive a fork without
# exec, and dies there with SIGSEGV now and then — in any $(...) or ( … ) that
# jig runs in (conventions/shell.md). A simple command in a pipeline, `$(cmd)`,
# `<(…)` and `env LC_ALL=C cmd` exec the command and restore nothing, so the
# scan drops quoted text, $((…)), <(…) and a $(…) of one command before it
# looks, and what stands after a single `|` or `env` is never in a statement's
# place — unless the command is a shell function, which restores anywhere.
#
# _locale_guard_hits <dir|file>… — one line per site, `<file>:<line>: <text>`,
# line continuations joined as the pipe guard joins them.
_locale_guard_hits() {
  find "$@" -type f -exec awk '
    function flag(text,   t, prev, body, fn) {
      t = text
      gsub(/\047[^\047]*\047/, "", t)
      gsub(/"[^"]*"/, "", t)
      sub(/[[:space:]]#.*$/, "", t)
      # A command word with an underscore is taken for a shell function (jig
      # names its own so; no external it runs has one): a locale prefix on it is
      # restored on return wherever it stands, a pipeline or $(...) included.
      fn = (t ~ /(LC_[A-Z]+|LANG)=[^[:space:];|&]*[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&]*[[:space:]]+)*[A-Za-z0-9-]*_[A-Za-z0-9_]*([[:space:];|&)]|$)/)
      # A $(...) of one command execs it and goes; one holding a list runs it
      # in a shell of its own, so its body is read as statements.
      do {
        prev = t
        gsub(/\$\(\([^()]*\)\)/, "", t)
        if (match(t, /\$\([^()]*\)/)) {
          body = substr(t, RSTART + 2, RLENGTH - 3)
          t = substr(t, 1, RSTART - 1) (body ~ /;|&&|\|\|/ ? "; " body " ;" : "") substr(t, RSTART + RLENGTH)
        }
        gsub(/<\([^()]*\)/, "", t)
      } while (t != prev)
      if (fn ||
          t ~ /(^|[;!{()&]|\|\||(^|[[:space:]])(if|then|else|elif|do|while|until))[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&]*[[:space:]]+)*(LC_[A-Z]+|LANG)=[^[:space:];|&]*[[:space:]]+[^[:space:];|&#]/ ||
          t ~ /(^|[[:space:];])(local|declare|typeset)[[:space:]]+([^;]*[[:space:]])?(LC_[A-Z]+|LANG)=/)
        printf "%s:%d: %s\n", origin, start, text
    }
    FNR == 1 { flag(buf); buf = "" }
    {
      line = $0
      if (buf == "" && line ~ /^[[:space:]]*#/) next
      if (buf == "") { origin = FILENAME; start = FNR }
      sub(/\r$/, "", line)
      if (line ~ /\\$/) { sub(/\\$/, " ", line); buf = buf line; next }
      flag(buf line)
      buf = ""
    }
    END { flag(buf) }
  ' {} +
}

test_no_script_restores_a_locale_in_its_own_shell() {
  local hits
  hits=$(_locale_guard_hits "$JIG_HOME/scripts" "$JIG_HOME/profiles" \
    "$JIG_HOME/adapters" "$JIG_HOME/.github/scripts")
  assert_eq "" "$hits"
}

# The guard above reads files that must stay clean, so it is green whether it
# sees anything or not. This one plants every form it must report — the
# housekeeping trim as it was, prefixes and $((…)) included — and the forms it
# must let through.
test_locale_guard_tells_the_forms_apart() {
  mkdir -p sample
  cat > sample/bad.sh <<'EOF'
  LC_ALL=C sort -u "$f"
if LC_ALL=C grep -q "^$mark" "$err"; then :; fi
  if JIG_HK_FIRST=$((runs + pre - $(_keep) + 1)) JIG_HK_OUT=$(_out) \
    JIG_HK_PRE="$pre" LC_ALL=C awk '
    { print }' "$log" > "$tmp"; then :; fi
  local LC_ALL=C
  local s="$1" LC_CTYPE=C n=0
[ -s "$f" ] || LC_ALL=C tr -d a < "$f"
  LC_ALL=C jig knowledge sources --json > out
case $x in a) LC_ALL=C sort -o "$f" "$f" ;; esac
wait_for & LC_ALL=C sort -o "$f" "$f"
n=$(LC_ALL=C sort -u "$f"; printf x)
n=$(LC_ALL=C _my_func "$f")
printf '%s' "$x" | LC_ALL=C jig_cut 80
EOF
  cat > sample/good.sh <<'EOF'
# LC_ALL=C grep -q x "$f" in a comment
printf '%s\n' "$x" | LC_ALL=C sort -u
n=$(LC_ALL=C grep -c x "$f")
done < <(find . -type f | LC_ALL=C sort)
path=$(LC_ALL=C comm -3 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed -n 1p)
env LC_ALL=C sort -o "$f" "$f"
  JIG_HK_PRE="$pre" env LC_ALL=C awk '{ print }' "$log"
( LC_ALL=C; out_init )
_cut() (
  LC_ALL=C
  printf '%s' "${#1}"
)
  } 2>/dev/null | sed '/^$/d' \
    | LC_ALL=C sort -u
EOF
  local hits
  hits=$(_locale_guard_hits sample)
  assert_not_contains "$hits" "good.sh"
  assert_eq 12 "$(printf '%s\n' "$hits" | grep -c 'sample/bad.sh:')"
  for line in 1 2 3 6 7 8 9 10 11 12 13 14; do
    assert_contains "$hits" "sample/bad.sh:$line:"
  done
}

# --- .ai/config.local.yaml (ADR-0038) ----------------------------------------

test_cfg_local_value_wins_for_a_whitelisted_key() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
housekeeping.cadence: 1d
housekeeping.fetch: true
EOF
  cat > .ai/config.local.yaml <<'EOF'
housekeeping.cadence: 9d
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    printf "%s|%s|%s" "$(cfg housekeeping.cadence)" "$(cfg housekeeping.fetch)" "$(cfg housekeeping.trash_ttl dflt)"
  '
  assert_eq 0 "$RC"
  # cadence: local overrides project. fetch: absent locally, project answers.
  # trash_ttl: absent from both, the default is used.
  assert_eq "9d|true|dflt" "$OUT"
}

test_cfg_ignores_a_non_whitelisted_key_in_the_local_file() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
git.base_branch: main
EOF
  cat > .ai/config.local.yaml <<'EOF'
git.base_branch: other
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg git.base_branch
  '
  assert_eq 0 "$RC"
  assert_eq "main" "$OUT"
}

test_cfg_empty_local_value_falls_through_to_project() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
housekeeping.cadence: 3d
EOF
  cat > .ai/config.local.yaml <<'EOF'
housekeeping.cadence:
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg housekeeping.cadence
  '
  assert_eq 0 "$RC"
  assert_eq "3d" "$OUT"
}

test_cfg_in_a_worktree_reads_the_main_checkouts_local_file() {
  mkdir repo
  cd repo || fail "setup"
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
housekeeping.cadence: 1d
EOF
  cat > .ai/config.local.yaml <<'EOF'
housekeeping.cadence: 9d
EOF
  local main_root
  main_root=$(pwd -P)

  git worktree add -q ../wt -b wtbranch >/dev/null

  # A local file placed inside the worktree itself must not be read: one
  # local file serves every worktree of a clone (ADR-0038).
  mkdir -p ../wt/.ai
  cat > ../wt/.ai/config.local.yaml <<'EOF'
housekeeping.cadence: 5d
EOF

  # A plain checkout's clone root is itself.
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_config_clone_root
  '
  assert_eq 0 "$RC"
  assert_eq "$main_root" "$OUT"

  run bash -c '
    cd ../wt || exit 1
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    printf "%s|%s" "$(cfg housekeeping.cadence)" "$(jig_config_clone_root)"
  '
  assert_eq 0 "$RC"
  assert_eq "9d|$main_root" "$OUT"
}

# --- JIG_CFG_LOCAL_ONLY_KEYS: agent.git (design.md, .ai/specs/autopilot/) ----
# A value committed to .ai/config.yaml would hand every contributor's agent
# the same git rights, so `cfg` must never read `agent.git` from the project
# layer — only from .ai/config.local.yaml, or the `none` default.

test_cfg_agent_git_in_project_config_is_never_read() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
agent.git: pr
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg agent.git none
  '
  assert_eq 0 "$RC"
  assert_eq "none" "$OUT"
}

test_cfg_agent_git_local_value_is_read() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
agent.git: pr
EOF
  cat > .ai/config.local.yaml <<'EOF'
agent.git: commit
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    cfg agent.git none
  '
  assert_eq 0 "$RC"
  assert_eq "commit" "$OUT"
}

test_jig_agent_git_default_is_none() {
  fixture_repo
  mkdir -p .ai
  : > .ai/config.yaml
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_agent_git
  '
  assert_eq 0 "$RC"
  assert_eq "none" "$OUT"
}

test_jig_agent_git_rejects_an_unknown_value_but_still_prints_it() {
  fixture_repo
  mkdir -p .ai
  : > .ai/config.yaml
  cat > .ai/config.local.yaml <<'EOF'
agent.git: yolo
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_agent_git
  '
  assert_eq 1 "$RC"
  assert_eq "yolo" "$OUT"
}

test_jig_config_project_ignored_reports_agent_git_set_in_project_config() {
  fixture_repo
  mkdir -p .ai
  cat > .ai/config.yaml <<'EOF'
agent.git: pr
EOF
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"
    jig_require_repo
    jig_config_project_ignored
  '
  assert_eq 0 "$RC"
  assert_eq "$(printf 'agent.git\tpr')" "$OUT"
}

test_duration_seconds() {
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; printf "%s %s %s %s" "$(jig_duration_seconds 1d)" "$(jig_duration_seconds 2h)" "$(jig_duration_seconds 30m)" "$(jig_duration_seconds 45)"'
  assert_eq "86400 7200 1800 3888000" "$OUT"
}

test_hash_matches_git_hash_object() {
  fixture_repo
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; jig_hash README.md'
  assert_eq "$(git hash-object README.md)" "$OUT"
}

# --- release versions (framework-self-update, AC-12) --------------------------
# Release tags are the update channel, so "which tag is newest" decides what a
# user gets. Ordering is numeric per field, in shell arithmetic, because
# `sort -V` is not everywhere jig runs.

# lib_run <shell code> — run code with common.sh sourced, the way these tests
# exercise shared helpers without the dispatcher.
lib_run() {
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; '"$1"
}

test_release_version_accepts_only_three_numeric_fields() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'for t in v0.1.0 v10.20.30 v01.2.3 0.1.0 v1.0.0-rc1 v1.0 v1.0.0.0 v1..0 va.b.c ""; do
      if v=$(jig_release_version "$t"); then printf "%s=%s " "$t" "$v"; else printf "%s=no " "$t"; fi
    done'
  assert_eq 0 "$RC"
  assert_eq "v0.1.0=0.1.0 v10.20.30=10.20.30 v01.2.3=01.2.3 0.1.0=no v1.0.0-rc1=no v1.0=no v1.0.0.0=no v1..0=no va.b.c=no =no " "$OUT"
}

test_version_newer_compares_fields_as_numbers() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'check() { if jig_version_newer "$1" "$2"; then printf "%s>%s " "$1" "$2"; else printf "%s!>%s " "$1" "$2"; fi; }
    check 0.10.0 0.9.0; check 1.0.0 0.99.99; check 0.1.1 0.1.0; check 0.1.0 0.1.0
    check 0.9.0 0.10.0; check 08.0.0 7.0.0; check 1.0.0-rc1 0.1.0; check 0.1.0 junk'
  assert_eq 0 "$RC"
  assert_eq "0.10.0>0.9.0 1.0.0>0.99.99 0.1.1>0.1.0 0.1.0!>0.1.0 0.9.0!>0.10.0 08.0.0>7.0.0 1.0.0-rc1!>0.1.0 0.1.0!>junk " "$OUT"
}

# A build suffix (`X.Y.Z+<sha>`, unreleased code) orders by its X.Y.Z alone.
test_version_newer_ignores_the_build_suffix_of_unreleased_versions() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'check() { if jig_version_newer "$1" "$2"; then printf "%s>%s " "$1" "$2"; else printf "%s!>%s " "$1" "$2"; fi; }
    check 0.41.0+abc1234 0.40.0; check 0.40.0+abc 0.40.0; check 0.40.0 0.40.0+abc
    check 0.40.0+abc 0.41.0; check 0.40.0+abc 0.40.0+def'
  assert_eq 0 "$RC"
  assert_eq "0.41.0+abc1234>0.40.0 0.40.0+abc!>0.40.0 0.40.0!>0.40.0+abc 0.40.0+abc!>0.41.0 0.40.0+abc!>0.40.0+def " "$OUT"
}

test_newest_release_reads_tags_and_ls_remote_lines() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'printf "%s\n" \
      "4e41650e	refs/tags/v0.9.0" "0b9ed917	refs/tags/v0.9.0^{}" \
      "v0.10.0" "v1.0.0-rc1" "not-a-release" "refs/tags/v0.2.0" | jig_newest_release'
  assert_eq 0 "$RC"
  assert_eq "v0.10.0" "$OUT"
}

test_newest_release_fails_without_a_release_tag() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'printf "%s\n" v1.0.0-rc1 latest | jig_newest_release; printf "rc=%s" "$?"'
  assert_eq "rc=1" "$OUT"
}

test_declared_version_reads_exactly_one_quoted_declaration() {
  mkdir -p one/scripts/lib two/scripts/lib bare/scripts/lib none
  printf '# comment\nJIG_VERSION="1.2.3"\nexport JIG_VERSION\n' > one/scripts/lib/version.sh
  printf 'JIG_VERSION="1.2.3"\nJIG_VERSION="2.0.0"\n' > two/scripts/lib/version.sh
  printf 'JIG_VERSION=1.2.3\n' > bare/scripts/lib/version.sh
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'for d in one two bare none; do
      if v=$(jig_declared_version "$d"); then printf "%s=%s " "$d" "$v"; else printf "%s=no " "$d"; fi
    done'
  assert_eq 0 "$RC"
  assert_eq "one=1.2.3 two=no bare=no none=no " "$OUT"
}

# --- released and unreleased sources
# (adr-20261106-copy-mode-projects-take-released-code-only) ------------------
# A framework checkout is a release only when it is the top of its own git
# repository and HEAD carries the tag of the version it declares.

# _src_fixture <dir> [version] — a minimal framework checkout (all the
# release test reads is scripts/lib/version.sh), released: one commit, tagged
# v<version>.
_src_fixture() {
  local dir="$1" version="${2:-1.2.3}"
  mkdir -p "$dir/scripts/lib"
  printf 'JIG_VERSION="%s"\n' "$version" > "$dir/scripts/lib/version.sh"
  fixture_release_source "$dir" || fail "could not release the fixture source $dir"
}

# _src_commit <dir> — one more commit in <dir>, past whatever tag it carries.
_src_commit() {
  printf '%s\n' "$RANDOM" >> "$1/change.txt"
  git -C "$1" add -A
  git -C "$1" commit -q -m "past the tag"
}

# _src_state <dir> — "<release yes|no> <version>" as the helpers answer for <dir>.
_src_state() {
  lib_run "if jig_source_release '$1'; then r=yes; else r=no; fi
    printf '%s %s' \$r \"\$(jig_source_version '$1')\""
}

test_source_release_true_at_its_tag() {
  _src_fixture src
  _src_state src
  assert_eq 0 "$RC"
  assert_eq "yes 1.2.3" "$OUT"
}

test_source_release_true_on_a_branch_whose_head_carries_the_tag() {
  _src_fixture src
  git -C src checkout -q -b somewhere-else
  _src_state src
  assert_eq "yes 1.2.3" "$OUT" "a branch at the release commit holds the release's bytes"
}

test_source_release_false_on_a_branch_past_the_tag() {
  _src_fixture src
  _src_commit src
  local sha
  sha=$(git -C src rev-parse --short=7 HEAD)
  _src_state src
  assert_eq "no 1.2.3+$sha" "$OUT"
}

test_source_release_false_detached_past_the_tag() {
  _src_fixture src
  _src_commit src
  git -C src checkout -q --detach
  local sha
  sha=$(git -C src rev-parse --short=7 HEAD)
  _src_state src
  assert_eq "no 1.2.3+$sha" "$OUT"
}

test_source_release_true_detached_at_the_tag() {
  _src_fixture src
  _src_commit src
  git -C src checkout -q --detach v1.2.3
  _src_state src
  assert_eq "yes 1.2.3" "$OUT"
}

test_source_release_false_when_the_version_is_raised_but_not_tagged() {
  _src_fixture src
  printf 'JIG_VERSION="1.2.4"\n' > src/scripts/lib/version.sh
  git -C src commit -q -am "raise the version"
  local sha
  sha=$(git -C src rev-parse --short=7 HEAD)
  _src_state src
  assert_eq "no 1.2.4+$sha" "$OUT" "the tag at HEAD is for another version"
}

test_source_release_false_without_git() {
  mkdir -p src/scripts/lib
  printf 'JIG_VERSION="1.2.3"\n' > src/scripts/lib/version.sh
  _src_state src
  assert_eq 0 "$RC"
  assert_eq "no 1.2.3+unknown" "$OUT"
}

# A copy of the framework placed inside somebody else's repository must not
# answer with that repository's tags.
test_source_release_false_in_a_subdirectory_of_another_repository() {
  _src_fixture outer
  mkdir -p outer/vendor/jig/scripts/lib
  printf 'JIG_VERSION="1.2.3"\n' > outer/vendor/jig/scripts/lib/version.sh
  git -C outer add -A
  git -C outer commit -q --amend --no-edit
  git -C outer tag -f -a v1.2.3 -m v1.2.3 >/dev/null
  _src_state outer/vendor/jig
  assert_eq "no 1.2.3+unknown" "$OUT"
}

test_source_version_fails_without_a_declared_version() {
  mkdir -p none
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'if jig_source_version none; then printf yes; else printf no; fi'
  assert_eq "no" "$OUT"
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'if jig_source_release none; then printf yes; else printf no; fi'
  assert_eq "no" "$OUT"
}

test_version_core_drops_the_build_part() {
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'for v in 1.2.3 1.2.3+abc1234 1.2.3+unknown 0.40.0+0123456 ""; do
      printf "[%s] " "$(jig_version_core "$v")"
    done'
  assert_eq 0 "$RC"
  assert_eq "[1.2.3] [1.2.3] [1.2.3] [0.40.0] [] " "$OUT"
}

test_source_where_names_branch_detached_and_no_git() {
  _src_fixture src
  mkdir -p bare/scripts/lib
  printf 'JIG_VERSION="1.2.3"\n' > bare/scripts/lib/version.sh
  local sha branch
  sha=$(git -C src rev-parse --short=7 HEAD)
  branch=$(git -C src symbolic-ref --short HEAD)
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  lib_run 'jig_source_where src; jig_source_where bare; git -C src checkout -q --detach; jig_source_where src'
  assert_eq "on branch $branch at $sha
not a git checkout
detached at $sha" "$OUT"
}

test_dispatcher_version_names_unreleased_code_from_a_checkout() {
  # The whole framework, released: JIG_HOME is a copy of this one at its tag.
  mkdir src
  cp -R "$JIG_HOME"/. src/
  local declared sha
  declared=$(sed -n 's/^JIG_VERSION="\([^"]*\)".*/\1/p' src/scripts/lib/version.sh)
  run "$PWD/src/scripts/jig" --version
  assert_eq 0 "$RC"
  assert_eq "jig $declared" "$OUT" "at its tag the plain number"
  _src_commit src
  sha=$(git -C src rev-parse --short=7 HEAD)
  run "$PWD/src/scripts/jig" --version
  assert_eq "jig $declared+$sha" "$OUT"
  run "$PWD/src/scripts/jig" version
  assert_eq "jig $declared+$sha" "$OUT"
}

# Link mode: a project's .ai/scripts is a link to the checkout's scripts/, and
# the version run through it names the checkout's code too.
test_dispatcher_version_through_a_link_names_the_checkout() {
  skip_unless_symlinks
  mkdir src
  cp -R "$JIG_HOME"/. src/
  local declared sha
  declared=$(sed -n 's/^JIG_VERSION="\([^"]*\)".*/\1/p' src/scripts/lib/version.sh)
  _src_commit src
  sha=$(git -C src rev-parse --short=7 HEAD)
  mkdir -p project/.ai
  ln -s "$PWD/src/scripts" project/.ai/scripts
  run "$PWD/project/.ai/scripts/jig" --version
  assert_eq 0 "$RC"
  assert_eq "jig $declared+$sha" "$OUT"
}

test_help_lists_self_update() {
  run jig help
  assert_contains "$OUT" "self-update"
}

test_help_lists_spec_list() {
  run jig help
  assert_contains "$OUT" "spec list"
}

test_help_lists_spec_new() {
  run jig help
  assert_contains "$OUT" "spec new <id>"
}

test_help_lists_spec_done() {
  run jig help
  assert_contains "$OUT" "spec done <task-id>"
}

test_help_lists_spec_remove() {
  run jig help
  assert_contains "$OUT" "spec remove <id>"
}

test_help_lists_spec_close() {
  run jig help
  assert_contains "$OUT" "spec close <id>"
}

test_help_lists_spec_epic() {
  run jig help
  assert_contains "$OUT" "spec epic <id>"
}

# --- jig_trash_dest (shared by housekeeping and `jig spec remove`) -----------

test_jig_trash_dest_no_collision() {
  fixture_repo
  local today root
  today=$(date +%Y-%m-%d)
  # JIG_PROJECT is the physical path in bash's own spelling (jig_require_repo):
  # `pwd -P` matches it, where plain $PWD keeps macOS's /tmp -> /private/tmp
  # link and git's --show-toplevel prints C:/... on Windows.
  root=$(pwd -P)
  lib_run 'jig_require_repo; jig_trash_dest foo'
  assert_eq 0 "$RC"
  assert_eq "$root/.ai/runtime/trash/$today/foo" "$OUT"
}

test_jig_trash_dest_appends_suffix_on_collision() {
  fixture_repo
  local today root
  today=$(date +%Y-%m-%d)
  root=$(pwd -P)
  mkdir -p ".ai/runtime/trash/$today"
  touch ".ai/runtime/trash/$today/foo"

  lib_run 'jig_require_repo; jig_trash_dest foo'
  assert_eq 0 "$RC"
  assert_eq "$root/.ai/runtime/trash/$today/foo-2" "$OUT"

  mkdir -p ".ai/runtime/trash/$today/foo-2"
  lib_run 'jig_require_repo; jig_trash_dest foo'
  assert_eq 0 "$RC"
  assert_eq "$root/.ai/runtime/trash/$today/foo-3" "$OUT"
}

test_jig_trash_dest_creates_nothing() {
  fixture_repo
  lib_run 'jig_require_repo; jig_trash_dest bar'
  assert_eq 0 "$RC"
  assert_no_file .ai/runtime/trash
}

# --- jig_task_base / jig_base_ref (ADR-0039) ----------------------------------
# The one answer `task`, `housekeeping`, `context` and `knowledge` must never
# disagree about: the branch a task was cut from and has to land on.

# base_run <shell code> — like lib_run, but with config.sh also sourced:
# jig_task_base reads the configured fallback through `cfg`.
base_run() {
  run bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"; '"$1"
}

test_jig_task_base_reads_the_state_field() {
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\n' > .ai/config.yaml
  mkdir -p .ai/workspace/tasks/T-1
  printf 'task_id: T-1\nbranch: task/T-1\nbase_branch: epic/x\n' > .ai/workspace/tasks/T-1/state

  base_run 'jig_require_repo; jig_task_base T-1'
  assert_eq 0 "$RC"
  assert_eq "epic/x" "$OUT"
}

test_jig_task_base_falls_back_to_configured_base_without_the_field() {
  # A workspace started before base_branch existed carries no such line, and
  # a project can also configure a base other than main.
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\ngit.base_branch: develop\n' > .ai/config.yaml
  mkdir -p .ai/workspace/tasks/T-1
  printf 'task_id: T-1\nbranch: task/T-1\n' > .ai/workspace/tasks/T-1/state

  base_run 'jig_require_repo; jig_task_base T-1'
  assert_eq 0 "$RC"
  assert_eq "develop" "$OUT"
}

test_jig_task_base_falls_back_when_the_state_file_is_missing() {
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\n' > .ai/config.yaml

  base_run 'jig_require_repo; jig_task_base no-such-task'
  assert_eq 0 "$RC"
  assert_eq "main" "$OUT"
}

test_jig_task_base_invalid_id_uses_the_configured_base() {
  # An id jig_valid_id rejects (empty, leading dash, leading dot) must never
  # be built into a path under .ai/workspace/tasks/ — only the fallback.
  fixture_repo
  mkdir -p .ai
  printf 'profiles: [generic]\n' > .ai/config.yaml

  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  base_run 'jig_require_repo; for id in "" "-x" "../etc"; do printf "%s=%s " "$id" "$(jig_task_base "$id")"; done'
  assert_eq 0 "$RC"
  assert_eq "=main -x=main ../etc=main " "$OUT"
}

test_jig_base_ref_prefers_the_remote_tracking_ref() {
  # Landed means landed on the remote (a local base can be behind or ahead of
  # it). Faked without a real remote: jig_base_ref only asks whether the ref
  # resolves to a commit.
  fixture_repo
  git branch feature
  git update-ref refs/remotes/origin/feature "$(git rev-parse HEAD)"

  base_run 'jig_require_repo; jig_base_ref feature'
  assert_eq 0 "$RC"
  assert_eq "refs/remotes/origin/feature" "$OUT"
}

test_jig_base_ref_falls_back_to_the_local_branch() {
  fixture_repo
  git branch feature

  base_run 'jig_require_repo; jig_base_ref feature'
  assert_eq 0 "$RC"
  assert_eq "refs/heads/feature" "$OUT"
}

test_jig_base_ref_prints_nothing_when_neither_resolves() {
  fixture_repo

  base_run 'jig_require_repo; jig_base_ref does-not-exist; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

test_jig_base_ref_empty_name_prints_nothing() {
  fixture_repo

  base_run 'jig_require_repo; jig_base_ref; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

# --- jig_spec_epic (ADR-0040) --------------------------------------------------
# Parses the roadmap's Epic: line; moved to common.sh so both spec.sh and
# task.sh can read it without one command library sourcing another.

test_jig_spec_epic_open_line() {
  printf 'Destination: x\n\nEpic: epic/alpha\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha open" "$OUT"
}

test_jig_spec_epic_finished_line() {
  printf 'Destination: x\n\nEpic: epic/alpha — finished\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha finished" "$OUT"
}

test_jig_spec_epic_dash_variants_before_finished() {
  local sep
  for sep in '—' '-' '--'; do
    printf 'Destination: x\n\nEpic: epic/alpha %s finished\n' "$sep" > roadmap.md
    lib_run 'jig_spec_epic roadmap.md'
    assert_eq 0 "$RC" "separator [$sep]"
    assert_eq "epic/alpha finished" "$OUT" "separator [$sep]"
  done
}

test_jig_spec_epic_no_line_prints_nothing() {
  printf 'Destination: x\n\nNothing here.\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

test_jig_spec_epic_two_conflicting_lines_fails() {
  printf 'Destination: x\n\nEpic: epic/alpha\nEpic: epic/beta\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md; printf "rc=%s" "$?"'
  assert_eq "rc=2" "$OUT"
}

test_jig_spec_epic_two_lines_disagreeing_only_on_state_fails() {
  # Same branch, different state — still a guess about which base a task is
  # cut from, so it is refused exactly like a disagreement on the branch.
  printf 'Destination: x\n\nEpic: epic/alpha\nEpic: epic/alpha — finished\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md; printf "rc=%s" "$?"'
  assert_eq "rc=2" "$OUT"
}

test_jig_spec_epic_same_line_repeated_is_fine() {
  printf 'Destination: x\n\nEpic: epic/alpha\nEpic: epic/alpha\n' > roadmap.md
  lib_run 'jig_spec_epic roadmap.md'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha open" "$OUT"
}

test_jig_spec_epic_reads_stdin_as_dash() {
  # spec_epic_declare pipes `git show <ref>:<roadmap>` into it as `-`.
  lib_run 'printf "Destination: x\n\nEpic: epic/alpha\n" | jig_spec_epic -'
  assert_eq 0 "$RC"
  assert_eq "epic/alpha open" "$OUT"
}

# --- jig_fetch_branches (ADR-0040) ---------------------------------------------

test_jig_fetch_branches_without_origin_is_a_noop() {
  fixture_repo
  base_run 'jig_require_repo; jig_fetch_branches "who" main; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_eq "rc=0" "$OUT"
}

test_jig_fetch_branches_failure_warns_and_is_not_fatal() {
  fixture_repo
  git remote add origin "$PWD/no-such-remote"
  base_run 'jig_require_repo; jig_fetch_branches "spec epic" main; printf "rc=%s" "$?"'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "spec epic: could not fetch main from origin; using the refs this checkout has"
  assert_contains "$OUT" "rc=0"
}

# fetch-never-waits-for-a-prompt: GIT_TERMINAL_PROMPT=0 was already here;
# GIT_SSH_COMMAND (BatchMode=yes) is the part this task added. Asserted on
# the actual invocation (stub_git_env_log_dir), the same way housekeeping's
# and self-update's own fetches are.
test_jig_fetch_branches_never_waits_for_a_prompt() {
  fixture_repo
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"

  local log="$PWD/git-calls.log"
  PATH="$(stub_git_env_log_dir "$log"):$PATH" \
    base_run 'jig_require_repo; jig_fetch_branches "who" main'
  assert_eq 0 "$RC"

  assert_file "$log"
  local fetch_line
  fetch_line=$(grep 'ARGS=.*fetch --quiet origin' "$log") \
    || fail "no logged git fetch --quiet origin call: $(cat "$log")"
  assert_contains "$fetch_line" "TERMINAL_PROMPT=0"
  case "$fetch_line" in
    *"BatchMode=yes"*) ;;
    *) fail "GIT_SSH_COMMAND must carry -o BatchMode=yes: $fetch_line" ;;
  esac
}

test_jig_fetch_branches_one_bad_branch_does_not_stop_the_others() {
  # Each branch is fetched on its own so that one origin does not have does
  # not take the rest down with it.
  fixture_repo
  git clone -q --bare . origin.git
  git remote add origin "$PWD/origin.git"
  git branch real-branch
  git push -q origin real-branch
  # Never fetched generically: refs/remotes/origin/real-branch does not exist
  # here yet, so it can only appear through jig_fetch_branches's own fetch.

  base_run 'jig_require_repo; jig_fetch_branches "who" no-such-branch real-branch'
  assert_eq 0 "$RC"
  assert_contains "$OUT" "who: could not fetch no-such-branch from origin"

  base_run 'jig_require_repo; jig_base_ref real-branch'
  assert_eq "refs/remotes/origin/real-branch" "$OUT"
}

# --- the repository is where you are, not what you were told ------------------
# `git rev-parse --show-toplevel` asks the environment first, and `git -C` does
# not override it. With GIT_DIR and GIT_WORK_TREE naming another repository and
# the working directory untouched, every record jig wrote landed there and none
# here. jig_require_repo clears the git location variables before it asks
# (jig_clear_git_location_env), so the answer comes from where the command runs.

# foreign_repo <dir> — a second repository, the one the environment will lie
# about. Built with its own `git init`, so it is a real target: a run that
# believes the lie succeeds there instead of failing, which is what made the
# original bug quiet.
foreign_repo() {
  mkdir -p "$1"
  (
    cd "$1" || exit 1
    git init -q .
    git symbolic-ref HEAD refs/heads/main
    printf '# foreign\n' > README.md
    git add README.md
    git commit -q -m "foreign"
  )
}

test_jig_require_repo_ignores_a_git_dir_naming_another_repository() {
  fixture_repo
  local root foreign
  root=$(pwd -P)
  foreign="$root/../foreign-$$"
  foreign_repo "$foreign"
  foreign=$(cd -P "$foreign" && pwd -P)

  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  run env GIT_DIR="$foreign/.git" GIT_WORK_TREE="$foreign" \
    bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; jig_require_repo; printf "%s" "$JIG_PROJECT"'
  assert_eq 0 "$RC"
  assert_eq "$root" "$OUT"

  rm -rf "$foreign"
}

# GIT_CEILING_DIRECTORIES does not redirect the search, it stops it: with the
# repository's own parent in the list, discovery from a subdirectory finds
# nothing and the command dies "not inside a git repository". A variable that
# turns a working command into an error belongs in the same list as the ones
# that send it elsewhere.
test_jig_require_repo_ignores_a_ceiling_that_hides_the_repository() {
  fixture_repo
  local root
  root=$(pwd -P)
  mkdir -p sub

  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  run env GIT_CEILING_DIRECTORIES="$root" \
    bash -c 'cd sub; JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; jig_require_repo; printf "%s" "$JIG_PROJECT"'
  assert_eq 0 "$RC"
  assert_eq "$root" "$OUT"
}

# The whole list travels together. Clearing GIT_DIR while GIT_OBJECT_DIRECTORY
# stands would commit into this repository and write the objects into another,
# so the test names a variable from each end: one that chooses the repository,
# one that chooses where its objects go.
test_jig_require_repo_clears_every_git_location_variable() {
  fixture_repo
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  run env GIT_DIR=/nowhere/.git GIT_WORK_TREE=/nowhere GIT_COMMON_DIR=/nowhere/.git \
    GIT_OBJECT_DIRECTORY=/nowhere/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=/nowhere/alt \
    GIT_INDEX_FILE=/nowhere/index GIT_NAMESPACE=other \
    GIT_CEILING_DIRECTORIES=/nowhere GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
    bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; jig_require_repo
      for v in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
               GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_INDEX_FILE GIT_NAMESPACE \
               GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM; do
        eval "printf \"%s=%s \" \"\$v\" \"\${$v-unset}\""
      done'
  assert_eq 0 "$RC"
  assert_eq "GIT_DIR=unset GIT_WORK_TREE=unset GIT_COMMON_DIR=unset GIT_OBJECT_DIRECTORY=unset GIT_ALTERNATE_OBJECT_DIRECTORIES=unset GIT_INDEX_FILE=unset GIT_NAMESPACE=unset GIT_CEILING_DIRECTORIES=unset GIT_DISCOVERY_ACROSS_FILESYSTEM=unset " "$OUT"
}

# Configuration is not location: jig decides which repository it is in, and
# reads that repository as the person configured it. The test suite isolates
# itself with GIT_CONFIG_NOSYSTEM, so clearing these would break the runner.
test_jig_require_repo_leaves_git_config_variables_alone() {
  fixture_repo
  # shellcheck disable=SC2016 # expanded by the inner bash, not here
  run env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/nowhere/gitconfig \
    bash -c 'JIG_LIB="$JIG_HOME/scripts/lib"; . "$JIG_LIB/common.sh"; jig_require_repo
      printf "%s|%s" "${GIT_CONFIG_NOSYSTEM-unset}" "${GIT_CONFIG_GLOBAL-unset}"'
  assert_eq 0 "$RC"
  assert_eq "1|/nowhere/gitconfig" "$OUT"
}
