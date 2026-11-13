# Tests for `jig gh` and the GitHub account of a clone (scripts/lib/gh.sh,
# jig_gh_resolve in scripts/lib/common.sh;
# adr-20261110-a-clone-names-its-github-account): every gh call about the
# project's repository runs under the token of the account the clone names,
# for that call only, whichever account gh has active.
# shellcheck shell=bash

# _gh_repo [origin-url] — the test directory holds `bin/` (a gh stub and its
# files) and `clone/`, a Jig-installed repository the test is left in. Its
# origin is <origin-url> (default https://github.com/acme/widget.git); nothing
# is ever fetched from it. No token variable is set.
_gh_repo() {
  local top="$PWD"
  mkdir clone
  cd clone || return 1
  fixture_jig_repo
  git remote add origin "${1:-https://github.com/acme/widget.git}"
  _gh_stub "$top/bin"
  PATH="$top/bin:$PATH"
  export PATH
  unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
  _GH_D="$top/bin"
  _GH_HOST=github.com
}

# _gh_stub <dir> — a gh that stands in for GitHub. Every call goes to
# <dir>/calls as `<arguments><TAB>GH_TOKEN=<value><TAB>GH_ENTERPRISE_TOKEN=<value>`:
# the arguments, and the token each call ran under. Then:
#   auth status           prints <dir>/auth and fails, as gh does with a broken account
#   auth token --user U   prints `tok-U` when <dir>/auth holds U and <dir>/notoken.U
#                         is absent (a gh older than 2.40 has no --user at all)
#   api ... repos/o/r     prints <dir>/push.<login> (default `false false false`),
#                         the login being the one the token stands for, the active
#                         one without a token
#   anything else         prints `ran:<arguments>` and exits <dir>/rc (default 0)
_gh_stub() {
  mkdir -p "$1"
  : > "$1/calls"
  cat > "$1/gh" <<STUB
#!/bin/sh
d='$1'
printf '%s\tGH_TOKEN=%s\tGH_ENTERPRISE_TOKEN=%s\n' "\$*" "\${GH_TOKEN:-}" "\${GH_ENTERPRISE_TOKEN:-}" >> "\$d/calls"
tok="\${GH_TOKEN:-\${GH_ENTERPRISE_TOKEN:-}}"
case "\$1" in
  auth)
    case "\$2" in
      status) cat "\$d/auth"; exit 1 ;;
      token)
        shift 2
        user=""
        while [ \$# -gt 0 ]; do
          case "\$1" in --user) user="\$2"; shift 2 ;; *) shift ;; esac
        done
        grep -q "account \$user " "\$d/auth" || exit 1
        [ ! -f "\$d/notoken.\$user" ] || exit 1
        printf 'tok-%s\n' "\$user"
        ;;
      *) exit 1 ;;
    esac
    ;;
  api)
    case "\$tok" in
      tok-*) who=\${tok#tok-} ;;
      *) who=\$(cat "\$d/active") ;;
    esac
    if [ -f "\$d/push.\$who" ]; then cat "\$d/push.\$who"; else echo 'false false false'; fi
    ;;
  *)
    printf 'ran:%s\n' "\$*"
    exit "\$(cat "\$d/rc" 2>/dev/null || echo 0)"
    ;;
esac
STUB
  chmod +x "$1/gh"
}

# _gh_accounts <active> <login>... — gh holds these accounts on $_GH_HOST,
# <active> being the active one.
_gh_accounts() {
  local active="$1" l
  shift
  {
    printf '%s\n' "$_GH_HOST"
    for l in "$@"; do
      printf '  ✓ Logged in to %s account %s (keyring)\n' "$_GH_HOST" "$l"
      if [ "$l" = "$active" ]; then
        printf '  - Active account: true\n'
      else
        printf '  - Active account: false\n'
      fi
    done
  } > "$_GH_D/auth"
  printf '%s\n' "$active" > "$_GH_D/active"
}

# _gh_pushers <login>... — these accounts may push to the origin repository.
_gh_pushers() {
  local l
  for l in "$@"; do printf 'true false false\n' > "$_GH_D/push.$l"; done
}

# _gh_called <prefix> — the lines of the call log that start with <prefix>.
_gh_called() { grep "^$1" "$_GH_D/calls" || true; }

# _gh_count <prefix> — how many calls start with <prefix>.
_gh_count() { _gh_called "$1" | grep -c . || true; }

# _gh_tab — a TAB, for the expected call lines.
_gh_tab() { printf '\t'; }

# _gh_memo — where the detected account is remembered.
_gh_memo() { printf '.ai/runtime/gh-account\n'; }

# --- the account is named -----------------------------------------------------

test_gh_config_account_runs_gh_under_its_token_whatever_is_active() {
  _gh_repo
  _gh_accounts alice alice bob
  run jig config set github.account bob --local
  assert_eq 0 "$RC" "$OUT"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "ran:pr list" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "0" "$(_gh_count 'auth switch')" "jig must never switch the active account"
  assert_eq "0" "$(_gh_count 'api')" "a named account is not checked against the repository"
  assert_no_file "$(_gh_memo)"
}

test_gh_config_account_gh_does_not_hold_is_refused_before_gh_runs() {
  _gh_repo
  _gh_accounts alice alice bob
  jig config set github.account carol --local >/dev/null
  run jig gh pr list
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "github.account"
  assert_contains "$OUT" "carol"
  assert_contains "$OUT" "accounts gh holds: alice bob"
  assert_eq "0" "$(_gh_count 'pr list')" "gh ran the real command under an account nobody named"
  assert_eq "0" "$(_gh_count 'auth switch')"
}

test_gh_config_account_is_never_quietly_replaced_by_the_active_one() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers alice
  # gh gives no token for bob (a gh older than 2.40 has no `auth token --user`).
  : > "$_GH_D/notoken.bob"
  jig config set github.account bob --local >/dev/null
  run jig gh pr list
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "github.account is bob"
  assert_contains "$OUT" "2.40"
  assert_eq "0" "$(_gh_count 'pr list')"
}

# --- the account is found -----------------------------------------------------

test_gh_detects_the_one_account_that_may_push_and_remembers_it() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "$(printf 'https://github.com/acme/widget.git\tbob\tdetected')" "$(cat "$(_gh_memo)")"
  assert_eq "0" "$(_gh_count 'auth switch')"
  # The second run asks neither GitHub about the repository nor gh about its accounts.
  : > "$_GH_D/calls"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "0" "$(_gh_count 'api')" "the remembered account was checked again"
  assert_eq "0" "$(_gh_count 'auth status')" "the remembered account was looked up again"
}

test_gh_several_may_push_and_the_active_one_is_among_them_it_is_the_one() {
  _gh_repo
  _gh_accounts bob alice bob
  _gh_pushers alice bob
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_contains "$(cat "$(_gh_memo)")" "$(printf '\tbob\tdetected')"
}

test_gh_several_may_push_and_the_active_one_is_not_among_them_is_refused() {
  _gh_repo
  _gh_accounts alice alice bob carol
  _gh_pushers bob carol
  run jig gh pr list
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "several gh accounts may push to acme/widget (bob carol)"
  assert_contains "$OUT" "jig config set --local github.account"
  assert_eq "0" "$(_gh_count 'pr list')"
  assert_no_file "$(_gh_memo)"
  # And naming one is the way out.
  jig config set github.account carol --local >/dev/null
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-carol$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
}

test_gh_no_account_may_push_leaves_gh_to_its_own_choice() {
  _gh_repo
  _gh_accounts alice alice bob
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_no_file "$(_gh_memo)"
}

test_gh_one_account_is_used_without_asking_the_repository() {
  _gh_repo
  _gh_accounts alice alice
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-alice$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "$(printf 'https://github.com/acme/widget.git\talice\tonly')" "$(cat "$(_gh_memo)")"
  assert_eq "0" "$(_gh_count 'api')"
}

test_gh_one_account_whose_token_gh_will_not_give_runs_gh_as_it_is() {
  _gh_repo
  _gh_accounts alice alice
  : > "$_GH_D/notoken.alice"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_no_file "$(_gh_memo)"
}

test_gh_no_account_at_all_runs_gh_as_it_is() {
  _gh_repo
  : > "$_GH_D/auth"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
}

test_gh_a_token_in_the_environment_is_what_gh_sees() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  run env GH_TOKEN=from-the-environment "$JIG_BIN" gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=from-the-environment$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "0" "$(_gh_count 'auth')" "gh was asked about accounts although the environment named a token"
  assert_eq "0" "$(_gh_count 'api')"
  assert_no_file "$(_gh_memo)"
  # It wins over github.account too.
  jig config set github.account bob --local >/dev/null
  : > "$_GH_D/calls"
  run env GH_TOKEN=from-the-environment "$JIG_BIN" gh pr list
  assert_eq "pr list$(_gh_tab)GH_TOKEN=from-the-environment$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
}

test_gh_a_github_token_in_the_environment_is_left_to_gh() {
  _gh_repo
  _gh_accounts alice alice bob
  run env GITHUB_TOKEN=also-an-environment-token "$JIG_BIN" gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "0" "$(_gh_count 'auth')"
  assert_eq "0" "$(_gh_count 'api')"
}

test_gh_an_enterprise_token_does_not_stand_in_for_a_github_com_clone() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  # GH_ENTERPRISE_TOKEN is read for an Enterprise Server only; for github.com
  # it names nothing, and the account is found as usual.
  run env GH_ENTERPRISE_TOKEN=enterprise-token "$JIG_BIN" gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(_gh_called 'pr list')" "GH_TOKEN=tok-bob"
}

# --- the memory ---------------------------------------------------------------

test_gh_a_memory_of_another_origin_is_ignored() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  mkdir -p .ai/runtime
  printf 'https://github.com/other/thing.git\talice\tdetected\n' > "$(_gh_memo)"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "2" "$(_gh_count api)" "an account of another origin was believed"
  assert_eq "$(printf 'https://github.com/acme/widget.git\tbob\tdetected')" "$(cat "$(_gh_memo)")"
}

test_gh_a_remembered_account_gh_no_longer_gives_a_token_for_is_found_again() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  mkdir -p .ai/runtime
  printf 'https://github.com/acme/widget.git\talice\tdetected\n' > "$(_gh_memo)"
  : > "$_GH_D/notoken.alice"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_contains "$(cat "$(_gh_memo)")" "$(printf '\tbob\tdetected')"
}

test_gh_a_new_github_account_overrides_a_remembered_one() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  mkdir -p .ai/runtime
  printf 'https://github.com/acme/widget.git\talice\tdetected\n' > "$(_gh_memo)"
  jig config set github.account bob --local >/dev/null
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
}

# --- the origin ---------------------------------------------------------------

test_gh_an_enterprise_server_gets_its_token_in_the_enterprise_variable() {
  _gh_repo https://ghe.example.test/o/r.git
  _GH_HOST=ghe.example.test
  _gh_accounts alice alice bob
  _gh_pushers bob
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=$(_gh_tab)GH_ENTERPRISE_TOKEN=tok-bob" "$(_gh_called 'pr list')"
  assert_contains "$(_gh_called 'api')" "--hostname ghe.example.test repos/o/r"
  assert_contains "$(_gh_called 'auth status')" "--hostname ghe.example.test"
}

test_gh_a_ghe_com_tenant_gets_its_token_in_github_token() {
  _gh_repo https://acme.ghe.com/o/r.git
  _GH_HOST=acme.ghe.com
  _gh_accounts alice alice bob
  _gh_pushers bob
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
}

test_gh_reads_host_and_repository_from_every_form_of_an_origin_url() {
  local url
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  for url in \
    'git@github.com:o/r.git' \
    'git@github.com:o/r' \
    'ssh://git@github.com/o/r.git' \
    'ssh://git@ssh.github.com:443/o/r.git' \
    'https://user@github.com/o/r/' \
    'HTTPS://GitHub.com/o/r.git'; do
    git remote set-url origin "$url"
    : > "$_GH_D/calls"
    run jig gh pr list
    assert_eq 0 "$RC" "$url: $OUT"
    assert_contains "$(_gh_called 'api')" "--hostname github.com repos/o/r " "$url"
    assert_contains "$(_gh_called 'pr list')" "GH_TOKEN=tok-bob" "$url"
    assert_eq "$(printf '%s\tbob\tdetected' "$url")" "$(cat "$(_gh_memo)")" "$url"
  done
}

test_gh_an_origin_that_names_no_repository_runs_gh_as_it_is() {
  local url
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  for url in '/some/local/path.git' 'https://github.com/only-owner' 'https://github.com/a/b/c'; do
    git remote set-url origin "$url"
    : > "$_GH_D/calls"
    run jig gh pr list
    assert_eq 0 "$RC" "$url: $OUT"
    assert_eq "pr list$(_gh_tab)GH_TOKEN=$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')" "$url"
    assert_eq "0" "$(_gh_count 'auth')" "$url"
  done
  git remote remove origin
  : > "$_GH_D/calls"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
}

# --- the token stays where it is ----------------------------------------------

test_gh_a_token_is_never_printed_written_down_or_an_argument() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_not_contains "$OUT" "tok-"
  jig config set github.account bob --local >/dev/null
  run jig gh pr list
  assert_not_contains "$OUT" "tok-"
  run jig status
  assert_not_contains "$OUT" "tok-"
  run jig config show --local
  assert_not_contains "$OUT" "tok-"
  assert_eq "" "$(grep -r 'tok-' .ai/runtime 2>/dev/null || true)" "a token was written down under .ai/runtime"
  assert_eq "" "$(grep -r 'tok-' .ai/config.local.yaml .ai/config.yaml 2>/dev/null || true)"
  # The arguments gh was called with are the ones ps would show.
  assert_eq "0" "$(cut -f1 "$_GH_D/calls" | grep -c 'tok-' || true)" "a token was an argument"
  # Nor does it outlive the call: the next one starts from the same clean environment.
  assert_eq "0" "$(_gh_count 'auth switch')"
}

test_gh_a_refusal_prints_no_token() {
  _gh_repo
  _gh_accounts alice alice bob carol
  _gh_pushers bob carol
  run jig gh pr list
  assert_eq 1 "$RC"
  assert_not_contains "$OUT" "tok-"
}

# --- jig gh is gh --------------------------------------------------------------

test_gh_returns_gh_exit_status_and_passes_stdout_through() {
  local out
  _gh_repo
  _gh_accounts alice alice
  out=$(jig gh pr list 2>/dev/null) || fail "jig gh failed where gh succeeded"
  assert_eq "ran:pr list" "$out"
  printf '3\n' > "$_GH_D/rc"
  run jig gh pr view 7 --json state
  assert_eq 3 "$RC" "$OUT"
  assert_eq "ran:pr view 7 --json state" "$OUT"
}

test_gh_keeps_arguments_with_spaces_and_quotes_whole() {
  _gh_repo
  _gh_accounts alice alice
  run jig gh pr create --title 'a b' --body "it's"
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(_gh_called 'pr create')" "pr create --title a b --body it's"
}

test_gh_is_listed_in_the_help() {
  run jig help
  assert_eq 0 "$RC"
  assert_contains "$OUT" "gh <args>..."
}

# --- jig status ---------------------------------------------------------------

test_gh_status_shows_an_account_jig_found_among_several() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  run jig status
  assert_not_contains "$OUT" "github.account:"
  jig gh pr list >/dev/null 2>&1
  run jig status
  assert_eq 0 "$RC"
  assert_contains "$OUT" "github.account: bob (found:"
  assert_contains "$OUT" "jig config set --local github.account"
  # status reads what was remembered; it asks gh nothing.
  : > "$_GH_D/calls"
  run jig status
  assert_eq "0" "$(_gh_count 'api')"
  assert_eq "0" "$(_gh_count 'auth')"
}

test_gh_status_says_nothing_once_the_account_is_named() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  jig gh pr list >/dev/null 2>&1
  jig config set github.account bob --local >/dev/null
  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "github.account: bob (found:"
}

test_gh_status_says_nothing_of_the_only_account() {
  _gh_repo
  _gh_accounts alice alice
  jig gh pr list >/dev/null 2>&1
  assert_contains "$(cat "$(_gh_memo)")" "$(printf '\tonly')"
  run jig status
  assert_eq 0 "$RC"
  assert_not_contains "$OUT" "github.account:"
}

# --- no bare gh in the scripts ------------------------------------------------

# _gh_bare_calls <scripts-dir> — the lines of the scripts under <scripts-dir>
# that run `gh pr|api|repo|run|release|issue|workflow` without jig_gh, as
# `<file>:<line>:<text>`. A call is a `gh` in command position — at the start
# of a line, or after `$(`, a pipe, `&&`, `||`, `;`, a backtick, `{`, or one of
# then/do/else/if/exec/command/jig_net/! (itself after a blank or one of those,
# so `$(jig_net gh pr view` is a call). A comment and a word in a message
# ("gh pr create failed") are not calls. Exempt: lib/pr.sh, which chooses its
# account per pull request, and the helpers of the GitHub-account section of
# lib/common.sh (jig_gh_accounts, jig_gh_stored_token, _jig_gh_may_push,
# jig_gh itself), which are what jig_gh stands on.
_gh_bare_calls() {
  local f
  for f in $(find "$1" -type f \( -name '*.sh' -o -name jig \) | sort); do
    case "$f" in */lib/pr.sh) continue ;; esac
    awk -v file="$f" '
      /^# --- the GitHub account of this clone/ { skip = 1 }
      /^# jig_forge_kind / { skip = 0 }
      skip && file ~ /lib\/common\.sh$/ { next }
      /^[[:space:]]*#/ { next }
      /(^|[$(|&;`{]|(^|[$(|&;`{[:space:]])(then|do|else|if|exec|command|jig_net|!))[[:space:]]*gh[[:space:]]+(pr|api|repo|run|release|issue|workflow)([[:space:]]|$)/ {
        printf "%s:%d:%s\n", file, NR, $0
      }' "$f"
  done
}

test_gh_the_guard_tells_a_bare_call_from_a_comment_and_a_message() {
  mkdir -p guard/lib
  cat > guard/lib/x.sh <<'EOF'
# gh pr list in a comment is not a call
  # nor is this: gh api repos/o/r
  jig_die "gh pr create failed"
  printf 'gh api failed: %s\n' "$x"
  jig_warn "could not run gh pr view; try gh run list"
  out=$(jig_gh pr list)
  out=$(jig_net jig_gh api repos/o/r)
  ghx pr list
  x=gh_pr
  gh auth status
  jig_net gh auth token
EOF
  assert_eq "" "$(_gh_bare_calls guard)" "the guard flags what is not a call"
  cat > guard/lib/y.sh <<'EOF'
gh pr list
  gh api repos/o/r
  out=$(gh pr view 7)
  out=$(jig_net gh pr view 7)
  x=$(foo | gh issue list)
  foo && gh run list
  foo || gh release view
  foo; gh workflow run x
  if gh repo view; then :; fi
  then gh pr merge
  exec gh pr list
  command gh api x
  x=`gh pr list`
  ! gh pr list
EOF
  assert_eq "14" "$(_gh_bare_calls guard | grep -c . || true)" "the guard misses a bare call: $(_gh_bare_calls guard)"
  # The exemptions: pr.sh whole, and only the GitHub-account section of common.sh.
  rm guard/lib/x.sh guard/lib/y.sh
  printf 'gh pr list\n' > guard/lib/pr.sh
  assert_eq "" "$(_gh_bare_calls guard)"
  printf 'gh pr list\n' > guard/lib/other.sh
  assert_contains "$(_gh_bare_calls guard)" "other.sh:1:"
  cat > guard/lib/common.sh <<'EOF'
before() {
  gh pr list
}
# --- the GitHub account of this clone -----------------------------------------
helper() {
  gh api repos/o/r
}
# jig_forge_kind — which forge
after() {
  gh pr view 7
}
EOF
  rm guard/lib/other.sh
  assert_eq "2" "$(_gh_bare_calls guard | grep -c . || true)"
  assert_contains "$(_gh_bare_calls guard)" "common.sh:2:"
  assert_contains "$(_gh_bare_calls guard)" "common.sh:10:"
  assert_not_contains "$(_gh_bare_calls guard)" "common.sh:6:"
}

test_gh_no_script_calls_gh_about_the_repository_without_jig_gh() {
  local found
  found=$(_gh_bare_calls "$JIG_HOME/scripts")
  assert_eq "" "$found" "a script calls gh about the repository without jig_gh (account of the clone):
$found"
}

# --- under jig_net ---------------------------------------------------------------

# _gh_net <body> — run <body> in a shell that has loaded the libraries and is in
# the clone, TMPDIR pointing at the test-local `tmp/` (so that what jig_net and
# the helpers write down can be looked at).
_gh_net() {
  mkdir -p "$PWD/tmp"
  # shellcheck disable=SC2016 # the script's own variables, expanded when it runs
  printf '#!/usr/bin/env bash\nset -eu\nJIG_LIB="%s/scripts/lib"; . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"\njig_require_repo\n%s\n' \
    "$JIG_HOME" "$1" > "$PWD/net.sh"
  run env TMPDIR="$PWD/tmp" bash "$PWD/net.sh"
}

test_gh_under_a_deadline_a_silent_gh_is_cut_off_and_does_not_outlive_the_cut() {
  local pid i
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  # A gh that answers the account questions and then, for a pull-request call,
  # records its pid, sleeps, and would write a marker if it were still alive.
  mv "$_GH_D/gh" "$_GH_D/gh.real"
  cat > "$_GH_D/gh" <<STUB
#!/bin/sh
case "\$1" in
  pr)
    echo \$\$ > '$PWD/gh.pid'
    sleep 4
    : > '$PWD/marker'
    echo opened
    ;;
  *) exec '$_GH_D/gh.real' "\$@" ;;
esac
STUB
  chmod +x "$_GH_D/gh"
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_JIG_NET_CALL=1
_JIG_NET_DEADLINE=$(($(date +%s) + 600))
jig_gh_resolve
jig_net jig_gh pr create --title x || echo "rc=$?"'
  assert_contains "$OUT" "rc=124"
  assert_contains "$OUT" "gh: no answer within 1s; cut off"
  assert_not_contains "$OUT" "jig_gh:"
  assert_not_contains "$OUT" "opened"
  assert_file gh.pid "the stub gh never ran"
  pid=$(cat gh.pid)
  # The kill reached gh itself, not a wrapper around it.
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    fail "gh (pid $pid) outlived the cut-off"
  fi
  sleep 4
  assert_no_file marker "gh went on after it was cut off and finished its work"
}

test_gh_under_a_deadline_gh_sees_the_token_and_none_lands_in_tmpdir() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_JIG_NET_DEADLINE=$(($(date +%s) + 600))
jig_net jig_gh pr list'
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "ran:pr list"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_not_contains "$OUT" "tok-"
  # The account was named by config this time: the stored token is asked for
  # outside jig_net, and no file under TMPDIR holds it afterwards.
  jig config set github.account bob --local >/dev/null
  : > "$_GH_D/calls"
  # shellcheck disable=SC2016
  _gh_net '_JIG_NET_DEADLINE=$(($(date +%s) + 600))
jig_net jig_gh pr list'
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "" "$(grep -r 'tok-' tmp 2>/dev/null || true)" "a token lies in a file under TMPDIR"
  assert_eq "" "$(find tmp -type f 2>/dev/null)" "jig_net left files under TMPDIR"
}

test_gh_the_stored_token_is_read_outside_jig_net() {
  local f
  _gh_repo
  _gh_accounts alice alice bob
  # A deadline already past: anything that went through jig_net would not start.
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_JIG_NET_DEADLINE=$(($(date +%s) - 1))
jig_gh_stored_token github.com bob'
  assert_eq 0 "$RC" "$OUT"
  assert_eq "tok-bob" "$OUT"
  for f in tmp/*; do [ -e "$f" ] && fail "a file was made under TMPDIR: $f"; done
  return 0
}

# --- one memory per clone -----------------------------------------------------------

test_gh_a_task_worktree_uses_the_account_its_clone_remembered() {
  local top="$PWD"
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "$(printf 'https://github.com/acme/widget.git\tbob\tdetected')" "$(cat .ai/runtime/gh-account)"
  git worktree add -q -b wt-side "$top/wt"
  cd "$top/wt" || return 1
  : > "$_GH_D/calls"
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_eq "pr list$(_gh_tab)GH_TOKEN=tok-bob$(_gh_tab)GH_ENTERPRISE_TOKEN=" "$(_gh_called 'pr list')"
  assert_eq "0" "$(_gh_count 'api')" "the worktree asked GitHub about the repository again"
  assert_eq "0" "$(_gh_count 'auth status')" "the worktree looked up gh's accounts again"
  assert_no_file .ai/runtime/gh-account "the worktree kept a memo of its own"
}

test_gh_a_worktree_that_detects_first_leaves_the_memo_with_its_clone() {
  local top="$PWD"
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  git worktree add -q -b wt-side "$top/wt"
  cd "$top/wt" || return 1
  run jig gh pr list
  assert_eq 0 "$RC" "$OUT"
  assert_no_file .ai/runtime/gh-account "the memo was written inside the worktree"
  assert_eq "$(printf 'https://github.com/acme/widget.git\tbob\tdetected')" "$(cat "$top/clone/.ai/runtime/gh-account")"
}

# --- git over HTTPS as the account of this clone ----------------------------------
# (jig_git_origin, adr-20261111-git-over-https-asks-gh-for-the-clones-account)

# _git_own_helper — the person's own credential helper in the clone: it answers
# every host as alice and logs each action it is asked for to $PWD/own.log.
_git_own_helper() {
  : > "$PWD/own.log"
  git config credential.helper "!f() { cat >/dev/null; echo \"\$1\" >> '$PWD/own.log'; test \"\$1\" = get && printf 'username=alice\npassword=own-alice\n'; return 0; }; f"
}

# _git_fill [host] — what git hands over for https://<host>/acme/widget.git
# (default github.com) when asked through jig_git_origin: `user:password`.
_git_fill() {
  _gh_net "printf 'protocol=https\nhost=${1:-github.com}\npath=acme/widget.git\n\n' | jig_git_origin credential fill | awk -F= '\$1 == \"username\" { u = \$2 } \$1 == \"password\" { p = \$2 } END { print u \":\" p }'"
}

test_git_origin_over_https_hands_git_the_named_account_not_the_helpers_one() {
  _gh_repo
  _gh_accounts alice alice bob
  _git_own_helper
  jig config set github.account bob --local >/dev/null
  _git_fill
  assert_eq 0 "$RC" "$OUT"
  assert_eq "bob:tok-bob" "$OUT"
  assert_eq "" "$(cat own.log)" "the person's own helper was asked"
  assert_eq "0" "$(_gh_count 'auth switch')"
}

# Git Bash on Windows turns a backslash in an argument to git.exe into `/`: a
# helper that wrote `\n` reached git as one line, and the token went into the
# user name and out in git's error. Guarded here, where every platform runs it.
test_git_origin_helper_holds_no_backslash() {
  _gh_repo
  _gh_accounts alice alice bob
  jig config set github.account bob --local >/dev/null
  # shellcheck disable=SC2016 # expanded by the script _gh_net writes
  _gh_net 'jig_git_origin_account test read
_jig_git_cred https://github.com/acme/widget.git
printf "%s\n" "${_JIG_GIT_CRED[@]}"'
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "gh auth token --hostname github.com --user bob"
  case "$OUT" in
    *\\*) fail "the helper holds a backslash: $OUT" ;;
  esac
  return 0
}

test_git_origin_over_https_hands_git_the_detected_account() {
  _gh_repo
  _gh_accounts alice alice bob
  _gh_pushers bob
  _git_own_helper
  _git_fill
  assert_eq 0 "$RC" "$OUT"
  assert_eq "bob:tok-bob" "$OUT"
}

test_git_origin_never_stores_or_erases_in_the_persons_helper() {
  _gh_repo
  _gh_accounts alice alice bob
  _git_own_helper
  jig config set github.account bob --local >/dev/null
  _gh_net "printf 'protocol=https\nhost=github.com\nusername=bob\npassword=tok-bob\n\n' | jig_git_origin credential approve
printf 'protocol=https\nhost=github.com\nusername=bob\npassword=tok-bob\n\n' | jig_git_origin credential reject"
  assert_eq 0 "$RC" "$OUT"
  assert_eq "" "$(cat own.log)" "the person's helper was told to store or erase"
}

test_git_origin_leaves_another_host_to_the_persons_helper() {
  _gh_repo
  _gh_accounts alice alice bob
  _git_own_helper
  jig config set github.account bob --local >/dev/null
  _git_fill gitlab.com
  assert_eq "alice:own-alice" "$OUT"
  assert_eq "get" "$(cat own.log)"
}

test_git_origin_leaves_git_as_it_is_when_no_account_is_named() {
  _gh_repo
  _git_own_helper
  # Several accounts, none may push: gh's own choice, and git's own helper.
  _gh_accounts alice alice bob
  _git_fill
  assert_eq "alice:own-alice" "$OUT"
  # A token in the environment: it is in charge, as it is for gh.
  jig config set github.account bob --local >/dev/null
  run env GH_TOKEN=from-env TMPDIR="$PWD/tmp" bash "$PWD/net.sh"
  assert_eq "alice:own-alice" "$OUT"
}

test_git_origin_over_ssh_asks_gh_nothing() {
  _gh_repo git@github.com:acme/widget.git
  _gh_accounts alice alice bob
  _gh_pushers bob
  _git_own_helper
  _git_fill
  assert_eq "alice:own-alice" "$OUT"
  assert_eq "" "$(cat "$_GH_D/calls")" "gh was asked about an SSH origin"
}

test_git_origin_asks_gh_nothing_for_another_forge_or_forge_none() {
  _gh_repo https://gitlab.com/acme/widget.git
  _gh_accounts alice alice bob
  _git_own_helper
  _git_fill gitlab.com
  assert_eq "alice:own-alice" "$OUT"
  git remote set-url origin https://github.com/acme/widget.git
  # forge is the team's key, in the shared file.
  grep -v '^forge:' .ai/config.yaml > config.tmp
  printf 'forge: none\n' >> config.tmp
  mv config.tmp .ai/config.yaml
  _git_fill
  assert_eq "alice:own-alice" "$OUT"
  assert_eq "" "$(cat "$_GH_D/calls")" "gh was asked although Jig chooses nothing here"
}

test_git_origin_reads_the_push_url_for_a_push() {
  _gh_repo git@github.com:acme/widget.git
  git remote set-url --push origin https://github.com/acme/widget.git
  _gh_accounts alice alice bob
  jig config set github.account bob --local >/dev/null
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_jig_git_cred "$(_jig_git_origin_url push)"; echo "push:${#_JIG_GIT_CRED[@]}"
_jig_git_cred "$(_jig_git_origin_url fetch)"; echo "fetch:${#_JIG_GIT_CRED[@]}"'
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "push:4"
  assert_contains "$OUT" "fetch:0"
}

test_git_origin_puts_nothing_but_a_login_into_the_helper() {
  _gh_repo
  _gh_accounts alice alice 'b;ob'
  jig config set github.account 'b;ob' --local >/dev/null
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_jig_git_cred "$(_jig_git_origin_url fetch)"; echo "n:${#_JIG_GIT_CRED[@]}"'
  assert_contains "$OUT" "n:0"
}

# _git_stub — a git on PATH in front of the real one. Every call logs its
# arguments to $PWD/git.argv and its environment to $PWD/git.env; an
# `ls-remote` stands for the network: it asks the real git, with the same
# global options, to fill credentials for github.com into $PWD/git.fill, and
# sleeps first when $PWD/git.sleep exists (writing its pid to $PWD/git.pid).
_git_stub() {
  local real
  real=$(command -v git)
  cat > "$_GH_D/git" <<STUB
#!/bin/sh
d='$PWD'
printf '%s\n' "\$*" >> "\$d/git.argv"
env >> "\$d/git.env"
n=0
for a in "\$@"; do
  case "\$a" in ls-remote | push | fetch) break ;; esac
  n=\$((n + 1))
done
case " \$* " in
  *" ls-remote "*)
    if [ -f "\$d/git.sleep" ]; then echo \$\$ > "\$d/git.pid"; sleep 4; : > "\$d/git.late"; fi
    # Keep the global options alone: append them, then drop the originals.
    total=\$#
    i=0
    for a in "\$@"; do
      [ "\$i" -lt "\$n" ] || break
      set -- "\$@" "\$a"
      i=\$((i + 1))
    done
    shift "\$total"
    printf 'protocol=https\nhost=github.com\n\n' | '$real' "\$@" credential fill > "\$d/git.fill" 2>/dev/null
    exit 0
    ;;
  # Nothing in a test reaches a real remote.
  *" push "* | *" fetch "*) exit 1 ;;
esac
exec '$real' "\$@"
STUB
  chmod +x "$_GH_D/git"
}

test_git_origin_under_a_deadline_git_gets_the_token_and_it_is_nowhere_else() {
  _gh_repo
  _gh_accounts alice alice bob
  jig config set github.account bob --local >/dev/null
  _git_stub
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_JIG_NET_DEADLINE=$(($(date +%s) + 600))
jig_git_origin_account test read
jig_net jig_git_origin ls-remote --heads origin'
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(cat git.fill)" "username=bob"
  assert_contains "$(cat git.fill)" "password=tok-bob"
  assert_contains "$(cat git.argv)" "credential.https://github.com.helper="
  assert_contains "$(cat git.env)" "GIT_TERMINAL_PROMPT=0"
  assert_contains "$(cat git.env)" "BatchMode=yes"
  assert_eq "" "$(grep 'tok-' git.argv || true)" "the token was an argument of git"
  assert_eq "" "$(grep 'tok-' git.env || true)" "the token was in git's environment"
  assert_eq "" "$(grep -r 'tok-' tmp 2>/dev/null || true)" "a token lies in a file under TMPDIR"
  assert_not_contains "$OUT" "tok-"
}

test_git_origin_under_a_deadline_a_silent_git_is_cut_off_itself() {
  local pid i
  _gh_repo
  _gh_accounts alice alice bob
  jig config set github.account bob --local >/dev/null
  _git_stub
  : > git.sleep
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_JIG_NET_CALL=1
_JIG_NET_DEADLINE=$(($(date +%s) + 600))
jig_net jig_git_origin ls-remote --heads origin || echo "rc=$?"'
  assert_contains "$OUT" "rc=124"
  assert_contains "$OUT" "git: no answer within 1s; cut off"
  assert_file git.pid "the stub git never ran"
  pid=$(cat git.pid)
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    fail "git (pid $pid) outlived the cut-off"
  fi
  sleep 4
  assert_no_file git.late "git went on after it was cut off"
}

test_git_origin_a_push_refuses_with_nothing_pushed_when_no_account_is_named() {
  _gh_repo
  _gh_accounts alice alice bob carol
  _gh_pushers bob carol
  _git_stub
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_JIG_SHIP_SENDS=x
jig_ship_push "task ship" main'
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "task ship: several gh accounts may push"
  assert_contains "$OUT" "Nothing was pushed"
  assert_eq "" "$(grep '^.*push' git.argv 2>/dev/null | grep -v 'get-url' || true)" "git push ran"
}

test_git_origin_a_read_warns_once_and_goes_on_with_gits_own_credentials() {
  _gh_repo
  _gh_accounts alice alice bob carol
  _gh_pushers bob carol
  _git_own_helper
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net 'jig_git_origin_account "task start" read
jig_git_origin_account "task start" read
printf "protocol=https\nhost=github.com\n\n" | jig_git_origin credential fill | grep "^username="'
  assert_eq 0 "$RC" "$OUT"
  assert_eq "1" "$(printf '%s\n' "$OUT" | grep -c "reaching origin with git's own credentials")"
  assert_contains "$OUT" "username=alice"
}

test_git_origin_a_ship_at_push_level_pushes_as_the_named_account() {
  _gh_repo
  _gh_accounts alice alice bob
  jig config set github.account bob --local >/dev/null
  _git_stub
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_JIG_SHIP_SENDS=x
jig_ship_push "task ship" main || true'
  assert_contains "$(grep ' push -u origin main' git.argv)" "credential.https://github.com.helper="
  assert_contains "$(grep ' push -u origin main' git.argv)" "--user bob"
}

# --- no network git about origin without jig_git_origin ----------------------------

# _git_bare_calls <scripts-dir> — the lines that run `git [-C <dir>] fetch|push|
# ls-remote|pull` in command position — at the start of a line or after `$(`,
# a pipe, `&&`, `||`, `;` or `{`, then any of then/do/else/if/exec/command/
# jig_net/!/VAR=value, and git's own -C/-c options; never after a backtick,
# the way a message quotes a command — without
# jig_git_origin, as `<file>:<line>:<text>`. Exempt, as they reach another
# repository than the project's: lib/self-update.sh (Jig's own source),
# lib/pr.sh (its own account per pull request) and jig_ls_remote_tags in
# lib/common.sh (Jig's public release tags).
_git_bare_calls() {
  local f
  for f in $(find "$1" -type f \( -name '*.sh' -o -name jig \) | sort); do
    case "$f" in */lib/pr.sh | */lib/self-update.sh) continue ;; esac
    awk -v file="$f" '
      /^jig_ls_remote_tags\(\)/ { skip = 1 }
      skip && /^}/ { skip = 0; next }
      skip { next }
      /^[[:space:]]*#/ { next }
      # A fetch from "." reads this repository itself, never origin.
      /git[[:space:]]+(-[cC][[:space:]]+[^[:space:]]+[[:space:]]+)*fetch([[:space:]]+-[^[:space:]]+)*[[:space:]]+\.([[:space:]]|$)/ { next }
      /(^|[$(|&;{])[[:space:]]*((then|do|else|if|exec|command|jig_net|!|[A-Z_][A-Z0-9_]*=[^[:space:]]*)[[:space:]]+)*git[[:space:]]+(-[cC][[:space:]]+[^[:space:]]+[[:space:]]+)*(fetch|push|ls-remote|pull)([[:space:]]|$)/ {
        printf "%s:%d:%s\n", file, NR, $0
      }' "$f"
  done
}

test_git_origin_the_guard_tells_a_bare_call_from_a_comment_and_a_message() {
  mkdir -p guard/lib
  cat > guard/lib/x.sh <<'G'
# git push origin main, in a comment
jig_die "git push failed"
printf 'push it with `git push -u origin %s`\n' "$b"
jig_net jig_git_origin fetch --quiet origin
git -C "$JIG_PROJECT" stash push -u
git -C "$JIG_PROJECT" fetch -q --no-tags --no-recurse-submodules . \
G
  assert_eq "" "$(_git_bare_calls guard)" "the guard flags what is not a call"
  cat > guard/lib/y.sh <<'G'
git -C "$JIG_PROJECT" fetch --quiet origin
  out=$(git -C "$JIG_PROJECT" ls-remote --heads origin)
jig_net git -C "$JIG_PROJECT" push -u origin "$b"
if ! git pull --ff-only; then :; fi
GIT_TERMINAL_PROMPT=0 git -C "$d" fetch origin
  then git -c credential.helper= ls-remote origin
G
  assert_eq "6" "$(_git_bare_calls guard | grep -c . || true)" "the guard misses a bare call: $(_git_bare_calls guard)"
}

test_git_origin_no_script_reaches_origin_with_git_without_jig_git_origin() {
  local found
  found=$(_git_bare_calls "$JIG_HOME/scripts")
  assert_eq "" "$found" "a script reaches origin with git without jig_git_origin (account of the clone):
$found"
}

test_git_origin_a_remembered_only_account_keeps_the_push_after_a_second_one() {
  _gh_repo
  _gh_accounts alice alice
  _git_own_helper
  _git_fill
  assert_eq "alice:tok-alice" "$OUT"
  assert_eq "$(printf 'https://github.com/acme/widget.git\talice\tonly')" "$(cat .ai/runtime/gh-account)"
  # bob signs in later and becomes active: the pull request stays alice's, so does the push.
  _gh_accounts bob alice bob
  _git_fill
  assert_eq "alice:tok-alice" "$OUT"
}

test_git_origin_never_hands_a_token_to_plain_http() {
  _gh_repo http://github.com/acme/widget.git
  _gh_accounts alice alice bob
  jig config set github.account bob --local >/dev/null
  # shellcheck disable=SC2016 # the body expands in the shell it runs in
  _gh_net '_jig_git_cred "$(_jig_git_origin_url fetch)"; echo "n:${#_JIG_GIT_CRED[@]}"'
  assert_contains "$OUT" "n:0"
}
