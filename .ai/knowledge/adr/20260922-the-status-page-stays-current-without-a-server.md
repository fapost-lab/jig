---
id: adr-20260922-the-status-page-stays-current-without-a-server
type: adr
status: accepted
date: 2026-09-22
domains:
  - task
  - housekeeping
  - spec
paths:
  - scripts/lib/status.sh
  - scripts/lib/common.sh
supersedes: adr-20260921-the-status-page-is-the-one-file-a-report-writes
summary: Why the status page leads with what needs the reader, reloads itself every 10 s, and is redrawn synchronously by the commands that change it from cached slow counts — no server, no background process.
reviewed_at: 2026-09-22
---
# The status page answers "what needs me" and stays current without a server: writers redraw it synchronously from cached counts, and it reloads itself

## Context

adr-20260921-the-status-page-is-the-one-file-a-report-writes gave `jig status --html` one
self-contained page, written only on request and described as a snapshot. In use it was not worth
opening: a dead picture one had to regenerate and reopen by hand, and `jig status` as a table that
answered neither "what needs me" nor "what is happening" (the maintainer, 2026-09-22). The autopilot
specification (Phase 5) asks for a page a non-developer keeps open while agents work — with no server
and no new dependency (ADR-0002).

Two facts shaped the answer. A full `jig status` costs three to four seconds, almost all of it in
three counts — knowledge awaiting a decision (`km_proposed_count`), linked sources changed
(`km_changed_sources_count`) and pending upgrades (`upgrade_pending`) — while an autopilot run makes
dozens of task commands. And a task command can end in many ways (`return 3` from the third repair,
`exit 3` from `task ship`, `jig_die`) that a hook after the command in the dispatcher would miss
under `set -e`.

## Decision

- **Order of the page.** "Needs you" first — a stopped autopilot run with its reason, a T3/T4 design
  waiting at its gate or changed after approval, a finished task waiting for the reader's git step
  (by `agent.git`), a pull request to review or merge, a merged task to close, work flagged
  `wrong-base`, `abandoned?` or `worktree-kept`, knowledge to decide — each card with one line saying
  what to do, or an explicit "Nothing needs you right now". Then "Running now" (autopilot stage, how
  long, repairs), spec progress by phase, and details with the whole text report last.
- **It reloads itself** with `<meta http-equiv="refresh" content="10">`. Still no script and no
  external asset; this tag is the one addition to "inert".
- **The commands that change what it shows redraw it, synchronously.** Task writers (state, the
  autopilot journal, the findings ledger, the receipt) mark the command dirty
  (`jig_status_page_dirty`); `cmd_task` redraws once at its end, and `jig_die` and the third repair's
  `return 3` redraw on their way out. `spec new|done|remove|close|epic` and every non-dry
  housekeeping run redraw too. The redraw is a process — `jig status --refresh` run by the clone's
  own `.ai/scripts/jig` (`jig_status_page_touch`, `lib/common.sh`) — because no command library may
  source `status.sh`. It returns 0 and prints nothing whatever happens: a failed redraw never changes
  the output or the exit code of the command that triggered it.
- **The redraw reuses the slow counts.** A full `jig status` (only once the page exists, and only in
  the main checkout), `--html`, `--open` and a housekeeping run (which redraws in full) write the
  three counts with their UTC time to `.ai/runtime/status-counts`; `--refresh` reads them and the page
  says how old they are. With no cache yet, `--refresh` counts once and writes it.
- **Live only after the page was first written.** Nothing redraws a page that does not exist: a
  project where nobody ran `--html` or `--open` gets no file and no extra process.
- **One page per clone, in the main checkout.** Every mode run in a task worktree is handed to the
  main checkout's jig (`jig_config_clone_root`), so the one open tab shows every task.
- **`jig status --open`** writes the page and opens it with what the system has: `open` (macOS),
  `cmd /c start` with a `cygpath -w` path from Git Bash (ADR-0037), `explorer.exe` in WSL, `xdg-open`
  elsewhere. Without one, the page is written and its path printed; exit 0.
- **Data comes only from what peers answer or already stored**, never recomputed and never fetched on
  the write path: unformatted producers where a peer printed only text (`_task_autopilot_facts` in
  `task.sh`, `spec_phase_rows` and `spec_phase_counts` in `spec.sh`), `_task_gate_state` for the gate,
  and the last housekeeping run for pull requests and flags, whose `--- run` marker now carries
  `forge=github|gitlab|none|failed` so the page can say when that data is stale. Two facts are new in
  task state, each written by the command that knows it: `gate`/`gate_design` by
  `jig task gate <id> approved`, and `pr_url` by `jig task ship`.
- **Unchanged from the superseded decision:** one file with one fixed name written atomically, every
  value escaped by `_status_h`, a link only for an `https://` address, an uninitialised project
  refused by `--html`/`--open` (and silently skipped by `--refresh`), and plain `jig status` output
  byte-for-byte as before.

## Alternatives

- **A detached background redraw with a lock and a pending file** (the design before the gate) —
  hides the cost but adds a process nobody waits for, a lock to break when it is abandoned, and
  output that races the command. Rejected at the gate once the counts could be cached: synchronous is
  fast enough.
- **A local server** or **a file watcher** (`fswatch`, `inotifywait`) — a running process and a
  dependency that differs per system (ADR-0002; the specification's non-goal "no server").
- **Redrawing only from the session hook** — a run happens inside one session, exactly when someone
  watches.
- **A hook after the command in the dispatcher** — `set -e` ends the process at `return 3` and at
  `jig_die` before it; wrapping the call to catch the code disables `errexit` inside every command.
- **A call in every public command** instead of the writers — fifteen places, and a new writer is
  easily forgotten.
- **JavaScript polling** — browsers refuse `fetch` of a `file://` page, and the page would no longer
  be script-free.
- **Always writing the page** — a file in every project whether or not anyone looks, and a redraw in
  every test of every command.
- **A page per worktree** — a worktree sees one task.
- **Inferring "design waiting" from class + design.md + no receipt** — false during the whole
  implementation after approval; a "needs you" that lies is worse than none.
- **Asking the forge for review or CI state during a redraw** — network on the write path.

## Consequences

- Every task command with a page open costs one redraw at its end — measured on the maintainer's Mac
  at about 0.55 s with one live task and 0.75 s with ten (about a hundred short-lived processes;
  every process per task per value multiplies it, which is why `status.sh` reads all `state` files in
  one awk pass) — and nothing without one.
- The knowledge counts on a redrawn page are as old as the last full run, and it says so; the
  pull-request data is as old as the last housekeeping run, and it says so, marked stale past
  `housekeeping.cadence` or when the forge failed.
- A new writer in `task.sh` must call `jig_status_page_dirty`, and a new early exit after a write must
  flush, or the page lags until the next command.
- The page's strings are asserted by `tests/status.t.sh`; renaming a peer's answer changes both
  reports. `.ai/runtime/status-counts` joins the page as the only files a reporting command writes.
- The page is redrawn with the main checkout's own jig, so a worktree running a newer jig does not
  change how the page looks until the main checkout is upgraded.
