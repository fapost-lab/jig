# Tests for where a project's checks run: scripts/lib/runenv.sh, its wiring
# in `jig verify`, and jp_exec/jp_have in scripts/lib/profile.sh
# (adr-20261001-checks-run-where-the-project-runs; domains/verify).
# shellcheck shell=bash
#
# No test needs docker. A `docker` stub on PATH writes every call to
# docker.log and runs the command after `compose exec <options> <service>` on
# this machine, so a check that went through the prefix is told apart from one
# that ran on the host by the log alone. Every test clears CI: with CI set,
# `run.exec: auto` neither detects nor refuses, which one test asserts.
# Snippets run by `bash -c` expand their variables inside, not here.
# shellcheck disable=SC2016

# _env_docker_stub [up|down|other] — a `docker` on PATH. `up` (default) runs
# the command; `down` fails the way `docker compose exec` does for a service
# that is not running; `other` answers the probe of `.git` with another
# checkout's text.
_env_docker_stub() {
  local mode="${1:-up}"
  mkdir -p stub-bin
  cat > stub-bin/docker <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/docker.log"
if [ "$mode" = down ]; then
  printf 'service "app" is not running\n' >&2
  exit 1
fi
shift 2
while [ \$# -gt 0 ]; do
  case "\$1" in
    -u|-w) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
if [ "$mode" = other ] && [ "\$1" = sh ] && [ "\$3" = 'cat .git 2>/dev/null; exit 0' ]; then
  printf 'gitdir: /elsewhere/.git/worktrees/other\n'
  exit 0
fi
exec "\$@"
STUB
  chmod +x stub-bin/docker
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _env_php_stub — a `php` that answers `--version` and logs `artisan test`.
_env_php_stub() {
  mkdir -p stub-bin
  cat > stub-bin/php <<STUB
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then printf 'PHP 8.4.0\n'; exit 0; fi
if [ "\$1" = artisan ] && [ "\$2" = test ]; then printf 'ran\n' >> "$PWD/artisan.log"; exit 0; fi
exit 127
STUB
  chmod +x stub-bin/php
}

# _env_sail_project — a Laravel project on Sail: the launcher, and the
# compose file Sail writes, its volume quoted.
_env_sail_project() {
  : > artisan
  mkdir -p vendor/bin
  : > vendor/bin/sail
  cat > docker-compose.yml <<'EOF'
services:
    laravel.test:
        build:
            context: ./vendor/laravel/sail/runtimes/8.4
        volumes:
            - '.:/var/www/html'
        depends_on:
            - mysql
    mysql:
        image: 'mysql/mysql-server:8.0'
        volumes:
            - 'sail-mysql:/var/lib/mysql'
volumes:
    sail-mysql:
        driver: local
EOF
  printf 'DB_HOST=mysql\n' > .env
}

# _env_resolve — run runenv_resolve in a plain directory, with `cfg` answering
# run.exec from $RUN_EXEC (default auto), and print what it decided.
_env_resolve() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; JIG_PROJECT="$(pwd)"
    . "$JIG_LIB/common.sh"; . "$JIG_LIB/runenv.sh"
    cfg() { printf "%s\n" "${RUN_EXEC:-$2}"; }
    runenv_resolve
    printf "exec=[%s]\nwhere=[%s]\nup=[%s]\nrefusal=[%s]\n" "$RUNENV_EXEC" "$RUNENV_WHERE" "$RUNENV_UP" "$RUNENV_REFUSAL"
  '
}

# --- detectors -----------------------------------------------------------------

test_runenv_detects_sail_and_runs_as_its_user() {
  unset CI
  _env_sail_project
  _env_docker_stub
  _env_resolve
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "exec=[docker compose exec -T -u sail -w /var/www/html laravel.test"
  assert_contains "$OUT" "(Laravel Sail, detected)"
  assert_contains "$OUT" "up=[./vendor/bin/sail up -d"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_sail_reads_app_service_from_env() {
  unset CI
  _env_sail_project
  sed -i.bak 's/laravel\.test:/web:/' docker-compose.yml
  printf 'APP_SERVICE="web"\n' >> .env
  _env_docker_stub
  _env_resolve
  assert_contains "$OUT" "exec=[docker compose exec -T -u sail -w /var/www/html web"
}

test_runenv_detects_the_one_compose_service_that_mounts_the_project() {
  unset CI
  cat > compose.yaml <<'EOF'
# the app and its database
services:
  db:
    image: postgres
  app:
    image: node:22
    volumes:
      - ./:/app:cached
      - node_modules:/app/node_modules
EOF
  _env_docker_stub
  _env_resolve
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "exec=[docker compose exec -T -w /app app"
  assert_contains "$OUT" "(docker compose service app, detected)"
  assert_contains "$OUT" "up=[docker compose up -d"
}

test_runenv_compose_list_items_may_sit_at_the_key_indent() {
  unset CI
  cat > docker-compose.yaml <<'EOF'
services:
  php:
    volumes:
    - ".:/srv/app"
EOF
  _env_docker_stub
  _env_resolve
  assert_contains "$OUT" "exec=[docker compose exec -T -w /srv/app php"
}

test_runenv_reads_a_compose_file_with_crlf_line_ends() {
  unset CI
  printf 'services:  # the stack\r\n  db:\r\n    image: postgres\r\n\r\n  app:\r\n    volumes:\r\n      - .:/app\r\n' > compose.yaml
  _env_docker_stub
  _env_resolve
  assert_contains "$OUT" "exec=[docker compose exec -T -w /app app]"
}

# _env_unread_mount <volumes-block> — a compose file whose only app service
# mounts the project in a form the reader does not take apart; resolving it
# must refuse, never fall through to the host.
_env_unread_mount() {
  printf 'services:\n  app:\n    image: php\n%s\n' "$1" > compose.yaml
  _env_docker_stub
  _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "app in compose.yaml mounts the project in a form jig does not read"
}

test_runenv_long_syntax_mount_is_a_sign() {
  unset CI
  _env_unread_mount '    volumes:
      - type: bind
        source: .
        target: /app'
}

test_runenv_pwd_mount_is_a_sign() {
  unset CI
  _env_unread_mount '    volumes:
      - "${PWD}:/app"'
}

test_runenv_flow_list_mount_is_a_sign() {
  unset CI
  _env_unread_mount '    volumes: [".:/app"]'
}

# --- signs without a detector ------------------------------------------------------

test_runenv_refuses_when_db_host_names_a_compose_service() {
  unset CI
  cat > docker-compose.yml <<'EOF'
services:
  mysql:
    image: mysql:8
EOF
  printf 'DB_HOST=mysql\n' > .env
  _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "refusal=[this project looks like it runs in a container (.env sets DB_HOST=mysql, a service in docker-compose.yml)"
  assert_contains "$OUT" "jig config set run.exec"
}

test_runenv_a_database_in_compose_beside_a_host_app_is_not_a_sign() {
  unset CI
  cat > docker-compose.yml <<'EOF'
services:
  mysql:
    image: mysql:8
EOF
  printf 'DB_HOST=127.0.0.1\n' > .env
  _env_resolve
  assert_contains "$OUT" "where=[host"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_refuses_when_two_services_mount_the_project() {
  unset CI
  cat > compose.yml <<'EOF'
services:
  web:
    volumes:
      - .:/var/www
  worker:
    volumes:
      - .:/var/www
EOF
  _env_resolve
  assert_contains "$OUT" "2 services in compose.yml mount the project (web,worker)"
}

test_runenv_refuses_for_devcontainer_ddev_and_lando() {
  unset CI
  mkdir .devcontainer .ddev
  : > .lando.yml
  _env_resolve
  assert_contains "$OUT" "a devcontainer is defined; a DDEV project (.ddev/); a Lando project (.lando.yml)"
}

test_runenv_plain_project_runs_on_the_host() {
  unset CI
  _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "where=[host]"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_host_setting_ignores_the_signs() {
  unset CI
  mkdir .devcontainer
  RUN_EXEC=host _env_resolve
  assert_contains "$OUT" "where=[host (run.exec: host)"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_ci_neither_detects_nor_refuses() {
  _env_sail_project
  mkdir .devcontainer
  CI=1 _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "where=[host (CI is set)"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_a_set_prefix_is_used_as_is() {
  unset CI
  mkdir -p stub-bin
  printf '#!/usr/bin/env bash\nshift\nexec "$@"\n' > stub-bin/inbox
  chmod +x stub-bin/inbox
  PATH="$PWD/stub-bin:$PATH" RUN_EXEC="inbox php-container" _env_resolve
  assert_contains "$OUT" "exec=[inbox php-container"
  assert_contains "$OUT" "where=[inbox php-container (run.exec)"
  assert_contains "$OUT" "refusal=[]"
}

# --- readiness ---------------------------------------------------------------------

test_runenv_refuses_an_environment_that_is_not_running() {
  unset CI
  _env_sail_project
  _env_docker_stub down
  _env_resolve
  assert_contains "$OUT" 'refusal=[the environment is not running (docker compose exec -T -u sail -w /var/www/html laravel.test (Laravel Sail, detected)): service "app" is not running; start it with: ./vendor/bin/sail up -d]'
}

test_runenv_refuses_an_environment_that_mounts_another_checkout() {
  unset CI
  _env_sail_project
  printf 'gitdir: /here/.git/worktrees/mine\n' > .git
  _env_docker_stub other
  _env_resolve
  assert_contains "$OUT" "refusal=[the environment does not see this checkout"
}

test_runenv_accepts_an_environment_that_mounts_this_worktree() {
  unset CI
  _env_sail_project
  printf 'gitdir: /here/.git/worktrees/mine\n' > .git
  _env_docker_stub
  _env_resolve
  assert_contains "$OUT" "refusal=[]"
}

# --- jig verify ----------------------------------------------------------------------

_env_laravel_install() {
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null
  _env_sail_project
  _env_php_stub
}

test_runenv_verify_runs_laravel_through_sail() {
  unset CI
  _env_laravel_install
  _env_docker_stub
  run jig verify --profile laravel
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "verify: checks run in docker compose exec -T -u sail -w /var/www/html laravel.test (Laravel Sail, detected)"
  assert_contains "$OUT" "laravel: artisan test: pass (PHP 8.4.0)"
  assert_contains "$(cat docker.log)" "compose exec -T -u sail -w /var/www/html laravel.test php artisan test"
  assert_contains "$(cat docker.log)" "compose exec -T -u sail -w /var/www/html laravel.test php --version"
}

test_runenv_verify_refuses_with_exit_3_and_runs_nothing() {
  unset CI
  _env_laravel_install
  cat > docker-compose.yml <<'EOF'
services:
  mysql:
    image: mysql:8
EOF
  run jig verify --profile laravel
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "verify: refused: this project looks like it runs in a container"
  assert_not_contains "$OUT" "RESULT"
  [ ! -f artisan.log ] || fail "artisan ran on the host"
}

test_runenv_verify_explain_names_the_environment_or_refuses() {
  unset CI
  fixture_repo
  jig init --from "$JIG_HOME" --profiles laravel >/dev/null
  run jig verify --explain --profile generic
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "verify: checks run in host"
  _env_sail_project
  _env_docker_stub down
  run jig verify --explain --profile generic
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "verify: refused: the environment is not running"
}

test_runenv_verify_never_runs_an_unadapted_profile_on_the_host() {
  unset CI
  _env_laravel_install
  _env_docker_stub
  mkdir -p .ai/profiles/hostonly
  printf 'name: hostonly\ndescription: a profile that never declared environment.\ndetect: always\nscope: [changed]\n' \
    > .ai/profiles/hostonly/profile.yaml
  printf '#!/usr/bin/env bash\ntouch hostonly.ran\nexit 0\n' > .ai/profiles/hostonly/verify.sh
  run jig verify --profile laravel,hostonly
  assert_contains "$OUT" "RESULT hostonly: skip (not adapted to run in docker compose exec -T -u sail -w /var/www/html laravel.test (Laravel Sail, detected); its checks were not run on the host)"
  assert_contains "$OUT" "RESULT laravel: pass"
  [ ! -f hostonly.ran ] || fail "the unadapted profile ran"
}

test_runenv_verify_hands_the_prefix_only_to_a_profile_that_declares_it() {
  unset CI
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local p
  for p in yes no; do
    mkdir -p ".ai/profiles/$p"
    printf 'name: %s\ndescription: probe.\ndetect: always\n' "$p" > ".ai/profiles/$p/profile.yaml"
    printf '#!/usr/bin/env bash\necho "%s: exec=${JIG_RUN_EXEC:-<unset>}"\nexit 0\n' "$p" > ".ai/profiles/$p/verify.sh"
  done
  printf 'scope: [environment]\n' >> .ai/profiles/yes/profile.yaml
  run env JIG_RUN_EXEC=leak "$JIG_BIN" verify --profile yes,no
  assert_contains "$OUT" "yes: exec=<unset>"
  assert_contains "$OUT" "no: exec=<unset>"
}

# --- jp_exec / jp_have ------------------------------------------------------------------

test_runenv_jp_run_goes_through_the_prefix_and_closes_stdin() {
  mkdir -p stub-bin
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/wrap.log"\nshift\nexec "$@"\n' "$PWD" > stub-bin/wrap
  chmod +x stub-bin/wrap
  run bash -c '
    PATH="$(pwd)/stub-bin:$PATH" JIG_RUN_EXEC="wrap box"
    . "$JIG_HOME/scripts/lib/profile.sh"
    jp_begin probe
    jp_run "a check" "" sh -c "read -r x && echo got:\$x || echo stdin-closed"
    v=$(jp_version sh -c "echo v1")
    echo "version=$v"
    if jp_have sh; then echo have-sh; fi
    if ! jp_have no-such-tool-here; then echo no-tool; fi
  ' <<<"leaked"
  assert_contains "$OUT" "stdin-closed"
  assert_contains "$OUT" "probe: a check: pass"
  assert_contains "$OUT" "version=v1"
  assert_contains "$OUT" "have-sh"
  assert_contains "$OUT" "no-tool"
  assert_contains "$(cat wrap.log)" "box sh -c read -r x"
}

test_runenv_jp_exec_without_a_prefix_runs_as_is() {
  run bash -c '
    unset JIG_RUN_EXEC
    . "$JIG_HOME/scripts/lib/profile.sh"
    f() { echo "function ran: $*"; }
    jp_exec f a b
  '
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "function ran: a b"
}

# --- the setting ------------------------------------------------------------------------

test_runenv_config_set_accepts_a_prefix_and_refuses_quotes() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig config set run.exec "docker exec -i -w /shared/httpd/app php" --local
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(cat .ai/config.local.yaml)" "run.exec: docker exec -i -w /shared/httpd/app php"
  run jig config set run.exec "docker exec 'php'" --local
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "plain words"
}
