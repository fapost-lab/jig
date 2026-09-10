---
id: adr-0017-verify-refuses-a-stale-install
type: adr
status: accepted
date: 2026-09-09
domains:
  - install
  - verify
paths:
  - scripts/lib/verify.sh
  - scripts/lib/upgrade.sh
  - scripts/lib/status.sh
summary: Why a never-installed framework file is a gap drift cannot see, and why verify refuses to run across it.
reviewed_at: 2026-09-09
---
# ADR-0017: `pending` is a kind of gap, and `verify` refuses to run across it

## Context

A skill added under `skills/` does not exist for any runtime until `jig upgrade` places
it: copied into `.claude/skills/` and `.codex/skills/` in copy mode, symlinked there in
link mode. Nothing reported the interval between the two.

`jig status` reports drift as `modified` and `missing`, both computed by walking the paths
recorded in `.ai/manifest`. A path that was never installed has no manifest entry, so it
is neither modified nor missing — it is invisible by construction. In link mode the
manifest carries no path lines at all (ADR-0003), so drift is structurally `0 modified, 0
missing` no matter how far behind the project is.

This is not hypothetical. `skills/jig-map/` was authored, validated and committed to the
working tree while `.claude/skills/jig-map` did not exist; every runtime reported eight
skills where the repository had nine. The session that noticed concluded that the
framework had no mechanism to create the link — it had one, `jig upgrade`, and had had
one all along. Both halves were present and nothing connected them, which is the
signature of a missing report rather than a missing feature.

`jig upgrade --dry-run` already computed the answer exactly, and printed it as one action
line per path.

## Decision

**`pending` is a distinct kind of gap, reported beside drift.** `jig status` prints
`drift: <m> modified, <x> missing, <p> pending`, where pending counts framework-owned
items an upgrade would install or link right now. Pending and drift are not merged
because they are different questions with different repairs: drift is "installed and since
changed", pending is "the source has it and the project does not".

**`jig verify` refuses to run any profile while anything is pending.** It prints the
pending paths and `FAIL framework: <n> framework file(s) not installed (run jig upgrade)`
and exits non-zero before the profile loop. A pass computed against a stale install is not
evidence of anything — and the staleness can be in the checks themselves, since a
profile's `verify.sh` is framework-owned and installed by the same mechanism.

**Unknown is not zero.** When the framework source root cannot be resolved — a copy-mode
install whose source checkout no longer exists on this machine — pending is unknown:
`status` omits the field rather than printing `0 pending`, and `verify` runs the profiles
normally. The check is best-effort and must never convert an absent source into a failure.

The count is computed from `jig upgrade --dry-run`, not from a second implementation of
the decision table. One place decides what an upgrade would do; `status` and `verify` ask
it.

## Alternatives

- **Extend drift to cover it.** Rejected: drift is defined against the manifest, and the
  whole problem is a path the manifest has never heard of. Widening one word to mean two
  gaps with different repairs would make `0 missing` mean less, not more.
- **Report it and stop there** — `status` prints pending, `verify` stays silent. Rejected
  on this repository's own evidence: the missing symlink was visible in `ls` output for
  hours and nobody looked. A report no one reads is not a control.
- **Have `verify` run `upgrade` itself.** Rejected: `verify` is a reporting command, and a
  check that mutates the project makes its own result unreproducible. `upgrade` also
  deletes framework-owned files that left the source; that is not something a verify run
  may do as a side effect.
- **A working rule in `AGENTS.md` and nothing else** ("adding a skill is not finished
  until `jig upgrade`"). Rejected as *sufficient*, kept as a complement: an instruction to
  an agent is a habit, not an invariant, and ADR-0001's premise is that mechanics belong
  in scripts rather than in prose the agent may skip.
- **Fail when pending cannot be determined.** Rejected: a copy-mode install whose source
  is gone is a normal, supported state (SPEC §32). Failing there would break verify for
  exactly the projects copy mode exists to serve.
- **A `jig doctor` command carrying all such checks.** Rejected for now: one more command
  to remember, reporting something the two commands agents already run can report in
  place.

## Consequences

- `jig verify` can now fail without running a single check, and in that case does not
  print its `verify: <n> profiles, ...` tally. Anything parsing that line must tolerate
  its absence.
- `status` and `verify` each perform an `upgrade --dry-run` per invocation. In link mode
  that is a symlink comparison; in copy mode it builds a staging tree in a temporary
  directory. Cheap at this repository's size and not free — if it ever becomes hot, the
  answer is a cheaper pending query, not removing the gate.
- An agent that adds a skill and runs `jig verify` is told so at the first check it runs,
  instead of discovering it when a later session cannot find the skill.
- `pending` enters the install vocabulary as a term distinct from drift.
