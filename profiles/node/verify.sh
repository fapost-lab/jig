#!/usr/bin/env bash
# Verification for the node profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (nothing applicable
# found).
set -eu
set -o pipefail

status=0
ran_any=0

# _node_has_script <name> — true when package.json declares a "<name>"
# script. Grep-based on purpose: SPEC requires no mandatory dependency
# besides git, so a JSON parser (e.g. jq) cannot be assumed present.
_node_has_script() {
  [ -f package.json ] || return 1
  grep -qE "\"$1\"[[:space:]]*:" package.json
}

if command -v npm >/dev/null 2>&1 && _node_has_script test; then
  ran_any=1
  if npm test; then
    echo "node: npm test: pass"
  else
    echo "node: npm test: fail"
    status=1
  fi
else
  echo "node: npm test: skip (no test script or npm not found)"
fi

if command -v npm >/dev/null 2>&1 && _node_has_script lint; then
  ran_any=1
  if npm run lint; then
    echo "node: npm run lint: pass"
  else
    echo "node: npm run lint: fail"
    status=1
  fi
else
  echo "node: npm run lint: skip (no lint script or npm not found)"
fi

if [ "$ran_any" -eq 0 ]; then
  exit 2
fi
exit "$status"
