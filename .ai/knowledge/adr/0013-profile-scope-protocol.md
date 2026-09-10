---
id: adr-0013-profile-scope-protocol
type: adr
status: accepted
date: 2026-09-09
domains:
  - scripts
  - profiles
paths:
  - scripts/lib/verify.sh
  - "profiles/**"
reviewed_at: 2026-09-09
summary: Why a verify scope is a file list at the profile boundary, and why an ignored scope is reported.
---
# ADR-0013: `jig verify` narrows by changed files, and every profile declares whether it understands the scope

## Context

`jig verify` had one button: run everything. Every route ends in verify, so a task pays
the full cost several times. Measured on this repository: a full `jig verify` is 380 s
(334 tests plus shellcheck over 36 files, of which shellcheck is 4.5 s). Verifying a
documentation-only change cost all 380 s, essentially every second of it tests that could
not have been affected; the same change under `--changed` runs no tests at all.

Two constraints shaped the answer.

Profiles do not share a filter syntax. `go test -run <regex>`, `phpunit --filter
<regex>`, `artisan test --filter <name>` and `tests/run.sh <substring>` take different
things, and the node profile cannot map a pattern at all without knowing whether the
runner is jest, vitest or mocha. A scope expressed as a filter string means something
different in every profile, and a pattern that matches nothing reports zero tests as a
pass. A scope expressed as a *file list* means the same thing everywhere.

Version skew is guaranteed, not hypothetical. Profiles are copied into projects
(ADR-0003) and `upgrade` preserves user-modified files as `keep-modified` (RULES
invariant). A new `jig verify` will meet `verify.sh` scripts written before this
protocol existed.

## Decision

`jig verify --changed [--base <ref>]` computes the changed-file list once — staged,
unstaged and untracked — writes it to a temporary file, and passes it to profiles through
`JIG_VERIFY_SCOPE=changed` and `JIG_VERIFY_FILES=<path>`. Translating files into checks
is the profile's job, because that is where the knowledge of the stack already lives.

A profile receives the scope only if its `profile.yaml` declares `scope: [changed]`.
Support is declared, never assumed. A profile without the declaration is run with both
variables explicitly unset — not merely left as the caller's environment had them — so an
older or user-modified script can never observe a scope it was not written to honour.

The report never leaves the scope implicit:

```
RESULT shell: pass (scope: changed, 3 files)
RESULT php:   pass (scope ignored: profile declares no scope support, ran full set)
```

A profile that cannot map a changed path to a subset runs its full set and says so
(`scope: not narrowable, ran full set`). A supporting profile with an empty list is
reported `skip`, never `pass`.

`--changed` is opt-in and is never the default. It is for iteration; the evidence that a
task is done is an unscoped run.

## Alternatives

**A filter string passed through to the runner** (`--tests <pattern>`). Rejected: the
value means a different thing per stack, so one pattern is correct in one profile and
matches nothing in the next, where zero tests read as a pass. Available later as an
explicitly stack-specific escape hatch, on top of this protocol.

**Check-level scope only** (`--only tests`, `--skip lint`). Uniform and simple, but it
does not address the cost: on this repository it saves the 4.5 s of shellcheck out of
380 s and still runs every test. It needs the same protocol machinery as this decision,
so it is a cheap later addition rather than an alternative to it. That ~1 % is specific
to this repository — in a project where `phpstan` or `eslint` dominates the run,
check-level scope is worth considerably more.

**Nothing; let agents narrow by calling the runner directly.** This was the status quo,
and it is what produced a self-matching `pgrep -f` wait loop that hung for nine hours: an
instruction to be selective with no mechanism to be selective invites improvisation.

**Assume support instead of declaring it.** Rejected on the skew above. A silently
ignored scope makes `pass` mean something different per profile, which is the same defect
as treating a skip as a pass.

## Consequences

Verifying a documentation change runs no tests and reports `skip`, in well under a
second against 380 s unscoped.
A single-library change runs that library's tests only.

The protocol is now a distributed contract: `profile.yaml`'s `scope` key and the two
environment variables are copied into every project and hashed into `.ai/manifest`.
Changing their shape later means an upgrade across six shipped profiles, and profiles a
user has edited stay behind as `keep-modified`.

Each profile now carries a files-to-checks mapping that can rot. The shell profile's
mapping (`profiles/shell/verify.sh:_shell_test_filters`) defaults to running everything
for any path it does not recognise, so rot costs time rather than coverage. That default
is the load-bearing part of the design and must survive edits to the table.

Only the shell profile implements the mapping today. The other five declare no support
and are reported as ignoring the scope, which is the intended honest behaviour, not a
gap to be hidden.
