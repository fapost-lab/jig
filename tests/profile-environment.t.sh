# Tests for the stack profiles that run where the project runs
# (adr-20261001-checks-run-where-the-project-runs): shell, python, go, rust,
# ruby, jvm, dotnet, dart and swift declare the `environment` capability, so
# `jig verify` hands them the command prefix and every project command goes
# through it.
# shellcheck shell=bash
#
# No test needs docker. A `docker` stub on PATH logs each call to docker.log
# and runs the command after `compose exec <options> <service>` with an
# extra directory, env-bin/, on PATH. The stack's tools live only there, so a
# profile that asks the host (`command -v`, a host path) finds nothing and
# skips, while one that goes through the prefix finds them. Every test clears
# CI: with CI set, `run.exec` is not consulted.

# _pe_docker_stub — the `docker` on PATH, and an empty env-bin/ it exposes.
_pe_docker_stub() {
  mkdir -p stub-bin env-bin
  cat > stub-bin/docker <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PWD/docker.log"
shift 2
while [ \$# -gt 0 ]; do
  case "\$1" in
    -u|-w) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
shift
PATH="$PWD/env-bin:\${PE_ENV_PATH:-\$PATH}"
exec "\$@"
STUB
  chmod +x stub-bin/docker
  PATH="$PWD/stub-bin:$PATH"
  export PATH
}

# _pe_tool <name>... — a tool in env-bin/ that answers its version flags and
# exits 0 for anything else.
_pe_tool() {
  local name
  for name in "$@"; do
    cat > "env-bin/$name" <<STUB
#!/bin/sh
printf '%s\n' "$name \$*" >> "$PWD/tool.log"
case "\$1" in
  --version|version|-version) printf '$name 1.2.3\n' ;;
esac
exit 0
STUB
    chmod +x "env-bin/$name"
  done
}

# _pe_install <profile> — a project with the profile installed and its checks
# set to run through the docker stub.
_pe_install() {
  unset CI
  fixture_repo
  jig init --from "$JIG_HOME" --profiles "$1" >/dev/null
  _pe_docker_stub
  jig config set run.exec "docker compose exec -T -w /app app" --local >/dev/null
}

# _pe_assert_ran <tool>... — each tool ran through the prefix, never beside it.
_pe_assert_ran() {
  local t
  for t in "$@"; do
    assert_contains "$(cat docker.log)" "compose exec -T -w /app app $t"
  done
}

test_profile_environment_shell_runs_shellcheck_and_tests_through_the_prefix() {
  _pe_install shell
  mkdir -p scripts tests
  printf '#!/bin/sh\ntrue\n' > scripts/a.sh
  chmod +x scripts/a.sh
  printf '#!/bin/sh\nexit 0\n' > tests/run.sh
  chmod +x tests/run.sh
  _pe_tool shellcheck
  run jig verify --profile shell
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "shell: shellcheck: pass"
  assert_contains "$OUT" "shell: tests/run.sh: pass"
  _pe_assert_ran "shellcheck -s bash" "tests/run.sh"
}

test_profile_environment_python_takes_tools_from_the_environment_path() {
  _pe_install python
  printf '[project]\nname = "x"\n' > pyproject.toml
  _pe_tool ruff pytest
  run jig verify --profile python
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: ruff: pass (ruff 1.2.3)"
  assert_contains "$OUT" "python: pytest: pass (pytest 1.2.3)"
  _pe_assert_ran "ruff check" "pytest"
}

test_profile_environment_python_ignores_a_host_virtualenv_it_cannot_run() {
  _pe_install python
  printf '[project]\nname = "x"\n' > pyproject.toml
  mkdir -p .venv/bin
  printf '#!/nonexistent/python\n' > .venv/bin/pytest
  chmod +x .venv/bin/pytest
  _pe_tool pytest
  run jig verify --profile python
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "python: pytest: pass"
  assert_eq 0 "$(grep -c 'app \.venv/bin/pytest$' docker.log || true)" "the host's virtualenv ran in the environment"
}

test_profile_environment_go_runs_vet_and_test_through_the_prefix() {
  _pe_install go
  printf 'module x\n' > go.mod
  _pe_tool go
  run jig verify --profile go
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go 1.2.3)"
  assert_contains "$OUT" "go: test: pass"
  _pe_assert_ran "go vet" "go test"
}

test_profile_environment_go_narrows_to_importers_using_the_environments_paths() {
  unset CI
  fixture_repo
  _pe_docker_stub
  mkdir sub
  printf 'module x\n' > go.mod
  printf 'package sub\n' > sub/a.go
  printf 'package main\n' > main.go
  cat > env-bin/go <<STUB
#!/bin/sh
printf 'go %s\n' "\$*" >> "$PWD/tool.log"
case "\$*" in
  version) printf 'go version go1.22\n' ;;
  *'{{.ImportPath}} {{.Dir}}'*) printf 'x %s\nx/sub %s/sub\n' "$PWD" "$PWD" ;;
  *'{{.Dir}} {{join'*) printf '%s x/sub\n%s/sub \n' "$PWD" "$PWD" ;;
esac
exit 0
STUB
  chmod +x env-bin/go
  printf 'sub/a.go\n' > changed-files
  JIG_RUN_EXEC="docker compose exec -T -w /app app"
  JIG_VERIFY_SCOPE=changed
  JIG_VERIFY_FILES="$PWD/changed-files"
  export JIG_RUN_EXEC JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  run bash "$JIG_HOME/profiles/go/verify.sh"
  unset JIG_RUN_EXEC JIG_VERIFY_SCOPE JIG_VERIFY_FILES
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: pass (go version go1.22, scope: 1 packages)"
  assert_contains "$OUT" "go: test: pass (go version go1.22, scope: 2 packages)"
  _pe_assert_ran "go list"
}

test_profile_environment_a_tool_missing_in_the_environment_is_a_skip_not_a_host_run() {
  _pe_install go
  printf 'module x\n' > go.mod
  mkdir -p host-bin
  printf '#!/bin/sh\nprintf host >> host-go.log\n' > host-bin/go
  chmod +x host-bin/go
  PATH="$PWD/host-bin:$PATH"
  # The environment sees system directories only, and no go among them.
  PE_ENV_PATH=/usr/bin:/bin
  export PE_ENV_PATH
  if PATH=$PE_ENV_PATH command -v go >/dev/null 2>&1; then
    return 0
  fi
  run jig verify --profile go
  assert_eq 3 "$RC" "$OUT"
  assert_contains "$OUT" "go: vet: skip"
  [ ! -f host-go.log ] || fail "go ran on the host"
}

test_profile_environment_rust_runs_cargo_through_the_prefix() {
  _pe_install rust
  printf '[package]\nname = "x"\n' > Cargo.toml
  _pe_tool cargo
  run jig verify --profile rust
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "rust: fmt: pass"
  assert_contains "$OUT" "rust: clippy: pass"
  assert_contains "$OUT" "rust: test: pass"
  _pe_assert_ran "cargo fmt --check" "cargo clippy" "cargo test"
}

test_profile_environment_ruby_runs_bundle_through_the_prefix() {
  _pe_install ruby
  printf "source 'https://rubygems.org'\n" > Gemfile
  printf 'GEM\n  specs:\n    rspec-core (3.13.0)\n    rubocop (1.60.0)\n' > Gemfile.lock
  _pe_tool bundle
  run jig verify --profile ruby
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "ruby: rubocop: pass"
  assert_contains "$OUT" "ruby: rspec: pass"
  _pe_assert_ran "bundle exec rubocop" "bundle exec rspec"
}

test_profile_environment_jvm_runs_gradle_from_the_environment_path() {
  _pe_install jvm
  : > build.gradle
  _pe_tool gradle
  run jig verify --profile jvm
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: check: pass"
  _pe_assert_ran "gradle check"
}

test_profile_environment_jvm_runs_the_maven_wrapper_through_the_prefix() {
  _pe_install jvm
  : > pom.xml
  printf '#!/bin/sh\nexit 0\n' > mvnw
  _pe_tool sh
  run jig verify --profile jvm
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "jvm: test: pass"
  _pe_assert_ran "sh ./mvnw"
}

test_profile_environment_dotnet_runs_format_and_test_through_the_prefix() {
  _pe_install dotnet
  : > App.sln
  _pe_tool dotnet
  run jig verify --profile dotnet
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dotnet: format: pass (dotnet 1.2.3)"
  assert_contains "$OUT" "dotnet: test: pass"
  _pe_assert_ran "dotnet format" "dotnet test"
}

test_profile_environment_dart_runs_analyze_format_and_test_through_the_prefix() {
  _pe_install dart
  printf 'name: x\n' > pubspec.yaml
  _pe_tool dart
  run jig verify --profile dart
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "dart: analyze: pass"
  assert_contains "$OUT" "dart: format: pass"
  assert_contains "$OUT" "dart: test: pass"
  _pe_assert_ran "dart analyze" "dart format" "dart test"
}

test_profile_environment_swift_runs_build_and_test_through_the_prefix() {
  _pe_install swift
  : > Package.swift
  _pe_tool swift
  run jig verify --profile swift
  assert_eq 0 "$RC" "$OUT"
  assert_contains "$OUT" "swift: build: pass"
  assert_contains "$OUT" "swift: test: pass"
  _pe_assert_ran "swift build" "swift test"
}
