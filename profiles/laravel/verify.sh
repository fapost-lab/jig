#!/usr/bin/env bash
# Verification for the laravel profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip. Only runs Laravel's
# own test runner; PHPUnit/Pest/PHPStan/Pint/composer validate are the php
# profile's job (requires: [php], SPEC §30) and are not duplicated here.
set -eu
set -o pipefail

if [ -f artisan ] && command -v php >/dev/null 2>&1; then
  if php artisan test; then
    echo "laravel: artisan test: pass"
    exit 0
  else
    echo "laravel: artisan test: fail"
    exit 1
  fi
else
  echo "laravel: artisan test: skip (artisan or php not found)"
  exit 2
fi
