#!/usr/bin/env bash
# Verification for the php profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (nothing applicable
# found). Never installs anything; only runs project-local binaries that
# already exist under vendor/bin. Prints one line per check:
# "php: <check>: pass|fail|skip (<reason>)".
set -eu
set -o pipefail

status=0
ran_any=0

# _php_run <check-name> <binary> [args...] — run <binary> [args...] when
# <binary> exists and is executable; skip otherwise.
_php_run() {
  local name="$1"
  shift
  if [ -x "$1" ]; then
    ran_any=1
    if "$@"; then
      echo "php: $name: pass"
    else
      echo "php: $name: fail"
      status=1
    fi
  else
    echo "php: $name: skip (not found)"
  fi
}

if [ -x vendor/bin/phpunit ]; then
  _php_run phpunit vendor/bin/phpunit
elif [ -x vendor/bin/pest ]; then
  _php_run pest vendor/bin/pest
else
  echo "php: phpunit: skip (not found)"
fi

_php_run phpstan vendor/bin/phpstan analyse --no-progress
_php_run pint vendor/bin/pint --test

if command -v composer >/dev/null 2>&1; then
  ran_any=1
  if composer validate --no-check-publish; then
    echo "php: composer validate: pass"
  else
    echo "php: composer validate: fail"
    status=1
  fi
else
  echo "php: composer validate: skip (composer not found)"
fi

if [ "$ran_any" -eq 0 ]; then
  exit 2
fi
exit "$status"
