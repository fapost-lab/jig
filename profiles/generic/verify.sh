#!/usr/bin/env bash
# Verification for the generic profile. Called by `jig verify` from the
# repository root. Exit 0 = pass. The generic profile has no stack-specific
# checks; it only confirms the working tree is a git repository.
set -eu
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "generic: not a git repository" >&2; exit 1; }
echo "generic: ok"
