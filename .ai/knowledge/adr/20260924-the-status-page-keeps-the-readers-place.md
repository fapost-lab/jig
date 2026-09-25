---
id: adr-20260924-the-status-page-keeps-the-readers-place
type: adr
status: accepted
date: 2026-09-24
domains:
  - task
  - housekeeping
  - spec
paths:
  - scripts/lib/status.sh
  - scripts/lib/common.sh
supersedes: adr-20260922-the-status-page-stays-current-without-a-server
summary: Why the status page is reloaded by one static inline script that waits while the reader is busy, keeps their scroll position and open details in sessionStorage and offers a pause, with the meta refresh left in noscript — and why it still has no server.
reviewed_at: 2026-09-25
---
# The status page keeps the reader's place: one static inline script reloads it, waits while they read, remembers what they opened and offers a pause

## Context

adr-20260922-the-status-page-stays-current-without-a-server made the status page a page one keeps
open: writers redraw it synchronously, and `<meta http-equiv="refresh" content="10">` reloads it.
That tag was its one addition to "inert"; the page carried no script, and JavaScript was rejected
as a way to *poll*, because browsers refuse `fetch` of a `file://` page.

In use, the tag made the page hard to read (the maintainer, 2026-09-24). A meta refresh is a full
reload on a fixed clock: every ten seconds the scroll position goes (browsers restore it
unreliably, Safari hardly at all) and every `<details>` closes again — the paused tasks and the
full report are collapsed by design, so a reader who opened one lost it before finishing. Nothing
in the page can defer the reload while someone scrolls or selects text, and nothing can stop it.

Keeping a reader's place across a reload needs state that survives the reload and code that puts
it back. HTML without script has neither. Unlike polling, this needs no network and no access to
the file: `sessionStorage` works on `file://` in Chrome, survives `location.reload()`, and a
`<meta refresh>` inside `<noscript>` in `<head>` is ignored when scripting runs and honoured when
it does not (checked in headless Chrome on a real `file://` page, 2026-09-24).

## Decision

- **One static inline script reloads the page** instead of the meta tag. It is the only `<script>`
  on the page, has no attributes, loads nothing, and holds no value people wrote: the reload
  interval is the only value interpolated into it, and it writes to the page only through
  `textContent`. It reloads once 10 seconds have passed since the page loaded, except while the tab
  is hidden (it reloads as soon as the tab is visible again and the time is up), while text is
  selected, within 3 seconds of the reader's last scroll, wheel, key, click or touch, or while the
  reader has paused it.
- **The reader's place survives the reload.** Before reloading, and on `pagehide` for a reload the
  reader started, the script stores in `sessionStorage`, under a key made of the page's path: which
  `<details>` are open (by id — `paused`, `full-report`), the nearest `<section>` above the top of
  the window with the offset into it, and the absolute scroll position as a fallback. After the
  load it opens those `<details>` and scrolls to the same offset in the same section, so a card
  added above does not move the reader. `history.scrollRestoration` is `manual` so the browser
  does not fight it. No id on the page is used twice, since the script finds what it restores by
  id.
- **A pause.** A control fixed to the bottom-right corner says "Auto-refresh every 10 s · keeps
  your place · Pause"; paused, it says "Auto-refresh paused · Resume" in the warning colours, and
  Resume reloads at once. The pause is kept in the same `sessionStorage` entry, so neither a manual
  reload nor a redraw by jig lifts it; it ends with the tab. The control is rendered `hidden` and
  only the script shows it, so a page without script promises nothing it cannot do; the line at
  the top ("refreshes itself every 10 seconds … jig redraws it whenever a task changes") stays
  true either way.
- **Without script, the page behaves as before.** The meta refresh moves into `<noscript>` in
  `<head>`. Every storage access is guarded: where storage is unavailable, the script still
  reloads and still waits while the reader is busy, and only forgets their place between reloads.
- **Unchanged from adr-20260922-the-status-page-stays-current-without-a-server** — carried
  here in full, since this record replaces it:
  - *Order of the page.* "Needs you" first — a stopped autopilot run with its reason, a T3/T4
    design waiting at its gate or changed after approval, a finished task waiting for the reader's
    git step (by `agent.git`), a pull request to review or merge, a merged task to close, work
    flagged `wrong-base`, `abandoned?` or `worktree-kept`, knowledge to decide — each card with one
    line saying what to do, or an explicit "Nothing needs you right now". Then "Running now"
    (autopilot stage, how long, repairs), spec progress by phase, and details with the whole text
    report last.
  - *The commands that change what it shows redraw it, synchronously.* Task writers (state, the
    autopilot journal, the findings ledger, the receipt) mark the command dirty
    (`jig_status_page_dirty`); `cmd_task` redraws once at its end, and `jig_die` and the third
    repair's `return 3` redraw on their way out. `spec new|done|remove|close|epic` and every
    non-dry housekeeping run redraw too. The redraw is a process — `jig status --refresh` run by
    the clone's own `.ai/scripts/jig` (`jig_status_page_touch`, `lib/common.sh`) — because no
    command library may source `status.sh`. It returns 0 and prints nothing whatever happens.
  - *The redraw reuses the slow counts.* A full `jig status` (only once the page exists, and only
    in the main checkout), `--html`, `--open` and a housekeeping run write the three slow counts
    with their UTC time to `.ai/runtime/status-counts`; `--refresh` reads them and the page says
    how old they are. With no cache yet, `--refresh` counts once and writes it.
  - *Live only after the page was first written:* nothing redraws a page that does not exist, so
    a project where nobody ran `--html` or `--open` gets no file and no extra process.
  - *One page per clone, in the main checkout:* every mode run in a task worktree is handed to the
    main checkout's jig (`jig_config_clone_root`), so the one open tab shows every task.
  - *`jig status --open`* opens it with what the system has (`open`, `cmd /c start` with a
    `cygpath -w` path, `explorer.exe` in WSL, `xdg-open`), or prints its path and exits 0.
  - *Data comes only from what peers answer or already stored,* never recomputed and never
    fetched on the write path; `gate`/`gate_design` are written by `jig task gate <id> approved`
    and `pr_url` by `jig task ship`; the last housekeeping run's `--- run` marker carries
    `forge=github|gitlab|none|failed`.

    *Amended 2026-09-25.* "Already stored" is a snapshot, and a snapshot can be wrong by the
    time the page is drawn: a housekeeping flag kept telling the reader to close a task they
    had closed, and would have kept a worktree card past a worktree they had deleted. What is
    ruled out above is a network request on the write path, not a peer asked again — so the
    page now asks the free ones. `_status_flagged_ids` drops a flag before a card is built
    from it when a free local read answers what that card asks for: the task's own `status`
    for `needs-consolidation` (closed) and `abandoned?` (abandoned), and whether the kept
    worktree is still on disk for `worktree-kept`. Those three, and no others. The counts in
    both reports go through the same function, so they cannot disagree with the cards.

    The test is whether the card's *ask* has been answered, and answered where the page can
    see it for free. `wrong-base` fails the second half — only the forge and the history know
    where work landed. The pull-request cards fail the first: closing a task does not merge
    its pull request, so "review and merge it" still stands for a `consolidated` task. Both
    stay borrowed, past tense, "as of" their run. And a recheck may only contradict, never
    invent: an id with no state file, a kept worktree with no path in the log, an id
    `jig_valid_id` refuses — the page keeps repeating what the run said rather than asking a
    peer that would `jig_die` inside a report.

    One card is corrected rather than dropped, which is the third thing a free local answer
    is good for. `task abandon` does not touch the forge, so a task the person gave up on
    keeps its pull request open, and the page asked them to review and merge work nobody
    wants. Neither test above applies: the flag is not disproved, and nothing was done that
    the card can stop asking for. What the local `status` settles is the imperative — so the
    card keeps the borrowed fact and the "as of" mark, and asks for the pull request to be
    closed or the task reopened. `abandoned` only.
  - One file with one fixed name written atomically, every value escaped by `_status_h`, a link
    only for an `https://` address, no external asset of any kind, an uninitialised project
    refused by `--html`/`--open` (and silently skipped by `--refresh`), and plain `jig status`
    output byte-for-byte as before.

## Alternatives

- **Stay script-free and stop collapsing** — render the paused tasks as a plain section. It keeps
  one block open but still loses the scroll position every ten seconds, and the full report is too
  long to leave open.
- **Stay script-free with a `#fragment`** — a meta refresh keeps the fragment, but it points at a
  section, not the line the reader was on, and opens no `<details>`.
- **Poll the file and patch the page instead of reloading** — `fetch` of `file://` is refused, and
  Chrome treats every file as its own origin, so an iframe of it cannot be read either. It needs a
  server (ADR-0002; the specification's non-goal "no server"). Rejected as before.
- **A local server or a JavaScript framework** — a process, a port and a dependency for a problem
  forty lines solve.
- **`localStorage`** — the pause would outlive the tab, and tomorrow's page would silently show
  yesterday's data; in Chrome every `file://` page also shares one store.
- **No pause, only "wait while busy"** — a reader studying a table without touching it is still
  interrupted; the pause is theirs to take and visibly marked while it holds.

Rejected by adr-20260922-the-status-page-stays-current-without-a-server, and still rejected:

- **A detached background redraw with a lock and a pending file** — hides the cost but adds a
  process nobody waits for, a lock to break when it is abandoned, and output that races the
  command. Synchronous is fast enough once the slow counts are cached.
- **A file watcher** (`fswatch`, `inotifywait`) — a running process and a dependency that differs
  per system (ADR-0002).
- **Redrawing only from the session hook** — a run happens inside one session, exactly when
  someone watches.
- **A hook after the command in the dispatcher** — `set -e` ends the process at `return 3` and at
  `jig_die` before it; wrapping the call to catch the code disables `errexit` inside every command.
- **A call in every public command** instead of the writers — fifteen places, and a new writer is
  easily forgotten.
- **Always writing the page** — a file in every project whether or not anyone looks, and a redraw
  in every test of every command.
- **A page per worktree** — a worktree saw one task then, and the page belongs to the checkout
  that owns the workspaces either way (ADR-0029 as amended).
- **Inferring "design waiting" from class + design.md + no receipt** — false during the whole
  implementation after approval; a "needs you" that lies is worse than none.
- **Asking the forge for review or CI state during a redraw** — network on the write path.

## Consequences

- The page is no longer inert. The script is reviewed like code: static, no network, no value
  people wrote, `textContent` only. `tests/status.t.sh` asserts one attribute-less `<script>`,
  no `fetch(`, `XMLHttpRequest` or `innerHTML`, the meta refresh only inside `<noscript>`, the
  control rendered `hidden`, and unique ids.
- The script's behaviour is not covered by `tests/`: exercising it needs a browser, which would be
  a dependency (ADR-0002). It was checked in headless Chrome over the DevTools protocol; a change
  to the script should be checked the same way.
- Safari was not checked. Where its `file://` storage fails, the page still reloads and waits
  while the reader is busy, and only forgets their place.
- A new collapsible block that a reader should keep open needs an id of its own; a block without
  one closes on every reload, as every block did before.
- A reader who pauses sees data as old as the "updated" time at the top until they resume.
- The costs of adr-20260922-the-status-page-stays-current-without-a-server stand unchanged:
  - Every task command with a page open costs one redraw at its end — measured on the maintainer's
    Mac at about 0.55 s with one live task and 0.75 s with ten (about a hundred short-lived
    processes, which is why `status.sh` reads all `state` files in one awk pass) — and nothing
    without one.
  - The knowledge counts on a redrawn page are as old as the last full run, and it says so; the
    pull-request data is as old as the last housekeeping run, and it says so, marked stale past
    `housekeeping.cadence` or when the forge failed.
  - A new writer in `task.sh` must call `jig_status_page_dirty`, and a new early exit after a write
    must flush, or the page lags until the next command.
  - The page's strings are asserted by `tests/status.t.sh`; renaming a peer's answer changes both
    reports. `.ai/runtime/status-counts` joins the page as the only files a reporting command
    writes.
  - The page is redrawn with the main checkout's own jig, so a worktree running a newer jig does
    not change how the page looks until the main checkout is upgraded.
