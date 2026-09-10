---
id: rule-verify
type: rule
status: active
summary: "Constraints on running checks: exit codes decide results, the changed-file list is computed once, capabilities are named before they are granted."
domains:
  - verify
topics: []
load: domain
requires: []
paths:
  - scripts/lib/verify.sh
  - scripts/lib/profiles.sh
  - "profiles/**"
---
# Verify rules

The project-wide invariants on capability granting and on "a skip is not a pass" are in
the global `RULES.md` (ADR-0013). What follows binds changes inside this domain.

## Invariants

- A profile is run from the repository root, in a subshell, and its exit code is the only
  thing that decides its result. `cmd_verify` never inspects a profile's output to
  decide pass or fail — profiles are user-modifiable and their prose is not an API.
- Exit code 2 means skip and must stay distinguishable from 0. Collapsing skip into pass
  would let an unrunnable check report success.
- The changed-file list is computed once, in `_verify_changed_files`, and shared. Two
  profiles must never disagree about what changed in the same run.
- The changed-file list includes staged, unstaged and untracked files: a project is
  verified in the state it is in, not the state it was committed in.

## Rules

- A new capability gets a name in `profile.yaml`'s `scope` list and is passed only to
  profiles that name it. Adding a capability that older profiles could observe by default
  would break profiles written before it existed.
- `detect` globs live in `profile.yaml` and nowhere else. No command re-derives the
  mapping from root manifest to stack.
- A profile's `verify.sh` prints one line per check it ran, because a profile runs
  several and a single profile-level result hides which of them fired.
