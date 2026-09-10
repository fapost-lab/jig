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
---
# Install glossary

## Framework-owned

A path the framework installs and `upgrade` may replace. The complement is
project-owned: created once and never overwritten, however far it has drifted from the
template. The split is the whole safety story of `upgrade` (ADR-0003).

## Copy mode / link mode

The two install modes recorded as `jig.mode` in `.ai/manifest`. **Copy**: files are copied
into the project and hashed, so drift is detectable per path. **Link**: framework paths
are relative symlinks into the source checkout, `jig.source` is `.`, and the manifest has
no hash lines — used when developing the framework against itself.

## Manifest

`.ai/manifest`: a header (`jig.version`, `jig.source`, `jig.mode`, `installed_at`,
`adapters`) and, in copy mode, one hash line per installed path. Maintained by `init` and
`upgrade`, never edited by hand.

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
installed `verify.sh` may be older than the framework that calls it.
