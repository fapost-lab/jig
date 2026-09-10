---
id: domain-verify
type: domain
status: active
summary: The profile contract, profile activation and detection, and the scope protocol for narrowed checks.
domains:
  - verify
topics: []
load: domain
paths:
  - scripts/lib/verify.sh
  - scripts/lib/profiles.sh
  - "profiles/**"
---
# Verify

How a project's own checks are described, selected and run, and how a check reports what
it actually did.

## Responsibility

- The profile contract: `profile.yaml` (`name`, `description`, `detect`, `requires`,
  `scope`) and `verify.sh` with its three exit codes — 0 pass, 1 fail, **2 skip**.
- Which profiles are active: explicit activation in `.ai/config.yaml`, and detection from
  root manifests when none is given (`profiles_detect`).
- The scope protocol: computing the changed-file list once and handing it to profiles
  that declared they understand it, via `JIG_VERIFY_SCOPE` and `JIG_VERIFY_FILES`
  (ADR-0013).
- Honest reporting: a narrowed run says what it narrowed to, and an ignored scope is
  printed rather than dropped.

## Boundaries

Outside: what any individual check *does*. `profiles/shell/verify.sh` running shellcheck
is content, not framework. Outside: installing profiles into a project — that is domain
`install`, which owns `profiles_source_dir` and the upgrade decision table; this domain
owns `profiles_installed_dir` and the contract the installed files must satisfy.

`profiles.sh` sits on that seam and is claimed here because its subject is the profile
contract. A change to how profiles are *copied* still belongs to `install`.

## Entry points

- `scripts/lib/verify.sh` — `cmd_verify`, `_verify_changed_files`.
- `scripts/lib/profiles.sh` — `profiles_active`, `profiles_detect`, `profiles_supports`,
  `profiles_check_requires`.
- `profiles/<stack>/profile.yaml` — the one place the mapping "root manifest → stack" is
  written down.
