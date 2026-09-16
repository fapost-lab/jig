---
id: adr-0038-per-clone-settings-live-in-a-local-layer
type: adr
status: accepted
date: 2026-09-16
domains:
  - config
  - install
  - housekeeping
paths:
  - scripts/lib/config.sh
  - scripts/jig-session-hook
  - schemas/config.md
  - templates/gitignore
  - templates/config.yaml
summary: Why a contributor's own settings go in a gitignored config.local.yaml that answers only for whitelisted keys, one file per clone, and warns rather than refuses when it is not ignored.
reviewed_at: 2026-09-16
---
# ADR-0038: Per-clone settings live in a gitignored local layer that answers only for whitelisted keys

## Context

`.ai/config.yaml` is committed and project-owned, and `cfg` read nothing else. Some of its keys
fail ADR-0023's ownership test — is the answer the same for every contributor? The
`housekeeping.*` keys govern `.ai/workspace/` and `.ai/runtime/`, which are gitignored and never
leave the machine, and `git.worktree_root` is a place on one person's disk. On 2026-09-16
shortening the retention of abandoned tasks for one developer meant editing the committed file,
where the change would have landed in an unrelated branch's diff and changed the policy for
everyone.

ADR-0023 had already weighed a gitignored `.ai/config.local.yaml` for language settings and
rejected it only because no script could act on a language value — "worth revisiting if a
per-user setting appears that a script can actually act on". Housekeeping TTLs are that setting.
ADR-0023 also named the trap: `.gitignore` is created once from `templates/gitignore` and then
belongs to the project, and `upgrade` never touches it, so a new ignored path does not reach a
project installed earlier.

Discovery found two more facts. A task worktree receives nothing from the checkout it was added
from except its workspace link (ADR-0029), so a gitignored file would silently stop applying
there — and most work in this repository happens in worktrees. And `cfg` runs inside a command
substitution for every key, so nothing it computes survives to the next call; the session hook
promises no git on its idle path.

## Decision

- **`.ai/config.local.yaml`** — same flat format as `.ai/config.yaml`, gitignored, created by
  nobody but the person who wants it. Neither `init` nor `upgrade` creates or touches it. It is
  neither framework-owned nor project-owned: it belongs to the owner of the clone.
- **Layers in `cfg`: local, then project, then the built-in default.** An empty value falls
  through to the next layer. `cfg_list` and `cfg_bool` sit on `cfg` and inherit it. Both files
  are parsed by one function, `_cfg_read`.
- **The local layer answers only for `JIG_CFG_LOCAL_KEYS`**: `housekeeping.cadence`,
  `housekeeping.fetch`, `housekeeping.trash_ttl`, `housekeeping.abandoned_ttl`,
  `housekeeping.stale_after`, `git.worktree_root`. A key joins the list only by passing the
  ADR-0023 test. A value for any other key — `git.base_branch`, `profiles`, `forge`, or a
  misspelt name — is ignored, not an error: failing every command over a file that cannot harm
  the repository punishes the wrong thing. It is not silent either: `jig status` names it.
- **One file per clone.** The file is read from the clone's main checkout. In a worktree, whose
  `.git` is a file, the main checkout is found through git's own files — the `gitdir:` line, then
  `commondir` in that directory — without starting git. A submodule (no `commondir`), a bare
  repository or a separate git dir (common dir not named `.git`) answers the project itself. A
  `.ai/config.local.yaml` inside a worktree is not read.
- **Not being ignored by git is a warning, not a veto.** The file applies either way. `jig status`
  prints `config.local: .ai/config.local.yaml is not ignored by git and can be committed (fix:
  jig init)`, and `jig doctor` warns with the same fix. `cfg` never runs `git check-ignore`; only
  these two reporting commands do, through `jig_config_local_ignored`. `templates/gitignore`
  carries the line, and `jig init` appends missing template lines to an existing `.gitignore`.
- **`jig status` reports the layer** after `initialised: yes`: a `config.local: <key>=<value>` line
  for each key that applies, `config.local: ignored <key> (not a local key)` for each that does
  not, and a line for a local file inside a worktree. Nothing when no local file exists. The
  answers come from `config.sh`, so the report cannot disagree with `cfg`.
- **The session hook sources `lib/config.sh`** and reads `cfg housekeeping.cadence 1d`, instead of
  its own `sed`. It still starts no git and no network when nothing is due.
- **A second named exception to ADR-0008's "no cross-worktree lookup"**: a worktree reads the
  main checkout's `.ai/config.local.yaml`. Read-only, a setting of the clone rather than task
  data, and never written or owned through that path.

## Alternatives

- **Local git config (`git config jig.housekeeping.abandoned-ttl 7d`).** Cannot be committed at
  all, shared by every worktree without code, needs no `.gitignore` line, works on Windows.
  Rejected: git forbids `_` in a variable name (`invalid key: jig.housekeeping.abandoned_ttl`), so
  keys would be spelt differently from `.ai/config.yaml`; the settings are invisible beside the
  project; and the session hook would have to start git on its idle path.
- **A file under `.ai/runtime/`.** Already ignored in every project since its first `init`, so the
  `.gitignore` trap disappears. Rejected: `runtime/` is machine state housekeeping maintains
  itself — a log, a stamp, the trash — and a person's settings there are hard to find and easy to
  confuse with it.
- **Refuse to apply a local file git does not ignore.** The design first shown at the gate: safe
  by construction in an old project, at the cost of a `git check-ignore` in every command. Changed
  at the gate to a warning: the maintainer preferred the file to work, and the warning in `status`
  and `doctor` to say what to fix.
- **Allow every key locally, with a warning.** Rejected: a contributor whose `git.base_branch` or
  `profiles` differ gets a different ancestry answer and a different set of checks than CI — what
  a project configuration exists to prevent.
- **An error for a key outside the list.** Rejected, see Decision.
- **Link or copy the file into a worktree at `task start --worktree`.** Rejected: a file created
  after the start would not arrive, a copy diverges, and Windows junctions link directories only
  (ADR-0037).
- **A global `~/.config/jig/config.yaml`.** Out of scope, not rejected. It would be a third layer
  between local and project, with the same key list.

## Consequences

- A contributor can change retention, fetch and the worktree location for their own clone without
  a diff, and `jig status` shows what they changed.
- A project installed before this decision does not ignore the file until someone runs `jig init`
  or adds the line; until then the file can be committed, and `status` and `doctor` say so on
  every run. This is the accepted cost of the warning rule.
- `schemas/config.md` marks which keys are local. Adding a key to `JIG_CFG_LOCAL_KEYS` is a
  decision about ADR-0023's test and is recorded in that table.
- `cfg` reads up to two files per key and, in a worktree, `.git` and `commondir` as well — never
  git. A relative `git.worktree_root` is still resolved against the checkout a command
  runs in (ADR-0029), whichever layer supplied it.
- Validation is unchanged and shared: a bad duration in either file fails housekeeping before it
  acts. `cfg_bool` still reads any unrecognised value as false, in both layers.
