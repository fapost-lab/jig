---
id: adr-20261029-the-manifest-names-the-global-framework-not-its-path
type: adr
status: accepted
date: 2026-10-29
domains:
  - install
paths:
  - scripts/lib/manifest.sh
  - scripts/lib/upgrade.sh
  - scripts/lib/common.sh
  - scripts/lib/self-update.sh
summary: Why jig.source records 'global' for the machine's Jig instead of an install path, and the order a plain jig upgrade looks for its source.
---
# The manifest records the global framework as `global`, not as one person's path

## Context

`.ai/manifest` is committed. Its `jig.source` header said where the project's framework came from
as an absolute path — in practice the path of whoever ran the last `jig upgrade`, because the
project's copy hands the run to the global framework and the global framework is where every
installed project's files come from. On 2026-10-29 the jig-ui repository carried
`jig.source: /Users/juve/.local/share/jig`. On every other developer's machine that path does not
exist, and the project's own `.ai/scripts/jig upgrade` refused with `cannot determine the framework
source root; pass --from <dir>` — while `jig status` in the same project had just found the
developer's global jig and said the project was older than it. The common shell wrapper runs the
project's copy first, and Jig UI's Upgrade button does too, so neither could upgrade.

The cause was in the source lookup: `--from`, then the checkout the script runs from (empty in an
installed copy), then the recorded path. The global framework — the Jig `status` compares with and
`self-update` moves — was never asked.

Only `.` was ever kept machine-independent: a framework repository installed from itself.

## Decision

- **`jig.source` takes one of three values.** `.` when the source is the project itself, as
  before. `global` when the source is the global framework: physically the checkout behind the
  `jig` that `PATH` selects (`jig_global_source`, the root behind `jig_global_executable`). An
  absolute path only for any other checkout — a clone run without `install.sh`, a `--from` onto a
  checkout that is not on `PATH`. The project is asked first, so a framework checkout that is both
  its own source and the global jig keeps `.`. `manifest_write_entries` decides, so `init` and
  `upgrade`, copy and link mode, all write the same way.
- **`global` is read as the reader's own global framework.** `manifest_source` resolves it with
  `jig_global_source`, and prints nothing (failing) on a machine without one. A recorded path is
  printed as recorded; whoever is about to read from it checks that it is a checkout here.
- **A plain `jig upgrade` looks in a fixed order** (`upgrade_source`): the checkout the running jig
  belongs to; then the recorded source, if it is a framework checkout on this machine; then the
  global framework — but the global framework only when it is not older than the version the
  install records, whichever step reached it: a recorded `global` is the same checkout, and on a
  colleague's machine with an older global jig it is an older source. Nothing found is the old refusal, now naming where it looked and never the
  recorded path, which on this machine means nothing; when an older global jig was passed over,
  it says so and names `jig self-update`.
- **This narrows ADR-0017's "unknown".** Pending is computed by the same lookup
  (`upgrade --dry-run`), so a copy-mode install whose recorded source is not on this machine —
  ADR-0017's own example — is now measured against the global framework when one is there and
  not older, and `verify` refuses across what it finds. It stays unknown, and `verify` runs, when
  there is no global jig or it is older than the install: an older global would only offer a
  downgrade, and ADR-0017's rule that an absent source never becomes a failure still holds for
  it.
- **`status`, `self-update` and `upgrade` share one answer to "the Jig on this machine"**:
  `jig_global_executable`, through `jig_global_source` where a checkout is needed.
- **A foreign path is replaced, not edited out by hand.** ADR-20260922 stands: an upgrade rewrites
  the header only when it applied something or the source is the recorded one. So the first
  upgrade that places a file from the global framework records `global`; on the machine whose path
  it was, where that path is the global framework, even an upgrade that placed nothing does. An
  upgrade that placed nothing elsewhere leaves the header alone, and the path stays harmless until
  then — every reader treats it as absent.

## Alternatives

- **Ask the global framework before the recorded source**, as the task was first written. For a
  manifest written after this change the two orders agree, because `global` is the global
  framework. They differ only where a person deliberately installed from another checkout that is
  still on their machine: that project would silently switch to the global jig. Asking the
  recorded checkout first changes behaviour only where the old lookup failed.
- **A path relative to `$HOME`** (`~/.local/share/jig`). Still one person's layout: it breaks for
  anyone who installed elsewhere, and a Windows home is not shaped like a macOS one.
- **The path in `.ai/config.local.yaml`.** A per-clone file is the right home for a per-machine
  fact, but it is a setting somebody has to fill or Jig has to write into a person's own file, and
  it buys nothing over asking `PATH`, which is where the answer already lives.
- **No `jig.source` at all.** Loses `.` and the one way back for a machine with no global jig, and
  an older jig reading an empty value is a worse failure than reading an unknown word.
- **Always `global`, whatever the source.** On a machine without a global jig — a clone used
  directly — the next upgrade would lose the only checkout it had, a regression for that person to
  spare a path that no longer breaks anyone else.

## Consequences

- An installed project upgrades from its own copy on any machine with a global jig, whatever the
  committed manifest says, and the manifest stops carrying usernames.
- `jig status`, `jig verify` and `jig doctor` measure pending items with the same lookup, so where
  the recorded path is not on the machine they now compare the install with the global framework
  instead of reporting "unknown". A developer whose global jig is newer than the project is told
  to upgrade by `verify` (ADR-0017), as the developer whose path was recorded already was. Without
  a global jig, or with an older one, nothing changes: pending stays unknown.
- An older jig reading `jig.source: global` sees a relative path that is not there: the same
  refusal it gave for a foreign path, and `jig upgrade` with the global jig is the way out, as it
  was. A project whose copy predates this change needs that once.
- A test that wants "no source anywhere" must keep the maintainer's real global jig off `PATH`
  (`path_without_jig`, `jig_installed_without_global` in `tests/lib/assert.sh`); CI has none, so
  only a laptop would catch the difference.
- The word `global` is reserved in `jig.source`. A relative path is never written there, so the
  word cannot collide with a recorded directory.
