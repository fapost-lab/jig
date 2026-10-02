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
  - schemas/verify-map.md
  - ".ai/verify/**"
  - scripts/lib/profile.sh
  - schemas/profile.md
  - scripts/lib/runenv.sh
  - scripts/lib/hostruntime.sh
reviewed_at: 2026-10-01
---
# Verify

How a project's own checks are described, selected and run, and how a check reports what
it actually did.

## Responsibility

- The profile contract: `profile.yaml` (`name`, `description`, `detect`, `requires`,
  `scope`) and `verify.sh` with its four exit codes — 0 pass, 1 fail, **2 skip**,
  **3 incomplete**: a check that started and did not finish, which is neither a pass nor a
  fail and means run it again. A profile killed by a signal (128+N) says the same without
  knowing it. `jig verify` itself exits 3 for a run that produced no verdict at all — one
  where nothing passed and nothing failed
  (adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass).
- Which profiles are active: explicit activation in `.ai/config.yaml`, and detection from
  root manifests (`profiles_detect`), which a first `jig init` turns into activation
  (adr-20260918-init-activates-detected-profiles). Detection skips dependency directories
  and `.ai/`.
- The profile library `scripts/lib/profile.sh` and the thirteen shipped profiles: where each
  finds its tools and how it narrows each check
  (adr-20260918-profiles-narrow-per-check-with-project-tools).
- The scope protocol: computing the changed-file list once and handing it to profiles
  that declared they understand it, via `JIG_VERIFY_SCOPE` and `JIG_VERIFY_FILES`
  (ADR-0013).
- The CI-backed mode (ADR-0041): with `verify.full_run: ci` a flag-less run narrows to what
  changed since the merge base with `git.base_branch`, and `--full` or a non-empty `CI`
  restore the full set. The mode and its reason are printed in a header line.
- The project map `.ai/verify/<profile>.map` (`schemas/verify-map.md`): parsed and validated
  here, handed as `JIG_VERIFY_MAPPED` to profiles declaring `scope: [changed, map]`.
- Where the project's checks run (adr-20261001-checks-run-where-the-project-runs):
  `scripts/lib/runenv.sh` decides once per run — `run.exec`, the detectors (Sail, DDEV,
  Lando, devcontainer, docker compose, Devilbox, Herd), the signs that refuse, the readiness
  probe — and the prefix reaches profiles declaring `scope: [..., environment]` as
  `JIG_RUN_EXEC`. A host runtime not first on `PATH` (Herd, or `run.path`) is a directory
  `cmd_verify` puts first on `PATH` for every profile, not a prefix.
- The host runtime check (`scripts/lib/hostruntime.sh`): when the checks run on the host,
  `jig doctor` and `jig verify --explain` compare the host's php, node and python with what
  the project asks for (`composer.json` `require.php`, `package.json` `engines.node`,
  `.python-version`). Common constraint forms are judged; any other is "could not compare",
  never an ok. `_hostruntime_version` is the one place that names which binary the host runs.
- Honest reporting: a narrowed run says what it narrowed to, and an ignored scope is
  printed rather than dropped.

## Boundaries

Outside: what any individual check *does*. `profiles/shell/verify.sh` running shellcheck
is content, not framework. Outside: installing profiles into a project — that is domain
`install`, which owns `profiles_source_dir` and the upgrade decision table; this domain
owns `profiles_installed_dir` and the contract the installed files must satisfy.

One property of profile content is still a rule for any profile that walks the tree:
inside git, take the file list from git (`git ls-files -co --exclude-standard`, skipping
paths no longer on disk), not from the filesystem. Agent runtimes nest whole worktrees
inside the repository, and git lists such a tree as one directory entry instead of a second
copy of the project.

`profiles.sh` sits on that seam and is claimed here because its subject is the profile
contract. A change to how profiles are *copied* still belongs to `install`.

## Entry points

- `scripts/lib/verify.sh` — `cmd_verify`, `_verify_changed_files`, `_verify_map_check`,
  `_verify_map_apply`.
- `scripts/lib/profile.sh` — `jp_begin`, `jp_changed`, `jp_changed_any`, `jp_decide`,
  `jp_path_matches`, `jp_is_doc`, `jp_first_missing`, `jp_files`, `jp_version`, `jp_run`,
  `jp_exec`, `jp_have`, `jp_skip`, `jp_end`.
- `scripts/lib/runenv.sh` — `runenv_resolve`, `_runenv_detect`, `_runenv_signs`,
  `_runenv_probe`.
- `scripts/lib/hostruntime.sh` — `hostruntime_report`, `_hr_satisfies`, `_hostruntime_version`.
- `profiles/python/verify.sh` — the reference profile on the library; each profile's header
  comment states where its tools come from and how it narrows.
- `profiles/shell/verify.sh` — `_shell_builtin_filters`, the reference for what a shipped
  profile may know about a project (nothing beyond its stack's conventions).
- `scripts/lib/profiles.sh` — `profiles_active`, `profiles_detect`, `profiles_supports`,
  `profiles_check_requires`.
- `profiles/<stack>/profile.yaml` — the one place the mapping "root manifest → stack" is
  written down; its keys are described in `schemas/profile.md`.
