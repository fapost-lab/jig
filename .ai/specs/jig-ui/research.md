# Research — prior art for Jig UI

Read on 2026-10-14 from the public repositories. Facts only; "not found" means the reader did
not find it, not that it does not exist. aif-handoff's web package was not read, so its
drag-and-drop is unverified.

## aif-handoff (lee-to/aif-handoff) — the closest existing board

- Kanban over agent stages: backlog, planning, plan_ready, implementing, review, done,
  verified, blocked_external (optional improve, verify). Columns are the agent's state.
- Stack: Hono API with WebSocket, React + Vite, SQLite. Three long-running processes, Docker
  for remote.
- **The database is the source of truth** (status, position, flags). Plans are duplicated
  into the database. Not mergeable or reviewable in git.
- Priority (0–5) and `position` are separate fields. New tasks get `max(position)+100`,
  reordering sets one number. `paused` is a flag; `blockedReason`, `scheduledAt`,
  `manualReviewRequired` are fields.
- A table of legal human actions per status lives in shared code.
- `projects/overview` returns compact per-project counts; list rows are light, detail is a
  separate call.
- Roadmap import is idempotent by alias (`rm:<alias>`, `phase:N`, `seq:NN`) but done by an LLM.
- No epics. No cloud product; remote is Docker plus a reverse proxy, with opt-in accounts.
- It runs the agents itself; its README warns this may breach subscription terms.

## ai-workspace (lee-to/ai-workspace)

- No UI and no task model: a CLI and MCP server sharing context across projects (Rust).
- Registry: a user-global SQLite database; an optional committed `.ai-workspace.json`
  manifest rebuilds it.
- Concurrency: a content hash on read, no overwrite on write by default.
- Cloud: one-way manual snapshot with a revision number; a stale base returns 409.

## HLV (lee-to/hlv)

- A spec-driven harness; the board idea is absent (no priority, order or epics).
- A terminal dashboard; a web example app talks to the framework over MCP with no database of
  its own — the browser is a cache and changes go through the framework's commands.
- Global registry `~/.hlv/workspace.yaml` (`id`, `root`). Workspace card per project.
- Its watcher follows only three files, so edits elsewhere need a manual "Sync".
- Open CORS, no authentication; three processes to run.

## ai-factory (lee-to/ai-factory)

- No UI, registry, `--json` listing or priority model of its own. A contract test pins one JSON
  block (`aif-gate-result`).

## What this means for Jig UI

Borrow:

- Priority and position as separate fields; sparse position (step 100) so a move writes one
  number (aif-handoff).
- Legal human actions per state exposed by Core, not duplicated in the UI (aif-handoff).
- A registry of project paths outside the repositories, rebuilt from the repositories
  (ai-workspace, HLV).
- A stale-write guard — a hash or revision sent with every write, a refusal when it changed
  (ai-workspace).
- Cloud as a one-way read snapshot first (ai-workspace).
- A contract test for each JSON shape Core exposes (ai-factory).
- Light list rows, heavy detail on demand; compact per-project overview (aif-handoff, HLV).

Avoid:

- A database holding state that exists nowhere else (aif-handoff).
- The UI running agents (aif-handoff).
- A watcher that covers only some files (HLV); open CORS without authentication (HLV).
- LLM-based roadmap import; Jig reads roadmaps deterministically.
- Several processes and native dependencies — Jig's audience includes non-developers on Windows.

Nobody covers epics, priority across projects, or ordering that agents can read from files.
That part Jig designs itself.
