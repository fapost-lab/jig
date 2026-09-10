---
id: adr-0024-framework-never-edits-runtime-config
type: adr
status: accepted
date: 2026-09-10
domains:
  - install
  - housekeeping
paths:
  - "adapters/**"
  - scripts/jig-session-hook
  - scripts/lib/init.sh
summary: Why jig offers the session hook as a snippet and never edits a project-owned runtime config file.
reviewed_at: 2026-09-10
---
# ADR-0024: The framework offers the session hook; it never edits a project-owned runtime config

## Context

Housekeeping needs a cheap trigger, and SPEC §25 specifies one: a `SessionStart` hook
that checks a timestamp and starts housekeeping only when it is due. For Claude Code that
hook lives in `.claude/settings.json`.

SPEC §33 proposed that the adapter merge one entry tagged `"_jig": true` into that file,
and that `upgrade` later locate and replace only that entry. The question was deferred
twice ("decide in Phase 1 with a real `settings.json` at hand"), and was still open when
Phase 5 implemented the rest of the lifecycle.

Two constraints decide it. `.claude/settings.json` is project-owned arbitrary JSON whose
shape the framework does not control — nested objects, arrays, any formatting the user
chose. And there is no JSON parser available: ADR-0002 admits `git` as the only mandatory
dependency, and permits a `sed` reader only for jig's *own* formats, which are restricted
to flat scalars precisely so that shell can read them. That guarantee does not extend to
someone else's settings file.

The manifest cannot describe the situation either. A manifest line is `<hash> <path>`:
whole-file ownership keyed by path, with an upgrade decision table of install / replace /
keep-modified / keep-conflict / keep-orphaned-modified / delete. There is no vocabulary
for "the framework owns four lines inside a file the project owns".

## Decision

- The hook's logic lives in `scripts/jig-session-hook`, an ordinary **framework-owned**
  script installed as `.ai/scripts/jig-session-hook`, manifested and upgraded like any
  other script.
- What goes into the project-owned config is **one line naming that command**. The
  adapter *prints* it; a human pastes it.

  > **Amendment (2026-09-10, task `session-hook-optin`).** The rule is *never edits*, not
  > *never writes*. Editing an existing config means understanding arbitrary JSON, which
  > is what this decision refused; **creating a file that does not exist parses nothing**,
  > so the reason does not reach that case. `jig init --session-hook` therefore writes
  > `.claude/settings.json` whole when it is absent, and still declines — exit 2, file
  > untouched — when anything is already at that path. It is opt-in, because the hook
  > starts a background process at every session start. The created file is project-owned
  > under the existing `_init_place_if_absent` rule (ADR-0003): absent from the manifest,
  > never overwritten, and never restored by `upgrade` once removed.
- Detection is a **read-only substring test** for the command string, which is safe on
  arbitrary JSON in a way that editing is not. `jig status` uses it to report
  `session hook (<runtime>): installed | not installed`.
- The adapter contract gains `adapter_<name>_session_hook_hint <project-root>`: prints
  the advice, prints nothing when the trigger is already in place, and **exits 2 when the
  runtime has no session hook at all**. Codex is that case, and says so rather than
  implying parity. A companion `adapter_<name>_install_session_hook <project-root>` does
  the create-if-absent install of the amendment above, declining with exit 2 in every
  case it cannot handle safely.
- `init` advises and never prompts, so it keeps working in CI and in an agent session
  (this also settles SPEC §32 step 8, which said init should "offer to configure"
  scheduling).

## Alternatives

- **Merge a tagged entry with shell text processing** (the §33 proposal). Rejected: a
  JSON editor in bash 3.2, correct against an arbitrary hand-formatted file, is not a
  small job, and every bug in it damages a file the user owns and the framework cannot
  rebuild. Unlike a purged workspace (ADR-0006) there is no trash to recover from.
- **Use `jq` when present, refuse when absent.** Rejected: makes the headline trigger
  conditional on an optional binary and splits behaviour between machines. It also does
  not solve the problem — a `jq` round-trip rewrites the whole file, discarding the key
  order and formatting the user chose.
- **Extend the manifest with a "merged entry" record type.** Rejected: a second ownership
  model, and a second upgrade decision table, to serve exactly one file.
- **Ship no hook at all, scheduler only.** Rejected: the in-session trigger is what makes
  "no manual discipline" (SPEC §3.8) true for people who never set up cron.

## Consequences

- Installation is automatic only on a project that has no runtime config yet, and only
  when asked: `jig init --session-hook`. Everywhere else enabling the trigger costs one
  paste, once. A user who deletes the entry stays deleted — `upgrade` cannot silently
  restore what someone removed on purpose, because `upgrade` never touches that file.
- The two runtimes are not symmetric. Lifecycle semantics are identical, the trigger is
  not: Codex users must use a scheduler (`.ai/templates/scheduler/`). Saying this plainly
  is part of the decision, because the alternative is Codex users assuming housekeeping
  runs when it never does.
- Exit 2 now means "not applicable to this runtime" for adapter capability functions.
  This resembles, but is not, a profile's verify skip code — see `ARCHITECTURE.md`.
- Any future integration with a project-owned config file inherits this rule: offer the
  snippet, own the script, detect by reading.
