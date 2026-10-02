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

# _env_wrapper_stub <tool> <skip> [down] — a `<tool>` on PATH that logs its
# call to <tool>.log, drops its first <skip> words (its own subcommand and
# options) and runs the rest on this machine; `down` fails the way the tool
# does for an environment that is not running.
_env_wrapper_stub() {
  local tool="$1" skip="$2" mode="${3:-up}"
  mkdir -p stub-bin
  cat > "stub-bin/$tool" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/$tool.log"
if [ "$mode" = down ]; then
  printf '$tool: the environment is not running\n' >&2
  exit 1
fi
shift $skip
exec "\$@"
STUB
  chmod +x "stub-bin/$tool"
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _env_labelled_docker_stub <label> [<mount source>] — a `docker` that knows
# one running container, proj_app_1, carrying <label> and mounting
# <mount source> (default: this directory) at /workspace; `exec` runs the
# command after its options on this machine.
_env_labelled_docker_stub() {
  local label="$1" src="${2:-$(pwd -P)}"
  mkdir -p stub-bin
  cat > stub-bin/docker <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/docker.log"
case "\$1" in
  ps)
    case "\$*" in *"label=$label"*) echo abc123 ;; esac
    ;;
  inspect)
    printf '/proj_app_1\n$src\t/workspace\n/other\t/elsewhere\n'
    ;;
  exec)
    shift
    while [ \$# -gt 0 ]; do
      case "\$1" in
        -w) shift 2 ;;
        -*) shift ;;
        *) break ;;
      esac
    done
    shift
    exec "\$@"
    ;;
esac
STUB
  chmod +x stub-bin/docker
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _env_hide <tool> — drop from PATH every directory that holds <tool>.
_env_hide() {
  local d kept="" IFS=:
  for d in $PATH; do
    [ -x "$d/$1" ] || kept="${kept:+$kept:}$d"
  done
  PATH="$kept"
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
# run.exec from $RUN_EXEC and run.path from $RUN_PATH (default auto for
# both), and print what it decided.
_env_resolve() {
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; JIG_PROJECT="$(pwd)"
    . "$JIG_LIB/common.sh"; . "$JIG_LIB/runenv.sh"
    cfg() {
      case "$1" in
        run.exec) printf "%s\n" "${RUN_EXEC:-$2}" ;;
        run.path) printf "%s\n" "${RUN_PATH:-$2}" ;;
        *) printf "%s\n" "$2" ;;
      esac
    }
    runenv_resolve
    printf "exec=[%s]\nwhere=[%s]\nup=[%s]\nrefusal=[%s]\npath=[%s]\n" "$RUNENV_EXEC" "$RUNENV_WHERE" "$RUNENV_UP" "$RUNENV_REFUSAL" "$RUNENV_PATH"
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

test_runenv_refuses_for_a_devcontainer_or_ddev_folder_without_a_manifest() {
  unset CI
  mkdir .devcontainer .ddev
  _env_resolve
  assert_contains "$OUT" "a devcontainer is defined; a DDEV project (.ddev/)"
  assert_contains "$OUT" "exec=[]"
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

# --- DDEV, Lando, devcontainer --------------------------------------------------------

test_runenv_detects_ddev() {
  unset CI
  mkdir .ddev
  printf 'name: site\n' > .ddev/config.yaml
  _env_wrapper_stub ddev 2
  _env_resolve
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "exec=[ddev exec --raw]"
  assert_contains "$OUT" "(DDEV, detected)"
  assert_contains "$OUT" "up=[ddev start]"
  assert_contains "$OUT" "refusal=[]"
  assert_contains "$(cat ddev.log)" "exec --raw sh -c"
}

test_runenv_ddev_that_is_stopped_is_refused_with_its_start_command() {
  unset CI
  mkdir .ddev
  : > .ddev/config.yaml
  _env_wrapper_stub ddev 2 down
  _env_resolve
  assert_contains "$OUT" "refusal=[the environment is not running (ddev exec --raw (DDEV, detected)): ddev: the environment is not running; start it with: ddev start]"
}

test_runenv_ddev_comes_before_a_compose_service_that_mounts_the_project() {
  unset CI
  mkdir .ddev
  : > .ddev/config.yaml
  printf 'services:\n  app:\n    volumes:\n      - .:/app\n' > compose.yaml
  _env_wrapper_stub ddev 2
  _env_resolve
  assert_contains "$OUT" "exec=[ddev exec --raw]"
}

test_runenv_detects_lando_through_its_labelled_container() {
  unset CI
  printf 'name: site\nrecipe: lamp\n' > .lando.yml
  _env_labelled_docker_stub io.lando.container=TRUE
  _env_resolve
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "exec=[docker exec -i -w /workspace proj_app_1]"
  assert_contains "$OUT" "(Lando, detected)"
  assert_contains "$OUT" "up=[lando start]"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_lando_without_a_running_container_is_refused_with_its_start_command() {
  unset CI
  : > .lando.yml
  _env_labelled_docker_stub io.lando.container=TRUE /somewhere/else
  _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "refusal=[the environment is not running (Lando: no running container mounts the project); start it with: lando start]"
}

test_runenv_detects_a_devcontainer_through_its_cli() {
  unset CI
  mkdir .devcontainer
  : > .devcontainer/devcontainer.json
  _env_wrapper_stub devcontainer 3
  _env_resolve
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "exec=[devcontainer exec --workspace-folder .]"
  assert_contains "$OUT" "(devcontainer, detected)"
  assert_contains "$OUT" "up=[devcontainer up --workspace-folder .]"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_detects_a_devcontainer_through_the_container_label_without_the_cli() {
  unset CI
  : > .devcontainer.json
  _env_hide devcontainer
  _env_labelled_docker_stub "devcontainer.local_folder=$PWD"
  _env_resolve
  assert_contains "$OUT" "exec=[docker exec -i -w /workspace proj_app_1]"
  assert_contains "$OUT" "(devcontainer, detected)"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_devcontainer_that_is_stopped_is_refused() {
  unset CI
  mkdir .devcontainer
  : > .devcontainer/devcontainer.json
  _env_wrapper_stub devcontainer 3 down
  _env_resolve
  assert_contains "$OUT" "refusal=[the environment is not running (devcontainer exec --workspace-folder . (devcontainer, detected)): devcontainer: the environment is not running; start it with: devcontainer up --workspace-folder .]"
}

test_runenv_devcontainer_without_a_cli_or_container_is_refused() {
  unset CI
  mkdir .devcontainer
  : > .devcontainer/devcontainer.json
  _env_hide devcontainer
  _env_labelled_docker_stub "devcontainer.local_folder=/not/here"
  _env_resolve
  assert_contains "$OUT" "refusal=[the environment is not running (devcontainer: no running container mounts the project); start it with: devcontainer up --workspace-folder ."
}

test_runenv_inside_the_environment_runs_on_the_host() {
  unset CI
  mkdir .devcontainer .ddev
  : > .devcontainer/devcontainer.json
  : > .ddev/config.yaml
  : > .lando.yml
  local marker
  for marker in REMOTE_CONTAINERS=true CODESPACES=true IS_DDEV_PROJECT=true LANDO=ON; do
    run env "$marker" bash -c '
      JIG_LIB="$JIG_HOME/scripts/lib"; JIG_PROJECT="$(pwd)"
      . "$JIG_LIB/common.sh"; . "$JIG_LIB/runenv.sh"
      cfg() { printf "%s\n" "$2"; }
      runenv_resolve
      printf "exec=[%s] where=[%s] refusal=[%s]\n" "$RUNENV_EXEC" "$RUNENV_WHERE" "$RUNENV_REFUSAL"
    '
    assert_contains "$OUT" "exec=[] where=[host (this shell is already inside the project's environment)] refusal=[]"
  done
}

test_runenv_verify_runs_php_through_ddev() {
  unset CI
  fixture_repo
  jig init --from "$JIG_HOME" --profiles php >/dev/null
  mkdir .ddev
  : > .ddev/config.yaml
  _env_wrapper_stub ddev 2
  run jig verify --explain --profile php
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "verify: checks run in ddev exec --raw (DDEV, detected)"
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

# --- Devilbox -------------------------------------------------------------------------

# _env_devilbox_stub [running|stopped] [<mount source>] [<destination>] [<env>]
# — a `docker` that knows one Devilbox PHP container, server-php-1 (compose
# service php, stack folder /stack), mounting <mount source> (default: the
# parent of this directory, as Docker Desktop on macOS spells it) at
# <destination> (default /shared/httpd), with <env> (default MY_USER=devilbox)
# in its environment; `exec` runs the command after its options here.
_env_devilbox_stub() {
  local state="${1:-running}" src="${2:-/host_mnt$(dirname "$(pwd -P)")}" dst="${3:-/shared/httpd}" env="${4-MY_USER=devilbox}" run=true
  [ "$state" = running ] || run=false
  mkdir -p stub-bin
  cat > stub-bin/docker <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/docker.log"
case "\$1" in
  ps)
    case "\$*" in *"-a"*"label=com.docker.compose.service=php"*) echo f00d ;; esac
    ;;
  inspect)
    printf '/server-php-1\t$run\t/stack\n'
    printf 'M\t/host_mnt/stack/backups\t/shared/backups\n'
    printf 'M\t$src\t$dst\n'
    printf 'E\tPATH=/usr/bin\n'
    [ -z "$env" ] || printf 'E\t%s\n' "$env"
    ;;
  exec)
    shift
    while [ \$# -gt 0 ]; do
      case "\$1" in
        -u|-w) shift 2 ;;
        -*) shift ;;
        *) break ;;
      esac
    done
    shift
    exec "\$@"
    ;;
esac
STUB
  chmod +x stub-bin/docker
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

test_runenv_detects_devilbox_by_the_container_that_mounts_an_ancestor() {
  unset CI
  _env_devilbox_stub
  _env_resolve
  local name
  name=$(basename "$(pwd -P)")
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "exec=[docker exec -i -u devilbox -w /shared/httpd/$name server-php-1]"
  assert_contains "$OUT" "(Devilbox, detected)"
  assert_contains "$OUT" "up=[cd /stack && docker compose up -d]"
  assert_contains "$OUT" "refusal=[]"
  assert_contains "$(cat docker.log)" "exec -i -u devilbox -w /shared/httpd/$name server-php-1 sh -c"
}

test_runenv_devilbox_reads_its_user_and_a_deeper_project() {
  unset CI
  local base
  base=$(pwd -P)
  mkdir -p www/group/app
  cd www/group/app || fail "cd"
  _env_devilbox_stub running "/run/desktop/mnt/host$base/www" /shared/httpd "MY_USER=web"
  _env_resolve
  assert_contains "$OUT" "exec=[docker exec -i -u web -w /shared/httpd/group/app server-php-1]"
  _env_devilbox_stub running "$base/www/group/app" /shared/httpd ""
  _env_resolve
  assert_contains "$OUT" "exec=[docker exec -i -u devilbox -w /shared/httpd server-php-1]"
}

test_runenv_devilbox_that_is_stopped_is_refused_with_its_start_command() {
  unset CI
  _env_devilbox_stub stopped
  _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "refusal=[the environment is not running (Devilbox: its PHP container server-php-1 is stopped); start it with: cd /stack && docker compose up -d]"
}

test_runenv_a_container_that_mounts_elsewhere_or_not_as_devilbox_is_not_devilbox() {
  unset CI
  _env_devilbox_stub running /host_mnt/somewhere/else
  _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "where=[host]"
  # An ancestor mounted anywhere but Devilbox's data folder: not a match.
  _env_devilbox_stub running "/host_mnt$(dirname "$(pwd -P)")" /home/user
  _env_resolve
  assert_contains "$OUT" "where=[host]"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_a_compose_service_of_the_project_comes_before_devilbox() {
  unset CI
  _env_devilbox_stub
  cat > compose.yml <<'EOF'
services:
  app:
    volumes:
      - .:/app
EOF
  _env_resolve
  assert_contains "$OUT" "(docker compose service app, detected)"
}

test_runenv_devilbox_refuses_a_worktree_outside_its_data_folder() {
  unset CI
  mkdir -p data
  git init -q data/app
  git -C data/app commit -q --allow-empty -m init
  git -C data/app worktree add -q ../../wt 2>/dev/null || fail "worktree add"
  cd wt || fail "cd"
  _env_devilbox_stub running "/host_mnt$(cd ../data && pwd -P)"
  run bash -c '
    JIG_LIB="$JIG_HOME/scripts/lib"; JIG_PROJECT="$(pwd)"; JIG_AI_DIR=.ai
    . "$JIG_LIB/common.sh"; . "$JIG_LIB/config.sh"; . "$JIG_LIB/runenv.sh"
    cfg() { printf "%s\n" "$2"; }
    runenv_resolve
    printf "exec=[%s]\nrefusal=[%s]\n" "$RUNENV_EXEC" "$RUNENV_REFUSAL"
  '
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "refusal=[the environment does not see this checkout (Devilbox, detected): its PHP container server-php-1 mounts the main checkout's folder"
}

test_runenv_a_sign_in_the_project_outranks_a_stack_on_the_machine() {
  unset CI
  _env_devilbox_stub
  mkdir .ddev
  _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "refusal=[this project looks like it runs in a container (a DDEV project (.ddev/))"
}

# --- Laravel Herd ---------------------------------------------------------------------

# _env_herd <home layout> <paths json> — a Herd install under $PWD/home:
# `mac` (Library/Application Support/Herd) or `win` (.config/herd), with a
# php in its bin that names itself, and a Valet config listing <paths json>.
_env_herd() {
  local h
  case "$1" in
    mac) h="$PWD/home/Library/Application Support/Herd" ;;
    *) h="$PWD/home/.config/herd" ;;
  esac
  mkdir -p "$h/bin" "$h/config/valet"
  printf '#!/usr/bin/env bash\necho "herd php"\n' > "$h/bin/php"
  chmod +x "$h/bin/php"
  printf '{\n    "tld": "test",\n    "paths": %s\n}\n' "$2" > "$h/config/valet/config.json"
  HERD_BIN="$h/bin"
}

test_runenv_detects_a_herd_site_in_a_parked_folder() {
  unset CI
  mkdir -p sites/app
  _env_herd mac "[\"$PWD/sites\"]"
  cd sites/app || fail "cd"
  HOME="$OLDPWD/home" _env_resolve
  assert_contains "$OUT" "exec=[]"
  assert_contains "$OUT" "path=[$HERD_BIN]"
  assert_contains "$OUT" "where=[host, with $HERD_BIN first on PATH (Laravel Herd, detected)]"
  assert_contains "$OUT" "refusal=[]"
}

test_runenv_detects_a_linked_herd_site_with_escaped_json() {
  unset CI
  mkdir -p app links
  _env_herd win "[\"$(printf '%s' "$PWD/links" | sed 's#/#\\/#g')\", \"/no/such\"]"
  plant_dir_link "$PWD/app" links/app
  cd app || fail "cd"
  HOME="$OLDPWD/home" _env_resolve
  assert_contains "$OUT" "path=[$HERD_BIN]"
}

test_runenv_herd_leaves_a_project_that_is_not_its_site_alone() {
  unset CI
  mkdir -p sites app
  _env_herd mac "[\"$PWD/sites\"]"
  cd app || fail "cd"
  HOME="$OLDPWD/home" _env_resolve
  assert_contains "$OUT" "where=[host]"
  assert_contains "$OUT" "path=[]"
  # run.exec host turns the detection off with the rest.
  mkdir -p ../sites/site
  cd ../sites/site || fail "cd"
  HOME="$OLDPWD/../home" RUN_EXEC=host _env_resolve
  assert_contains "$OUT" "where=[host (run.exec: host)]"
  assert_contains "$OUT" "path=[]"
}

test_runenv_run_path_names_a_directory_with_a_blank_or_is_refused() {
  unset CI
  mkdir -p "my php/bin"
  RUN_PATH="$PWD/my php/bin" _env_resolve
  assert_contains "$OUT" "path=[$PWD/my php/bin]"
  assert_contains "$OUT" "where=[host, with $PWD/my php/bin first on PATH (run.path)]"
  RUN_PATH="$PWD/missing" _env_resolve
  assert_contains "$OUT" "refusal=[run.path names $PWD/missing, which is not a directory on this machine"
  RUN_PATH="my php/bin" _env_resolve
  assert_contains "$OUT" "refusal=[run.path is my php/bin, not an absolute path"
  # Under a prefix, run.path is not used.
  _env_sail_project
  _env_docker_stub
  RUN_PATH="$PWD/my php/bin" _env_resolve
  assert_contains "$OUT" "(Laravel Sail, detected)"
  assert_contains "$OUT" "path=[]"
}

test_runenv_verify_puts_the_herd_bin_first_on_path_for_every_profile() {
  unset CI
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  local here
  here=$(pwd -P)
  mkdir -p .ai/profiles/probe
  printf 'name: probe\ndescription: probe.\ndetect: always\n' > .ai/profiles/probe/profile.yaml
  printf '#!/usr/bin/env bash\necho "probe: $(php)"\nexit 0\n' > .ai/profiles/probe/verify.sh
  _env_herd mac "[\"$(dirname "$here")\"]"
  HOME="$PWD/home" run jig verify --profile probe
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "verify: checks run in host, with $HERD_BIN first on PATH (Laravel Herd, detected)"
  assert_contains "$OUT" "probe: herd php"
}

test_runenv_config_set_accepts_a_run_path_with_a_blank() {
  fixture_repo
  jig init --from "$JIG_HOME" >/dev/null
  run jig config set run.path "/Users/me/Library/Application Support/Herd/bin" --local
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$(cat .ai/config.local.yaml)" "run.path: /Users/me/Library/Application Support/Herd/bin"
  run jig config set run.path "Herd/bin" --local
  assert_eq 1 "$RC" "$OUT"
  assert_contains "$OUT" "not auto or an absolute path"
}
