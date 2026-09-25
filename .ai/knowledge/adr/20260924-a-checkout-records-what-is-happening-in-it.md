---
id: adr-20260924-a-checkout-records-what-is-happening-in-it
type: adr
status: accepted
date: 2026-09-24
domains:
  - task
paths:
  - scripts/lib/checkout.sh
  - scripts/jig
  - scripts/lib/status.sh
  - "adapters/**"
  - scripts/lib/config.sh
  - "skills/jig-task/**"
summary: Why every jig run records in the checkout that work is happening there, and why the record holds only what nothing can compute.
---
# ADR: A checkout records what is happening in it, so a session is no longer invisible

## Context

On 2026-09-24 a coordinating session was working in the main checkout of this repository:
a clean tree, no task of its own, reading registries and running agents in worktrees.
Another session filed a task and ran `jig task start`, exactly as `jig-task` prescribes.
The branch was checked out here, and the first session was no longer on `main` — and was
never told.

The harm is not that HEAD moved. That is the ordinary meaning of `task start`. The harm is
the word **silently**. `task start` refuses a checkout with uncommitted work and has
nothing to say about a checkout that is clean but occupied.

The difference between those two is not risk, it is observability. A dirty tree is a fact
git prints. A live session is not a fact at all: no file, no lock, no field in any state.
For `task start`, a coordinator reading registries on a clean `main` and an empty checkout
are the same checkout.

**Prose could not fix it.** `conventions/required-records.md` asks what makes a record
resist ritual: it is computed, or written by someone other than whom it binds, or
refutable by the machine. "Before `task start`, check whether the checkout is busy" has
none of the three, and for the worst reason — there is nothing to look at. An agent that
followed the instruction honestly would answer "free", and would be right on every datum
available to it. So the fact has to exist before anything can refer to it.

**git has the primitive and withholds it where it is needed.** Housekeeping already reads
a worktree lock as "a session may still be using it" (`scripts/lib/housekeeping.sh`). But
`git worktree lock .` answers `fatal: The main working tree cannot be locked or unlocked`
(git 2.48.1), and the main checkout is where the incident happened. ADR-0029's amendment
of 2026-09-22 keeps it that way: no automatic lock is taken at `task start --worktree`;
locks on session worktrees belong to the runtime.

**Parallel work is the normal state here, not an edge case.** Measured over this
repository's history: 63 of 109 task branches overlapped in life with another, and on
every one of the 12 days that had branch activity, two or more task branches received
commits. Since worktrees arrived on 11 September, 11 days out of 11.

## Decision

Every jig run says, in the checkout it runs in, that work is happening here. One writer
(the dispatcher), one format, two files, both under this checkout's own gitignored
`.ai/runtime/`:

- **`runtime/working/<name>` — one file per piece of work in progress here.** Its whole
  content is one line, `command: <the words of the jig command>`.
- **`runtime/checkout` — what this checkout last told a reader.** `command:`, and
  `branch_reported:`, the branch a reader was last told about. `command:` here is read by no
  command, and is kept anyway: it is what a person sees when they open the file to ask what
  last ran in this checkout, and the file is rewritten by every run regardless, so it costs
  nothing to be true. Wherever a session is named, `branch_reported` is not in this file at
  all — see below.

**Only the incomputable is stored.** This is the rule the record's shape comes from, and
it is the half of `conventions/required-records.md` that points inward: "derived rather
than filled in" is a requirement on a record's *content*, not only on whether it is
demanded. Which worktree the work is in, which branch it sits on, when it was last
touched, and which checkout the record is about are all facts git, the filesystem or the
record's own path answer better — `jig status` already prints `worktree=<path>
uncommitted=<n>` from `git worktree list` (ADR-0029). What nothing can answer afterwards
is which command ran, so that is the whole content. A stored `worktree` field would be a
kept copy of a computed fact, which is the thing the convention says to prefer the other
way round. Freshness is the file's **mtime**, not a field — the idiom
`.ai/runtime/last-housekeeping` already uses, read with `stat -f %m` and a fallback to
`stat -c %Y` (`scripts/jig-session-hook`).

**The name is derived, never composed**, in this order: the task named by the command's
arguments whose workspace exists **and whose branch is not checked out in another
worktree**; otherwise the live task whose branch is this checkout's HEAD; otherwise the
runtime's own session id; otherwise nothing is written. The exclusion in the first rule is
this decision meeting ADR-0029's own column: `jig status` prints `worktree=<path>` for a
task whose branch git says is elsewhere, so naming that task as work in progress here made
one page say both. Reading about work elsewhere is not doing it. The same test is applied
again when the records are read, because a record can become wrong after it was written —
and does, in the case that matters most: `jig task start <id> --worktree` runs in this
checkout, records the work before the tree exists, and leaves the branch somewhere else a
moment later. The name
becomes a path, so it passes `jig_valid_id` first, the same check `task_dir` makes for the
same RULES.md invariant. An anonymous run leaves no trace and can cause no refusal — that
is what keeps the refusal narrow. There is no race by construction: every writer has its
own file.

**Writes are `tmp` then `mv`**, as `_task_rewrite_state` writes state: a reader sees the
old record or the new one, never a torn one. Appending to a shared log was rejected on the
way here — `>>` is atomic only up to `PIPE_BUF` and guaranteed by nothing, and a torn line
would reach a reader exactly when it is deciding.

**Nothing in the recorder may fail a command or write to stdout.** Every path gives up
with `return 0`, and the one message it prints goes to stderr: `jig task current` prints
an id that callers read as a value (ADR-0012), and an advisory must not become part of it.

**The checkout tells a session when HEAD moved under it.** While `branch_reported`
disagrees with the actual HEAD, the commands a session orients itself with — `jig status`,
`jig task current`, `jig task list` — print one message and update the key. Only they
update it; `task start`, which moved HEAD, does not, or it would swallow the message meant
for its neighbour.

**That key is the reader's, not the checkout's, wherever the runtime names a session.** What
a reader has been told is a fact about that reader, so one shared key is answered by
whoever looks first — including the session that moved HEAD, which then consumes the only
message its neighbour would ever get. Measured: `task start T-1` followed by `task current`
in the same session took the message for itself and left the neighbour's `jig status`
silent. Each named session therefore keeps its own `branch_reported`, one file per session,
so two sessions never rewrite each other's answer. A session that switched the branch itself
still gets one true line — the noise this decision accepts; what it can no longer do is eat
somebody else's. Without a session id the key stays shared, and the message still goes to
whoever looks first: another place where the identifier sharpens the mechanism rather than
switching it on. The message names the way out, because the obvious move is the wrong
one: switching the branch back pulls the tree from under the session that just started
work on it. The right move is to give that task a worktree of its own.

**`task start` refuses a checkout where other work is live.** It reads `working/`,
ignoring two names — the task it is about to start, and this session's own id — and when a
fresh record remains it refuses with the other road named, the same shape as the
dirty-tree refusal: start this task in its own worktree. There is no `--force` and no
`--here`: ADR-0029 records that the dirty-tree refusal "was overridden with `--force`
every time".

> **That refusal is decided here and built in a successor task.** Said plainly, because the
> alternative is a reader looking for it in `task_start` and concluding the decision was
> never implemented. `scripts/lib/task.sh` is held by another branch that changes
> `task_start` itself, with six tasks queued behind it, and the two halves of this decision
> are separable: the observing half answers "is this checkout busy", which is worth having
> before and regardless of whether anything refuses on the answer. What remains is one
> condition in `task_start`, reading `jig_checkout_busy <id-being-started>` — which already
> excludes the task being started, this session's own id, expired records, work that lives
> in another worktree and leftover temporaries — and refusing with the worktree named. No
> other part of this decision waits on it, and the reading side ships without it: until then
> the record is reported by `jig status` and nothing refuses.

**A record's freshness window is `checkout.busy_ttl`, 12 hours by default**, read through
the one duration grammar the framework already has (`jig_duration_seconds`); an
unparseable value leaves the default standing rather than taking the command down. Long on
purpose: a stale record costs one worktree nobody needed, a missed one costs another
session's HEAD. A live session refreshes its own record with every jig command, so a
generous window does not keep a finished session alive. The key belongs to the local layer
(ADR-0038) — it governs gitignored state on one machine — and it is a key with a working
default, never one a person must fill.

**The session id is an optional fourth name, behind the adapter contract.**
`adapter_<name>_session_id` prints the runtime's id for the session running this command,
or exits 2 for "not applicable to this runtime", the same code the session hook hint uses
(ADR-0024). Claude Code answers from `CLAUDE_CODE_SESSION_ID`, measured in the shape jig
actually runs in — a `bash -c` subprocess: a 36-character UUID, stable across separate
commands of one session, **inherited by subagents**, and absent under `env -i`. The
inheritance is what makes delegation safe: a session and the agents it spawns are one
occupant, not four, so the refusal never fires on a session's own helpers. Codex exits 2
and the boundary is named rather than guessed: Codex does have session ids
(`~/.codex/sessions/…/rollout-<time>-<uuid>.jsonl`), but its `config.toml` carries
`[shell_environment_policy.set]`, so whether an id reaches the environment of a command it
runs could not be established here. It is one line in one adapter whenever someone
verifies it. The id is compared only with names of files jig wrote itself: never shown,
never sent anywhere, never stored beyond its own file name.

**The directory is per checkout, not one shared directory per repository.** A worktree can
reach the main checkout with git alone, so this is a choice on the merits. It is settled by
ADR-0029's own rule, written about exactly this: where a task's branch is checked out is
read from git, **never from another checkout's `.ai/`**. A shared directory would be a
second exception to ADR-0008 on top of the single named one, and an exception for
*writing*.

**Nothing is deleted.** An expired record is ignored, not removed. RULES.md lets a script
delete only a path it has checked to be inside `.ai/` and shaped like a workspace or a
trash entry, and a file under `runtime/working/` is neither. Cleaning up after it is a
decision of its own, with its own line in that document.

## Alternatives

- **Prose in the `jig-task` skill.** Rejected: it fails all three tests of
  `conventions/required-records.md`, and an agent that obeys it answers "free" correctly.
  The skill's §3 changes as a consequence of this decision, not as a substitute for it.
- **Heuristic: refuse when the repository has any task worktree.** The data is already in
  hand and costs nothing. Rejected as a ground for refusal because it is true every day
  out of eleven — in this repository it is not a filter but a constant, which is "always
  work in a worktree" written in another syntax. It also answers the wrong question: seven
  worktrees mean seven sessions left *here*, so a busy repository is weak evidence that
  this checkout is occupied.
- **`--worktree` by default.** Not reopened: until a worktree bootstraps itself, a fresh
  worktree in a project with an install step is a broken tree.
- **A fixed record name for read-only commands**, so a task-less coordinator leaves a trace
  too. Rejected: a reader's trace is indistinguishable from the trace of a session that is
  about to start a task, because `jig-task` §1 has a starting session run exactly the
  commands a coordinator runs. Under one shared name `task start` would refuse *always*,
  which is the rejected default-worktree option arriving through the back door. A fixed
  name does not create a fact; it creates noise shaped like one.
- **The session declares itself (`jig checkout hold`).** It passes the convention's test
  well — written by someone it does not bind. Rejected by a RULES.md invariant: routine
  maintenance never depends on a developer remembering to run it. A forgotten `hold` is
  today's silence. This decision is that proposal with the machine doing the remembering.
- **A session id from the process tree** (walking `ppid` with `ps`). Rejected: `ps` is not
  in ADR-0002's "git only", it behaves differently in Git Bash on Windows, and each Bash
  tool call may start a new shell, so "stable ancestor" is undefined.
- **One shared directory per repository**, so `jig status` in any tree sees the whole
  picture. Rejected on four counts: it contradicts ADR-0029's rule above; it does not
  replace the per-checkout directory but adds to it, since a worktree of a bare repository
  has no main working tree at all and would need the per-checkout fallback anyway; an
  expired record would stop being one checkout's ghost and become a lying line in every
  checkout's `jig status`; and nobody owns the cleanup, because records in another
  checkout outlive the worktree's removal. What it was wanted for — the task-to-worktree
  map — `jig status` already computes from git. If cross-checkout freshness is ever needed,
  the cheap move is to let `jig status` *read* the neighbours' `working/` through the paths
  in `git worktree list`: still an exception, but on reading, with no writers in another
  checkout and no question of cleanup.

## Consequences

- One boundary stays open, and is named rather than papered over: a neighbour with no
  branch of its own, naming no task in its arguments, in a runtime that gives no session
  id, is invisible, and its HEAD moves silently. It gets the moved-HEAD message on its
  next orienting command, which has no false positives at all and arrives within seconds
  for a session that runs jig constantly.
- The moved-HEAD message names a move that has no command yet: taking an already started
  task into a worktree. `jig task start --worktree` on a started task fails earlier and
  with a different text, and the manual route has four steps, the last of which is freeing
  the branch in this checkout — the very move the message warns against. Until
  `jig task move --worktree` exists, the message names the move in words.
- A false refusal — a record that outlived a dead session — costs one worktree that nobody
  needed; housekeeping removes it under the ordinary rules. A miss costs what has already
  happened twice. The refusal leans towards the false one deliberately, which is why the
  window is long.
- `jig status` gains a line per other live record in this checkout, and prints none when
  there is no other work. A record named by a session id is shown as "another session":
  the id means nothing to a person, and the fact they need is that somebody else is here.
- Every jig command now writes two small files in `.ai/runtime/`. Nothing is committed
  (RULES.md), sizes are constant because records are rewritten rather than appended, and
  the number of files is bounded by the number of tasks plus two per named session — its
  work record and the branch it was last told about.
- **Reading a directory of records costs two processes, not two per record.** Nothing here
  deletes an expired record, so the directory only grows, and a `stat` plus a fork for each
  file is the process-per-item shape `conventions/shell.md` forbids: `jig status` measured
  1.77 s of CPU with one record against 8.46 s with 500. One `stat` answers the whole
  directory and the record's one line is read without a subshell, so what a grown directory
  costs is now proportional to what is reported, not to what is stored.
- **The session id reaches as far as the adapters do, and where it does not, the report
  says so.** Adapters are not copied into `.ai/`, so the lookup finds them where init and
  upgrade do: the framework source the manifest records, and failing that the framework
  checkout this jig is running from, which is what a global install is. What is left
  uncovered is a copy install driven through `.ai/scripts/jig` whose source is not on this
  machine. There, rule 3 goes quiet and the naming falls back to the rules above it —
  silently, which was the worse half: a reader cannot tell "nobody else is here" from "there
  is no way to see anybody". `jig status` now prints `sessions: not observable (<why>)`,
  keeping the two reasons apart, because a runtime that does not name its sessions is a
  named boundary while an install that cannot reach its adapters is a gap. Closing that gap
  means installing adapters into the project, which is an install-surface decision of its
  own (ADR-0003, ADR-0024), not a detail of this one.
- **"This command changes nothing under `.ai/`" is no longer true, and the narrower claim
  replaces it: a command changes nothing *about the project*.** `spec remove --dry-run` is
  tested by comparing the whole `.ai/` tree before and after, and it now differs by the two
  records — as does every other command, `jig status` included. This is a consequence of the
  decision, not a test that needed fixing: `.ai/runtime/` is where a read-only command may
  write, as `scripts/lib/status.sh` already declares for the status page and its cached
  counts. The comparison now excludes exactly those two paths and still covers the spec, the
  workspaces and the trash a dry run must not move anything into. Anything that wants the old
  claim has to name the two records; nothing else about the invariant is intact.
- **A record about what is happening *here* may not take "here" from the environment.** The
  recorder resolved the checkout by reusing an inherited `JIG_PROJECT` when one was set, and
  a jig command run under another jig inherits it: the test suite launched by `jig verify`
  wrote every record into the repository being verified instead of each test's own tree, and
  was caught because this repository's `.ai/runtime/told/` filled up with session ids that
  only ever existed inside tests. The root is computed now, as `jig_require_repo` computes
  it, at the cost of one `git` call. This is the same failure as the row below, one layer
  down — a component written to describe its own surroundings must not inherit the answer —
  and it is why the two are recorded together rather than as one bug each.
- **A test runner must clear the runtime's own environment variables, or its tests measure
  the machine they run on.** The session id is read from the environment, so a suite run
  inside an agent session wrote records a CI run would not, and three tests passed or failed
  depending on who started them. `tests/run.sh` now unsets `CLAUDE_CODE_SESSION_ID` beside
  the scope variables it already unsets; a test that wants one sets it itself. This is the
  `run_no_tools` failure again — a helper written to remove environment dependence must not
  inherit any (conventions/shell.md) — and it is the standing cost of reading the
  environment at all: every future adapter capability that does so owes the runner the same
  line.
- **One part of the approved design is deliberately not built: the session hook does not
  write a record when a session starts.** The design had it as a layer on top, so that a
  session's very first command was already covered. Two facts took the value out of it. The
  dispatcher covers a session from its first jig command, so the only window the hook adds
  is one in which the session has not yet read or written anything in the checkout — there
  is nothing there to protect, and the incident this decision answers was a session losing
  HEAD after working for a while. And the cost lands on every session start, which is
  precisely why the hook is opt-in (ADR-0024) and why its idle path is written to touch no
  git at all. A hook that ran jig on every start to record a session that has done nothing
  would spend that budget on the emptiest case. Said here rather than left as a gap between
  the design and the code, because silently diverging from an approved design is how the
  next reader is made to guess which one is true.
- Rolling back is `git revert` plus an amendment: no existing file changes format, and no
  command changes its output when the recorder is removed.
