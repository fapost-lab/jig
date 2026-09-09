#!/usr/bin/env bash
# Verification for the go profile. Called by `jig verify` from the
# repository root. Exit 0 = pass, 1 = fail, 2 = skip (go not found).
set -eu
set -o pipefail

if ! command -v go >/dev/null 2>&1; then
  echo "go: vet: skip (go not found)"
  echo "go: test: skip (go not found)"
  exit 2
fi

status=0

if go vet ./...; then
  echo "go: vet: pass"
else
  echo "go: vet: fail"
  status=1
fi

if go test ./...; then
  echo "go: test: pass"
else
  echo "go: test: fail"
  status=1
fi

exit "$status"
