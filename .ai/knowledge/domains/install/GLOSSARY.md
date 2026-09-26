---
id: glossary-install
type: glossary
status: active
summary: "Terms for installation: framework-owned, copy and link mode, manifest, drift, pending, keep-modified."
domains:
  - install
topics: []
load: domain
paths:
  - scripts/lib/init.sh
  - scripts/lib/upgrade.sh
  - scripts/lib/manifest.sh
  - "adapters/**"
  - install.sh
  - scripts/lib/self-update.sh
  - .github/scripts/release-tag.sh
  - scripts/lib/section.sh
reviewed_at: 2026-09-26
---
# Install glossary

## Framework-owned

A path the framework installs and `upgrade` may replace. The complement is
project-owned: created once and never overwritten, however far it has drifted from the
template. The split is the whole safety story of `upgrade` (ADR-0003). It is per path with
one exception, the Marked section below, which is framework-owned text inside a
project-owned file.

## Copy mode / link mode

The two install modes recorded as `jig.mode` in `.ai/manifest`. **Copy**: files are copied
into the project and hashed, so drift is detectable per path. **Link**: framework paths
are relative symlinks into the source checkout, `jig.source` is `.`, and the manifest has
no hash lines — used when developing the framework against itself.

## Marked section

The region of a project's `AGENTS.md` between `<!-- jig:begin -->` and `<!-- jig:end -->`:
framework-owned text inside a project-owned file, and the only such region there is.
`jig upgrade` replaces it while it still hashes to the manifest's `instructions.section`
record, and keeps it otherwise. `jig init` is the only command that starts tracking one,
and only when the region is byte for byte what jig itself would write — upgrade never
adopts, and a record `init` already holds is carried forward, never re-derived, so a
re-run cannot re-baseline a section a human edited. Parsed by `scripts/lib/section.sh`
(adr-20260924-jig-owns-a-marked-section-of-the-instructions).
Informal synonyms: the Jig section, the managed block.

## Manifest

`.ai/manifest`: a header (`jig.version`, `jig.source`, `jig.mode`, `installed_at`,
`adapters`, and `instructions.section` once a marked section is tracked) and, in copy
mode, one hash line per installed path. Maintained by `init` and
`upgrade`, never edited by hand. `init` chooses `jig.source`; `upgrade` writes it only for a
source it actually installed from (adr-20260922-upgrade-records-the-source-it-installed-from).

## Drift

A framework-owned path whose current hash differs from the manifest (**modified**) or that
is gone (**missing**). Reported by `jig status`. Drift is about paths the manifest already
knows; it says nothing about source files that were never installed.

## Pending

A framework-owned item the source provides now and the project does not have yet — a new
skill, a newly activated profile. `jig upgrade --dry-run` lists it as `install` or `link`.
Distinct from drift: pending is "not installed yet", drift is "installed and changed".

## Keep-modified

The upgrade outcome for a file the user edited: the new version is not written, the
project's copy stays. It is the reason `upgrade` is safe to run and the reason an
installed `verify.sh` may be older than the framework that calls it. A file the user did
not edit but an earlier run already placed is not this — it is **already-placed**, and
telling the two apart is what makes an interrupted upgrade repeatable
(adr-20260926-an-interrupted-upgrade-is-repeated-not-rolled-back).

## Already-placed

The upgrade outcome for a file that already holds exactly the bytes the run would install,
whoever placed it: the manifest records the staged hash and nothing is written. Counted in
`kept`, like every other outcome that writes no file, and reported only when the manifest
did not already agree — which is exactly when the run reconciled something. It is not
pending: the file is current.

The content is the predicate, not a record of progress, because a record can be lost, go
stale or arrive from somebody else's clone. That is what makes repeating `jig upgrade` the
way to finish an interrupted one, and why nothing is rolled back
(adr-20260926-an-interrupted-upgrade-is-repeated-not-rolled-back).

## Hash space

The pair of decisions `git hash-object` takes from wherever it runs — the repository's
object format (SHA-1 or SHA-256 names) and its clean filters — which together decide
whether identical bytes hash equal. `upgrade` compares a project against a staging tree in
`$TMPDIR`, so both sides are computed the same way or the comparison is meaningless:
`jig_hash` and `jig_hash_list` pass `--no-filters` and the project's own git directory
(`jig_hash_git_dir`), whatever directory the files live in. `--no-filters` answers the
filters and not the object format, so both halves are needed
(adr-20260926-an-interrupted-upgrade-is-repeated-not-rolled-back).

## Global framework

The framework checkout behind the `jig` that `PATH` selects: `~/.local/share/jig` when
installed by `install.sh`, a developer's own clone otherwise. `jig self-update` moves it; a
project's installed copy is unaffected until `upgrade` (ADR-0033).

## Release tag

An annotated tag `v<major>.<minor>.<patch>`, digits only, on a commit whose `JIG_VERSION` is
the same version. Anything else — a pre-release suffix, a stray tag — is not a release. Only the
CI `release` job creates one, always without leading zeros (ADR-0034).

## Update channel

What a global framework follows. Release tags are the default channel; `main` is the
development channel, installed only with `--ref main` (ADR-0033).
